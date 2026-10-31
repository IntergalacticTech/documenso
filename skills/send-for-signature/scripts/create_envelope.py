#!/usr/bin/env python3
"""Create a draft signing envelope in Documenso from a PDF and a field plan.

Usage:
  create_envelope.py document.pdf plan.json            # create a draft, print its edit link
  create_envelope.py --send ENVELOPE_ID                # send a draft that was reviewed

Environment:
  DOCUMENSO_API_TOKEN  required; Settings > API Tokens in the VictoryCTO team
  DOCUMENSO_URL        default https://signature.victorycto.com
  DOCUMENSO_TEAM_URL   default victorycto (only used to build the edit link)

plan.json:
{
  "title": "Consulting Agreement - Acme",
  "sequential": true,
  "subject": "Please sign: Consulting Agreement",          (optional)
  "message": "Hi, please review and sign.",                (optional)
  "recipients": [
    {"key": "client", "name": "Jane Doe", "email": "jane@acme.com", "role": "SIGNER", "signingOrder": 1},
    {"key": "vcto", "name": "J. Smith", "email": "j@victorycto.com", "role": "SIGNER", "signingOrder": 2}
  ],
  "fields": [
    {"recipient": "client", "type": "SIGNATURE", "page": 3,
     "positionX": 12.1, "positionY": 70.4, "width": 22, "height": 5},
    {"recipient": "client", "type": "TEXT", "label": "Title", "page": 3,
     "positionX": 12.1, "positionY": 78.0, "width": 22, "height": 2.8, "required": true}
  ]
}
Positions and sizes are percentages of the page, measured from the top-left corner.
"""

import json
import os
import sys
import urllib.error
import urllib.request
import uuid

FIELD_TYPES = {"SIGNATURE", "INITIALS", "NAME", "EMAIL", "DATE", "TEXT", "NUMBER", "CHECKBOX"}
ROLES = {"SIGNER", "APPROVER", "VIEWER", "CC", "ASSISTANT"}


def config():
    token = os.environ.get("DOCUMENSO_API_TOKEN")
    if not token:
        sys.exit("DOCUMENSO_API_TOKEN is not set. Create one under Settings > API Tokens in Documenso.")
    base = os.environ.get("DOCUMENSO_URL", "https://signature.victorycto.com").rstrip("/")
    team = os.environ.get("DOCUMENSO_TEAM_URL", "victorycto")
    return token, base, team


def request(method, url, token, body=None, content_type="application/json"):
    req = urllib.request.Request(url, data=body, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    if body is not None:
        req.add_header("Content-Type", content_type)
    try:
        with urllib.request.urlopen(req, timeout=120) as res:
            return json.loads(res.read() or b"{}")
    except urllib.error.HTTPError as err:
        sys.exit(f"Documenso API {method} {url} failed ({err.code}): {err.read().decode(errors='replace')}")


def field_meta(field):
    field_type = field["type"]
    base = {"type": field_type.lower(), "required": field.get("required", True)}
    if field.get("label"):
        base["label"] = field["label"]
    if field_type == "CHECKBOX":
        base["values"] = [{"id": 1, "checked": False, "value": field.get("label", "")}]
    return base


def validate(plan):
    errors = []
    keys = {r.get("key") for r in plan.get("recipients", [])}
    if not plan.get("title"):
        errors.append("title is required")
    if not plan.get("recipients"):
        errors.append("at least one recipient is required")
    for r in plan.get("recipients", []):
        if not r.get("email") or "@" not in r["email"]:
            errors.append(f"recipient {r.get('key')!r} needs a valid email")
        if r.get("role", "SIGNER") not in ROLES:
            errors.append(f"recipient {r.get('key')!r} has unknown role {r.get('role')!r}")
    signers = {r["key"] for r in plan.get("recipients", []) if r.get("role", "SIGNER") == "SIGNER"}
    for i, f in enumerate(plan.get("fields", [])):
        if f.get("recipient") not in keys:
            errors.append(f"field {i} points at unknown recipient {f.get('recipient')!r}")
        if f.get("type") not in FIELD_TYPES:
            errors.append(f"field {i} has unknown type {f.get('type')!r}")
        for k in ("positionX", "positionY", "width", "height"):
            if not 0 <= float(f.get(k, -1)) <= 100:
                errors.append(f"field {i} {k} must be a percentage between 0 and 100")
        if float(f.get("positionX", 0)) + float(f.get("width", 0)) > 100:
            errors.append(f"field {i} runs off the right edge of the page")
    for key in signers:
        if not any(f.get("recipient") == key and f.get("type") == "SIGNATURE" for f in plan.get("fields", [])):
            errors.append(f"signer {key!r} has no SIGNATURE field")
    if errors:
        sys.exit("Plan is invalid:\n  - " + "\n  - ".join(errors))


def build_payload(plan, filename):
    recipients = []
    for order, r in enumerate(plan["recipients"], start=1):
        fields = [
            {
                "type": f["type"],
                "identifier": filename,
                "page": int(f["page"]),
                "positionX": float(f["positionX"]),
                "positionY": float(f["positionY"]),
                "width": float(f["width"]),
                "height": float(f["height"]),
                "fieldMeta": field_meta(f),
            }
            for f in plan.get("fields", [])
            if f["recipient"] == r["key"]
        ]
        recipients.append({
            "name": r.get("name", ""),
            "email": r["email"],
            "role": r.get("role", "SIGNER"),
            "signingOrder": int(r.get("signingOrder", order)),
            "fields": fields,
        })

    meta = {"signingOrder": "SEQUENTIAL" if plan.get("sequential", True) else "PARALLEL"}
    for key in ("subject", "message"):
        if plan.get(key):
            meta[key] = plan[key]

    return {"title": plan["title"], "type": "DOCUMENT", "recipients": recipients, "meta": meta}


def multipart(payload, pdf_path, filename):
    boundary = uuid.uuid4().hex
    with open(pdf_path, "rb") as fh:
        pdf = fh.read()
    parts = [
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"payload\"\r\n\r\n".encode(),
        json.dumps(payload).encode(),
        f"\r\n--{boundary}\r\nContent-Disposition: form-data; name=\"files\"; filename=\"{filename}\"\r\n"
        "Content-Type: application/pdf\r\n\r\n".encode(),
        pdf,
        f"\r\n--{boundary}--\r\n".encode(),
    ]
    return b"".join(parts), f"multipart/form-data; boundary={boundary}"


def create(pdf_path, plan_path):
    token, base, team = config()
    with open(plan_path) as fh:
        plan = json.load(fh)
    validate(plan)

    filename = os.path.basename(pdf_path)
    body, content_type = multipart(build_payload(plan, filename), pdf_path, filename)
    envelope = request("POST", f"{base}/api/v2/envelope/create", token, body, content_type)

    print(json.dumps({
        "envelopeId": envelope["id"],
        "status": "DRAFT",
        "editUrl": f"{base}/t/{team}/documents/{envelope['id']}/edit",
    }, indent=2))


def send(envelope_id):
    token, base, _ = config()
    result = request("POST", f"{base}/api/v2/envelope/distribute", token,
                     json.dumps({"envelopeId": envelope_id}).encode())
    print(json.dumps({"envelopeId": envelope_id, "sent": True, "result": result}, indent=2))


def main():
    args = sys.argv[1:]
    if len(args) == 2 and args[0] == "--send":
        send(args[1])
    elif len(args) == 2:
        create(*args)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()

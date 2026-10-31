---
name: send-for-signature
description: Turn a Google Doc (or PDF) into a ready-to-send e-signature envelope on signature.victorycto.com. Use when someone asks to send a document for signature, get a contract/agreement/NDA/SOW signed, prepare a doc for signing, or set up signers and signing order. Detects where signatures, initials, dates, names and other fill-ins belong, assigns them to recipients, creates a draft in Documenso, and only sends after explicit confirmation.
---

# Send a document for signature

Creates a **draft** envelope in VictoryCTO's signing service (Documenso at
`https://signature.victorycto.com`) with recipients, signing order and every
field placed. The person reviews it, then you send it only when they say so.

Scripts live in `scripts/` next to this file. They need Python 3 with
`pdfplumber`, `pypdfium2` and `Pillow`, plus network access to
`signature.victorycto.com`.

## 1. Get the document as a PDF

Field positions come from the PDF, so the PDF must be the exact file that gets signed.

1. If the person attached a PDF, use it.
2. If they gave a Google Docs link, export it as PDF with whatever Google Drive
   tool is available (export/download with mime type `application/pdf`).
3. If no Drive tool can export, try
   `https://docs.google.com/document/d/<DOC_ID>/export?format=pdf` (works only for
   docs shared as "anyone with the link").
4. Otherwise ask them to use **File → Download → PDF document** in Google Docs
   and attach the file. Don't recreate the document from its text: layout and
   page breaks would change.

Use the Google Doc's title as the envelope title unless they give another.

## 2. Find what needs filling in

```bash
python3 scripts/detect_fields.py document.pdf --render-dir pages
```

This prints candidate fields (`page`, `type`, `label`, `context`, and a box as
percentages of the page from the top-left) and renders `pages/page-N.png`.

The detector is a starting point, not the answer. **Look at every page image**
and the document text yourself:

- Drop false positives, e.g. underscores that are part of the prose or a
  "Date" that is already filled in.
- Add anything it missed: signature blocks with no underline, "[Client to
  complete]" notes, checkboxes, a fee or start date left blank. Estimate those
  boxes from the page image (x and y as % of width and height from the top-left).
- Fix types. The detector guesses from nearby words: SIGNATURE, INITIALS, DATE,
  NAME, EMAIL, TEXT, NUMBER, CHECKBOX. DATE fields are auto-filled with the
  signing date, and NAME/EMAIL with the signer's details; use TEXT for anything
  the signer must type, such as title, company or address.
- An "Initials" line repeated on every page means one INITIALS field per page.

## 3. Work out who signs, and in what order

From the document (party names, signature block headings such as "Client" and
"VictoryCTO") and what the person told you, decide the recipients:

- `name`, `email` (ask for any email you can't find; never guess one)
- `role`: `SIGNER` (signs/fills), `APPROVER` (approves, no fields), `VIEWER`,
  or `CC` (gets the final copy)
- `signingOrder`: 1, 2, 3… Default is **sequential**: the counterparty signs
  first and VictoryCTO countersigns last, unless the person says otherwise or
  the document implies another order. Set `"sequential": false` only if they ask
  for everyone to sign at once.

Assign every field to exactly one recipient. Each SIGNER needs at least one
SIGNATURE field. Fields belong to whoever's block they sit in.

## 4. Write the plan and check placement

Write `plan.json` (the full format is in the docstring at the top of
`scripts/create_envelope.py`):

```json
{
  "title": "Consulting Agreement - Acme",
  "sequential": true,
  "subject": "Please sign: Consulting Agreement",
  "message": "Hi Jane, please review and sign the attached agreement.",
  "recipients": [
    {"key": "client", "name": "Jane Doe", "email": "jane@acme.com", "role": "SIGNER", "signingOrder": 1},
    {"key": "vcto", "name": "Sam Lee", "email": "sam@victorycto.com", "role": "SIGNER", "signingOrder": 2}
  ],
  "fields": [
    {"recipient": "client", "type": "SIGNATURE", "page": 2, "positionX": 11.8, "positionY": 16.5, "width": 25, "height": 5},
    {"recipient": "client", "type": "TEXT", "label": "Title", "page": 2, "positionX": 11.8, "positionY": 31.3, "width": 25, "height": 2.8}
  ]
}
```

Then render the plan over the pages and **look at the images**:

```bash
python3 scripts/preview_fields.py document.pdf plan.json preview
```

Each recipient has its own colour. Boxes should sit on their line or blank
without covering printed text, and every box must be in the right person's
block. Adjust and re-render until it's right.

## 5. Create the draft

The script needs the person's Documenso API token in `DOCUMENSO_API_TOKEN`.
They create one at **signature.victorycto.com → Settings → API Tokens** in the
VictoryCTO team. If it isn't set, ask them for it, pass it only as an
environment variable on the command, and never write it to a file or repeat it.

```bash
DOCUMENSO_API_TOKEN=... python3 scripts/create_envelope.py document.pdf plan.json
```

It validates the plan, uploads the PDF, and prints the `envelopeId` and an
`editUrl`.

## 6. Hand it over for review, then send only on confirmation

Show the person a short summary:

- the title and signing order, with each recipient's name, email, role and number of fields
- anything you were unsure about (guessed field types, a box you placed by eye)
- the `editUrl`, where they can open the draft and drag fields if needed

Ask whether to send it. **Do not send unless they explicitly confirm**; a
draft is the default deliverable. When they confirm:

```bash
DOCUMENSO_API_TOKEN=... python3 scripts/create_envelope.py --send <envelopeId>
```

With sequential signing, only the first signer is emailed; each later signer is
emailed when the previous one finishes.

## Troubleshooting

- **401/403**: the token is wrong, expired, or belongs to another team; create a new one.
- **Network error reaching signature.victorycto.com**: in Claude.ai, an org admin
  must allow that domain for code execution.
- **400 with a validation message**: usually a box past the page edge (x + width
  over 100) or an unknown field type; fix the plan and retry. Nothing was created.

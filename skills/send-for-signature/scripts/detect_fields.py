#!/usr/bin/env python3
"""Find places in a PDF where someone needs to sign or fill something in.

Prints JSON candidates with page numbers and boxes as percentages of the page
(top-left origin), which is the coordinate system the Documenso API uses.
Candidates are suggestions: the caller decides which are real, which recipient
each belongs to, and drops duplicates.

Usage: detect_fields.py document.pdf [--render-dir DIR]
  --render-dir  also writes page-N.png images so the pages can be checked visually.
"""

import argparse
import json
import re
import sys

import pdfplumber

# Ordered: the first label pattern that matches decides the suggested field type.
LABEL_PATTERNS = [
    ("INITIALS", re.compile(r"\binitials?\b", re.I)),
    ("SIGNATURE", re.compile(r"\b(signature|signed|sign here|signatory|by:)", re.I)),
    ("DATE", re.compile(r"\bdate[d]?\b", re.I)),
    ("EMAIL", re.compile(r"\be-?mail\b", re.I)),
    ("NAME", re.compile(r"\b(print(ed)? name|full name|name)\b", re.I)),
    ("TEXT", re.compile(r"\b(title|company|address|phone|position|role)\b", re.I)),
]

PLACEHOLDER_RE = re.compile(r"(_{4,}|\.{6,}|\[\s*\]|\[\s*(sign|signature|date|name)[^\]]*\]|\{\{[^}]+\}\})", re.I)
CHECKBOX_CHARS = {"☐", "□", "❏", "▢"}

# Field sizes as a percentage of the page, roughly matching Documenso's defaults.
DEFAULT_SIZE = {
    "SIGNATURE": (22.0, 5.0),
    "INITIALS": (8.0, 4.0),
    "DATE": (14.0, 2.8),
    "NAME": (22.0, 2.8),
    "EMAIL": (22.0, 2.8),
    "TEXT": (22.0, 2.8),
    "CHECKBOX": (2.2, 1.8),
}


def classify(text):
    for field_type, pattern in LABEL_PATTERNS:
        if pattern.search(text):
            return field_type
    return "TEXT"


def pct(value, total):
    return round(max(0.0, min(100.0, value / total * 100)), 2)


def group_lines(words, tolerance=3):
    lines = []
    for word in sorted(words, key=lambda w: (round(w["top"]), w["x0"])):
        if lines and abs(lines[-1][-1]["top"] - word["top"]) <= tolerance:
            lines[-1].append(word)
        else:
            lines.append([word])
    return [sorted(line, key=lambda w: w["x0"]) for line in lines]


def preceding_words(line, index, max_gap=18):
    """Words directly left of line[index], stopping at a column-sized gap."""
    words = []
    right_edge = line[index]["x0"]
    for word in reversed(line[:index]):
        if right_edge - word["x1"] > max_gap:
            break
        words.insert(0, word)
        right_edge = word["x0"]
    return words


def box_for(field_type, x0, bottom, page, width_pt=None):
    w_pct, h_pct = DEFAULT_SIZE[field_type]
    if width_pt:
        w_pct = max(w_pct * 0.6, min(pct(width_pt, page.width), 45.0))
    h_pt = h_pct / 100 * page.height
    return {
        "positionX": pct(x0, page.width),
        "positionY": pct(bottom - h_pt, page.height),
        "width": round(w_pct, 2),
        "height": h_pct,
    }


def detect(pdf_path):
    candidates = []

    with pdfplumber.open(pdf_path) as pdf:
        for page_number, page in enumerate(pdf.pages, start=1):
            words = page.extract_words(keep_blank_chars=False, use_text_flow=True)
            lines = group_lines(words)

            for line in lines:
                line_text = " ".join(w["text"] for w in line)

                for index, word in enumerate(line):
                    if word["text"] in CHECKBOX_CHARS:
                        label = " ".join(w["text"] for w in line[index + 1 : index + 8])
                        candidates.append({
                            "page": page_number,
                            "type": "CHECKBOX",
                            "label": label.strip(),
                            "context": line_text,
                            **box_for("CHECKBOX", word["x0"], word["bottom"], page),
                        })
                        continue

                    if not PLACEHOLDER_RE.search(word["text"]):
                        continue

                    label = " ".join(w["text"] for w in preceding_words(line, index)).strip()
                    candidates.append({
                        "page": page_number,
                        "type": classify(label or line_text),
                        "label": label,
                        "context": line_text,
                        **box_for(classify(label or line_text), word["x0"], word["bottom"], page,
                                  width_pt=word["x1"] - word["x0"]),
                    })

            # Signature lines are often drawn rules rather than underscores.
            for rule in page.lines + [r for r in page.rects if r["height"] < 1.5]:
                width = rule["x1"] - rule["x0"]
                if width < page.width * 0.12:
                    continue
                rule_bottom = rule.get("bottom", rule["top"])
                nearby = [
                    w for w in words
                    if (-4 <= rule_bottom - w["bottom"] <= 30 and w["x1"] <= rule["x0"] + 5)
                    or (0 <= w["top"] - rule_bottom <= 16 and rule["x0"] - 5 <= w["x0"] <= rule["x1"])
                ]
                label = " ".join(w["text"] for w in sorted(nearby, key=lambda w: (w["top"], w["x0"])))
                if not label:
                    continue
                field_type = classify(label)
                candidates.append({
                    "page": page_number,
                    "type": field_type,
                    "label": label,
                    "context": label,
                    **box_for(field_type, rule["x0"], rule_bottom, page, width_pt=width),
                })

    return dedupe(candidates)


def dedupe(candidates):
    kept = []
    for c in candidates:
        if any(
            k["page"] == c["page"]
            and abs(k["positionX"] - c["positionX"]) < 3
            and abs(k["positionY"] - c["positionY"]) < 2
            for k in kept
        ):
            continue
        kept.append(c)
    return kept


def render(pdf_path, out_dir):
    import os

    import pypdfium2

    os.makedirs(out_dir, exist_ok=True)
    doc = pypdfium2.PdfDocument(pdf_path)
    paths = []
    for i in range(len(doc)):
        path = os.path.join(out_dir, f"page-{i + 1}.png")
        doc[i].render(scale=1.5).to_pil().save(path)
        paths.append(path)
    return paths


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("pdf")
    parser.add_argument("--render-dir")
    args = parser.parse_args()

    with pdfplumber.open(args.pdf) as pdf:
        pages = [{"page": i + 1, "width": p.width, "height": p.height} for i, p in enumerate(pdf.pages)]

    result = {"pages": pages, "candidates": detect(args.pdf)}
    if args.render_dir:
        result["images"] = render(args.pdf, args.render_dir)

    json.dump(result, sys.stdout, indent=2)
    print()


if __name__ == "__main__":
    main()

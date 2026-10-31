#!/usr/bin/env python3
"""Draw a plan's fields onto the PDF pages so placement can be checked by eye.

Usage: preview_fields.py document.pdf plan.json OUT_DIR
Writes OUT_DIR/preview-page-N.png for every page that has fields, each box
labelled with its recipient key and field type.
"""

import json
import os
import sys

import pypdfium2
from PIL import ImageDraw

COLOURS = ["#e11d48", "#2563eb", "#16a34a", "#d97706", "#7c3aed", "#0891b2"]


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    pdf_path, plan_path, out_dir = sys.argv[1:]
    with open(plan_path) as fh:
        plan = json.load(fh)

    colour_for = {r["key"]: COLOURS[i % len(COLOURS)] for i, r in enumerate(plan["recipients"])}
    os.makedirs(out_dir, exist_ok=True)
    doc = pypdfium2.PdfDocument(pdf_path)

    for page_number in sorted({int(f["page"]) for f in plan.get("fields", [])}):
        image = doc[page_number - 1].render(scale=1.5).to_pil().convert("RGB")
        draw = ImageDraw.Draw(image)
        width, height = image.size
        for f in plan["fields"]:
            if int(f["page"]) != page_number:
                continue
            x0 = f["positionX"] / 100 * width
            y0 = f["positionY"] / 100 * height
            x1 = x0 + f["width"] / 100 * width
            y1 = y0 + f["height"] / 100 * height
            colour = colour_for.get(f["recipient"], "#000000")
            draw.rectangle([x0, y0, x1, y1], outline=colour, width=3)
            draw.text((x0 + 3, y0 + 2), f"{f['recipient']}:{f['type']}", fill=colour)
        path = os.path.join(out_dir, f"preview-page-{page_number}.png")
        image.save(path)
        print(path)


if __name__ == "__main__":
    main()

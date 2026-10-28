import re
from pathlib import Path

from docx import Document
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml.ns import qn
from docx.shared import Cm, Pt, RGBColor

ROOT = Path(r"E:\VRAIGC\docs\manual")
md = (ROOT / "output" / "aigc-redraw-guide.md").read_text(encoding="utf-8")
out = ROOT / "output" / "aigc-redraw-guide.docx"

doc = Document()
sec = doc.sections[0]
sec.top_margin = Cm(2.2)
sec.bottom_margin = Cm(2.2)
sec.left_margin = Cm(2.2)
sec.right_margin = Cm(2.2)

style = doc.styles["Normal"]
style.font.name = "Microsoft YaHei"
style.font.size = Pt(10.5)
style.element.rPr.rFonts.set(qn("w:eastAsia"), "Microsoft YaHei")

IMG = re.compile(r"^!\[图 (\d+-\d+) [^\]]*\]\(\.\./images/([^)]+)\)$")


def add_runs(par, text):
    for i, part in enumerate(text.split("**")):
        if not part:
            continue
        run = par.add_run(part.replace("`", ""))
        run.bold = i % 2 == 1


def add_para(text, style_name=None):
    par = doc.add_paragraph(style=style_name) if style_name else doc.add_paragraph()
    add_runs(par, text)
    par.paragraph_format.space_after = Pt(6)
    return par


first_h1 = True
lines = md.splitlines()
i = 0
while i < len(lines):
    line = lines[i].rstrip()
    if not line:
        i += 1
        continue
    if line == "---":
        i += 1
        continue

    m = IMG.match(line)
    if m:
        name, path = m.group(1), m.group(2)
        img_path = ROOT / "images" / path
        if path.endswith(".svg"):
            img_path = img_path.with_suffix(".png")
        par = doc.add_paragraph()
        par.alignment = WD_ALIGN_PARAGRAPH.CENTER
        par.paragraph_format.space_before = Pt(6)
        par.paragraph_format.space_after = Pt(2)
        par.add_run().add_picture(str(img_path), width=Cm(16))
        i += 1
        continue

    if line.startswith("**图 ") and "　" in line:
        par = doc.add_paragraph()
        par.paragraph_format.space_after = Pt(10)
        add_runs(par, line)
        for run in par.runs:
            run.font.size = Pt(9)
            run.font.color.rgb = RGBColor(0x47, 0x55, 0x69)
        i += 1
        continue

    if line.startswith("# "):
        if first_h1:
            par = doc.add_paragraph(style="Title")
            add_runs(par, line[2:])
            first_h1 = False
        else:
            doc.add_heading(line[2:], level=1)
        i += 1
        continue
    if line.startswith("## "):
        doc.add_heading(line[3:], level=2)
        i += 1
        continue
    if line.startswith("### "):
        doc.add_heading(line[4:], level=3)
        i += 1
        continue

    if line.startswith("- "):
        add_para(line[2:], "List Bullet")
        i += 1
        continue

    if re.match(r"^\d+\. ", line):
        par = doc.add_paragraph()
        par.paragraph_format.left_indent = Cm(0.6)
        add_runs(par, line)
        i += 1
        continue

    add_para(line)
    i += 1

doc.save(out)
print("saved", out, out.stat().st_size)

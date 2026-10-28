import json
import subprocess
import sys
from pathlib import Path

FFMPEG = r"E:\VRAIGC\vrstudio\bin\ffmpeg.exe"
FONT = "C\\:/Windows/Fonts/arialbd.ttf"


def badge_filters(x: int, y: int, n) -> list[str]:
    if n is None:
        return []
    bx = x - 11
    by = y - 11
    return [
        f"drawbox=x={bx}:y={by}:w=22:h=22:color=white@1:t=fill",
        f"drawbox=x={bx}:y={by}:w=22:h=22:color=0xE11D48@1:t=2",
        f"drawtext=fontfile='{FONT}':text='{n}':x={bx}+11-text_w/2:y={by}+11-text_h/2:fontsize=13:fontcolor=0xE11D48",
    ]


def build(spec: dict) -> str:
    clip = spec["clip"]
    parts = [f"crop={clip['width']}:{clip['height']}:{clip['x']}:{clip['y']}"]
    for m in spec["marks"]:
        x = m["x"] - clip["x"]
        y = m["y"] - clip["y"]
        if m.get("box"):
            parts.append(
                f"drawbox=x={x - 4}:y={y - 4}:w={m['w'] + 8}:h={m['h'] + 8}:color=0xE11D48@1:t=2"
            )
            bx, by = x - 16, y - 16
        else:
            bx, by = x - 12, y - 12
        if m.get("pos") == "bl":
            bx, by = x - 12, y + m["h"] + 12
        if m.get("pos") == "tr":
            bx, by = x + m["w"] + 12, y - 12
        if m.get("pos") == "br":
            bx, by = x + m["w"] - 23, y + m["h"] + 12
        parts.extend(badge_filters(bx, by, m.get("n")))
    return ",".join(parts)


def main() -> None:
    shot = Path(sys.argv[1])
    spec_path = Path(sys.argv[2])
    raw_out = Path(sys.argv[3])
    ann_out = Path(sys.argv[4])
    spec = json.loads(spec_path.read_text(encoding="utf-8"))
    clip = spec["clip"]
    base = f"crop={clip['width']}:{clip['height']}:{clip['x']}:{clip['y']}"
    subprocess.run(
        [FFMPEG, "-y", "-i", str(shot), "-vf", base, "-frames:v", "1", str(raw_out)],
        check=True, capture_output=True,
    )
    subprocess.run(
        [FFMPEG, "-y", "-i", str(shot), "-vf", build(spec), "-frames:v", "1", str(ann_out)],
        check=True, capture_output=True,
    )
    print("ok", raw_out, ann_out)


if __name__ == "__main__":
    main()

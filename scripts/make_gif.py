"""Turn the frames from `Mac_Renamer --snapshot` into docs/demo.gif.

    python3 scripts/make_gif.py docs/frames docs/demo.gif

Identical consecutive frames are merged (their durations add up) to keep the file small.
"""
import sys
from pathlib import Path

from PIL import Image

FRAME_MS = 110
WIDTH = 720


def main(frames_dir: str, out_path: str) -> None:
    paths = sorted(Path(frames_dir).glob("frame_*.png"))
    if not paths:
        sys.exit(f"no frames in {frames_dir}")

    frames, durations, last = [], [], None
    for p in paths:
        img = Image.open(p).convert("RGB")
        if img.width > WIDTH:
            img = img.resize((WIDTH, round(img.height * WIDTH / img.width)), Image.LANCZOS)
        raw = img.tobytes()
        if raw == last:
            durations[-1] += FRAME_MS
            continue
        last = raw
        frames.append(img)
        durations.append(FRAME_MS)

    # one shared palette keeps colours stable from frame to frame
    palette = frames[-1].quantize(colors=128, method=Image.Quantize.MEDIANCUT)
    quantized = [f.quantize(palette=palette, dither=Image.Dither.NONE) for f in frames]
    quantized[0].save(
        out_path,
        save_all=True,
        append_images=quantized[1:],
        duration=durations,
        loop=0,
        optimize=True,
        disposal=1,
    )
    print(f"{out_path}: {len(frames)} frames, {Path(out_path).stat().st_size // 1024} KB")


if __name__ == "__main__":
    main(*sys.argv[1:3])

#!/usr/bin/env python3
"""房子四種狀態去背，裁成同一個框（切換時不跳動），並由開門／關門的差異算出門的位置。"""
import json, os
from PIL import Image, ImageChops, ImageFilter
from cut_sheets import background_mask

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STATES = ["day-closed", "day-open", "night-closed", "night-open"]
SIZE = 336


def main():
    cuts, boxes = {}, []
    for state in STATES:
        img = Image.open(f"{ROOT}/design/codex/house-{state}.png").convert("RGB")
        mask = background_mask(img)
        soft = mask.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.7))
        cut = img.convert("RGBA")
        cut.putalpha(soft)
        cuts[state] = cut
        boxes.append(mask.getbbox())
    box = (min(b[0] for b in boxes), min(b[1] for b in boxes), max(b[2] for b in boxes), max(b[3] for b in boxes))
    width, height = box[2] - box[0], box[3] - box[1]
    scale = SIZE / max(width, height)
    size = (round(width * scale), round(height * scale))
    offset = ((SIZE - size[0]) // 2, SIZE - size[1])
    folder = f"{ROOT}/assets/house"
    os.makedirs(folder, exist_ok=True)
    for state, cut in cuts.items():
        canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        canvas.paste(cut.crop(box).resize(size, Image.LANCZOS), offset)
        canvas.save(f"{folder}/{state}.png")
    diff = ImageChops.difference(cuts["day-closed"].convert("L"), cuts["day-open"].convert("L")).crop(box)
    # 修圖會讓整張有細微差異；只看下半部，取變化最集中的那幾欄。
    lower = diff.crop((0, diff.height // 2, diff.width, diff.height)).point(lambda v: 1 if v > 90 else 0)
    px = lower.load()
    columns = [sum(px[x, y] for y in range(0, lower.height, 2)) for x in range(lower.width)]
    peak = max(columns)
    dense = [x for x, c in enumerate(columns) if c >= peak * 0.4]
    door_x = (offset[0] + (dense[0] + dense[-1]) / 2 * scale) / SIZE
    json.dump({"doorX": round(door_x, 3)}, open(f"{folder}/house.json", "w"))
    print("box", box, "door columns", dense[0], dense[-1], "doorX", round(door_x, 3))


if __name__ == "__main__":
    main()

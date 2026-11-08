#!/usr/bin/env python3
"""把 Codex 的三姿勢白底圖切開、去背，輸出到 assets/pet/<角色>/。"""
import os
from collections import deque
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
POSES = ["idle", "sleep", "alert"]
SIZE = 448


def background_mask(img, limit=238):
    """從邊緣往內找連通的近白像素，角色裡的白（眼白、卡片）不會被吃掉。"""
    w, h = img.size
    px = img.load()
    mask = Image.new("L", (w, h), 255)
    out = mask.load()
    queue = deque((x, y) for x in range(w) for y in (0, h - 1))
    queue.extend((x, y) for y in range(h) for x in (0, w - 1))
    while queue:
        x, y = queue.popleft()
        if not (0 <= x < w and 0 <= y < h) or out[x, y] == 0:
            continue
        if min(px[x, y][:3]) < limit:
            continue
        out[x, y] = 0
        queue.extend(((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))
    remove_enclosed_white(px, out, w, h)
    return mask


def remove_enclosed_white(px, out, w, h, limit=246, smallest=120):
    """尾巴圈住、雙腳中間這種被包起來的底色，邊緣洪水填不到，要另外清。"""
    seen = set()
    for sy in range(h):
        for sx in range(w):
            if (sx, sy) in seen or out[sx, sy] == 0 or min(px[sx, sy][:3]) < limit:
                continue
            region, queue = [], deque([(sx, sy)])
            seen.add((sx, sy))
            while queue:
                x, y = queue.popleft()
                region.append((x, y))
                for n in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if 0 <= n[0] < w and 0 <= n[1] < h and n not in seen and out[n] != 0 and min(px[n][:3]) >= limit:
                        seen.add(n)
                        queue.append(n)
            if len(region) >= smallest:
                for point in region:
                    out[point] = 0


def split_columns(mask, count=3):
    w, h = mask.size
    px = mask.load()
    filled = [sum(1 for y in range(0, h, 2) if px[x, y]) > 0 for x in range(w)]
    runs, start = [], None
    for x, on in enumerate(filled + [False]):
        if on and start is None:
            start = x
        elif not on and start is not None:
            runs.append((start, x))
            start = None
    while len(runs) > count:  # 小碎片併給最近的一段
        gaps = [runs[i + 1][0] - runs[i][1] for i in range(len(runs) - 1)]
        i = gaps.index(min(gaps))
        runs[i:i + 2] = [(runs[i][0], runs[i + 1][1])]
    assert len(runs) == count, runs
    return runs


def main():
    for name in ["tape", "speaker", "cat", "guitar", "trumpet", "drum", "piano", "sax", "cello"]:
        sheet = Image.open(f"{ROOT}/design/codex/{name}-sheet.png").convert("RGB")
        mask = background_mask(sheet)
        soft = mask.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.7))
        cut = sheet.convert("RGBA")
        cut.putalpha(soft)
        folder = f"{ROOT}/assets/pet/{name}"
        os.makedirs(folder, exist_ok=True)
        for pose, (a, b) in zip(POSES, split_columns(mask)):
            part = cut.crop((a, 0, b, sheet.height))
            part = part.crop(part.getchannel("A").getbbox())
            scale = SIZE / max(part.size)
            part = part.resize((round(part.width * scale), round(part.height * scale)), Image.LANCZOS)
            canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
            canvas.paste(part, ((SIZE - part.width) // 2, SIZE - part.height))  # 腳貼底
            canvas.save(f"{folder}/{pose}.png")
            print(name, pose, part.size)
        if not cut_step(name):
            cut_walk(name)


def cut_walk(name):
    """走路 4 格用同一個縮放、腳貼同一條線，播放時才不會忽大忽小。身高對齊站姿。"""
    path = f"{ROOT}/design/codex/{name}-walk.png"
    if not os.path.exists(path) or os.path.getsize(path) == 0:
        return
    sheet = Image.open(path).convert("RGB")
    mask = background_mask(sheet)
    soft = mask.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.7))
    cut = sheet.convert("RGBA")
    cut.putalpha(soft)
    parts = []
    for a, b in split_columns(mask, 4):
        part = cut.crop((a, 0, b, sheet.height))
        parts.append(part.crop(part.getchannel("A").getbbox()))
    idle = Image.open(f"{ROOT}/assets/pet/{name}/idle.png").getchannel("A").getbbox()
    scale = min((idle[3] - idle[1]) / max(p.height for p in parts), SIZE / max(p.width for p in parts))
    for i, part in enumerate(parts, 1):
        part = part.resize((round(part.width * scale), round(part.height * scale)), Image.LANCZOS)
        canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        canvas.paste(part, ((SIZE - part.width) // 2, SIZE - part.height), part)
        canvas.save(f"{ROOT}/assets/pet/{name}/walk{i}.png")
    print(name, "walk", [p.size for p in parts], "scale", round(scale, 3))


def cut_step(name):
    """走路循環：左腳（step-a）、併攏（step-pass）、右腳（step-b）、併攏。
    都是同一張底圖改出來的，裁同一個框才不會跳。沒有 step-pass 就只用左右兩格。"""
    def ok(path):
        return os.path.exists(path) and os.path.getsize(path) > 0
    a, b, p = (f"{ROOT}/design/codex/step/{name}-step-{x}.png" for x in ("a", "b", "pass"))
    if not (ok(a) and ok(b)):
        return False
    paths = [a, p, b] if ok(p) else [a, b]
    cuts, boxes = [], []
    for path in paths:
        img = Image.open(path).convert("RGB")
        mask = background_mask(img)
        soft = mask.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.7))
        cut = img.convert("RGBA")
        cut.putalpha(soft)
        cuts.append(cut)
        boxes.append(mask.getbbox())
    box = (min(b[0] for b in boxes), min(b[1] for b in boxes), max(b[2] for b in boxes), max(b[3] for b in boxes))
    idle = Image.open(f"{ROOT}/assets/pet/{name}/idle.png").getchannel("A").getbbox()
    width, height = box[2] - box[0], box[3] - box[1]
    scale = min((idle[3] - idle[1]) / max(b[3] - b[1] for b in boxes), SIZE / width)
    size = (round(width * scale), round(height * scale))
    for old in range(1, 5):
        path = f"{ROOT}/assets/pet/{name}/walk{old}.png"
        if os.path.exists(path):
            os.remove(path)
    order = cuts + [cuts[1]] if len(cuts) == 3 else cuts
    for i, cut in enumerate(order, 1):
        canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        canvas.paste(cut.crop(box).resize(size, Image.LANCZOS), ((SIZE - size[0]) // 2, SIZE - size[1]))
        canvas.save(f"{ROOT}/assets/pet/{name}/walk{i}.png")
    print(name, "step", boxes, "scale", round(scale, 3))
    return True


if __name__ == "__main__":
    main()

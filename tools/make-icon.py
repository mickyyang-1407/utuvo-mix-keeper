#!/usr/bin/env python3
"""App 圖示：暖米色圓角方塊上一隻 Claw'd。輸出 assets/AppIcon.icns。"""
import os, subprocess, tempfile
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def base(size=1024):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    inset, radius = int(size * 0.098), int(size * 0.18)   # 比照 macOS 圖示格線
    box = (inset, inset, size - inset, size - inset)
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((box[0], box[1] + 14, box[2], box[3] + 14), radius, fill=(60, 40, 30, 90))
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(18)))
    # 先畫兩色底（上牆、下地板），再用圓角遮罩裁成圖示形狀，角才不會露出直角。
    fill = Image.new("RGBA", (size, size), (247, 238, 224, 255))
    ImageDraw.Draw(fill).rectangle((0, int(size * 0.66), size, size), fill=(236, 214, 188, 255))
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius, fill=255)
    card = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    card.paste(fill, (0, 0), mask)
    img.alpha_composite(card)
    pet = Image.open(f"{ROOT}/assets/pet/clawd/idle.png").convert("RGBA")
    pet = pet.crop(pet.getchannel("A").getbbox())
    w = int(size * 0.66); h = int(pet.height * w / pet.width)
    pet = pet.resize((w, h), Image.LANCZOS)
    img.alpha_composite(pet, ((size - w) // 2, int(size * 0.70) - h))
    return img


def main():
    icon = base()
    with tempfile.TemporaryDirectory() as tmp:
        iconset = os.path.join(tmp, "AppIcon.iconset")
        os.mkdir(iconset)
        for pt in (16, 32, 128, 256, 512):
            for scale in (1, 2):
                px = pt * scale
                name = f"icon_{pt}x{pt}{'@2x' if scale == 2 else ''}.png"
                icon.resize((px, px), Image.LANCZOS).save(os.path.join(iconset, name))
        subprocess.run(["iconutil", "-c", "icns", iconset, "-o", f"{ROOT}/assets/AppIcon.icns"], check=True)
    icon.save(f"{ROOT}/design/app-icon-1024.png")
    print("ok", f"{ROOT}/assets/AppIcon.icns")


if __name__ == "__main__":
    main()

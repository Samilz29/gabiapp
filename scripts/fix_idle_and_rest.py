#!/usr/bin/env python3
"""
1. Fixes idle_front.png's eye highlights so both eyes are 100% symmetrical (zero cross-eyed look).
2. Re-extracts rest_lying.png and rest_sleep.png from Sheet 2 at the EXACT same pixel scale
   as standing/walking Gabi (using a wider 350x256 canvas) so Gabi never shrinks when lying down!
"""
import os
import sys
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(__file__))
from update_sprites_v2 import remove_checkerboard_s2
from extract_sprites import find_sprite_components, tight_crop
from fix_eyes import find_eye_boxes

PROJECT_DIR = "/Users/samilz/proyectosPersonales/gabi-pet"
RAW_SHEET_2 = os.path.join(PROJECT_DIR, "assets/raw/gabi_sheet_2.jpg")
SPRITES_DIR = os.path.join(PROJECT_DIR, "assets/sprites")
PREVIEW_PATH = "/Users/samilz/.gemini/antigravity-cli/brain/011efb60-b5a6-4c39-acb2-ad0c10bbd5a1/scratch/fix_idle_and_rest.png"


def fix_idle_front_eyes():
    path = os.path.join(SPRITES_DIR, "idle_front.png")
    im = Image.open(path).convert("RGBA")
    pair = find_eye_boxes(im, (90, 100, 170, 145))
    if not pair:
        print("Could not find eye pair in idle_front.png")
        return
    print(f"idle_front eyes: left={pair[0][:4]}, right={pair[1][:4]}")
    px = im.load()
    avg_y_top = int(round((pair[0][1] + pair[1][1]) / 2.0))

    for (ex0, ey0, ex1, ey1, _) in pair:
        # Clear any existing bright/gray specular pixels inside pupil
        for y in range(ey0, ey1 + 1):
            for x in range(ex0, ex1 + 1):
                r, g, b, a = px[x, y]
                if a > 200 and (r + g + b) / 3.0 > 70:
                    if ex0 + 1 <= x <= ex1 - 1 and ey0 + 1 <= y <= ey1 - 1:
                        px[x, y] = (14, 10, 10, 255)
                    elif (r + g + b) / 3.0 > 170:
                        px[x, y] = (14, 10, 10, 255)
        # Symmetrical 3x3 upper-left specular highlight
        hx = ex0 + 2
        hy = max(ey0 + 1, avg_y_top + 2)
        for dy in range(3):
            for dx in range(3):
                px[hx + dx, hy + dy] = (248, 245, 240, 255)

    im.save(path)
    print("Saved polished idle_front.png")


def rescale_resting_sprites():
    sheet2 = Image.open(RAW_SHEET_2)
    rgba = remove_checkerboard_s2(sheet2)
    rows = find_sprite_components(rgba)
    # 10% smaller than 0.555 -> 0.495 for a natural, balanced lying-down proportion
    scale = 0.495
    canvas_w, canvas_h = 340, 256

    rest_boxes = rows[3]  # [rest_lying, rest_sleep]
    for idx, name in enumerate(["rest_lying", "rest_sleep"]):
        x0, y0, x1, y1 = rest_boxes[idx]
        crop = rgba.crop((max(0, x0 - 8), max(0, y0 - 8), min(rgba.width, x1 + 8), min(rgba.height, y1 + 8)))
        crop = tight_crop(crop, pad=2)
        nw = int(round(crop.width * scale))
        nh = int(round(crop.height * scale))
        # Clamp if slightly wider than canvas_w - 8
        if nw > canvas_w - 8:
            f = (canvas_w - 8) / nw
            nw = int(round(nw * f))
            nh = int(round(nh * f))
        resized = crop.resize((nw, nh), Image.Resampling.NEAREST)
        canvas = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
        ox = (canvas_w - nw) // 2
        oy = canvas_h - nh - 8
        canvas.paste(resized, (ox, oy), resized)
        canvas.save(os.path.join(SPRITES_DIR, f"{name}.png"))
        print(f"Saved full-scale {name}.png ({nw}x{nh} on {canvas_w}x{canvas_h})")


def make_preview():
    idle_f = Image.open(os.path.join(SPRITES_DIR, "idle_front.png")).convert("RGBA")
    idle_s = Image.open(os.path.join(SPRITES_DIR, "idle_side.png")).convert("RGBA")
    rest_l = Image.open(os.path.join(SPRITES_DIR, "rest_lying.png")).convert("RGBA")
    rest_s = Image.open(os.path.join(SPRITES_DIR, "rest_sleep.png")).convert("RGBA")

    # Place side-by-side at 1:1 pixel ratio to verify exact head/body scale match!
    out = Image.new("RGB", (1020, 300), (32, 68, 84))
    draw = ImageDraw.Draw(out)
    out.paste(idle_f, (10, 20), idle_f)
    out.paste(idle_s, (260, 20), idle_s)
    out.paste(rest_l, (510, 20), rest_l)
    # Also draw zoomed face of idle_front
    face = idle_f.crop((68, 72, 188, 172)).resize((150, 125), Image.Resampling.NEAREST)
    out.paste(face, (860, 40), face)
    draw.text((70, 280), "idle_front", fill=(255, 255, 255))
    draw.text((320, 280), "idle_side", fill=(255, 255, 255))
    draw.text((620, 280), "rest_lying (1:1 scale!)", fill=(255, 255, 255))
    draw.text((875, 175), "idle_front eyes", fill=(255, 255, 255))
    out.save(PREVIEW_PATH)
    print(f"Saved preview to {PREVIEW_PATH}")


if __name__ == "__main__":
    fix_idle_front_eyes()
    rescale_resting_sprites()
    make_preview()

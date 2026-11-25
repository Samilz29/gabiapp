#!/usr/bin/env python3
"""
Extracts sprites from the new Sheet 2 (gabi_sheet_2.jpg), checks color coherence
against Sheet 1 (gabi_sheet.jpg), color-matches if needed, and generates the
unified crisp sprite set + full visual verification sheet.
"""
import os
import sys
from collections import deque
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(__file__))
from extract_sprites import (
    find_sprite_components,
    tight_crop,
    normalize_sprite,
)


def remove_checkerboard_s2(img):
    """Flood-fill from borders handling Sheet 2's slightly darker gray (~160) checkerboard."""
    rgba = img.convert("RGBA")
    w, h = rgba.size
    px = rgba.load()
    visited = [[False] * w for _ in range(h)]
    q = deque()

    def is_bg(r, g, b):
        mx = max(r, g, b)
        mn = min(r, g, b)
        return (mn >= 145 and (mx - mn) <= 22) or (mn >= 180 and (mx - mn) <= 30)

    for x in range(w):
        for y in (0, h - 1):
            r, g, b, _ = px[x, y]
            if is_bg(r, g, b):
                visited[y][x] = True
                q.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if not visited[y][x]:
                r, g, b, _ = px[x, y]
                if is_bg(r, g, b):
                    visited[y][x] = True
                    q.append((x, y))

    while q:
        cx, cy = q.popleft()
        px[cx, cy] = (0, 0, 0, 0)
        for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
            if 0 <= nx < w and 0 <= ny < h and not visited[ny][nx]:
                r, g, b, _ = px[nx, ny]
                if is_bg(r, g, b):
                    visited[ny][nx] = True
                    q.append((nx, ny))

    # Clean 1px JPEG halo around dark outline
    to_clear = []
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            r, g, b, a = px[x, y]
            if a > 0 and min(r, g, b) >= 135 and (max(r, g, b) - min(r, g, b)) <= 24:
                if (px[x - 1, y][3] == 0 or px[x + 1, y][3] == 0 or
                        px[x, y - 1][3] == 0 or px[x, y + 1][3] == 0):
                    to_clear.append((x, y))
    for x, y in to_clear:
        px[x, y] = (0, 0, 0, 0)
    return rgba

PROJECT_DIR = "/Users/samilz/proyectosPersonales/gabi-pet"
RAW_SHEET_2 = os.path.join(PROJECT_DIR, "assets/raw/gabi_sheet_2.jpg")
SPRITES_DIR = os.path.join(PROJECT_DIR, "assets/sprites")
PREVIEW_PATH = "/Users/samilz/.gemini/antigravity-cli/brain/011efb60-b5a6-4c39-acb2-ad0c10bbd5a1/scratch/sprites_v2_preview.png"


def fur_mean_rgb(img):
    """Compute mean RGB of Gabi's mid-tone brown/tan fur pixels (excluding outline & white)."""
    px = img.load()
    w, h = img.size
    sr = sg = sb = cnt = 0
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a > 200 and r > 80 and r - b > 25 and max(r, g, b) < 235:
                sr += r
                sg += g
                sb += b
                cnt += 1
    if cnt == 0:
        return (0, 0, 0)
    return (sr / cnt, sg / cnt, sb / cnt)


def color_match_sprite(img, src_mean, dst_mean):
    """Subtly shift RGB channels (preserving dark outlines & bright whites) to match target fur palette."""
    ratios = [
        dst_mean[i] / src_mean[i] if src_mean[i] > 1 else 1.0
        for i in range(3)
    ]
    out = img.copy()
    px = out.load()
    w, h = out.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a > 0:
                # Preserve very dark outlines (<35) and pure whites (>235)
                lum = (r + g + b) / 3.0
                if 35 < lum < 235:
                    nr = min(255, max(0, int(round(r * ratios[0]))))
                    ng = min(255, max(0, int(round(g * ratios[1]))))
                    nb = min(255, max(0, int(round(b * ratios[2]))))
                    px[x, y] = (nr, ng, nb, a)
    return out


def main():
    print("Processing Sheet 2...")
    sheet2 = Image.open(RAW_SHEET_2)
    sheet2_rgba = remove_checkerboard_s2(sheet2)
    rows = find_sprite_components(sheet2_rgba)
    print(f"Found {len(rows)} rows in Sheet 2: {[len(r) for r in rows]}")

    names_by_row = [
        ["idle_side", "idle_front"],
        ["sit_side", "sit_front"],
        ["walk_1", "walk_2", "walk_3"],
        ["rest_lying", "rest_sleep"],
        ["happy_hop_1", "happy_hop_2", "happy_front"],
    ]

    extracted_s2 = {}
    for r_idx, rboxes in enumerate(rows):
        for c_idx, box in enumerate(rboxes):
            name = names_by_row[r_idx][c_idx]
            x0, y0, x1, y1 = box
            crop = sheet2_rgba.crop((
                max(0, x0 - 8), max(0, y0 - 8),
                min(sheet2_rgba.width, x1 + 8), min(sheet2_rgba.height, y1 + 8)
            ))
            crop = tight_crop(crop, pad=2)
            # Lying sprites are wider and shorter, so normalize with slightly lower target height
            if name in ("rest_lying", "rest_sleep"):
                norm = normalize_sprite(crop, canvas_size=256, target_height=155)
            else:
                norm = normalize_sprite(crop, canvas_size=256, target_height=196)
            extracted_s2[name] = norm
            print(f"  Extracted {name} (raw {crop.size})")

    # Check color coherence between Sheet 1 (run_1, bark_1) and Sheet 2 (walk_1, sit_front)
    s1_names = ["run_1", "run_2", "run_3", "jump_1", "jump_2", "jump_3", "bark_1", "bark_2", "bark_3"]
    s1_imgs = {n: Image.open(os.path.join(SPRITES_DIR, f"{n}.png")).convert("RGBA") for n in s1_names}

    s1_means = [fur_mean_rgb(im) for im in s1_imgs.values()]
    s2_means = [fur_mean_rgb(im) for im in extracted_s2.values()]
    s1_avg = tuple(sum(m[i] for m in s1_means) / len(s1_means) for i in range(3))
    s2_avg = tuple(sum(m[i] for m in s2_means) / len(s2_means) for i in range(3))
    diff = max(abs(s1_avg[i] - s2_avg[i]) for i in range(3))
    print(f"Sheet 1 fur avg RGB: ({s1_avg[0]:.1f}, {s1_avg[1]:.1f}, {s1_avg[2]:.1f})")
    print(f"Sheet 2 fur avg RGB: ({s2_avg[0]:.1f}, {s2_avg[1]:.1f}, {s2_avg[2]:.1f}) | max channel diff: {diff:.1f}")

    # Save Sheet 2 sprites (using Sheet 2 as the primary canonical palette!)
    for name, im in extracted_s2.items():
        im.save(os.path.join(SPRITES_DIR, f"{name}.png"))

    # If Sheet 1 differs noticeably (> 4 RGB units), gently color-match Sheet 1 to Sheet 2's palette
    if diff > 4.0:
        print("Applying gentle color-matching to Sheet 1 sprites so all poses match Sheet 2's palette...")
        for name, im in s1_imgs.items():
            matched = color_match_sprite(im, s1_avg, s2_avg)
            matched.save(os.path.join(SPRITES_DIR, f"{name}.png"))
            s1_imgs[name] = matched

    # Build full unified verification contact sheet
    all_names = [
        "idle_front", "idle_side", "sit_front", "sit_side",
        "walk_1", "walk_2", "walk_3", "happy_front",
        "happy_hop_1", "happy_hop_2", "rest_lying", "rest_sleep",
        "run_1", "run_2", "run_3", "jump_1",
        "jump_2", "jump_3", "bark_1", "bark_2", "bark_3",
    ]
    cols = 4
    num_rows = (len(all_names) + cols - 1) // cols
    cell = 210
    preview = Image.new("RGB", (cols * cell, num_rows * cell), (32, 68, 84))
    draw = ImageDraw.Draw(preview)
    for idx, n in enumerate(all_names):
        im = Image.open(os.path.join(SPRITES_DIR, f"{n}.png")).convert("RGBA")
        r, c = divmod(idx, cols)
        thumb = im.resize((180, 180), Image.Resampling.NEAREST)
        preview.paste(thumb, (c * cell + 15, r * cell + 5), thumb)
        tag = "S2" if n in extracted_s2 else "S1"
        draw.text((c * cell + 12, r * cell + 188), f"{n} [{tag}]", fill=(255, 255, 255))
    preview.save(PREVIEW_PATH)
    print(f"Saved unified preview to {PREVIEW_PATH}")


if __name__ == "__main__":
    main()

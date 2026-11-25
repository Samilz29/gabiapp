#!/usr/bin/env python3
"""
Refines Gabi's eye specular highlights in front/3-quarter sprites so both eyes
have symmetrical, gentle upper-left shine (preventing any cross-eyed look).
"""
import os
from collections import deque
from PIL import Image, ImageDraw

SPRITES_DIR = "/Users/samilz/proyectosPersonales/gabi-pet/assets/sprites"
PREVIEW_PATH = "/Users/samilz/.gemini/antigravity-cli/brain/011efb60-b5a6-4c39-acb2-ad0c10bbd5a1/scratch/eyes_closeup_fixed.png"


def find_eye_boxes(im, search_box):
    """Find the two dark pupil clusters inside search_box = (x0, y0, x1, y1)."""
    px = im.load()
    x0, y0, x1, y1 = search_box
    dark = set()
    for y in range(y0, y1):
        for x in range(x0, x1):
            r, g, b, a = px[x, y]
            if a > 200 and max(r, g, b) < 42:
                dark.add((x, y))

    # Merge nearby dark pixels (within 2px so white highlight inside pupil doesn't split the eye)
    visited = set()
    clusters = []
    for pt in list(dark):
        if pt in visited:
            continue
        q = deque([pt])
        visited.add(pt)
        pts = []
        while q:
            cx, cy = q.popleft()
            pts.append((cx, cy))
            for dx in range(-4, 5):
                for dy in range(-4, 5):
                    np = (cx + dx, cy + dy)
                    if np in dark and np not in visited:
                        visited.add(np)
                        q.append(np)
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        w = max(xs) - min(xs) + 1
        h = max(ys) - min(ys) + 1
        if 6 <= w <= 22 and 6 <= h <= 22 and len(pts) >= 25:
            clusters.append((min(xs), min(ys), max(xs), max(ys), len(pts)))

    # Pick the two most eye-like clusters (similar Y, separated in X)
    clusters.sort(key=lambda c: c[4], reverse=True)
    best_pair = None
    for i in range(len(clusters)):
        for j in range(i + 1, len(clusters)):
            a, b = clusters[i], clusters[j]
            dy = abs((a[1] + a[3]) / 2 - (b[1] + b[3]) / 2)
            dx = abs((a[0] + a[2]) / 2 - (b[0] + b[2]) / 2)
            if dy <= 8 and 18 <= dx <= 52:
                best_pair = sorted([a, b], key=lambda c: c[0])
                break
        if best_pair:
            break
    return best_pair


def polish_eyes(name, search_box):
    path = os.path.join(SPRITES_DIR, f"{name}.png")
    im = Image.open(path).convert("RGBA")
    pair = find_eye_boxes(im, search_box)
    if not pair:
        print(f"  [skip] Could not locate eye pair for {name}")
        return
    print(f"  Polishing {name}: left={pair[0][:4]}, right={pair[1][:4]}")

    px = im.load()
    # Compute shared vertical highlight alignment across both eyes
    avg_y_top = int(round((pair[0][1] + pair[1][1]) / 2.0))

    for (ex0, ey0, ex1, ey1, _) in pair:
        # 1. Replace any existing bright specular pixels inside the eye box with deep glossy pupil dark
        for y in range(ey0, ey1 + 1):
            for x in range(ex0, ex1 + 1):
                r, g, b, a = px[x, y]
                if a > 200 and (r + g + b) / 3.0 > 75:
                    # Only replace if it's inside the pupil interior (not outer fur corners)
                    if ex0 + 1 <= x <= ex1 - 1 and ey0 + 1 <= y <= ey1 - 1:
                        px[x, y] = (14, 10, 10, 255)
                    elif (r + g + b) / 3.0 > 175:
                        px[x, y] = (14, 10, 10, 255)

        # 2. Place a crisp 3x3 pixel-art specular highlight in the upper-left of each pupil
        #    at the exact same Y height so both eyes look gently & symmetrically focused!
        hx = ex0 + 2
        hy = max(ey0 + 1, avg_y_top + 2)
        for dy in range(3):
            for dx in range(3):
                px[hx + dx, hy + dy] = (248, 245, 240, 255)

    im.save(path)


def main():
    targets = [
        ("sit_front", (90, 100, 165, 138)),
        ("happy_front", (90, 98, 165, 138)),
        ("walk_2", (115, 110, 190, 148)),
        ("sit_side", (135, 100, 200, 138)),
    ]
    for name, box in targets:
        polish_eyes(name, box)

    # Render before/after verification closeup
    names = ["idle_front", "sit_front", "sit_side", "happy_front", "walk_2", "rest_lying"]
    cols = 3
    cell = 220
    out = Image.new("RGB", (cols * cell, 2 * cell), (30, 50, 60))
    draw = ImageDraw.Draw(out)
    for i, n in enumerate(names):
        im = Image.open(os.path.join(SPRITES_DIR, f"{n}.png"))
        face = im.crop((64, 70, 192, 175)).resize((200, 165), Image.Resampling.NEAREST)
        r, c = divmod(i, cols)
        out.paste(face, (c * cell + 10, r * cell + 10), face)
        draw.text((c * cell + 10, r * cell + 185), n, fill=(255, 255, 255))
    out.save(PREVIEW_PATH)
    print(f"Saved preview to {PREVIEW_PATH}")


if __name__ == "__main__":
    main()

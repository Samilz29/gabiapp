#!/usr/bin/env python3
"""
Extracts transparent PNG sprites for Gabi from the two reference sheets.
Uses flood-fill from image borders on neutral gray/white checkerboard pixels
so Gabi's white paws and cream fur inside the dark pixel-art outline stay intact.
"""
import os
import sys
from collections import deque
from PIL import Image, ImageDraw

PROJECT_DIR = "/Users/samilz/proyectosPersonales/gabi-pet"
RAW_SHEET = os.path.join(PROJECT_DIR, "assets/raw/gabi_sheet.jpg")
RAW_REST = os.path.join(PROJECT_DIR, "assets/raw/gabi_rest.jpg")
OUT_DIR = os.path.join(PROJECT_DIR, "assets/sprites")
PREVIEW_PATH = "/Users/samilz/.gemini/antigravity-cli/brain/011efb60-b5a6-4c39-acb2-ad0c10bbd5a1/scratch/sprites_preview.png"


def is_bg_pixel(r, g, b):
    # Checkerboard is white (~255) and light gray (~195-215), plus JPEG compression artifacts
    # Also handle the misty gray gradient at the bottom of gabi_rest.jpg (~180-230, low chroma)
    mx = max(r, g, b)
    mn = min(r, g, b)
    chroma = mx - mn
    # Pure gray/white background
    if mn >= 165 and chroma <= 20:
        return True
    # Slight anti-alias/JPEG fringe near neutral gray
    if mn >= 185 and chroma <= 28:
        return True
    return False


def remove_checkerboard_floodfill(img):
    """Flood-fill from all 4 borders through neutral checkerboard pixels."""
    rgba = img.convert("RGBA")
    w, h = rgba.size
    px = rgba.load()
    visited = [[False] * w for _ in range(h)]
    q = deque()

    # Seed all border pixels that look like background
    for x in range(w):
        for y in (0, h - 1):
            r, g, b, a = px[x, y]
            if is_bg_pixel(r, g, b):
                visited[y][x] = True
                q.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if not visited[y][x]:
                r, g, b, a = px[x, y]
                if is_bg_pixel(r, g, b):
                    visited[y][x] = True
                    q.append((x, y))

    while q:
        cx, cy = q.popleft()
        px[cx, cy] = (0, 0, 0, 0)
        for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
            if 0 <= nx < w and 0 <= ny < h and not visited[ny][nx]:
                r, g, b, a = px[nx, ny]
                if is_bg_pixel(r, g, b):
                    visited[ny][nx] = True
                    q.append((nx, ny))

    # Clean 1-pixel light neutral halo right next to transparent pixels (JPEG ringing around outline)
    to_clear = []
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            r, g, b, a = px[x, y]
            if a > 0:
                mx = max(r, g, b)
                mn = min(r, g, b)
                if mn >= 150 and (mx - mn) <= 22:
                    # Check if adjacent to transparent
                    if (px[x - 1, y][3] == 0 or px[x + 1, y][3] == 0 or
                            px[x, y - 1][3] == 0 or px[x, y + 1][3] == 0):
                        to_clear.append((x, y))
    for x, y in to_clear:
        px[x, y] = (0, 0, 0, 0)

    return rgba


def find_sprite_components(rgba, min_area=1500):
    """Find connected components of non-transparent pixels, merging nearby small pieces (like bark lines)."""
    w, h = rgba.size
    px = rgba.load()
    # Downsample mask by 4x for fast component detection
    step = 4
    sw, sh = (w + step - 1) // step, (h + step - 1) // step
    grid = [[False] * sw for _ in range(sh)]
    for sy in range(sh):
        y0 = sy * step
        for sx in range(sw):
            x0 = sx * step
            if px[x0, y0][3] > 0:
                grid[sy][sx] = True

    visited = [[False] * sw for _ in range(sh)]
    comps = []
    for sy in range(sh):
        for sx in range(sw):
            if grid[sy][sx] and not visited[sy][sx]:
                q = deque([(sx, sy)])
                visited[sy][sx] = True
                minx = maxx = sx
                miny = maxy = sy
                count = 0
                while q:
                    cx, cy = q.popleft()
                    count += 1
                    if cx < minx: minx = cx
                    if cx > maxx: maxx = cx
                    if cy < miny: miny = cy
                    if cy > maxy: maxy = cy
                    for dx in (-1, 0, 1):
                        for dy in (-1, 0, 1):
                            nx, ny = cx + dx, cy + dy
                            if 0 <= nx < sw and 0 <= ny < sh and grid[ny][nx] and not visited[ny][nx]:
                                visited[ny][nx] = True
                                q.append((nx, ny))
                box = [minx * step, miny * step, min(w, (maxx + 1) * step), min(h, (maxy + 1) * step)]
                comps.append((count * step * step, box))

    # Separate main bodies and small accents (bark lines)
    mains = [box for area, box in comps if area >= min_area]
    smalls = [box for area, box in comps if 30 <= area < min_area]

    # Attach each small accent to the nearest main body within 80px
    for sb in smalls:
        scx = (sb[0] + sb[2]) / 2
        scy = (sb[1] + sb[3]) / 2
        best_i = None
        best_d = 999999
        for i, mb in enumerate(mains):
            # Distance from sb center to mb box
            dx = max(mb[0] - scx, 0, scx - mb[2])
            dy = max(mb[1] - scy, 0, scy - mb[3])
            d = (dx * dx + dy * dy) ** 0.5
            if d < best_d:
                best_d = d
                best_i = i
        if best_i is not None and best_d < 90:
            mb = mains[best_i]
            mb[0] = min(mb[0], sb[0])
            mb[1] = min(mb[1], sb[1])
            mb[2] = max(mb[2], sb[2])
            mb[3] = max(mb[3], sb[3])

    # Sort into rows by vertical center, then left-to-right
    mains.sort(key=lambda b: (b[1] + b[3]) / 2)
    rows = []
    for b in mains:
        cy = (b[1] + b[3]) / 2
        if not rows or abs(cy - rows[-1][0]) > 180:
            rows.append([cy, [b]])
        else:
            rows[-1][1].append(b)
    ordered = []
    for _, rboxes in rows:
        rboxes.sort(key=lambda b: b[0])
        ordered.append(rboxes)
    return ordered


def tight_crop(img, pad=4):
    bbox = img.getbbox()
    if not bbox:
        return img
    x0 = max(0, bbox[0] - pad)
    y0 = max(0, bbox[1] - pad)
    x1 = min(img.width, bbox[2] + pad)
    y1 = min(img.height, bbox[3] + pad)
    return img.crop((x0, y0, x1, y1))


def normalize_sprite(sprite, canvas_size=256, target_height=200):
    """Scale sprite cleanly (keeping pixel-art crispness with NEAREST/BOX) and bottom-center it."""
    w, h = sprite.size
    # Fit within target_height and target_width=230
    scale = min(target_height / h, 230 / w)
    nw = max(1, int(round(w * scale)))
    nh = max(1, int(round(h * scale)))
    resized = sprite.resize((nw, nh), Image.Resampling.NEAREST)
    canvas = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    ox = (canvas_size - nw) // 2
    oy = canvas_size - nh - 8  # Align paws to consistent baseline
    canvas.paste(resized, (ox, oy), resized)
    return canvas


def keep_largest_component(rgba):
    """Keep only the largest connected non-transparent component (removes stray specks)."""
    w, h = rgba.size
    px = rgba.load()
    step = 4
    sw, sh = (w + step - 1) // step, (h + step - 1) // step
    visited = [[False] * sw for _ in range(sh)]
    best_cells = []
    for sy in range(sh):
        for sx in range(sw):
            if px[sx * step, sy * step][3] > 0 and not visited[sy][sx]:
                q = deque([(sx, sy)])
                visited[sy][sx] = True
                cells = []
                while q:
                    cx, cy = q.popleft()
                    cells.append((cx, cy))
                    for dx in (-1, 0, 1):
                        for dy in (-1, 0, 1):
                            nx, ny = cx + dx, cy + dy
                            if 0 <= nx < sw and 0 <= ny < sh and not visited[ny][nx] and px[nx * step, ny * step][3] > 0:
                                visited[ny][nx] = True
                                q.append((nx, ny))
                if len(cells) > len(best_cells):
                    best_cells = cells
    if not best_cells:
        return rgba
    minx = min(c[0] for c in best_cells) * step
    maxx = min(w, (max(c[0] for c in best_cells) + 1) * step)
    miny = min(c[1] for c in best_cells) * step
    maxy = min(h, (max(c[1] for c in best_cells) + 1) * step)
    return rgba.crop((max(0, minx - 8), max(0, miny - 8), min(w, maxx + 8), min(h, maxy + 8)))


def clear_enclosed_tail_hole(img):
    """Clear the small enclosed checkerboard pocket inside jump_1's curled tail."""
    rgba = img.copy()
    w, h = rgba.size
    px = rgba.load()
    # Look in the tail region (left 35%, vertical 25%-65%) for neutral bright checkerboard pixels
    for y in range(int(h * 0.25), int(h * 0.65)):
        for x in range(int(w * 0.05), int(w * 0.35)):
            r, g, b, a = px[x, y]
            if a > 0 and min(r, g, b) >= 190 and (max(r, g, b) - min(r, g, b)) <= 16:
                px[x, y] = (0, 0, 0, 0)
    return rgba


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(os.path.dirname(PREVIEW_PATH), exist_ok=True)

    print("Processing sprite sheet...")
    sheet = Image.open(RAW_SHEET)
    sheet_rgba = remove_checkerboard_floodfill(sheet)
    rows = find_sprite_components(sheet_rgba)
    print(f"Found {len(rows)} rows: {[len(r) for r in rows]}")

    names_by_row = [
        ["idle_front", "idle_side", "sit_front", "sit_side"],
        ["walk_1", "walk_2", "walk_3", "happy_front"],
        ["run_1", "run_2", "run_3"],
        ["jump_1", "jump_2", "jump_3"],
        ["bark_1", "bark_2", "bark_3"],
    ]

    saved = []
    for r_idx, rboxes in enumerate(rows):
        for c_idx, box in enumerate(rboxes):
            name = names_by_row[r_idx][c_idx] if r_idx < len(names_by_row) and c_idx < len(names_by_row[r_idx]) else f"r{r_idx}_c{c_idx}"
            x0, y0, x1, y1 = box
            crop = sheet_rgba.crop((max(0, x0 - 8), max(0, y0 - 8), min(sheet_rgba.width, x1 + 8), min(sheet_rgba.height, y1 + 8)))
            crop = tight_crop(crop, pad=2)
            if name == "jump_1":
                crop = clear_enclosed_tail_hole(crop)
            # Normalize all side-facing sprites to face RIGHT
            if name in ("idle_side", "sit_side"):
                crop = crop.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
            norm = normalize_sprite(crop, canvas_size=256, target_height=196)
            out_path = os.path.join(OUT_DIR, f"{name}.png")
            norm.save(out_path)
            saved.append((name, norm))
            print(f"  Saved {name}.png (raw {crop.size})")

    print("Processing resting sprite...")
    rest = Image.open(RAW_REST)
    rest_rgba = remove_checkerboard_floodfill(rest)
    rest_rgba = keep_largest_component(rest_rgba)
    rest_crop = tight_crop(rest_rgba, pad=4)
    # Resting Gabi is wider and lower than standing Gabi
    rest_norm = normalize_sprite(rest_crop, canvas_size=256, target_height=165)
    rest_norm.save(os.path.join(OUT_DIR, "rest_lying.png"))
    saved.append(("rest_lying", rest_norm))
    print(f"  Saved rest_lying.png (raw {rest_crop.size})")

    # Build visual verification preview on a teal background so any stray white/gray pixels pop out immediately
    cols = 4
    num_rows = (len(saved) + cols - 1) // cols
    cell = 220
    preview = Image.new("RGB", (cols * cell, num_rows * cell), (35, 95, 115))
    draw = ImageDraw.Draw(preview)
    for idx, (name, im) in enumerate(saved):
        r = idx // cols
        c = idx % cols
        thumb = im.resize((190, 190), Image.Resampling.NEAREST)
        preview.paste(thumb, (c * cell + 15, r * cell + 5), thumb)
        draw.text((c * cell + 12, r * cell + 198), name, fill=(255, 255, 255))
    preview.save(PREVIEW_PATH)
    print(f"Saved preview to {PREVIEW_PATH}")


if __name__ == "__main__":
    main()

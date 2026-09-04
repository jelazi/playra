#!/usr/bin/env python3
import json
import math
import os
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parent


def ensure_parent(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)


def _lerp(a: int, b: int, t: float) -> int:
    return int(a + (b - a) * t)


def _parse_scale(scale_value: str) -> float:
    return float(scale_value.lower().replace("x", ""))


def _parse_point_size(size_value: str) -> float:
    return float(size_value.lower().split("x")[0])


def build_master_icon(size: int = 1024) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Rounded app tile with vertical gradient.
    radius = int(size * 0.24)
    for y in range(size):
        t = y / max(1, size - 1)
        color = (
            _lerp(20, 11, t),
            _lerp(69, 52, t),
            _lerp(130, 96, t),
            255,
        )
        draw.line([(0, y), (size, y)], fill=color)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    img.putalpha(mask)

    # Play badge.
    badge_size = int(size * 0.62)
    badge_left = (size - badge_size) // 2
    badge_top = int(size * 0.14)
    badge_right = badge_left + badge_size
    badge_bottom = badge_top + badge_size
    draw.rounded_rectangle(
        [badge_left, badge_top, badge_right, badge_bottom],
        radius=int(size * 0.1),
        fill=(245, 251, 255, 255),
    )

    tri_margin_left = int(size * 0.12)
    tri_margin_top = int(size * 0.08)
    play_points = [
        (badge_left + tri_margin_left, badge_top + tri_margin_top),
        (badge_right - int(size * 0.17), (badge_top + badge_bottom) // 2),
        (badge_left + tri_margin_left, badge_bottom - tri_margin_top),
    ]
    draw.polygon(play_points, fill=(27, 120, 201, 255))

    # Subtitle strip.
    strip_h = int(size * 0.26)
    strip_left = int(size * 0.16)
    strip_right = int(size * 0.84)
    strip_bottom = int(size * 0.9)
    strip_top = strip_bottom - strip_h
    draw.rounded_rectangle(
        [strip_left, strip_top, strip_right, strip_bottom],
        radius=int(size * 0.06),
        fill=(12, 32, 67, 220),
    )

    line_w = int(size * 0.045)
    line_gap = int(size * 0.03)
    line_left = strip_left + int(size * 0.08)
    line_right = strip_right - int(size * 0.08)
    y1 = strip_top + int(size * 0.07)
    y2 = y1 + line_w + line_gap
    draw.rounded_rectangle([line_left, y1, line_right, y1 + line_w], radius=line_w // 2, fill=(251, 211, 69, 255))
    draw.rounded_rectangle([line_left + int(size * 0.03), y2, line_right - int(size * 0.07), y2 + line_w], radius=line_w // 2, fill=(251, 211, 69, 255))

    # Search lens overlapping subtitle strip.
    lens_r = int(size * 0.11)
    lens_center_x = int(size * 0.78)
    lens_center_y = int(size * 0.74)
    draw.ellipse(
        [lens_center_x - lens_r, lens_center_y - lens_r, lens_center_x + lens_r, lens_center_y + lens_r],
        outline=(255, 255, 255, 255),
        width=int(size * 0.028),
    )
    handle_len = int(size * 0.1)
    angle = math.radians(42)
    hx1 = lens_center_x + int(math.cos(angle) * lens_r * 0.6)
    hy1 = lens_center_y + int(math.sin(angle) * lens_r * 0.6)
    hx2 = hx1 + int(math.cos(angle) * handle_len)
    hy2 = hy1 + int(math.sin(angle) * handle_len)
    draw.line([(hx1, hy1), (hx2, hy2)], fill=(255, 255, 255, 255), width=int(size * 0.03))

    return img


def save_png(master: Image.Image, size: int, target: Path) -> None:
    ensure_parent(target)
    resized = master.resize((size, size), Image.Resampling.LANCZOS)
    resized.save(target, format="PNG")
    print(f"Created: {target}")


def generate_ios(master: Image.Image) -> None:
    contents_path = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json"
    data = json.loads(contents_path.read_text(encoding="utf-8"))
    for item in data.get("images", []):
        filename = item.get("filename")
        if not filename:
            continue
        px = int(round(_parse_point_size(item["size"]) * _parse_scale(item["scale"])))
        save_png(master, px, contents_path.parent / filename)


def generate_macos(master: Image.Image) -> None:
    contents_path = ROOT / "macos/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json"
    data = json.loads(contents_path.read_text(encoding="utf-8"))
    generated = set()
    for item in data.get("images", []):
        filename = item.get("filename")
        if not filename or filename in generated:
            continue
        px = int(round(_parse_point_size(item["size"]) * _parse_scale(item["scale"])))
        save_png(master, px, contents_path.parent / filename)
        generated.add(filename)


def generate_android(master: Image.Image) -> None:
    sizes = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    for folder, px in sizes.items():
        save_png(master, px, ROOT / f"android/app/src/main/res/{folder}/ic_launcher.png")


def generate_web(master: Image.Image) -> None:
    save_png(master, 192, ROOT / "web/icons/Icon-192.png")
    save_png(master, 512, ROOT / "web/icons/Icon-512.png")
    save_png(master, 192, ROOT / "web/icons/Icon-maskable-192.png")
    save_png(master, 512, ROOT / "web/icons/Icon-maskable-512.png")
    save_png(master, 32, ROOT / "web/favicon.png")


def generate_windows(master: Image.Image) -> None:
    target = ROOT / "windows/runner/resources/app_icon.ico"
    ensure_parent(target)
    resized = [master.resize((s, s), Image.Resampling.LANCZOS) for s in [16, 24, 32, 48, 64, 128, 256]]
    resized[0].save(target, format="ICO", sizes=[img.size for img in resized])
    print(f"Created: {target}")


def generate_linux(master: Image.Image) -> None:
    save_png(master, 256, ROOT / "linux/runner/resources/app_icon.png")


def generate_misc(master: Image.Image) -> None:
    for size in [16, 32, 64, 128, 256, 512, 1024]:
        save_png(master, size, ROOT / f"assets/images/app_icon_{size}.png")


def main() -> None:
    master = build_master_icon(1024)
    generate_misc(master)
    generate_android(master)
    generate_ios(master)
    generate_macos(master)
    generate_windows(master)
    generate_web(master)
    generate_linux(master)
    print("All icons generated successfully.")


if __name__ == "__main__":
    main()

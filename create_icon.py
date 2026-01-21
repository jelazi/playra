#!/usr/bin/env python3
from PIL import Image, ImageDraw
import os

def create_app_icon(size, output_path):
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    margin = size // 10
    corner_radius = size // 5
    
    # Blue background
    draw.rounded_rectangle(
        [margin, margin, size - margin, size - margin],
        radius=corner_radius,
        fill=(45, 120, 200, 255)
    )
    
    center_x = size // 2
    center_y = size // 2
    
    # White CC box
    cc_height = size // 3
    cc_width = size // 2
    cc_x = center_x - cc_width // 2
    cc_y = center_y - cc_height // 2
    
    draw.rounded_rectangle(
        [cc_x, cc_y, cc_x + cc_width, cc_y + cc_height],
        radius=size // 20,
        fill=(255, 255, 255, 255)
    )
    
    # Draw simple CC using rectangles (stylized)
    line_width = max(2, size // 30)
    letter_gap = size // 20
    c_width = size // 8
    c_height = size // 5
    
    # First C
    c1_x = center_x - c_width - letter_gap // 2
    c1_y = center_y - c_height // 2
    
    # Draw C as arc-like shape using lines
    draw.arc([c1_x, c1_y, c1_x + c_width, c1_y + c_height], 
             45, 315, fill=(45, 120, 200, 255), width=line_width)
    
    # Second C
    c2_x = center_x + letter_gap // 2
    c2_y = center_y - c_height // 2
    
    draw.arc([c2_x, c2_y, c2_x + c_width, c2_y + c_height], 
             45, 315, fill=(45, 120, 200, 255), width=line_width)
    
    img.save(output_path)
    print(f"Created: {output_path}")

os.makedirs("assets/images", exist_ok=True)
os.makedirs("macos/Runner/Assets.xcassets/AppIcon.appiconset", exist_ok=True)

sizes = [16, 32, 64, 128, 256, 512, 1024]

for size in sizes:
    create_app_icon(size, f"assets/images/app_icon_{size}.png")
    create_app_icon(size, f"macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_{size}.png")

print("Done!")

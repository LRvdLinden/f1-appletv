#!/usr/bin/env python3
"""Generates Pitwall's asset catalog: app icons (iOS, macOS), tvOS brand assets and accent colour.
Run from the repository root:  python3 Tools/generate_assets.py
"""
import json, os, sys
sys.path.insert(0, os.path.dirname(__file__))
from icon_art import mark, background, draw_kerb
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.join(os.path.dirname(__file__), "..", "Pitwall", "Resources", "Assets.xcassets")
INFO = {"author": "xcode", "version": 1}

def write_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(data, f, indent=2)

def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)

def app_icon():
    folder = os.path.join(ROOT, "AppIcon.appiconset")
    base = mark(1024, 1024, 0.78).convert("RGB")
    images = []
    save(base, os.path.join(folder, "icon-1024.png"))
    images.append({"filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"})
    for size in [16, 32, 128, 256, 512]:
        for scale in [1, 2]:
            px = size * scale
            name = f"mac-{size}@{scale}x.png"
            # macOS icons sit on a rounded tile with a margin
            tile = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
            inner = base.resize((824, 824), Image.LANCZOS)
            m = Image.new("L", (824, 824), 0)
            ImageDraw.Draw(m).rounded_rectangle([0, 0, 823, 823], radius=185, fill=255)
            tile.paste(inner, (100, 100), m)
            save(tile.resize((px, px), Image.LANCZOS), os.path.join(folder, name))
            images.append({"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{size}x{size}"})
    write_json(os.path.join(folder, "Contents.json"), {"images": images, "info": INFO})

def imagestack(folder, w, h, scales):
    layers = []
    for layer in ["Front", "Back"]:
        lf = os.path.join(folder, f"{layer}.imagestacklayer")
        write_json(os.path.join(lf, "Contents.json"), {"info": INFO})
        imgs = []
        for scale in scales:
            W, H = w * scale, h * scale
            if layer == "Back":
                img = draw_kerb(background(W, H)).convert("RGB")
            else:
                img = mark(W, H, 0.78, with_bg=False)
            name = f"{layer.lower()}@{scale}x.png"
            save(img, os.path.join(lf, "Content.imageset", name))
            imgs.append({"filename": name, "idiom": "tv", "scale": f"{scale}x"})
        write_json(os.path.join(lf, "Content.imageset", "Contents.json"), {"images": imgs, "info": INFO})
        layers.append({"filename": f"{layer}.imagestacklayer"})
    write_json(os.path.join(folder, "Contents.json"), {"info": INFO, "layers": layers})

def top_shelf(folder, w, h):
    imgs = []
    for scale in [1, 2]:
        W, H = w * scale, h * scale
        img = draw_kerb(background(W, H))
        d = ImageDraw.Draw(img)
        logo = mark(H, H, 0.7, with_bg=False)
        img.alpha_composite(logo, (int(W * 0.08), 0))
        font = ImageFont.truetype("/usr/share/fonts/truetype/google-fonts/Poppins-Bold.ttf", int(H * 0.2))
        d.text((int(W * 0.08) + H, int(H * 0.36)), "Pitwall", font=font, fill=(255, 255, 255))
        name = f"topshelf@{scale}x.png"
        save(img.convert("RGB"), os.path.join(folder, name))
        imgs.append({"filename": name, "idiom": "tv", "scale": f"{scale}x"})
    write_json(os.path.join(folder, "Contents.json"), {"images": imgs, "info": INFO})

def brand_assets():
    folder = os.path.join(ROOT, "App Icon & Top Shelf Image.brandassets")
    imagestack(os.path.join(folder, "App Icon.imagestack"), 400, 240, [1, 2])
    imagestack(os.path.join(folder, "App Icon - App Store.imagestack"), 1280, 768, [1])
    top_shelf(os.path.join(folder, "Top Shelf Image.imageset"), 1920, 720)
    top_shelf(os.path.join(folder, "Top Shelf Image Wide.imageset"), 2320, 720)
    write_json(os.path.join(folder, "Contents.json"), {
        "assets": [
            {"filename": "App Icon - App Store.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "1280x768"},
            {"filename": "App Icon.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "400x240"},
            {"filename": "Top Shelf Image Wide.imageset", "idiom": "tv", "role": "top-shelf-image-wide", "size": "2320x720"},
            {"filename": "Top Shelf Image.imageset", "idiom": "tv", "role": "top-shelf-image", "size": "1920x720"},
        ],
        "info": INFO,
    })

def accent():
    write_json(os.path.join(ROOT, "AccentColor.colorset", "Contents.json"), {
        "colors": [{"idiom": "universal", "color": {"color-space": "srgb", "components": {"red": "0.929", "green": "0.110", "blue": "0.141", "alpha": "1.000"}}}],
        "info": INFO,
    })

def logo():
    folder = os.path.join(ROOT, "Logo.imageset")
    save(mark(512, 512, 0.78, with_bg=False), os.path.join(folder, "logo.png"))
    write_json(os.path.join(folder, "Contents.json"), {"images": [{"filename": "logo.png", "idiom": "universal"}], "info": INFO})

if __name__ == "__main__":
    write_json(os.path.join(ROOT, "Contents.json"), {"info": INFO})
    app_icon(); brand_assets(); accent(); logo()
    print("Assets written to", os.path.normpath(ROOT))

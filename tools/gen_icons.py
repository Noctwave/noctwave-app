import os
from PIL import Image

SRC = r"C:\Users\sm171\.dsh\attachments\v1\objects\80\8040223e798a809590688acdf0a70a0c293febda35d10333c725fdcd40f1bba2"
ROOT = r"E:\Projects Directory\noctwave-app"

img = Image.open(SRC).convert("RGB")
print("source size:", img.size)

def save(size, path):
    im = img.resize((size, size), Image.LANCZOS)
    im.save(path, "PNG")
    print("wrote", path, size)

# iOS appiconset
ios = os.path.join(ROOT, "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset")
ios_sizes = {
    "Icon-App-20x20@1x.png": 20,
    "Icon-App-20x20@2x.png": 40,
    "Icon-App-20x20@3x.png": 60,
    "Icon-App-29x29@1x.png": 29,
    "Icon-App-29x29@2x.png": 58,
    "Icon-App-29x29@3x.png": 87,
    "Icon-App-40x40@1x.png": 40,
    "Icon-App-40x40@2x.png": 80,
    "Icon-App-40x40@3x.png": 120,
    "Icon-App-60x60@2x.png": 120,
    "Icon-App-60x60@3x.png": 180,
    "Icon-App-76x76@1x.png": 76,
    "Icon-App-76x76@2x.png": 152,
    "Icon-App-83.5x83.5@2x.png": 167,
    "Icon-App-1024x1024@1x.png": 1024,
}
for name, size in ios_sizes.items():
    save(size, os.path.join(ios, name))

# Android mipmap launcher
android = os.path.join(ROOT, "android", "app", "src", "main", "res")
android_sizes = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}
for folder, size in android_sizes.items():
    save(size, os.path.join(android, folder, "ic_launcher.png"))

# docs/appicon.png for feed
save(512, os.path.join(ROOT, "docs", "appicon.png"))
print("DONE")

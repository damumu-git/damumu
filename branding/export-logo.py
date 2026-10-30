"""Export the approved embrace logo. Run from any directory; requires Pillow.

Only resize/pad the selected raster master: do not redraw the approved artwork.
"""
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
MASTER = ROOT / 'branding/damumu-embrace-master.png'
SOURCE = Image.open(MASTER).convert('RGB')
BACKGROUND = SOURCE.getpixel((0, 0))


def export(path, size, inset=0):
    image = SOURCE.resize((size - 2 * inset, size - 2 * inset), Image.Resampling.LANCZOS)
    if inset:
        canvas = Image.new('RGB', (size, size), BACKGROUND)
        canvas.paste(image, (inset, inset))
        image = canvas
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    image.save(target, optimize=True)


for path in ['app/assets/branding/logo.png', 'app/web/logo.png',
             'admin/public/brand/logo.png', 'website/dist/assets/logo.png',
             'preview/shared/logo.png']:
    export(path, 256)
for path in ['app/web/favicon.png', 'admin/public/favicon.png', 'website/dist/favicon.png']:
    export(path, 48)
for size in [192, 512]:
    export(f'app/web/icons/Icon-{size}.png', size)
    # Conservative safe zone for circular / squircle masks.
    export(f'app/web/icons/Icon-maskable-{size}.png', size, round(size * .14))
export('website/dist/apple-touch-icon.png', 180)
export('admin/public/apple-touch-icon.png', 180)

for density, size in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
    export(f'app/android/app/src/main/res/mipmap-{density}/ic_launcher.png', size)
export('app/android/app/src/main/res/drawable-nodpi/launch_image.png', 288, 48)
# Adaptive foreground occupies 78dp of the 108dp canvas; visible mark fits safe zone.
export('app/android/app/src/main/res/drawable-nodpi/ic_launcher_foreground.png', 432, 60)

catalog = ROOT / 'app/ios/Runner/Assets.xcassets/AppIcon.appiconset'
for item in json.loads((catalog / 'Contents.json').read_text())['images']:
    if 'filename' in item:
        size = round(float(item['size'].split('x')[0]) * float(item['scale'].rstrip('x')))
        export(str((catalog / item['filename']).relative_to(ROOT)), size)
for scale, suffix in [(1, ''), (2, '@2x'), (3, '@3x')]:
    export(f'app/ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage{suffix}.png', 160 * scale)

print(f'Exported approved logo; solid padding color #{BACKGROUND[0]:02x}{BACKGROUND[1]:02x}{BACKGROUND[2]:02x}')

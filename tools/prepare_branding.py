"""Generate launcher sizes from the owner's approved ViL artwork (Pillow required)."""
from pathlib import Path
import shutil
import sys
from PIL import Image

root = Path(__file__).resolve().parent.parent
brand = root / 'branding'
brand.mkdir(exist_ok=True)
if len(sys.argv) > 1:
    shutil.copyfile(sys.argv[1], brand / 'vil-icon.png')
source = Image.open(brand / 'vil-icon.png').convert('RGBA')
res = root / 'mobile/android/app/src/main/res'
for density, size in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
    source.resize((size, size), Image.Resampling.LANCZOS).save(res / f'mipmap-{density}/ic_launcher.png')
foreground = Image.new('RGBA', (432, 432))
foreground.alpha_composite(source.resize((288, 288), Image.Resampling.LANCZOS), (72, 72))
(res / 'drawable-nodpi').mkdir(exist_ok=True)
foreground.save(res / 'drawable-nodpi/vil_foreground.png')
source.resize((256, 256), Image.Resampling.LANCZOS).save(brand / 'vil-icon-256.png')
source.save(brand / 'vil-icon.ico', sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
shutil.copyfile(brand / 'vil-icon-256.png', root / 'output/vil-icon.png')
print('ViL launcher assets generated')

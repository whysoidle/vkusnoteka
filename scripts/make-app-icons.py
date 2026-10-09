"""Package the selected glass artwork into platform icon sizes (run on macOS).

Artwork is edited with imagegen. sips only resizes the approved PNG masters;
the ICO writer wraps resized PNG files without altering their pixels or alpha.
"""
import argparse
import struct
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
MASTER = ROOT / 'app/branding/vkusnoteka-desktop.png'
FOREGROUND = ROOT / 'app/branding/vkusnoteka-foreground.png'


def resize(source, target, size):
    target.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ['sips', '-z', str(size), str(size), str(source), '--out', str(target)],
        stdout=subprocess.DEVNULL, check=True,
    )


def generate(platform='all'):
    if platform in ('all', 'macos'):
        icons = ROOT / 'app/macos/Runner/Assets.xcassets/AppIcon.appiconset'
        for size in (16, 32, 64, 128, 256, 512, 1024):
            resize(MASTER, icons / f'app_icon_{size}.png', size)
    if platform in ('all', 'android'):
        resources = ROOT / 'app/android/app/src/main/res'
        for density, size in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96),
                              ('xxhdpi', 144), ('xxxhdpi', 192)]:
            resize(MASTER, resources / f'mipmap-{density}/ic_launcher.png', size)
        resize(FOREGROUND, resources / 'drawable-nodpi/ic_launcher_book.png', 432)
    if platform in ('all', 'windows'):
        sizes = (16, 24, 32, 48, 64, 128, 256)
        images = []
        with tempfile.TemporaryDirectory(prefix='vkusnoteka-icons-') as directory:
            for size in sizes:
                output = Path(directory) / f'{size}.png'
                resize(MASTER, output, size)
                images.append(output.read_bytes())
        header = bytearray(struct.pack('<HHH', 0, 1, len(sizes)))
        offset = 6 + 16 * len(sizes)
        for size, data in zip(sizes, images):
            header.extend(struct.pack('<BBBBHHII', size % 256, size % 256,
                                      0, 0, 1, 32, len(data), offset))
            offset += len(data)
        target = ROOT / 'app/windows/runner/resources/app_icon.ico'
        target.write_bytes(header + b''.join(images))
    if platform == 'all':
        resize(MASTER, ROOT / 'app/assets/branding/app_icon.png', 256)
    print(f'Вкуснотека: {platform} icon assets updated.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platform', choices=('all', 'macos', 'windows', 'android'),
                        default='all')
    generate(parser.parse_args().platform)

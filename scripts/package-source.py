"""Create a portable source archive while excluding credentials, SDKs and caches."""
import argparse
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--output", type=Path, default=root / "dist/Vkusnoteka-Source.zip")
target = parser.parse_args().output
target.parent.mkdir(parents=True, exist_ok=True)
skip_dirs = {".git", ".gradle", ".dart_tool", ".idea", "build", "ephemeral", ".symlinks",
             "__pycache__", ".pytest_cache", ".venv", ".build", ".swiftpm", "Pods", "xcuserdata"}
skip_names = {"key.properties", "local.properties", ".flutter-plugins-dependencies", ".env", ".DS_Store"}
paths = [root / name for name in ("README.md", "CHANGELOG.md", ".gitignore",
                                  "LICENSE", "NOTICE", "THIRD_PARTY.md")]
for folder in ("app", "backend", "docs", "packaging", "scripts", ".github"):
    for file in (root / folder).rglob("*"):
        if file.is_symlink() or not file.is_file():
            continue
        relative = file.relative_to(root)
        if set(relative.parts) & skip_dirs or any(part.endswith(".egg-info") for part in relative.parts):
            continue
        if file.name in skip_names or file.suffix in {".iml", ".jks", ".keystore", ".p12"}:
            continue
        paths.append(file)
with ZipFile(target, "w", ZIP_DEFLATED) as archive:
    for file in sorted(paths):
        archive.write(file, Path("Vkusnoteka") / file.relative_to(root))
print(f"Created {target.name}: {len(paths)} files; signing keys and tokens excluded.")

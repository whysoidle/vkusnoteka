"""Create a portable source archive while excluding credentials, SDKs and caches."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

root = Path(__file__).resolve().parent.parent
target = root / "dist/Vkusnoteka-Source.zip"
target.parent.mkdir(exist_ok=True)
skip_dirs = {".git", ".gradle", ".dart_tool", ".idea", "build", "ephemeral", ".symlinks",
             "__pycache__", ".pytest_cache", ".venv", ".build", ".swiftpm", "Pods", "xcuserdata"}
skip_names = {"key.properties", "local.properties", ".flutter-plugins-dependencies", ".env", ".DS_Store"}
paths = [root / "README.md", root / ".gitignore"]
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

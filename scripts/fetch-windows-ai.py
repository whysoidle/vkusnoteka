"""Bundle a pinned upstream CPU worker; models are downloaded by the app."""
import hashlib
import json
from pathlib import Path
import shutil
import tempfile
import os
import subprocess
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parent.parent
TARGET = ROOT / 'app/build/windows/x64/runner/Release/LocalAI'
TAG = 'b11429'
ARCHIVE = f'llama-{TAG}-bin-win-cpu-x64.zip'
CHECKSUM = '1283323272b04cd07905816a597a0da810918102de958f4ff6f7bbaa70ed2efe'


def main():
    TARGET.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='vkusnoteka-ai-') as temp:
        archive = Path(temp) / ARCHIVE
        urllib.request.urlretrieve(
            f'https://github.com/ggml-org/llama.cpp/releases/download/{TAG}/{ARCHIVE}', archive)
        if hashlib.sha256(archive.read_bytes()).hexdigest() != CHECKSUM:
            raise RuntimeError('Local AI runtime checksum mismatch')
        # Distribute the server and its DLLs, not the other upstream tools.
        with zipfile.ZipFile(archive) as package:
            for item in package.infolist():
                name = Path(item.filename).name
                if name != item.filename:
                    raise RuntimeError('Unexpected upstream archive layout')
                if name == 'llama-server.exe' or name.endswith('.dll') or name.startswith('LICENSE'):
                    with package.open(item) as source, (TARGET / name).open('wb') as target:
                        shutil.copyfileobj(source, target)
    # Upstream's narrow main(argc, argv) otherwise loses Cyrillic characters
    # before model loading, even when its parent correctly uses CreateProcessW.
    # Set UTF-8 for this worker only, without changing Windows system settings.
    sdk = Path(os.environ.get('ProgramFiles(x86)', r'C:\Program Files (x86)')) / 'Windows Kits/10/bin'
    manifest_tools = sorted(sdk.glob('*/x64/mt.exe'), reverse=True)
    if not manifest_tools:
        raise RuntimeError('Windows SDK manifest tool mt.exe is required')
    subprocess.run([str(manifest_tools[0]), '-nologo', '-manifest',
                    str(ROOT / 'packaging/windows-ai.manifest'),
                    f'-outputresource:{TARGET / "llama-server.exe"};#1'], check=True)
    for name, url in {
        'LICENSE-llama.cpp.txt': f'https://raw.githubusercontent.com/ggml-org/llama.cpp/{TAG}/LICENSE',
        'LICENSE-Qwen3.txt': 'https://huggingface.co/Qwen/Qwen3-4B-GGUF/resolve/bc640142c66e1fdd12af0bd68f40445458f3869b/LICENSE',
    }.items():
        urllib.request.urlretrieve(url, TARGET / name)
    (TARGET / 'runtime.json').write_text(json.dumps({
        'engine': 'llama.cpp', 'version': TAG, 'archiveSha256': CHECKSUM,
        'source': 'https://github.com/ggml-org/llama.cpp',
        'model': 'Qwen3 4B Q4_K_M', 'modelDownloadedSeparately': True,
        'utf8ProcessManifest': True,
    }, indent=2), encoding='utf-8')
    for required in ('llama-server.exe', 'llama-server-impl.dll', 'llama.dll', 'ggml.dll', 'ggml-base.dll', 'ggml-cpu-x64.dll'):
        if not (TARGET / required).is_file():
            raise RuntimeError(f'Missing AI runtime dependency: {required}')
    print(f'Bundled llama.cpp {TAG} CPU runtime with verified SHA256')


if __name__ == '__main__':
    main()

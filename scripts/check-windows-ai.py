"""Run the shipped CPU worker with the app's real prompts and shared decoder."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import secrets
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
MODEL_SIZE = 2497280256
MODEL_SHA = '7485fe6f11af29433bc51cab58009521f205840f5b4ae3a32fa7f92e8534fdf5'
MODEL_URL = ('https://huggingface.co/Qwen/Qwen3-4B-GGUF/resolve/'
             'bc640142c66e1fdd12af0bd68f40445458f3869b/Qwen3-4B-Q4_K_M.gguf')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--server', type=Path, default=ROOT / 'app/build/windows/x64/runner/Release/LocalAI/llama-server.exe')
    parser.add_argument('--model', type=Path, default=Path(tempfile.gettempdir()) / 'Вкуснотека ИИ' / 'Qwen3 4B.gguf')
    parser.add_argument('--dart', default='dart')
    args = parser.parse_args()
    args.model.parent.mkdir(parents=True, exist_ok=True)
    if not args.model.exists() or args.model.stat().st_size != MODEL_SIZE:
        print('Downloading pinned 2.50 GB model for the release smoke test', flush=True)
        urllib.request.urlretrieve(MODEL_URL, args.model)
    digest = hashlib.sha256()
    with args.model.open('rb') as source:
        for block in iter(lambda: source.read(4 * 1024 * 1024), b''):
            digest.update(block)
    if digest.hexdigest() != MODEL_SHA:
        raise RuntimeError('Smoke test model checksum mismatch')
    with tempfile.TemporaryDirectory(prefix='vkusnoteka-smoke-') as temp:
        request_file, output_file = Path(temp) / 'request.json', Path(temp) / 'output.json'
        subprocess.run([args.dart, 'run', 'tool/check_windows_ai.dart', 'prepare', str(request_file)], cwd=ROOT / 'app', check=True)
        cases = json.loads(request_file.read_text(encoding='utf-8'))['cases']
        with socket.socket() as reservation:
            reservation.bind(('127.0.0.1', 0))
            port = reservation.getsockname()[1]
        key = secrets.token_hex(32)
        # Match the native Windows channel's launch arguments.
        command = [str(args.server.resolve()), '--model', str(args.model.resolve()),
                   '--host', '127.0.0.1', '--port', str(port), '--api-key', key,
                   '--ctx-size', '8192', '--parallel', '1', '--threads', str(min(os.cpu_count() or 4, 8)),
                   '--gpu-layers', '0', '--batch-size', '512', '--ubatch-size', '128',
                   '--no-webui', '--no-context-shift', '--offline', '--log-disable']
        with (Path(temp) / 'runtime.log').open('wb') as log:
            worker = subprocess.Popen(command, cwd=args.server.resolve().parent, stdout=log, stderr=log)
            try:
                client = urllib.request.build_opener(urllib.request.ProxyHandler({}))
                origin = f'http://127.0.0.1:{port}'
                headers = {'Authorization': f'Bearer {key}', 'Content-Type': 'application/json'}
                deadline = time.monotonic() + 180
                while True:
                    if worker.poll() is not None:
                        raise RuntimeError('Bundled AI worker exited during startup')
                    try:
                        with client.open(urllib.request.Request(origin + '/health', headers=headers), timeout=2) as response:
                            if response.status == 200: break
                    except (urllib.error.URLError, TimeoutError):
                        pass
                    if time.monotonic() > deadline: raise RuntimeError('Model startup timeout')
                    time.sleep(.15)
                results = []
                for case_index, case in enumerate(cases):
                    outputs = []
                    for index, body in enumerate(case):
                        print(f'Actual model: case {case_index + 1}, fragment {index + 1}/{len(case)}', flush=True)
                        with client.open(urllib.request.Request(origin + '/completion', data=json.dumps(body).encode(), headers=headers), timeout=600) as response:
                            data = json.load(response)
                        if data.get('stop_type') == 'limit' or data.get('truncated'):
                            raise RuntimeError('Actual model exceeded output/context budget')
                        outputs.append(data['content'])
                    results.append(outputs)
                output_file.write_text(json.dumps(results, ensure_ascii=False), encoding='utf-8')
                report = ROOT / 'dist/windows-ai-validation'
                report.mkdir(parents=True, exist_ok=True)
                (report / 'request.json').write_bytes(request_file.read_bytes())
                (report / 'output.json').write_bytes(output_file.read_bytes())
                subprocess.run([args.dart, 'run', 'tool/check_windows_ai.dart', 'check', str(request_file), str(output_file)], cwd=ROOT / 'app', check=True)
            except Exception:
                log.flush()
                print((Path(temp) / 'runtime.log').read_text(encoding='utf-8', errors='replace')[-12000:])
                raise
            finally:
                worker.terminate()
                try: worker.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    worker.kill()
                    worker.wait(timeout=10)


if __name__ == '__main__':
    main()

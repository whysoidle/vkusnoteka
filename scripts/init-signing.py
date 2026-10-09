"""Generate a private signing identity for personal APK installation and updates."""
import secrets
import shutil
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parent.parent
properties = root / "app/android/key.properties"
keys = root / ".local-signing"
keystore = keys / "recipe-vault.p12"
if properties.exists() or keystore.exists():
    raise SystemExit("Signing identity already exists. It was not overwritten.")
keytool = shutil.which("keytool")
if not keytool:
    raise SystemExit("Install JDK 21, then rerun this script.")
keys.mkdir(mode=0o700, exist_ok=True)
password = secrets.token_hex(24)
subprocess.run([keytool, "-genkeypair", "-keystore", str(keystore), "-storetype", "PKCS12",
    "-alias", "recipevault", "-keyalg", "RSA", "-keysize", "3072", "-validity", "10000",
    "-storepass", password, "-keypass", password, "-dname", "CN=Recipe Vault Personal"], check=True)
properties.write_text(f"storeFile={keystore.as_posix()}\nstorePassword={password}\nkeyPassword={password}\nkeyAlias=recipevault\n", encoding="utf-8")
properties.chmod(0o600)
keystore.chmod(0o600)
print("Private signing identity created. Keep .local-signing and key.properties for future APK updates; do not publish them.")

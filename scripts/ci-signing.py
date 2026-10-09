"""Set up signing only when CI secrets are supplied. Never print secrets."""
import base64
import os
from pathlib import Path

data = os.getenv("SIGNING_BASE64", "")
if data:
    root = Path(__file__).resolve().parent.parent
    keys = root / ".local-signing"
    keys.mkdir(exist_ok=True)
    (keys / "release.jks").write_bytes(base64.b64decode(data, validate=True))
    lines = {"storeFile": str(keys / "release.jks").replace("\\", "/"),
             "storePassword": os.environ["SIGNING_STORE_PASSWORD"],
             "keyPassword": os.environ["SIGNING_KEY_PASSWORD"],
             "keyAlias": os.environ["SIGNING_KEY_ALIAS"]}
    def escape(value):
        return value.replace("\\", "\\\\").replace("\n", "\\n").replace("\r", "\\r")
    (root / "app/android/key.properties").write_text("\n".join(f"{key}={escape(value)}" for key, value in lines.items()), encoding="utf-8")
else:
    print("Release signing secrets absent: producing a development-signed APK.")

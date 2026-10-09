"""Decode HTML bytes using BOM, HTTP charset or actual meta declarations."""
import codecs
import re
from bs4 import BeautifulSoup

CHARSET = re.compile(r'''charset\s*=\s*["']?([a-zA-Z0-9._:-]+)''', re.I)


def known_codec(label: str | None) -> str | None:
    if not label:
        return None
    try:
        return codecs.lookup(label.strip()).name
    except LookupError:
        return None


def charset(value: str) -> str | None:
    match = CHARSET.search(value)
    return match.group(1) if match else None


def decode_html(data: bytes, content_type: str = "") -> str:
    if data.startswith(codecs.BOM_UTF8):
        return data.decode("utf-8-sig")
    if data.startswith((codecs.BOM_UTF16_LE, codecs.BOM_UTF16_BE)):
        return data.decode("utf-16")
    codec = known_codec(charset(content_type))
    if codec is None:
        head = BeautifulSoup(data[:8192].decode("latin1"), "html.parser")
        for meta in head.find_all("meta"):
            label = meta.get("charset")
            if not label and str(meta.get("http-equiv", "")).lower() == "content-type":
                label = charset(str(meta.get("content", "")))
            codec = known_codec(label)
            if codec:
                break
    return data.decode(codec or "utf-8")

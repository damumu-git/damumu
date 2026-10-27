"""Mutating integration checks for a DISPOSABLE localhost API/database only.

Run after all migrations and starting a local API with EMOJI_QA_ADMIN_KEY.
This intentionally replaces/disables the coffee asset in the disposable DB.
"""
import json
import struct
import os
from pathlib import Path
import urllib.error
import urllib.parse
import urllib.request

BASE = os.environ.get("EMOJI_QA_BASE", "http://127.0.0.1:18089/api/v1")
assert urllib.parse.urlparse(BASE).hostname in {"127.0.0.1", "localhost"}, "Localhost QA only"
KEY = os.environ.get("EMOJI_QA_ADMIN_KEY", "emoji-qa-only")
ROOT = Path(__file__).resolve().parents[1]


def request(path, body=None, method="GET", admin=True, content_type="application/json"):
    headers = {"Content-Type": content_type}
    if admin:
        headers["X-Admin-Key"] = KEY
    if isinstance(body, dict):
        body = json.dumps(body).encode()
    req = urllib.request.Request(BASE + path, data=body, headers=headers, method=method)
    try:
        response = urllib.request.urlopen(req, timeout=15)
    except urllib.error.HTTPError as error:
        response = error
    payload = response.read()
    return response.status, json.loads(payload) if payload else None


def upload(key, emoji, data):
    boundary = "damumu-emoji-qa-boundary"
    chunks = []
    for name, value in {"key": key, "emoji": emoji, "name": "QA Coffee"}.items():
        chunks.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'.encode())
    chunks.append(f'--{boundary}\r\nContent-Disposition: form-data; name="image"; filename="icon.png"\r\nContent-Type: image/png\r\n\r\n'.encode())
    chunks.extend([data, f"\r\n--{boundary}--\r\n".encode()])
    return request("/admin/emoji-assets", b"".join(chunks), "POST", content_type=f"multipart/form-data; boundary={boundary}")


status, public = request("/emoji-assets", admin=False)
assert status == 200 and len(public["data"]) == 67
assert all(item["width"] == item["height"] == 64 for item in public["data"])
assert all(item["image_url"].startswith("http") for item in public["data"])
for item in public["data"]:
    content = urllib.request.urlopen(item["image_url"], timeout=15).read()
    assert content[:8] == b"\x89PNG\r\n\x1a\n"
    assert struct.unpack(">II", content[16:24]) == (64, 64), item["key"]
assert request("/admin/emoji-assets", admin=False)[0] == 401
coffee = next(item for item in public["data"] if item["key"] == "coffee")
old_url = coffee["image_url"]
old_image = urllib.request.urlopen(old_url).read()
for path in ["/categories", "/interests", "/events", "/admin/categories", "/admin/events"]:
    status, payload = request(path)
    assert status == 200 and payload["error"] is None, (path, status)
status, categories = request("/categories")
assert any(item["icon_url"] for item in categories["data"])
row = next(item for item in categories["data"] if item["code"] == "cafe_hopping")
assert row["icon_url"] == old_url
assert request("/admin/emoji-assets/coffee", {"name": "咖啡", "isActive": False}, "PATCH")[0] == 200
assert not any(item["key"] == "coffee" for item in request("/emoji-assets")[1]["data"])
disabled = next(item for item in request("/categories")[1]["data"] if item["code"] == "cafe_hopping")
assert disabled["icon_url"] is None and disabled["icon"] == row["icon"]
assert request("/admin/emoji-assets/coffee", {"name": "咖啡", "isActive": True}, "PATCH")[0] == 200
assert upload("../escape", "☕", old_image)[0] == 400
assert upload("coffee", "☕", b"not a PNG")[0] == 400
assert upload("coffee", "☕", b"x" * (201 * 1024))[0] == 400
conflict = upload("coffee", "DIFFERENT", old_image)
assert conflict[0] == 409, conflict
status, saved = upload("coffee", "☕", old_image)
assert status == 200, saved
assert saved["data"]["image_url"] != old_url
response = urllib.request.urlopen(saved["data"]["image_url"])
assert "immutable" in response.headers["Cache-Control"]
assert response.headers["Content-Type"].startswith("image/png")
assert urllib.request.urlopen(old_url).read() == old_image
assert request("/admin/emoji-assets/coffee", {"name": "", "isActive": True}, "PATCH")[0] == 400
assert request("/admin/emoji-assets/no-such-key", {"name": "test", "isActive": True}, "PATCH")[0] == 404
print("Emoji API: 67 public assets, absolute URLs, catalog binding, auth, disable fallback, validation, replacement and immutable cache passed")

status, added = upload("qa-new", "🧪", old_image)
assert status == 200, added
assert request("/admin/emoji-assets/qa-new", {"name": "QA new icon", "isActive": False}, "PATCH")[0] == 200
assert upload("qa-conflict", "☕", old_image)[0] == 409
assert request("/admin/audit?action=admin.emoji_asset.saved")[1]["data"]
print("New icon creation, duplicate identity conflict and audit trail passed")

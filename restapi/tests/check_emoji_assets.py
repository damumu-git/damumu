"""Validate the complete 64px PNG library and generated deployment metadata."""
import hashlib
import json
from pathlib import Path
import struct
import zlib

root = Path(__file__).resolve().parents[1]
assets = root / "Assets" / "emoji"
manifest = json.loads((assets / "manifest.json").read_text(encoding="utf-8"))
assert len(manifest) == 67
assert len({item["key"] for item in manifest}) == 67
assert len({item["emoji"].replace("\ufe0f", "").replace("\ufe0e", "") for item in manifest}) == 67
total = 0
for item in manifest:
    data = (assets / (item["key"] + ".png")).read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    width, height, depth, color = struct.unpack(">IIBB", data[16:26])
    assert (width, height, depth, color) == (64, 64, 8, 6), item["key"]
    assert len(data) <= 200 * 1024
    compressed = bytearray()
    offset = 8
    while offset < len(data):
        length = struct.unpack(">I", data[offset:offset + 4])[0]
        kind = data[offset + 4:offset + 8]
        body = data[offset + 8:offset + 8 + length]
        expected = struct.unpack(">I", data[offset + 8 + length:offset + 12 + length])[0]
        assert zlib.crc32(kind + body) == expected
        if kind == b"IDAT":
            compressed.extend(body)
        offset += 12 + length
    raw = zlib.decompress(compressed)
    previous = bytearray(width * 4)
    alphas = []
    for y in range(height):
        start = y * (width * 4 + 1)
        filter_type = raw[start]
        row = bytearray(raw[start + 1:start + 1 + width * 4])
        for x in range(len(row)):
            left, up, corner = (row[x - 4] if x >= 4 else 0), previous[x], (previous[x - 4] if x >= 4 else 0)
            predictors = [0, left, up, (left + up) // 2]
            p = left + up - corner
            paeth = min([(abs(p - left), 0, left), (abs(p - up), 1, up), (abs(p - corner), 2, corner)])[2]
            row[x] = (row[x] + (predictors[filter_type] if filter_type < 4 else paeth)) & 255
        alphas.extend(row[3::4])
        previous = row
    assert min(alphas) == 0 and max(alphas) > 0, item["key"]
    assert item["sha256"] == hashlib.sha256(data).hexdigest()
    assert item["byte_size"] == len(data)
    assert item["storage_key"].endswith(item["sha256"][:12] + ".png")
    total += len(data)
print(f"67 unique 64x64 transparent PNGs: {total:,} bytes total; CRC, alpha, hashes and sizes verified")

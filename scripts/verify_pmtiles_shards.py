#!/usr/bin/env python3
"""Verify that static shards reconstruct the exact logical PMTiles archive."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("shard_dir", type=Path)
    args = parser.parse_args()
    manifest = json.loads((args.shard_dir / "manifest.json").read_text(encoding="utf-8"))
    digest = hashlib.sha256()
    size = 0
    for chunk in manifest["chunks"]:
        payload = (args.shard_dir / chunk["name"]).read_bytes()
        if len(payload) != chunk["size"]:
            raise RuntimeError(f"Ukuran shard salah: {chunk['name']}")
        digest.update(payload)
        size += len(payload)
    if size != manifest["archive_size"]:
        raise RuntimeError(f"Ukuran arsip salah: {size}")
    if digest.hexdigest() != manifest["archive_sha256"]:
        raise RuntimeError("SHA-256 arsip hasil rekonstruksi tidak cocok")
    print(json.dumps({"ok": True, "archive_size": size, "sha256": digest.hexdigest()}))


if __name__ == "__main__":
    main()

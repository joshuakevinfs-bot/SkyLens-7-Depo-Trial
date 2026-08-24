#!/usr/bin/env python3
"""Split a PMTiles archive into static-hosting-friendly immutable shards.

The logical byte offsets are unchanged.  The browser custom Source reassembles
only requested ranges, so PMTiles directory/tile semantics remain intact while
GitHub Pages can serve small cacheable objects.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("archive", type=Path)
    parser.add_argument("output_dir", type=Path)
    parser.add_argument("--chunk-size", type=int, default=700 * 1024)
    args = parser.parse_args()

    args.output_dir.mkdir(parents=True, exist_ok=True)
    digest = hashlib.sha256()
    chunks = []
    total = 0

    with args.archive.open("rb") as source:
        index = 0
        while True:
            payload = source.read(args.chunk_size)
            if not payload:
                break
            digest.update(payload)
            name = f"{index:05d}.bin"
            (args.output_dir / name).write_bytes(payload)
            chunks.append({"name": name, "size": len(payload)})
            total += len(payload)
            index += 1

    manifest = {
        "format": "pmtiles-shards-v1",
        "archive_name": args.archive.name,
        "archive_size": total,
        "archive_sha256": digest.hexdigest(),
        "chunk_size": args.chunk_size,
        "chunks": chunks,
    }
    (args.output_dir / "manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps({**manifest, "chunks": len(chunks)}, indent=2))


if __name__ == "__main__":
    main()

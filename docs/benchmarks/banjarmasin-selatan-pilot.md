# PMTiles pilot benchmark — Banjarmasin Selatan

Generated: 2026-08-24T02:43:57.765Z

| Metric | Legacy embedded gzip | Tippecanoe + sharded PMTiles |
|---|---:|---:|
| Full artifact | 15.60 MB | 27.38 MB |
| Initial/overview bytes read | 15.60 MB | 0.68 MB |
| Close 3×3 viewport cumulative | 15.60 MB | 1.37 MB |
| Initial decode/load | 803.2 ms | 13.6 ms |
| RSS increase | 155.49 MB | 6.19 MB |

The PMTiles artifact is 75.5% larger on disk because it contains indexed, independently retrievable tiles. Runtime delivery is the win: overview transfer drops 95.6% and the close 3×3 viewport remains 91.2% below the legacy all-at-once payload.

FPS is displayed live in the dashboard during the scripted pan/zoom benchmark. Browser and GPU choice materially affect that measurement, so it is intentionally not fabricated by this Node benchmark.

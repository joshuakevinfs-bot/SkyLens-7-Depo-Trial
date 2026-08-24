# Tippecanoe + PMTiles architecture

## Pilot scope

Depot pilot: **Banjarmasin Selatan**.

- 999 opportunity cells, including 18 pilot cells.
- 553,454 Open Buildings roof polygons.
- Opportunity is tiled at zoom 4–16.
- Individual roofs exist only at zoom 16; MapLibre overzooms those vector tiles up to zoom 20.
- The Opportunity Model values and pilot rule are copied unchanged from dashboard v5.

## Runtime path

```text
dashboard v5 + ATAP ZIP
  -> deterministic NDJSON conversion
  -> Tippecanoe
  -> one logical PMTiles v3 archive per depot
  -> immutable 700 KiB shards for free static hosting
  -> PMTiles custom Source
  -> MapLibre viewport-only rendering
```

The shard layer is a GitHub Pages compatibility adapter. It preserves PMTiles byte offsets and SHA-256 identity. On object storage or a CDN with HTTP Range support, serve the original `.pmtiles` file directly and remove the adapter.

## Zoom contract

| Zoom | Visible data | Delivery rule |
|---|---|---|
| 4–11 | Opportunity overview | Low-detail opportunity tiles only |
| 12–15 | Depot/city opportunity | More detailed opportunity cells |
| 16–20 | Individual roofs | Building geometry and interaction enabled |

Building properties preserved in the vector tile are `kelas`, `luas_m2`, `center_lat`, and `center_lon`. They drive hover/click, Google Maps, and Street View links in both Command Center and Field App.

## Scale-out contract

For seven depots, produce one building archive per depot and lazy-load only the selected depot. A national view should use a separate small national opportunity archive; never combine national roofs into one initial request.

```text
opportunity-national.pmtiles
buildings-jambi.pmtiles
buildings-kudus.pmtiles
buildings-tulung-agung.pmtiles
buildings-banjarbaru.pmtiles
buildings-banjarmasin-selatan.pmtiles
buildings-kendari.pmtiles
buildings-denpasar.pmtiles
```

This repository publishes only the Banjarmasin Selatan pilot until the live browser gate is accepted. Raw RO P3M, outlet identities, GPS, sales roster, and transactions are never published.

## Rebuild

Tippecanoe 2.79.0 was used for the pilot. With `tippecanoe` on `PATH`:

```bash
scripts/build_depot_pmtiles.sh \
  'BANJARMASIN SELATAN' \
  SkyLens_7Depot_Pilot_v5_Standalone.html \
  'ATAP 7 DEPO.zip' \
  build/banjarmasin-selatan
```

The same command accepts every depot key supported by `scripts/build_pmtiles.py`.

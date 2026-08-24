#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "Usage: $0 'DEPOT NAME' dashboard.html 'ATAP 7 DEPO.zip' output-dir" >&2
  exit 2
fi

depot="$1"
dashboard="$2"
roof_zip="$3"
output_dir="$4"
tippecanoe_bin="${TIPPECANOE_BIN:-tippecanoe}"
slug="$(printf '%s' "$depot" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')"

mkdir -p "$output_dir/source" "$output_dir/shards/$slug"
python3 scripts/build_pmtiles.py \
  --depot "$depot" \
  --dashboard-html "$dashboard" \
  --roof-zip "$roof_zip" \
  --output-dir "$output_dir/source"

"$tippecanoe_bin" \
  -q -P -f \
  -o "$output_dir/$slug.pmtiles" \
  -Z4 -z16 \
  --no-feature-limit \
  --no-tile-size-limit \
  --no-tiny-polygon-reduction-at-maximum-zoom \
  "$output_dir/source/$slug-opportunity.ndjson" \
  "$output_dir/source/$slug-buildings.ndjson"

python3 scripts/shard_pmtiles.py \
  "$output_dir/$slug.pmtiles" \
  "$output_dir/shards/$slug"

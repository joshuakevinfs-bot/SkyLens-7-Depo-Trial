#!/usr/bin/env python3
"""Build SkyLens vector-tile inputs without changing model outputs.

The supplied roof archive stores each depot as two base64 fragments of one
gzipped, line-oriented custom geometry stream.  This script decodes that
stream, reconstructs the original roof polygons, and writes newline-delimited
GeoJSON that Tippecanoe can consume in parallel.

Opportunity cells are copied verbatim from the embedded dashboard artifact.
Only their delivery format changes: the grid rule, status, scores, estimates,
and pilot threshold remain untouched.
"""

from __future__ import annotations

import argparse
import base64
import gzip
import io
import json
import math
import re
import zipfile
from pathlib import Path


ROOF_PARTS = {
    "JAMBI": [("atap_part1_jambi.txt", "atap_part2_jambi.txt")],
    "KUDUS": [("atap_part1_kudus.txt", "atap_part2_kudus.txt")],
    "TULUNG AGUNG": [("atap_part1_tulungagung.txt", "atap_part2_tulungagung.txt")],
    "BANJARBARU": [
        ("atap_part1_banjarbaru_rural.txt", "atap_part2_banjarbaru_rural.txt"),
        ("atap_part1_banjarbaru_urban.txt", "atap_part2_banjarbaru_urban.txt"),
    ],
    "BANJARMASIN SELATAN": [
        ("atap_part1_banjarmasinselatan.txt", "atap_part2_banjarmasinselatan.txt")
    ],
    "KENDARI": [("atap_part1_kendari.txt", "atap_part2_kendari.txt")],
    "DENPASAR": [("atap_part1_denpasar_v2.txt", "atap_part2_denpasar_v2.txt")],
}

CLASS_NAMES = {
    0: "Terlalu kecil / noise",
    1: "Rumah / ruko",
    2: "Gudang / bangunan besar",
}

STATUS_NAMES = {
    "K": "Kurang digarap",
    "W": "Whitespace",
    "T": "Tergarap",
}

METERS_TO_DEGREES = 1 / 111_320
DECIMETER_TO_METERS = 0.1


def compact_feature(geometry: dict, properties: dict, *, layer: str, minzoom: int, maxzoom: int, feature_id: int) -> str:
    feature = {
        "type": "Feature",
        "id": feature_id,
        "tippecanoe": {"layer": layer, "minzoom": minzoom, "maxzoom": maxzoom},
        "properties": properties,
        "geometry": geometry,
    }
    return json.dumps(feature, ensure_ascii=False, separators=(",", ":"))


def load_embedded_depot(html_path: Path, depot: str) -> dict:
    html = html_path.read_text(encoding="utf-8")
    match = re.search(r"const DDATA_B64 = (\{.*\});\n// Banjarbaru", html)
    if not match:
        raise RuntimeError("DDATA_B64 tidak ditemukan di dashboard artifact")
    encoded = json.loads(match.group(1))[depot]
    return json.loads(gzip.decompress(base64.b64decode(encoded)))


def write_opportunity(depot_data: dict, output_path: Path) -> dict:
    grid_size = float(depot_data["S"])
    status_counts = {"K": 0, "W": 0, "T": 0}
    pilots = 0

    with output_path.open("w", encoding="utf-8") as out:
        for zone in depot_data["zona"]:
            lat, lon, gx, gy = float(zone[0]), float(zone[1]), int(zone[2]), int(zone[3])
            status = zone[10]
            peluang_a = float(zone[7])
            key_petak = gx * 100_000 + gy
            is_pilot = status == "K" and peluang_a >= 0.40
            south = math.floor(lat / grid_size) * grid_size
            west = math.floor(lon / grid_size) * grid_size
            ring = [
                [west, south],
                [west + grid_size, south],
                [west + grid_size, south + grid_size],
                [west, south + grid_size],
                [west, south],
            ]
            properties = {
                "key_petak": key_petak,
                "status": status,
                "building_count": int(zone[4]),
                "big_building_count": int(zone[5]),
                "registered_outlets": int(zone[6]),
                "peluang_a": peluang_a,
                "est_outlet": float(zone[8]),
                "est_tier_a": float(zone[9]),
                "desa": zone[11] or "-",
                "kecamatan": zone[12] or "-",
                "pilot": is_pilot,
                "center_lat": lat,
                "center_lon": lon,
            }
            out.write(compact_feature(
                {"type": "Polygon", "coordinates": [ring]},
                properties,
                layer="opportunity",
                minzoom=4,
                maxzoom=16,
                feature_id=key_petak,
            ) + "\n")
            status_counts[status] = status_counts.get(status, 0) + 1
            pilots += int(is_pilot)

    return {
        "features": len(depot_data["zona"]),
        "pilots": pilots,
        "status": status_counts,
        "bytes": output_path.stat().st_size,
    }


def write_pilot_tasks(depot_data: dict, depot: str, output_path: Path) -> int:
    tasks = []
    for zone in depot_data["zona"]:
        if zone[10] != "K" or float(zone[7]) < 0.40:
            continue
        gx, gy = int(zone[2]), int(zone[3])
        tasks.append({
            "key_petak": gx * 100_000 + gy,
            "depot": depot,
            "center_lat": float(zone[0]),
            "center_lon": float(zone[1]),
            "building_count": int(zone[4]),
            "big_building_count": int(zone[5]),
            "registered_outlets": int(zone[6]),
            "peluang_a": float(zone[7]),
            "est_outlet": float(zone[8]),
            "est_tier_a": float(zone[9]),
            "desa": zone[11] or "-",
            "kecamatan": zone[12] or "-",
        })
    tasks.sort(key=lambda item: (-item["peluang_a"], item["key_petak"]))
    output_path.write_text(json.dumps(tasks, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    return len(tasks)


def polygon_area_m2(offsets: list[tuple[float, float]]) -> float:
    twice_area = 0.0
    for index, (x1, y1) in enumerate(offsets):
        x2, y2 = offsets[(index + 1) % len(offsets)]
        twice_area += x1 * y2 - x2 * y1
    return abs(twice_area / 2) / 100


def roof_lines(archive: zipfile.ZipFile, first_name: str, second_name: str):
    encoded = archive.read(first_name) + archive.read(second_name)
    compressed = base64.b64decode(encoded)
    with gzip.GzipFile(fileobj=io.BytesIO(compressed)) as stream:
        for raw_line in stream:
            line = raw_line.decode("utf-8").strip()
            if line:
                yield line


def write_roofs(zip_path: Path, depot: str, output_path: Path) -> dict:
    count = 0
    class_counts: dict[int, int] = {}
    min_area = None
    max_area = None

    with zipfile.ZipFile(zip_path) as archive, output_path.open("w", encoding="utf-8") as out:
        for first_name, second_name in ROOF_PARTS[depot]:
            for line in roof_lines(archive, first_name, second_name):
                values = line.split(",")
                center_lat, center_lon = float(values[0]), float(values[1])
                roof_class = int(values[2])
                cos_lat = math.cos(math.radians(center_lat))
                offsets = []
                ring = []
                for index in range(3, len(values), 2):
                    dx_dm, dy_dm = float(values[index]), float(values[index + 1])
                    offsets.append((dx_dm, dy_dm))
                    dx_m, dy_m = dx_dm * DECIMETER_TO_METERS, dy_dm * DECIMETER_TO_METERS
                    ring.append([
                        center_lon + dx_m * METERS_TO_DEGREES / cos_lat,
                        center_lat + dy_m * METERS_TO_DEGREES,
                    ])
                if len(ring) < 3:
                    continue
                if ring[0] != ring[-1]:
                    ring.append(ring[0])
                area = polygon_area_m2(offsets)
                properties = {
                    "kelas": roof_class,
                    "luas_m2": round(area, 1),
                    "center_lat": center_lat,
                    "center_lon": center_lon,
                }
                out.write(compact_feature(
                    {"type": "Polygon", "coordinates": [ring]},
                    properties,
                    layer="buildings",
                    minzoom=16,
                    maxzoom=16,
                    feature_id=count + 1,
                ) + "\n")
                count += 1
                class_counts[roof_class] = class_counts.get(roof_class, 0) + 1
                min_area = area if min_area is None else min(min_area, area)
                max_area = area if max_area is None else max(max_area, area)

    return {
        "features": count,
        "class_counts": class_counts,
        "min_area_m2": round(min_area or 0, 2),
        "max_area_m2": round(max_area or 0, 2),
        "bytes": output_path.stat().st_size,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--depot", required=True, choices=sorted(ROOF_PARTS))
    parser.add_argument("--dashboard-html", required=True, type=Path)
    parser.add_argument("--roof-zip", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args()

    args.output_dir.mkdir(parents=True, exist_ok=True)
    slug = args.depot.lower().replace(" ", "-")
    opportunity_path = args.output_dir / f"{slug}-opportunity.ndjson"
    buildings_path = args.output_dir / f"{slug}-buildings.ndjson"
    manifest_path = args.output_dir / f"{slug}-source-manifest.json"
    pilot_tasks_path = args.output_dir / f"{slug}-pilot-tasks.json"

    depot_data = load_embedded_depot(args.dashboard_html, args.depot)
    opportunity_stats = write_opportunity(depot_data, opportunity_path)
    building_stats = write_roofs(args.roof_zip, args.depot, buildings_path)
    pilot_task_count = write_pilot_tasks(depot_data, args.depot, pilot_tasks_path)
    manifest = {
        "schema_version": 1,
        "depot": args.depot,
        "grid_size_degrees": depot_data["S"],
        "model_logic_changed": False,
        "pilot_rule": "status=K AND peluang_a>=0.40",
        "pilot_tasks": pilot_task_count,
        "tippecanoe_layers": {
            "opportunity": {"minzoom": 4, "maxzoom": 16, **opportunity_stats},
            "buildings": {"minzoom": 16, "maxzoom": 16, **building_stats},
        },
    }
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

import * as maplibregl from "maplibre-gl";
import { PMTiles, Protocol } from "pmtiles";
import "maplibre-gl/dist/maplibre-gl.css";
import "./app.css";
import { loadShardedManifest, ShardedPMTilesSource } from "./sharded-pmtiles.js";

const DEPOT_CENTER = [114.5347, -3.2032];
const ARCHIVE_KEY = "skylens-banjarmasin-selatan";
const startedAt = performance.now();

const metrics = {
  fetchedBytes: 0,
  fetchedChunks: 0,
};

const formatBytes = (bytes) => {
  if (!Number.isFinite(bytes)) return "—";
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 ** 2) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / 1024 ** 2).toFixed(2)} MB`;
};

function updateMetrics() {
  const bytes = document.querySelector("#metricBytes");
  if (bytes) bytes.textContent = `${formatBytes(metrics.fetchedBytes)} · ${metrics.fetchedChunks} shard`;
  const heap = document.querySelector("#metricHeap");
  if (heap && performance.memory) heap.textContent = formatBytes(performance.memory.usedJSHeapSize);
}

const { manifestUrl, manifest } = await loadShardedManifest("data/pmtiles/banjarmasin-selatan/manifest.json");
const shardedSource = new ShardedPMTilesSource(new URL("./", manifestUrl).href, manifest, ARCHIVE_KEY, (bytes) => {
  metrics.fetchedBytes += bytes;
  metrics.fetchedChunks += 1;
  updateMetrics();
});
const archive = new PMTiles(shardedSource);
const protocol = new Protocol({ metadata: true });
protocol.add(archive);
maplibregl.addProtocol("pmtiles", protocol.tile);

const map = new maplibregl.Map({
  container: "map",
  center: DEPOT_CENTER,
  zoom: 10.3,
  minZoom: 4,
  maxZoom: 20,
  attributionControl: false,
  style: {
    version: 8,
    sources: {
      osm: {
        type: "raster",
        tiles: ["https://tile.openstreetmap.org/{z}/{x}/{y}.png"],
        tileSize: 256,
        attribution: "© OpenStreetMap contributors",
      },
      skylens: {
        type: "vector",
        url: `pmtiles://${ARCHIVE_KEY}`,
        attribution: "Google Open Buildings · SkyLens Opportunity Model",
      },
    },
    layers: [
      { id: "basemap", type: "raster", source: "osm", paint: { "raster-saturation": -0.7, "raster-brightness-max": 0.72, "raster-contrast": 0.1 } },
      {
        id: "opportunity-fill",
        type: "fill",
        source: "skylens",
        "source-layer": "opportunity",
        paint: {
          "fill-color": [
            "match", ["get", "status"],
            "K", "#e34b4b",
            "T", "#2cc884",
            ["case", [">=", ["get", "building_count"], 300], "#ef8f3b", [">=", ["get", "building_count"], 100], "#f2c94c", "#8d9b98"],
          ],
          "fill-opacity": ["interpolate", ["linear"], ["zoom"], 4, 0.62, 14, 0.32, 16, 0.08],
        },
      },
      {
        id: "opportunity-line",
        type: "line",
        source: "skylens",
        "source-layer": "opportunity",
        paint: {
          "line-color": ["case", ["==", ["get", "pilot"], true], "#0b0e0d", ["match", ["get", "status"], "K", "#c73535", "T", "#13875a", "#aa9c61"]],
          "line-width": ["case", ["==", ["get", "pilot"], true], 2.8, 0.7],
          "line-opacity": ["interpolate", ["linear"], ["zoom"], 4, 0.7, 16, 0.45],
        },
      },
      {
        id: "buildings-fill",
        type: "fill",
        source: "skylens",
        "source-layer": "buildings",
        minzoom: 16,
        paint: {
          "fill-color": ["match", ["get", "kelas"], 0, "#a8b5b1", 2, "#f2c94c", "#39d49e"],
          "fill-opacity": ["interpolate", ["linear"], ["zoom"], 16, 0.55, 19, 0.78],
        },
      },
      {
        id: "buildings-line",
        type: "line",
        source: "skylens",
        "source-layer": "buildings",
        minzoom: 16,
        paint: {
          "line-color": ["match", ["get", "kelas"], 0, "#7d8c88", 2, "#c99b1c", "#157a59"],
          "line-width": ["interpolate", ["linear"], ["zoom"], 16, 0.25, 20, 1.2],
        },
      },
    ],
  },
});

map.addControl(new maplibregl.NavigationControl({ showCompass: false }), "bottom-right");
map.addControl(new maplibregl.AttributionControl({ compact: true }), "bottom-right");

const className = (value) => ({ 0: "Terlalu kecil / noise", 1: "Rumah / ruko", 2: "Gudang / bangunan besar" }[Number(value)] || "Bangunan");
const statusName = (value) => ({ K: "Kurang digarap", W: "Whitespace", T: "Tergarap" }[value] || value);
const numberId = (value, digits = 0) => Number(value).toLocaleString("id-ID", { maximumFractionDigits: digits });

function popupActions(lat, lon, streetView = false) {
  const maps = `https://www.google.com/maps?q=${lat},${lon}`;
  const street = `https://www.google.com/maps/@?api=1&map_action=pano&viewpoint=${lat},${lon}`;
  return `<div class="popup-actions"><a target="_blank" rel="noopener" href="${maps}">Google Maps</a>${streetView ? `<a target="_blank" rel="noopener" href="${street}">Street View</a>` : ""}</div>`;
}

function buildingPopup(properties) {
  return `<div class="popup-title">Bangunan · ${className(properties.kelas)}</div>
    <div class="popup-row"><span>Perkiraan luas</span><b>${numberId(properties.luas_m2)} m²</b></div>
    <div class="popup-row"><span>Kelas</span><b>${className(properties.kelas)}</b></div>
    ${popupActions(properties.center_lat, properties.center_lon, true)}`;
}

function opportunityPopup(properties) {
  return `<div class="popup-title">${properties.desa} · Kec. ${properties.kecamatan}${properties.pilot ? " · PILOT" : ""}</div>
    <div class="popup-row"><span>Status</span><b>${statusName(properties.status)}</b></div>
    <div class="popup-row"><span>Key petak</span><b>${properties.key_petak}</b></div>
    <div class="popup-row"><span>Bangunan</span><b>${numberId(properties.building_count)}</b></div>
    <div class="popup-row"><span>Bangunan besar</span><b>${numberId(properties.big_building_count)}</b></div>
    <div class="popup-row"><span>Toko terdaftar</span><b>${numberId(properties.registered_outlets)}</b></div>
    <div class="popup-row"><span>Peluang Tier A</span><b>${numberId(properties.peluang_a * 100)}%</b></div>
    <div class="popup-row"><span>Perkiraan outlet</span><b>${numberId(properties.est_outlet, 1)}</b></div>
    <div class="popup-row"><span>Perkiraan Tier A</span><b>${numberId(properties.est_tier_a, 1)}</b></div>
    ${popupActions(properties.center_lat, properties.center_lon)}`;
}

const hoverCard = document.querySelector("#hoverCard");
let hoverFeature = null;

map.on("mousemove", (event) => {
  const layers = map.getZoom() >= 16 ? ["buildings-fill", "opportunity-fill"] : ["opportunity-fill"];
  const feature = map.queryRenderedFeatures(event.point, { layers })[0];
  if (!feature) {
    hoverCard.hidden = true;
    map.getCanvas().style.cursor = "";
    hoverFeature = null;
    return;
  }
  map.getCanvas().style.cursor = "pointer";
  hoverFeature = feature;
  hoverCard.hidden = false;
  hoverCard.style.left = `${Math.min(event.point.x + 16, map.getContainer().clientWidth - 275)}px`;
  hoverCard.style.top = `${Math.max(70, event.point.y - 10)}px`;
  hoverCard.innerHTML = feature.layer.id.startsWith("buildings")
    ? `<strong>${className(feature.properties.kelas)}</strong><span>±${numberId(feature.properties.luas_m2)} m² · klik untuk Maps/Street View</span>`
    : `<strong>${feature.properties.desa} · ${statusName(feature.properties.status)}</strong><span>${numberId(feature.properties.building_count)} bangunan · peluang A ${numberId(feature.properties.peluang_a * 100)}%</span>`;
});

map.on("click", (event) => {
  const layers = map.getZoom() >= 16 ? ["buildings-fill", "opportunity-fill"] : ["opportunity-fill"];
  const feature = map.queryRenderedFeatures(event.point, { layers })[0] || hoverFeature;
  if (!feature) return;
  const html = feature.layer.id.startsWith("buildings") ? buildingPopup(feature.properties) : opportunityPopup(feature.properties);
  new maplibregl.Popup({ maxWidth: "320px" }).setLngLat(event.lngLat).setHTML(html).addTo(map);
});

function setLayerVisibility(ids, visible) {
  ids.forEach((id) => map.getLayer(id) && map.setLayoutProperty(id, "visibility", visible ? "visible" : "none"));
}

document.querySelector("#toggleOpportunity").addEventListener("change", (event) => setLayerVisibility(["opportunity-fill", "opportunity-line"], event.target.checked));
document.querySelector("#toggleBuildings").addEventListener("change", (event) => setLayerVisibility(["buildings-fill", "buildings-line"], event.target.checked));
document.querySelector("#togglePilot").addEventListener("change", (event) => {
  const filter = event.target.checked ? ["==", ["get", "pilot"], true] : null;
  map.setFilter("opportunity-fill", filter);
  map.setFilter("opportunity-line", filter);
});
document.querySelector("#homeView").addEventListener("click", () => map.easeTo({ center: DEPOT_CENTER, zoom: 10.3, duration: 900 }));

function updateMode() {
  const zoom = map.getZoom();
  document.querySelector("#zoomLabel").textContent = `Zoom ${zoom.toFixed(1)}`;
  document.querySelector("#modeLabel").textContent = zoom >= 16 ? "Individual building mode" : "Opportunity overview";
  document.querySelector("#modeHint").textContent = zoom >= 16 ? "Hover atau klik atap untuk luas, kelas, Maps, dan Street View." : "Zoom mendekat sampai 16 untuk membuka detail atap.";
  updateMetrics();
}
map.on("zoom", updateMode);

map.once("idle", () => {
  document.querySelector("#metricLoad").textContent = `${Math.round(performance.now() - startedAt)} ms`;
  updateMetrics();
});

document.querySelector("#runBenchmark").addEventListener("click", async (event) => {
  const button = event.currentTarget;
  button.disabled = true;
  button.textContent = "Mengukur…";
  const fpsLabel = document.querySelector("#metricFps");
  const original = { center: map.getCenter(), zoom: map.getZoom() };
  let frames = 0;
  let running = true;
  const countFrame = () => { if (running) { frames += 1; requestAnimationFrame(countFrame); } };
  requestAnimationFrame(countFrame);
  const start = performance.now();
  map.easeTo({ center: [original.center.lng + 0.035, original.center.lat + 0.018], zoom: Math.min(17.2, Math.max(16.2, original.zoom + 1)), duration: 1900 });
  await new Promise((resolve) => setTimeout(resolve, 2000));
  map.easeTo({ center: [original.center.lng - 0.025, original.center.lat - 0.012], zoom: Math.max(16, original.zoom), duration: 1900 });
  await new Promise((resolve) => setTimeout(resolve, 2000));
  running = false;
  const seconds = (performance.now() - start) / 1000;
  fpsLabel.textContent = `${(frames / seconds).toFixed(1)} FPS`;
  button.disabled = false;
  button.textContent = "Ulangi tes pan/zoom";
  updateMetrics();
});

updateMode();

import * as maplibregl from "maplibre-gl";
import { PMTiles, Protocol } from "pmtiles";
import "maplibre-gl/dist/maplibre-gl.css";
import "./field.css";
import { loadShardedManifest, ShardedPMTilesSource } from "./sharded-pmtiles.js";

const STORAGE_KEY = "skylens_field_preview_v1";
const ARCHIVE_KEY = "skylens-field-banjarmasin-selatan";
const { manifestUrl, manifest } = await loadShardedManifest("data/pmtiles/banjarmasin-selatan/manifest.json");
const archive = new PMTiles(new ShardedPMTilesSource(new URL("./", manifestUrl).href, manifest, ARCHIVE_KEY));
const protocol = new Protocol({ metadata: true });
protocol.add(archive);
maplibregl.addProtocol("pmtiles", protocol.tile);
const tasks = await fetch(`${import.meta.env.BASE_URL}data/pilot-tasks.json`).then((response) => response.json());
let state = JSON.parse(localStorage.getItem(STORAGE_KEY) || "{}") || {};
let activeTask = null;
let activeFilter = "all";
let fieldMap = null;
let watchId = null;
let lastPosition = null;
let dwellCell = null;
let dwellStartedAt = null;
let dwellTimer = null;

const saveState = () => localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
const progressFor = (key) => state[key] || { cells: [], findings: [] };
const statusFor = (key) => progressFor(key).cells.length >= 16 ? "done" : progressFor(key).cells.length ? "active" : "open";
const formatScore = (value) => `${Math.round(value * 100)}%`;

function renderTasks() {
  const query = document.querySelector("#taskSearch").value.trim().toLowerCase();
  const filtered = tasks.filter((task) => {
    const status = statusFor(task.key_petak);
    const matchesFilter = activeFilter === "all" || (activeFilter === "done" ? status === "done" : status !== "done");
    const text = `${task.desa} ${task.kecamatan} ${task.key_petak}`.toLowerCase();
    return matchesFilter && text.includes(query);
  });
  document.querySelector("#doneCount").textContent = tasks.filter((task) => progressFor(task.key_petak).cells.length > 0).length;
  document.querySelector("#taskList").innerHTML = filtered.map((task) => {
    const progress = progressFor(task.key_petak);
    const status = statusFor(task.key_petak);
    return `<button class="task-card ${status}" data-key="${task.key_petak}">
      <span class="task-rank">${formatScore(task.peluang_a)}</span>
      <div><strong>${task.desa}</strong><small>Kec. ${task.kecamatan} · ${task.key_petak}</small><em>${task.building_count.toLocaleString("id-ID")} bangunan · est. ${task.est_outlet} outlet</em></div>
      <div class="task-progress"><b>${progress.cells.length}/16</b><i><span style="width:${progress.cells.length / 16 * 100}%"></span></i></div>
    </button>`;
  }).join("") || `<p class="empty-tasks">Tidak ada tugas yang cocok.</p>`;
  document.querySelectorAll(".task-card").forEach((button) => button.addEventListener("click", () => openTask(Number(button.dataset.key))));
}

function gridGeoJSON(task) {
  const size = 0.01;
  const south = Math.floor(task.center_lat / size) * size;
  const west = Math.floor(task.center_lon / size) * size;
  const step = size / 4;
  const progress = progressFor(task.key_petak);
  const features = [];
  for (let row = 0; row < 4; row += 1) {
    for (let col = 0; col < 4; col += 1) {
      const id = row * 4 + col;
      const x1 = west + col * step;
      const y1 = south + row * step;
      features.push({
        type: "Feature",
        properties: { id, label: String(id + 1), done: progress.cells.includes(id) },
        geometry: { type: "Polygon", coordinates: [[[x1,y1],[x1+step,y1],[x1+step,y1+step],[x1,y1+step],[x1,y1]]] },
      });
    }
  }
  return { type: "FeatureCollection", features };
}

function initMap() {
  fieldMap = new maplibregl.Map({
    container: "fieldMap",
    center: [activeTask.center_lon, activeTask.center_lat],
    zoom: 15.5,
    maxZoom: 20,
    attributionControl: false,
    style: {
      version: 8,
      sources: {
        osm: { type: "raster", tiles: ["https://tile.openstreetmap.org/{z}/{x}/{y}.png"], tileSize: 256, attribution: "© OpenStreetMap contributors" },
        skylens: { type: "vector", url: `pmtiles://${ARCHIVE_KEY}` },
      },
      layers: [
        { id: "osm", type: "raster", source: "osm", paint: { "raster-saturation": -0.55, "raster-brightness-max": 0.78 } },
        { id: "field-buildings-fill", type: "fill", source: "skylens", "source-layer": "buildings", minzoom: 16, paint: { "fill-color": ["match", ["get", "kelas"], 0, "#a8b5b1", 2, "#f2c94c", "#39d49e"], "fill-opacity": .56 } },
        { id: "field-buildings-line", type: "line", source: "skylens", "source-layer": "buildings", minzoom: 16, paint: { "line-color": "#126c51", "line-width": ["interpolate", ["linear"], ["zoom"], 16, .25, 20, 1.1] } },
      ],
    },
  });
  fieldMap.addControl(new maplibregl.NavigationControl({ showCompass: false }), "bottom-right");
  fieldMap.on("load", () => {
    fieldMap.addSource("sweep", { type: "geojson", data: gridGeoJSON(activeTask), generateId: true });
    fieldMap.addLayer({ id: "sweep-fill", type: "fill", source: "sweep", paint: { "fill-color": ["case", ["get", "done"], "#3ce2ac", "#f2c94c"], "fill-opacity": ["case", ["get", "done"], .38, .16] } });
    fieldMap.addLayer({ id: "sweep-line", type: "line", source: "sweep", paint: { "line-color": ["case", ["get", "done"], "#1aa67b", "#d7a91e"], "line-width": 2 } });
    fieldMap.addLayer({ id: "sweep-label", type: "symbol", source: "sweep", layout: { "text-field": ["get", "label"], "text-size": 12 }, paint: { "text-color": "#10231f", "text-halo-color": "#ffffff", "text-halo-width": 1.5 } });
  });
  fieldMap.on("click", "field-buildings-fill", (event) => {
    const building = event.features?.[0]?.properties;
    if (!building) return;
    const maps = `https://www.google.com/maps?q=${building.center_lat},${building.center_lon}`;
    const street = `https://www.google.com/maps/@?api=1&map_action=pano&viewpoint=${building.center_lat},${building.center_lon}`;
    new maplibregl.Popup({ maxWidth: "280px" }).setLngLat(event.lngLat).setHTML(
      `<strong>Atap ${Number(building.luas_m2).toLocaleString("id-ID")} m²</strong><br>Kelas ${building.kelas}<div class="field-popup-links"><a href="${maps}" target="_blank" rel="noopener">Maps</a><a href="${street}" target="_blank" rel="noopener">Street View</a></div>`,
    ).addTo(fieldMap);
  });
  fieldMap.on("mouseenter", "field-buildings-fill", () => { fieldMap.getCanvas().style.cursor = "pointer"; });
  fieldMap.on("mouseleave", "field-buildings-fill", () => { fieldMap.getCanvas().style.cursor = ""; });
}

function updateActiveUI() {
  if (!activeTask) return;
  const progress = progressFor(activeTask.key_petak);
  document.querySelector("#activeArea").textContent = `${activeTask.desa} · ${activeTask.kecamatan}`;
  document.querySelector("#activeKey").textContent = `Petak ${activeTask.key_petak}`;
  document.querySelector("#activeScore").textContent = formatScore(activeTask.peluang_a);
  document.querySelector("#cellProgress").textContent = `${progress.cells.length}/16 kotak`;
  document.querySelector("#progressBar").style.width = `${progress.cells.length / 16 * 100}%`;
  document.querySelector("#navigateLink").href = `https://www.google.com/maps/dir/?api=1&destination=${activeTask.center_lat},${activeTask.center_lon}`;
  if (fieldMap?.getSource("sweep")) fieldMap.getSource("sweep").setData(gridGeoJSON(activeTask));
}

function openTask(key) {
  activeTask = tasks.find((task) => task.key_petak === key);
  document.querySelector("#taskScreen").classList.remove("active");
  document.querySelector("#mapScreen").classList.add("active");
  if (!fieldMap) initMap();
  else {
    fieldMap.jumpTo({ center: [activeTask.center_lon, activeTask.center_lat], zoom: 15.5 });
    updateActiveUI();
  }
  updateActiveUI();
}

function closeTask() {
  stopGps();
  document.querySelector("#mapScreen").classList.remove("active");
  document.querySelector("#taskScreen").classList.add("active");
  renderTasks();
}

function cellForPosition(lat, lon) {
  const size = 0.01;
  const south = Math.floor(activeTask.center_lat / size) * size;
  const west = Math.floor(activeTask.center_lon / size) * size;
  if (lat < south || lat >= south + size || lon < west || lon >= west + size) return null;
  const row = Math.min(3, Math.floor((lat - south) / (size / 4)));
  const col = Math.min(3, Math.floor((lon - west) / (size / 4)));
  return row * 4 + col;
}

function completeCell(cell) {
  const progress = progressFor(activeTask.key_petak);
  if (!progress.cells.includes(cell)) progress.cells.push(cell);
  state[activeTask.key_petak] = progress;
  saveState();
  updateActiveUI();
}

function handlePosition(position) {
  lastPosition = position;
  const { latitude, longitude, accuracy } = position.coords;
  if (accuracy > 100) {
    document.querySelector("#dwellHint").textContent = `Akurasi GPS ${Math.round(accuracy)} m terlalu lemah; titik belum dihitung.`;
    return;
  }
  const cell = cellForPosition(latitude, longitude);
  if (cell === null) {
    dwellCell = null;
    dwellStartedAt = null;
    document.querySelector("#dwellHint").textContent = "Lu masih di luar zona pilot.";
    return;
  }
  if (dwellCell !== cell) {
    dwellCell = cell;
    dwellStartedAt = Date.now();
  }
  const elapsed = Math.floor((Date.now() - dwellStartedAt) / 1000);
  document.querySelector("#dwellHint").textContent = `Kotak ${cell + 1} · ${Math.max(0, 45 - elapsed)} detik lagi untuk selesai.`;
  if (elapsed >= 45) completeCell(cell);
  fieldMap.easeTo({ center: [longitude, latitude], duration: 350 });
}

function startGps() {
  if (!navigator.geolocation) return alert("GPS tidak tersedia di browser ini.");
  watchId = navigator.geolocation.watchPosition(handlePosition, (error) => alert(`GPS gagal: ${error.message}`), { enableHighAccuracy: true, maximumAge: 3000, timeout: 15000 });
  dwellTimer = setInterval(() => lastPosition && handlePosition(lastPosition), 1000);
  document.querySelector("#gpsBadge").textContent = "GPS ON";
  document.querySelector("#gpsBadge").classList.add("on");
  document.querySelector("#gpsToggle").textContent = "Stop GPS";
}

function stopGps() {
  if (watchId !== null) navigator.geolocation.clearWatch(watchId);
  clearInterval(dwellTimer);
  watchId = null;
  dwellTimer = null;
  lastPosition = null;
  document.querySelector("#gpsBadge").textContent = "GPS OFF";
  document.querySelector("#gpsBadge").classList.remove("on");
  document.querySelector("#gpsToggle").textContent = "Mulai GPS";
}

document.querySelector("#taskSearch").addEventListener("input", renderTasks);
document.querySelectorAll(".task-filters button").forEach((button) => button.addEventListener("click", () => {
  activeFilter = button.dataset.filter;
  document.querySelectorAll(".task-filters button").forEach((item) => item.classList.toggle("active", item === button));
  renderTasks();
}));
document.querySelector("#backToTasks").addEventListener("click", closeTask);
document.querySelector("#gpsToggle").addEventListener("click", () => watchId === null ? startGps() : stopGps());
document.querySelector("#demoCell").addEventListener("click", () => {
  const progress = progressFor(activeTask.key_petak);
  const next = Array.from({ length: 16 }, (_, index) => index).find((index) => !progress.cells.includes(index));
  if (next !== undefined) completeCell(next);
});
document.querySelector("#openFinding").addEventListener("click", () => document.querySelector("#findingDialog").showModal());
document.querySelector("#findingForm").addEventListener("submit", (event) => {
  if (event.submitter?.value === "cancel") return;
  event.preventDefault();
  const outcome = document.querySelector("#findingOutcome").value;
  if (!outcome) return;
  const progress = progressFor(activeTask.key_petak);
  progress.findings.push({
    outcome,
    name: document.querySelector("#findingName").value.trim(),
    notes: document.querySelector("#findingNotes").value.trim(),
    latitude: lastPosition?.coords.latitude || null,
    longitude: lastPosition?.coords.longitude || null,
    created_at: new Date().toISOString(),
  });
  state[activeTask.key_petak] = progress;
  saveState();
  document.querySelector("#findingDialog").close();
  document.querySelector("#findingForm").reset();
  document.querySelector("#dwellHint").textContent = `Temuan tersimpan lokal (${progress.findings.length} laporan di zona ini).`;
});
document.querySelector("#resetPreview").addEventListener("click", () => {
  if (confirm("Reset seluruh progress preview di perangkat ini?")) {
    state = {};
    saveState();
    renderTasks();
  }
});

renderTasks();

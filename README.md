# SkyLens 7 Depo Trial

Source of truth untuk pilot SkyLens di tujuh depot:

- Jambi
- Kudus
- Tulung Agung
- Banjarbaru
- Banjarmasin Selatan
- Kendari
- Denpasar

Project Supabase: `SkyLens 7 Depo`  
Region: Singapore (`ap-southeast-1`)  
Plan: Free

## Preview PMTiles pilot

- Command Center: `https://joshuakevinfs-bot.github.io/SkyLens-7-Depo-Trial/dashboard/`
- Field App: `https://joshuakevinfs-bot.github.io/SkyLens-7-Depo-Trial/sales/`

Pilot pertama memakai Banjarmasin Selatan: 999 opportunity cells, 18 zona pilot, dan 553.454 polygon atap. Tippecanoe hanya mengubah delivery/visualisasi; nilai Opportunity Model dan rule pilot tidak diubah.

Layer besar disimpan sebagai satu arsip logis PMTiles per depot, lalu dipotong menjadi shard 700 KiB untuk GitHub Pages. Dashboard mengambil tile sesuai viewport. Atap individual baru muncul di zoom 16, dengan hover/click, luas, kelas, Google Maps, dan Street View tetap aktif. Detail desain ada di [PMTiles architecture](docs/pmtiles-architecture.md), sedangkan hasil ukur pilot ada di [benchmark report](docs/benchmarks/banjarmasin-selatan-pilot.md).

```bash
npm ci
npm run check
npm run build
```

> Repository ini publik. Jangan commit data outlet internal, roster sales, GPS, foto, nomor telepon, password, service-role key, atau secret lainnya.

# Arsitektur SkyLens 7 Depo

## Komponen

- **Command Center:** analisis peta, assignment, KPI, validasi temuan, dan monitoring.
- **Field App:** tugas sales, tracking, penyisiran 4×4, foto, serta outcome kunjungan.
- **Supabase:** Auth, database operasional, RLS, dan private storage.
- **Model pipeline:** menghasilkan skor dan estimasi per petak; tidak dijalankan di browser.

## Kontrak grid

```text
S = 0.01 derajat
gx = floor(lon / S)
gy = floor(lat / S)
key_petak = gx * 100000 + gy
```

## Kontrak keputusan awal

```text
outlet terdaftar = 0                    -> whitespace
outlet terdaftar > 0 dan gap >= 3      -> kurang_digarap
gap < 3                                -> tergarap
kurang_digarap dan peluang_A >= 0.40   -> kandidat pilot
```

AUC, Lift, dan Spearman adalah metrik validasi model, bukan aturan pewarnaan petak.

## Aturan data repository publik

Data outlet internal, roster sales, GPS, foto, nomor telepon, raw transaksi, password, secret key, dan service-role key dilarang masuk repository. Frontend hanya memakai publishable key; akses data dikendalikan Auth dan RLS.

update public.model_versions
set active = false
where active = true
  and version <> 'pilot7_v2_nobocor_dashboard_v5';

insert into public.model_versions (
  version,
  trained_at,
  data_vintage,
  algorithm,
  grid_size_degrees,
  pilot_threshold,
  metrics,
  notes,
  active
)
values (
  'pilot7_v2_nobocor_dashboard_v5',
  null,
  null,
  'HistGradientBoostingClassifier + HistGradientBoostingRegressor (quantile 0.75), leave-target-out',
  0.01,
  0.40,
  jsonb_build_object(
    'source_artifact', 'SkyLens_7Depot_Pilot_v5_Standalone.html',
    'source_prediction_file', '_prediksi_7depot_v2_nobocor.csv.gz',
    'raw_zone_rows', 7580,
    'unique_zone_keys', 7426,
    'duplicate_zone_rows', 154,
    'duplicate_scope', 'BANJARBARU_RURAL + BANJARBARU_URBAN overlap',
    'conflicting_duplicate_rows', 24,
    'deduplication_rule', 'same key_petak: keep row with greatest building_count; stable first-row tie break',
    'pilot_zones', 173,
    'pilot_counts', jsonb_build_object(
      'JAMBI',31,'KUDUS',23,'TULUNG_AGUNG',6,'BANJARBARU',4,
      'BANJARMASIN_SELATAN',18,'KENDARI',3,'DENPASAR',88
    ),
    'source_sha256', jsonb_build_object(
      'JAMBI','daec82539d918a2ddf1c0ea0450b0edd6e2157b2c65df7b43a68bc3407089571',
      'KUDUS','d759e8e7be5f39feb39dc6aa25fddedb3c7c415d03e0a8d8889f49d8a5635fd9',
      'TULUNG_AGUNG','382f6e001ef7f3de04f010dcdca89d5c875bc02b2daeadaad83ab0c79b8323b3',
      'BANJARBARU','5b49b1e641b76ff11936b48453712eb7452fdb6435af5536206f6458dc72ae35',
      'BANJARMASIN_SELATAN','ec79f9d04ab97571ddbb163a60d870cded9611d8fb5c0559b4abc5f39015bb29',
      'KENDARI','028b0f6ed3304fc72aca09cef7e9aab1c906d1ba9799530389e4c2ec378d69aa',
      'DENPASAR','d54df88492f4d71e93ca32ee74006e7003709fa15425dd2bc028e7ad5a8ee5d2'
    )
  ),
  'Training timestamp and data vintage are not present in the supplied artifact, so both remain NULL. Pilot rule: status=kurang_digarap and peluang_a>=0.40.',
  true
)
on conflict (version) do update
set algorithm = excluded.algorithm,
    grid_size_degrees = excluded.grid_size_degrees,
    pilot_threshold = excluded.pilot_threshold,
    metrics = excluded.metrics,
    notes = excluded.notes,
    active = excluded.active;

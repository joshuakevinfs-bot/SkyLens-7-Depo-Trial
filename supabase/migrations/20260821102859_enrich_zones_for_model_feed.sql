alter table public.zones
  add column if not exists center_lat double precision,
  add column if not exists center_lon double precision,
  add column if not exists building_count integer not null default 0,
  add column if not exists large_building_count integer not null default 0,
  add column if not exists village_name text,
  add column if not exists district_name text,
  add column if not exists source_row_count smallint not null default 1;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.zones'::regclass
      and conname = 'zones_center_lat_check'
  ) then
    alter table public.zones
      add constraint zones_center_lat_check
      check (center_lat is null or center_lat between -90 and 90);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.zones'::regclass
      and conname = 'zones_center_lon_check'
  ) then
    alter table public.zones
      add constraint zones_center_lon_check
      check (center_lon is null or center_lon between -180 and 180);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.zones'::regclass
      and conname = 'zones_building_counts_check'
  ) then
    alter table public.zones
      add constraint zones_building_counts_check
      check (
        building_count >= 0
        and large_building_count >= 0
        and large_building_count <= building_count
      );
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.zones'::regclass
      and conname = 'zones_source_row_count_check'
  ) then
    alter table public.zones
      add constraint zones_source_row_count_check
      check (source_row_count >= 1);
  end if;
end $$;

create index if not exists zones_depot_district_idx
  on public.zones (depot_id, district_name);

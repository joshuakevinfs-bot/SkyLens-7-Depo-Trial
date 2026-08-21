begin;

create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated, service_role;

alter default privileges for role postgres in schema public
  revoke select, insert, update, delete on tables from anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke execute on functions from public, anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke usage, select on sequences from anon, authenticated, service_role;

create table public.depots (
  id text primary key,
  name text not null unique,
  region text,
  timezone text not null default 'Asia/Jakarta',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint depots_id_format check (id ~ '^[A-Z0-9_]+$')
);

create table public.user_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  app_role text not null,
  depot_id text references public.depots(id),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint user_profiles_role check (
    app_role in ('admin_nasional','manager_depot','supervisor','sales','validator')
  ),
  constraint user_profiles_depot_required check (
    app_role = 'admin_nasional' or depot_id is not null
  )
);

create table public.sales (
  id uuid primary key default gen_random_uuid(),
  depot_id text not null references public.depots(id),
  sales_code text not null,
  full_name text not null,
  route_code text,
  user_id uuid unique references auth.users(id) on delete set null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (depot_id, sales_code),
  unique (id, depot_id)
);

create table public.model_versions (
  id uuid primary key default gen_random_uuid(),
  version text not null unique,
  trained_at timestamptz,
  data_vintage date,
  algorithm text,
  grid_size_degrees numeric(6,5) not null default 0.01,
  pilot_threshold numeric(6,5) not null default 0.40,
  metrics jsonb not null default '{}'::jsonb,
  notes text,
  active boolean not null default false,
  created_at timestamptz not null default now(),
  constraint model_threshold_range check (pilot_threshold between 0 and 1),
  constraint model_grid_contract check (grid_size_degrees = 0.01)
);

create table public.zones (
  key_petak bigint primary key,
  depot_id text not null references public.depots(id),
  model_version_id uuid not null references public.model_versions(id),
  grid_x integer not null,
  grid_y integer not null,
  min_lon numeric(10,6) not null,
  min_lat numeric(9,6) not null,
  max_lon numeric(10,6) not null,
  max_lat numeric(9,6) not null,
  status text not null,
  registered_outlets integer not null default 0,
  estimated_outlets numeric(9,2) not null default 0,
  outlet_gap numeric(9,2) generated always as (estimated_outlets - registered_outlets) stored,
  peluang_a numeric(7,6) not null,
  estimated_tier_a numeric(9,2) not null default 0,
  is_pilot boolean not null default false,
  pilot_reason text,
  source text not null default 'model',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (key_petak, depot_id),
  constraint zones_key_contract check (
    key_petak = grid_x::bigint * 100000::bigint + grid_y::bigint
  ),
  constraint zones_bbox_valid check (min_lon < max_lon and min_lat < max_lat),
  constraint zones_status check (status in ('whitespace','kurang_digarap','tergarap')),
  constraint zones_probability check (peluang_a between 0 and 1),
  constraint zones_counts check (
    registered_outlets >= 0 and estimated_outlets >= 0 and estimated_tier_a >= 0
  ),
  constraint zones_source check (source in ('model','manual'))
);

create table public.assignments (
  id uuid primary key default gen_random_uuid(),
  depot_id text not null references public.depots(id),
  zone_key bigint not null references public.zones(key_petak),
  sales_id uuid not null references public.sales(id),
  status text not null default 'assigned',
  priority smallint not null default 3,
  assigned_by uuid not null references auth.users(id),
  assigned_at timestamptz not null default now(),
  due_date date,
  started_at timestamptz,
  completed_at timestamptz,
  canceled_at timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, depot_id),
  constraint assignments_zone_depot_fk
    foreign key (zone_key, depot_id) references public.zones(key_petak, depot_id),
  constraint assignments_sales_depot_fk
    foreign key (sales_id, depot_id) references public.sales(id, depot_id),
  constraint assignments_status check (
    status in ('assigned','in_progress','completed','canceled')
  ),
  constraint assignments_priority check (priority between 1 and 5)
);

create unique index assignments_one_active_zone_idx
  on public.assignments(zone_key)
  where status in ('assigned','in_progress');

create table public.zone_cells (
  assignment_id uuid not null references public.assignments(id) on delete cascade,
  cell_index smallint not null,
  depot_id text not null references public.depots(id),
  status text not null default 'pending',
  dwell_seconds integer not null default 0,
  first_entered_at timestamptz,
  completed_at timestamptz,
  completed_by_sales_id uuid references public.sales(id),
  updated_at timestamptz not null default now(),
  primary key (assignment_id, cell_index),
  constraint zone_cells_assignment_depot_fk
    foreign key (assignment_id, depot_id) references public.assignments(id, depot_id),
  constraint zone_cells_sales_depot_fk
    foreign key (completed_by_sales_id, depot_id) references public.sales(id, depot_id),
  constraint zone_cells_index check (cell_index between 0 and 15),
  constraint zone_cells_status check (status in ('pending','in_progress','completed')),
  constraint zone_cells_dwell check (dwell_seconds >= 0)
);

create table public.location_tracks (
  id bigint generated always as identity primary key,
  depot_id text not null references public.depots(id),
  assignment_id uuid references public.assignments(id) on delete set null,
  sales_id uuid not null references public.sales(id),
  user_id uuid not null references auth.users(id),
  recorded_at timestamptz not null,
  latitude double precision not null,
  longitude double precision not null,
  accuracy_m numeric(8,2),
  speed_mps numeric(8,2),
  heading_deg numeric(6,2),
  event_type text not null default 'breadcrumb',
  received_at timestamptz not null default now(),
  retention_until timestamptz not null default (now() + interval '30 days'),
  constraint location_assignment_depot_fk
    foreign key (assignment_id, depot_id) references public.assignments(id, depot_id),
  constraint location_sales_depot_fk
    foreign key (sales_id, depot_id) references public.sales(id, depot_id),
  constraint location_lat check (latitude between -90 and 90),
  constraint location_lon check (longitude between -180 and 180),
  constraint location_accuracy check (accuracy_m is null or accuracy_m >= 0),
  constraint location_event check (
    event_type in ('breadcrumb','check_in','check_out','stop','resume')
  )
);

create table public.findings (
  id uuid primary key default gen_random_uuid(),
  depot_id text not null references public.depots(id),
  assignment_id uuid references public.assignments(id) on delete set null,
  zone_key bigint not null references public.zones(key_petak),
  sales_id uuid not null references public.sales(id),
  created_by uuid not null references auth.users(id),
  found_at timestamptz not null default now(),
  latitude double precision not null,
  longitude double precision not null,
  gps_accuracy_m numeric(8,2),
  outlet_name text,
  contact_phone text,
  average_purchase_amount numeric(14,2),
  outcome text not null,
  photo_path text,
  notes text,
  recommendation_source text not null default 'model',
  model_version_id uuid references public.model_versions(id),
  verification_status text not null default 'pending',
  verified_by uuid references auth.users(id),
  verified_at timestamptz,
  rejection_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint findings_assignment_depot_fk
    foreign key (assignment_id, depot_id) references public.assignments(id, depot_id),
  constraint findings_zone_depot_fk
    foreign key (zone_key, depot_id) references public.zones(key_petak, depot_id),
  constraint findings_sales_depot_fk
    foreign key (sales_id, depot_id) references public.sales(id, depot_id),
  constraint findings_lat check (latitude between -90 and 90),
  constraint findings_lon check (longitude between -180 and 180),
  constraint findings_accuracy check (gps_accuracy_m is null or gps_accuracy_m >= 0),
  constraint findings_amount check (
    average_purchase_amount is null or average_purchase_amount >= 0
  ),
  constraint findings_outcome check (
    outcome in ('candidate_noo','already_covered','revisit','not_interested','not_a_store','other')
  ),
  constraint findings_source check (recommendation_source in ('model','manual')),
  constraint findings_verification check (
    verification_status in ('pending','verified','rejected')
  )
);

create table public.manual_areas (
  id uuid primary key default gen_random_uuid(),
  depot_id text not null references public.depots(id),
  drawn_by uuid not null references auth.users(id),
  name text,
  reason text not null,
  geojson jsonb not null,
  status text not null default 'pending',
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  review_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint manual_areas_geojson_object check (jsonb_typeof(geojson) = 'object'),
  constraint manual_areas_status check (status in ('pending','approved','rejected','archived'))
);

create index user_profiles_depot_role_idx on public.user_profiles(depot_id, app_role) where active;
create index sales_depot_active_idx on public.sales(depot_id) where active;
create index zones_depot_pilot_idx on public.zones(depot_id, is_pilot, peluang_a desc);
create index zones_model_idx on public.zones(model_version_id);
create index assignments_depot_status_idx on public.assignments(depot_id, status);
create index assignments_sales_status_idx on public.assignments(sales_id, status);
create index zone_cells_depot_status_idx on public.zone_cells(depot_id, status);
create index location_tracks_sales_time_idx on public.location_tracks(sales_id, recorded_at desc);
create index location_tracks_depot_time_idx on public.location_tracks(depot_id, recorded_at desc);
create index location_tracks_recorded_brin_idx on public.location_tracks using brin(recorded_at);
create index location_tracks_retention_idx on public.location_tracks(retention_until);
create index findings_depot_verification_idx on public.findings(depot_id, verification_status, found_at desc);
create index findings_zone_idx on public.findings(zone_key);
create index manual_areas_depot_status_idx on public.manual_areas(depot_id, status);

create or replace function private.current_app_role()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select p.app_role
  from public.user_profiles p
  where p.user_id = (select auth.uid())
    and p.active
  limit 1
$$;

create or replace function private.current_depot_id()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select p.depot_id
  from public.user_profiles p
  where p.user_id = (select auth.uid())
    and p.active
  limit 1
$$;

create or replace function private.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(private.current_app_role() = 'admin_nasional', false)
$$;

create or replace function private.can_access_depot(target_depot_id text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.user_profiles p
    where p.user_id = (select auth.uid())
      and p.active
      and (p.app_role = 'admin_nasional' or p.depot_id = target_depot_id)
  )
$$;

create or replace function private.can_manage_depot(target_depot_id text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.user_profiles p
    where p.user_id = (select auth.uid())
      and p.active
      and (
        p.app_role = 'admin_nasional'
        or (p.depot_id = target_depot_id and p.app_role in ('manager_depot','supervisor'))
      )
  )
$$;

create or replace function private.can_validate_depot(target_depot_id text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.user_profiles p
    where p.user_id = (select auth.uid())
      and p.active
      and (
        p.app_role = 'admin_nasional'
        or (p.depot_id = target_depot_id and p.app_role in ('manager_depot','supervisor','validator'))
      )
  )
$$;

create or replace function private.owns_sales(target_sales_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.sales s
    where s.id = target_sales_id
      and s.user_id = (select auth.uid())
      and s.active
  )
$$;

create or replace function private.owns_assignment(target_assignment_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.assignments a
    join public.sales s on s.id = a.sales_id
    where a.id = target_assignment_id
      and s.user_id = (select auth.uid())
      and s.active
  )
$$;

create or replace function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

revoke all on all functions in schema private from public, anon, authenticated;
grant execute on function private.current_app_role() to authenticated, service_role;
grant execute on function private.current_depot_id() to authenticated, service_role;
grant execute on function private.is_admin() to authenticated, service_role;
grant execute on function private.can_access_depot(text) to authenticated, service_role;
grant execute on function private.can_manage_depot(text) to authenticated, service_role;
grant execute on function private.can_validate_depot(text) to authenticated, service_role;
grant execute on function private.owns_sales(uuid) to authenticated, service_role;
grant execute on function private.owns_assignment(uuid) to authenticated, service_role;

create trigger user_profiles_set_updated_at before update on public.user_profiles
for each row execute function private.set_updated_at();
create trigger sales_set_updated_at before update on public.sales
for each row execute function private.set_updated_at();
create trigger zones_set_updated_at before update on public.zones
for each row execute function private.set_updated_at();
create trigger assignments_set_updated_at before update on public.assignments
for each row execute function private.set_updated_at();
create trigger zone_cells_set_updated_at before update on public.zone_cells
for each row execute function private.set_updated_at();
create trigger findings_set_updated_at before update on public.findings
for each row execute function private.set_updated_at();
create trigger manual_areas_set_updated_at before update on public.manual_areas
for each row execute function private.set_updated_at();

alter table public.depots enable row level security;
alter table public.user_profiles enable row level security;
alter table public.sales enable row level security;
alter table public.model_versions enable row level security;
alter table public.zones enable row level security;
alter table public.assignments enable row level security;
alter table public.zone_cells enable row level security;
alter table public.location_tracks enable row level security;
alter table public.findings enable row level security;
alter table public.manual_areas enable row level security;

create policy depots_select on public.depots
for select to authenticated
using (private.can_access_depot(id));

create policy depots_admin_all on public.depots
for all to authenticated
using (private.is_admin())
with check (private.is_admin());

create policy profiles_select on public.user_profiles
for select to authenticated
using (
  user_id = (select auth.uid())
  or private.is_admin()
  or private.can_manage_depot(depot_id)
);

create policy profiles_admin_insert on public.user_profiles
for insert to authenticated
with check (private.is_admin());

create policy profiles_admin_update on public.user_profiles
for update to authenticated
using (private.is_admin())
with check (private.is_admin());

create policy profiles_admin_delete on public.user_profiles
for delete to authenticated
using (private.is_admin());

create policy sales_select on public.sales
for select to authenticated
using (private.can_access_depot(depot_id));

create policy sales_manage_insert on public.sales
for insert to authenticated
with check (private.can_manage_depot(depot_id));

create policy sales_manage_update on public.sales
for update to authenticated
using (private.can_manage_depot(depot_id))
with check (private.can_manage_depot(depot_id));

create policy sales_manage_delete on public.sales
for delete to authenticated
using (private.can_manage_depot(depot_id));

create policy model_versions_select on public.model_versions
for select to authenticated
using (true);

create policy model_versions_admin_all on public.model_versions
for all to authenticated
using (private.is_admin())
with check (private.is_admin());

create policy zones_select on public.zones
for select to authenticated
using (private.can_access_depot(depot_id));

create policy zones_admin_all on public.zones
for all to authenticated
using (private.is_admin())
with check (private.is_admin());

create policy assignments_select on public.assignments
for select to authenticated
using (
  private.can_manage_depot(depot_id)
  or private.owns_sales(sales_id)
);

create policy assignments_manage_insert on public.assignments
for insert to authenticated
with check (private.can_manage_depot(depot_id));

create policy assignments_manage_update on public.assignments
for update to authenticated
using (private.can_manage_depot(depot_id))
with check (private.can_manage_depot(depot_id));

create policy assignments_manage_delete on public.assignments
for delete to authenticated
using (private.can_manage_depot(depot_id));

create policy zone_cells_select on public.zone_cells
for select to authenticated
using (
  private.can_manage_depot(depot_id)
  or private.owns_assignment(assignment_id)
);

create policy zone_cells_insert on public.zone_cells
for insert to authenticated
with check (
  private.can_manage_depot(depot_id)
  or private.owns_assignment(assignment_id)
);

create policy zone_cells_update on public.zone_cells
for update to authenticated
using (
  private.can_manage_depot(depot_id)
  or private.owns_assignment(assignment_id)
)
with check (
  private.can_manage_depot(depot_id)
  or private.owns_assignment(assignment_id)
);

create policy location_tracks_select on public.location_tracks
for select to authenticated
using (
  private.can_manage_depot(depot_id)
  or user_id = (select auth.uid())
);

create policy location_tracks_insert on public.location_tracks
for insert to authenticated
with check (
  user_id = (select auth.uid())
  and private.owns_sales(sales_id)
  and private.can_access_depot(depot_id)
);

create policy findings_select on public.findings
for select to authenticated
using (
  private.can_validate_depot(depot_id)
  or private.owns_sales(sales_id)
);

create policy findings_insert on public.findings
for insert to authenticated
with check (
  created_by = (select auth.uid())
  and private.owns_sales(sales_id)
  and private.can_access_depot(depot_id)
  and verification_status = 'pending'
  and verified_by is null
  and verified_at is null
);

create policy findings_update on public.findings
for update to authenticated
using (
  private.can_validate_depot(depot_id)
  or (
    created_by = (select auth.uid())
    and verification_status = 'pending'
  )
)
with check (
  private.can_validate_depot(depot_id)
  or (
    created_by = (select auth.uid())
    and private.owns_sales(sales_id)
    and private.can_access_depot(depot_id)
    and verification_status = 'pending'
    and verified_by is null
    and verified_at is null
    and rejection_reason is null
  )
);

create policy findings_delete on public.findings
for delete to authenticated
using (private.can_manage_depot(depot_id));

create policy manual_areas_select on public.manual_areas
for select to authenticated
using (private.can_access_depot(depot_id));

create policy manual_areas_insert on public.manual_areas
for insert to authenticated
with check (
  drawn_by = (select auth.uid())
  and private.can_access_depot(depot_id)
  and status = 'pending'
  and reviewed_by is null
  and reviewed_at is null
);

create policy manual_areas_update on public.manual_areas
for update to authenticated
using (
  private.can_validate_depot(depot_id)
  or (drawn_by = (select auth.uid()) and status = 'pending')
)
with check (
  private.can_validate_depot(depot_id)
  or (
    drawn_by = (select auth.uid())
    and status = 'pending'
    and reviewed_by is null
    and reviewed_at is null
  )
);

create policy manual_areas_delete on public.manual_areas
for delete to authenticated
using (
  private.can_manage_depot(depot_id)
  or (drawn_by = (select auth.uid()) and status = 'pending')
);

revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;

grant select on public.depots, public.user_profiles, public.sales,
  public.model_versions, public.zones, public.assignments, public.zone_cells,
  public.location_tracks, public.findings, public.manual_areas
to authenticated;

grant insert, update, delete on public.depots, public.user_profiles, public.sales,
  public.model_versions, public.zones, public.assignments, public.zone_cells,
  public.findings, public.manual_areas
to authenticated;

grant insert on public.location_tracks to authenticated;
grant usage, select on sequence public.location_tracks_id_seq to authenticated;

grant all on all tables in schema public to service_role;
grant all on all sequences in schema public to service_role;

insert into public.depots (id, name, region) values
  ('JAMBI', 'Jambi', 'Sumatra'),
  ('KUDUS', 'Kudus', 'Jawa'),
  ('TULUNG_AGUNG', 'Tulung Agung', 'Jawa'),
  ('BANJARBARU', 'Banjarbaru', 'Kalimantan'),
  ('BANJARMASIN_SELATAN', 'Banjarmasin Selatan', 'Kalimantan'),
  ('KENDARI', 'Kendari', 'Sulawesi'),
  ('DENPASAR', 'Denpasar', 'Bali');

commit;

begin;

drop policy depots_admin_all on public.depots;
create policy depots_admin_insert on public.depots
for insert to authenticated
with check (private.is_admin());
create policy depots_admin_update on public.depots
for update to authenticated
using (private.is_admin())
with check (private.is_admin());
create policy depots_admin_delete on public.depots
for delete to authenticated
using (private.is_admin());

drop policy model_versions_admin_all on public.model_versions;
create policy model_versions_admin_insert on public.model_versions
for insert to authenticated
with check (private.is_admin());
create policy model_versions_admin_update on public.model_versions
for update to authenticated
using (private.is_admin())
with check (private.is_admin());
create policy model_versions_admin_delete on public.model_versions
for delete to authenticated
using (private.is_admin());

drop policy zones_admin_all on public.zones;
create policy zones_admin_insert on public.zones
for insert to authenticated
with check (private.is_admin());
create policy zones_admin_update on public.zones
for update to authenticated
using (private.is_admin())
with check (private.is_admin());
create policy zones_admin_delete on public.zones
for delete to authenticated
using (private.is_admin());

create index assignments_assigned_by_idx
  on public.assignments(assigned_by);
create index assignments_zone_depot_idx
  on public.assignments(zone_key, depot_id);
create index assignments_sales_depot_idx
  on public.assignments(sales_id, depot_id);

create index zone_cells_assignment_depot_idx
  on public.zone_cells(assignment_id, depot_id);
create index zone_cells_sales_depot_idx
  on public.zone_cells(completed_by_sales_id, depot_id);

create index location_tracks_assignment_depot_idx
  on public.location_tracks(assignment_id, depot_id);
create index location_tracks_sales_depot_idx
  on public.location_tracks(sales_id, depot_id);
create index location_tracks_user_idx
  on public.location_tracks(user_id);

drop index public.findings_zone_idx;
create index findings_assignment_depot_idx
  on public.findings(assignment_id, depot_id);
create index findings_created_by_idx
  on public.findings(created_by);
create index findings_model_version_idx
  on public.findings(model_version_id);
create index findings_sales_depot_idx
  on public.findings(sales_id, depot_id);
create index findings_verified_by_idx
  on public.findings(verified_by);
create index findings_zone_depot_idx
  on public.findings(zone_key, depot_id);

create index manual_areas_drawn_by_idx
  on public.manual_areas(drawn_by);
create index manual_areas_reviewed_by_idx
  on public.manual_areas(reviewed_by);

commit;

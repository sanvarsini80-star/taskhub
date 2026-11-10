-- Apply after schema.sql and migration_v2.sql.
create table if not exists public.task_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  task_id uuid not null references public.tasks(id) on delete cascade,
  kind text not null check (kind in ('started','deadline_soon','deadline')),
  title text not null,
  body text not null,
  event_key text not null,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  unique(user_id,event_key)
);
create index if not exists task_notifications_user_created_idx
  on public.task_notifications(user_id,created_at desc);
alter table public.task_notifications enable row level security;
drop policy if exists task_notifications_read on public.task_notifications;
drop policy if exists task_notifications_insert on public.task_notifications;
drop policy if exists task_notifications_update on public.task_notifications;
create policy task_notifications_read on public.task_notifications
  for select to authenticated using(user_id=auth.uid());
create policy task_notifications_insert on public.task_notifications
  for insert to authenticated with check(
    user_id=auth.uid() and exists(select 1 from public.tasks t where t.id=task_id and (t.owner_id=auth.uid() or t.assigned_to=auth.uid()))
  );
create policy task_notifications_update on public.task_notifications
  for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
notify pgrst, 'reload schema';

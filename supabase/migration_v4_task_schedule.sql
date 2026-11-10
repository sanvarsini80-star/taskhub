-- Apply after schema.sql and migration_v3_notifications.sql.
-- starts_at schedules the task focus start; due_at remains its deadline.
alter table public.tasks add column if not exists starts_at timestamptz;

alter table public.task_notifications
  drop constraint if exists task_notifications_kind_check;
alter table public.task_notifications
  add constraint task_notifications_kind_check
  check (kind in ('started', 'deadline_soon', 'deadline'));

create index if not exists tasks_schedule_idx
  on public.tasks(starts_at, due_at)
  where status not in ('completed', 'archived');

notify pgrst, 'reload schema';

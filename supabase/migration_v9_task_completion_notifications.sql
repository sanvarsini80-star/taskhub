-- Apply after migration_v8_concurrent_task_timers.sql.
-- Allows the notification inbox to record tasks confirmed complete at their deadline.
alter table public.task_notifications
  drop constraint if exists task_notifications_kind_check;

alter table public.task_notifications
  add constraint task_notifications_kind_check
  check (kind in ('started', 'deadline_soon', 'deadline', 'completed'));

notify pgrst, 'reload schema';

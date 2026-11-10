-- Apply after migration_v3_notifications.sql.
-- Lets each signed-in user delete only their own notification history.
alter table public.task_notifications enable row level security;

drop policy if exists task_notifications_delete on public.task_notifications;
create policy task_notifications_delete
  on public.task_notifications
  for delete to authenticated
  using (user_id = auth.uid());

grant delete on table public.task_notifications to authenticated;

notify pgrst, 'reload schema';

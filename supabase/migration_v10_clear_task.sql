-- Apply after migration_v9_task_completion_notifications.sql.
-- Archives a task from the active list, including completed tasks, and stops its timer atomically.
create or replace function public.clear_task(target_task uuid)
returns void language plpgsql security definer set search_path=public as $$
declare
  task_row public.tasks;
  stopped timestamptz;
  duration integer := 0;
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;

  select * into task_row
  from public.tasks
  where id = target_task
  for update;

  if task_row.id is null or
     (task_row.owner_id <> auth.uid() and task_row.assigned_to <> auth.uid()) then
    raise exception 'Task access required';
  end if;
  if task_row.status = 'archived' then
    raise exception 'This task is already archived';
  end if;

  stopped := clock_timestamp();
  if task_row.timer_started_at is not null then
    duration := greatest(
      0,
      floor(extract(epoch from (stopped - task_row.timer_started_at)))::integer
    );
    update public.task_timer_sessions
    set stopped_at = stopped, elapsed_seconds = duration
    where task_id = target_task and stopped_at is null;
  end if;

  update public.tasks
  set status = 'archived',
      archived_at = stopped,
      timer_started_at = null,
      actual_seconds = actual_seconds + duration,
      updated_at = stopped
  where id = target_task;

  insert into public.task_changes(task_id, user_id, field, old_value, new_value, reason)
  values(target_task, auth.uid(), 'status', task_row.status, 'archived', 'Cleared from the task list');
end;
$$;

grant execute on function public.clear_task(uuid) to authenticated;
revoke all on function public.clear_task(uuid) from public, anon;

notify pgrst, 'reload schema';

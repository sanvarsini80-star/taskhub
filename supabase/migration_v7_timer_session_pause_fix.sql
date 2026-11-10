-- Apply after migration_v6_workspace_tasks_and_names.sql.
-- Closes the active timer session by task_id so paused sessions appear in history.
create or replace function public.pause_task_timer(target_task uuid)
returns integer language plpgsql security definer set search_path=public as $$
declare
  t public.tasks;
  stopped timestamptz := clock_timestamp();
  duration integer;
begin
  select * into t from public.tasks where id = target_task for update;
  if t.id is null or (t.owner_id <> auth.uid() and t.assigned_to <> auth.uid()) then
    raise exception 'Task access required';
  end if;
  if t.timer_started_at is null then
    raise exception 'This timer is not running';
  end if;

  duration := greatest(
    0,
    floor(extract(epoch from (stopped - t.timer_started_at)))::integer
  );
  update public.tasks
  set timer_started_at = null,
      actual_seconds = actual_seconds + duration,
      updated_at = stopped
  where id = target_task;
  update public.task_timer_sessions
  set stopped_at = stopped, elapsed_seconds = duration
  where task_id = target_task
    and user_id = auth.uid()
    and stopped_at is null;
  return duration;
end;
$$;

grant execute on function public.pause_task_timer(uuid) to authenticated;
revoke all on function public.pause_task_timer(uuid) from public, anon;
notify pgrst, 'reload schema';

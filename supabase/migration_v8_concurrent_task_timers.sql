-- Apply after migration_v7_timer_session_pause_fix.sql.
-- Allows up to three timers per user and can atomically replace/synchronize a set.

create or replace function public.start_task_timer(target_task uuid)
returns timestamptz language plpgsql security definer set search_path=public as $$
declare
  t public.tasks;
  started timestamptz;
  active_count integer;
  current_user_id uuid := auth.uid();
begin
  if current_user_id is null then raise exception 'Sign in required'; end if;
  perform pg_advisory_xact_lock(hashtext(current_user_id::text));

  select * into t from public.tasks where id = target_task for update;
  if t.id is null or (t.owner_id <> current_user_id and t.assigned_to <> current_user_id) then
    raise exception 'Task access required';
  end if;
  if t.status in ('completed', 'archived') then
    raise exception 'Completed or archived tasks cannot be started';
  end if;
  if t.timer_started_at is not null then
    raise exception 'This timer is already running';
  end if;

  select count(*) into active_count
  from public.tasks
  where timer_started_at is not null
    and (owner_id = current_user_id or assigned_to = current_user_id);
  if active_count >= 3 then
    raise exception 'You can run up to three task timers at once';
  end if;

  started := clock_timestamp();
  update public.tasks
  set timer_started_at = started, status = 'in_progress', updated_at = started
  where id = target_task;
  insert into public.task_timer_sessions(task_id, user_id, started_at)
  values(target_task, current_user_id, started);
  return started;
end;
$$;

create or replace function public.pause_task_timer(target_task uuid)
returns integer language plpgsql security definer set search_path=public as $$
declare
  t public.tasks;
  stopped timestamptz;
  duration integer;
begin
  select * into t from public.tasks where id = target_task for update;
  if t.id is null or (t.owner_id <> auth.uid() and t.assigned_to <> auth.uid()) then
    raise exception 'Task access required';
  end if;
  if t.timer_started_at is null then
    raise exception 'This timer is not running';
  end if;

  stopped := clock_timestamp();
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
  where task_id = target_task and stopped_at is null;
  return duration;
end;
$$;

create or replace function public.set_running_task_timers(target_tasks uuid[])
returns timestamptz language plpgsql security definer set search_path=public as $$
declare
  current_user_id uuid := auth.uid();
  target_count integer;
  accessible_count integer;
  task_row record;
  started timestamptz := clock_timestamp();
begin
  if current_user_id is null then raise exception 'Sign in required'; end if;
  target_count := coalesce(array_length(target_tasks, 1), 0);
  if target_count < 1 or target_count > 3 then
    raise exception 'Choose between one and three tasks';
  end if;
  if (select count(distinct selected_id) from unnest(target_tasks) as selected(selected_id)) <> target_count then
    raise exception 'A task was selected more than once';
  end if;

  perform pg_advisory_xact_lock(hashtext(current_user_id::text));

  select count(*) into accessible_count
  from public.tasks t
  where t.id = any(target_tasks)
    and (t.owner_id = current_user_id or t.assigned_to = current_user_id);
  if accessible_count <> target_count then
    raise exception 'Task access required';
  end if;
  if exists (
    select 1 from public.tasks t
    where t.id = any(target_tasks) and t.status in ('completed', 'archived')
  ) then
    raise exception 'Completed or archived tasks cannot be started';
  end if;

  for task_row in
    select t.id from public.tasks t
    where t.timer_started_at is not null
      and (t.owner_id = current_user_id or t.assigned_to = current_user_id)
    order by t.id
    for update
  loop
    perform public.pause_task_timer(task_row.id);
  end loop;

  started := clock_timestamp();
  update public.tasks
  set timer_started_at = started,
      status = 'in_progress',
      updated_at = started
  where id = any(target_tasks);
  insert into public.task_timer_sessions(task_id, user_id, started_at)
  select t.id, current_user_id, started
  from public.tasks t
  where t.id = any(target_tasks);

  return started;
end;
$$;

grant execute on function public.start_task_timer(uuid) to authenticated;
grant execute on function public.pause_task_timer(uuid) to authenticated;
grant execute on function public.set_running_task_timers(uuid[]) to authenticated;
revoke all on function public.start_task_timer(uuid) from public, anon;
revoke all on function public.pause_task_timer(uuid) from public, anon;
revoke all on function public.set_running_task_timers(uuid[]) from public, anon;

notify pgrst, 'reload schema';

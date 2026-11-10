-- Apply after migration_v14_prevent_employee_assignment_to_admin.sql.
-- After a task is assigned, only its assignee can change progress or track time.
-- The creator keeps read access to the task in the workspace's Assigned to list.

create or replace function public.change_task_field(
  target_task uuid,
  field_name text,
  new_value text,
  reason_text text
)
returns void language plpgsql security definer set search_path = public as $$
declare
  t public.tasks;
  old_text text;
  v_stopped_at timestamptz;
  elapsed integer;
begin
  select * into t from public.tasks where id = target_task for update;
  if t.id is null or not (
    t.assigned_to = auth.uid()
    or (t.owner_id = auth.uid() and t.assigned_to is null and not exists (select 1 from public.task_assignment_requests r where r.task_id = t.id and r.requested_by = auth.uid() and r.status = 'pending'))
  ) then
    raise exception 'Only the task assignee can change its progress';
  end if;
  if length(trim(coalesce(reason_text, ''))) < 3 then
    raise exception 'Please provide a specific reason';
  end if;

  if field_name = 'status' then
    if t.status = 'completed' and new_value <> 'completed' then
      raise exception 'Completed tasks cannot be reopened';
    end if;
    if new_value not in ('active', 'in_progress', 'completed', 'archived') then
      raise exception 'Invalid status';
    end if;
    old_text := t.status;
    if t.timer_started_at is not null and new_value <> 'in_progress' then
      v_stopped_at := clock_timestamp();
      elapsed := greatest(0, floor(extract(epoch from (v_stopped_at - t.timer_started_at)))::integer);
      update public.tasks
      set status = new_value,
          updated_at = v_stopped_at,
          archived_at = case when new_value = 'archived' then v_stopped_at else null end,
          timer_started_at = null,
          actual_seconds = actual_seconds + elapsed
      where id = target_task;
      update public.task_timer_sessions
      set stopped_at = v_stopped_at, elapsed_seconds = elapsed
      where task_id = target_task and user_id = auth.uid() and stopped_at is null;
    else
      update public.tasks
      set status = new_value,
          updated_at = now(),
          archived_at = case when new_value = 'archived' then now() else null end
      where id = target_task;
    end if;
  elsif field_name = 'priority' then
    if new_value not in ('low', 'medium', 'high', 'critical') then
      raise exception 'Invalid priority';
    end if;
    old_text := t.priority;
    update public.tasks set priority = new_value, updated_at = now() where id = target_task;
  else
    raise exception 'Unsupported task field';
  end if;

  insert into public.task_changes(task_id, user_id, field, old_value, new_value, reason)
  values (target_task, auth.uid(), field_name, old_text, new_value, trim(reason_text));
end;
$$;

grant execute on function public.change_task_field(uuid, text, text, text) to authenticated;
revoke all on function public.change_task_field(uuid, text, text, text) from public, anon;

create or replace function public.start_task_timer(target_task uuid)
returns timestamptz language plpgsql security definer set search_path = public as $$
declare
  t public.tasks;
  started timestamptz;
  active_count integer;
  current_user_id uuid := auth.uid();
begin
  if current_user_id is null then raise exception 'Sign in required'; end if;
  perform pg_advisory_xact_lock(hashtext(current_user_id::text));
  select * into t from public.tasks where id = target_task for update;
  if t.id is null or not (
    t.assigned_to = current_user_id
    or (t.owner_id = current_user_id and t.assigned_to is null and not exists (select 1 from public.task_assignment_requests r where r.task_id = t.id and r.requested_by = current_user_id and r.status = 'pending'))
  ) then
    raise exception 'Only the task assignee can track its time';
  end if;
  if t.status in ('completed', 'archived') then
    raise exception 'Completed or archived tasks cannot be started';
  end if;
  if t.timer_started_at is not null then raise exception 'This timer is already running'; end if;

  select count(*) into active_count
  from public.tasks t
  where t.timer_started_at is not null
    and (t.assigned_to = current_user_id or (
      t.owner_id = current_user_id and t.assigned_to is null
      and not exists (
        select 1 from public.task_assignment_requests r
        where r.task_id = t.id and r.requested_by = current_user_id and r.status = 'pending'
      )
    ));
  if active_count >= 3 then raise exception 'You can run up to three task timers at once'; end if;

  started := clock_timestamp();
  update public.tasks
  set timer_started_at = started, status = 'in_progress', updated_at = started
  where id = target_task;
  insert into public.task_timer_sessions(task_id, user_id, started_at)
  values (target_task, current_user_id, started);
  return started;
end;
$$;

grant execute on function public.start_task_timer(uuid) to authenticated;
revoke all on function public.start_task_timer(uuid) from public, anon;

create or replace function public.pause_task_timer(target_task uuid)
returns integer language plpgsql security definer set search_path = public as $$
declare
  t public.tasks;
  stopped timestamptz;
  duration integer;
  current_user_id uuid := auth.uid();
begin
  if current_user_id is null then raise exception 'Sign in required'; end if;
  select * into t from public.tasks where id = target_task for update;
  if t.id is null or not (
    t.assigned_to = current_user_id
    or (t.owner_id = current_user_id and t.assigned_to is null and not exists (select 1 from public.task_assignment_requests r where r.task_id = t.id and r.requested_by = current_user_id and r.status = 'pending'))
  ) then
    raise exception 'Only the task assignee can control its timer';
  end if;
  if t.timer_started_at is null then raise exception 'This timer is not running'; end if;

  stopped := clock_timestamp();
  duration := greatest(0, floor(extract(epoch from (stopped - t.timer_started_at)))::integer);
  update public.tasks
  set timer_started_at = null, actual_seconds = actual_seconds + duration, updated_at = stopped
  where id = target_task;
  update public.task_timer_sessions
  set stopped_at = stopped, elapsed_seconds = duration
  where task_id = target_task and user_id = current_user_id and stopped_at is null;
  return duration;
end;
$$;

grant execute on function public.pause_task_timer(uuid) to authenticated;
revoke all on function public.pause_task_timer(uuid) from public, anon;

create or replace function public.set_running_task_timers(target_tasks uuid[])
returns timestamptz language plpgsql security definer set search_path = public as $$
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
    and (t.assigned_to = current_user_id or (t.owner_id = current_user_id and t.assigned_to is null and not exists (select 1 from public.task_assignment_requests r where r.task_id = t.id and r.requested_by = current_user_id and r.status = 'pending')));
  if accessible_count <> target_count then
    raise exception 'Only tasks assigned to you can be tracked';
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
      and (t.assigned_to = current_user_id or (t.owner_id = current_user_id and t.assigned_to is null and not exists (select 1 from public.task_assignment_requests r where r.task_id = t.id and r.requested_by = current_user_id and r.status = 'pending')))
    order by t.id
    for update
  loop
    perform public.pause_task_timer(task_row.id);
  end loop;

  started := clock_timestamp();
  update public.tasks
  set timer_started_at = started, status = 'in_progress', updated_at = started
  where id = any(target_tasks);
  insert into public.task_timer_sessions(task_id, user_id, started_at)
  select t.id, current_user_id, started
  from public.tasks t where t.id = any(target_tasks);
  return started;
end;
$$;

grant execute on function public.set_running_task_timers(uuid[]) to authenticated;
revoke all on function public.set_running_task_timers(uuid[]) from public, anon;

notify pgrst, 'reload schema';



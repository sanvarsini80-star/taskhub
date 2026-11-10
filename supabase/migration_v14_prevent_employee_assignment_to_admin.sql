-- Apply after migration_v13_workspace_task_personal_transfer.sql.
-- Workspace employees may request another employee as assignee, but cannot
-- create assignment requests for workspace admins. Admins retain direct assignment.
create or replace function public.workspace_assign_task(target_task uuid, target_user uuid)
returns text language plpgsql security definer set search_path = public as $$
declare
  task_row public.tasks;
  current_user_id uuid := auth.uid();
begin
  if current_user_id is null then
    raise exception 'Sign in required';
  end if;

  select * into task_row
  from public.tasks
  where id = target_task
  for update;

  if task_row.id is null or task_row.scope <> 'workspace' then
    raise exception 'Workspace task not found';
  end if;
  if not public.is_workspace_member(task_row.workspace_id, current_user_id) then
    raise exception 'Workspace member access required';
  end if;
  if task_row.timer_started_at is not null then
    raise exception 'Pause the task timer before assigning it';
  end if;
  if target_user = current_user_id then
    raise exception 'Choose another workspace member';
  end if;
  if not public.is_workspace_member(task_row.workspace_id, target_user) then
    raise exception 'Assignee must be a workspace member';
  end if;

  if public.is_workspace_admin(task_row.workspace_id, current_user_id) then
    update public.tasks
    set assigned_to = target_user, updated_at = now()
    where id = target_task;
    return 'assigned';
  end if;

  if public.is_workspace_admin(task_row.workspace_id, target_user) then
    raise exception 'Employees cannot assign tasks to workspace admins';
  end if;

  insert into public.task_assignment_requests(task_id, requested_by, requested_to, status)
  values (target_task, current_user_id, target_user, 'pending')
  on conflict (task_id, requested_to) do update
    set requested_by = excluded.requested_by,
        status = 'pending', created_at = now(), decided_at = null;
  return 'requested';
end;
$$;

grant execute on function public.workspace_assign_task(uuid, uuid) to authenticated;
revoke all on function public.workspace_assign_task(uuid, uuid) from public, anon;

notify pgrst, 'reload schema';

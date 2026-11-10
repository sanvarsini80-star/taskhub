-- Apply after migration_v17_workspace_join_notifications.sql.
-- Lets each workspace admin choose which employees may request tasks assigned to them.

create table if not exists public.workspace_admin_assignment_permissions (
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  admin_id uuid not null references auth.users(id) on delete cascade,
  employee_id uuid not null references auth.users(id) on delete cascade,
  enabled_at timestamptz not null default now(),
  primary key (workspace_id, admin_id, employee_id),
  check (admin_id <> employee_id)
);

alter table public.workspace_admin_assignment_permissions enable row level security;
revoke all on public.workspace_admin_assignment_permissions from public, anon, authenticated;

create or replace function public.workspace_admin_assignment_permissions(target_workspace uuid)
returns table(employee_id uuid, enabled boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null or not public.is_workspace_admin(target_workspace) then
    raise exception 'Workspace admin access required';
  end if;
  return query
    select m.user_id,
           exists (
             select 1 from public.workspace_admin_assignment_permissions p
             where p.workspace_id = target_workspace
               and p.admin_id = auth.uid()
               and p.employee_id = m.user_id
           )
    from public.workspace_members m
    where m.workspace_id = target_workspace and m.role <> 'admin'
    order by lower(coalesce(nullif(trim((select p.display_name from public.profiles p where p.user_id = m.user_id)), ''),
                             (select p.email from public.profiles p where p.user_id = m.user_id), ''));
end;
$$;

create or replace function public.set_workspace_admin_assignment_permission(
  target_workspace uuid,
  target_employee uuid,
  allow_assignment boolean
)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or not public.is_workspace_admin(target_workspace) then
    raise exception 'Workspace admin access required';
  end if;
  if not exists (
    select 1 from public.workspace_members m
    where m.workspace_id = target_workspace
      and m.user_id = target_employee
      and m.role <> 'admin'
  ) then
    raise exception 'Choose an employee in this workspace';
  end if;

  if allow_assignment then
    insert into public.workspace_admin_assignment_permissions(
      workspace_id, admin_id, employee_id
    ) values (target_workspace, auth.uid(), target_employee)
    on conflict (workspace_id, admin_id, employee_id)
    do update set enabled_at = clock_timestamp();
  else
    delete from public.workspace_admin_assignment_permissions
    where workspace_id = target_workspace
      and admin_id = auth.uid()
      and employee_id = target_employee;
  end if;
end;
$$;

grant execute on function public.workspace_admin_assignment_permissions(uuid) to authenticated;
grant execute on function public.set_workspace_admin_assignment_permission(uuid, uuid, boolean) to authenticated;
revoke all on function public.workspace_admin_assignment_permissions(uuid) from public, anon;
revoke all on function public.set_workspace_admin_assignment_permission(uuid, uuid, boolean) from public, anon;

-- Add a flag to each listed admin indicating whether the signed-in employee
-- is allowed to send that admin an assignment request.
drop function if exists public.workspace_member_list(uuid);
create function public.workspace_member_list(target_workspace uuid)
returns table(
  user_id uuid,
  email text,
  role text,
  display_name text,
  can_current_user_assign_to_admin boolean
)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_workspace_member(target_workspace) then
    raise exception 'Workspace member access required';
  end if;
  return query
    select m.user_id,
           coalesce(p.email, 'Workspace member'),
           m.role,
           coalesce(nullif(trim(p.display_name), ''), ''),
           m.role = 'admin' and exists (
             select 1 from public.workspace_admin_assignment_permissions a
             where a.workspace_id = target_workspace
               and a.admin_id = m.user_id
               and a.employee_id = auth.uid()
           )
    from public.workspace_members m
    left join public.profiles p on p.user_id = m.user_id
    where m.workspace_id = target_workspace
    order by m.role desc, p.display_name nulls last, p.email;
end;
$$;

grant execute on function public.workspace_member_list(uuid) to authenticated;
revoke all on function public.workspace_member_list(uuid) from public, anon;

-- Only admins may directly assign to any member. An employee may request an
-- admin as assignee only when that specific admin enabled the employee.
create or replace function public.workspace_assign_task(target_task uuid, target_user uuid)
returns text language plpgsql security definer set search_path = public as $$
declare
  task_row public.tasks;
  current_user_id uuid := auth.uid();
  actor_name text;
  request_row_id uuid;
  event_time timestamptz := clock_timestamp();
begin
  if current_user_id is null then raise exception 'Sign in required'; end if;
  select * into task_row from public.tasks where id = target_task for update;
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

  select coalesce(nullif(trim(p.display_name), ''), p.email, 'A workspace member')
    into actor_name from public.profiles p where p.user_id = current_user_id;
  actor_name := coalesce(actor_name, 'A workspace member');

  if public.is_workspace_admin(task_row.workspace_id, current_user_id) then
    update public.tasks set assigned_to = target_user, updated_at = event_time
    where id = target_task;
    insert into public.task_notifications(user_id, task_id, kind, title, body, event_key)
    values (
      target_user, target_task, 'assignment_assigned', 'Task assigned to you',
      actor_name || ' assigned you "' || task_row.title || '". Priority: ' || upper(task_row.priority) || '.',
      'admin-assignment:' || target_task::text || ':' || target_user::text || ':' || extract(epoch from event_time)::text
    );
    return 'assigned';
  end if;

  if public.is_workspace_admin(task_row.workspace_id, target_user)
     and not exists (
       select 1 from public.workspace_admin_assignment_permissions p
       where p.workspace_id = task_row.workspace_id
         and p.admin_id = target_user
         and p.employee_id = current_user_id
     ) then
    raise exception 'This admin has not enabled task requests from you';
  end if;

  insert into public.task_assignment_requests(task_id, requested_by, requested_to, status)
  values (target_task, current_user_id, target_user, 'pending')
  on conflict (task_id, requested_to) do update
    set requested_by = excluded.requested_by,
        status = 'pending', created_at = event_time, decided_at = null
  returning id into request_row_id;

  insert into public.task_notifications(
    user_id, task_id, kind, title, body, event_key, assignment_request_id
  ) values (
    target_user, target_task, 'assignment_request', 'Task assignment request',
    actor_name || ' wants you to take "' || task_row.title || '". Priority: ' || upper(task_row.priority) || '.',
    'assignment-request:' || request_row_id::text, request_row_id
  )
  on conflict (user_id, event_key) do update
    set title = excluded.title,
        body = excluded.body,
        created_at = event_time,
        read_at = null,
        assignment_request_id = excluded.assignment_request_id;
  return 'requested';
end;
$$;

grant execute on function public.workspace_assign_task(uuid, uuid) to authenticated;
revoke all on function public.workspace_assign_task(uuid, uuid) from public, anon;

notify pgrst, 'reload schema';

-- Apply after migration_v21_workspace_founder_approval.sql.
-- Include workspace display names and selected roles in assignment request,
-- assignment result, and direct assignment notifications.

create or replace function public.workspace_assign_task(target_task uuid, target_user uuid)
returns text language plpgsql security definer set search_path = public as $$
declare
  task_row public.tasks;
  current_user_id uuid := auth.uid();
  actor_label text;
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

  select coalesce(
           nullif(trim(m.display_name), ''),
           nullif(trim(p.display_name), ''),
           'Workspace member'
         ) || ' (' || public.workspace_join_role_label(coalesce(m.workspace_role, m.role)) || ')'
    into actor_label
  from public.workspace_members m
  left join public.profiles p on p.user_id = m.user_id
  where m.workspace_id = task_row.workspace_id and m.user_id = current_user_id;
  actor_label := coalesce(actor_label, 'Workspace member (Employee)');

  if public.is_workspace_admin(task_row.workspace_id, current_user_id) then
    update public.tasks set assigned_to = target_user, updated_at = event_time
    where id = target_task;
    insert into public.task_notifications(user_id, task_id, kind, title, body, event_key)
    values (
      target_user, target_task, 'assignment_assigned', 'Task assigned to you',
      actor_label || ' assigned you "' || task_row.title || '". Priority: ' || upper(task_row.priority) || '.',
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
    actor_label || ' wants you to take "' || task_row.title || '". Priority: ' || upper(task_row.priority) || '.',
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

create or replace function public.decide_task_assignment(request_id uuid, accept boolean)
returns void language plpgsql security definer set search_path = public as $$
declare
  req public.task_assignment_requests;
  task_row public.tasks;
  responder_label text;
  result_kind text;
  result_title text;
  result_word text;
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  select * into req from public.task_assignment_requests where id = request_id for update;
  if req.id is null or req.requested_to <> auth.uid() then
    raise exception 'This assignment request is not yours';
  end if;
  if req.status <> 'pending' then
    raise exception 'This request has already been handled';
  end if;
  select * into task_row from public.tasks where id = req.task_id for update;
  if task_row.id is null or task_row.scope <> 'workspace'
     or not public.is_workspace_member(task_row.workspace_id, auth.uid()) then
    raise exception 'This task is no longer available in your workspace';
  end if;

  update public.task_assignment_requests
  set status = case when accept then 'accepted' else 'rejected' end,
      decided_at = clock_timestamp()
  where id = request_id;
  update public.task_notifications
  set read_at = coalesce(read_at, clock_timestamp())
  where assignment_request_id = request_id;
  if accept then
    update public.tasks
    set assigned_to = auth.uid(), updated_at = clock_timestamp()
    where id = req.task_id;
  end if;

  select coalesce(
           nullif(trim(m.display_name), ''),
           nullif(trim(p.display_name), ''),
           'Workspace member'
         ) || ' (' || public.workspace_join_role_label(coalesce(m.workspace_role, m.role)) || ')'
    into responder_label
  from public.workspace_members m
  left join public.profiles p on p.user_id = m.user_id
  where m.workspace_id = task_row.workspace_id and m.user_id = auth.uid();
  responder_label := coalesce(responder_label, 'Workspace member (Employee)');
  result_kind := case when accept then 'assignment_accepted' else 'assignment_rejected' end;
  result_title := case when accept then 'Task assignment accepted' else 'Task assignment declined' end;
  result_word := case when accept then 'accepted' else 'declined' end;

  insert into public.task_notifications(user_id, task_id, kind, title, body, event_key)
  values (
    req.requested_by,
    req.task_id,
    result_kind,
    result_title,
    responder_label || ' ' || result_word || ' your request for "' || task_row.title || '".',
    'assignment-response:' || request_id::text || ':' || result_kind
  )
  on conflict (user_id, event_key) do update
    set title = excluded.title,
        body = excluded.body,
        created_at = clock_timestamp(),
        read_at = null;
end;
$$;

grant execute on function public.decide_task_assignment(uuid, boolean) to authenticated;
revoke all on function public.decide_task_assignment(uuid, boolean) from public, anon;

-- Refresh outstanding request notifications so they also show the requester's
-- workspace name and role after this migration is applied.
update public.task_notifications n
set body = coalesce(
      nullif(trim(requester.display_name), ''),
      nullif(trim(profile.display_name), ''),
      'Workspace member'
    ) || ' (' || public.workspace_join_role_label(coalesce(requester.workspace_role, requester.role)) ||
    ') wants you to take "' || task_row.title || '". Priority: ' || upper(task_row.priority) || '.'
from public.task_assignment_requests r
join public.tasks task_row on task_row.id = r.task_id
join public.workspace_members requester
  on requester.workspace_id = task_row.workspace_id and requester.user_id = r.requested_by
left join public.profiles profile on profile.user_id = requester.user_id
where n.assignment_request_id = r.id
  and n.kind = 'assignment_request'
  and r.status = 'pending';

update public.task_notifications n
set body = coalesce(
      nullif(trim(responder.display_name), ''),
      nullif(trim(profile.display_name), ''),
      'Workspace member'
    ) || ' (' || public.workspace_join_role_label(coalesce(responder.workspace_role, responder.role)) || ') ' ||
    case when n.kind = 'assignment_accepted' then 'accepted' else 'declined' end ||
    ' your request for "' || task_row.title || '".'
from public.task_assignment_requests r
join public.tasks task_row on task_row.id = r.task_id
join public.workspace_members responder
  on responder.workspace_id = task_row.workspace_id and responder.user_id = r.requested_to
left join public.profiles profile on profile.user_id = responder.user_id
where split_part(n.event_key, ':', 2) = r.id::text
  and n.kind in ('assignment_accepted', 'assignment_rejected');

notify pgrst, 'reload schema';

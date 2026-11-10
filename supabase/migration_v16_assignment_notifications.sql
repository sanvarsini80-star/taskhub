-- Apply after migration_v15_assignee_only_progress_and_timers.sql.
-- Adds assignment requests and assignment results to the in-app notification inbox.

alter table public.task_notifications
  add column if not exists assignment_request_id uuid
    references public.task_assignment_requests(id) on delete cascade;

alter table public.task_notifications
  drop constraint if exists task_notifications_kind_check;
alter table public.task_notifications
  add constraint task_notifications_kind_check
  check (kind in (
    'started', 'deadline_soon', 'deadline', 'completed',
    'assignment_request', 'assignment_accepted', 'assignment_rejected',
    'assignment_assigned'
  ));

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
    into actor_name
  from public.profiles p where p.user_id = current_user_id;
  actor_name := coalesce(actor_name, 'A workspace member');

  if public.is_workspace_admin(task_row.workspace_id, current_user_id) then
    update public.tasks
    set assigned_to = target_user, updated_at = event_time
    where id = target_task;

    insert into public.task_notifications(
      user_id, task_id, kind, title, body, event_key
    ) values (
      target_user,
      target_task,
      'assignment_assigned',
      'Task assigned to you',
      actor_name || ' assigned you "' || task_row.title || '". Priority: ' || upper(task_row.priority) || '.',
      'admin-assignment:' || target_task::text || ':' || target_user::text || ':' || extract(epoch from event_time)::text
    );
    return 'assigned';
  end if;

  if public.is_workspace_admin(task_row.workspace_id, target_user) then
    raise exception 'Employees cannot assign tasks to workspace admins';
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
    target_user,
    target_task,
    'assignment_request',
    'Task assignment request',
    actor_name || ' wants you to take "' || task_row.title || '". Priority: ' || upper(task_row.priority) || '.',
    'assignment-request:' || request_row_id::text,
    request_row_id
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
  recipient_name text;
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

  select coalesce(nullif(trim(p.display_name), ''), p.email, 'Your teammate')
    into recipient_name
  from public.profiles p where p.user_id = auth.uid();
  recipient_name := coalesce(recipient_name, 'Your teammate');
  result_kind := case when accept then 'assignment_accepted' else 'assignment_rejected' end;
  result_title := case when accept then 'Task assignment accepted' else 'Task assignment declined' end;
  result_word := case when accept then 'accepted' else 'declined' end;

  insert into public.task_notifications(user_id, task_id, kind, title, body, event_key)
  values (
    req.requested_by,
    req.task_id,
    result_kind,
    result_title,
    recipient_name || ' ' || result_word || ' "' || task_row.title || '".',
    'assignment-response:' || request_id::text || ':' || result_kind
  )
  on conflict (user_id, event_key) do nothing;
end;
$$;

grant execute on function public.decide_task_assignment(uuid, boolean) to authenticated;
revoke all on function public.decide_task_assignment(uuid, boolean) from public, anon;

-- Make any requests created before this migration visible in the inbox too.
insert into public.task_notifications(
  user_id, task_id, kind, title, body, event_key, assignment_request_id
)
select
  r.requested_to,
  r.task_id,
  'assignment_request',
  'Task assignment request',
  coalesce(nullif(trim(p.display_name), ''), p.email, 'A workspace member') ||
    ' wants you to take "' || t.title || '". Priority: ' || upper(t.priority) || '.',
  'assignment-request:' || r.id::text,
  r.id
from public.task_assignment_requests r
join public.tasks t on t.id = r.task_id
left join public.profiles p on p.user_id = r.requested_by
where r.status = 'pending'
on conflict (user_id, event_key) do nothing;

notify pgrst, 'reload schema';

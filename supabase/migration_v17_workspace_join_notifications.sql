-- Apply after migration_v16_assignment_notifications.sql.
-- Puts workspace join requests and decisions in the notification inbox.

alter table public.task_notifications alter column task_id drop not null;
alter table public.task_notifications
  add column if not exists workspace_id uuid
    references public.workspaces(id) on delete cascade;
alter table public.task_notifications
  add column if not exists workspace_request_id uuid
    references public.workspace_requests(id) on delete cascade;

alter table public.task_notifications
  drop constraint if exists task_notifications_kind_check;
alter table public.task_notifications
  add constraint task_notifications_kind_check
  check (kind in (
    'started', 'deadline_soon', 'deadline', 'completed',
    'assignment_request', 'assignment_accepted', 'assignment_rejected',
    'assignment_assigned', 'workspace_join_request',
    'workspace_join_accepted', 'workspace_join_rejected'
  ));

create or replace function public.request_workspace_join(target_workspace uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  request_row_id uuid;
  requester_name text;
  workspace_name text;
  admin_row record;
  created_at_time timestamptz := clock_timestamp();
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  select w.name into workspace_name from public.workspaces w where w.id = target_workspace;
  if workspace_name is null then raise exception 'Workspace not found'; end if;
  if public.is_workspace_member(target_workspace) then
    raise exception 'You are already a member';
  end if;

  insert into public.workspace_requests(workspace_id, user_id, status)
  values (target_workspace, auth.uid(), 'pending')
  on conflict (workspace_id, user_id) do update
    set status = 'pending', created_at = created_at_time
  returning id into request_row_id;

  select coalesce(nullif(trim(p.display_name), ''), p.email, 'A new member')
    into requester_name
  from public.profiles p where p.user_id = auth.uid();
  requester_name := coalesce(requester_name, 'A new member');

  for admin_row in
    select m.user_id from public.workspace_members m
    where m.workspace_id = target_workspace and m.role = 'admin'
  loop
    insert into public.task_notifications(
      user_id, workspace_id, kind, title, body, event_key, workspace_request_id
    ) values (
      admin_row.user_id,
      target_workspace,
      'workspace_join_request',
      'Workspace join request',
      requester_name || ' wants to join "' || workspace_name || '".',
      'workspace-join-request:' || request_row_id::text || ':' || admin_row.user_id::text,
      request_row_id
    )
    on conflict (user_id, event_key) do update
      set title = excluded.title,
          body = excluded.body,
          created_at = created_at_time,
          read_at = null,
          workspace_request_id = excluded.workspace_request_id,
          workspace_id = excluded.workspace_id;
  end loop;

  return request_row_id;
end;
$$;

grant execute on function public.request_workspace_join(uuid) to authenticated;
revoke all on function public.request_workspace_join(uuid) from public, anon;

create or replace function public.decide_workspace_request(request_id uuid, accept boolean)
returns void language plpgsql security definer set search_path = public as $$
declare
  req public.workspace_requests;
  workspace_name text;
  admin_name text;
  result_kind text;
  result_title text;
  result_word text;
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  select * into req from public.workspace_requests where id = request_id for update;
  if req.id is null or not public.is_workspace_admin(req.workspace_id) then
    raise exception 'Workspace admin access required';
  end if;
  if req.status <> 'pending' then
    raise exception 'This request has already been handled';
  end if;
  select w.name into workspace_name from public.workspaces w where w.id = req.workspace_id;
  select coalesce(nullif(trim(p.display_name), ''), p.email, 'A workspace admin')
    into admin_name
  from public.profiles p where p.user_id = auth.uid();
  admin_name := coalesce(admin_name, 'A workspace admin');

  update public.workspace_requests
  set status = case when accept then 'accepted' else 'rejected' end
  where id = request_id;
  update public.task_notifications
  set read_at = coalesce(read_at, clock_timestamp())
  where workspace_request_id = request_id and kind = 'workspace_join_request';

  if accept then
    insert into public.workspace_members(workspace_id, user_id, role)
    values (req.workspace_id, req.user_id, 'member')
    on conflict (workspace_id, user_id) do nothing;
  end if;

  result_kind := case when accept then 'workspace_join_accepted' else 'workspace_join_rejected' end;
  result_title := case when accept then 'Workspace request accepted' else 'Workspace request declined' end;
  result_word := case when accept then 'accepted' else 'declined' end;
  insert into public.task_notifications(
    user_id, workspace_id, workspace_request_id, kind, title, body, event_key
  ) values (
    req.user_id,
    req.workspace_id,
    request_id,
    result_kind,
    result_title,
    admin_name || ' ' || result_word || ' your request to join "' || workspace_name || '".',
    'workspace-join-result:' || request_id::text || ':' || result_kind
  )
  on conflict (user_id, event_key) do nothing;
end;
$$;

grant execute on function public.decide_workspace_request(uuid, boolean) to authenticated;
revoke all on function public.decide_workspace_request(uuid, boolean) from public, anon;

-- Backfill outstanding requests so admins can handle them from Notifications.
insert into public.task_notifications(
  user_id, workspace_id, kind, title, body, event_key, workspace_request_id
)
select
  admin.user_id,
  r.workspace_id,
  'workspace_join_request',
  'Workspace join request',
  coalesce(nullif(trim(p.display_name), ''), p.email, 'A new member') ||
    ' wants to join "' || w.name || '".',
  'workspace-join-request:' || r.id::text || ':' || admin.user_id::text,
  r.id
from public.workspace_requests r
join public.workspaces w on w.id = r.workspace_id
join public.workspace_members admin
  on admin.workspace_id = r.workspace_id and admin.role = 'admin'
left join public.profiles p on p.user_id = r.user_id
where r.status = 'pending'
on conflict (user_id, event_key) do nothing;

notify pgrst, 'reload schema';

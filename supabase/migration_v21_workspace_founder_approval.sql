-- Apply after migration_v20_founder_display_labels.sql.
-- Founder-role join requests go to the workspace creator (the original
-- founder). Once accepted, the new founder receives the existing admin access.

create or replace function public.request_workspace_join(
  target_workspace uuid,
  p_applicant_name text,
  p_requested_role text
)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  request_row_id uuid;
  workspace_name text;
  creator_id uuid;
  admin_row record;
  event_time timestamptz := clock_timestamp();
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  if length(trim(coalesce(p_applicant_name, ''))) < 2 then
    raise exception 'Please enter your name';
  end if;
  if p_requested_role not in ('admin', 'co_founder', 'employee') then
    raise exception 'Choose a workspace role';
  end if;

  select w.name, w.created_by into workspace_name, creator_id
  from public.workspaces w where w.id = target_workspace;
  if workspace_name is null then raise exception 'Workspace not found'; end if;
  if public.is_workspace_member(target_workspace) then
    raise exception 'You are already a member';
  end if;

  insert into public.workspace_requests(
    workspace_id, user_id, status, applicant_name, requested_role
  ) values (
    target_workspace, auth.uid(), 'pending', trim(p_applicant_name), p_requested_role
  )
  on conflict (workspace_id, user_id) do update
    set status = 'pending',
        applicant_name = excluded.applicant_name,
        requested_role = excluded.requested_role,
        created_at = event_time
  returning id into request_row_id;

  for admin_row in
    select m.user_id
    from public.workspace_members m
    where m.workspace_id = target_workspace
      and m.role = 'admin'
      and (p_requested_role <> 'admin' or m.user_id = creator_id)
  loop
    insert into public.task_notifications(
      user_id, workspace_id, kind, title, body, event_key, workspace_request_id
    ) values (
      admin_row.user_id,
      target_workspace,
      'workspace_join_request',
      'Workspace join request',
      trim(p_applicant_name) || ' (' || public.workspace_join_role_label(p_requested_role) ||
        ') wants to join "' || workspace_name || '".',
      'workspace-join-request:' || request_row_id::text || ':' || admin_row.user_id::text,
      request_row_id
    )
    on conflict (user_id, event_key) do update
      set title = excluded.title,
          body = excluded.body,
          created_at = event_time,
          read_at = null,
          workspace_request_id = excluded.workspace_request_id,
          workspace_id = excluded.workspace_id;
  end loop;

  return request_row_id;
end;
$$;

grant execute on function public.request_workspace_join(uuid, text, text) to authenticated;
revoke all on function public.request_workspace_join(uuid, text, text) from public, anon;

create or replace function public.decide_workspace_request(request_id uuid, accept boolean)
returns void language plpgsql security definer set search_path = public as $$
declare
  req public.workspace_requests;
  workspace_name text;
  workspace_creator uuid;
  admin_name text;
  result_kind text;
  result_title text;
  result_word text;
  joined_access_role text;
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  select * into req from public.workspace_requests where id = request_id for update;
  if req.id is null or not public.is_workspace_admin(req.workspace_id) then
    raise exception 'Workspace admin access required';
  end if;
  if req.status <> 'pending' then
    raise exception 'This request has already been handled';
  end if;

  select w.name, w.created_by into workspace_name, workspace_creator
  from public.workspaces w where w.id = req.workspace_id;
  if req.requested_role = 'admin' and auth.uid() <> workspace_creator then
    raise exception 'Only the original workspace founder can approve another founder';
  end if;
  select coalesce(nullif(trim(p.display_name), ''), 'A workspace founder')
    into admin_name from public.profiles p where p.user_id = auth.uid();
  admin_name := coalesce(admin_name, 'A workspace founder');

  update public.workspace_requests
  set status = case when accept then 'accepted' else 'rejected' end
  where id = request_id;
  update public.task_notifications
  set read_at = coalesce(read_at, clock_timestamp())
  where workspace_request_id = request_id and kind = 'workspace_join_request';

  if accept then
    joined_access_role := case when req.requested_role = 'admin' then 'admin' else 'member' end;
    insert into public.workspace_members(
      workspace_id, user_id, role, display_name, workspace_role
    ) values (
      req.workspace_id,
      req.user_id,
      joined_access_role,
      req.applicant_name,
      req.requested_role
    )
    on conflict (workspace_id, user_id) do update
      set role = excluded.role,
          display_name = excluded.display_name,
          workspace_role = excluded.workspace_role;
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
    admin_name || ' ' || result_word || ' your request to join "' || workspace_name ||
      '" as ' || public.workspace_join_role_label(req.requested_role) || '.',
    'workspace-join-result:' || request_id::text || ':' || result_kind
  )
  on conflict (user_id, event_key) do nothing;
end;
$$;

grant execute on function public.decide_workspace_request(uuid, boolean) to authenticated;
revoke all on function public.decide_workspace_request(uuid, boolean) from public, anon;

-- Remove stale copies of pending founder requests from other founders' inboxes
-- and ensure the original workspace founder has the actionable notification.
delete from public.task_notifications n
using public.workspace_requests r, public.workspaces w
where n.workspace_request_id = r.id
  and n.kind = 'workspace_join_request'
  and r.status = 'pending'
  and r.requested_role = 'admin'
  and w.id = r.workspace_id
  and n.user_id <> w.created_by;

insert into public.task_notifications(
  user_id, workspace_id, kind, title, body, event_key, workspace_request_id
)
select
  w.created_by,
  r.workspace_id,
  'workspace_join_request',
  'Workspace join request',
  r.applicant_name || ' (Founder) wants to join "' || w.name || '".',
  'workspace-join-request:' || r.id::text || ':' || w.created_by::text,
  r.id
from public.workspace_requests r
join public.workspaces w on w.id = r.workspace_id
join public.workspace_members founder
  on founder.workspace_id = r.workspace_id
 and founder.user_id = w.created_by
 and founder.role = 'admin'
where r.status = 'pending'
  and r.requested_role = 'admin'
on conflict (user_id, event_key) do update
  set title = excluded.title,
      body = excluded.body,
      created_at = clock_timestamp(),
      read_at = null,
      workspace_request_id = excluded.workspace_request_id,
      workspace_id = excluded.workspace_id;

notify pgrst, 'reload schema';

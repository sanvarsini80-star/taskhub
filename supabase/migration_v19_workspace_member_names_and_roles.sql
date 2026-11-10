-- Apply after migration_v18_admin_assignment_allowlist.sql.
-- Collect a display name and workspace role when requesting to join, and
-- keep workspace access role separate from the member's displayed role.

alter table public.workspace_requests
  add column if not exists applicant_name text;
alter table public.workspace_requests
  add column if not exists requested_role text not null default 'employee';
update public.workspace_requests r
set applicant_name = coalesce(
  nullif(trim(r.applicant_name), ''),
  nullif(trim(p.display_name), ''),
  'Workspace member'
)
from public.profiles p
where p.user_id = r.user_id and nullif(trim(r.applicant_name), '') is null;
update public.workspace_requests
set applicant_name = 'Workspace member'
where nullif(trim(applicant_name), '') is null;
alter table public.workspace_requests alter column applicant_name set not null;
alter table public.workspace_requests alter column applicant_name set default 'Workspace member';
alter table public.workspace_requests
  drop constraint if exists workspace_requests_requested_role_check;
alter table public.workspace_requests
  add constraint workspace_requests_requested_role_check
  check (requested_role in ('admin', 'co_founder', 'employee'));

alter table public.workspace_members
  add column if not exists display_name text;
alter table public.workspace_members
  add column if not exists workspace_role text not null default 'employee';
update public.workspace_members m
set display_name = coalesce(
      nullif(trim(m.display_name), ''),
      nullif(trim(p.display_name), ''),
      case when m.role = 'admin' then 'Workspace founder' else 'Workspace member' end
    ),
    workspace_role = case when m.role = 'admin' then 'admin' else coalesce(m.workspace_role, 'employee') end
from public.profiles p
where p.user_id = m.user_id;
update public.workspace_members
set display_name = case when role = 'admin' then 'Workspace founder' else 'Workspace member' end
where nullif(trim(display_name), '') is null;
update public.workspace_members
set workspace_role = 'admin'
where role = 'admin' and workspace_role <> 'admin';
alter table public.workspace_members alter column display_name set default 'Workspace member';
alter table public.workspace_members alter column display_name set not null;
alter table public.workspace_members
  drop constraint if exists workspace_members_workspace_role_check;
alter table public.workspace_members
  add constraint workspace_members_workspace_role_check
  check (workspace_role in ('admin', 'co_founder', 'employee'));

-- New workspace creators keep admin access and get a readable workspace name.
create or replace function public.bootstrap_workspace_admin()
returns trigger language plpgsql security definer set search_path = public as $$
declare creator_name text;
begin
  select coalesce(nullif(trim(p.display_name), ''), 'Workspace founder')
    into creator_name
  from public.profiles p where p.user_id = new.created_by;
  insert into public.workspace_members(
    workspace_id, user_id, role, display_name, workspace_role
  ) values (
    new.id,
    new.created_by,
    'admin',
    coalesce(creator_name, 'Workspace founder'),
    'admin'
  );
  return new;
end;
$$;

-- Replace the old one-argument RPC so a join request must include both values.
drop function if exists public.request_workspace_join(uuid);
create function public.request_workspace_join(
  target_workspace uuid,
  p_applicant_name text,
  p_requested_role text
)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  request_row_id uuid;
  workspace_name text;
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
  select w.name into workspace_name from public.workspaces w where w.id = target_workspace;
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
      trim(p_applicant_name) || ' (' || case p_requested_role
        when 'admin' then 'Founder'
        when 'co_founder' then 'Co-founder'
        else 'Employee' end ||
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
  select w.name into workspace_name from public.workspaces w where w.id = req.workspace_id;
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
      '" as ' || case req.requested_role
        when 'admin' then 'Founder'
        when 'co_founder' then 'Co-founder'
        else 'Employee' end || '.',
    'workspace-join-result:' || request_id::text || ':' || result_kind
  )
  on conflict (user_id, event_key) do nothing;
end;
$$;

grant execute on function public.decide_workspace_request(uuid, boolean) to authenticated;
revoke all on function public.decide_workspace_request(uuid, boolean) from public, anon;

update public.task_notifications n
set title = 'Workspace join request',
    body = r.applicant_name || ' (' || case r.requested_role
      when 'admin' then 'Founder'
      when 'co_founder' then 'Co-founder'
      else 'Employee' end ||
      ') wants to join "' || w.name || '".'
from public.workspace_requests r
join public.workspaces w on w.id = r.workspace_id
where n.workspace_request_id = r.id
  and n.kind = 'workspace_join_request'
  and r.status = 'pending';

-- Include the workspace display name and selected role in member data used by
-- task assignment controls and workspace member lists.
drop function if exists public.workspace_member_list(uuid);
create function public.workspace_member_list(target_workspace uuid)
returns table(
  user_id uuid,
  email text,
  role text,
  display_name text,
  workspace_role text,
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
           m.display_name,
           m.workspace_role,
           m.role = 'admin' and exists (
             select 1 from public.workspace_admin_assignment_permissions a
             where a.workspace_id = target_workspace
               and a.admin_id = m.user_id
               and a.employee_id = auth.uid()
           )
    from public.workspace_members m
    left join public.profiles p on p.user_id = m.user_id
    where m.workspace_id = target_workspace
    order by lower(m.display_name), m.role desc;
end;
$$;

grant execute on function public.workspace_member_list(uuid) to authenticated;
revoke all on function public.workspace_member_list(uuid) from public, anon;

notify pgrst, 'reload schema';

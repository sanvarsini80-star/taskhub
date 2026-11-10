-- Apply this after schema.sql. Adds workspace/task approval flows and durable timer sessions.
alter table public.tasks add column if not exists timer_started_at timestamptz;
alter table public.tasks add column if not exists created_by uuid references auth.users(id);
alter table public.tasks add column if not exists created_by_email text;
update public.tasks set created_by=owner_id where created_by is null;
update public.tasks set created_by_email=coalesce((select email from auth.users where id=tasks.created_by),'') where created_by_email is null;
alter table public.tasks alter column created_by set not null;

create table if not exists public.task_assignment_requests (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.tasks(id) on delete cascade,
  requested_by uuid not null references auth.users(id) on delete cascade,
  requested_to uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted','rejected')),
  created_at timestamptz not null default now(), decided_at timestamptz,
  unique(task_id, requested_to)
);
create table if not exists public.task_timer_sessions (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.tasks(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  started_at timestamptz not null, stopped_at timestamptz,
  elapsed_seconds integer check (elapsed_seconds is null or elapsed_seconds >= 0),
  created_at timestamptz not null default now()
);
create table if not exists public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null, updated_at timestamptz not null default now()
);
insert into public.profiles(user_id,email) select id,email from auth.users where email is not null
on conflict(user_id) do update set email=excluded.email;
create or replace function public.sync_profile_email() returns trigger language plpgsql security definer set search_path=public as $$
begin insert into public.profiles(user_id,email) values(new.id,coalesce(new.email,'')) on conflict(user_id) do update set email=excluded.email,updated_at=now(); return new; end $$;
drop trigger if exists taskhub_profile_email on auth.users;
create trigger taskhub_profile_email after insert or update of email on auth.users for each row execute function public.sync_profile_email();
alter table public.profiles enable row level security;

create or replace function public.is_workspace_member(wid uuid, uid uuid default auth.uid())
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.workspace_members where workspace_id=wid and user_id=uid)
$$;
create or replace function public.is_workspace_admin(wid uuid, uid uuid default auth.uid())
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.workspace_members where workspace_id=wid and user_id=uid and role='admin')
$$;

-- Replace starter policies with policies that allow approved workspace workflows.
drop policy if exists "workspace members can view workspaces" on public.workspaces;
drop policy if exists "workspace admins can update workspaces" on public.workspaces;
drop policy if exists "members can view membership" on public.workspace_members;
drop policy if exists "members can request to join" on public.workspace_requests;
drop policy if exists "requester and workspace admin can see requests" on public.workspace_requests;
drop policy if exists "admin can decide requests" on public.workspace_requests;
drop policy if exists "task owner can manage tasks" on public.tasks;
drop policy if exists task_participant_access on public.tasks;
drop policy if exists "task participants can read change history" on public.task_changes;
drop policy if exists "task participants can record changes" on public.task_changes;
drop policy if exists workspace_read on public.workspaces;
drop policy if exists workspace_update on public.workspaces;
drop policy if exists membership_read on public.workspace_members;
drop policy if exists join_requests_read on public.workspace_requests;
drop policy if exists task_participant_read on public.tasks;
drop policy if exists task_assignment_request_read on public.tasks;
drop policy if exists task_owner_insert on public.tasks;
drop policy if exists task_owner_delete on public.tasks;
drop policy if exists task_change_read on public.task_changes;
drop policy if exists task_change_insert on public.task_changes;
create policy workspace_read on public.workspaces for select to authenticated using (created_by=auth.uid() or public.is_workspace_member(id));
create policy workspace_update on public.workspaces for update to authenticated using (public.is_workspace_admin(id)) with check(public.is_workspace_admin(id));
create policy membership_read on public.workspace_members for select to authenticated using (user_id=auth.uid() or public.is_workspace_admin(workspace_id));
create policy join_requests_read on public.workspace_requests for select to authenticated using (user_id=auth.uid() or public.is_workspace_admin(workspace_id));
create policy task_participant_read on public.tasks for select to authenticated using(owner_id=auth.uid() or assigned_to=auth.uid());
create policy task_assignment_request_read on public.tasks for select to authenticated using (
  exists(select 1 from public.task_assignment_requests r where r.task_id=id and r.requested_to=auth.uid() and r.status='pending')
);
create policy task_owner_insert on public.tasks for insert to authenticated with check(
  owner_id=auth.uid() and created_by=auth.uid() and ((scope='personal' and workspace_id is null) or (scope='workspace' and workspace_id is not null and public.is_workspace_admin(workspace_id)))
);
create policy task_owner_delete on public.tasks for delete to authenticated using(owner_id=auth.uid());
create policy task_change_read on public.task_changes for select to authenticated using (
  exists(select 1 from public.tasks t where t.id=task_id and (t.owner_id=auth.uid() or t.assigned_to=auth.uid()))
);
create policy task_change_insert on public.task_changes for insert to authenticated with check(user_id=auth.uid() and exists(select 1 from public.tasks t where t.id=task_id and (t.owner_id=auth.uid() or t.assigned_to=auth.uid())));
alter table public.task_assignment_requests enable row level security;
alter table public.task_timer_sessions enable row level security;
drop policy if exists assignment_request_read on public.task_assignment_requests;
drop policy if exists timer_sessions_read on public.task_timer_sessions;
drop policy if exists profile_self_read on public.profiles;
create policy assignment_request_read on public.task_assignment_requests for select to authenticated using(requested_by=auth.uid() or requested_to=auth.uid());
create policy timer_sessions_read on public.task_timer_sessions for select to authenticated using(user_id=auth.uid());
create policy profile_self_read on public.profiles for select to authenticated using(user_id=auth.uid());

create or replace function public.search_workspaces(search_text text)
returns table(id uuid, name text) language sql stable security definer set search_path=public as $$
  select w.id,w.name from public.workspaces w
  where auth.uid() is not null and length(trim(search_text)) >= 2 and w.name ilike '%'||trim(search_text)||'%'
  order by w.name limit 30
$$;
create or replace function public.workspace_member_list(target_workspace uuid)
returns table(user_id uuid,email text,role text) language plpgsql stable security definer set search_path=public as $$
begin
  if not public.is_workspace_admin(target_workspace) then raise exception 'Workspace admin access required'; end if;
  return query select m.user_id,coalesce(p.email,'Workspace member'),m.role from public.workspace_members m left join public.profiles p on p.user_id=m.user_id where m.workspace_id=target_workspace order by m.role desc,p.email;
end $$;
create or replace function public.workspace_join_requests_for_admin()
returns table(request_id uuid,requester_email text,workspace_id uuid,workspace_name text) language plpgsql stable security definer set search_path=public as $$
begin
  return query select r.id,coalesce(p.email,'New member'),r.workspace_id,w.name from public.workspace_requests r
  join public.workspaces w on w.id=r.workspace_id left join public.profiles p on p.user_id=r.user_id
  where r.status='pending' and public.is_workspace_admin(r.workspace_id) order by r.created_at;
end $$;
create or replace function public.request_workspace_join(target_workspace uuid)
returns uuid language plpgsql security definer set search_path=public as $$
declare request_id uuid;
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  if not exists(select 1 from public.workspaces where id=target_workspace) then raise exception 'Workspace not found'; end if;
  if public.is_workspace_member(target_workspace) then raise exception 'You are already a member'; end if;
  insert into public.workspace_requests(workspace_id,user_id,status) values(target_workspace,auth.uid(),'pending')
  on conflict(workspace_id,user_id) do update set status='pending',created_at=now()
  returning id into request_id;
  return request_id;
end $$;
create or replace function public.decide_workspace_request(request_id uuid, accept boolean)
returns void language plpgsql security definer set search_path=public as $$
declare req public.workspace_requests;
begin
  select * into req from public.workspace_requests where id=request_id for update;
  if req.id is null or not public.is_workspace_admin(req.workspace_id) then raise exception 'Workspace admin access required'; end if;
  if req.status <> 'pending' then raise exception 'This request has already been handled'; end if;
  update public.workspace_requests set status=case when accept then 'accepted' else 'rejected' end where id=request_id;
  if accept then insert into public.workspace_members(workspace_id,user_id,role) values(req.workspace_id,req.user_id,'member') on conflict do nothing; end if;
end $$;

create or replace function public.request_task_assignment(target_task uuid, target_user uuid)
returns uuid language plpgsql security definer set search_path=public as $$
declare t public.tasks; request_id uuid;
begin
  select * into t from public.tasks where id=target_task for update;
  if t.id is null or t.owner_id<>auth.uid() then raise exception 'Only the task creator can assign this task'; end if;
  if t.scope<>'workspace' or not public.is_workspace_admin(t.workspace_id) then raise exception 'Workspace admin access required'; end if;
  if t.timer_started_at is not null then raise exception 'Pause the task timer before assigning it'; end if;
  if not public.is_workspace_member(t.workspace_id,target_user) then raise exception 'Assignee must be a workspace member'; end if;
  insert into public.task_assignment_requests(task_id,requested_by,requested_to,status) values(target_task,auth.uid(),target_user,'pending')
  on conflict(task_id,requested_to) do update set status='pending',created_at=now(),decided_at=null returning id into request_id;
  return request_id;
end $$;
create or replace function public.decide_task_assignment(request_id uuid, accept boolean)
returns void language plpgsql security definer set search_path=public as $$
declare req public.task_assignment_requests; t public.tasks;
begin
  select * into req from public.task_assignment_requests where id=request_id for update;
  if req.id is null or req.requested_to<>auth.uid() then raise exception 'This assignment request is not yours'; end if;
  if req.status<>'pending' then raise exception 'This request has already been handled'; end if;
  select * into t from public.tasks where id=req.task_id for update;
  if t.id is null or t.scope<>'workspace' or not public.is_workspace_member(t.workspace_id,auth.uid()) then raise exception 'This task is no longer available in your workspace'; end if;
  update public.task_assignment_requests set status=case when accept then 'accepted' else 'rejected' end,decided_at=now() where id=request_id;
  if accept then update public.tasks set owner_id=auth.uid(),assigned_to=auth.uid(),updated_at=now() where id=req.task_id; end if;
end $$;
create or replace function public.request_task_assignments(target_tasks uuid[], target_user uuid)
returns integer language plpgsql security definer set search_path=public as $$
declare task_id uuid; task_row public.tasks; total integer:=0;
begin
  foreach task_id in array target_tasks loop
    select * into task_row from public.tasks where id=task_id for update;
    if task_row.id is null or task_row.owner_id<>auth.uid() or task_row.scope<>'workspace' or not public.is_workspace_admin(task_row.workspace_id) then raise exception 'Workspace admin access required'; end if;
    if not public.is_workspace_member(task_row.workspace_id,target_user) then raise exception 'Assignee must be a workspace member'; end if;
    insert into public.task_assignment_requests(task_id,requested_by,requested_to,status) values(task_id,auth.uid(),target_user,'pending')
      on conflict(task_id,requested_to) do update set status='pending',created_at=now(),decided_at=null;
    total:=total+1;
  end loop;
  return total;
end $$;

create or replace function public.change_task_field(target_task uuid, field_name text, new_value text, reason_text text)
returns void language plpgsql security definer set search_path=public as $$
declare t public.tasks; old_text text;
begin
  select * into t from public.tasks where id=target_task for update;
  if t.id is null or (t.owner_id<>auth.uid() and t.assigned_to<>auth.uid()) then raise exception 'Task access required'; end if;
  if length(trim(coalesce(reason_text,'')))<3 then raise exception 'Please provide a specific reason'; end if;
  if field_name='status' then
    if t.status='completed' and new_value<>'completed' then raise exception 'Completed tasks cannot be reopened'; end if;
    if new_value not in ('active','in_progress','completed','archived') then raise exception 'Invalid status'; end if;
    old_text:=t.status;
    if t.timer_started_at is not null and new_value<>'in_progress' then
      update public.tasks set status=new_value,updated_at=now(),archived_at=case when new_value='archived' then now() else null end,timer_started_at=null,
        actual_seconds=actual_seconds+greatest(0,floor(extract(epoch from (clock_timestamp()-t.timer_started_at)))::integer) where id=target_task;
      update public.task_timer_sessions set stopped_at=clock_timestamp(),elapsed_seconds=greatest(0,floor(extract(epoch from (clock_timestamp()-t.timer_started_at)))::integer)
        where task_id=target_task and user_id=auth.uid() and stopped_at is null;
    else
      update public.tasks set status=new_value,updated_at=now(),archived_at=case when new_value='archived' then now() else null end where id=target_task;
    end if;
  elsif field_name='priority' then
    if new_value not in ('low','medium','high','critical') then raise exception 'Invalid priority'; end if;
    old_text:=t.priority; update public.tasks set priority=new_value,updated_at=now() where id=target_task;
  else raise exception 'Unsupported task field'; end if;
  insert into public.task_changes(task_id,user_id,field,old_value,new_value,reason) values(target_task,auth.uid(),field_name,old_text,new_value,trim(reason_text));
end $$;

create or replace function public.start_task_timer(target_task uuid)
returns timestamptz language plpgsql security definer set search_path=public as $$
declare t public.tasks; started timestamptz:=clock_timestamp(); active_count integer; current_user_id uuid:=auth.uid();
begin
  if current_user_id is null then raise exception 'Sign in required'; end if;
  perform pg_advisory_xact_lock(hashtext(current_user_id::text));
  select * into t from public.tasks where id=target_task for update;
  if t.id is null or (t.owner_id<>current_user_id and t.assigned_to<>current_user_id) then raise exception 'Task access required'; end if;
  if t.status in ('completed','archived') then raise exception 'Completed or archived tasks cannot be started'; end if;
  if t.timer_started_at is not null then raise exception 'This timer is already running'; end if;
  select count(*) into active_count from public.tasks
  where timer_started_at is not null and (owner_id=current_user_id or assigned_to=current_user_id);
  if active_count >= 3 then raise exception 'You can run up to three task timers at once'; end if;
  update public.tasks set timer_started_at=started,status='in_progress',updated_at=started where id=target_task;
  insert into public.task_timer_sessions(task_id,user_id,started_at) values(target_task,auth.uid(),started);
  return started;
end $$;
create or replace function public.pause_task_timer(target_task uuid)
returns integer language plpgsql security definer set search_path=public as $$
declare t public.tasks; stopped timestamptz:=clock_timestamp(); duration integer;
begin
  select * into t from public.tasks where id=target_task for update;
  if t.id is null or (t.owner_id<>auth.uid() and t.assigned_to<>auth.uid()) then raise exception 'Task access required'; end if;
  if t.timer_started_at is null then raise exception 'This timer is not running'; end if;
  duration:=greatest(0,floor(extract(epoch from (stopped-t.timer_started_at)))::integer);
  update public.tasks set timer_started_at=null,actual_seconds=actual_seconds+duration,updated_at=stopped where id=target_task;
  update public.task_timer_sessions set stopped_at=stopped,elapsed_seconds=duration where task_id=target_task and stopped_at is null;
  return duration;
end $$;
create or replace function public.move_task_to_personal(target_task uuid)
returns void language plpgsql security definer set search_path=public as $$
declare t public.tasks;
begin
  select * into t from public.tasks where id=target_task for update;
  if t.id is null or (t.owner_id<>auth.uid() and t.assigned_to<>auth.uid()) then raise exception 'Task access required'; end if;
  if t.scope<>'workspace' then raise exception 'Only workspace tasks can be moved to personal'; end if;
  update public.tasks set scope='personal',workspace_id=null,assigned_to=null,updated_at=now() where id=target_task;
end $$;

grant execute on function public.search_workspaces(text) to authenticated;
grant execute on function public.workspace_member_list(uuid) to authenticated;
grant execute on function public.workspace_join_requests_for_admin() to authenticated;
grant execute on function public.request_workspace_join(uuid) to authenticated;
grant execute on function public.decide_workspace_request(uuid,boolean) to authenticated;
grant execute on function public.request_task_assignment(uuid,uuid) to authenticated;
grant execute on function public.decide_task_assignment(uuid,boolean) to authenticated;
grant execute on function public.request_task_assignments(uuid[],uuid) to authenticated;
grant execute on function public.change_task_field(uuid,text,text,text) to authenticated;
grant execute on function public.start_task_timer(uuid) to authenticated;
grant execute on function public.pause_task_timer(uuid) to authenticated;
grant execute on function public.move_task_to_personal(uuid) to authenticated;
revoke all on function public.is_workspace_member(uuid,uuid) from public,anon;
revoke all on function public.is_workspace_admin(uuid,uuid) from public,anon;
grant execute on function public.is_workspace_member(uuid,uuid) to authenticated;
grant execute on function public.is_workspace_admin(uuid,uuid) to authenticated;
revoke all on function public.search_workspaces(text) from public,anon;
revoke all on function public.workspace_member_list(uuid) from public,anon;
revoke all on function public.workspace_join_requests_for_admin() from public,anon;
revoke all on function public.request_workspace_join(uuid) from public,anon;
revoke all on function public.decide_workspace_request(uuid,boolean) from public,anon;
revoke all on function public.request_task_assignment(uuid,uuid) from public,anon;
revoke all on function public.decide_task_assignment(uuid,boolean) from public,anon;
revoke all on function public.request_task_assignments(uuid[],uuid) from public,anon;
revoke all on function public.change_task_field(uuid,text,text,text) from public,anon;
revoke all on function public.start_task_timer(uuid) from public,anon;
revoke all on function public.pause_task_timer(uuid) from public,anon;
revoke all on function public.move_task_to_personal(uuid) from public,anon;

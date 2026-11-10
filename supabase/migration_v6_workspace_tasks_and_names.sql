-- Apply after migration_v5_notification_delete.sql.
-- Enables workspace-member task creation, profile display names, and the
-- workspace assignment flow (admin direct; employee assignment by request).

alter table public.profiles
  add column if not exists display_name text;

update public.profiles p
set display_name = coalesce(
  nullif(trim(u.raw_user_meta_data ->> 'display_name'), ''),
  nullif(trim(u.raw_user_meta_data ->> 'full_name'), ''),
  nullif(trim(u.raw_user_meta_data ->> 'name'), ''),
  p.display_name
)
from auth.users u
where u.id = p.user_id;

create or replace function public.sync_profile_email()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  profile_name text;
begin
  profile_name := coalesce(
    nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''),
    nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
    nullif(trim(new.raw_user_meta_data ->> 'name'), '')
  );
  insert into public.profiles(user_id, email, display_name)
  values(new.id, coalesce(new.email, ''), profile_name)
  on conflict(user_id) do update set
    email = excluded.email,
    display_name = coalesce(excluded.display_name, public.profiles.display_name),
    updated_at = now();
  return new;
end $$;

drop trigger if exists taskhub_profile_email on auth.users;
create trigger taskhub_profile_email
  after insert or update on auth.users
  for each row execute function public.sync_profile_email();

drop function if exists public.workspace_member_list(uuid);
create function public.workspace_member_list(target_workspace uuid)
returns table(user_id uuid, email text, role text, display_name text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_workspace_member(target_workspace) then
    raise exception 'Workspace member access required';
  end if;
  return query
    select m.user_id,
           coalesce(p.email, 'Workspace member'),
           m.role,
           coalesce(nullif(trim(p.display_name), ''), '')
    from public.workspace_members m
    left join public.profiles p on p.user_id = m.user_id
    where m.workspace_id = target_workspace
    order by m.role desc, p.display_name nulls last, p.email;
end $$;

drop policy if exists task_owner_insert on public.tasks;
create policy task_owner_insert on public.tasks
  for insert to authenticated
  with check (
    owner_id = auth.uid()
    and created_by = auth.uid()
    and (
      (scope = 'personal' and workspace_id is null)
      or (scope = 'workspace' and workspace_id is not null
          and public.is_workspace_member(workspace_id))
    )
  );

drop policy if exists task_participant_read on public.tasks;
create policy task_participant_read on public.tasks
  for select to authenticated
  using (
    owner_id = auth.uid()
    or assigned_to = auth.uid()
    or (scope = 'workspace' and public.is_workspace_member(workspace_id))
  );

create or replace function public.workspace_assign_task(target_task uuid, target_user uuid)
returns text language plpgsql security definer set search_path = public as $$
declare
  task_row public.tasks;
begin
  select * into task_row from public.tasks where id = target_task for update;
  if task_row.id is null or task_row.scope <> 'workspace' then
    raise exception 'Workspace task not found';
  end if;
  if not public.is_workspace_member(task_row.workspace_id, auth.uid()) then
    raise exception 'Workspace member access required';
  end if;
  if task_row.timer_started_at is not null then
    raise exception 'Pause the task timer before assigning it';
  end if;
  if target_user = auth.uid() then
    raise exception 'Choose another workspace member to assign this task';
  end if;
  if not public.is_workspace_member(task_row.workspace_id, target_user) then
    raise exception 'Assignee must be a workspace member';
  end if;

  if public.is_workspace_admin(task_row.workspace_id) then
    update public.tasks
    set assigned_to = target_user, updated_at = now()
    where id = target_task;
    return 'assigned';
  end if;

  insert into public.task_assignment_requests(task_id, requested_by, requested_to, status)
  values(target_task, auth.uid(), target_user, 'pending')
  on conflict(task_id, requested_to) do update
    set requested_by = excluded.requested_by,
        status = 'pending', created_at = now(), decided_at = null;
  return 'requested';
end $$;

create or replace function public.decide_task_assignment(request_id uuid, accept boolean)
returns void language plpgsql security definer set search_path = public as $$
declare
  req public.task_assignment_requests;
  task_row public.tasks;
begin
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
      decided_at = now()
  where id = request_id;
  if accept then
    update public.tasks
    set assigned_to = auth.uid(), updated_at = now()
    where id = req.task_id;
  end if;
end $$;

grant execute on function public.workspace_member_list(uuid) to authenticated;
grant execute on function public.workspace_assign_task(uuid, uuid) to authenticated;
grant execute on function public.decide_task_assignment(uuid, boolean) to authenticated;
revoke all on function public.workspace_member_list(uuid) from public, anon;
revoke all on function public.workspace_assign_task(uuid, uuid) from public, anon;
revoke all on function public.decide_task_assignment(uuid, boolean) from public, anon;

notify pgrst, 'reload schema';

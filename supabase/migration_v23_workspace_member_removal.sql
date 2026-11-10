-- Apply after migration_v22_assignment_notification_member_roles.sql.
-- Founders may remove employees and co-founders. Co-founders may leave only
-- their own workspace membership through the settings flow.

create or replace function public._detach_workspace_member(
  target_workspace uuid,
  target_member uuid
)
returns void language plpgsql security definer set search_path = public as $$
declare
  task_row record;
  stopped timestamptz;
  duration integer;
begin
  -- Stop the departing member's active timers and close their sessions first.
  for task_row in
    select id, timer_started_at
    from public.tasks
    where workspace_id = target_workspace
      and (
        assigned_to = target_member
        or (owner_id = target_member and assigned_to is null)
      )
      and timer_started_at is not null
    for update
  loop
    stopped := clock_timestamp();
    duration := greatest(
      0,
      floor(extract(epoch from (stopped - task_row.timer_started_at)))::integer
    );
    update public.task_timer_sessions
    set stopped_at = stopped,
        elapsed_seconds = duration
    where task_id = task_row.id
      and user_id = target_member
      and stopped_at is null;
    update public.tasks
    set timer_started_at = null,
        actual_seconds = actual_seconds + duration,
        status = case when status = 'in_progress' then 'active' else status end,
        updated_at = stopped
    where id = task_row.id;
  end loop;

  -- Return assigned tasks to their creators' workspace task lists.
  insert into public.task_changes(
    task_id, user_id, field, old_value, new_value, reason
  )
  select t.id,
         auth.uid(),
         'assignment',
         target_member::text,
         null,
         'Assignee removed from the workspace'
  from public.tasks t
  where t.workspace_id = target_workspace and t.assigned_to = target_member;

  update public.tasks
  set assigned_to = null,
      updated_at = clock_timestamp()
  where workspace_id = target_workspace and assigned_to = target_member;

  -- Remove stale assignment requests addressed to the departing member.
  delete from public.task_assignment_requests r
  using public.tasks t
  where r.task_id = t.id
    and t.workspace_id = target_workspace
    and r.requested_to = target_member;

  delete from public.workspace_members
  where workspace_id = target_workspace and user_id = target_member;
end;
$$;
revoke all on function public._detach_workspace_member(uuid, uuid)
  from public, anon, authenticated;

create or replace function public.remove_workspace_member(
  target_workspace uuid,
  target_member uuid
)
returns void language plpgsql security definer set search_path = public as $$
declare
  member_role text;
  workspace_creator uuid;
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  if not public.is_workspace_admin(target_workspace) then
    raise exception 'Only workspace founders can remove members';
  end if;
  if target_member = auth.uid() then
    raise exception 'You cannot remove yourself from this screen';
  end if;

  select w.created_by into workspace_creator
  from public.workspaces w where w.id = target_workspace;
  if workspace_creator is null then raise exception 'Workspace not found'; end if;
  if target_member = workspace_creator then
    raise exception 'The workspace founder who created it cannot be removed';
  end if;

  select m.workspace_role into member_role
  from public.workspace_members m
  where m.workspace_id = target_workspace and m.user_id = target_member
  for update;
  if member_role is null then raise exception 'Workspace member not found'; end if;
  if member_role = 'admin' then
    raise exception 'Founders cannot remove other founders';
  end if;
  if member_role not in ('employee', 'co_founder') then
    raise exception 'Only employees and co-founders can be removed here';
  end if;

  perform public._detach_workspace_member(target_workspace, target_member);
end;
$$;
grant execute on function public.remove_workspace_member(uuid, uuid) to authenticated;
revoke all on function public.remove_workspace_member(uuid, uuid) from public, anon;

create or replace function public.leave_workspace_as_cofounder(target_workspace uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  member_role text;
  workspace_creator uuid;
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  select w.created_by into workspace_creator
  from public.workspaces w where w.id = target_workspace;
  if workspace_creator is null then raise exception 'Workspace not found'; end if;
  if auth.uid() = workspace_creator then
    raise exception 'The workspace founder who created it cannot leave';
  end if;

  select m.workspace_role into member_role
  from public.workspace_members m
  where m.workspace_id = target_workspace and m.user_id = auth.uid()
  for update;
  if member_role is distinct from 'co_founder' then
    raise exception 'Only co-founders can leave from this settings option';
  end if;

  perform public._detach_workspace_member(target_workspace, auth.uid());
end;
$$;
grant execute on function public.leave_workspace_as_cofounder(uuid) to authenticated;
revoke all on function public.leave_workspace_as_cofounder(uuid) from public, anon;

notify pgrst, 'reload schema';

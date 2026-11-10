-- Apply after migration_v12_unfinished_task_occurrences.sql.
-- Lets the workspace owner or assigned workspace member transfer a task
-- into their own personal task list while preserving the task and its history.
create or replace function public.move_task_to_personal(target_task uuid)
returns void language plpgsql security definer set search_path=public as $$
declare
  task_row public.tasks;
  current_user_id uuid := auth.uid();
  source_workspace_name text;
  moved_note text;
begin
  if current_user_id is null then
    raise exception 'Sign in required';
  end if;

  select * into task_row
  from public.tasks
  where id = target_task
  for update;

  if task_row.id is null
     or (task_row.owner_id <> current_user_id
         and task_row.assigned_to <> current_user_id) then
    raise exception 'Task access required';
  end if;
  if task_row.scope <> 'workspace' or task_row.workspace_id is null then
    raise exception 'Only workspace tasks can be moved to personal';
  end if;
  if not public.is_workspace_member(task_row.workspace_id, current_user_id) then
    raise exception 'Workspace membership is required to move this task';
  end if;

  select w.name into source_workspace_name
  from public.workspaces w
  where w.id = task_row.workspace_id;
  moved_note := 'Moved from workspace' ||
      case when nullif(trim(source_workspace_name), '') is null
        then '' else ': ' || trim(source_workspace_name) end;

  update public.tasks
  set owner_id = current_user_id,
      scope = 'personal',
      workspace_id = null,
      assigned_to = null,
      description = case
        when nullif(trim(coalesce(task_row.description, '')), '') is null
          then moved_note
        else rtrim(task_row.description) || E'\n\n' || moved_note
      end,
      updated_at = clock_timestamp()
  where id = target_task;

  insert into public.task_changes(task_id, user_id, field, old_value, new_value, reason)
  values (
    target_task,
    current_user_id,
    'scope',
    'workspace',
    'personal',
    moved_note
  );
end;
$$;

grant execute on function public.move_task_to_personal(uuid) to authenticated;
revoke all on function public.move_task_to_personal(uuid) from public, anon;

notify pgrst, 'reload schema';

-- Apply after migration_v24_all_founders_manage_workspace.sql.
-- Ensure assignment notifications always carry the workspace scope so they
-- appear in the workspace inbox (and stay out of the personal inbox).

create or replace function public.set_task_notification_workspace_scope()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.workspace_id is null and new.task_id is not null then
    select t.workspace_id
      into new.workspace_id
    from public.tasks t
    where t.id = new.task_id
      and t.scope = 'workspace';
  end if;
  return new;
end;
$$;

revoke all on function public.set_task_notification_workspace_scope()
  from public, anon, authenticated;

drop trigger if exists task_notification_workspace_scope
  on public.task_notifications;
create trigger task_notification_workspace_scope
  before insert or update of task_id, workspace_id
  on public.task_notifications
  for each row
  execute function public.set_task_notification_workspace_scope();

-- Correct assignment notifications that were created before this trigger.
update public.task_notifications n
set workspace_id = t.workspace_id
from public.tasks t
where n.task_id = t.id
  and t.scope = 'workspace'
  and n.workspace_id is distinct from t.workspace_id;

notify pgrst, 'reload schema';

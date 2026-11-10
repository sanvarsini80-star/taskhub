-- Apply after migration_v10_clear_task.sql.
-- Hides a task occurrence from the task list without archiving or deleting its history.
create table if not exists public.task_occurrence_clears (
  task_id uuid not null references public.tasks(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  occurrence_date date not null,
  created_at timestamptz not null default now(),
  primary key (task_id, user_id, occurrence_date)
);

alter table public.task_occurrence_clears enable row level security;
drop policy if exists task_occurrence_clears_read on public.task_occurrence_clears;
create policy task_occurrence_clears_read
  on public.task_occurrence_clears
  for select to authenticated
  using (user_id = auth.uid());
drop policy if exists task_occurrence_clears_delete on public.task_occurrence_clears;
create policy task_occurrence_clears_delete
  on public.task_occurrence_clears
  for delete to authenticated
  using (user_id = auth.uid());

grant select, delete on public.task_occurrence_clears to authenticated;
revoke all on public.task_occurrence_clears from public, anon;

create or replace function public.clear_task_occurrence(
  target_task uuid,
  occurrence_date date
)
returns void language plpgsql security definer set search_path=public as $$
declare
  inserted_count integer;
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  if occurrence_date is null then raise exception 'Occurrence date required'; end if;
  if not exists (
    select 1 from public.tasks t
    where t.id = target_task
      and (t.owner_id = auth.uid() or t.assigned_to = auth.uid())
  ) then
    raise exception 'Task access required';
  end if;

  insert into public.task_occurrence_clears(task_id, user_id, occurrence_date)
  values (target_task, auth.uid(), occurrence_date)
  on conflict (task_id, user_id, occurrence_date) do nothing;
  get diagnostics inserted_count = row_count;
  if inserted_count > 0 then
    insert into public.task_changes(task_id, user_id, field, old_value, new_value, reason)
    values (
      target_task,
      auth.uid(),
      'occurrence',
      'scheduled',
      'cleared',
      'Cleared from the task list on ' || occurrence_date::text
    );
  end if;
end;
$$;

grant execute on function public.clear_task_occurrence(uuid, date) to authenticated;
revoke all on function public.clear_task_occurrence(uuid, date) from public, anon;

notify pgrst, 'reload schema';

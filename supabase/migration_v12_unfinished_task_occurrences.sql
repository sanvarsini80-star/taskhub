-- Apply after migration_v11_task_occurrence_clears.sql.
-- Stores each deadline that passed without completion so recurring task
-- history stays tied to its original calendar date when the task is restarted.
create table if not exists public.task_unfinished_occurrences (
  task_id uuid not null references public.tasks(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  occurrence_date date not null,
  starts_at timestamptz,
  due_at timestamptz not null,
  restarted_task_id uuid references public.tasks(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (task_id, user_id, occurrence_date)
);

alter table public.task_unfinished_occurrences enable row level security;
drop policy if exists task_unfinished_occurrences_read on public.task_unfinished_occurrences;
create policy task_unfinished_occurrences_read
  on public.task_unfinished_occurrences for select to authenticated
  using (user_id = auth.uid());
drop policy if exists task_unfinished_occurrences_insert on public.task_unfinished_occurrences;
create policy task_unfinished_occurrences_insert
  on public.task_unfinished_occurrences for insert to authenticated
  with check (
    user_id = auth.uid() and exists (
      select 1 from public.tasks t
      where t.id = task_id and (t.owner_id = auth.uid() or t.assigned_to = auth.uid())
    )
  );
drop policy if exists task_unfinished_occurrences_update on public.task_unfinished_occurrences;
create policy task_unfinished_occurrences_update
  on public.task_unfinished_occurrences for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

grant select, insert, update on public.task_unfinished_occurrences to authenticated;
revoke all on public.task_unfinished_occurrences from public, anon;

create or replace function public.record_unfinished_occurrence()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.task_changes(task_id, user_id, field, old_value, new_value, reason)
  values (
    new.task_id,
    new.user_id,
    'occurrence',
    'scheduled',
    'unfinished',
    'Deadline passed without completing the occurrence on ' || new.occurrence_date::text
  );
  return new;
end;
$$;
revoke all on function public.record_unfinished_occurrence() from public, anon, authenticated;

drop trigger if exists task_unfinished_occurrence_history on public.task_unfinished_occurrences;
create trigger task_unfinished_occurrence_history
  after insert on public.task_unfinished_occurrences
  for each row execute function public.record_unfinished_occurrence();

notify pgrst, 'reload schema';

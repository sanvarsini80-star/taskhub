-- Run in the Supabase SQL editor before launching Task Hub.
create extension if not exists pgcrypto;

create table if not exists public.workspaces (
  id uuid primary key default gen_random_uuid(), name text not null unique,
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
create table if not exists public.workspace_members (
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('admin','member')),
  joined_at timestamptz not null default now(), primary key(workspace_id,user_id)
);
create table if not exists public.workspace_requests (
  id uuid primary key default gen_random_uuid(), workspace_id uuid not null references public.workspaces(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted','rejected')),
  created_at timestamptz not null default now(), unique(workspace_id,user_id)
);
create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id) on delete cascade,
  title text not null, description text not null default '',
  status text not null default 'active' check (status in ('active','in_progress','completed','archived')),
  priority text not null default 'medium' check (priority in ('low','medium','high','critical')),
  scope text not null default 'personal' check (scope in ('personal','workspace')),
  workspace_id uuid references public.workspaces(id) on delete cascade,
  assigned_to uuid references auth.users(id) on delete set null,
  starts_at timestamptz, due_at timestamptz, estimated_minutes integer not null default 0 check (estimated_minutes >= 0),
  actual_seconds integer not null default 0 check (actual_seconds >= 0),
  recurrence text, archived_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.task_changes (
  id uuid primary key default gen_random_uuid(), task_id uuid not null references public.tasks(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  field text not null, old_value text, new_value text, reason text not null,
  created_at timestamptz not null default now()
);
alter table public.workspaces enable row level security;
alter table public.workspace_members enable row level security;
alter table public.workspace_requests enable row level security;
alter table public.tasks enable row level security;
alter table public.task_changes enable row level security;

create policy "workspace members can view workspaces" on public.workspaces for select using (
  created_by = auth.uid() or exists (select 1 from public.workspace_members m where m.workspace_id=id and m.user_id=auth.uid())
);
create policy "signed in users can create workspaces" on public.workspaces for insert with check (created_by=auth.uid());
create policy "workspace admins can update workspaces" on public.workspaces for update using (
  exists(select 1 from public.workspace_members m where m.workspace_id=id and m.user_id=auth.uid() and m.role='admin')
);
create policy "members can view membership" on public.workspace_members for select using (
  user_id=auth.uid()
);
create policy "members can request to join" on public.workspace_requests for insert with check(user_id=auth.uid());
create policy "requester and workspace admin can see requests" on public.workspace_requests for select using (
  user_id=auth.uid() or exists(select 1 from public.workspace_members m where m.workspace_id=workspace_id and m.user_id=auth.uid() and m.role='admin')
);
create policy "admin can decide requests" on public.workspace_requests for update using (
  exists(select 1 from public.workspace_members m where m.workspace_id=workspace_id and m.user_id=auth.uid() and m.role='admin')
);
create policy "task owner can manage tasks" on public.tasks for all using(owner_id=auth.uid() or assigned_to=auth.uid()) with check(owner_id=auth.uid() or assigned_to=auth.uid());
create policy "task participants can read change history" on public.task_changes for select using (
  exists(select 1 from public.tasks t where t.id=task_id and (t.owner_id=auth.uid() or t.assigned_to=auth.uid()))
);
create policy "task participants can record changes" on public.task_changes for insert with check(user_id=auth.uid());

-- Workspace creators are admins from the moment the workspace is created.
create or replace function public.bootstrap_workspace_admin() returns trigger language plpgsql security definer set search_path=public as $$
begin insert into public.workspace_members(workspace_id,user_id,role) values(new.id,new.created_by,'admin'); return new; end $$;
drop trigger if exists workspace_admin_on_create on public.workspaces;
create trigger workspace_admin_on_create after insert on public.workspaces for each row execute function public.bootstrap_workspace_admin();


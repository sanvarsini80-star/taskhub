-- Apply after migration_v19_workspace_member_names_and_roles.sql.
-- Changes user-facing "Admin" role wording to "Founder" without changing
-- the internal admin access role used by workspace authorization.

create or replace function public.workspace_join_role_label(role_value text)
returns text language sql immutable set search_path = public as $$
  select case role_value
    when 'admin' then 'Founder'
    when 'co_founder' then 'Co-founder'
    else 'Employee'
  end
$$;
grant execute on function public.workspace_join_role_label(text) to authenticated;
revoke all on function public.workspace_join_role_label(text) from public, anon;

-- Update the existing join request RPC while retaining its access checks and
-- notification behavior from v19.
do $$
declare
  definition text;
  old_expression text := $old$replace(initcap(p_requested_role), '_', ' ')$old$;
begin
  definition := pg_get_functiondef(
    'public.request_workspace_join(uuid,text,text)'::regprocedure
  );
  if position(old_expression in definition) > 0 then
    definition := replace(
      definition,
      old_expression,
      'public.workspace_join_role_label(p_requested_role)'
    );
  end if;
  execute definition;
end;
$$;

do $$
declare
  definition text;
  old_expression text := $old$replace(initcap(req.requested_role), '_', ' ')$old$;
begin
  definition := pg_get_functiondef(
    'public.decide_workspace_request(uuid,boolean)'::regprocedure
  );
  if position(old_expression in definition) > 0 then
    definition := replace(
      definition,
      old_expression,
      'public.workspace_join_role_label(req.requested_role)'
    );
  end if;
  definition := replace(
    definition,
    $old$'A workspace admin'$old$,
    $new$'A workspace founder'$new$
  );
  execute definition;
end;
$$;

do $$
declare
  definition text;
begin
  definition := pg_get_functiondef(
    'public.bootstrap_workspace_admin()'::regprocedure
  );
  definition := replace(
    definition,
    $old$'Workspace admin'$old$,
    $new$'Workspace founder'$new$
  );
  execute definition;
end;
$$;

-- Keep existing fallback member names and notification history consistent.
update public.workspace_members
set display_name = 'Workspace founder'
where display_name = 'Workspace admin';

update public.task_notifications
set body = replace(body, '(Admin)', '(Founder)')
where kind = 'workspace_join_request'
  and body like '%(Admin)%';

update public.task_notifications
set body = replace(body, ' as Admin.', ' as Founder.')
where kind = 'workspace_join_accepted'
  and body like '% as Admin.';

update public.task_notifications
set body = replace(body, 'A workspace admin', 'A workspace founder')
where kind in ('workspace_join_accepted', 'workspace_join_rejected')
  and body like '%A workspace admin%';

notify pgrst, 'reload schema';

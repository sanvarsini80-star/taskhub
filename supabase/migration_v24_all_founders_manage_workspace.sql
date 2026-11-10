-- Apply after migration_v23_workspace_member_removal.sql.
-- All workspace founders have the existing admin access, can decide join
-- requests, and receive an inbox notification for every pending join request.

do $$
declare
  definition text;
  updated_definition text;
begin
  definition := pg_get_functiondef(
    'public.request_workspace_join(uuid,text,text)'::regprocedure
  );
  updated_definition := regexp_replace(
    definition,
    $pattern$and [(]p_requested_role <> 'admin' or m[.]user_id = creator_id[)]$pattern$,
    '',
    'g'
  );
  if updated_definition = definition then
    raise exception 'Could not update request_workspace_join founder routing';
  end if;
  execute updated_definition;
end;
$$;

do $$
declare
  definition text;
  updated_definition text;
begin
  definition := pg_get_functiondef(
    'public.decide_workspace_request(uuid,boolean)'::regprocedure
  );
  updated_definition := regexp_replace(
    definition,
    $pattern$if req[.]requested_role = 'admin' and auth[.]uid[(][)] <> workspace_creator then[[:space:]]+raise exception 'Only the original workspace founder can approve another founder';[[:space:]]+end if;$pattern$,
    '',
    'g'
  );
  if updated_definition = definition then
    raise exception 'Could not update decide_workspace_request founder authorization';
  end if;
  execute updated_definition;
end;
$$;

-- Ensure every current founder can act on all still-pending join requests,
-- including requests created before this migration.
insert into public.task_notifications(
  user_id, workspace_id, kind, title, body, event_key, workspace_request_id
)
select
  founder.user_id,
  request.workspace_id,
  'workspace_join_request',
  'Workspace join request',
  coalesce(nullif(trim(request.applicant_name), ''), 'A new member') ||
    ' (' || public.workspace_join_role_label(request.requested_role) ||
    ') wants to join "' || workspace.name || '".',
  'workspace-join-request:' || request.id::text || ':' || founder.user_id::text,
  request.id
from public.workspace_requests request
join public.workspaces workspace on workspace.id = request.workspace_id
join public.workspace_members founder
  on founder.workspace_id = request.workspace_id
 and founder.role = 'admin'
where request.status = 'pending'
on conflict (user_id, event_key) do update
  set title = excluded.title,
      body = excluded.body,
      created_at = clock_timestamp(),
      read_at = null,
      workspace_request_id = excluded.workspace_request_id,
      workspace_id = excluded.workspace_id;

notify pgrst, 'reload schema';

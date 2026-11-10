# Task Hub

Responsive Flutter app for personal and workspace task planning. The app uses Supabase Auth and Postgres; it has no seeded/sample tasks.

## Connect a Supabase project

1. Run [`supabase/schema.sql`](supabase/schema.sql), then apply `migration_v2.sql` through `migration_v24_all_founders_manage_workspace.sql` in numeric order in the Supabase SQL editor. Each migration includes its filename and prerequisite in its opening comment. The later migrations add occurrence clearing and unfinished history, workspace assignment requests and notifications, member roles, founder permissions, and member removal.
2. In Supabase Auth, enable Email and Google providers. For email/password sign-up without confirmation, turn **Confirm email** off under **Authentication → Sign In / Providers → Email**. Add the app's current browser origin (shown in Chrome's address bar, e.g. `http://localhost:PORT/**`) under **Authentication → URL Configuration → Redirect URLs**. For Google, configure OAuth credentials and use `https://oifekikglmtujukwilgi.supabase.co/auth/v1/callback` as the Google provider's authorized redirect URI.
3. Launch the app:

```powershell
flutter run -d chrome
```

For a Windows desktop build, replace `-d chrome` with `-d windows`. The project URL and publishable key are configured in `lib/main.dart`.

## Included

- Email/password sign up and sign in, plus Google OAuth.
- Personal tasks and workspace creation, name search, join requests, and admin approval.
- Workspace staff selection, assignment requests, employee accept/reject, and personal/workspace moves.
- Task creation from the list and calendar, voice-to-text names, estimates, start/end times for today and tomorrow, weekday recurrence with rolling month selection for one-month and one-year schedules, filters and sorting. Each repeating schedule remains one task row and appears on matching calendar dates.
- Unfinished tasks are separated from active work when their deadline passes, shown as red on their Calendar dates, and can be restarted with a new date, time window, and repeat schedule while preserving occurrence history.
- Reason-required status and priority changes with history; completed tasks cannot be reopened.
- Server-timed pause/resume sessions for up to three concurrent tasks, synchronized combined sessions, timer history after reload, scheduled-task start prompts, and audible in-app deadline alerts.
- Persistent notification inbox and Android system alarms with sound for task starts, deadlines approaching within ten minutes, and deadlines reached. Android alarm schedules are restored after device reboot.
- Dashboard counts and insights for status, priority, estimated time, and tracked time.
- Row-level security and database RPCs for approval, timer, and change workflows.

## Current boundaries

Android alarms use the device notification permission. When exact-alarm access is unavailable, Android schedules an allow-while-idle alarm and may deliver it a little later. Browser and Windows reminders run while TaskHub is open. Voice input requires microphone permission and a browser/device with speech recognition support. Google sign-in requires provider OAuth credentials and configured redirect URLs in Supabase. No sample tasks are seeded.

The Supabase project URL and publishable key are configured in `lib/main.dart`; the publishable key is intended for client apps. Dashboard and task data load from the connected project after signing in.

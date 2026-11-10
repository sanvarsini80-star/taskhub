# TaskHub cartoon UI implementation checklist

This checklist follows the current Flutter source in `lib/main.dart`. The shared `TaskHubMascot` now paints a puppy and kitten together and animates them through a running orbit, hop, float, paw wave, blink, mood gaze and tap reaction. The application has five authenticated content tabs and shared setup/authentication screens. It does not currently define standalone Profile or Settings routes; account controls are in the app shell.

| Screen / flow | Reusable cartoon integration | Animation / interaction | UI treatment | Functional regression |
| --- | --- | --- | --- | --- |
| Setup / first-run configuration | Planning mascot banner | Float, tap reaction, animated banner | Implemented | Not exercised against a configured Supabase account |
| Splash / auth gate | Welcome mascot from shared painter | Idle float and tap reaction | Implemented | Release APK installed and launched on Android emulator; login screen rendered |
| Login / Google sign-in | Welcome mascot | Idle float and tap reaction | Implemented | Login screen visually checked in emulator; valid credentials/provider flow not exercised |
| Shell, workspace chooser and navigation | Shared branded mark; teamwork expression in workspace controls | Violet selected navigation; animated tab fade/slide; workspace review feedback | Implemented | Workspace data operations require authenticated account |
| Home dashboard | Welcome mascot and existing task-card status expressions | Animated navigation, responsive metrics/cards | Implemented | Reads live Supabase data; authenticated data load not verified here |
| Task list, search, filters and sorting | Planning empty state and status-aware task marks | Animated list switch and card border; mascot reacts to taps | Implemented | Task queries/mutations require authenticated account |
| Create task, speech input and recurrence | Planning/listening mascot banner | Listening expression changes; button and chip feedback | Implemented | Dictation/device permissions and task persistence need device/account validation |
| Status / priority reason dialogs | Focus and insight expressions | Animated mascot reaction; existing reason-required guard retained | Implemented | Database audit updates need authenticated account |
| Task change history | Insight mascot | Dialog and mascot response | Implemented | History query needs authenticated account |
| Calendar and selected-day agenda | Calendar expression; calendar empty state | Selected-day content and calendar interactions use current selected date | Implemented | Live task/repeat records require authenticated account |
| Calendar task planning and date/time dialogs | Calendar and focus mascot banners inside custom date and time pickers | Exact day/hour/minute selection, speech, weekday recurrence chips and scheduled-time callbacks | Implemented | Picker selection is widget-tested; task persistence and recurrence need authenticated account |
| Time tracking / focus | Focus or celebration mascot banner; focus-state expression | Existing live timer/ring; animated progress and task card state | Implemented | Timer start/pause/resume requires authenticated account and device timing validation |
| Smart analytics | Insight mascot | Insight bars animate to current database-derived values | Implemented | Metrics require authenticated records to validate values |
| Notification center | Reminder mascot and reminder empty state | Existing mark-read actions with animated mascot affordance | Implemented | Notification sync/alarms require authenticated account and OS permission validation |
| Scheduled-start confirmation | Reminder mascot and contextual banner | Start action and dialog feedback | Implemented | Requires a real scheduled task and authenticated account |
| Loading, empty and error states | Shared expressive mascot empty states | Floating and tap reaction; animated transitions where list changes | Implemented | Error states can be rendered; backend-specific cases require live account |

## Verification status

- Source audit completed for the route classes, shell tabs, dialogs, calendar/time pickers, workspace review surfaces, and reusable empty states present in the current source.
- No standalone profile/settings page is present in the audited Flutter source.
- Static analysis of `lib/main.dart` and `lib/ui/taskhub_mascot_kit.dart` completed with no errors (42 pre-existing informational lint notices).
- Widget tests for the violet action button and mascot tap reaction pass. Release APK builds, installs, and launches to the login screen on the Android emulator.
- Branded date picker selection and exact-minute time selection pass widget tests; these checks use real widgets and no task fixtures.
- Authenticated end-to-end regression checks remain unverified without a test account. Workspace/task persistence, live metrics, timer records, speech permissions, and OS alarms require that account and applicable device permissions.
- Supabase-backed flows are not marked end-to-end verified without a real test account and live records. No sample task records are added by this redesign.

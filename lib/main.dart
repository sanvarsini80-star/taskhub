import 'dart:async';
import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ui/taskhub_mascot_kit.dart';

const ink = Color(0xFF2B1D46),
    muted = Color(0xFF7B708F),
    violet = Color(0xFF6841C8),
    secondaryViolet = Color(0xFF8964E8),
    softPurple = Color(0xFFB49AFF),
    lilac = Color(0xFFE8DEFF),
    canvas = Color(0xFFF8F5FF),
    line = Color(0xFFEAE3F7),
    pink = Color(0xFFFF91B5),
    sunshine = Color(0xFFFFD36E),
    mint = Color(0xFF76DDBB),
    sky = Color(0xFF75B9FF),
    pinkTint = Color(0xFFFFEDF4),
    sunshineTint = Color(0xFFFFF7E2),
    mintTint = Color(0xFFE8FBF4),
    skyTint = Color(0xFFEAF5FF),
    success = Color(0xFF3FA783),
    warning = Color(0xFFB78425),
    danger = Color(0xFFD9577C);

const violetGradient = LinearGradient(
  colors: [violet, secondaryViolet],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);
const supabaseUrl = 'https://oifekikglmtujukwilgi.supabase.co';
const supabasePublishableKey = 'sb_publishable_rqj6iSn0T8lxVSKInZZPKA_GZGO4GOK';

const _weekdays = <String>[
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String _repeatLabel(
  List<String> days,
  String duration, [
  String frequency = 'Weekly',
  List<String> months = const [],
]) {
  final ordered = [...days]
    ..sort((a, b) => _weekdays.indexOf(a).compareTo(_weekdays.indexOf(b)));
  final names = ordered.length < 2
      ? ordered.join()
      : '${ordered.take(ordered.length - 1).join(', ')} and ${ordered.last}';
  return switch (frequency) {
    'Daily' => 'Daily for $duration',
    'Monthly' =>
      'Monthly: $names${months.isEmpty ? '' : ' on ${months.join(', ')}'} for $duration',
    'Yearly' =>
      'Yearly: $names${months.isEmpty ? '' : ' on ${months.join(', ')}'} for $duration',
    _ =>
      'Weekly: $names${months.isEmpty ? '' : ' on ${months.join(', ')}'} for $duration',
  };
}

String _repeatFrequency(String? recurrence) {
  if (recurrence == null) return 'None';
  if (recurrence.startsWith('Daily')) return 'Daily';
  if (recurrence.startsWith('Monthly')) return 'Monthly';
  if (recurrence.startsWith('Yearly')) return 'Yearly';
  return recurrence.startsWith('Weekly:') || recurrence.startsWith('Every ')
      ? 'Weekly'
      : 'None';
}

bool _occursOnDate(DateTime date, DateTime firstDue, String? recurrence) {
  final frequency = _repeatFrequency(recurrence);
  if (frequency == 'None') return DateUtils.isSameDay(date, firstDue);
  final startDay = DateTime(firstDue.year, firstDue.month, firstDue.day);
  final dateOnly = DateTime(date.year, date.month, date.day);
  if (dateOnly.isBefore(startDay) ||
      dateOnly.isAfter(_repeatEnd(firstDue, recurrence))) {
    return false;
  }
  final months = _repeatMonths(recurrence);
  if (months.isNotEmpty) {
    return months.contains(_monthKey(date)) &&
        _repeatDays(recurrence).contains(_weekdays[date.weekday - 1]);
  }
  return switch (frequency) {
    'Daily' => true,
    'Weekly' => _repeatDays(recurrence).contains(_weekdays[date.weekday - 1]),
    'Monthly' =>
      date.day ==
          math.min(
            firstDue.day,
            DateUtils.getDaysInMonth(date.year, date.month),
          ),
    'Yearly' =>
      date.month == firstDue.month &&
          date.day ==
              math.min(
                firstDue.day,
                DateUtils.getDaysInMonth(date.year, date.month),
              ),
    _ => false,
  };
}

int _timeWindowMinutes(TimeOfDay start, TimeOfDay end) =>
    (end.hour * 60 + end.minute) - (start.hour * 60 + start.minute);

int? _taskEstimateMinutes(TimeOfDay start, TimeOfDay end) {
  final minutes = _timeWindowMinutes(start, end);
  return minutes <= 0 ? null : minutes.clamp(1, 24 * 60);
}

String _formatDurationMinutes(int minutes) {
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final remainingMinutes = minutes % 60;
  return remainingMinutes == 0
      ? '$hours hr'
      : '$hours hr $remainingMinutes min';
}

List<String> _repeatDays(String? recurrence) {
  if (recurrence == null) return const [];
  final prefix = recurrence.startsWith('Weekly: ')
      ? 'Weekly: '
      : recurrence.startsWith('Monthly: ')
      ? 'Monthly: '
      : recurrence.startsWith('Yearly: ')
      ? 'Yearly: '
      : recurrence.startsWith('Every ')
      ? 'Every '
      : null;
  if (prefix == null) return const [];
  final end = recurrence.indexOf(' for ');
  if (end < 0) return const [];
  final schedule = recurrence.substring(prefix.length, end).split(' on ').first;
  return schedule
      .replaceAll(' and ', ', ')
      .split(',')
      .map((day) => day.trim())
      .map(
        (short) => _weekdays.firstWhere(
          (day) => day.toLowerCase().startsWith(short.toLowerCase()),
          orElse: () => '',
        ),
      )
      .where((day) => day.isNotEmpty)
      .toList();
}

String _monthKey(DateTime month) =>
    '${month.year}-${month.month.toString().padLeft(2, '0')}';

List<DateTime> _repeatMonthOptions(DateTime start, String duration) {
  final monthCount = duration == '1 year' ? 12 : 1;
  final startIndex = start.year * 12 + start.month - 1;
  return [
    for (var offset = 0; offset <= monthCount; offset++)
      DateTime((startIndex + offset) ~/ 12, (startIndex + offset) % 12 + 1),
  ];
}

Set<String> _repeatMonths(String? recurrence) {
  if (recurrence == null) return const {};
  final on = recurrence.indexOf(' on ');
  final end = recurrence.indexOf(' for ');
  if (on < 0 || end <= on) return const {};
  return recurrence
      .substring(on + 4, end)
      .split(',')
      .map((month) => month.trim())
      .where((month) => RegExp(r'^\d{4}-\d{2}$').hasMatch(month))
      .toSet();
}

String _repeatSummary(String recurrence) {
  final frequency = _repeatFrequency(recurrence);
  final durationStart = recurrence.lastIndexOf(' for ');
  final duration = durationStart < 0
      ? ''
      : recurrence.substring(durationStart + 5).trim();
  final days = _repeatDays(
    recurrence,
  ).map((day) => day.substring(0, 3)).join(', ');
  final months = _repeatMonths(recurrence).toList()..sort();
  if (frequency == 'Daily') {
    return 'Daily${duration.isEmpty ? '' : ' - $duration'}';
  }
  if (months.isEmpty) {
    final parts = <String>[frequency];
    if (days.isNotEmpty) parts.add(days);
    if (duration.isNotEmpty) parts.add(duration);
    return parts.join(' - ');
  }
  String monthLabel(String value) => DateFormat('MMM yyyy').format(
    DateTime(
      int.parse(value.substring(0, 4)),
      int.parse(value.substring(5, 7)),
    ),
  );
  final monthRange = months.length == 1
      ? monthLabel(months.first)
      : '${monthLabel(months.first)} to ${monthLabel(months.last)}';
  final parts = <String>[frequency];
  if (days.isNotEmpty) parts.add(days);
  parts.add(monthRange);
  if (duration.isNotEmpty) parts.add(duration);
  return parts.join(' - ');
}

bool _needsMonthSelection(String frequency, String duration) =>
    frequency == 'Monthly' ||
    frequency == 'Yearly' ||
    (frequency == 'Weekly' && duration == '1 year');

String? _repeatSelectionError({
  required String frequency,
  required String duration,
  required Set<String> days,
  required Set<String> months,
  required DateTime? start,
}) {
  if (!{'Weekly', 'Monthly', 'Yearly'}.contains(frequency)) return null;
  if (days.isEmpty)
    return 'Choose at least one weekday for this repeat schedule.';
  if (_needsMonthSelection(frequency, duration) && months.isEmpty) {
    return 'Choose at least one month for this repeat schedule.';
  }
  if (start != null &&
      _firstSelectedOccurrence(start, frequency, duration, days, months) ==
          null) {
    return 'No selected weekday falls in the chosen months. Select another month or weekday.';
  }
  return null;
}

DateTime? _firstSelectedOccurrence(
  DateTime start,
  String frequency,
  String duration,
  Set<String> days,
  Set<String> months,
) {
  final end = _repeatEnd(start, 'repeat for $duration');
  for (
    var date = DateTime(start.year, start.month, start.day);
    !date.isAfter(end);
    date = date.add(const Duration(days: 1))
  ) {
    final weekdayMatches =
        !{'Weekly', 'Monthly', 'Yearly'}.contains(frequency) ||
        days.contains(_weekdays[date.weekday - 1]);
    final monthMatches = months.isEmpty || months.contains(_monthKey(date));
    if (weekdayMatches && monthMatches) return date;
  }
  return null;
}

Widget _repeatMonthSelector(
  DateTime? start,
  String duration,
  Set<String> selectedMonths,
  StateSetter refresh,
) {
  if (start == null) {
    return const Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('Choose a task date to see the available months.'),
      ),
    );
  }
  final options = _repeatMonthOptions(start, duration);
  final firstMonth = DateFormat('MMM yyyy').format(options.first);
  final lastMonth = DateFormat('MMM yyyy').format(options.last);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Padding(
        padding: EdgeInsets.only(top: 10, bottom: 5),
        child: Text('Choose months for this schedule'),
      ),
      const Padding(
        padding: EdgeInsets.only(bottom: 4),
        child: Text(
          'It repeats on each selected weekday in the months you choose.',
          style: TextStyle(color: muted, fontSize: 12),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          '$firstMonth to $lastMonth',
          style: const TextStyle(color: muted, fontSize: 12),
        ),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: () => refresh(() {
            if (selectedMonths.length == options.length) {
              selectedMonths.clear();
            } else {
              selectedMonths
                ..clear()
                ..addAll(options.map(_monthKey));
            }
          }),
          child: Text(
            selectedMonths.length == options.length
                ? 'Clear month selection'
                : 'Select all months',
          ),
        ),
      ),
      Wrap(
        spacing: 6,
        runSpacing: 2,
        children: [
          for (final month in options)
            FilterChip(
              label: Text(DateFormat('MMM yyyy').format(month)),
              selected: selectedMonths.contains(_monthKey(month)),
              onSelected: (selected) => refresh(() {
                if (selected) {
                  selectedMonths.add(_monthKey(month));
                } else {
                  selectedMonths.remove(_monthKey(month));
                }
              }),
            ),
        ],
      ),
    ],
  );
}

DateTime _repeatEnd(DateTime start, String? recurrence) {
  final addYear = recurrence?.endsWith('1 year') ?? false;
  final target = DateTime(
    start.year + (addYear ? 1 : 0),
    start.month + (addYear ? 0 : 1),
  );
  final year = target.year;
  final month = target.month;
  final lastDay = DateUtils.getDaysInMonth(year, month);
  return DateTime(
    year,
    month,
    math.min(start.day, lastDay),
    start.hour,
    start.minute,
  );
}

List<(DateTime, DateTime?)> _scheduledOccurrences(
  Map<String, dynamic> task,
  DateTime from,
  DateTime through,
) {
  if (task['due_at'] == null) return const [];
  final firstDeadline = DateTime.parse('${task['due_at']}').toLocal();
  final firstStart = task['starts_at'] == null
      ? firstDeadline
      : DateTime.parse('${task['starts_at']}').toLocal();
  final recurrence = task['recurrence'] as String?;
  final days = _repeatDays(recurrence);
  final months = _repeatMonths(recurrence);
  final frequency = _repeatFrequency(recurrence);
  final startDay = DateTime(firstStart.year, firstStart.month, firstStart.day);
  final endDay = DateTime(
    firstDeadline.year,
    firstDeadline.month,
    firstDeadline.day,
  );
  if (frequency == 'None') {
    return firstStart.isBefore(through) &&
            endDay.add(const Duration(days: 1)).isAfter(from)
        ? [(firstStart, firstDeadline)]
        : const [];
  }
  final repeatUntil = _repeatEnd(firstStart, recurrence);
  final first = from.isAfter(startDay)
      ? DateTime(from.year, from.month, from.day)
      : startDay;
  final last = through.isBefore(repeatUntil) ? through : repeatUntil;
  final results = <(DateTime, DateTime?)>[];
  for (
    var day = first;
    !day.isAfter(last);
    day = day.add(const Duration(days: 1))
  ) {
    if (months.isNotEmpty) {
      if (!months.contains(_monthKey(day)) ||
          !days.contains(_weekdays[day.weekday - 1])) {
        continue;
      }
    } else if (frequency == 'Weekly' &&
        !days.contains(_weekdays[day.weekday - 1])) {
      continue;
    }
    final recurringDay = math.min(
      firstStart.day,
      DateUtils.getDaysInMonth(day.year, day.month),
    );
    if (frequency == 'Monthly' && day.day != recurringDay) continue;
    if (frequency == 'Yearly' &&
        (day.month != firstStart.month || day.day != recurringDay)) {
      continue;
    }
    final start = DateTime(
      day.year,
      day.month,
      day.day,
      firstStart.hour,
      firstStart.minute,
    );
    final deadline = DateTime(
      day.year,
      day.month,
      day.day,
      firstDeadline.hour,
      firstDeadline.minute,
    );
    results.add((start, deadline));
  }
  return results;
}

const _nativeAlarmChannel = MethodChannel('taskhub/alarms');

Future<void> _showRunningTimer(
  String title,
  DateTime startedAt, {
  String? body,
}) async {
  if (kIsWeb) return;
  try {
    await _nativeAlarmChannel.invokeMethod<void>('showRunningTimer', {
      'title': title,
      'body': body ?? 'Task timer is running',
      'startedAt': startedAt.millisecondsSinceEpoch,
    });
  } on PlatformException {
    // The timer continues in the app when system notifications are unavailable.
  } on MissingPluginException {
    // Other platforms do not show the Android running timer notification.
  }
}

Future<void> _syncRunningTimerNotification(List<HubTask> runningTasks) async {
  if (runningTasks.isEmpty) {
    await _hideRunningTimer();
    return;
  }
  final earliest = runningTasks
      .map((task) => task.timerStarted!)
      .reduce((a, b) => a.isBefore(b) ? a : b);
  final title = runningTasks.length == 1
      ? runningTasks.first.title
      : '${runningTasks.length} TaskHub timers running';
  final names = runningTasks.map((task) => task.title).join(', ');
  await _showRunningTimer(title, earliest.toLocal(), body: names);
}

Future<void> _hideRunningTimer() async {
  if (kIsWeb) return;
  try {
    await _nativeAlarmChannel.invokeMethod<void>('hideRunningTimer');
  } on PlatformException {
    // The task timer remains available in the app.
  } on MissingPluginException {
    // Other platforms do not show the Android running timer notification.
  }
}

Future<bool> _showNativeTaskNotification({
  required String title,
  required String body,
  required String eventKey,
}) async {
  if (kIsWeb) return false;
  try {
    return await _nativeAlarmChannel.invokeMethod<bool>(
          'showTaskNotification',
          {'title': title, 'body': body, 'notificationId': eventKey.hashCode},
        ) ??
        false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}

Future<void> _scheduleNativeTaskAlarms(Map<String, dynamic> task) async {
  if (kIsWeb || task['due_at'] == null) return;
  final now = DateTime.now();
  final due = DateTime.parse('${task['due_at']}').toLocal();
  final recurrence = task['recurrence'] as String?;
  final through = recurrence == null
      ? due.add(const Duration(days: 1))
      : _repeatEnd(due, recurrence).add(const Duration(days: 1));
  final alarms = <Map<String, Object>>[];
  for (final (start, deadline) in _scheduledOccurrences(
    task,
    now.subtract(const Duration(minutes: 10)),
    through,
  )) {
    final id = '${task['id']}';
    final day = DateFormat('yyyy-MM-dd').format(start);
    void add(String suffix, DateTime at, String title, String body) {
      if (at.isAfter(now)) {
        alarms.add({
          'id': '$id:$day:$suffix',
          'at': at.millisecondsSinceEpoch,
          'title': title,
          'body': body,
        });
      }
    }

    if (task['starts_at'] != null) {
      add(
        'start',
        start,
        '${task['title']} · time to start',
        'Your scheduled task is ready. Tap to start it.',
      );
    }
    if (deadline != null) {
      add(
        'deadline-soon',
        deadline.subtract(const Duration(minutes: 10)),
        '${task['title']} · deadline in 10 minutes',
        '${task['title']} is due at ${DateFormat.jm().format(deadline)}.',
      );
      add(
        'deadline',
        deadline,
        '${task['title']} · deadline reached',
        'The deadline has arrived. Open TaskHub and confirm whether this task is done.',
      );
    }
  }
  if (alarms.isEmpty) return;
  try {
    await _nativeAlarmChannel.invokeMethod<void>('scheduleTaskAlarms', {
      'alarms': alarms,
    });
  } on MissingPluginException {
    // Non-Android targets keep the in-app reminder path.
  } on PlatformException {
    // In-app reminders remain available if system notification access is denied.
  }
}

Future<void> _cancelNativeTaskAlarms(String taskId) async {
  if (kIsWeb) return;
  try {
    await _nativeAlarmChannel.invokeMethod<void>('cancelTaskAlarms', {
      'taskId': taskId,
    });
  } on MissingPluginException {
    // Non-Android targets have no OS alarms to cancel.
  } on PlatformException {
    // The in-app reminder loop ignores completed and archived tasks.
  }
}

Future<void> _cancelNativeTaskStartAlarm(String taskId, DateTime day) async {
  if (kIsWeb) return;
  final alarmId = '$taskId:${DateFormat('yyyy-MM-dd').format(day)}:start';
  try {
    await _nativeAlarmChannel.invokeMethod<void>('cancelTaskAlarm', {
      'alarmId': alarmId,
    });
  } on MissingPluginException {
    // Other platforms do not schedule Android alarms.
  } on PlatformException {
    // The task timer remains usable if the OS alarm cannot be cancelled.
  }
}

late final SupabaseClient db;
final AudioPlayer alertPlayer = AudioPlayer();

String _authDisplayName() {
  final metadata =
      db.auth.currentUser?.userMetadata ?? const <String, dynamic>{};
  for (final key in ['display_name', 'full_name', 'name']) {
    final value = '${metadata[key] ?? ''}'.trim();
    if (value.isNotEmpty) return value;
  }
  return '';
}

String _currentDisplayName() {
  final saved = _authDisplayName();
  if (saved.isNotEmpty) return saved;
  final emailName = db.auth.currentUser?.email?.split('@').first ?? '';
  final words = emailName.replaceAll(RegExp(r'[._-]+'), ' ').trim();
  if (words.isEmpty) return 'there';
  return words
      .split(RegExp(r'\s+'))
      .map(
        (part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}',
      )
      .join(' ');
}

String _humanError(Object error, String fallback) {
  final message = error.toString().toLowerCase();
  if (message.contains('only workspace founders can remove members')) {
    return 'Only workspace founders can remove other members.';
  }
  if (message.contains('founders cannot remove other founders')) {
    return 'A founder cannot remove another founder.';
  }
  if (message.contains('workspace founder who created it cannot be removed')) {
    return 'The founder who created this workspace cannot be removed.';
  }
  if (message.contains('only co-founders can leave')) {
    return 'Only co-founders can use this leave option.';
  }
  if (message.contains('workspace founder who created it cannot leave')) {
    return 'The founder who created this workspace cannot leave.';
  }
  if (message.contains('clear_task_occurrence') ||
      message.contains('task_occurrence_clears') ||
      message.contains('schema cache')) {
    return 'Task clearing is not available yet. Please ask your app administrator to apply the latest task database update, then try again.';
  }
  if (message.contains('occurrence date required')) {
    return 'Could not identify the date for this task. Edit the task schedule and try again.';
  }
  if (message.contains('only workspace tasks can be moved')) {
    return 'Only workspace tasks can be moved to personal tasks.';
  }
  if (message.contains('employees cannot assign tasks to workspace admins')) {
    return 'Workspace employees cannot assign tasks to a founder. Please choose another teammate.';
  }
  if (message.contains('workspace membership is required')) {
    return 'You must still belong to this workspace to move this task.';
  }
  if (message.contains('pause your current timer first')) {
    return 'Pause your current task before starting another one.';
  }
  if (message.contains('up to three task timers') ||
      message.contains('up to 3 task timers')) {
    return 'You can run up to three tasks at once. Pause a timer or switch to a different task.';
  }
  if (message.contains('task access required') ||
      message.contains('row-level security')) {
    return 'You do not have permission to change this task.';
  }
  if (message.contains('socket') || message.contains('network')) {
    return 'Could not connect. Check your internet connection and try again.';
  }
  if (message.contains('invalid login credentials')) {
    return 'The email or password is incorrect. Check them and try again.';
  }
  if (message.contains('user already registered') ||
      message.contains('already been registered')) {
    return 'An account already exists for this email. Try signing in instead.';
  }
  if (message.contains('password should be at least') ||
      message.contains('weak password')) {
    return 'Choose a stronger password and try again.';
  }
  if (message.contains('email not confirmed')) {
    return 'Please confirm your email before signing in.';
  }
  if (message.contains('permission denied') ||
      message.contains('not authorized')) {
    return 'You do not have permission to do that.';
  }
  return fallback;
}

String _taskStatusLabel(String status) => switch (status) {
  'active' => 'To do',
  'in_progress' => 'In progress',
  'completed' => 'Done',
  'archived' => 'Archived',
  'unfinished' => 'Not done',
  'cleared' => 'Cleared',
  _ => status,
};

List<String> _availableTaskStatuses(String status) => switch (status) {
  'active' => ['active', 'in_progress', 'completed', 'archived'],
  'in_progress' => ['in_progress', 'completed', 'archived'],
  'completed' => ['completed'],
  'archived' => ['archived', 'active'],
  _ => [status],
};

final ValueNotifier<int> notificationRevision = ValueNotifier<int>(0);

Future<List<Map<String, dynamic>>> _loadScopedNotifications({
  required String scope,
  String? workspaceId,
}) async {
  final userId = db.auth.currentUser?.id;
  if (userId == null) return [];

  late final List<Map<String, dynamic>> taskRows;
  if (scope == 'Workspace') {
    if (workspaceId == null) return [];
    taskRows = await db
        .from('tasks')
        .select('id')
        .eq('scope', 'workspace')
        .eq('workspace_id', workspaceId);
  } else {
    taskRows = await db
        .from('tasks')
        .select('id')
        .eq('scope', 'personal')
        .eq('owner_id', userId);
  }
  final taskIds = taskRows.map((row) => '${row['id']}').toList();

  final notifications = <Map<String, dynamic>>[];
  if (taskIds.isNotEmpty) {
    final taskNotifications = await db
        .from('task_notifications')
        .select()
        .eq('user_id', userId)
        .inFilter('task_id', taskIds);
    notifications.addAll(
      taskNotifications.map((row) => Map<String, dynamic>.from(row)),
    );
  }
  if (scope == 'Workspace' && workspaceId != null) {
    final workspaceNotifications = await db
        .from('task_notifications')
        .select()
        .eq('user_id', userId)
        .eq('workspace_id', workspaceId);
    final existingIds = notifications.map((row) => '${row['id']}').toSet();
    notifications.addAll(
      workspaceNotifications
          .where((row) => !existingIds.contains('${row['id']}'))
          .map((row) => Map<String, dynamic>.from(row)),
    );
  }
  notifications.sort((a, b) {
    final aDate = DateTime.tryParse('${a['created_at']}') ?? DateTime(1970);
    final bDate = DateTime.tryParse('${b['created_at']}') ?? DateTime(1970);
    return bDate.compareTo(aDate);
  });
  return notifications;
}

Future<void> addTaskNotification({
  required String taskId,
  required String kind,
  required String eventKey,
  required String title,
  required String body,
}) async {
  final userId = db.auth.currentUser?.id;
  if (userId == null) return;
  try {
    final inserted = await db
        .from('task_notifications')
        .upsert(
          {
            'user_id': userId,
            'task_id': taskId,
            'kind': kind,
            'title': title,
            'body': body,
            'event_key': eventKey,
          },
          onConflict: 'user_id,event_key',
          ignoreDuplicates: true,
        )
        .select('event_key')
        .maybeSingle();
    if (inserted == null) return;
    notificationRevision.value++;
    final shown = await _showNativeTaskNotification(
      title: title,
      body: body,
      eventKey: eventKey,
    );
    if (!shown) unawaited(playAlert());
  } catch (error) {
    debugPrint('Could not save task notification: $error');
  }
}

Future<void> playAlert() async {
  try {
    await alertPlayer.play(AssetSource('audio/meow.wav'));
  } catch (_) {}
}

bool get configured => true;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (configured) {
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabasePublishableKey,
    );
    db = Supabase.instance.client;
  }
  runApp(const TaskHub());
}

class TaskHub extends StatelessWidget {
  const TaskHub({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Task Hub',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: violet,
        surface: Colors.white,
        primary: violet,
        secondary: secondaryViolet,
        tertiary: pink,
      ),
      scaffoldBackgroundColor: canvas,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
          TargetPlatform.linux: ZoomPageTransitionsBuilder(),
        },
      ),
      textTheme: GoogleFonts.plusJakartaSansTextTheme().apply(
        bodyColor: ink,
        displayColor: ink,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        hintStyle: const TextStyle(color: muted, fontSize: 13),
        labelStyle: const TextStyle(color: muted, fontSize: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: secondaryViolet, width: 1.7),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: violet,
          foregroundColor: Colors.white,
          minimumSize: const Size(44, 46),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          minimumSize: const Size(42, 44),
          side: const BorderSide(color: line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: violet,
          hoverColor: lilac,
          highlightColor: violet.withValues(alpha: .10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white,
        selectedColor: lilac,
        side: const BorderSide(color: line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        labelStyle: const TextStyle(color: muted, fontSize: 12),
        secondaryLabelStyle: const TextStyle(
          color: violet,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: violet,
        linearTrackColor: lilac,
        circularTrackColor: lilac,
        linearMinHeight: 7,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 1,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: line),
        ),
        shadowColor: violet.withValues(alpha: .06),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: violet,
        foregroundColor: Colors.white,
        elevation: 5,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: const TextStyle(
          color: ink,
          fontSize: 19,
          fontWeight: FontWeight.w800,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: Colors.transparent,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected) ? violet : muted,
            fontSize: 10,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      useMaterial3: true,
    ),
    home: configured ? const AuthGate() : const SetupPage(),
  );
}

class VioletActionButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double minHeight;

  const VioletActionButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    this.minHeight = 46,
  });

  @override
  State<VioletActionButton> createState() => _VioletActionButtonState();
}

class _VioletActionButtonState extends State<VioletActionButton> {
  bool pressed = false;

  @override
  Widget build(BuildContext context) => AnimatedScale(
    scale: pressed ? .975 : 1,
    duration: const Duration(milliseconds: 120),
    curve: Curves.easeOut,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      constraints: BoxConstraints(minHeight: widget.minHeight),
      decoration: BoxDecoration(
        gradient: widget.onPressed == null
            ? const LinearGradient(colors: [line, line])
            : violetGradient,
        borderRadius: BorderRadius.circular(15),
        boxShadow: widget.onPressed == null
            ? const []
            : [
                BoxShadow(
                  color: violet.withValues(alpha: pressed ? .12 : .20),
                  blurRadius: pressed ? 8 : 16,
                  offset: Offset(0, pressed ? 2 : 6),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onPressed,
          onHighlightChanged: (value) => setState(() => pressed = value),
          borderRadius: BorderRadius.circular(15),
          splashColor: Colors.white.withValues(alpha: .18),
          child: Padding(
            padding: widget.padding,
            child: Center(
              child: IconTheme.merge(
                data: const IconThemeData(color: Colors.white),
                child: DefaultTextStyle.merge(
                  style: TextStyle(
                    color: widget.onPressed == null ? muted : Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class Brand extends StatelessWidget {
  const Brand({super.key});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const TaskHubMascot(mood: MascotMood.welcome, size: 38),
      const SizedBox(width: 10),
      Text(
        'TaskHub',
        style: GoogleFonts.plusJakartaSans(
          fontSize: 19,
          fontWeight: FontWeight.w800,
        ),
      ),
    ],
  );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  final MascotMood mood;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.mood = MascotMood.empty,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              TaskHubMascot(mood: mood, size: 92),
              Positioned(
                right: -5,
                bottom: -4,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: line),
                  ),
                  child: Icon(icon, color: mood.accent, size: 17),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: muted, fontSize: 12, height: 1.5),
            ),
          ),
          if (action != null) ...[const SizedBox(height: 15), action!],
        ],
      ),
    ),
  );
}

Future<DateTime?> showHubDatePicker(
  BuildContext context, {
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
}) {
  var selected = initialDate.isBefore(firstDate)
      ? firstDate
      : initialDate.isAfter(lastDate)
      ? lastDate
      : initialDate;
  return showDialog<DateTime>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, refresh) => AlertDialog(
        title: const Row(
          children: [
            TaskHubMascot(mood: MascotMood.calendar, size: 40),
            SizedBox(width: 10),
            Expanded(child: Text('Choose a date')),
          ],
        ),
        content: SizedBox(
          width: math.min(360, MediaQuery.sizeOf(dialogContext).width * .82),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const MascotBanner(
                mood: MascotMood.calendar,
                title: 'Pick your day',
                message: 'We’ll place the task on this date.',
                mascotSize: 46,
              ),
              const SizedBox(height: 8),
              CalendarDatePicker(
                initialDate: selected,
                firstDate: firstDate,
                lastDate: lastDate,
                onDateChanged: (value) => refresh(() => selected = value),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          VioletActionButton(
            onPressed: () => Navigator.pop(dialogContext, selected),
            child: const Text('Select date'),
          ),
        ],
      ),
    ),
  );
}

Future<TimeOfDay?> showHubTimePicker(
  BuildContext context, {
  required TimeOfDay initialTime,
  required String label,
}) => showTimePicker(
  context: context,
  initialTime: initialTime,
  initialEntryMode: TimePickerEntryMode.dial,
  helpText: label,
  cancelText: 'Cancel',
  confirmText: 'Set time',
  builder: (context, child) => Theme(
    data: Theme.of(context).copyWith(
      timePickerTheme: const TimePickerThemeData(
        backgroundColor: Colors.white,
        dialBackgroundColor: lilac,
        dialHandColor: violet,
        hourMinuteColor: lilac,
        hourMinuteTextColor: ink,
        entryModeIconColor: violet,
        dayPeriodColor: lilac,
        dayPeriodTextColor: violet,
      ),
    ),
    child: child!,
  ),
);

class PressableCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Color color;
  const PressableCard({
    super.key,
    required this.child,
    required this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.color = Colors.white,
  });

  @override
  State<PressableCard> createState() => _PressableCardState();
}

class _PressableCardState extends State<PressableCard> {
  bool hovered = false;
  bool pressed = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => hovered = true),
    onExit: (_) => setState(() => hovered = false),
    child: AnimatedScale(
      duration: const Duration(milliseconds: 130),
      scale: pressed ? .985 : 1,
      child: Container(
        margin: widget.margin,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: widget.color == Colors.white
                ? const [Colors.white, Color(0xFFFCFAFF)]
                : [widget.color, Colors.white],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: hovered ? softPurple : line),
          boxShadow: [
            BoxShadow(
              color: hovered
                  ? violet.withValues(alpha: .13)
                  : ink.withValues(alpha: .035),
              blurRadius: hovered ? 24 : 18,
              offset: Offset(0, hovered ? 9 : 5),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            splashColor: violet.withValues(alpha: .08),
            highlightColor: violet.withValues(alpha: .035),
            onHighlightChanged: (value) => setState(() => pressed = value),
            onTap: widget.onTap,
            child: Padding(padding: widget.padding, child: widget.child),
          ),
        ),
      ),
    ),
  );
}

class SetupPage extends StatelessWidget {
  const SetupPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Container(
              width: math.min(480, math.max(0, constraints.maxWidth - 32)),
              padding: EdgeInsets.all(constraints.maxWidth < 400 ? 20 : 36),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Brand(),
                  SizedBox(height: 25),
                  MascotBanner(
                    mood: MascotMood.planning,
                    title: 'Let’s set up your hub',
                    message: 'The mascot is ready to help you get started.',
                  ),
                  SizedBox(height: 18),
                  Text(
                    'Connect your workspace',
                    style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Add your Supabase project URL and anon key to launch Task Hub.',
                  ),
                  SizedBox(height: 20),
                  SelectableText(
                    'flutter run -d chrome --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      color: violet,
                      fontSize: 12,
                    ),
                  ),
                  SizedBox(height: 14),
                  Text(
                    'Run supabase/schema.sql first. See README.md.',
                    style: TextStyle(color: muted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Future<void> _minimumSplash;

  @override
  void initState() {
    super.initState();
    _minimumSplash = Future<void>.delayed(const Duration(seconds: 5));
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _minimumSplash,
    builder: (context, delay) {
      if (delay.connectionState != ConnectionState.done) {
        return const TaskHubSplash();
      }
      return StreamBuilder<AuthState>(
        stream: db.auth.onAuthStateChange,
        builder: (context, state) {
          if (state.connectionState == ConnectionState.waiting) {
            return const TaskHubSplash();
          }
          return db.auth.currentSession == null
              ? const LoginPage()
              : const Shell();
        },
      );
    },
  );
}

class TaskHubSplash extends StatelessWidget {
  const TaskHubSplash({super.key});
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFFF0E9FF),
                  Color(0xFFF9F6FF),
                  Color(0xFFECE3FF),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Positioned(
            top: -90,
            right: -75,
            child: _splashGlow(
              250,
              const Color(0xFFB89AFF).withValues(alpha: .15),
            ),
          ),
          Positioned(
            bottom: -95,
            left: -85,
            child: _splashGlow(
              260,
              const Color(0xFFD4C2FF).withValues(alpha: .2),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 28,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: .9, end: 1),
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeOutCubic,
                    builder: (context, scale, child) =>
                        Transform.scale(scale: scale, child: child),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: math.min(width * .82, 340),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                width: math.min(width * .58, 240),
                                height: 72,
                                margin: const EdgeInsets.only(top: 205),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(100),
                                  boxShadow: [
                                    BoxShadow(
                                      color: violet.withValues(alpha: .16),
                                      blurRadius: 55,
                                      spreadRadius: 14,
                                    ),
                                  ],
                                ),
                              ),
                              Image.asset(
                                'assets/brand/taskhub_puppy_cutout.png',
                                width: math.min(width * .82, 340),
                                fit: BoxFit.contain,
                                semanticLabel:
                                    'TaskHub puppy holding the TaskHub and Meoww banners',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 26),
                        Text(
                          'TaskHub welcomes you',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: ink,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -.35,
                              ),
                        ),
                        const SizedBox(height: 9),
                        const Text(
                          'A happy little start to a more focused day.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: muted, fontSize: 14),
                        ),
                        const SizedBox(height: 30),
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: 1),
                          duration: const Duration(seconds: 5),
                          builder: (context, progress, _) => SizedBox(
                            width: 76,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(99),
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 5,
                                color: violet,
                                backgroundColor: Colors.white.withValues(
                                  alpha: .8,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _splashGlow(double size, Color color) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final displayName = TextEditingController();
  final email = TextEditingController(), password = TextEditingController();
  bool signup = false, busy = false;
  String? error, info;
  Future<void> submit() async {
    if (signup && displayName.text.trim().isEmpty) {
      setState(
        () => error = 'Enter your name so your teammates can recognize you.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
      info = null;
    });
    try {
      if (signup) {
        final response = await db.auth.signUp(
          email: email.text.trim(),
          password: password.text,
          data: {'display_name': displayName.text.trim()},
        );
        if (response.session == null) {
          if (mounted) {
            setState(() {
              info =
                  'Supabase is still requiring email confirmation. Turn off “Confirm email” in Authentication settings and save changes. This account was created unconfirmed; confirm it in Authentication → Users, or recreate it after turning confirmation off.';
            });
          }
          return;
        }
        if (response.session != null) await db.auth.signOut();
        if (mounted)
          setState(() {
            signup = false;
            info = 'Account created. Please sign in.';
          });
      } else {
        await db.auth.signInWithPassword(
          email: email.text.trim(),
          password: password.text,
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        final unconfirmed = e.message.toLowerCase().contains(
          'email not confirmed',
        );
        setState(
          () => error = unconfirmed
              ? 'This account is not confirmed. Turn off “Confirm email” in Supabase, then confirm this account under Authentication → Users or create a fresh account.'
              : _humanError(
                  e.message,
                  'Could not sign in or create the account. Check your details and try again.',
                ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    displayName.dispose();
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> googleSignIn() async {
    setState(() {
      busy = true;
      error = null;
      info = null;
    });
    try {
      final launched = await db.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kIsWeb
            ? Uri.base.origin
            : 'com.taskhub.app://login-callback/',
        authScreenLaunchMode: kIsWeb
            ? LaunchMode.platformDefault
            : LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        setState(
          () => error =
              'Could not open Google sign-in. Check your redirect URL settings and try again.',
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(
          () => error = _humanError(
            e.message,
            'Google sign-in could not be completed. Please try again.',
          ),
        );
      }
    } catch (_) {
      if (mounted)
        setState(
          () => error =
              'Could not start Google sign-in. Check your connection and try again.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: LayoutBuilder(
      builder: (context, box) {
        final compact = box.maxWidth < 760;
        final left = Container(
          color: lilac,
          padding: const EdgeInsets.all(42),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Brand(),
              const Spacer(),
              const TaskHubMascot(mood: MascotMood.welcome, size: 92),
              const SizedBox(height: 18),
              Text(
                'A little more focus.\nA lot more done.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 42,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Your day, thoughtfully organized.',
                style: TextStyle(color: muted, fontSize: 17),
              ),
              const Spacer(),
              const Text(
                'YOUR SPACE TO MAKE PROGRESS',
                style: TextStyle(color: muted, letterSpacing: 2, fontSize: 11),
              ),
            ],
          ),
        );
        final form = Center(
          child: Container(
            width: math.min(390, box.maxWidth - 36),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: line),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0A29243A),
                  blurRadius: 28,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    signup ? 'Create your account' : 'Welcome back',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 27,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Sign in to pick up where you left off.',
                    style: TextStyle(color: muted),
                  ),
                  const SizedBox(height: 26),
                  if (signup) ...[
                    input(
                      'Your name',
                      displayName,
                      Icons.person_outline_rounded,
                    ),
                    const SizedBox(height: 15),
                  ],
                  input('Email address', email, Icons.mail_outline),
                  const SizedBox(height: 15),
                  input(
                    'Password',
                    password,
                    Icons.lock_outline,
                    obscure: true,
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  if (info != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        info!,
                        style: const TextStyle(color: success, fontSize: 12),
                      ),
                    ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: VioletActionButton(
                      onPressed: busy ? null : submit,
                      child: Text(
                        busy
                            ? 'Please wait…'
                            : signup
                            ? 'Create account'
                            : 'Sign in',
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : googleSignIn,
                      icon: const Icon(Icons.g_mobiledata),
                      label: const Text('Continue with Google'),
                    ),
                  ),
                  Center(
                    child: TextButton(
                      onPressed: () => setState(() {
                        signup = !signup;
                        error = null;
                        info = null;
                      }),
                      child: Text(
                        signup
                            ? 'Already registered? Sign in'
                            : 'Create an account',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        return compact
            ? SingleChildScrollView(
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Brand(),
                        const SizedBox(height: 30),
                        Row(
                          children: [
                            const TaskHubMascot(
                              mood: MascotMood.welcome,
                              size: 72,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'A little more focus.\nA lot more done.',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 25,
                                  fontWeight: FontWeight.w800,
                                  height: 1.15,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Your day, thoughtfully organized.',
                          style: TextStyle(color: muted, fontSize: 13),
                        ),
                        const SizedBox(height: 22),
                        form,
                      ],
                    ),
                  ),
                ),
              )
            : Row(
                children: [
                  Expanded(flex: 6, child: left),
                  Expanded(flex: 5, child: form),
                ],
              );
      },
    ),
  );
}

Widget input(
  String label,
  TextEditingController controller,
  IconData icon, {
  bool obscure = false,
}) => TextField(
  controller: controller,
  obscureText: obscure,
  decoration: InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon),
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: const BorderSide(color: line),
    ),
  ),
);

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int page = 0;
  String scope = 'Personal';
  WorkspaceInfo? workspace;
  Timer? reminders;
  Timer? notificationRefresh;
  bool checkingReminders = false;
  bool exitPromptOpen = false;
  final Set<String> notifiedDeadlines = {};
  final Set<String> promptedDeadlineCompletions = {};
  final Set<String> promptedTasks = {};
  final Map<String, String> nativeAlarmFingerprints = {};
  @override
  void initState() {
    super.initState();
    reminders = Timer.periodic(
      const Duration(seconds: 10),
      (_) => checkReminders(),
    );
    notificationRefresh = Timer.periodic(
      const Duration(seconds: 20),
      (_) => notificationRevision.value++,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _ensureDisplayName();
      if (mounted) unawaited(checkReminders());
    });
  }

  Future<void> _ensureDisplayName() async {
    if (_authDisplayName().isNotEmpty || !mounted) return;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, refresh) => AlertDialog(
          title: const Row(
            children: [
              TaskHubMascot(mood: MascotMood.welcome, size: 42),
              SizedBox(width: 10),
              Expanded(child: Text('What should we call you?')),
            ],
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Your name'),
            onChanged: (_) => refresh(() {}),
          ),
          actions: [
            VioletActionButton(
              onPressed: controller.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('Save name'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty || !mounted) return;
    try {
      await db.auth.updateUser(
        UserAttributes(data: {'display_name': name.trim()}),
      );
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save your name. Try again.')),
        );
    }
  }

  @override
  void dispose() {
    reminders?.cancel();
    notificationRefresh?.cancel();
    super.dispose();
  }

  Future<void> checkReminders() async {
    if (checkingReminders) return;
    checkingReminders = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final userKey = db.auth.currentUser!.id;
      notifiedDeadlines.addAll(
        prefs.getStringList('reminders.deadline.$userKey') ?? const [],
      );
      promptedDeadlineCompletions.addAll(
        prefs.getStringList('reminders.deadline-completion.$userKey') ??
            const [],
      );
      promptedTasks.addAll(
        prefs.getStringList('reminders.prompt.v2.$userKey') ?? const [],
      );
      final uid = db.auth.currentUser!.id;
      final rows = await db
          .from('tasks')
          .select(
            'id,title,starts_at,due_at,recurrence,timer_started_at,status',
          )
          .or('owner_id.eq.$uid,assigned_to.eq.$uid')
          .neq('status', 'completed')
          .neq('status', 'archived');
      final now = DateTime.now();
      final currentTaskIds = <String>{};
      for (final row in rows) {
        final id = '${row['id']}';
        currentTaskIds.add(id);
        final alarmFingerprint =
            '${row['starts_at']}|${row['due_at']}|${row['recurrence']}';
        if (nativeAlarmFingerprints[id] != alarmFingerprint) {
          if (nativeAlarmFingerprints.containsKey(id)) {
            await _cancelNativeTaskAlarms(id);
          }
          nativeAlarmFingerprints[id] = alarmFingerprint;
          await _scheduleNativeTaskAlarms(row);
        }
        final firstDue = row['due_at'] == null
            ? now
            : DateTime.parse('${row['due_at']}').toLocal();
        final occurrenceFrom = row['recurrence'] == null
            ? firstDue.subtract(const Duration(minutes: 10))
            : DateTime(
                now.year,
                now.month,
                now.day,
              ).subtract(const Duration(days: 1));
        final occurrences = _scheduledOccurrences(
          row,
          occurrenceFrom,
          now.add(const Duration(seconds: 20)),
        );
        for (final (start, deadline) in occurrences) {
          final dateKey = DateFormat('yyyy-MM-dd').format(start);
          final dueSoonKey = '$id:$dateKey:due-soon';
          if (deadline != null &&
              !now.isBefore(deadline.subtract(const Duration(minutes: 10))) &&
              now.isBefore(deadline) &&
              notifiedDeadlines.add(dueSoonKey)) {
            await prefs.setStringList(
              'reminders.deadline.$userKey',
              notifiedDeadlines.toList(),
            );
            await addTaskNotification(
              taskId: id,
              kind: 'deadline_soon',
              eventKey: 'deadline-soon:$id:$dateKey',
              title: '${row['title']} · deadline in 10 minutes',
              body:
                  '${row['title']} is due at ${DateFormat.jm().format(deadline)}.',
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${row['title']} is due in 10 minutes.'),
                ),
              );
            }
          }
          final dueKey = '$id:$dateKey:due';
          if (deadline != null &&
              !now.isBefore(deadline) &&
              notifiedDeadlines.add(dueKey)) {
            await prefs.setStringList(
              'reminders.deadline.$userKey',
              notifiedDeadlines.toList(),
            );
            await addTaskNotification(
              taskId: id,
              kind: 'deadline',
              eventKey: 'deadline:$id:$dateKey',
              title: '${row['title']} · deadline reached',
              body:
                  'The deadline has arrived. Open TaskHub and confirm whether this task is done.',
            );
          }
          final completionPromptKey = '$id:$dateKey:completion-prompt';
          final aMoreRecentDeadlineIsDue = occurrences.any(
            (occurrence) =>
                occurrence.$2 != null &&
                deadline != null &&
                occurrence.$2!.isAfter(deadline) &&
                !now.isBefore(occurrence.$2!),
          );
          if (deadline != null &&
              !now.isBefore(deadline) &&
              !aMoreRecentDeadlineIsDue &&
              row['status'] != 'completed' &&
              mounted &&
              WidgetsBinding.instance.lifecycleState ==
                  AppLifecycleState.resumed &&
              promptedDeadlineCompletions.add(completionPromptKey)) {
            await prefs.setStringList(
              'reminders.deadline-completion.$userKey',
              promptedDeadlineCompletions.toList(),
            );
            final completed = await showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (dialogContext) => AlertDialog(
                title: const Text('Task deadline reached'),
                content: Text('Did you complete "${row['title']}"?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('No, keep it open'),
                  ),
                  VioletActionButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Yes, mark done'),
                  ),
                ],
              ),
            );
            if (completed == true && mounted) {
              try {
                if (row['timer_started_at'] != null) {
                  await db.rpc('pause_task_timer', params: {'target_task': id});
                }
                await db.rpc(
                  'change_task_field',
                  params: {
                    'target_task': id,
                    'field_name': 'status',
                    'new_value': 'completed',
                    'reason_text': 'Completed after deadline confirmation',
                  },
                );
                await _cancelNativeTaskAlarms(id);
                await _syncRunningTimerNotification(await _loadRunningTasks());
                await addTaskNotification(
                  taskId: id,
                  kind: 'completed',
                  eventKey: 'completed:$id:$dateKey',
                  title: '${row['title']} completed',
                  body: 'Your task is marked done.',
                );
                if (mounted) setState(() {});
              } catch (error) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        _humanError(
                          error,
                          'Could not mark this task as done. Please try again.',
                        ),
                      ),
                    ),
                  );
                }
                promptedDeadlineCompletions.remove(completionPromptKey);
                await prefs.setStringList(
                  'reminders.deadline-completion.$userKey',
                  promptedDeadlineCompletions.toList(),
                );
              }
            }
          }
          final startKey = '$id:$dateKey';
          if (row['status'] == 'active' &&
              row['timer_started_at'] == null &&
              !now.isBefore(start) &&
              now.difference(start) < const Duration(days: 1) &&
              promptedTasks.add(startKey) &&
              mounted) {
            await prefs.setStringList(
              'reminders.prompt.v2.$userKey',
              promptedTasks.toList(),
            );
            await addTaskNotification(
              taskId: id,
              kind: 'started',
              eventKey: 'scheduled-start:$id:$dateKey',
              title: '${row['title']} · time to start',
              body: 'Your scheduled task is ready. Tap to start it.',
            );
            final outcome = await _startTaskWithChoice(context, HubTask(row));
            if (mounted && outcome != _TaskStartOutcome.cancelled) {
              setState(() => page = 3);
            }
          }
        }
      }
      for (final id in nativeAlarmFingerprints.keys.toList()) {
        if (!currentTaskIds.contains(id)) {
          await _cancelNativeTaskAlarms(id);
          nativeAlarmFingerprints.remove(id);
        }
      }
    } catch (_) {
      /* Reminders resume on the next poll when connectivity returns. */
    } finally {
      checkingReminders = false;
    }
  }

  Future<void> selectScope(String value) async {
    if (value == 'Workspace' && workspace == null) {
      final selected = await showDialog<WorkspaceInfo>(
        context: context,
        builder: (_) => const WorkspaceDialog(),
      );
      if (selected == null || !mounted) {
        setState(() => scope = 'Personal');
        return;
      }
      setState(() {
        workspace = selected;
        scope = 'Workspace';
      });
      if (selected.createdNow) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Workspace "${selected.name}" created successfully.'),
          ),
        );
      }
    } else {
      setState(() => scope = value);
    }
  }

  Future<void> confirmExit() async {
    if (exitPromptOpen || !mounted) return;
    exitPromptOpen = true;
    final exit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            TaskHubMascot(mood: MascotMood.welcome, size: 40),
            SizedBox(width: 10),
            Text('Leaving TaskHub?'),
          ],
        ),
        content: const Text('Are you sure you want to exit the app?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No, stay'),
          ),
          VioletActionButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, exit'),
          ),
        ],
      ),
    );
    exitPromptOpen = false;
    if (exit == true) await SystemNavigator.pop();
  }

  final labels = [
    'Home',
    'My tasks',
    'Calendar',
    'Progression status',
    'Insights',
  ];
  final navigationLabels = [
    'Home',
    'My tasks',
    'Calendar',
    'Progression\nStatus',
    'Insights',
  ];
  final icons = [
    Icons.grid_view,
    Icons.checklist,
    Icons.calendar_month,
    Icons.timer_outlined,
    Icons.insights,
  ];
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 920;
    final compact = width < 430;
    final ultraCompact = width < 360;
    final pageMood = switch (page) {
      0 => MascotMood.welcome,
      1 => MascotMood.planning,
      2 => MascotMood.calendar,
      3 => MascotMood.focus,
      _ => MascotMood.insight,
    };
    final pageColors = switch (page) {
      0 => const [Color(0xFFF0E7FF), Color(0xFFFFF1F7), Color(0xFFF8F5FF)],
      1 => const [Color(0xFFEDE4FF), Color(0xFFF9F5FF), Color(0xFFFFF2F7)],
      2 => const [Color(0xFFECE6FF), Color(0xFFEFF7FF), Color(0xFFFFF6FC)],
      3 => const [Color(0xFFEAE2FF), Color(0xFFFFF0F5), Color(0xFFF7F2FF)],
      _ => const [Color(0xFFEFE8FF), Color(0xFFE9FBF5), Color(0xFFFFF5FA)],
    };
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(confirmExit());
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Row(
            children: [
              if (wide)
                Container(
                  width: 248,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(right: BorderSide(color: line)),
                  ),
                  child: _nav(),
                ),
              Expanded(
                child: Column(
                  children: [
                    Container(
                      height: 72,
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 8 : 22,
                      ),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        border: Border(bottom: BorderSide(color: line)),
                      ),
                      child: Row(
                        children: [
                          if (compact)
                            const TaskHubMascot(
                              mood: MascotMood.welcome,
                              size: 36,
                            )
                          else if (!wide)
                            const Brand()
                          else
                            Text(
                              labels[page],
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 17,
                              ),
                            ),
                          const Spacer(),
                          if (wide)
                            for (final s in ['Personal', 'Workspace'])
                              Padding(
                                padding: const EdgeInsets.only(left: 5),
                                child: ChoiceChip(
                                  label: Text(s),
                                  selected: scope == s,
                                  onSelected: (_) => selectScope(s),
                                ),
                              )
                          else
                            PopupMenuButton<String>(
                              tooltip: 'Choose workspace',
                              onSelected: selectScope,
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'Personal',
                                  child: Text('Personal'),
                                ),
                                PopupMenuItem(
                                  value: 'Workspace',
                                  child: Text('Workspace'),
                                ),
                              ],
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: ultraCompact
                                      ? 5
                                      : compact
                                      ? 7
                                      : 10,
                                  vertical: 9,
                                ),
                                decoration: BoxDecoration(
                                  color: lilac,
                                  borderRadius: BorderRadius.circular(13),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      scope == 'Personal'
                                          ? Icons.person_outline_rounded
                                          : Icons.groups_2_outlined,
                                      color: violet,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      scope,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const Icon(Icons.expand_more, size: 17),
                                  ],
                                ),
                              ),
                            ),
                          if (scope == 'Workspace')
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints.tightFor(
                                width: 34,
                                height: 34,
                              ),
                              tooltip: 'Manage workspaces',
                              onPressed: () async {
                                final selected =
                                    await showDialog<WorkspaceInfo>(
                                      context: context,
                                      builder: (_) => WorkspaceDialog(
                                        onWorkspaceLeft: (leftId) {
                                          if (workspace?.id == leftId &&
                                              mounted) {
                                            setState(() {
                                              workspace = null;
                                              scope = 'Personal';
                                            });
                                          }
                                        },
                                      ),
                                    );
                                if (selected != null && mounted) {
                                  setState(() => workspace = selected);
                                  if (selected.createdNow) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Workspace "${selected.name}" created successfully.',
                                        ),
                                      ),
                                    );
                                  }
                                }
                              },
                              icon: const Icon(
                                Icons.settings_outlined,
                                color: violet,
                              ),
                            ),
                          ValueListenableBuilder<int>(
                            valueListenable: notificationRevision,
                            builder: (context, revision, _) =>
                                FutureBuilder<List<Map<String, dynamic>>>(
                                  future: _loadScopedNotifications(
                                    scope: scope,
                                    workspaceId: workspace?.id,
                                  ),
                                  builder: (context, notifications) {
                                    final count =
                                        notifications.data
                                            ?.where(
                                              (row) => row['read_at'] == null,
                                            )
                                            .length ??
                                        0;
                                    return IconButton(
                                      visualDensity: VisualDensity.compact,
                                      constraints:
                                          const BoxConstraints.tightFor(
                                            width: 34,
                                            height: 34,
                                          ),
                                      tooltip: count == 0
                                          ? 'Notifications'
                                          : '$count unread notifications',
                                      onPressed: openNotifications,
                                      icon: Badge(
                                        isLabelVisible: count > 0,
                                        label: Text('$count'),
                                        child: const Icon(
                                          Icons.notifications_none_rounded,
                                          color: violet,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                          ),
                          PopupMenuButton<String>(
                            tooltip: 'Account',
                            padding: EdgeInsets.zero,
                            onSelected: (value) {
                              if (value == 'signout') db.auth.signOut();
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                enabled: false,
                                value: 'email',
                                child: Text(
                                  db.auth.currentUser?.email ?? 'Account',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const PopupMenuDivider(),
                              const PopupMenuItem(
                                value: 'signout',
                                child: Row(
                                  children: [
                                    Icon(Icons.logout_rounded, size: 18),
                                    SizedBox(width: 8),
                                    Text('Sign out'),
                                  ],
                                ),
                              ),
                            ],
                            child: CircleAvatar(
                              radius: ultraCompact ? 15 : 17,
                              backgroundColor: lilac,
                              child: Text(
                                _currentDisplayName()[0].toUpperCase(),
                                style: const TextStyle(
                                  color: violet,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOutCubic,
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(.015, 0),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        ),
                        child: KeyedSubtree(
                          key: ValueKey('$scope-${workspace?.id}-$page'),
                          child: Stack(
                            fit: StackFit.expand,
                            clipBehavior: Clip.none,
                            children: [
                              Positioned.fill(
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 650),
                                  curve: Curves.easeInOutCubic,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: pageColors,
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                right: -42,
                                bottom: 16,
                                child: IgnorePointer(
                                  child: Opacity(
                                    opacity: .08,
                                    child: TaskHubMascot(
                                      mood: pageMood,
                                      size: 230,
                                    ),
                                  ),
                                ),
                              ),
                              Positioned.fill(child: _content()),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                labelBehavior: compact
                    ? NavigationDestinationLabelBehavior.onlyShowSelected
                    : NavigationDestinationLabelBehavior.alwaysShow,
                selectedIndex: page,
                onDestinationSelected: (i) => setState(() => page = i),
                destinations: List.generate(
                  labels.length,
                  (i) => NavigationDestination(
                    icon: Icon(icons[i], color: muted),
                    selectedIcon: Container(
                      width: 38,
                      height: 30,
                      decoration: BoxDecoration(
                        gradient: violetGradient,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: violet.withValues(alpha: .18),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Icon(icons[i], color: Colors.white, size: 19),
                    ),
                    label: navigationLabels[i],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _nav() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 24, 16, 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Brand(),
        const SizedBox(height: 12),
        Text(
          scope == 'Workspace'
              ? workspace?.name ?? 'Workspace'
              : 'Personal space',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: muted, fontSize: 12),
        ),
        const SizedBox(height: 34),
        const Text(
          'YOUR SPACE',
          style: TextStyle(
            color: muted,
            fontSize: 10,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < labels.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              decoration: BoxDecoration(
                color: page == i ? null : Colors.transparent,
                gradient: page == i ? violetGradient : null,
                borderRadius: BorderRadius.circular(13),
                boxShadow: page == i
                    ? [
                        BoxShadow(
                          color: violet.withValues(alpha: .16),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : const [],
              ),
              child: ListTile(
                dense: true,
                selected: page == i,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
                leading: Icon(
                  icons[i],
                  color: page == i ? Colors.white : muted,
                  size: 20,
                ),
                title: Text(
                  labels[i],
                  style: TextStyle(
                    color: page == i ? Colors.white : ink,
                    fontSize: 13,
                    fontWeight: page == i ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                onTap: () => setState(() => page = i),
              ),
            ),
          ),
        const Spacer(),
        const Text(
          'One thing at a time.\nYou’re making progress.',
          style: TextStyle(color: muted),
        ),
      ],
    ),
  );
  Widget _content() => switch (page) {
    0 => Dashboard(
      scope: scope,
      workspaceId: workspace?.id,
      isWorkspaceAdmin: workspace?.admin ?? false,
      openTasks: () => setState(() => page = 1),
    ),
    1 => TasksPage(
      scope: scope,
      workspaceId: workspace?.id,
      isWorkspaceAdmin: workspace?.admin ?? false,
      onOpenProgression: () => setState(() => page = 3),
    ),
    2 => CalendarPage(
      scope: scope,
      workspaceId: workspace?.id,
      isWorkspaceAdmin: workspace?.admin ?? false,
    ),
    3 => TimePage(scope: scope, workspaceId: workspace?.id),
    _ => InsightsPage(scope: scope, workspaceId: workspace?.id),
  };
  Future<void> openNotifications() async {
    await showDialog<void>(
      context: context,
      builder: (_) =>
          NotificationCenter(scope: scope, workspaceId: workspace?.id),
    );
  }
}

class NotificationCenter extends StatefulWidget {
  const NotificationCenter({super.key, required this.scope, this.workspaceId});
  final String scope;
  final String? workspaceId;
  @override
  State<NotificationCenter> createState() => _NotificationCenterState();
}

class _NotificationCenterState extends State<NotificationCenter> {
  late Future<List<Map<String, dynamic>>> future;
  late final VoidCallback _notificationListener;
  @override
  void initState() {
    super.initState();
    future = load();
    _notificationListener = () {
      if (mounted) setState(() => future = load());
    };
    notificationRevision.addListener(_notificationListener);
  }

  @override
  void dispose() {
    notificationRevision.removeListener(_notificationListener);
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> load() async {
    final rows = await _loadScopedNotifications(
      scope: widget.scope,
      workspaceId: widget.workspaceId,
    );
    final requestIds = rows
        .where((row) => row['assignment_request_id'] != null)
        .map((row) => '${row['assignment_request_id']}')
        .toSet()
        .toList();
    final workspaceRequestIds = rows
        .where((row) => row['workspace_request_id'] != null)
        .map((row) => '${row['workspace_request_id']}')
        .toSet()
        .toList();
    final statusByRequestId = <String, dynamic>{};
    final workspaceStatusByRequestId = <String, dynamic>{};
    if (requestIds.isNotEmpty) {
      final requests = await db
          .from('task_assignment_requests')
          .select('id,status')
          .inFilter('id', requestIds);
      statusByRequestId.addAll({
        for (final request in requests) '${request['id']}': request['status'],
      });
    }
    if (workspaceRequestIds.isNotEmpty) {
      final requests = await db
          .from('workspace_requests')
          .select('id,status')
          .inFilter('id', workspaceRequestIds);
      workspaceStatusByRequestId.addAll({
        for (final request in requests) '${request['id']}': request['status'],
      });
    }
    return rows
        .map(
          (row) => {
            ...row,
            'assignment_status':
                statusByRequestId['${row['assignment_request_id']}'] ??
                'unavailable',
            'workspace_request_status':
                workspaceStatusByRequestId['${row['workspace_request_id']}'] ??
                'unavailable',
          },
        )
        .toList();
  }

  Future<void> respondToAssignment(
    Map<String, dynamic> notification,
    bool accept,
  ) async {
    final requestId = notification['assignment_request_id'];
    if (requestId == null || notification['assignment_status'] != 'pending') {
      return;
    }
    try {
      await db.rpc(
        'decide_task_assignment',
        params: {'request_id': requestId, 'accept': accept},
      );
      await db
          .from('task_notifications')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', notification['id']);
      notificationRevision.value++;
      if (mounted) setState(() => future = load());
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _humanError(
                error,
                accept
                    ? 'Could not accept this assignment. Please try again.'
                    : 'Could not decline this assignment. Please try again.',
              ),
            ),
          ),
        );
      }
    }
  }

  Future<void> respondToWorkspaceJoin(
    Map<String, dynamic> notification,
    bool accept,
  ) async {
    final requestId = notification['workspace_request_id'];
    if (requestId == null ||
        notification['workspace_request_status'] != 'pending') {
      return;
    }
    try {
      await db.rpc(
        'decide_workspace_request',
        params: {'request_id': requestId, 'accept': accept},
      );
      notificationRevision.value++;
      if (mounted) setState(() => future = load());
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _humanError(
                error,
                accept
                    ? 'Could not accept this workspace request. Please try again.'
                    : 'Could not reject this workspace request. Please try again.',
              ),
            ),
          ),
        );
      }
    }
  }

  Future<void> markRead(String id) async {
    await db
        .from('task_notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', id);
    notificationRevision.value++;
    if (mounted) setState(() => future = load());
  }

  Future<void> markAllRead() async {
    final rows = await load();
    final unreadIds = rows
        .where((row) => row['read_at'] == null)
        .map((row) => '${row['id']}')
        .toList();
    if (unreadIds.isNotEmpty) {
      await db
          .from('task_notifications')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('user_id', db.auth.currentUser!.id)
          .inFilter('id', unreadIds);
    }
    notificationRevision.value++;
    if (mounted) setState(() => future = load());
  }

  Future<bool> deleteOne(String id, {bool refresh = true}) async {
    try {
      await db
          .from('task_notifications')
          .delete()
          .eq('id', id)
          .eq('user_id', db.auth.currentUser!.id);
      if (refresh) {
        notificationRevision.value++;
        if (mounted) setState(() => future = load());
      }
      return true;
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not delete that notification. Try again.'),
          ),
        );
      return false;
    }
  }

  Future<void> clearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all notifications?'),
        content: const Text(
          'This clears notifications in the current space. Pending requests stay until they are accepted or rejected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          VioletActionButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final userId = db.auth.currentUser!.id;
      final rows = await load();
      final deletableIds = rows
          .where((row) {
            if (row['kind'] == 'assignment_request' &&
                row['assignment_status'] == 'pending') {
              return false;
            }
            if (row['kind'] == 'workspace_join_request' &&
                row['workspace_request_status'] == 'pending') {
              return false;
            }
            return true;
          })
          .map((row) => '${row['id']}')
          .toList();
      if (deletableIds.isNotEmpty) {
        await db
            .from('task_notifications')
            .delete()
            .eq('user_id', userId)
            .inFilter('id', deletableIds);
      }
      notificationRevision.value++;
      if (mounted) setState(() => future = load());
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not clear notifications. Try again.'),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Row(
      children: [
        const TaskHubMascot(mood: MascotMood.reminder, size: 42),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            widget.scope == 'Workspace'
                ? 'Workspace notifications'
                : 'Personal notifications',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        PopupMenuButton<String>(
          tooltip: 'Notification options',
          onSelected: (value) => value == 'read' ? markAllRead() : clearAll(),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'read', child: Text('Mark all read')),
            PopupMenuItem(value: 'clear', child: Text('Clear all')),
          ],
          icon: const Icon(Icons.more_vert_rounded),
        ),
      ],
    ),
    content: SizedBox(
      width: math.min(500, MediaQuery.sizeOf(context).width * .86),
      height: math.min(520, MediaQuery.sizeOf(context).height * .72),
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: future,
        builder: (context, s) {
          if (s.hasError)
            return Text(
              _humanError(
                s.error!,
                'Could not load notifications. Check your connection and try again.',
              ),
            );
          if (!s.hasData)
            return const Center(child: CircularProgressIndicator());
          if (s.data!.isEmpty)
            return const EmptyState(
              icon: Icons.notifications_none_rounded,
              title: 'You’re all caught up',
              message: 'New task reminders and updates will appear here.',
              mood: MascotMood.reminder,
            );
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: s.data!.length,
            separatorBuilder: (_, _) => const SizedBox(height: 9),
            itemBuilder: (context, index) {
              final row = s.data![index];
              final unread = row['read_at'] == null;
              final started = row['kind'] == 'started';
              final assignmentRequest = row['kind'] == 'assignment_request';
              final workspaceJoinRequest =
                  row['kind'] == 'workspace_join_request';
              final assignmentStatus = '${row['assignment_status'] ?? ''}';
              final workspaceJoinStatus =
                  '${row['workspace_request_status'] ?? ''}';
              final actionableRequest =
                  assignmentRequest || workspaceJoinRequest;
              final requestStatus = workspaceJoinRequest
                  ? workspaceJoinStatus
                  : assignmentStatus;
              final assignmentResult =
                  row['kind'] == 'assignment_accepted' ||
                  row['kind'] == 'assignment_assigned' ||
                  row['kind'] == 'workspace_join_accepted';
              final requestResult =
                  row['kind'] == 'workspace_join_accepted' ||
                  row['kind'] == 'workspace_join_rejected';
              final pendingRequest =
                  actionableRequest && requestStatus == 'pending';
              return Dismissible(
                key: ValueKey('notification-${row['id']}'),
                direction: pendingRequest
                    ? DismissDirection.none
                    : DismissDirection.horizontal,
                confirmDismiss: (_) =>
                    deleteOne('${row['id']}', refresh: false),
                onDismissed: (_) => notificationRevision.value++,
                background: _notificationSwipeBackground(
                  alignment: Alignment.centerLeft,
                ),
                secondaryBackground: _notificationSwipeBackground(
                  alignment: Alignment.centerRight,
                ),
                child: PressableCard(
                  padding: const EdgeInsets.all(14),
                  color: unread ? canvas : Colors.white,
                  onTap: () => markRead('${row['id']}'),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: started || assignmentResult
                              ? mintTint
                              : requestStatus == 'rejected' ||
                                    row['kind'] == 'workspace_join_rejected'
                              ? pinkTint
                              : sunshineTint,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: TaskHubMascot(
                          size: 38,
                          idleAnimation: false,
                          mood: started || assignmentResult
                              ? MascotMood.celebration
                              : MascotMood.reminder,
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${row['title']}',
                              style: TextStyle(
                                fontWeight: unread
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${row['body']}',
                              style: const TextStyle(
                                color: muted,
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              DateFormat.yMMMd().add_jm().format(
                                DateTime.parse(
                                  '${row['created_at']}',
                                ).toLocal(),
                              ),
                              style: const TextStyle(
                                color: muted,
                                fontSize: 10,
                              ),
                            ),
                            if (actionableRequest && requestStatus == 'pending')
                              Padding(
                                padding: const EdgeInsets.only(top: 9),
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: () => assignmentRequest
                                          ? respondToAssignment(row, false)
                                          : respondToWorkspaceJoin(row, false),
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        size: 16,
                                      ),
                                      label: const Text('Reject'),
                                    ),
                                    FilledButton.icon(
                                      onPressed: () => assignmentRequest
                                          ? respondToAssignment(row, true)
                                          : respondToWorkspaceJoin(row, true),
                                      icon: const Icon(
                                        Icons.check_rounded,
                                        size: 16,
                                      ),
                                      label: const Text('Accept'),
                                    ),
                                  ],
                                ),
                              )
                            else if (actionableRequest)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  requestStatus == 'accepted'
                                      ? 'Accepted'
                                      : requestStatus == 'rejected'
                                      ? 'Rejected'
                                      : 'This request is no longer available.',
                                  style: TextStyle(
                                    color: requestStatus == 'accepted'
                                        ? success
                                        : requestStatus == 'rejected'
                                        ? danger
                                        : muted,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              )
                            else if (requestResult)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  row['kind'] == 'workspace_join_accepted'
                                      ? 'Accepted'
                                      : 'Rejected',
                                  style: TextStyle(
                                    color:
                                        row['kind'] == 'workspace_join_accepted'
                                        ? success
                                        : danger,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (unread)
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(left: 8),
                          decoration: const BoxDecoration(
                            color: violet,
                            shape: BoxShape.circle,
                          ),
                        ),
                      IconButton(
                        tooltip: 'Delete notification',
                        onPressed: pendingRequest
                            ? null
                            : () => deleteOne('${row['id']}'),
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 20,
                          color: muted,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}

class WorkspaceInfo {
  final String id, name;
  final bool admin, createdNow;
  const WorkspaceInfo(
    this.id,
    this.name, {
    this.admin = false,
    this.createdNow = false,
  });
}

class WorkspaceDialog extends StatefulWidget {
  const WorkspaceDialog({super.key, this.onWorkspaceLeft});
  final ValueChanged<String>? onWorkspaceLeft;
  @override
  State<WorkspaceDialog> createState() => _WorkspaceDialogState();
}

class _WorkspaceDialogState extends State<WorkspaceDialog> {
  final name = TextEditingController(), search = TextEditingController();
  List<Map<String, dynamic>> results = [];
  bool busy = false;

  @override
  void dispose() {
    name.dispose();
    search.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> myWorkspaces() async {
    final rows = await db
        .from('workspace_members')
        .select(
          'workspace_id,role,workspace_role,workspaces(id,name,created_by)',
        )
        .eq('user_id', db.auth.currentUser!.id);
    return rows.map((r) {
      final w = Map<String, dynamic>.from(r['workspaces'] as Map);
      w['role'] = r['role'];
      w['workspace_role'] = r['workspace_role'];
      w['role_label'] = _workspaceRoleLabel(w);
      return w;
    }).toList();
  }

  Future<void> leaveAsCofounder(Map<String, dynamic> workspace) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Leave ${workspace['name']}?'),
        content: const Text(
          'You will lose access to this workspace. Tasks assigned to you will return to the workspace task list, and your running timers will stop.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: danger),
            child: const Text('Leave workspace'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final workspaceId = '${workspace['id']}';
      await db.rpc(
        'leave_workspace_as_cofounder',
        params: {'target_workspace': workspaceId},
      );
      if (!mounted) return;
      widget.onWorkspaceLeft?.call(workspaceId);
      setState(() {});
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('You left the workspace.')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _humanError(error, 'Could not leave this workspace.'),
            ),
          ),
        );
      }
    }
  }

  Future<void> create() async {
    if (name.text.trim().length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter at least two characters for the workspace name.',
          ),
        ),
      );
      return;
    }
    setState(() => busy = true);
    try {
      final row = await db
          .from('workspaces')
          .insert({
            'name': name.text.trim(),
            'created_by': db.auth.currentUser!.id,
          })
          .select('id,name')
          .single();
      if (mounted)
        Navigator.pop(
          context,
          WorkspaceInfo(
            '${row['id']}',
            '${row['name']}',
            admin: true,
            createdNow: true,
          ),
        );
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not create the workspace. Check your connection and try again.',
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> find() async {
    if (search.text.trim().length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter at least two characters to search.'),
        ),
      );
      return;
    }
    setState(() => busy = true);
    try {
      final data = await db.rpc(
        'search_workspaces',
        params: {'search_text': search.text.trim()},
      );
      if (mounted)
        setState(() => results = List<Map<String, dynamic>>.from(data));
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Workspace search failed. Check your connection and try again.',
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> join(String id, String workspaceName) async {
    final details = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => const _WorkspaceJoinRequestDialog(),
    );
    if (details == null) return;
    try {
      await db.rpc(
        'request_workspace_join',
        params: {
          'target_workspace': id,
          'p_applicant_name': details['name'],
          'p_requested_role': details['role'],
        },
      );
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(content: Text('Request to join "$workspaceName" sent.')),
        );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_humanError(e, 'Could not send the join request.')),
          ),
        );
    }
  }

  Future<void> choose(Map<String, dynamic> row) async {
    final member = await db
        .from('workspace_members')
        .select('role')
        .eq('workspace_id', row['id'])
        .eq('user_id', db.auth.currentUser!.id)
        .maybeSingle();
    if (!mounted) return;
    Navigator.pop(
      context,
      WorkspaceInfo(
        '${row['id']}',
        '${row['name']}',
        admin: member?['role'] == 'admin',
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Row(
      children: [
        TaskHubMascot(mood: MascotMood.teamwork, size: 42),
        SizedBox(width: 8),
        Text('Your workspaces'),
      ],
    ),
    content: SizedBox(
      width: math.min(520, MediaQuery.sizeOf(context).width * .86),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: math.max(
            180,
            math
                .min(
                  520,
                  MediaQuery.sizeOf(context).height -
                      MediaQuery.viewInsetsOf(context).bottom -
                      210,
                )
                .toDouble(),
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const MascotBanner(
                mood: MascotMood.teamwork,
                title: 'Your team, in sync',
                message: 'Choose a workspace or explore one to join.',
                mascotSize: 52,
              ),
              const SizedBox(height: 8),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: myWorkspaces(),
                builder: (c, s) {
                  if (s.hasError) return Text('Load error: ${s.error}');
                  if (s.connectionState == ConnectionState.waiting)
                    return const SizedBox(
                      height: 56,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  final spaces = s.data ?? [];
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(2, 6, 8, 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (spaces.isEmpty)
                          const EmptyState(
                            icon: Icons.groups_2_outlined,
                            title: 'No workspace yet',
                            message:
                                'Create a workspace or search for one to join.',
                            mood: MascotMood.teamwork,
                          ),
                        for (final w in spaces)
                          PressableCard(
                            margin: const EdgeInsets.only(bottom: 9),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            onTap: () => choose(w),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: lilac,
                                    borderRadius: BorderRadius.circular(13),
                                  ),
                                  child: const TaskHubMascot(
                                    size: 36,
                                    idleAnimation: false,
                                    mood: MascotMood.teamwork,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${w['name']}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '${w['role_label']}',
                                        style: const TextStyle(
                                          color: muted,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  size: 14,
                                  color: muted,
                                ),
                                if (w['workspace_role'] == 'co_founder')
                                  IconButton(
                                    tooltip: 'Leave workspace',
                                    color: danger,
                                    onPressed: busy
                                        ? null
                                        : () => leaveAsCofounder(w),
                                    icon: const Icon(
                                      Icons.logout_rounded,
                                      size: 20,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
              const Divider(),
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(Icons.add_business_rounded, size: 17, color: violet),
                    SizedBox(width: 7),
                    Text(
                      'Create workspace',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              TextField(
                controller: name,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => busy ? null : create(),
                decoration: const InputDecoration(hintText: 'Workspace name'),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: busy ? null : create,
                  icon: const Icon(Icons.add_business_rounded),
                  label: const Text('Create workspace'),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 8, bottom: 6),
                child: Row(
                  children: [
                    Icon(Icons.search_rounded, size: 17, color: violet),
                    SizedBox(width: 7),
                    Text(
                      'Find a workspace',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              TextField(
                controller: search,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => busy ? null : find(),
                decoration: const InputDecoration(hintText: 'Search by name'),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: busy ? null : find,
                  icon: const Icon(Icons.search_rounded),
                  label: const Text('Find workspace'),
                ),
              ),
              if (results.isNotEmpty) ...[
                const SizedBox(height: 10),
                for (final w in results)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: line),
                    ),
                    child: Row(
                      children: [
                        const TaskHubMascot(
                          size: 42,
                          idleAnimation: false,
                          mood: MascotMood.teamwork,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            '${w['name']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        TextButton(
                          onPressed: busy
                              ? null
                              : () => join('${w['id']}', '${w['name']}'),
                          child: const Text('Request to join'),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}

class _WorkspaceJoinRequestDialog extends StatefulWidget {
  const _WorkspaceJoinRequestDialog();

  @override
  State<_WorkspaceJoinRequestDialog> createState() =>
      _WorkspaceJoinRequestDialogState();
}

class _WorkspaceJoinRequestDialogState
    extends State<_WorkspaceJoinRequestDialog> {
  final formKey = GlobalKey<FormState>();
  final memberName = TextEditingController();
  String? workspaceRole;

  @override
  void dispose() {
    memberName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Request to join workspace'),
    content: Form(
      key: formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: memberName,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Your name'),
            validator: (value) =>
                (value ?? '').trim().length < 2 ? 'Enter your name' : null,
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: workspaceRole,
            decoration: const InputDecoration(labelText: 'Your role'),
            hint: const Text('Choose your workspace role'),
            items: const [
              DropdownMenuItem(value: 'admin', child: Text('Founder')),
              DropdownMenuItem(value: 'co_founder', child: Text('Co-founder')),
              DropdownMenuItem(value: 'employee', child: Text('Employee')),
            ],
            validator: (value) => value == null ? 'Choose your role' : null,
            onChanged: (value) => setState(() => workspaceRole = value),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!formKey.currentState!.validate()) return;
          Navigator.pop(context, {
            'name': memberName.text.trim(),
            'role': workspaceRole!,
          });
        },
        child: const Text('Send request'),
      ),
    ],
  );
}

class HubTask {
  final Map<String, dynamic> source;
  final String id, title, description, status, priority, creatorEmail, scope;
  final bool canManage, canDelete;
  final String? recurrence;
  final DateTime? due, startsAt, timerStarted;
  final int estimate, seconds;
  HubTask(Map<String, dynamic> r)
    : source = r,
      id = '${r['id']}',
      title = '${r['title']}',
      description = '${r['description'] ?? ''}',
      status = '${r['display_status'] ?? r['status'] ?? 'active'}',
      priority = '${r['priority'] ?? 'medium'}',
      creatorEmail = '${r['created_by_email'] ?? ''}',
      scope = '${r['scope'] ?? 'personal'}',
      canManage =
          '${r['assigned_to'] ?? ''}' == db.auth.currentUser?.id ||
          ('${r['owner_id'] ?? ''}' == db.auth.currentUser?.id &&
              r['assigned_to'] == null &&
              r['outgoing_assignment_status'] != 'pending'),
      canDelete = '${r['owner_id'] ?? ''}' == db.auth.currentUser?.id,
      due = r['due_at'] == null ? null : DateTime.tryParse('${r['due_at']}'),
      startsAt = r['starts_at'] == null
          ? null
          : DateTime.tryParse('${r['starts_at']}'),
      recurrence = r['recurrence'] as String?,
      timerStarted = r['timer_started_at'] == null
          ? null
          : DateTime.tryParse('${r['timer_started_at']}'),
      estimate = r['estimated_minutes'] ?? 0,
      seconds = r['actual_seconds'] ?? 0;
}

String _memberName(Map<String, dynamic> member) {
  final name = '${member['display_name'] ?? ''}'.trim();
  return name.isEmpty || name == 'null' ? 'Workspace member' : name;
}

String _workspaceRoleLabel(Map<String, dynamic> member) {
  final accessRole = '${member['role'] ?? 'member'}';
  final rawWorkspaceRole = '${member['workspace_role'] ?? ''}'.trim();
  final workspaceRole = rawWorkspaceRole.isNotEmpty
      ? rawWorkspaceRole
      : accessRole == 'admin'
      ? 'admin'
      : 'employee';
  return switch (workspaceRole) {
    'co_founder' => 'Co-founder',
    'admin' => 'Founder',
    _ => 'Employee',
  };
}

String _memberLabel(Map<String, dynamic> member) =>
    '${_memberName(member)} · ${_workspaceRoleLabel(member)}';

Future<List<Map<String, dynamic>>> loadTasks(
  String scope,
  String? workspaceId,
) async {
  if (scope == 'Workspace' && workspaceId == null) return [];
  var query = db.from('tasks').select().eq('scope', scope.toLowerCase());
  if (scope == 'Workspace') {
    query = query.eq('workspace_id', workspaceId!);
  } else {
    query = query.eq('owner_id', db.auth.currentUser!.id);
  }
  return await query.order('updated_at', ascending: false);
}

Future<List<Map<String, dynamic>>> loadTaskList(
  String scope,
  String? workspaceId,
) async {
  final tasks = await loadTasks(scope, workspaceId);
  final userId = db.auth.currentUser!.id;
  final clears = await db
      .from('task_occurrence_clears')
      .select('task_id,occurrence_date')
      .eq('user_id', userId);
  final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
  final clearedDates = <String, Set<String>>{};
  for (final clear in clears) {
    (clearedDates['${clear['task_id']}'] ??= <String>{}).add(
      '${clear['occurrence_date']}',
    );
  }
  final rowsToMark = <Map<String, dynamic>>[];
  final expiredInProgressTasks = <String, bool>{};
  for (final task in tasks) {
    if (task['status'] == 'completed' ||
        task['status'] == 'archived' ||
        task['due_at'] == null ||
        ('${task['owner_id']}' != userId &&
            '${task['assigned_to']}' != userId)) {
      continue;
    }
    final start = task['starts_at'] == null
        ? DateTime.parse('${task['due_at']}').toLocal()
        : DateTime.parse('${task['starts_at']}').toLocal();
    for (final (occurrenceStart, occurrenceDue) in _scheduledOccurrences(
      task,
      start.subtract(const Duration(seconds: 1)),
      DateTime.now(),
    )) {
      if (occurrenceDue == null || occurrenceDue.isAfter(DateTime.now()))
        continue;
      final occurrenceDate = DateFormat('yyyy-MM-dd').format(occurrenceDue);
      if (clearedDates['${task['id']}']?.contains(occurrenceDate) ?? false)
        continue;
      rowsToMark.add({
        'task_id': task['id'],
        'user_id': userId,
        'occurrence_date': occurrenceDate,
        'starts_at': occurrenceStart.toIso8601String(),
        'due_at': occurrenceDue.toIso8601String(),
      });
      final timerStarted = task['timer_started_at'] == null
          ? null
          : DateTime.tryParse('${task['timer_started_at']}')?.toLocal();
      if (task['status'] == 'in_progress' &&
          (timerStarted == null || !timerStarted.isAfter(occurrenceDue))) {
        expiredInProgressTasks['${task['id']}'] = timerStarted != null;
      }
    }
  }
  if (rowsToMark.isNotEmpty) {
    await db
        .from('task_unfinished_occurrences')
        .upsert(
          rowsToMark,
          onConflict: 'task_id,user_id,occurrence_date',
          ignoreDuplicates: true,
        );
  }
  for (final entry in expiredInProgressTasks.entries) {
    try {
      if (entry.value) {
        await db.rpc('pause_task_timer', params: {'target_task': entry.key});
      }
      await db.rpc(
        'change_task_field',
        params: {
          'target_task': entry.key,
          'field_name': 'status',
          'new_value': 'active',
          'reason_text': 'Deadline passed without completing the task',
        },
      );
    } catch (_) {
      // Keep loading task history even if a timer cannot be stopped right now.
    }
  }
  final unfinishedRows = await db
      .from('task_unfinished_occurrences')
      .select('task_id,occurrence_date,starts_at,due_at,restarted_task_id')
      .eq('user_id', userId);
  final taskById = {for (final task in tasks) '${task['id']}': task};
  final occurrenceRows = unfinishedRows.where((row) {
    final source = taskById['${row['task_id']}'];
    final clearedForDate =
        clearedDates['${row['task_id']}']?.contains(
          '${row['occurrence_date']}',
        ) ??
        false;
    return source != null &&
        !clearedForDate &&
        (scope != 'Workspace' || source['workspace_id'] == workspaceId);
  }).toList();
  final unfinishedSingleTaskIds = occurrenceRows
      .where(
        (row) =>
            _repeatFrequency(
              taskById['${row['task_id']}']?['recurrence'] as String?,
            ) ==
            'None',
      )
      .map((row) => '${row['task_id']}')
      .toSet();
  final visibleTasks = tasks.where((task) {
    if (task['status'] == 'archived') return true;
    if (unfinishedSingleTaskIds.contains('${task['id']}')) return false;
    final dates = clearedDates['${task['id']}'];
    if (dates == null || dates.isEmpty) return true;
    final recurrence = task['recurrence'] as String?;
    final repeats =
        recurrence != null && _repeatFrequency(recurrence) != 'None';
    return repeats ? !dates.contains(today) : false;
  }).toList();
  final unfinishedTasks = <Map<String, dynamic>>[];
  final recurringUnfinished = <String, Map<String, dynamic>>{};
  for (final occurrence in occurrenceRows.where(
    (row) => row['restarted_task_id'] == null,
  )) {
    final source = taskById['${occurrence['task_id']}']!;
    final parentId = '${source['id']}';
    final isRecurring =
        _repeatFrequency(source['recurrence'] as String?) != 'None';
    if (isRecurring) {
      final previous = recurringUnfinished[parentId];
      if (previous == null ||
          '${occurrence['occurrence_date']}'.compareTo(
                '${previous['occurrence_date']}',
              ) >
              0) {
        recurringUnfinished[parentId] = occurrence;
      }
    } else {
      unfinishedTasks.add(_unfinishedTaskRow(source, occurrence));
    }
  }
  for (final entry in recurringUnfinished.entries) {
    unfinishedTasks.add(_unfinishedTaskRow(taskById[entry.key]!, entry.value));
  }
  final unfinishedRecurringIds = recurringUnfinished.keys.toSet();
  final result = [
    ...visibleTasks.where(
      (task) => !unfinishedRecurringIds.contains('${task['id']}'),
    ),
    ...unfinishedTasks,
  ];
  if (scope != 'Workspace' || workspaceId == null || result.isEmpty) {
    return result;
  }

  final requests = await db
      .from('task_assignment_requests')
      .select('id,task_id,requested_by,requested_to,status,created_at')
      .or('requested_by.eq.$userId,requested_to.eq.$userId')
      .order('created_at', ascending: false);
  final members = List<Map<String, dynamic>>.from(
    await db.rpc(
      'workspace_member_list',
      params: {'target_workspace': workspaceId},
    ),
  );
  final memberById = {
    for (final member in members) '${member['user_id']}': member,
  };
  return result.map((task) {
    final parentTaskId = '${task['parent_task_id'] ?? task['id']}';
    final taskRequests = requests
        .where((request) => '${request['task_id']}' == parentTaskId)
        .toList();
    final outgoing = taskRequests
        .where((request) => '${request['requested_by']}' == userId)
        .toList();
    final outgoingPending = outgoing
        .where((request) => request['status'] == 'pending')
        .toList();
    final selectedOutgoing = outgoingPending.isNotEmpty
        ? outgoingPending.first
        : outgoing.isNotEmpty
        ? outgoing.first
        : null;
    final assigneeId = '${task['assigned_to'] ?? ''}';
    final requestedToId = '${selectedOutgoing?['requested_to'] ?? ''}';
    final creatorId = '${task['created_by'] ?? task['owner_id'] ?? ''}';
    // Pending and rejected requests do not set tasks.assigned_to; resolve the
    // requested member so the requester still sees their name and role.
    final assignedToMember =
        memberById[assigneeId.isNotEmpty ? assigneeId : requestedToId];
    final creatorMember = memberById[creatorId];
    return {
      ...task,
      'outgoing_assignment_status': selectedOutgoing?['status'],
      'outgoing_assignment_request_id': selectedOutgoing?['id'],
      'outgoing_assignment_requested_to': selectedOutgoing?['requested_to'],
      'assigned_to_name': assignedToMember == null
          ? null
          : _memberLabel(assignedToMember),
      'created_by_name': creatorMember == null
          ? task['created_by_email']
          : _memberLabel(creatorMember),
    };
  }).toList();
}

Map<String, dynamic> _unfinishedTaskRow(
  Map<String, dynamic> source,
  Map<String, dynamic> occurrence,
) => {
  ...source,
  'parent_task_id': source['id'],
  'occurrence_date': '${occurrence['occurrence_date']}',
  'starts_at': occurrence['starts_at'],
  'due_at': occurrence['due_at'],
  'status': 'unfinished',
  'display_status': 'unfinished',
  'is_unfinished_occurrence': true,
};

Future<List<Map<String, dynamic>>> loadCalendarTasks(
  String scope,
  String? workspaceId,
) async {
  // Refresh overdue occurrence history, then return the original rows so
  // Calendar can render those occurrences on their scheduled dates.
  await loadTaskList(scope, workspaceId);
  return loadTasks(scope, workspaceId);
}

Future<List<HubTask>> _loadRunningTasks() async {
  final userId = db.auth.currentUser!.id;
  final rows = await db
      .from('tasks')
      .select()
      .or('assigned_to.eq.$userId,and(owner_id.eq.$userId,assigned_to.is.null)')
      .not('timer_started_at', 'is', null)
      .neq('status', 'completed')
      .neq('status', 'archived')
      .order('timer_started_at');
  final pendingRows = await db
      .from('task_assignment_requests')
      .select('task_id')
      .eq('requested_by', userId)
      .eq('status', 'pending');
  final pendingIds = pendingRows.map((row) => '${row['task_id']}').toSet();
  return rows
      .where((row) => !pendingIds.contains('${row['id']}'))
      .map(HubTask.new)
      .toList();
}

Future<List<Map<String, dynamic>>> _loadTasksForTimer() async {
  final userId = db.auth.currentUser!.id;
  final rows = await db
      .from('tasks')
      .select()
      .or('assigned_to.eq.$userId,and(owner_id.eq.$userId,assigned_to.is.null)')
      .order('updated_at', ascending: false);
  final pendingRows = await db
      .from('task_assignment_requests')
      .select('task_id')
      .eq('requested_by', userId)
      .eq('status', 'pending');
  final pendingIds = pendingRows.map((row) => '${row['task_id']}').toSet();
  return rows.where((row) => !pendingIds.contains('${row['id']}')).toList();
}

enum _TaskStartChoice { startOnly, keepCurrent, combine }

enum _TaskStartOutcome { started, keptCurrent, cancelled }

enum _TaskRemovalAction { clear, delete }

Future<_TaskStartChoice?> _chooseTaskTimerAction(
  BuildContext context,
  HubTask newTask,
  List<HubTask> running,
) => showDialog<_TaskStartChoice>(
  context: context,
  builder: (dialogContext) {
    final runningNames = running.map((task) => task.title).join(', ');
    return AlertDialog(
      title: const Text('A task timer is already running'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Currently running: $runningNames'),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.switch_access_shortcut, color: violet),
            title: Text('Focus only on “${newTask.title}”'),
            subtitle: Text(
              'Pause the current timer${running.length == 1 ? '' : 's'} and track this task alone.',
            ),
            onTap: () =>
                Navigator.pop(dialogContext, _TaskStartChoice.startOnly),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.play_circle_outline, color: violet),
            title: const Text('Keep current task timers running'),
            subtitle: const Text(
              'Leave the new task in To do and open the timers.',
            ),
            onTap: () =>
                Navigator.pop(dialogContext, _TaskStartChoice.keepCurrent),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            enabled: running.length < 3,
            leading: Icon(
              Icons.call_merge_rounded,
              color: running.length < 3 ? violet : muted,
            ),
            title: Text('Combine with “${newTask.title}”'),
            subtitle: Text(
              running.length < 3
                  ? 'Run ${newTask.title} with $runningNames. Time is tracked for each task.'
                  : 'You already have three timers running. Switch to this task or keep the current timers.',
            ),
            onTap: running.length < 3
                ? () => Navigator.pop(dialogContext, _TaskStartChoice.combine)
                : null,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
      ],
    );
  },
);

Future<_TaskStartOutcome> _startTaskWithChoice(
  BuildContext context,
  HubTask task, {
  bool alreadyConfirmed = false,
}) async {
  try {
    final running = await _loadRunningTasks();
    if (!context.mounted) return _TaskStartOutcome.cancelled;
    if (running.any((item) => item.id == task.id)) {
      await _syncRunningTimerNotification(running);
      return _TaskStartOutcome.keptCurrent;
    }

    late final List<String> targetIds;
    if (running.isEmpty) {
      if (!alreadyConfirmed) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(
              task.status == 'in_progress' ? 'Resume task?' : 'Start task?',
            ),
            content: Text(
              '${task.status == 'in_progress' ? 'Resume' : 'Start'} “${task.title}” and begin tracking time?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              VioletActionButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(
                  task.status == 'in_progress' ? 'Resume' : 'Start task',
                ),
              ),
            ],
          ),
        );
        if (confirmed != true) return _TaskStartOutcome.cancelled;
      }
      targetIds = [task.id];
    } else {
      final choice = await _chooseTaskTimerAction(context, task, running);
      if (choice == null) return _TaskStartOutcome.cancelled;
      if (choice == _TaskStartChoice.keepCurrent) {
        await _syncRunningTimerNotification(running);
        return _TaskStartOutcome.keptCurrent;
      }
      targetIds = choice == _TaskStartChoice.combine
          ? [...running.map((item) => item.id), task.id]
          : [task.id];
    }

    await db.rpc(
      'set_running_task_timers',
      params: {'target_tasks': targetIds},
    );
    if (task.startsAt != null) {
      await _cancelNativeTaskStartAlarm(task.id, task.startsAt!);
    }
    final updatedRunning = await _loadRunningTasks();
    await _syncRunningTimerNotification(updatedRunning);
    final startedAt = DateTime.now().toUtc().toIso8601String();
    await addTaskNotification(
      taskId: task.id,
      kind: 'started',
      eventKey: 'started:${task.id}:$startedAt',
      title: '${task.title} started',
      body: targetIds.length > 1
          ? 'Tracking ${targetIds.length} tasks together, including ${task.title}.'
          : '${task.title} is now in progress.',
    );
    return _TaskStartOutcome.started;
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _humanError(
              error,
              'Could not start the task timer. Please try again.',
            ),
          ),
        ),
      );
    }
    return _TaskStartOutcome.cancelled;
  }
}

class TasksPage extends StatefulWidget {
  final String scope;
  final String? workspaceId;
  final bool isWorkspaceAdmin;
  final VoidCallback onOpenProgression;
  const TasksPage({
    super.key,
    required this.scope,
    required this.workspaceId,
    required this.isWorkspaceAdmin,
    required this.onOpenProgression,
  });
  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  String filter = 'all', sort = 'Recently updated', query = '';
  String workspaceCategory = 'My tasks';
  String deadlineFilter = 'Any deadline';
  late Future<List<Map<String, dynamic>>> future;
  Timer? dayRefresh;
  late String listDayKey;
  late final VoidCallback _notificationListener;
  @override
  void initState() {
    super.initState();
    listDayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
    future = loadTaskList(widget.scope, widget.workspaceId);
    _notificationListener = () {
      if (mounted && widget.scope == 'Workspace') {
        setState(() => future = loadTaskList(widget.scope, widget.workspaceId));
      }
    };
    notificationRevision.addListener(_notificationListener);
    dayRefresh = Timer.periodic(const Duration(minutes: 1), (_) {
      final currentDay = DateFormat('yyyy-MM-dd').format(DateTime.now());
      if (mounted) {
        listDayKey = currentDay;
        setState(() => future = loadTaskList(widget.scope, widget.workspaceId));
      }
    });
  }

  @override
  void didUpdateWidget(covariant TasksPage old) {
    super.didUpdateWidget(old);
    if (old.scope != widget.scope || old.workspaceId != widget.workspaceId)
      future = loadTaskList(widget.scope, widget.workspaceId);
  }

  @override
  void dispose() {
    dayRefresh?.cancel();
    notificationRevision.removeListener(_notificationListener);
    super.dispose();
  }

  Future<void> create() async {
    final title = TextEditingController(),
        description = TextEditingController();
    final speech = SpeechToText();
    String? priority;
    DateTime? due;
    TimeOfDay? startTime;
    TimeOfDay? dueTime;
    int? estimate;
    final estimateController = TextEditingController();
    String? assignee;
    var assigneeChosen = false;
    bool listening = false;
    final repeatDays = <String>{};
    final repeatMonths = <String>{};
    String repeatDuration = '1 month';
    String repeatFrequency = 'None';
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, refresh) => AlertDialog(
          insetPadding: EdgeInsets.symmetric(
            horizontal: MediaQuery.sizeOf(ctx).width < 600 ? 12 : 40,
            vertical: 20,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          title: Row(
            children: [
              const TaskHubMascot(mood: MascotMood.planning, size: 38),
              const SizedBox(width: 10),
              const Expanded(child: Text('Create a task')),
            ],
          ),
          content: SizedBox(
            width: math.min(480, MediaQuery.sizeOf(ctx).width * .92),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(ctx).height * .66,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MascotBanner(
                      mood: listening
                          ? MascotMood.listening
                          : MascotMood.planning,
                      title: listening ? 'I’m listening' : 'Let’s plan it',
                      message:
                          'Add a title, set a priority and choose when to focus.',
                      mascotSize: 48,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: title,
                      decoration: InputDecoration(
                        labelText: 'Task name (required)',
                        suffixIcon: IconButton(
                          tooltip: 'Speak task name',
                          icon: Icon(
                            listening ? Icons.mic : Icons.mic_none,
                            color: violet,
                          ),
                          onPressed: () async {
                            try {
                              if (!await speech.initialize()) return;
                              if (listening) {
                                await speech.stop();
                                refresh(() => listening = false);
                              } else {
                                refresh(() => listening = true);
                                await speech.listen(
                                  onResult: (result) {
                                    title.text = result.recognizedWords;
                                    if (result.finalResult)
                                      refresh(() => listening = false);
                                  },
                                );
                              }
                            } catch (_) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Voice input is not available in this browser.',
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F5FF),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: line),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Schedule & estimate',
                            style: TextStyle(
                              color: ink,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          const Text(
                            'Choose a date and time window. The estimate updates automatically.',
                            style: TextStyle(color: muted, fontSize: 11),
                          ),
                          TextField(
                            controller: estimateController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Estimated time (auto)',
                            ),
                            readOnly: true,
                          ),
                          const SizedBox(height: 16),
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              due == null
                                  ? 'Choose a date (required)'
                                  : DateFormat('EEE, MMM d').format(due!),
                            ),
                            trailing: const Icon(Icons.calendar_today),
                            onTap: () async {
                              final d = await showHubDatePicker(
                                ctx,
                                firstDate: DateUtils.dateOnly(DateTime.now()),
                                lastDate: DateTime.now().add(
                                  const Duration(days: 3650),
                                ),
                                initialDate: due ?? DateTime.now(),
                              );
                              if (d != null) {
                                refresh(() {
                                  due = d;
                                  repeatMonths.clear();
                                  startTime = null;
                                  dueTime = null;
                                  estimate = null;
                                  estimateController.clear();
                                });
                              }
                            },
                          ),
                          if (due != null) ...[
                            const SizedBox(height: 8),
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                startTime == null
                                    ? 'Set start time (required)'
                                    : 'Start time · ${startTime!.format(ctx)}',
                              ),
                              trailing: const Icon(
                                Icons.play_circle_outline_rounded,
                              ),
                              onTap: () async {
                                final t = await showHubTimePicker(
                                  ctx,
                                  initialTime:
                                      startTime ??
                                      const TimeOfDay(hour: 9, minute: 0),
                                  label: 'Choose start time',
                                );
                                if (t != null) {
                                  refresh(() {
                                    startTime = t;
                                    estimate = dueTime == null
                                        ? null
                                        : _taskEstimateMinutes(t, dueTime!);
                                    estimateController.text = estimate == null
                                        ? ''
                                        : _formatDurationMinutes(estimate!);
                                  });
                                }
                              },
                            ),
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                dueTime == null
                                    ? 'Set end time (required)'
                                    : 'End time · ${dueTime!.format(ctx)}',
                              ),
                              trailing: const Icon(Icons.schedule_rounded),
                              onTap: () async {
                                final t = await showHubTimePicker(
                                  ctx,
                                  initialTime:
                                      dueTime ??
                                      const TimeOfDay(hour: 10, minute: 0),
                                  label: 'Choose deadline time',
                                );
                                if (t != null) {
                                  refresh(() {
                                    dueTime = t;
                                    estimate = startTime == null
                                        ? null
                                        : _taskEstimateMinutes(startTime!, t);
                                    estimateController.text = estimate == null
                                        ? ''
                                        : _formatDurationMinutes(estimate!);
                                  });
                                }
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (widget.scope == 'Workspace') const SizedBox(height: 20),
                    if (widget.scope == 'Workspace')
                      FutureBuilder<List<Map<String, dynamic>>>(
                        future: widget.workspaceId == null
                            ? Future.value([])
                            : db
                                  .rpc(
                                    'workspace_member_list',
                                    params: {
                                      'target_workspace': widget.workspaceId,
                                    },
                                  )
                                  .then(
                                    (v) => List<Map<String, dynamic>>.from(v),
                                  ),
                        builder: (context, members) => members.hasData
                            ? DropdownButtonFormField<String?>(
                                initialValue: assignee,
                                decoration: InputDecoration(
                                  labelText: 'Assign to a teammate (required)',
                                  helperText: widget.isWorkspaceAdmin
                                      ? null
                                      : 'Founders are not available for employee assignment requests unless they allow requests.',
                                ),
                                items: [
                                  const DropdownMenuItem(
                                    value: null,
                                    child: Text('Keep for me'),
                                  ),
                                  for (final member in members.data!)
                                    if (member['user_id'] !=
                                            db.auth.currentUser!.id &&
                                        (widget.isWorkspaceAdmin ||
                                            member['role'] != 'admin' ||
                                            member['can_current_user_assign_to_admin'] ==
                                                true))
                                      DropdownMenuItem(
                                        value: '${member['user_id']}',
                                        child: Text(_memberLabel(member)),
                                      ),
                                ],
                                onChanged: (v) => refresh(() {
                                  assignee = v;
                                  assigneeChosen = true;
                                }),
                              )
                            : const SizedBox.shrink(),
                      ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: description,
                      decoration: const InputDecoration(
                        labelText: 'Description (optional)',
                      ),
                    ),
                    const SizedBox(height: 20),
                    DropdownButtonFormField<String>(
                      initialValue: priority,
                      decoration: const InputDecoration(
                        labelText: 'Priority (required)',
                      ),
                      items: ['low', 'medium', 'high', 'critical']
                          .map(
                            (p) => DropdownMenuItem(
                              value: p,
                              child: Text(p.toUpperCase()),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => refresh(() => priority = v),
                    ),
                    const SizedBox(height: 20),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Repeat schedule',
                        style: Theme.of(ctx).textTheme.labelLarge,
                      ),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: repeatFrequency,
                      decoration: const InputDecoration(labelText: 'Repeat'),
                      items: ['None', 'Daily', 'Weekly', 'Monthly', 'Yearly']
                          .map(
                            (v) => DropdownMenuItem(value: v, child: Text(v)),
                          )
                          .toList(),
                      onChanged: (v) => refresh(() {
                        repeatFrequency = v ?? 'None';
                        repeatDays.clear();
                        repeatMonths.clear();
                        if (repeatFrequency == 'Yearly')
                          repeatDuration = '1 year';
                      }),
                    ),
                    if ({
                      'Weekly',
                      'Monthly',
                      'Yearly',
                    }.contains(repeatFrequency))
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: EdgeInsets.only(top: 10, bottom: 4),
                          child: Text('Repeat on weekdays'),
                        ),
                      ),
                    if ({
                      'Weekly',
                      'Monthly',
                      'Yearly',
                    }.contains(repeatFrequency))
                      Wrap(
                        spacing: 5,
                        children: [
                          for (var i = 0; i < _weekdays.length; i++)
                            FilterChip(
                              label: Text(
                                [
                                  'Mon',
                                  'Tue',
                                  'Wed',
                                  'Thu',
                                  'Fri',
                                  'Sat',
                                  'Sun',
                                ][i],
                              ),
                              selected: repeatDays.contains(_weekdays[i]),
                              onSelected: (selected) => refresh(() {
                                if (selected) {
                                  repeatDays.add(_weekdays[i]);
                                } else {
                                  repeatDays.remove(_weekdays[i]);
                                }
                              }),
                            ),
                        ],
                      ),
                    if (_needsMonthSelection(repeatFrequency, repeatDuration))
                      _repeatMonthSelector(
                        due,
                        repeatDuration,
                        repeatMonths,
                        refresh,
                      ),
                    if (repeatFrequency != 'None')
                      DropdownButtonFormField<String>(
                        initialValue: repeatDuration,
                        decoration: const InputDecoration(
                          labelText: 'Repeat until',
                        ),
                        items:
                            (repeatFrequency == 'Yearly'
                                    ? ['1 year']
                                    : ['1 month', '1 year'])
                                .map(
                                  (v) => DropdownMenuItem(
                                    value: v,
                                    child: Text(v),
                                  ),
                                )
                                .toList(),
                        onChanged: (v) => refresh(() {
                          repeatDuration = v ?? '1 month';
                          repeatMonths.clear();
                        }),
                      ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            VioletActionButton(
              onPressed: () {
                String? message;
                final repeatError = _repeatSelectionError(
                  frequency: repeatFrequency,
                  duration: repeatDuration,
                  days: repeatDays,
                  months: repeatMonths,
                  start: due,
                );
                final proposedDate = due == null
                    ? null
                    : _firstSelectedOccurrence(
                        due!,
                        repeatFrequency,
                        repeatDuration,
                        repeatDays,
                        repeatMonths,
                      );
                if (title.text.trim().isEmpty) {
                  message = 'Please enter a task name.';
                } else if (due == null) {
                  message = 'Task date is required. Please choose a date.';
                } else if (startTime == null) {
                  message = 'Start time is required. Please set a start time.';
                } else if (dueTime == null) {
                  message = 'End time is required. Please set an end time.';
                } else if (estimate == null || estimate! <= 0) {
                  message = 'End time must be after the start time.';
                } else if (priority == null) {
                  message = 'Priority is required. Please choose a priority.';
                } else if (widget.scope == 'Workspace' && !assigneeChosen) {
                  message =
                      'Assignee is required. Choose a teammate or Keep for me.';
                } else if (repeatError != null) {
                  message = repeatError;
                } else if (proposedDate != null &&
                    startTime != null &&
                    DateUtils.isSameDay(
                      DateTime(
                        proposedDate.year,
                        proposedDate.month,
                        proposedDate.day,
                        startTime!.hour,
                        startTime!.minute,
                      ),
                      DateTime.now(),
                    ) &&
                    !DateTime(
                      proposedDate.year,
                      proposedDate.month,
                      proposedDate.day,
                      startTime!.hour,
                      startTime!.minute,
                    ).isAfter(DateTime.now())) {
                  message = 'Please choose a start time that has not passed.';
                }
                if (message != null) {
                  ScaffoldMessenger.of(
                    ctx,
                  ).showSnackBar(SnackBar(content: Text(message)));
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    if (repeatFrequency != 'None' && due == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Choose a date before setting a repeat schedule.'),
          ),
        );
      }
      return;
    }
    final repeatError = _repeatSelectionError(
      frequency: repeatFrequency,
      duration: repeatDuration,
      days: repeatDays,
      months: repeatMonths,
      start: due,
    );
    if (repeatError != null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(repeatError)));
      }
      return;
    }
    final scheduleDate = due == null
        ? null
        : _firstSelectedOccurrence(
            due!,
            repeatFrequency,
            repeatDuration,
            repeatDays,
            repeatMonths,
          );
    if (due != null && scheduleDate == null) return;
    final hasTimeWindow = due != null;
    final startsAt = scheduleDate == null || !hasTimeWindow
        ? null
        : DateTime(
            scheduleDate.year,
            scheduleDate.month,
            scheduleDate.day,
            startTime!.hour,
            startTime!.minute,
          );
    final deadline = scheduleDate == null
        ? null
        : hasTimeWindow
        ? DateTime(
            scheduleDate.year,
            scheduleDate.month,
            scheduleDate.day,
            dueTime!.hour,
            dueTime!.minute,
          )
        : DateTime(
            scheduleDate.year,
            scheduleDate.month,
            scheduleDate.day,
            23,
            59,
          );
    if (startsAt != null && deadline != null && !deadline.isAfter(startsAt)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('End time must be after start time.')),
        );
      }
      return;
    }
    if (startsAt != null &&
        DateUtils.isSameDay(startsAt, DateTime.now()) &&
        !startsAt.isAfter(DateTime.now())) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Choose a start time that has not passed.'),
          ),
        );
      }
      return;
    }
    final recurrence = repeatFrequency == 'None'
        ? null
        : _repeatLabel(
            repeatDays.toList(),
            repeatDuration,
            repeatFrequency,
            due == null
                ? const []
                : _repeatMonthOptions(due!, repeatDuration)
                      .where((month) => repeatMonths.contains(_monthKey(month)))
                      .map(_monthKey)
                      .toList(),
          );
    final baseTask = <String, dynamic>{
      'owner_id': db.auth.currentUser!.id,
      'created_by': db.auth.currentUser!.id,
      'created_by_email': db.auth.currentUser!.email ?? '',
      'title': title.text.trim(),
      'description': description.text,
      'priority': priority!,
      'scope': widget.scope.toLowerCase(),
      'workspace_id': widget.scope == 'Workspace' ? widget.workspaceId : null,
      'starts_at': startsAt?.toIso8601String(),
      'due_at': deadline?.toIso8601String(),
      'estimated_minutes': estimate!,
      'status': 'active',
      'recurrence': recurrence,
    };
    try {
      final created = await db.from('tasks').insert(baseTask).select('id');
      await _scheduleNativeTaskAlarms({...baseTask, 'id': created.first['id']});
      String? assignmentResult;
      if (widget.scope == 'Workspace' && assignee != null) {
        assignmentResult =
            await db.rpc(
                  'workspace_assign_task',
                  params: {
                    'target_task': created.first['id'],
                    'target_user': assignee,
                  },
                )
                as String?;
      }
      if (!mounted) return;
      setState(() => future = loadTaskList(widget.scope, widget.workspaceId));
      final message = assignmentResult == 'requested'
          ? 'Task created. Assignment request sent to your teammate.'
          : assignmentResult == 'assigned'
          ? 'Task created and assigned.'
          : 'Task created.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_humanError(error, 'Could not create this task.')),
        ),
      );
    }
  }

  Future<void> setStatus(HubTask task, String status) async {
    if (status == 'in_progress') {
      final outcome = await _startTaskWithChoice(context, task);
      if (!mounted || outcome == _TaskStartOutcome.cancelled) return;
      setState(() => future = loadTaskList(widget.scope, widget.workspaceId));
      widget.onOpenProgression();
      return;
    }
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            TaskHubMascot(mood: MascotMood.focus, size: 38),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                status == 'in_progress'
                    ? (task.status == 'in_progress'
                          ? 'Resume this task?'
                          : 'Start this task?')
                    : 'Confirm status change',
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Change ${task.title} to ${_taskStatusLabel(status)}?'),
            TextField(
              controller: reason,
              decoration: const InputDecoration(labelText: 'Reason (required)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          VioletActionButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (ok != true || (status != 'in_progress' && reason.text.trim().isEmpty))
      return;
    if (task.status == 'completed' && status != 'completed') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Completed tasks cannot be reopened. Create a follow-up task.',
          ),
        ),
      );
      return;
    }
    if (status == 'active' && task.status == 'in_progress') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('An in-progress task cannot move back to To do.'),
        ),
      );
      return;
    }
    try {
      if ((status == 'completed' || status == 'archived') &&
          task.timerStarted != null) {
        await db.rpc('pause_task_timer', params: {'target_task': task.id});
        await _syncRunningTimerNotification(await _loadRunningTasks());
      }
      if (status != 'in_progress') {
        await db.rpc(
          'change_task_field',
          params: {
            'target_task': task.id,
            'field_name': 'status',
            'new_value': status,
            'reason_text': reason.text.trim(),
          },
        );
      }
      if (status == 'active' && task.status == 'archived') {
        await db
            .from('task_occurrence_clears')
            .delete()
            .eq('task_id', task.id)
            .eq('user_id', db.auth.currentUser!.id);
      }
      if (status == 'completed' || status == 'archived') {
        unawaited(_cancelNativeTaskAlarms(task.id));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_humanError(e, 'Could not update this task.')),
          ),
        );
      return;
    }
    if (mounted)
      setState(() => future = loadTaskList(widget.scope, widget.workspaceId));
  }

  Future<bool> confirmSwipeRemoval(HubTask task) async {
    final action = await showDialog<_TaskRemovalAction>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove "${task.title}"?'),
        content: Text(
          task.status == 'archived'
              ? 'This task is already in Archived.'
              : task.recurrence != null &&
                    _repeatFrequency(task.recurrence!) != 'None'
              ? 'Clear this occurrence from your task list today. It returns tomorrow, and its history stays in Calendar.'
              : 'Remove it from your task list, but keep its history in Calendar. You can archive it separately if you want.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          if (task.canDelete)
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, _TaskRemovalAction.delete),
              style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
              child: const Text('Delete permanently'),
            ),
          if (task.status != 'archived')
            VioletActionButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, _TaskRemovalAction.clear),
              child: const Text('Clear from today'),
            ),
        ],
      ),
    );
    if (!mounted || action == null) return false;

    try {
      if (action == _TaskRemovalAction.delete) {
        final deleted = await db
            .from('tasks')
            .delete()
            .eq('id', task.id)
            .select('id');
        if (deleted.isEmpty) {
          throw StateError('This task could not be deleted.');
        }
      } else {
        final recurring =
            task.recurrence != null &&
            _repeatFrequency(task.recurrence!) != 'None';
        final clearDate = recurring
            ? DateTime.now()
            : task.due?.toLocal() ?? DateTime.now();
        await db.rpc(
          'clear_task_occurrence',
          params: {
            'target_task': task.id,
            'occurrence_date': DateFormat('yyyy-MM-dd').format(clearDate),
          },
        );
      }
      if (action == _TaskRemovalAction.delete) {
        await _cancelNativeTaskAlarms(task.id);
        await _syncRunningTimerNotification(await _loadRunningTasks());
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              action == _TaskRemovalAction.delete
                  ? 'Task deleted.'
                  : task.recurrence != null &&
                        _repeatFrequency(task.recurrence!) != 'None'
                  ? 'Today’s occurrence was cleared. This task will return tomorrow.'
                  : 'Task cleared from the list. Its history remains in Calendar.',
            ),
          ),
        );
      }
      return true;
    } catch (error) {
      debugPrint('Task removal failed for ${task.id}: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _humanError(
                error,
                'Could not remove this task. Please try again.',
              ),
            ),
          ),
        );
      }
      return false;
    }
  }

  Future<void> restartUnfinished(Map<String, dynamic> occurrence) async {
    final title = TextEditingController(text: '${occurrence['title']}');
    final parentId = '${occurrence['parent_task_id']}';
    final occurrenceDate = '${occurrence['occurrence_date']}';
    DateTime? date;
    TimeOfDay? startTime;
    TimeOfDay? endTime;
    String frequency = 'None';
    String duration = '1 month';
    final days = <String>{};
    final months = <String>{};
    final parent = await db
        .from('tasks')
        .select()
        .eq('id', parentId)
        .maybeSingle();
    if (parent == null || !mounted) return;
    final priority = '${parent['priority'] ?? 'medium'}';
    final estimateController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, refresh) => AlertDialog(
          title: Text('Restart ${title.text}'),
          content: SizedBox(
            width: math.min(440, MediaQuery.sizeOf(dialogContext).width * .88),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(dialogContext).height * .66,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: title,
                      decoration: const InputDecoration(labelText: 'Task name'),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        date == null
                            ? 'Choose a new start date (required)'
                            : DateFormat.yMMMd().format(date!),
                      ),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () async {
                        final picked = await showHubDatePicker(
                          dialogContext,
                          firstDate: DateUtils.dateOnly(DateTime.now()),
                          lastDate: DateTime.now().add(
                            const Duration(days: 3650),
                          ),
                          initialDate: date ?? DateTime.now(),
                        );
                        if (picked != null)
                          refresh(() {
                            date = picked;
                            months.clear();
                          });
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        startTime == null
                            ? 'Choose a new start time (required)'
                            : 'Start time · ${startTime!.format(dialogContext)}',
                      ),
                      trailing: const Icon(Icons.play_circle_outline),
                      onTap: () async {
                        final picked = await showHubTimePicker(
                          dialogContext,
                          initialTime: const TimeOfDay(hour: 9, minute: 0),
                          label: 'Choose start time',
                        );
                        if (picked != null) refresh(() => startTime = picked);
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        endTime == null
                            ? 'Choose a new end time (required)'
                            : 'End time · ${endTime!.format(dialogContext)}',
                      ),
                      trailing: const Icon(Icons.schedule_rounded),
                      onTap: () async {
                        final picked = await showHubTimePicker(
                          dialogContext,
                          initialTime: const TimeOfDay(hour: 10, minute: 0),
                          label: 'Choose end time',
                        );
                        if (picked != null) refresh(() => endTime = picked);
                      },
                    ),
                    TextField(
                      controller: estimateController,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'Estimated time (auto)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: frequency,
                      decoration: const InputDecoration(
                        labelText: 'Repeat schedule',
                      ),
                      items: ['None', 'Weekly', 'Monthly', 'Yearly']
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => refresh(() {
                        frequency = value ?? 'None';
                        days.clear();
                        months.clear();
                        if (frequency == 'Yearly') duration = '1 year';
                      }),
                    ),
                    if ({
                      'Weekly',
                      'Monthly',
                      'Yearly',
                    }.contains(frequency)) ...[
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: EdgeInsets.only(top: 10, bottom: 4),
                          child: Text('Repeat on weekdays'),
                        ),
                      ),
                      Wrap(
                        spacing: 5,
                        children: [
                          for (var i = 0; i < _weekdays.length; i++)
                            FilterChip(
                              label: Text(
                                [
                                  'Mon',
                                  'Tue',
                                  'Wed',
                                  'Thu',
                                  'Fri',
                                  'Sat',
                                  'Sun',
                                ][i],
                              ),
                              selected: days.contains(_weekdays[i]),
                              onSelected: (selected) => refresh(() {
                                selected
                                    ? days.add(_weekdays[i])
                                    : days.remove(_weekdays[i]);
                              }),
                            ),
                        ],
                      ),
                    ],
                    if (date != null &&
                        _needsMonthSelection(frequency, duration))
                      _repeatMonthSelector(date, duration, months, refresh),
                    if (frequency != 'None')
                      DropdownButtonFormField<String>(
                        initialValue: duration,
                        decoration: const InputDecoration(
                          labelText: 'Repeat until',
                        ),
                        items:
                            (frequency == 'Yearly'
                                    ? ['1 year']
                                    : ['1 month', '1 year'])
                                .map(
                                  (value) => DropdownMenuItem(
                                    value: value,
                                    child: Text(value),
                                  ),
                                )
                                .toList(),
                        onChanged: (value) => refresh(() {
                          duration = value ?? '1 month';
                          months.clear();
                        }),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      'Priority will remain ${priority.toUpperCase()}.',
                      style: const TextStyle(color: muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            VioletActionButton(
              onPressed: () {
                final error = _repeatSelectionError(
                  frequency: frequency,
                  duration: duration,
                  days: days,
                  months: months,
                  start: date,
                );
                final estimate = startTime == null || endTime == null
                    ? null
                    : _taskEstimateMinutes(startTime!, endTime!);
                final firstDate = date == null
                    ? null
                    : _firstSelectedOccurrence(
                        date!,
                        frequency,
                        duration,
                        days,
                        months,
                      );
                final proposedStart = firstDate == null || startTime == null
                    ? null
                    : DateTime(
                        firstDate.year,
                        firstDate.month,
                        firstDate.day,
                        startTime!.hour,
                        startTime!.minute,
                      );
                if (title.text.trim().isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('Enter a task name.')),
                  );
                } else if (date == null) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('Choose a new start date.')),
                  );
                } else if (startTime == null) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('Choose a new start time.')),
                  );
                } else if (endTime == null) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('Choose a new end time.')),
                  );
                } else if (estimate == null) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('End time must be after the start time.'),
                    ),
                  );
                } else if (error != null) {
                  ScaffoldMessenger.of(
                    dialogContext,
                  ).showSnackBar(SnackBar(content: Text(error)));
                } else if (proposedStart != null &&
                    DateUtils.isSameDay(proposedStart, DateTime.now()) &&
                    !proposedStart.isAfter(DateTime.now())) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('Choose a start time that has not passed.'),
                    ),
                  );
                } else {
                  estimateController.text = _formatDurationMinutes(estimate);
                  Navigator.pop(dialogContext, true);
                }
              },
              child: const Text('Restart task'),
            ),
          ],
        ),
      ),
    );
    if (ok != true ||
        date == null ||
        startTime == null ||
        endTime == null ||
        !mounted)
      return;
    final firstDate = _firstSelectedOccurrence(
      date!,
      frequency,
      duration,
      days,
      months,
    );
    if (firstDate == null) return;
    final newStart = DateTime(
      firstDate.year,
      firstDate.month,
      firstDate.day,
      startTime!.hour,
      startTime!.minute,
    );
    final newDue = DateTime(
      firstDate.year,
      firstDate.month,
      firstDate.day,
      endTime!.hour,
      endTime!.minute,
    );
    final recurrence = frequency == 'None'
        ? null
        : _repeatLabel(
            days.toList(),
            duration,
            frequency,
            _needsMonthSelection(frequency, duration)
                ? _repeatMonthOptions(date!, duration)
                      .where((month) => months.contains(_monthKey(month)))
                      .map(_monthKey)
                      .toList()
                : const [],
          );
    try {
      final currentUser = db.auth.currentUser!;
      final newTask = <String, dynamic>{
        'owner_id': currentUser.id,
        'created_by': currentUser.id,
        'created_by_email': currentUser.email ?? '',
        'title': title.text.trim(),
        'description': parent['description'] ?? '',
        'priority': priority,
        'scope': parent['scope'],
        'workspace_id': parent['workspace_id'],
        'starts_at': newStart.toIso8601String(),
        'due_at': newDue.toIso8601String(),
        'estimated_minutes': _taskEstimateMinutes(startTime!, endTime!),
        'status': 'active',
        'recurrence': recurrence,
      };
      final inserted = await db
          .from('tasks')
          .insert(newTask)
          .select('id')
          .single();
      final unfinishedUpdates = db
          .from('task_unfinished_occurrences')
          .update({'restarted_task_id': inserted['id']})
          .eq('task_id', parentId)
          .eq('user_id', currentUser.id);
      if (_repeatFrequency(parent['recurrence'] as String?) != 'None') {
        await unfinishedUpdates.isFilter('restarted_task_id', null);
      } else {
        await unfinishedUpdates.eq('occurrence_date', occurrenceDate);
      }
      await db.from('task_changes').insert({
        'task_id': parentId,
        'user_id': currentUser.id,
        'field': 'occurrence',
        'old_value': 'unfinished',
        'new_value': 'restarted',
        'reason': 'Restarted as a new task with a new schedule',
      });
      await _scheduleNativeTaskAlarms({...newTask, 'id': inserted['id']});
      if (!mounted) return;
      setState(() => future = loadTaskList(widget.scope, widget.workspaceId));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Task restarted and added to To do.')),
      );
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _humanError(
                error,
                'Could not restart this task. Please try again.',
              ),
            ),
          ),
        );
    }
  }

  Future<void> setPriority(HubTask task, String priority) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            TaskHubMascot(mood: MascotMood.insight, size: 38),
            SizedBox(width: 10),
            Expanded(child: Text('Confirm priority change')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Change priority from ${task.priority} to $priority?'),
            TextField(
              controller: reason,
              decoration: const InputDecoration(labelText: 'Reason (required)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          VioletActionButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (!mounted || ok != true || reason.text.trim().isEmpty) return;
    try {
      await db.rpc(
        'change_task_field',
        params: {
          'target_task': task.id,
          'field_name': 'priority',
          'new_value': priority,
          'reason_text': reason.text.trim(),
        },
      );
      if (mounted)
        setState(() => future = loadTaskList(widget.scope, widget.workspaceId));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _humanError(e, 'Could not update the task priority.'),
            ),
          ),
        );
    }
  }

  Future<void> viewHistory(HubTask task) async {
    try {
      final rows = await db
          .from('task_changes')
          .select('field,old_value,new_value,reason,created_at')
          .eq('task_id', '${task.source['parent_task_id'] ?? task.id}')
          .order('created_at', ascending: false)
          .limit(30);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              const TaskHubMascot(mood: MascotMood.insight, size: 38),
              const SizedBox(width: 10),
              Expanded(child: Text('Change history - ${task.title}')),
            ],
          ),
          content: SizedBox(
            width: math.min(430, MediaQuery.sizeOf(ctx).width * .88),
            height: math.min(400, MediaQuery.sizeOf(ctx).height * .58),
            child: rows.isEmpty
                ? const Center(child: Text('No changes recorded yet.'))
                : ListView(
                    children: rows
                        .map(
                          (row) => ListTile(
                            leading: const Icon(Icons.history, color: violet),
                            title: Text(
                              '${row['field']}: ${row['old_value']} ? ${row['new_value']}',
                            ),
                            subtitle: Text(
                              '${row['reason']}\n${DateFormat.yMMMd().add_jm().format(DateTime.parse('${row['created_at']}').toLocal())}',
                            ),
                          ),
                        )
                        .toList(),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not load change history. Try again.'),
          ),
        );
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<List<Map<String, dynamic>>>(
    future: future,
    builder: (context, s) {
      final tasks = (s.data ?? []).map(HubTask.new).toList();
      final currentUserId = db.auth.currentUser?.id ?? '';
      final categoryTasks = widget.scope != 'Workspace'
          ? tasks
          : tasks.where((task) {
              final creator =
                  '${task.source['created_by'] ?? task.source['owner_id']}';
              final assignee = '${task.source['assigned_to'] ?? ''}';
              final assignmentStatus =
                  '${task.source['outgoing_assignment_status'] ?? ''}';
              return switch (workspaceCategory) {
                'My tasks' =>
                  creator == currentUserId &&
                      (assignee.isEmpty || assignee == currentUserId) &&
                      assignmentStatus.isEmpty,
                'Assigned to' =>
                  creator == currentUserId &&
                      ((assignee.isNotEmpty && assignee != currentUserId) ||
                          assignmentStatus.isNotEmpty),
                'Assigned from' =>
                  creator != currentUserId && assignee == currentUserId,
                _ => true,
              };
            }).toList();
      var shown = categoryTasks
          .where(
            (t) =>
                t.title.toLowerCase().contains(query.toLowerCase()) &&
                (widget.scope == 'Workspace' &&
                            workspaceCategory == 'Assigned to' ||
                        filter == 'all'
                    ? t.status != 'archived'
                    : t.status == filter) &&
                (deadlineFilter == 'Any deadline' ||
                    deadlineFilter == 'No deadline' && t.due == null ||
                    deadlineFilter == 'Upcoming' &&
                        t.due != null &&
                        t.due!.isAfter(DateTime.now()) ||
                    deadlineFilter == 'Overdue' &&
                        t.due != null &&
                        t.due!.isBefore(DateTime.now()) &&
                        t.status != 'completed' ||
                    deadlineFilter == 'Has deadline' && t.due != null),
          )
          .toList();
      if (sort == 'Alphabetical') {
        shown.sort((a, b) => a.title.compareTo(b.title));
      }
      if (sort == 'Priority highest') {
        shown.sort(
          (a, b) => ['critical', 'high', 'medium', 'low']
              .indexOf(a.priority)
              .compareTo(
                ['critical', 'high', 'medium', 'low'].indexOf(b.priority),
              ),
        );
      }
      if (sort == 'Deadline earliest') {
        shown.sort(
          (a, b) =>
              (a.due ?? DateTime(9999)).compareTo(b.due ?? DateTime(9999)),
        );
      }
      if (sort == 'Deadline latest') {
        shown.sort(
          (a, b) => (b.due ?? DateTime(1)).compareTo(a.due ?? DateTime(1)),
        );
      }
      if (sort == 'Weekly recurring' || sort == 'Monthly recurring') {
        final targetFrequency = sort == 'Weekly recurring'
            ? 'Weekly'
            : 'Monthly';
        shown.sort((a, b) {
          final aMatches = _repeatFrequency(a.recurrence) == targetFrequency;
          final bMatches = _repeatFrequency(b.recurrence) == targetFrequency;
          if (aMatches != bMatches) return aMatches ? -1 : 1;
          return (a.due ?? DateTime(9999)).compareTo(b.due ?? DateTime(9999));
        });
      }
      if (sort == 'Start time earliest' || sort == 'Start time latest') {
        final descending = sort == 'Start time latest';
        shown.sort((a, b) {
          final aTime = a.startsAt ?? a.due;
          final bTime = b.startsAt ?? b.due;
          if (aTime == null) return bTime == null ? 0 : 1;
          if (bTime == null) return -1;
          return descending ? bTime.compareTo(aTime) : aTime.compareTo(bTime);
        });
      }
      final narrowLayout = MediaQuery.sizeOf(context).width < 500;
      return ListView(
        padding: EdgeInsets.all(
          MediaQuery.sizeOf(context).width < 600 ? 14 : 26,
        ),
        children: [
          if (narrowLayout) ...[
            Text(
              '${widget.scope} tasks',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const Text(
              'Keep your next step in sight. Swipe a task to clear or delete it.',
              style: TextStyle(color: muted),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: create,
                icon: const Icon(Icons.add),
                label: const Text('New task'),
              ),
            ),
          ] else
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${widget.scope} tasks',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const Text(
                        'Keep your next step in sight. Swipe a task to clear or delete it.',
                        style: TextStyle(color: muted),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: create,
                  icon: const Icon(Icons.add),
                  label: const Text('New task'),
                ),
              ],
            ),
          const SizedBox(height: 18),
          const MascotBanner(
            mood: MascotMood.planning,
            title: 'Your plans, in one place',
            message: 'Filter, search and shape a day that works for you.',
            mascotSize: 50,
          ),
          const SizedBox(height: 14),
          if (widget.scope == 'Workspace') ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final category in [
                  'My tasks',
                  'Assigned to',
                  'Assigned from',
                ])
                  ChoiceChip(
                    label: Text(category),
                    selected: workspaceCategory == category,
                    onSelected: (_) => setState(() {
                      workspaceCategory = category;
                      filter = 'all';
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          SizedBox(
            height: 48,
            child: TextField(
              onChanged: (v) => setState(() => query = v),
              decoration: const InputDecoration(
                hintText: 'Search tasks',
                prefixIcon: Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
          ),
          if (widget.scope != 'Workspace' ||
              workspaceCategory != 'Assigned to') ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('All'),
                    selected: filter == 'all',
                    onSelected: (_) => setState(() => filter = 'all'),
                  ),
                  for (final f in [
                    'active',
                    'in_progress',
                    'completed',
                    'archived',
                    'unfinished',
                  ]) ...[
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text(_taskStatusLabel(f)),
                      selected: filter == f,
                      onSelected: (_) => setState(() => filter = f),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: sort,
                  items:
                      [
                            'Recently updated',
                            'Deadline earliest',
                            'Deadline latest',
                            'Weekly recurring',
                            'Monthly recurring',
                            'Start time earliest',
                            'Start time latest',
                            'Priority highest',
                            'Alphabetical',
                          ]
                          .map(
                            (v) => DropdownMenuItem(
                              value: v,
                              child: Row(
                                children: [
                                  if (v.startsWith('Start time')) ...[
                                    const Icon(
                                      Icons.access_time_rounded,
                                      size: 17,
                                    ),
                                    const SizedBox(width: 5),
                                  ],
                                  Expanded(
                                    child: Text(
                                      v,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                  onChanged: (v) => setState(() => sort = v!),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: deadlineFilter,
                  items:
                      [
                            'Any deadline',
                            'Overdue',
                            'Upcoming',
                            'No deadline',
                            'Has deadline',
                          ]
                          .map(
                            (v) => DropdownMenuItem(
                              value: v,
                              child: Text(
                                v,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                  onChanged: (v) => setState(() => deadlineFilter = v!),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          s.hasError
              ? Text(
                  _humanError(
                    s.error!,
                    'Could not load tasks. Please try again.',
                  ),
                )
              : s.connectionState == ConnectionState.waiting
              ? const SizedBox(
                  height: 180,
                  child: Center(child: CircularProgressIndicator()),
                )
              : shown.isEmpty
              ? EmptyState(
                  icon: tasks.isEmpty
                      ? Icons.checklist_rounded
                      : Icons.search_off_rounded,
                  title: tasks.isEmpty
                      ? 'Your task list is clear'
                      : categoryTasks.isEmpty && widget.scope == 'Workspace'
                      ? 'No ${workspaceCategory.toLowerCase()} tasks'
                      : 'No matching tasks',
                  message: tasks.isEmpty
                      ? 'Create a task when you’re ready to plan your next step.'
                      : categoryTasks.isEmpty && widget.scope == 'Workspace'
                      ? workspaceCategory == 'Assigned to'
                            ? 'Tasks you assign to teammates will appear here.'
                            : workspaceCategory == 'Assigned from'
                            ? 'Tasks assigned to you by teammates will appear here.'
                            : 'Tasks you create for yourself in this workspace will appear here.'
                      : 'Try changing your search or filters.',
                  mood: tasks.isEmpty
                      ? MascotMood.planning
                      : MascotMood.insight,
                )
              : AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: Column(
                    key: ValueKey('$query|$filter|$sort|$deadlineFilter'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: shown
                        .map(
                          (t) => Dismissible(
                            key: ValueKey('task-${t.id}'),
                            direction: t.status == 'unfinished'
                                ? DismissDirection.none
                                : t.status == 'archived'
                                ? (t.canDelete
                                      ? DismissDirection.horizontal
                                      : DismissDirection.none)
                                : t.canManage
                                ? DismissDirection.horizontal
                                : DismissDirection.none,
                            confirmDismiss: (_) => confirmSwipeRemoval(t),
                            onDismissed: (_) {
                              if (mounted) {
                                setState(
                                  () => future = loadTaskList(
                                    widget.scope,
                                    widget.workspaceId,
                                  ),
                                );
                              }
                            },
                            background: _taskSwipeBackground(
                              alignment: Alignment.centerLeft,
                              color: violet,
                              icon: Icons.archive_outlined,
                            ),
                            secondaryBackground: _taskSwipeBackground(
                              alignment: Alignment.centerRight,
                              color: Colors.red.shade600,
                              icon: Icons.delete_outline_rounded,
                            ),
                            child: TaskCard(
                              task: t,
                              showProgression:
                                  widget.scope != 'Workspace' ||
                                  workspaceCategory != 'Assigned to',
                              onRestart: t.status == 'unfinished'
                                  ? () => restartUnfinished(t.source)
                                  : null,
                              onTaskTap:
                                  (widget.scope != 'Workspace' ||
                                          workspaceCategory != 'Assigned to') &&
                                      t.canManage &&
                                      (t.status == 'active' ||
                                          t.status == 'in_progress')
                                  ? () => setStatus(t, 'in_progress')
                                  : null,
                              onStatus:
                                  (widget.scope != 'Workspace' ||
                                          workspaceCategory != 'Assigned to') &&
                                      t.canManage &&
                                      t.status != 'unfinished'
                                  ? (v) => setStatus(t, v)
                                  : null,
                              onPriority:
                                  t.canManage && t.status != 'unfinished'
                                  ? (v) => setPriority(t, v)
                                  : null,
                              onHistory: t.canManage
                                  ? () => viewHistory(t)
                                  : null,
                              onMove:
                                  widget.scope == 'Workspace' &&
                                      t.scope == 'workspace' &&
                                      t.canManage &&
                                      t.status != 'unfinished'
                                  ? () async {
                                      final confirmed = await showDialog<bool>(
                                        context: context,
                                        builder: (dialogContext) => AlertDialog(
                                          title: const Text(
                                            'Move task to Personal?',
                                          ),
                                          content: Text(
                                            'Are you sure you want to move “${t.title}” from this workspace to your Personal tasks? It will no longer appear in the workspace. Its timer and history will be kept.',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(
                                                dialogContext,
                                                false,
                                              ),
                                              child: const Text('Cancel'),
                                            ),
                                            VioletActionButton(
                                              onPressed: () => Navigator.pop(
                                                dialogContext,
                                                true,
                                              ),
                                              child: const Text(
                                                'Yes, move to Personal',
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (!mounted || confirmed != true) return;
                                      try {
                                        await db.rpc(
                                          'move_task_to_personal',
                                          params: {'target_task': t.id},
                                        );
                                        if (mounted) {
                                          setState(
                                            () => future = loadTaskList(
                                              widget.scope,
                                              widget.workspaceId,
                                            ),
                                          );
                                          ScaffoldMessenger.of(context)
                                            ..hideCurrentSnackBar()
                                            ..showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'Moved to your personal tasks.',
                                                ),
                                              ),
                                            );
                                        }
                                      } catch (e) {
                                        if (mounted)
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                _humanError(
                                                  e,
                                                  'Could not move this task.',
                                                ),
                                              ),
                                            ),
                                          );
                                      }
                                    }
                                  : null,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
        ],
      );
    },
  );
}

Widget _notificationSwipeBackground({required Alignment alignment}) =>
    Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.red.shade600,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
    );

Widget _taskSwipeBackground({
  required Alignment alignment,
  required Color color,
  required IconData icon,
}) => Container(
  alignment: alignment,
  padding: const EdgeInsets.symmetric(horizontal: 22),
  decoration: BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(18),
  ),
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, color: Colors.white),
      const SizedBox(width: 8),
      const Text(
        'Task actions',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      ),
    ],
  ),
);

class TaskCard extends StatelessWidget {
  final HubTask task;
  final VoidCallback? onTaskTap;
  final ValueChanged<String>? onStatus;
  final ValueChanged<String>? onPriority;
  final VoidCallback? onMove;
  final VoidCallback? onHistory;
  final VoidCallback? onRestart;
  final bool showProgression;
  const TaskCard({
    super.key,
    required this.task,
    this.onTaskTap,
    this.onStatus,
    this.onPriority,
    this.onMove,
    this.onHistory,
    this.onRestart,
    this.showProgression = true,
  });
  bool get _showProgressionForCurrentUser {
    final assignee = '${task.source['assigned_to'] ?? ''}';
    return showProgression &&
        (assignee.isEmpty || assignee == db.auth.currentUser?.id);
  }

  String get _assignmentLabel {
    final status = '${task.source['outgoing_assignment_status'] ?? ''}';
    final assigneeId = '${task.source['assigned_to'] ?? ''}';
    final assigneeName = '${task.source['assigned_to_name'] ?? 'teammate'}';
    if (status == 'pending') return 'Request sent · $assigneeName';
    if (status == 'accepted') return 'Accepted · $assigneeName';
    if (status == 'rejected') return 'Rejected · $assigneeName';
    final creatorId =
        '${task.source['created_by'] ?? task.source['owner_id'] ?? ''}';
    if (creatorId == db.auth.currentUser?.id &&
        assigneeId.isNotEmpty &&
        assigneeId != db.auth.currentUser?.id) {
      return 'Accepted · $assigneeName';
    }
    return '';
  }

  Color get _assignmentLabelColor =>
      task.source['outgoing_assignment_status'] == 'rejected'
      ? danger
      : task.source['outgoing_assignment_status'] == 'pending'
      ? violet
      : success;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTaskTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _showProgressionForCurrentUser && task.status == 'completed'
              ? mint
              : _showProgressionForCurrentUser && task.status == 'unfinished'
              ? Colors.red.shade400
              : line,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0824143D),
            blurRadius: 18,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: MediaQuery.sizeOf(context).width < 620
          ? _compact()
          : Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: lilac,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: TaskHubMascot(
                    size: 38,
                    idleAnimation: false,
                    mood: task.status == 'completed'
                        ? MascotMood.celebration
                        : task.status == 'in_progress'
                        ? MascotMood.focus
                        : MascotMood.planning,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (task.description.isNotEmpty)
                        Text(
                          task.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                      if (task.recurrence != null)
                        Text(
                          _repeatSummary(task.recurrence!),
                          style: const TextStyle(
                            color: violet,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      const SizedBox(height: 6),
                      Text(
                        '${task.priority.toUpperCase()} -- ${task.due == null ? 'No deadline' : DateFormat.MMMd().format(task.due!)}${task.startsAt == null ? '' : ' · Starts ${DateFormat.jm().format(task.startsAt!)}'} -- ${_formatDurationMinutes(task.estimate)}',
                        style: const TextStyle(color: muted, fontSize: 11),
                      ),
                      if (task.creatorEmail.isNotEmpty &&
                          task.creatorEmail != db.auth.currentUser?.email)
                        Text(
                          'Assigned by ${task.source['created_by_name'] ?? task.creatorEmail}',
                          style: const TextStyle(color: muted, fontSize: 11),
                        ),
                      if (_assignmentLabel.isNotEmpty)
                        Text(
                          _assignmentLabel,
                          style: TextStyle(
                            color: _assignmentLabelColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      if (_showProgressionForCurrentUser && task.seconds > 0)
                        Text(
                          'Tracked ${task.seconds ~/ 60} min',
                          style: const TextStyle(color: muted, fontSize: 11),
                        ),
                    ],
                  ),
                ),
                if (onMove != null)
                  IconButton(
                    tooltip: 'Move to personal tasks',
                    onPressed: onMove,
                    icon: const Icon(
                      Icons.move_to_inbox_outlined,
                      color: violet,
                    ),
                  ),
                if (onHistory != null)
                  IconButton(
                    tooltip: 'Change history',
                    onPressed: onHistory,
                    icon: const Icon(Icons.history, color: muted),
                  ),
                if (onRestart != null)
                  FilledButton.icon(
                    onPressed: onRestart,
                    icon: const Icon(Icons.refresh_rounded, size: 17),
                    label: const Text('Restart'),
                  ),
                if (onPriority != null)
                  DropdownButton<String>(
                    value: task.priority,
                    underline: const SizedBox(),
                    items: ['low', 'medium', 'high', 'critical']
                        .map(
                          (v) => DropdownMenuItem(
                            value: v,
                            child: Text(
                              v,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) onPriority!(v);
                    },
                  ),
                if (onStatus != null && _showProgressionForCurrentUser)
                  DropdownButton<String>(
                    value: task.status,
                    underline: const SizedBox(),
                    items: _availableTaskStatuses(task.status)
                        .map(
                          (v) => DropdownMenuItem(
                            value: v,
                            enabled: true,
                            child: Text(
                              _taskStatusLabel(v),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) onStatus!(v);
                    },
                  ),
                if ((onStatus == null || !_showProgressionForCurrentUser) &&
                    _showProgressionForCurrentUser)
                  Text(
                    _taskStatusLabel(task.status),
                    style: const TextStyle(color: muted, fontSize: 11),
                  ),
              ],
            ),
    ),
  );

  Widget _compact() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: lilac,
              borderRadius: BorderRadius.circular(11),
            ),
            child: TaskHubMascot(
              size: 36,
              idleAnimation: false,
              mood: task.status == 'completed'
                  ? MascotMood.celebration
                  : task.status == 'in_progress'
                  ? MascotMood.focus
                  : MascotMood.planning,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (task.description.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      task.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                  ),
                if (task.recurrence != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      _repeatSummary(task.recurrence!),
                      style: const TextStyle(
                        color: violet,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (onHistory != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Change history',
              onPressed: onHistory,
              icon: const Icon(Icons.history, color: muted, size: 20),
            ),
          if (onRestart != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Restart with a new schedule',
              onPressed: onRestart,
              icon: const Icon(Icons.refresh_rounded, color: violet, size: 20),
            ),
          if (onMove != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Move to personal tasks',
              onPressed: onMove,
              icon: const Icon(
                Icons.move_to_inbox_outlined,
                color: violet,
                size: 20,
              ),
            ),
        ],
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _taskTag(
            task.priority.toUpperCase(),
            task.priority == 'critical' || task.priority == 'high'
                ? pinkTint
                : lilac,
          ),
          if (_showProgressionForCurrentUser)
            _taskTag(
              onTaskTap == null
                  ? _taskStatusLabel(task.status)
                  : task.status == 'active'
                  ? 'To do · tap to start'
                  : task.timerStarted == null
                  ? 'In progress · tap to resume'
                  : 'In progress · running',
              task.status == 'completed'
                  ? mintTint
                  : task.status == 'unfinished'
                  ? pinkTint
                  : const Color(0xFFF3EEFA),
            ),
          _taskTag(
            task.due == null
                ? 'No deadline'
                : DateFormat.MMMd().format(task.due!),
            task.due != null &&
                    task.due!.isBefore(DateTime.now()) &&
                    task.status != 'completed'
                ? pinkTint
                : const Color(0xFFF3EEFA),
          ),
          if (task.startsAt != null)
            _taskTag('Starts ${DateFormat.jm().format(task.startsAt!)}', lilac),
          _taskTag(
            '${_formatDurationMinutes(task.estimate)} estimate',
            Colors.white,
          ),
          if (_showProgressionForCurrentUser && task.seconds > 0)
            _taskTag('Tracked ${task.seconds ~/ 60} min', Colors.white),
          if (task.creatorEmail.isNotEmpty &&
              task.creatorEmail != db.auth.currentUser?.email)
            _taskTag(
              'From ${task.source['created_by_name'] ?? task.creatorEmail}',
              Colors.white,
            ),
          if (_assignmentLabel.isNotEmpty)
            _taskTag(
              _assignmentLabel,
              task.source['outgoing_assignment_status'] == 'rejected'
                  ? pinkTint
                  : task.source['outgoing_assignment_status'] == 'pending'
                  ? skyTint
                  : mintTint,
            ),
        ],
      ),
      if (onPriority != null ||
          (onStatus != null && _showProgressionForCurrentUser))
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (onPriority != null) ...[
                const Text(
                  'Priority',
                  style: TextStyle(color: muted, fontSize: 11),
                ),
                const SizedBox(width: 4),
                DropdownButton<String>(
                  value: task.priority,
                  isDense: true,
                  underline: const SizedBox(),
                  items: ['low', 'medium', 'high', 'critical']
                      .map(
                        (v) => DropdownMenuItem(
                          value: v,
                          child: Text(v, style: const TextStyle(fontSize: 11)),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) onPriority!(v);
                  },
                ),
              ],
              if (onStatus != null && _showProgressionForCurrentUser)
                DropdownButton<String>(
                  value: task.status,
                  isDense: true,
                  underline: const SizedBox(),
                  items: _availableTaskStatuses(task.status)
                      .map(
                        (v) => DropdownMenuItem(
                          value: v,
                          enabled: true,
                          child: Text(
                            _taskStatusLabel(v),
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) onStatus!(v);
                  },
                )
              else if (_showProgressionForCurrentUser)
                Text(
                  _taskStatusLabel(task.status),
                  style: const TextStyle(color: muted, fontSize: 11),
                ),
            ],
          ),
        ),
    ],
  );

  Widget _taskTag(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 10,
        color: ink,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

Future<bool> _confirmAndRemoveWorkspaceMember(
  BuildContext context,
  String workspaceId,
  Map<String, dynamic> member,
) async {
  final name = _memberName(member);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Remove $name from this workspace?'),
      content: const Text(
        'They will lose access to this workspace. Their assigned tasks will return to the workspace task list, and any running timers will stop.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          style: TextButton.styleFrom(foregroundColor: danger),
          child: const Text('Remove member'),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;
  try {
    await db.rpc(
      'remove_workspace_member',
      params: {
        'target_workspace': workspaceId,
        'target_member': member['user_id'],
      },
    );
    return true;
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _humanError(error, 'Could not remove this workspace member.'),
          ),
        ),
      );
    }
    return false;
  }
}

Future<void> _showWorkspaceMembers(
  BuildContext context,
  String workspaceId,
  bool isWorkspaceAdmin,
) async {
  final membersFuture = db
      .rpc('workspace_member_list', params: {'target_workspace': workspaceId})
      .then((value) async {
        final members = List<Map<String, dynamic>>.from(value);
        members.sort((a, b) {
          final aName = '${a['display_name'] ?? ''}'.trim();
          final bName = '${b['display_name'] ?? ''}'.trim();
          final aSort = aName.isEmpty ? '${a['email'] ?? ''}' : aName;
          final bSort = bName.isEmpty ? '${b['email'] ?? ''}' : bName;
          return aSort.toLowerCase().compareTo(bSort.toLowerCase());
        });
        if (isWorkspaceAdmin) {
          final permissions = List<Map<String, dynamic>>.from(
            await db.rpc(
              'workspace_admin_assignment_permissions',
              params: {'target_workspace': workspaceId},
            ),
          );
          final enabledByEmployee = {
            for (final permission in permissions)
              '${permission['employee_id']}': permission['enabled'] == true,
          };
          for (final member in members) {
            member['can_assign_task_to_admin'] =
                enabledByEmployee['${member['user_id']}'] ?? false;
          }
        }
        return members;
      });
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Workspace members'),
      content: SizedBox(
        width: math.min(430, MediaQuery.sizeOf(dialogContext).width * .86),
        height: math.min(480, MediaQuery.sizeOf(dialogContext).height * .65),
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: membersFuture,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(
                child: Text(
                  'Could not load workspace members. Please try again.',
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final members = snapshot.data!;
            if (members.isEmpty) {
              return const Center(child: Text('No workspace members found.'));
            }
            return StatefulBuilder(
              builder: (context, setDialogState) => ListView.separated(
                itemCount: members.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final member = members[index];
                  final label = _memberName(member);
                  final role = '${member['role'] ?? 'member'}';
                  final workspaceRole = _workspaceRoleLabel(member);
                  final canRemove =
                      isWorkspaceAdmin && workspaceRole != 'Founder';
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: lilac,
                      child: Text(
                        label.isEmpty
                            ? '?'
                            : label.characters.first.toUpperCase(),
                        style: const TextStyle(
                          color: violet,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    title: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: isWorkspaceAdmin && role != 'admin'
                        ? Text(
                            member['can_assign_task_to_admin'] == true
                                ? '$workspaceRole · Can request tasks from you'
                                : workspaceRole,
                          )
                        : null,
                    trailing: isWorkspaceAdmin && role != 'admin'
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Tooltip(
                                message:
                                    'Allow this employee to send task requests to you',
                                child: Switch.adaptive(
                                  value:
                                      member['can_assign_task_to_admin'] ==
                                      true,
                                  onChanged: (enabled) async {
                                    try {
                                      await db.rpc(
                                        'set_workspace_admin_assignment_permission',
                                        params: {
                                          'target_workspace': workspaceId,
                                          'target_employee': member['user_id'],
                                          'allow_assignment': enabled,
                                        },
                                      );
                                      member['can_assign_task_to_admin'] =
                                          enabled;
                                      setDialogState(() {});
                                    } catch (error) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              _humanError(
                                                error,
                                                'Could not update task request access. Please try again.',
                                              ),
                                            ),
                                          ),
                                        );
                                      }
                                    }
                                  },
                                ),
                              ),
                              if (canRemove)
                                IconButton(
                                  tooltip: 'Remove from workspace',
                                  color: danger,
                                  onPressed: () async {
                                    final removed =
                                        await _confirmAndRemoveWorkspaceMember(
                                          context,
                                          workspaceId,
                                          member,
                                        );
                                    if (removed && context.mounted) {
                                      setDialogState(
                                        () => members.removeWhere(
                                          (row) =>
                                              row['user_id'] ==
                                              member['user_id'],
                                        ),
                                      );
                                    }
                                  },
                                  icon: const Icon(
                                    Icons.person_remove_alt_1_rounded,
                                  ),
                                ),
                            ],
                          )
                        : Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: role == 'admin' ? lilac : canvas,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              workspaceRole,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                  );
                },
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

class Dashboard extends StatelessWidget {
  final String scope;
  final String? workspaceId;
  final bool isWorkspaceAdmin;
  final VoidCallback openTasks;
  const Dashboard({
    super.key,
    required this.scope,
    required this.workspaceId,
    required this.isWorkspaceAdmin,
    required this.openTasks,
  });
  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<List<Map<String, dynamic>>>(
    future: loadTaskList(scope, workspaceId),
    builder: (context, s) {
      final rows = s.data ?? [];
      final currentUserId = db.auth.currentUser?.id ?? '';
      bool madeByCurrentUser(Map<String, dynamic> row) =>
          '${row['created_by'] ?? row['owner_id']}' == currentUserId;
      final myWorkspaceRows = rows.where((row) {
        final assignee = '${row['assigned_to'] ?? ''}';
        return madeByCurrentUser(row) &&
            (assignee.isEmpty || assignee == currentUserId) &&
            row['outgoing_assignment_status'] == null;
      }).toList();
      final assignedToRows = rows.where((row) {
        final assignee = '${row['assigned_to'] ?? ''}';
        return madeByCurrentUser(row) &&
            ((assignee.isNotEmpty && assignee != currentUserId) ||
                row['outgoing_assignment_status'] != null);
      }).toList();
      final assignedFromRows = rows.where((row) {
        return !madeByCurrentUser(row) &&
            '${row['assigned_to'] ?? ''}' == currentUserId;
      }).toList();
      final workspaceMyTaskPreview = scope == 'Workspace'
          ? myWorkspaceRows
          : rows;
      final progressionRows = rows.where((row) {
        final assignee = '${row['assigned_to'] ?? ''}';
        return (assignee.isEmpty || assignee == currentUserId) &&
            row['outgoing_assignment_status'] != 'pending';
      }).toList();
      int count(String st) =>
          progressionRows.where((r) => r['status'] == st).length;
      final overdue = progressionRows
          .where(
            (r) =>
                r['due_at'] != null &&
                DateTime.parse('${r['due_at']}').isBefore(DateTime.now()) &&
                r['status'] != 'completed',
          )
          .length;
      final trackableRows = rows.where((row) {
        final assignee = '${row['assigned_to'] ?? ''}';
        return (assignee.isEmpty || assignee == currentUserId) &&
            row['outgoing_assignment_status'] != 'pending';
      });
      final trackedSeconds = trackableRows.fold<int>(
        0,
        (sum, row) => sum + (row['actual_seconds'] as int? ?? 0),
      );
      final statWidth = math.min(
        190.0,
        (MediaQuery.sizeOf(context).width - 74) / 2,
      );
      return SingleChildScrollView(
        padding: EdgeInsets.all(
          MediaQuery.sizeOf(context).width < 600 ? 16 : 27,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
              decoration: BoxDecoration(
                gradient: violetGradient,
                borderRadius: BorderRadius.circular(25),
                boxShadow: [
                  BoxShadow(
                    color: violet.withValues(alpha: .22),
                    blurRadius: 24,
                    offset: const Offset(0, 9),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat('EEEE, MMMM d').format(DateTime.now()),
                          style: const TextStyle(
                            color: Color(0xFFEAE2FF),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Welcome, ${_currentDisplayName()}! ✨',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: Colors.white,
                                height: 1.08,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          'Let’s make today count. Here’s your ${scope.toLowerCase()} overview.',
                          style: const TextStyle(
                            color: Color(0xFFEDE8FB),
                            fontSize: 12,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  const TaskHubMascot(mood: MascotMood.welcome, size: 74),
                ],
              ),
            ),
            if (scope == 'Workspace' && workspaceId != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(17),
                  border: Border.all(color: line),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: lilac,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.groups_2_outlined, color: violet),
                    ),
                    const SizedBox(width: 11),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Workspace members',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'View members alphabetically with their roles',
                            style: TextStyle(color: muted, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => _showWorkspaceMembers(
                        context,
                        workspaceId!,
                        isWorkspaceAdmin,
                      ),
                      child: const Text('View'),
                    ),
                  ],
                ),
              ),
            ],
            if (s.hasError) Text('Could not load: ${s.error}'),
            const SizedBox(height: 22),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                metric(
                  'Active tasks',
                  '${count('active')}',
                  Icons.radio_button_unchecked,
                  width: statWidth,
                ),
                metric(
                  'In progress',
                  '${count('in_progress')}',
                  Icons.timelapse,
                  width: statWidth,
                ),
                metric(
                  'Completed',
                  '${count('completed')}',
                  Icons.task_alt,
                  width: statWidth,
                ),
                metric('Overdue', '$overdue', Icons.alarm, width: statWidth),
                metric(
                  'Time tracked',
                  '${trackedSeconds ~/ 3600}h ${(trackedSeconds ~/ 60) % 60}m',
                  Icons.timer_outlined,
                  width: statWidth,
                ),
              ],
            ),
            if (scope == 'Workspace') ...[
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Workspace task lists',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _workspaceTaskCount('My tasks', myWorkspaceRows.length),
                        _workspaceTaskCount(
                          'Assigned to',
                          assignedToRows.length,
                        ),
                        _workspaceTaskCount(
                          'Assigned from',
                          assignedFromRows.length,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: line),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: lilac,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.bolt_rounded, color: violet),
                  ),
                  const SizedBox(width: 13),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Make room for focused work',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Small, steady steps move important work forward.',
                          style: TextStyle(color: muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  if (MediaQuery.sizeOf(context).width < 420)
                    IconButton(
                      tooltip: 'View tasks',
                      onPressed: openTasks,
                      icon: const Icon(
                        Icons.arrow_forward_rounded,
                        color: violet,
                      ),
                    )
                  else
                    TextButton(
                      onPressed: openTasks,
                      child: const Text('View tasks'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Text(
                    scope == 'Workspace' ? 'My workspace tasks' : 'Your tasks',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
                TextButton(onPressed: openTasks, child: const Text('See all')),
              ],
            ),
            if (workspaceMyTaskPreview.isEmpty)
              const EmptyState(
                icon: Icons.checklist_rounded,
                title: 'Your list is ready',
                message:
                    'Create a task when you’re ready to plan your next step.',
              )
            else
              ...workspaceMyTaskPreview
                  .take(4)
                  .map((r) => TaskCard(task: HubTask(r))),
          ],
        ),
      );
    },
  );
}

Widget _workspaceTaskCount(String label, int count) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
  decoration: BoxDecoration(
    color: lilac.withValues(alpha: .6),
    borderRadius: BorderRadius.circular(14),
  ),
  child: Text(
    '$label · $count',
    style: const TextStyle(
      color: ink,
      fontSize: 12,
      fontWeight: FontWeight.w600,
    ),
  ),
);

Widget metric(String title, String value, IconData icon, {double width = 190}) {
  final accent = icon == Icons.task_alt
      ? mint
      : icon == Icons.alarm
      ? pink
      : icon == Icons.timer_outlined || icon == Icons.timer
      ? sky
      : icon == Icons.timelapse
      ? secondaryViolet
      : softPurple;
  final lowerTitle = title.toLowerCase();
  final mood = lowerTitle.contains('completed')
      ? MascotMood.celebration
      : lowerTitle.contains('overdue')
      ? MascotMood.reminder
      : lowerTitle.contains('progress') || lowerTitle.contains('tracked')
      ? MascotMood.focus
      : lowerTitle.contains('estimated')
      ? MascotMood.insight
      : MascotMood.planning;
  return _PetMetricCard(
    title: title,
    value: value,
    accent: accent,
    mood: mood,
    width: width,
  );
}

class _PetMetricCard extends StatefulWidget {
  final String title;
  final String value;
  final Color accent;
  final MascotMood mood;
  final double width;

  const _PetMetricCard({
    required this.title,
    required this.value,
    required this.accent,
    required this.mood,
    required this.width,
  });

  @override
  State<_PetMetricCard> createState() => _PetMetricCardState();
}

class _PetMetricCardState extends State<_PetMetricCard> {
  bool pressed = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown: (_) => setState(() => pressed = true),
    onTapUp: (_) => setState(() => pressed = false),
    onTapCancel: () => setState(() => pressed = false),
    child: AnimatedScale(
      scale: pressed ? .965 : 1,
      duration: const Duration(milliseconds: 170),
      curve: Curves.easeOutBack,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 440),
        curve: Curves.easeOutCubic,
        width: widget.width,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.white,
              widget.accent.withValues(alpha: pressed ? .28 : .19),
              const Color(0xFFF6F0FF),
            ],
            begin: pressed ? Alignment.bottomRight : Alignment.topLeft,
            end: pressed ? Alignment.topLeft : Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: widget.accent.withValues(alpha: pressed ? .48 : .32),
          ),
          boxShadow: [
            BoxShadow(
              color: widget.accent.withValues(alpha: pressed ? .19 : .10),
              blurRadius: pressed ? 24 : 16,
              offset: Offset(0, pressed ? 3 : 7),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TaskHubMascot(mood: widget.mood, size: 50),
            const SizedBox(height: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                widget.value,
                key: ValueKey(widget.value),
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              widget.title,
              style: const TextStyle(color: muted, fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _viewTaskHistory(
  BuildContext context,
  String taskId,
  String title,
) async {
  try {
    final rows = await db
        .from('task_changes')
        .select('field,old_value,new_value,reason,created_at')
        .eq('task_id', taskId)
        .order('created_at', ascending: false)
        .limit(30);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Task history · $title'),
        content: SizedBox(
          width: math.min(430, MediaQuery.sizeOf(dialogContext).width * .88),
          height: math.min(400, MediaQuery.sizeOf(dialogContext).height * .58),
          child: rows.isEmpty
              ? const Center(child: Text('No changes recorded yet.'))
              : ListView(
                  children: rows
                      .map(
                        (row) => ListTile(
                          leading: const Icon(Icons.history, color: violet),
                          title: Text(
                            '${row['field']}: ${row['old_value']} → ${row['new_value']}',
                          ),
                          subtitle: Text(
                            '${row['reason']}\n${DateFormat.yMMMd().add_jm().format(DateTime.parse('${row['created_at']}').toLocal())}',
                          ),
                        ),
                      )
                      .toList(),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _humanError(
              error,
              'Could not load task history. Please try again.',
            ),
          ),
        ),
      );
    }
  }
}

class CalendarPage extends StatefulWidget {
  final String scope;
  final String? workspaceId;
  final bool isWorkspaceAdmin;
  const CalendarPage({
    super.key,
    required this.scope,
    required this.workspaceId,
    required this.isWorkspaceAdmin,
  });
  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime selected = DateTime.now();
  Set<String> clearedOccurrenceIds = {};
  Timer? deadlineRefresh;
  late Future<List<Map<String, dynamic>>> future;
  @override
  void initState() {
    super.initState();
    future = loadCalendarTasks(widget.scope, widget.workspaceId);
    unawaited(_loadClearedOccurrences(selected));
    deadlineRefresh = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted)
        setState(
          () => future = loadCalendarTasks(widget.scope, widget.workspaceId),
        );
    });
  }

  @override
  void didUpdateWidget(covariant CalendarPage old) {
    super.didUpdateWidget(old);
    if (old.scope != widget.scope || old.workspaceId != widget.workspaceId) {
      future = loadCalendarTasks(widget.scope, widget.workspaceId);
      unawaited(_loadClearedOccurrences(selected));
    }
  }

  @override
  void dispose() {
    deadlineRefresh?.cancel();
    super.dispose();
  }

  Future<void> _loadClearedOccurrences(DateTime date) async {
    try {
      final rows = await db
          .from('task_occurrence_clears')
          .select('task_id')
          .eq('user_id', db.auth.currentUser!.id)
          .eq('occurrence_date', DateFormat('yyyy-MM-dd').format(date));
      if (!mounted || !DateUtils.isSameDay(date, selected)) return;
      setState(() {
        clearedOccurrenceIds = rows.map((row) => '${row['task_id']}').toSet();
      });
    } catch (_) {
      if (mounted && DateUtils.isSameDay(date, selected)) {
        setState(() => clearedOccurrenceIds = {});
      }
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<List<Map<String, dynamic>>>(
    future: future,
    builder: (context, s) {
      final list = (s.data ?? [])
          .where((r) {
            if (r['due_at'] == null) return false;
            final firstDue = DateTime.parse('${r['due_at']}');
            return _occursOnDate(
              selected,
              firstDue,
              r['recurrence'] as String?,
            );
          })
          .map((r) {
            var displayTask = Map<String, dynamic>.from(r);
            if (r['recurrence'] != null && r['due_at'] != null) {
              final original = DateTime.parse('${r['due_at']}').toLocal();
              displayTask = {
                ...displayTask,
                'due_at': DateTime(
                  selected.year,
                  selected.month,
                  selected.day,
                  original.hour,
                  original.minute,
                ).toIso8601String(),
                if (r['starts_at'] != null)
                  'starts_at': DateTime(
                    selected.year,
                    selected.month,
                    selected.day,
                    DateTime.parse('${r['starts_at']}').toLocal().hour,
                    DateTime.parse('${r['starts_at']}').toLocal().minute,
                  ).toIso8601String(),
              };
            }
            if (clearedOccurrenceIds.contains('${r['id']}') &&
                r['status'] != 'completed' &&
                r['status'] != 'archived') {
              displayTask['display_status'] = 'cleared';
            }
            final displayDeadline = displayTask['due_at'] == null
                ? null
                : DateTime.tryParse('${displayTask['due_at']}')?.toLocal();
            if (displayDeadline != null &&
                displayDeadline.isBefore(DateTime.now()) &&
                r['status'] != 'completed' &&
                r['status'] != 'archived' &&
                displayTask['display_status'] != 'cleared') {
              displayTask['display_status'] = 'unfinished';
            }
            return displayTask;
          })
          .toList();
      final wide = MediaQuery.sizeOf(context).width >= 920;
      final canPlan = true;
      return Padding(
        padding: EdgeInsets.all(wide ? 28 : 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: lilac,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.calendar_month_rounded,
                    color: violet,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Calendar',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const Text(
                        'Plan your days with intention.',
                        style: TextStyle(color: muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const MascotBanner(
              mood: MascotMood.calendar,
              title: 'Pick a day, make a plan',
              message:
                  'Scheduled tasks and cleared task history stay visible on their dates.',
              mascotSize: 46,
            ),
            if (s.hasError)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('Could not load calendar tasks: ${s.error}'),
              ),
            const SizedBox(height: 18),
            Expanded(
              child: wide
                  ? Row(
                      children: [
                        SizedBox(width: 350, child: _calendarCard()),
                        const SizedBox(width: 18),
                        Expanded(
                          child: _selectedDayCard(
                            context,
                            list,
                            canPlan,
                            scrollTasks: true,
                          ),
                        ),
                      ],
                    )
                  : ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        SizedBox(height: 340, child: _calendarCard()),
                        const SizedBox(height: 14),
                        _selectedDayCard(
                          context,
                          list,
                          canPlan,
                          scrollTasks: false,
                        ),
                      ],
                    ),
            ),
          ],
        ),
      );
    },
  );

  Widget _calendarCard() => Container(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: line),
      boxShadow: const [
        BoxShadow(
          color: Color(0x08000000),
          blurRadius: 20,
          offset: Offset(0, 6),
        ),
      ],
    ),
    child: CalendarDatePicker(
      initialDate: selected,
      firstDate: DateTime(2020),
      lastDate: DateTime(2036),
      onDateChanged: (d) {
        setState(() {
          selected = d;
          clearedOccurrenceIds = {};
        });
        unawaited(_loadClearedOccurrences(d));
      },
    ),
  );

  Widget _selectedDayCard(
    BuildContext context,
    List<Map<String, dynamic>> tasks,
    bool canPlan, {
    required bool scrollTasks,
  }) {
    final historyTasks = tasks
        .where(
          (task) =>
              task['status'] == 'completed' ||
              task['status'] == 'archived' ||
              task['display_status'] == 'unfinished' ||
              task['display_status'] == 'cleared',
        )
        .toList();
    final scheduledTasks = tasks
        .where(
          (task) =>
              task['status'] != 'completed' &&
              task['status'] != 'archived' &&
              task['display_status'] != 'unfinished' &&
              task['display_status'] != 'cleared',
        )
        .toList();
    final compact = MediaQuery.sizeOf(context).width < 480;
    final dateHeading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          DateFormat('EEEE').format(selected),
          style: const TextStyle(
            color: violet,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          DateFormat.yMMMMd().format(selected),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ],
    );
    final planButton = FilledButton.icon(
      onPressed: () => _plan(context),
      icon: const Icon(Icons.add_rounded, size: 18),
      label: const Text('Plan a task'),
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 20,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (compact)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                dateHeading,
                if (canPlan) ...[
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerRight, child: planButton),
                ],
              ],
            )
          else
            Row(
              children: [
                Expanded(child: dateHeading),
                if (canPlan) planButton,
              ],
            ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 13),
            child: Divider(height: 1),
          ),
          if (tasks.isEmpty)
            const EmptyState(
              icon: Icons.event_available_rounded,
              title: 'A clear day',
              message: 'No tasks are scheduled for this date.',
              mood: MascotMood.calendar,
            )
          else if (scrollTasks)
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 120, maxHeight: 320),
              child: ListView(
                shrinkWrap: true,
                primary: false,
                padding: EdgeInsets.zero,
                children: _calendarTaskEntries(scheduledTasks, historyTasks),
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _calendarTaskEntries(scheduledTasks, historyTasks),
            ),
        ],
      ),
    );
  }

  List<Widget> _calendarTaskEntries(
    List<Map<String, dynamic>> scheduledTasks,
    List<Map<String, dynamic>> historyTasks,
  ) => [
    for (final task in scheduledTasks) ...[
      TaskCard(
        task: HubTask(task),
        onHistory: () =>
            _viewTaskHistory(context, '${task['id']}', '${task['title']}'),
      ),
      const SizedBox(height: 8),
    ],
    if (historyTasks.isNotEmpty) ...[
      Padding(
        padding: EdgeInsets.only(
          top: scheduledTasks.isEmpty ? 0 : 6,
          bottom: 8,
        ),
        child: Row(
          children: [
            const Icon(Icons.history_rounded, size: 17, color: violet),
            const SizedBox(width: 7),
            Text(
              'Task history (${historyTasks.length})',
              style: const TextStyle(
                color: violet,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
      for (final task in historyTasks) ...[
        TaskCard(
          task: HubTask(task),
          onHistory: () =>
              _viewTaskHistory(context, '${task['id']}', '${task['title']}'),
        ),
        const SizedBox(height: 8),
      ],
    ],
  ];
  Future<void> _plan(BuildContext context) async {
    final title = TextEditingController();
    final description = TextEditingController();
    final speech = SpeechToText();
    String? priority;
    String? assignee;
    var assigneeChosen = false;
    final repeatDays = <String>{};
    final repeatMonths = <String>{};
    var repeatDuration = '1 month';
    var repeatFrequency = 'None';
    TimeOfDay? startTime;
    TimeOfDay? dueTime;
    int? estimate;
    final estimateController = TextEditingController();
    var listening = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, refresh) => AlertDialog(
          insetPadding: EdgeInsets.symmetric(
            horizontal: MediaQuery.sizeOf(c).width < 600 ? 12 : 40,
            vertical: 20,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          title: const Row(
            children: [
              TaskHubMascot(mood: MascotMood.calendar, size: 38),
              SizedBox(width: 10),
              Expanded(child: Text('Plan a task')),
            ],
          ),
          content: SizedBox(
            width: math.min(480, MediaQuery.sizeOf(c).width * .92),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(c).height * .66,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const MascotBanner(
                      mood: MascotMood.calendar,
                      title: 'Plan this day',
                      message:
                          'Choose a time window and the days this task repeats.',
                      mascotSize: 46,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: title,
                      decoration: InputDecoration(
                        labelText: 'Task name (required)',
                        suffixIcon: IconButton(
                          icon: Icon(
                            listening ? Icons.mic : Icons.mic_none,
                            color: violet,
                          ),
                          onPressed: () async {
                            if (!await speech.initialize()) return;
                            if (listening) {
                              await speech.stop();
                              refresh(() => listening = false);
                            } else {
                              refresh(() => listening = true);
                              await speech.listen(
                                onResult: (r) {
                                  title.text = r.recognizedWords;
                                  if (r.finalResult)
                                    refresh(() => listening = false);
                                },
                              );
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F5FF),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: line),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Schedule & estimate',
                            style: TextStyle(
                              color: ink,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${DateFormat('EEE, MMM d').format(selected)} · estimate follows the time window',
                            style: const TextStyle(color: muted, fontSize: 11),
                          ),
                          TextField(
                            controller: estimateController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Estimated time (auto)',
                            ),
                            readOnly: true,
                          ),
                          const SizedBox(height: 16),
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              startTime == null
                                  ? 'Set start time (required)'
                                  : 'Start time · ${startTime!.format(c)}',
                            ),
                            trailing: const Icon(
                              Icons.play_circle_outline_rounded,
                            ),
                            onTap: () async {
                              final value = await showHubTimePicker(
                                c,
                                initialTime:
                                    startTime ??
                                    const TimeOfDay(hour: 9, minute: 0),
                                label: 'Choose start time',
                              );
                              if (value != null) {
                                refresh(() {
                                  startTime = value;
                                  estimate = dueTime == null
                                      ? null
                                      : _taskEstimateMinutes(value, dueTime!);
                                  estimateController.text = estimate == null
                                      ? ''
                                      : _formatDurationMinutes(estimate!);
                                });
                              }
                            },
                          ),
                          const SizedBox(height: 8),
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              dueTime == null
                                  ? 'Set end time (required)'
                                  : 'End time · ${dueTime!.format(c)}',
                            ),
                            trailing: const Icon(Icons.schedule_rounded),
                            onTap: () async {
                              final value = await showHubTimePicker(
                                c,
                                initialTime:
                                    dueTime ??
                                    const TimeOfDay(hour: 10, minute: 0),
                                label: 'Choose deadline time',
                              );
                              if (value != null) {
                                refresh(() {
                                  dueTime = value;
                                  estimate = startTime == null
                                      ? null
                                      : _taskEstimateMinutes(startTime!, value);
                                  estimateController.text = estimate == null
                                      ? ''
                                      : _formatDurationMinutes(estimate!);
                                });
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: description,
                      decoration: const InputDecoration(
                        labelText: 'Description (optional)',
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (widget.scope == 'Workspace')
                      FutureBuilder<List<Map<String, dynamic>>>(
                        future: widget.workspaceId == null
                            ? Future.value([])
                            : db
                                  .rpc(
                                    'workspace_member_list',
                                    params: {
                                      'target_workspace': widget.workspaceId,
                                    },
                                  )
                                  .then(
                                    (value) =>
                                        List<Map<String, dynamic>>.from(value),
                                  ),
                        builder: (context, members) {
                          if (!members.hasData) return const SizedBox.shrink();
                          return DropdownButtonFormField<String?>(
                            initialValue: assignee,
                            decoration: InputDecoration(
                              labelText: 'Assign to a teammate (required)',
                              helperText: widget.isWorkspaceAdmin
                                  ? null
                                  : 'Founders are not available for employee assignment requests unless they allow requests.',
                            ),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('Keep for me'),
                              ),
                              for (final member in members.data!)
                                if (member['user_id'] !=
                                    db.auth.currentUser!.id)
                                  if (widget.isWorkspaceAdmin ||
                                      member['role'] != 'admin' ||
                                      member['can_current_user_assign_to_admin'] ==
                                          true)
                                    DropdownMenuItem<String?>(
                                      value: '${member['user_id']}',
                                      child: Text(_memberLabel(member)),
                                    ),
                            ],
                            onChanged: (value) => refresh(() {
                              assignee = value;
                              assigneeChosen = true;
                            }),
                          );
                        },
                      ),
                    const SizedBox(height: 20),
                    DropdownButtonFormField<String>(
                      initialValue: priority,
                      decoration: const InputDecoration(
                        labelText: 'Priority (required)',
                      ),
                      items: ['low', 'medium', 'high', 'critical']
                          .map(
                            (p) => DropdownMenuItem(
                              value: p,
                              child: Text(p.toUpperCase()),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => refresh(() => priority = v),
                    ),
                    const SizedBox(height: 20),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Repeat schedule'),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: repeatFrequency,
                      decoration: const InputDecoration(labelText: 'Repeat'),
                      items: ['None', 'Daily', 'Weekly', 'Monthly', 'Yearly']
                          .map(
                            (v) => DropdownMenuItem(value: v, child: Text(v)),
                          )
                          .toList(),
                      onChanged: (v) => refresh(() {
                        repeatFrequency = v ?? 'None';
                        repeatDays.clear();
                        repeatMonths.clear();
                        if (repeatFrequency == 'Yearly')
                          repeatDuration = '1 year';
                      }),
                    ),
                    if ({
                      'Weekly',
                      'Monthly',
                      'Yearly',
                    }.contains(repeatFrequency))
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: EdgeInsets.only(top: 10, bottom: 4),
                          child: Text('Repeat on weekdays'),
                        ),
                      ),
                    if ({
                      'Weekly',
                      'Monthly',
                      'Yearly',
                    }.contains(repeatFrequency))
                      Wrap(
                        spacing: 5,
                        children: [
                          for (var i = 0; i < _weekdays.length; i++)
                            FilterChip(
                              label: Text(
                                [
                                  'Mon',
                                  'Tue',
                                  'Wed',
                                  'Thu',
                                  'Fri',
                                  'Sat',
                                  'Sun',
                                ][i],
                              ),
                              selected: repeatDays.contains(_weekdays[i]),
                              onSelected: (value) => refresh(() {
                                if (value) {
                                  repeatDays.add(_weekdays[i]);
                                } else {
                                  repeatDays.remove(_weekdays[i]);
                                }
                              }),
                            ),
                        ],
                      ),
                    if (_needsMonthSelection(repeatFrequency, repeatDuration))
                      _repeatMonthSelector(
                        selected,
                        repeatDuration,
                        repeatMonths,
                        refresh,
                      ),
                    if (repeatFrequency != 'None')
                      DropdownButtonFormField<String>(
                        initialValue: repeatDuration,
                        decoration: const InputDecoration(
                          labelText: 'Repeat until',
                        ),
                        items:
                            (repeatFrequency == 'Yearly'
                                    ? ['1 year']
                                    : ['1 month', '1 year'])
                                .map(
                                  (v) => DropdownMenuItem(
                                    value: v,
                                    child: Text(v),
                                  ),
                                )
                                .toList(),
                        onChanged: (v) => refresh(() {
                          repeatDuration = v ?? '1 month';
                          repeatMonths.clear();
                        }),
                      ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            VioletActionButton(
              onPressed: () {
                String? message;
                final repeatError = _repeatSelectionError(
                  frequency: repeatFrequency,
                  duration: repeatDuration,
                  days: repeatDays,
                  months: repeatMonths,
                  start: selected,
                );
                final proposedDate = _firstSelectedOccurrence(
                  selected,
                  repeatFrequency,
                  repeatDuration,
                  repeatDays,
                  repeatMonths,
                );
                if (title.text.trim().isEmpty) {
                  message = 'Please enter a task name.';
                } else if (startTime == null) {
                  message = 'Start time is required. Please set a start time.';
                } else if (dueTime == null) {
                  message = 'End time is required. Please set an end time.';
                } else if (estimate == null || estimate! <= 0) {
                  message = 'End time must be after the start time.';
                } else if (priority == null) {
                  message = 'Priority is required. Please choose a priority.';
                } else if (widget.scope == 'Workspace' && !assigneeChosen) {
                  message =
                      'Assignee is required. Choose a teammate or Keep for me.';
                } else if (repeatError != null) {
                  message = repeatError;
                } else if (proposedDate != null &&
                    DateUtils.isSameDay(
                      DateTime(
                        proposedDate.year,
                        proposedDate.month,
                        proposedDate.day,
                        startTime!.hour,
                        startTime!.minute,
                      ),
                      DateTime.now(),
                    ) &&
                    !DateTime(
                      proposedDate.year,
                      proposedDate.month,
                      proposedDate.day,
                      startTime!.hour,
                      startTime!.minute,
                    ).isAfter(DateTime.now())) {
                  message = 'Please choose a start time that has not passed.';
                }
                if (message != null) {
                  ScaffoldMessenger.of(
                    c,
                  ).showSnackBar(SnackBar(content: Text(message)));
                  return;
                }
                Navigator.pop(c, true);
              },
              child: const Text('Add task'),
            ),
          ],
        ),
      ),
    );
    if (ok == true && title.text.trim().isNotEmpty) {
      final repeatError = _repeatSelectionError(
        frequency: repeatFrequency,
        duration: repeatDuration,
        days: repeatDays,
        months: repeatMonths,
        start: selected,
      );
      if (repeatError != null) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(repeatError)));
        }
        return;
      }
      final scheduleDate = _firstSelectedOccurrence(
        selected,
        repeatFrequency,
        repeatDuration,
        repeatDays,
        repeatMonths,
      );
      if (scheduleDate == null) return;
      final startsAt = DateTime(
        scheduleDate.year,
        scheduleDate.month,
        scheduleDate.day,
        startTime!.hour,
        startTime!.minute,
      );
      final deadline = DateTime(
        scheduleDate.year,
        scheduleDate.month,
        scheduleDate.day,
        dueTime!.hour,
        dueTime!.minute,
      );
      if (!deadline.isAfter(startsAt)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('End time must be after start time.')),
          );
        }
        return;
      }
      if (DateUtils.isSameDay(startsAt, DateTime.now()) &&
          !startsAt.isAfter(DateTime.now())) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Choose a start time that has not passed.'),
            ),
          );
        }
        return;
      }
      final base = <String, dynamic>{
        'owner_id': db.auth.currentUser!.id,
        'created_by': db.auth.currentUser!.id,
        'created_by_email': db.auth.currentUser!.email ?? '',
        'title': title.text.trim(),
        'description': description.text,
        'priority': priority!,
        'estimated_minutes': estimate!,
        'scope': widget.scope.toLowerCase(),
        'workspace_id': widget.scope == 'Workspace' ? widget.workspaceId : null,
        'starts_at': startsAt.toIso8601String(),
        'due_at': deadline.toIso8601String(),
        'status': 'active',
        'recurrence': repeatFrequency == 'None'
            ? null
            : _repeatLabel(
                repeatDays.toList(),
                repeatDuration,
                repeatFrequency,
                _repeatMonthOptions(selected, repeatDuration)
                    .where((month) => repeatMonths.contains(_monthKey(month)))
                    .map(_monthKey)
                    .toList(),
              ),
      };
      try {
        final created = await db
            .from('tasks')
            .insert(base)
            .select('id')
            .single();
        await _scheduleNativeTaskAlarms({...base, 'id': created['id']});
        String? assignmentResult;
        if (widget.scope == 'Workspace' && assignee != null) {
          assignmentResult =
              await db.rpc(
                    'workspace_assign_task',
                    params: {
                      'target_task': created['id'],
                      'target_user': assignee,
                    },
                  )
                  as String?;
        }
        if (!mounted) return;
        setState(() => future = loadTasks(widget.scope, widget.workspaceId));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              assignmentResult == 'requested'
                  ? 'Task added. Assignment request sent.'
                  : assignmentResult == 'assigned'
                  ? 'Task added and assigned.'
                  : 'Task added to your calendar.',
            ),
          ),
        );
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_humanError(error, 'Could not add this task.')),
          ),
        );
      }
    }
  }
}

class TimePage extends StatefulWidget {
  final String scope;
  final String? workspaceId;
  const TimePage({super.key, required this.scope, required this.workspaceId});
  @override
  State<TimePage> createState() => _TimePageState();
}

class _TimePageState extends State<TimePage> {
  Timer? timer;
  DateTime now = DateTime.now();
  String selectedBoardStatus = 'active';
  String? nativeTimerFingerprint;
  late Future<List<Map<String, dynamic>>> future;
  late Future<List<Map<String, dynamic>>> history;
  @override
  void initState() {
    super.initState();
    future = _loadTasksForTimer();
    history = loadHistory();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => now = DateTime.now());
    });
  }

  Future<List<Map<String, dynamic>>> loadHistory() => db
      .from('task_timer_sessions')
      .select('started_at,stopped_at,elapsed_seconds,tasks(title)')
      .eq('user_id', db.auth.currentUser!.id)
      .not('stopped_at', 'is', null)
      .order('stopped_at', ascending: false)
      .limit(5);

  @override
  void didUpdateWidget(covariant TimePage old) {
    super.didUpdateWidget(old);
    if (old.scope != widget.scope || old.workspaceId != widget.workspaceId)
      future = _loadTasksForTimer();
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> toggle(HubTask t) async {
    try {
      if (t.timerStarted != null) {
        await db.rpc('pause_task_timer', params: {'target_task': t.id});
        await _syncRunningTimerNotification(await _loadRunningTasks());
      } else {
        await _startTaskWithChoice(context, t);
      }
      if (mounted) {
        setState(() => future = _loadTasksForTimer());
        history = loadHistory();
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_humanError(e, 'Could not update the timer.')),
          ),
        );
    }
  }

  Future<void> confirmStart(HubTask task) async {
    final outcome = await _startTaskWithChoice(context, task);
    if (!mounted || outcome == _TaskStartOutcome.cancelled) return;
    setState(() => future = _loadTasksForTimer());
    history = loadHistory();
  }

  Future<void> completeTask(HubTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark task done?'),
        content: Text('Complete ${task.title} and stop its timer?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep working'),
          ),
          VioletActionButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Mark done'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      if (task.timerStarted != null) {
        await db.rpc('pause_task_timer', params: {'target_task': task.id});
      }
      await db.rpc(
        'change_task_field',
        params: {
          'target_task': task.id,
          'field_name': 'status',
          'new_value': 'completed',
          'reason_text': 'Completed from Progression status',
        },
      );
      await _syncRunningTimerNotification(await _loadRunningTasks());
      unawaited(_cancelNativeTaskAlarms(task.id));
      await addTaskNotification(
        taskId: task.id,
        kind: 'completed',
        eventKey: 'completed:${task.id}',
        title: '${task.title} completed',
        body: 'Your task is marked done.',
      );
      if (!mounted) return;
      setState(() {
        future = _loadTasksForTimer();
        history = loadHistory();
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_humanError(error, 'Could not complete this task.')),
          ),
        );
      }
    }
  }

  Widget _progressionTaskCard(HubTask task, DateTime now) {
    final running = task.timerStarted != null;
    final elapsed =
        task.seconds +
        (running ? now.difference(task.timerStarted!).inSeconds : 0);
    return GestureDetector(
      onTap:
          task.status == 'active' || (task.status == 'in_progress' && !running)
          ? () => confirmStart(task)
          : null,
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: running ? softPurple : line),
          boxShadow: const [
            BoxShadow(
              color: Color(0x06000000),
              blurRadius: 10,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              task.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 5),
            Text(
              '${_formatDurationMinutes(task.estimate)} estimate · ${task.priority.toUpperCase()}',
              style: const TextStyle(color: muted, fontSize: 11),
            ),
            if (task.seconds > 0 || running)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  'Tracked ${elapsed ~/ 60} min',
                  style: const TextStyle(color: muted, fontSize: 11),
                ),
              ),
            const SizedBox(height: 8),
            if (task.status == 'active')
              SizedBox(
                width: double.infinity,
                child: VioletActionButton(
                  onPressed: () => confirmStart(task),
                  child: const Text('Start task'),
                ),
              )
            else if (task.status == 'in_progress')
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  OutlinedButton.icon(
                    onPressed: running
                        ? () => toggle(task)
                        : () => confirmStart(task),
                    icon: Icon(
                      running ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    ),
                    label: Text(running ? 'Pause' : 'Resume'),
                  ),
                  TextButton.icon(
                    onPressed: () => completeTask(task),
                    icon: const Icon(Icons.check_circle_outline_rounded),
                    label: const Text('Done'),
                  ),
                ],
              )
            else
              const Text(
                'Done',
                style: TextStyle(color: success, fontWeight: FontWeight.w700),
              ),
          ],
        ),
      ),
    );
  }

  Widget _progressionLane(
    String status,
    String title,
    List<HubTask> tasks,
    DateTime now,
  ) {
    final color = switch (status) {
      'active' => violet,
      'in_progress' => warning,
      _ => success,
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F0FA),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              CircleAvatar(
                radius: 12,
                backgroundColor: color.withValues(alpha: .12),
                child: Text(
                  '${tasks.length}',
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (tasks.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'No tasks here yet',
                textAlign: TextAlign.center,
                style: TextStyle(color: muted, fontSize: 11),
              ),
            )
          else
            for (final task in tasks) _progressionTaskCard(task, now),
        ],
      ),
    );
  }

  Widget _progressionBoard({
    required List<HubTask> todo,
    required List<HubTask> inProgress,
    required List<HubTask> done,
    required DateTime now,
  }) {
    const stages = <(String, String)>[
      ('active', 'To do'),
      ('in_progress', 'In progress'),
      ('completed', 'Done'),
    ];
    final lanes = <String, List<HubTask>>{
      'active': todo,
      'in_progress': inProgress,
      'completed': done,
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 820) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (status, title) in stages)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: _progressionLane(status, title, lanes[status]!, now),
                  ),
                ),
            ],
          );
        }
        final selectedTitle = stages
            .firstWhere((stage) => stage.$1 == selectedBoardStatus)
            .$2;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 7,
              children: [
                for (final (status, title) in stages)
                  ChoiceChip(
                    label: Text('$title (${lanes[status]!.length})'),
                    selected: selectedBoardStatus == status,
                    onSelected: (_) =>
                        setState(() => selectedBoardStatus = status),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            _progressionLane(
              selectedBoardStatus,
              selectedTitle,
              lanes[selectedBoardStatus]!,
              now,
            ),
          ],
        );
      },
    );
  }

  Widget _focusCard(
    HubTask? task,
    int elapsed,
    int estimateMinutes, {
    VoidCallback? onPause,
  }) {
    final active = task != null;
    final progress = estimateMinutes <= 0
        ? 0.0
        : (elapsed / (estimateMinutes * 60)).clamp(0.0, 1.0);
    final time =
        '${(elapsed ~/ 3600).toString().padLeft(2, '0')}:${((elapsed ~/ 60) % 60).toString().padLeft(2, '0')}:${(elapsed % 60).toString().padLeft(2, '0')}';
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: active
              ? const [Color(0xFFE8DEFF), Color(0xFFF8F5FF)]
              : const [Colors.white, Color(0xFFFFF8FC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: active ? softPurple : line),
        boxShadow: [
          BoxShadow(
            color: active
                ? violet.withValues(alpha: .13)
                : const Color(0x0824143D),
            blurRadius: active ? 28 : 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: active
          ? Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.circle, color: success, size: 7),
                            SizedBox(width: 6),
                            Text(
                              'FOCUS SESSION',
                              style: TextStyle(
                                color: violet,
                                fontSize: 9,
                                letterSpacing: 1.1,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        task.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'You’re making steady progress.',
                        style: TextStyle(color: muted, fontSize: 11),
                      ),
                      const SizedBox(height: 7),
                      SizedBox(
                        width: double.infinity,
                        child: FittedBox(
                          alignment: Alignment.centerLeft,
                          fit: BoxFit.scaleDown,
                          child: Text(
                            time,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                              color: ink,
                            ),
                          ),
                        ),
                      ),
                      if (estimateMinutes > 0)
                        Text(
                          elapsed < estimateMinutes * 60
                              ? '${_formatDurationMinutes(((estimateMinutes * 60 - elapsed) / 60).ceil())} left in your estimate'
                              : 'Estimate passed · finish at your pace',
                          style: const TextStyle(color: muted, fontSize: 10),
                        ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: onPause,
                        icon: const Icon(Icons.pause_rounded, size: 17),
                        label: const Text('Pause session'),
                      ),
                    ],
                  ),
                ),
                if (MediaQuery.sizeOf(context).width >= 420) ...[
                  const SizedBox(width: 14),
                  Container(
                    width: 90,
                    height: 90,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: violet.withValues(alpha: .16),
                          blurRadius: 22,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: SizedBox(
                      width: 82,
                      height: 82,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: progress),
                        duration: const Duration(milliseconds: 450),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, _) => Stack(
                          fit: StackFit.expand,
                          children: [
                            CircularProgressIndicator(
                              value: value,
                              strokeWidth: 7,
                              strokeCap: StrokeCap.round,
                              backgroundColor: Colors.white,
                              color: violet,
                            ),
                            Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    estimateMinutes == 0
                                        ? '—'
                                        : '${(value * 100).round()}%',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 17,
                                    ),
                                  ),
                                  const Text(
                                    'estimate',
                                    style: TextStyle(color: muted, fontSize: 8),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            )
          : Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(Icons.spa_rounded, color: violet),
                ),
                const SizedBox(width: 13),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ready when you are',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Choose a task below to begin a focus session.',
                        style: TextStyle(color: muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_downward_rounded,
                  color: violet,
                  size: 19,
                ),
              ],
            ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<List<Map<String, dynamic>>>(
    future: future,
    builder: (context, s) {
      final userId = db.auth.currentUser!.id;
      final taskRows = (s.data ?? [])
          .where(
            (r) =>
                r['status'] != 'archived' &&
                (r['owner_id'] == userId || r['assigned_to'] == userId),
          )
          .toList();
      final tasks = taskRows.map(HubTask.new).toList();
      final activeTasks = tasks
          .where((task) => task.timerStarted != null)
          .toList();
      final todoTasks = tasks.where((task) => task.status == 'active').toList();
      final inProgressTasks = tasks
          .where((task) => task.status == 'in_progress')
          .toList();
      final doneTasks = tasks
          .where((task) => task.status == 'completed')
          .toList();
      if (s.hasData) {
        final fingerprint = activeTasks
            .map(
              (task) =>
                  '${task.id}:${task.timerStarted!.toUtc().toIso8601String()}',
            )
            .join('|');
        if (nativeTimerFingerprint != fingerprint) {
          nativeTimerFingerprint = fingerprint;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) unawaited(_syncRunningTimerNotification(activeTasks));
          });
        }
      }
      int elapsedFor(HubTask task) =>
          task.seconds +
          (task.timerStarted == null
              ? 0
              : now.difference(task.timerStarted!).inSeconds);
      return SingleChildScrollView(
        padding: EdgeInsets.all(
          MediaQuery.sizeOf(context).width < 600 ? 18 : 26,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: lilac,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.timer_rounded, color: violet),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Progression status',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const Text(
                        'Track up to three tasks at once.',
                        style: TextStyle(color: muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            MascotBanner(
              mood: activeTasks.isEmpty
                  ? MascotMood.focus
                  : MascotMood.celebration,
              title: activeTasks.isEmpty
                  ? 'Ready to focus?'
                  : 'You’re in focus mode',
              message: activeTasks.isEmpty
                  ? 'Start a task or combine up to three task timers.'
                  : activeTasks.map((task) => task.title).join(' · '),
              mascotSize: 48,
            ),
            const SizedBox(height: 12),
            if (activeTasks.isEmpty)
              _focusCard(null, 0, 0)
            else
              for (final task in activeTasks) ...[
                _focusCard(
                  task,
                  elapsedFor(task),
                  task.estimate,
                  onPause: () => toggle(task),
                ),
                const SizedBox(height: 10),
              ],
            const SizedBox(height: 18),
            const Text(
              'Task progression',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            const Text(
              'Start a timer when you’re ready to work.',
              style: TextStyle(color: muted, fontSize: 11),
            ),
            const SizedBox(height: 8),
            _progressionBoard(
              todo: todoTasks,
              inProgress: inProgressTasks,
              done: doneTasks,
              now: now,
            ),
            const SizedBox(height: 8),
            const Row(
              children: [
                Icon(Icons.history_rounded, color: violet, size: 18),
                SizedBox(width: 7),
                Text(
                  'Recent focus sessions',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            SizedBox(
              height: 132,
              child: Container(
                margin: const EdgeInsets.only(top: 7),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(17),
                  border: Border.all(color: line),
                ),
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: history,
                  builder: (context, history) {
                    if (history.hasError)
                      return Text(
                        'History unavailable: ${history.error}',
                        style: const TextStyle(color: muted),
                      );
                    if (!history.hasData)
                      return const Center(child: LinearProgressIndicator());
                    if (history.data!.isEmpty)
                      return const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Your completed sessions will appear here.',
                          style: TextStyle(color: muted, fontSize: 11),
                        ),
                      );
                    return ListView.separated(
                      itemCount: history.data!.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final r = history.data![index];
                        return ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                          ),
                          leading: const Icon(
                            Icons.check_circle_outline_rounded,
                            color: success,
                            size: 19,
                          ),
                          title: Text(
                            '${(r['tasks'] as Map?)?['title'] ?? 'Task'}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            DateFormat('MMM d · h:mm a').format(
                              DateTime.parse('${r['started_at']}').toLocal(),
                            ),
                            style: const TextStyle(fontSize: 10),
                          ),
                          trailing: Text(
                            '${((r['elapsed_seconds'] ?? 0) as int) ~/ 60} min',
                            style: const TextStyle(
                              color: violet,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class InsightsPage extends StatelessWidget {
  final String scope;
  final String? workspaceId;
  const InsightsPage({
    super.key,
    required this.scope,
    required this.workspaceId,
  });
  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<List<Map<String, dynamic>>>(
    future: loadTasks(scope, workspaceId),
    builder: (context, s) {
      final rows = s.data ?? [];
      final currentUserId = db.auth.currentUser?.id ?? '';
      final progressionRows = rows.where((row) {
        final assignee = '${row['assigned_to'] ?? ''}';
        return scope != 'Workspace' ||
            assignee.isEmpty ||
            assignee == currentUserId;
      }).toList();
      int count(String v) =>
          progressionRows.where((r) => r['status'] == v).length;
      final seconds = progressionRows.fold<int>(
        0,
        (n, r) => n + (r['actual_seconds'] as int? ?? 0),
      );
      final estimated = progressionRows.fold<int>(
        0,
        (n, r) => n + (r['estimated_minutes'] as int? ?? 0),
      );
      return SingleChildScrollView(
        padding: EdgeInsets.all(
          MediaQuery.sizeOf(context).width < 600 ? 16 : 27,
        ),
        child: Padding(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Task insights',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const MascotBanner(
                mood: MascotMood.insight,
                title: 'Your effort, at a glance',
                message:
                    'These summaries use the tasks and timer records in your hub.',
                mascotSize: 50,
              ),
              const Text(
                'A clear view of the progress you’re making.',
                style: TextStyle(color: muted),
              ),
              const SizedBox(height: 23),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  metric('Total tasks', '${rows.length}', Icons.list_alt),
                  metric('Completed', '${count('completed')}', Icons.task_alt),
                  metric(
                    'Active',
                    '${count('active')}',
                    Icons.radio_button_unchecked,
                  ),
                  metric(
                    'In progress',
                    '${count('in_progress')}',
                    Icons.timelapse,
                  ),
                  metric(
                    'Tracked time',
                    '${seconds ~/ 3600}h ${(seconds ~/ 60) % 60}m',
                    Icons.timer,
                  ),
                  metric(
                    'Estimated time',
                    _formatDurationMinutes(estimated),
                    Icons.hourglass_bottom,
                  ),
                ],
              ),
              const SizedBox(height: 25),
              const Text(
                'Tasks by status',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              for (final item in [
                ('Completed', 'completed', success),
                ('In progress', 'in_progress', violet),
                ('Active', 'active', secondaryViolet),
                ('Archived', 'archived', muted),
              ])
                _insightRow(
                  item.$1,
                  count(item.$2),
                  progressionRows.length,
                  item.$3,
                ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Time estimate vs actual',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _timeValue(
                            'Estimated',
                            estimated,
                            math.max(estimated, seconds ~/ 60),
                            violet,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _timeValue(
                            'Tracked',
                            seconds ~/ 60,
                            math.max(estimated, seconds ~/ 60),
                            success,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Tasks by priority',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              for (final p in ['critical', 'high', 'medium', 'low'])
                _priority(
                  p,
                  rows.where((r) => r['priority'] == p).length,
                  rows.length,
                ),
            ],
          ),
        ),
      );
    },
  );
}

Widget _insightRow(String label, int value, int total, Color color) => Padding(
  padding: const EdgeInsets.only(bottom: 12),
  child: Row(
    children: [
      SizedBox(
        width: 92,
        child: Text(label, style: const TextStyle(color: muted, fontSize: 12)),
      ),
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: total == 0 ? 0 : value / total),
            duration: const Duration(milliseconds: 520),
            curve: Curves.easeOutCubic,
            builder: (context, progress, _) => LinearProgressIndicator(
              value: progress,
              minHeight: 9,
              color: color,
              backgroundColor: lilac,
            ),
          ),
        ),
      ),
      const SizedBox(width: 12),
      SizedBox(
        width: 24,
        child: Text(
          '$value',
          textAlign: TextAlign.end,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
        ),
      ),
    ],
  ),
);

Widget _timeValue(String label, int minutes, int maxMinutes, Color color) =>
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: muted, fontSize: 11)),
        const SizedBox(height: 4),
        Text(
          _formatDurationMinutes(minutes),
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: LinearProgressIndicator(
            value: maxMinutes == 0 ? 0 : minutes / maxMinutes,
            minHeight: 6,
            color: color,
            backgroundColor: lilac,
          ),
        ),
      ],
    );

Widget _priority(String name, int count, int total) {
  final progress = total == 0 ? 0.0 : count / total;
  return Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      children: [
        SizedBox(
          width: 84,
          child: Text(name, style: const TextStyle(color: muted)),
        ),
        Expanded(
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 9,
            color: violet,
            backgroundColor: lilac,
          ),
        ),
        const SizedBox(width: 12),
        Text('$count'),
      ],
    ),
  );
}

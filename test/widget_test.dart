import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:task_hub/main.dart';
import 'package:task_hub/ui/taskhub_mascot_kit.dart';

void main() {
  testWidgets('TaskHub splash welcomes before authentication', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(const MaterialApp(home: TaskHubSplash()));
    await tester.pump(const Duration(milliseconds: 900));

    expect(find.text('TaskHub welcomes you'), findsOneWidget);
    expect(
      find.text('A happy little start to a more focused day.'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'TaskHub puppy holding the TaskHub and Meoww banners',
      ),
      findsOneWidget,
    );

    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
  });

  testWidgets('violet action button keeps its gradient and tap callback', (
    tester,
  ) async {
    var taps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: VioletActionButton(
              onPressed: () => taps++,
              child: const Text('Save'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Save'), findsOneWidget);
    final button = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    final decoration = button.decoration! as BoxDecoration;
    expect(decoration.gradient, violetGradient);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('shared mascot responds to a tap without a custom callback', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: TaskHubMascot(mood: MascotMood.planning, size: 72),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TaskHubMascot));
    await tester.pump(const Duration(milliseconds: 80));

    final scale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
    expect(scale.scale, 1.08);
    expect(
      find.bySemanticsLabel('TaskHub puppy and kitten helping you plan'),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 400));
    semantics.dispose();
  });

  testWidgets('branded date dialog returns the selected day', (tester) async {
    DateTime? selected;
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                selected = await showHubDatePicker(
                  context,
                  initialDate: DateTime(2026, 11, 9),
                  firstDate: DateTime(2026, 11, 9),
                  lastDate: DateTime(2026, 11, 10),
                );
              },
              child: const Text('Open date picker'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open date picker'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Pick your day'), findsOneWidget);
    await tester.tap(find.text('10'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('Select date'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(selected, DateTime(2026, 11, 10));
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
  });

  testWidgets('branded time picker exposes its label and actions', (
    tester,
  ) async {
    TimeOfDay? selected;
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                selected = await showHubTimePicker(
                  context,
                  initialTime: const TimeOfDay(hour: 9, minute: 0),
                  label: 'Choose a time',
                );
              },
              child: const Text('Open time picker'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open time picker'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Choose a time'), findsOneWidget);
    expect(find.text('Set time'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(selected, isNull);
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
  });
}

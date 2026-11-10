import 'dart:math' as math;
import 'package:flutter/material.dart';

enum MascotMood {
  welcome,
  planning,
  listening,
  celebration,
  calendar,
  focus,
  insight,
  teamwork,
  reminder,
  empty,
}

extension MascotMoodStyle on MascotMood {
  Color get accent => switch (this) {
    MascotMood.celebration => const Color(0xFFE7779B),
    MascotMood.calendar => const Color(0xFF8964E8),
    MascotMood.focus => const Color(0xFF6841C8),
    MascotMood.insight => const Color(0xFF6096D5),
    MascotMood.teamwork => const Color(0xFF4BAF92),
    MascotMood.reminder => const Color(0xFFB78425),
    MascotMood.listening => const Color(0xFF8964E8),
    MascotMood.empty => const Color(0xFF8964E8),
    MascotMood.planning => const Color(0xFF6841C8),
    MascotMood.welcome => const Color(0xFF6841C8),
  };

  List<Color> get backdrop => switch (this) {
    MascotMood.celebration => const [Color(0xFFFFE5EF), Color(0xFFFFF5D9)],
    MascotMood.calendar => const [Color(0xFFE8DEFF), Color(0xFFEAF5FF)],
    MascotMood.focus => const [Color(0xFFE8DEFF), Color(0xFFF4EDFF)],
    MascotMood.insight => const [Color(0xFFEAF5FF), Color(0xFFE8FBF4)],
    MascotMood.teamwork => const [Color(0xFFEAF5FF), Color(0xFFE8FBF4)],
    MascotMood.reminder => const [Color(0xFFFFF7E2), Color(0xFFFFEDF4)],
    MascotMood.listening => const [Color(0xFFE8DEFF), Color(0xFFEAF5FF)],
    MascotMood.empty => const [Color(0xFFF2ECFF), Color(0xFFFFEDF4)],
    MascotMood.planning => const [Color(0xFFF2ECFF), Color(0xFFFFEDF4)],
    MascotMood.welcome => const [Color(0xFFE8DEFF), Color(0xFFF2ECFF)],
  };

  String get accessibleName => switch (this) {
    MascotMood.celebration => 'celebrating',
    MascotMood.calendar => 'planning your calendar',
    MascotMood.focus => 'focused',
    MascotMood.insight => 'reviewing progress',
    MascotMood.teamwork => 'ready to collaborate',
    MascotMood.reminder => 'sharing a reminder',
    MascotMood.listening => 'listening',
    MascotMood.empty => 'waiting for your next task',
    MascotMood.planning => 'helping you plan',
    MascotMood.welcome => 'welcoming you',
  };
}

class TaskHubMark extends StatelessWidget {
  final double size;
  final MascotMood mood;
  const TaskHubMark({
    super.key,
    this.size = 64,
    this.mood = MascotMood.welcome,
  });
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _TaskHubMarkPainter(mood)),
  );
}

class _TaskHubMarkPainter extends CustomPainter {
  final MascotMood mood;
  const _TaskHubMarkPainter(this.mood);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(1, 1, 98, 98),
        const Radius.circular(27),
      ),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFF3E8FF), Color(0xFFE4D1FA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(const Rect.fromLTWH(0, 0, 100, 100)),
    );
    const outline = Color(0xFF44253E);
    final stroke = Paint()
      ..color = outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    final ink = Paint()..color = outline;
    final tan = Paint()..color = const Color(0xFFF0C996);
    final honey = Paint()..color = const Color(0xFFC9823F);
    final cream = Paint()..color = const Color(0xFFFFE6B6);

    final topRibbon = Path()
      ..moveTo(16, 32)
      ..quadraticBezierTo(18, 9, 48, 9)
      ..lineTo(78, 12)
      ..quadraticBezierTo(86, 14, 91, 6)
      ..quadraticBezierTo(91, 27, 79, 29)
      ..lineTo(31, 28)
      ..quadraticBezierTo(21, 28, 16, 36)
      ..close();
    canvas.drawPath(topRibbon, tan);
    canvas.drawPath(topRibbon, stroke);

    final tail = Path()
      ..moveTo(71, 65)
      ..quadraticBezierTo(86, 71, 82, 58)
      ..quadraticBezierTo(80, 53, 85, 54)
      ..quadraticBezierTo(95, 67, 84, 75)
      ..quadraticBezierTo(78, 78, 70, 75)
      ..close();
    canvas.drawPath(tail, honey);
    canvas.drawPath(tail, stroke);

    final leftEar = Path()
      ..moveTo(31, 36)
      ..quadraticBezierTo(17, 25, 20, 44)
      ..quadraticBezierTo(22, 56, 34, 56)
      ..close();
    final rightEar = Path()
      ..moveTo(67, 36)
      ..quadraticBezierTo(82, 25, 79, 45)
      ..quadraticBezierTo(77, 57, 65, 55)
      ..close();
    canvas.drawPath(leftEar, honey);
    canvas.drawPath(leftEar, stroke);
    canvas.drawPath(rightEar, honey);
    canvas.drawPath(rightEar, stroke);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(34, 65, 34, 27),
        const Radius.circular(10),
      ),
      Paint()..color = const Color(0xFFF9F7F4),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(34, 65, 34, 27),
        const Radius.circular(10),
      ),
      stroke,
    );
    for (var y = 72.0; y < 86; y += 6) {
      canvas.drawLine(
        Offset(39, y),
        Offset(62, y),
        Paint()
          ..color = const Color(0xFFD9D4D2)
          ..strokeWidth = 1.1,
      );
    }
    canvas.drawCircle(const Offset(57, 77), 3.2, ink);
    canvas.drawCircle(
      const Offset(55.8, 76),
      0.8,
      Paint()..color = Colors.white,
    );

    canvas.drawOval(const Rect.fromLTWH(24, 26, 52, 48), honey);
    canvas.drawOval(const Rect.fromLTWH(29, 31, 42, 39), cream);
    canvas.drawOval(
      const Rect.fromLTWH(35, 47, 30, 20),
      Paint()..color = const Color(0xFFFFF0D3),
    );
    canvas.drawOval(const Rect.fromLTWH(24, 26, 52, 48), stroke);

    for (final x in [40.0, 60.0]) {
      canvas.drawCircle(Offset(x, 48), 6.2, Paint()..color = Colors.white);
      canvas.drawCircle(Offset(x, 48), 4.2, ink);
      canvas.drawCircle(
        Offset(x - 1.2, 46.5),
        1.2,
        Paint()..color = Colors.white,
      );
      if (mood == MascotMood.focus || mood == MascotMood.planning) {
        canvas.drawLine(
          Offset(x - 5.2, 44.4),
          Offset(x + 5.2, 44.4),
          Paint()
            ..color = outline
            ..strokeWidth = 1.35
            ..strokeCap = StrokeCap.round,
        );
      }
    }
    if (mood == MascotMood.celebration || mood == MascotMood.insight) {
      for (final x in [31.0, 69.0]) {
        canvas.drawCircle(
          Offset(x, 59),
          3,
          Paint()..color = const Color(0xFFFF91B5).withValues(alpha: .78),
        );
      }
    }
    final nose = Path()
      ..moveTo(46, 55)
      ..quadraticBezierTo(50, 51, 54, 55)
      ..quadraticBezierTo(50, 61, 46, 55)
      ..close();
    canvas.drawPath(nose, ink);
    canvas.drawLine(const Offset(50, 59), const Offset(50, 62), stroke);
    final smile = Path()
      ..moveTo(45, 61)
      ..quadraticBezierTo(50, mood == MascotMood.celebration ? 68 : 65, 55, 61);
    canvas.drawPath(
      smile,
      Paint()
        ..color = outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round,
    );

    final bottomRibbon = Path()
      ..moveTo(19, 82)
      ..lineTo(29, 79)
      ..quadraticBezierTo(50, 87, 72, 79)
      ..lineTo(82, 82)
      ..lineTo(77, 90)
      ..lineTo(84, 96)
      ..quadraticBezierTo(51, 92, 18, 97)
      ..lineTo(24, 90)
      ..close();
    canvas.drawPath(bottomRibbon, tan);
    canvas.drawPath(bottomRibbon, stroke);

    void ribbonWord(String text, double top) {
      const glyphs = <String, List<(double, double, double, double)>>{
        'A': [(0, 8, 4, 0), (4, 0, 8, 8), (1.5, 5, 6.5, 5)],
        'B': [
          (0, 0, 0, 8),
          (0, 0, 6, 0),
          (6, 0, 8, 1.5),
          (8, 1.5, 8, 3),
          (8, 3, 6, 4),
          (0, 4, 6, 4),
          (6, 4, 8, 5),
          (8, 5, 8, 6.5),
          (8, 6.5, 6, 8),
          (6, 8, 0, 8),
        ],
        'H': [(0, 0, 0, 8), (8, 0, 8, 8), (0, 4, 8, 4)],
        'K': [(0, 0, 0, 8), (8, 0, 0, 4), (0, 4, 8, 8)],
        'S': [
          (8, 0, 1.5, 0),
          (1.5, 0, 0, 1.5),
          (0, 1.5, 0, 3),
          (0, 3, 1.5, 4),
          (1.5, 4, 6.5, 4),
          (6.5, 4, 8, 5),
          (8, 5, 8, 6.5),
          (8, 6.5, 6.5, 8),
          (6.5, 8, 0, 8),
        ],
        'T': [(0, 0, 8, 0), (4, 0, 4, 8)],
        'U': [
          (0, 0, 0, 6.5),
          (0, 6.5, 1.5, 8),
          (1.5, 8, 6.5, 8),
          (6.5, 8, 8, 6.5),
          (8, 6.5, 8, 0),
        ],
      };
      const advance = 10.5;
      final start = (100 - (text.length * advance - 2.5)) / 2;
      final letterPaint = Paint()
        ..color = outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.25
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      for (var i = 0; i < text.length; i++) {
        for (final segment in glyphs[text[i]]!) {
          canvas.drawLine(
            Offset(start + i * advance + segment.$1, top + segment.$2),
            Offset(start + i * advance + segment.$3, top + segment.$4),
            letterPaint,
          );
        }
      }
    }

    ribbonWord('TASKHUB', 16);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TaskHubMarkPainter oldDelegate) =>
      mood != oldDelegate.mood;
}

class TaskHubMascot extends StatefulWidget {
  final MascotMood mood;
  final double size;
  final bool idleAnimation;
  final VoidCallback? onTap;

  const TaskHubMascot({
    super.key,
    this.mood = MascotMood.welcome,
    this.size = 64,
    this.idleAnimation = true,
    this.onTap,
  });

  @override
  State<TaskHubMascot> createState() => _TaskHubMascotState();
}

class _TaskHubMascotState extends State<TaskHubMascot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _idle;
  bool _reacting = false;

  @override
  void initState() {
    super.initState();
    _idle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    );
    if (widget.idleAnimation) _idle.repeat();
  }

  @override
  void didUpdateWidget(covariant TaskHubMascot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.idleAnimation != oldWidget.idleAnimation) {
      if (widget.idleAnimation) {
        _idle.repeat();
      } else {
        _idle.stop();
        _idle.value = 0;
      }
    }
  }

  @override
  void dispose() {
    _idle.dispose();
    super.dispose();
  }

  void _react() {
    setState(() => _reacting = true);
    Future<void>.delayed(const Duration(milliseconds: 360), () {
      if (mounted) setState(() => _reacting = false);
    });
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'TaskHub puppy and kitten ${widget.mood.accessibleName}',
    button: true,
    hint: 'Tap for a cheer',
    child: GestureDetector(
      onTap: _react,
      child: AnimatedBuilder(
        animation: _idle,
        builder: (context, _) {
          final offset = widget.idleAnimation
              ? math.sin(_idle.value * math.pi * 2) * 3.2
              : 0.0;
          return Transform.translate(
            offset: Offset(0, offset),
            child: AnimatedScale(
              scale: _reacting ? 1.08 : 1,
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutBack,
              child: SizedBox.square(
                dimension: widget.size,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: widget.size * .92,
                      height: widget.size * .92,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: widget.mood.backdrop,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(widget.size * .30),
                        boxShadow: [
                          BoxShadow(
                            color: widget.mood.accent.withValues(alpha: .15),
                            blurRadius: widget.size * .25,
                            offset: Offset(0, widget.size * .08),
                          ),
                        ],
                      ),
                      padding: EdgeInsets.all(widget.size * .04),
                      child: CustomPaint(
                        painter: _PetDuoPainter(
                          mood: widget.mood,
                          progress: _idle.value,
                          reacting: _reacting,
                        ),
                      ),
                    ),
                    Positioned(
                      right: widget.size * .01,
                      top: widget.size * .01,
                      child: Icon(
                        Icons.auto_awesome_rounded,
                        size: widget.size * .19,
                        color: widget.mood.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

/// A compact cartoon scene shared by every animated TaskHub companion.
/// The puppy and kitten take turns running, hopping, floating and waving.
class _PetDuoPainter extends CustomPainter {
  final MascotMood mood;
  final double progress;
  final bool reacting;

  const _PetDuoPainter({
    required this.mood,
    required this.progress,
    required this.reacting,
  });

  static const outline = Color(0xFF44253E);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    final dogPhase = reacting ? .83 : progress;
    final catPhase = reacting ? .91 : (progress + .37) % 1;
    final orbit = math.sin(progress * math.pi * 2) * 5;
    _pet(
      canvas,
      Offset(34 + orbit, 55 + math.cos(progress * math.pi * 2) * 1.8),
      dogPhase,
      cat: false,
    );
    _pet(
      canvas,
      Offset(67 - orbit, 55 - math.cos(progress * math.pi * 2) * 1.8),
      catPhase,
      cat: true,
    );
    _moodSparkles(canvas);
    canvas.restore();
  }

  void _pet(Canvas canvas, Offset center, double phase, {required bool cat}) {
    final run = phase < .25;
    final jump = phase >= .25 && phase < .5;
    final floating = phase >= .5 && phase < .75;
    final waving = phase >= .75;
    final local = (phase * 4) % 1;
    final hop = run
        ? math.sin(local * math.pi * 2) * 2
        : jump
        ? -math.sin(local * math.pi) * 9
        : floating
        ? -3 - math.sin(local * math.pi * 2) * 2
        : 0.0;
    final stride = run
        ? math.sin(local * math.pi * 2) * 5
        : jump
        ? 4
        : 0.0;
    final waveLift = waving ? 11 + math.sin(local * math.pi * 2) * 2 : 0.0;
    final fur = cat ? const Color(0xFFAA8AEF) : const Color(0xFFC9823F);
    final lightFur = cat ? const Color(0xFFF1E9FF) : const Color(0xFFFFE6B6);
    final innerEar = cat ? const Color(0xFFFF91B5) : const Color(0xFF9E5A43);
    final stroke = Paint()
      ..color = outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final furPaint = Paint()..color = fur;
    final lightPaint = Paint()..color = lightFur;
    final innerPaint = Paint()..color = innerEar;
    final ink = Paint()..color = outline;

    canvas.save();
    canvas.translate(center.dx, center.dy + hop);
    canvas.rotate(run ? math.sin(local * math.pi * 2) * .055 : 0);

    // Wiggly tails move independently, making the two characters feel alive.
    canvas.save();
    canvas.translate(cat ? 12 : 11, 8);
    canvas.rotate(math.sin(phase * math.pi * 2) * .45 + (cat ? -.65 : .25));
    final tail = Path()
      ..moveTo(0, 0)
      ..cubicTo(10, 2, 9, -12, 3, -10);
    canvas.drawPath(
      tail,
      Paint()
        ..color = fur
        ..style = PaintingStyle.stroke
        ..strokeWidth = cat ? 5 : 7
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(tail, stroke..strokeWidth = 1.5);
    canvas.restore();

    // Body and little bouncing feet.
    canvas.drawOval(const Rect.fromLTRB(-12, 0, 12, 23), furPaint);
    canvas.drawOval(const Rect.fromLTRB(-12, 0, 12, 23), stroke);
    for (final side in [-1.0, 1.0]) {
      final footY = jump ? 23 - stride.abs() * .45 : 23.0;
      final footX = side * (6 + (run ? stride * side * .25 : 0));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(footX, footY), width: 11, height: 7),
          const Radius.circular(4),
        ),
        lightPaint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(footX, footY), width: 11, height: 7),
          const Radius.circular(4),
        ),
        stroke,
      );
    }

    // Raised and swinging paws make the run, jump and hello phases readable.
    for (final side in [-1.0, 1.0]) {
      final arm = Path()
        ..moveTo(side * 8, 5)
        ..quadraticBezierTo(
          side * (17 + (run ? stride * side : 0)),
          9 + (side < 0 && waving ? -waveLift : 0),
          side * (15 + (run ? stride * side : 0)),
          16 + (side < 0 && waving ? -waveLift : 0),
        );
      canvas.drawPath(
        arm,
        Paint()
          ..color = cat ? lightFur : const Color(0xFFF9F7F4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawPath(arm, stroke..strokeWidth = 1.8);
      final paw = arm.getBounds().bottomRight;
      canvas.drawCircle(paw, 3.1, lightPaint);
      canvas.drawCircle(paw, 3.1, stroke..strokeWidth = 1.2);
    }

    // Cat ears are pointed; the puppy has soft floppy ears.
    if (cat) {
      for (final side in [-1.0, 1.0]) {
        final ear = Path()
          ..moveTo(side * 6, -21)
          ..lineTo(side * 16, -37)
          ..quadraticBezierTo(side * 20, -25, side * 18, -15)
          ..close();
        canvas.drawPath(ear, furPaint);
        canvas.drawPath(ear, stroke);
        final inner = Path()
          ..moveTo(side * 9, -21)
          ..lineTo(side * 15, -32)
          ..lineTo(side * 15, -20)
          ..close();
        canvas.drawPath(inner, innerPaint);
      }
    } else {
      for (final side in [-1.0, 1.0]) {
        final ear = Path()
          ..moveTo(side * 10, -24)
          ..quadraticBezierTo(side * 21, -33, side * 20, -15)
          ..quadraticBezierTo(side * 17, -4, side * 8, -8)
          ..close();
        canvas.drawPath(ear, furPaint);
        canvas.drawPath(ear, stroke);
        canvas.drawOval(
          Rect.fromCenter(center: Offset(side * 15, -17), width: 5, height: 10),
          innerPaint,
        );
      }
    }

    // Round face, eye blinks and pupils that follow each screen's action.
    canvas.drawCircle(const Offset(0, -16), 18, furPaint);
    canvas.drawCircle(const Offset(0, -16), 18, stroke);
    canvas.drawOval(const Rect.fromLTRB(-11, -11, 11, -1), lightPaint);
    final blink = _blinkAt((phase + (cat ? .19 : 0)) % 1);
    final gazeY = mood == MascotMood.calendar || mood == MascotMood.insight
        ? -1.0
        : mood == MascotMood.focus
        ? 1.0
        : 0.0;
    final gazeX = mood == MascotMood.listening
        ? -1.3
        : mood == MascotMood.teamwork
        ? 1.0
        : 0.0;
    for (final eyeX in [-6.5, 6.5]) {
      final wink = waving && mood == MascotMood.teamwork && eyeX > 0;
      if (blink || wink) {
        canvas.drawLine(
          Offset(eyeX - 2.7, -17),
          Offset(eyeX + 2.7, -17),
          stroke,
        );
      } else {
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(eyeX + gazeX, -17 + gazeY),
            width: 5.1,
            height: mood == MascotMood.focus ? 4.8 : 7.0,
          ),
          ink,
        );
        canvas.drawCircle(
          Offset(eyeX - 1.1 + gazeX, -19 + gazeY),
          1.1,
          Paint()..color = Colors.white,
        );
      }
    }
    if (cat) {
      for (final side in [-1.0, 1.0]) {
        canvas.drawLine(
          Offset(side * 9, -8),
          Offset(side * 18, -10),
          Paint()
            ..color = outline.withValues(alpha: .55)
            ..strokeWidth = .8,
        );
        canvas.drawLine(
          Offset(side * 9, -5),
          Offset(side * 18, -4),
          Paint()
            ..color = outline.withValues(alpha: .55)
            ..strokeWidth = .8,
        );
      }
    }
    final nose = Path()
      ..moveTo(-2, -9)
      ..quadraticBezierTo(0, -12, 2, -9)
      ..quadraticBezierTo(0, -6, -2, -9)
      ..close();
    canvas.drawPath(nose, ink);
    if (mood == MascotMood.listening || mood == MascotMood.reminder) {
      canvas.drawOval(
        const Rect.fromLTWH(-2, -7, 4, 5),
        Paint()..color = outline,
      );
    } else {
      canvas.drawArc(
        const Rect.fromLTWH(-4, -8, 8, 6),
        .1,
        math.pi - .2,
        false,
        stroke..strokeWidth = 1.3,
      );
    }
    if (cat && mood == MascotMood.teamwork) {
      canvas.drawCircle(
        const Offset(11, -27),
        2,
        Paint()..color = const Color(0xFFFF91B5),
      );
    }
    canvas.restore();
  }

  bool _blinkAt(double phase) {
    for (final center in [.16, .54, .87]) {
      if ((phase - center).abs() < .018) return true;
    }
    return false;
  }

  void _moodSparkles(Canvas canvas) {
    final color = mood.accent;
    final twinkle = .65 + math.sin(progress * math.pi * 8) * .25;
    for (final point in [
      const Offset(12, 24),
      const Offset(85, 22),
      const Offset(50, 9),
    ]) {
      final radius = point.dx == 50 ? 2.3 : 1.8;
      canvas.drawCircle(
        point,
        radius * twinkle,
        Paint()..color = color.withValues(alpha: .72),
      );
    }
    if (mood == MascotMood.celebration || reacting) {
      final heart = Path()
        ..moveTo(50, 29)
        ..cubicTo(45, 24, 40, 31, 50, 37)
        ..cubicTo(60, 31, 55, 24, 50, 29)
        ..close();
      canvas.drawPath(heart, Paint()..color = const Color(0xFFFF91B5));
    }
    if (progress < .25) {
      canvas.drawLine(
        const Offset(5, 67),
        const Offset(14, 67),
        Paint()
          ..color = color.withValues(alpha: .5)
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PetDuoPainter oldDelegate) =>
      mood != oldDelegate.mood ||
      progress != oldDelegate.progress ||
      reacting != oldDelegate.reacting;
}

class MascotBanner extends StatelessWidget {
  final MascotMood mood;
  final String title;
  final String message;
  final double mascotSize;
  final VoidCallback? onTap;

  const MascotBanner({
    super.key,
    required this.mood,
    required this.title,
    required this.message,
    this.mascotSize = 58,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final companionSize = math.max(76.0, mascotSize);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: mood.backdrop,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: mood.accent.withValues(alpha: .16)),
      ),
      child: Row(
        children: [
          TaskHubMascot(mood: mood, size: companionSize, onTap: onTap),
          const SizedBox(width: 12),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, .08),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: Column(
                key: ValueKey('$title$message'),
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: mood.accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF6F6680),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

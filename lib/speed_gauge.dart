import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'core/speed_limit.dart';

/// Radarbot-style speed ring: a 270° arc open at the bottom that fills as
/// the speed rises, with the speed and "km/h" in the centre.
///
/// With a known limit the scale is relative to it (the limit sits at 75 % of
/// the arc, marked with a tick, plus a thinner tick at the fine threshold),
/// so the ring reads the same in town and on the motorway. Without a limit
/// the scale is a fixed 0–160 km/h.
class SpeedGauge extends StatelessWidget {
  const SpeedGauge({
    super.key,
    required this.speed,
    required this.limit,
    required this.color,
    this.size = 240,
  });

  final double? speed;
  final int? limit;
  final Color color;
  final double size;

  static const double limitFraction = 0.75;
  static const double defaultMax = 160;

  static double scaleMax(int? limit) => limit == null || limit <= 0
      ? defaultMax
      : math.max(limit / limitFraction, 40);

  static double fraction(double? speed, int? limit) {
    if (speed == null || speed <= 0) return 0;
    return (speed / scaleMax(limit)).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = speed?.round();
    final max = scaleMax(limit);
    return Semantics(
      label: shown == null ? '— km/h' : '$shown km/h',
      child: SizedBox.square(
        dimension: size,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: fraction(speed, limit)),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
          builder: (context, value, _) => TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: color),
            duration: const Duration(milliseconds: 400),
            builder: (context, animatedColor, _) => CustomPaint(
              painter: _GaugePainter(
                fraction: value,
                color: animatedColor ?? color,
                track: scheme.onSurface.withValues(alpha: 0.12),
                tickColor: scheme.onSurface,
                limitFraction: limit == null ? null : limitFraction,
                fineFraction: limit == null || limit! <= 0
                    ? null
                    : (SpeedLimit.fineThreshold(limit!) / max).clamp(0.0, 1.0),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      child: Text(
                        shown?.toString() ?? '—',
                        style: TextStyle(
                          fontSize: size * 0.33,
                          height: 1,
                          fontWeight: FontWeight.bold,
                          color: speed == null ? scheme.onSurface : color,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    Text(
                      'km/h',
                      style: TextStyle(
                        fontSize: size * 0.085,
                        color: scheme.onSurfaceVariant,
                      ),
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
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.fraction,
    required this.color,
    required this.track,
    required this.tickColor,
    this.limitFraction,
    this.fineFraction,
  });

  final double fraction;
  final Color color;
  final Color track;
  final Color tickColor;
  final double? limitFraction;
  final double? fineFraction;

  static const double start = math.pi * 0.75; // bottom-left
  static const double sweep = math.pi * 1.5; // 270°

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.07;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.width / 2 - stroke,
    );
    Paint arc(Color c, [double? width]) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = width ?? stroke
      ..color = c;

    canvas.drawArc(rect, start, sweep, false, arc(track));
    if (fraction > 0.001) {
      final glow = arc(color.withValues(alpha: 0.35), stroke * 1.6)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, stroke * 0.6);
      canvas.drawArc(rect, start, sweep * fraction, false, glow);
      canvas.drawArc(rect, start, sweep * fraction, false, arc(color));
    }
    void tick(double f, double length, double width) {
      final angle = start + sweep * f;
      final dir = Offset(math.cos(angle), math.sin(angle));
      final r = rect.width / 2;
      final c = rect.center;
      canvas.drawLine(
        c + dir * (r - stroke / 2 - length / 2),
        c + dir * (r + stroke / 2 + length / 2),
        Paint()
          ..color = tickColor
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round,
      );
    }

    if (fineFraction != null && fineFraction! < 1) {
      tick(fineFraction!, stroke * 0.2, stroke * 0.12);
    }
    if (limitFraction != null) tick(limitFraction!, stroke * 0.6, stroke * 0.22);
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.fraction != fraction ||
      old.color != color ||
      old.track != track ||
      old.tickColor != tickColor ||
      old.limitFraction != limitFraction ||
      old.fineFraction != fineFraction;
}

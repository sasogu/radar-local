import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_local/speed_gauge.dart';

void main() {
  test('limit sits at 75 % of the ring', () {
    expect(SpeedGauge.fraction(120, 120), closeTo(0.75, 1e-9));
    expect(SpeedGauge.fraction(50, 50), closeTo(0.75, 1e-9));
    expect(SpeedGauge.fraction(80, null), closeTo(0.5, 1e-9));
  });

  test('fraction is clamped and empty without speed', () {
    expect(SpeedGauge.fraction(null, 90), 0);
    expect(SpeedGauge.fraction(-3, 90), 0);
    expect(SpeedGauge.fraction(400, 90), 1);
  });

  testWidgets('shows rounded speed and unit', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SpeedGauge(speed: 87.6, limit: 90, color: Colors.green),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('88'), findsOneWidget);
    expect(find.text('km/h'), findsOneWidget);
  });
}

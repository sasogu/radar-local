import 'package:flutter_test/flutter_test.dart';
import 'package:radar_local/core/speed_limit.dart';

void main() {
  test('fine thresholds follow the 7 km/h and 7 percent rule', () {
    expect(SpeedLimit.fineThreshold(50), 57);
    expect(SpeedLimit.fineThreshold(90), 97);
    expect(SpeedLimit.fineThreshold(100), 107);
    expect(SpeedLimit.fineThreshold(110), 118);
    expect(SpeedLimit.fineThreshold(120), 129);
  });
  test('classifies speed into within, tolerance and fine zones', () {
    expect(SpeedLimit.zone(50, 50), SpeedZone.within);
    expect(SpeedLimit.zone(51, 50), SpeedZone.tolerance);
    expect(SpeedLimit.zone(56, 50), SpeedZone.tolerance);
    expect(SpeedLimit.zone(57, 50), SpeedZone.fine);
    expect(SpeedLimit.zone(128, 120), SpeedZone.tolerance);
    expect(SpeedLimit.zone(129, 120), SpeedZone.fine);
  });
  test('rejects invalid limits', () {
    expect(() => SpeedLimit.fineThreshold(0), throwsArgumentError);
  });
}

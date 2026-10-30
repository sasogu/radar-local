enum SpeedZone { within, tolerance, fine }

class SpeedLimit {
  const SpeedLimit._();

  static int fineThreshold(int limit) {
    if (limit <= 0) throw ArgumentError.value(limit, 'limit');
    return limit < 100 ? limit + 7 : (limit * 107 + 99) ~/ 100;
  }

  static SpeedZone zone(int speed, int limit) {
    if (speed <= limit) return SpeedZone.within;
    if (speed >= fineThreshold(limit)) return SpeedZone.fine;
    return SpeedZone.tolerance;
  }
}

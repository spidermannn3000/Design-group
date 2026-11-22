import 'route.dart';

/// LED symbol IDs shared by the phone and the front module (task N6).
///
/// These numbers are sent over Bluetooth LE (S4) and must match the byte
/// arrays in the front module firmware (F2). Keep docs/navigation.md in sync.
abstract final class LedSymbol {
  static const int blank = 0;
  static const int straight = 1;
  static const int left = 2;
  static const int right = 3;
  static const int slightLeft = 4;
  static const int slightRight = 5;
  static const int sharpLeft = 6;
  static const int sharpRight = 7;
  static const int uTurn = 8;
  static const int roundabout = 9;
  static const int arrive = 10;
  static const int rerouting = 11;
  static const int bluetoothLost = 12;
  static const int lowBattery = 13;

  /// Digits 1-9 for roundabout exit numbers are 21-29.
  static const int exitDigitBase = 20;

  static int exitDigit(int exit) => exitDigitBase + exit.clamp(1, 9);
}

int symbolFor(ManoeuvreKind kind) => switch (kind) {
      ManoeuvreKind.straight => LedSymbol.straight,
      ManoeuvreKind.left => LedSymbol.left,
      ManoeuvreKind.right => LedSymbol.right,
      ManoeuvreKind.slightLeft => LedSymbol.slightLeft,
      ManoeuvreKind.slightRight => LedSymbol.slightRight,
      ManoeuvreKind.sharpLeft => LedSymbol.sharpLeft,
      ManoeuvreKind.sharpRight => LedSymbol.sharpRight,
      ManoeuvreKind.uTurn => LedSymbol.uTurn,
      ManoeuvreKind.roundabout => LedSymbol.roundabout,
      ManoeuvreKind.arrive => LedSymbol.arrive,
    };

/// The symbols the front module should cycle through for one manoeuvre.
/// A roundabout shows the roundabout symbol then the exit number (F4).
List<int> displaySequence(Manoeuvre m) => [
      symbolFor(m.kind),
      if (m.kind == ManoeuvreKind.roundabout && m.exitNumber != null)
        LedSymbol.exitDigit(m.exitNumber!),
    ];

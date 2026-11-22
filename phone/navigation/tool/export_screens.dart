// Writes many navigation states two ways, for checking the front-module
// firmware against the phone (front-module/test_native/check.sh):
//   <dir>/packets.txt  "name hexpacket" per line (what the phone sends)
//   <dir>/dart.txt     each screen as text art (what the phone shows)
import 'dart:io';

import 'package:bike_navigation/bike_navigation.dart';

Manoeuvre _m(ManoeuvreKind k, [int? exit]) =>
    Manoeuvre(kind: k, instruction: '', pointIndex: 0, alongM: 0, exitNumber: exit);

NavState _state(Manoeuvre next, double distance,
    {Manoeuvre? then, bool show = true, bool flash = false}) {
  return NavState(
    next: next,
    then: show ? then : null,
    distanceToNextM: distance,
    showTurn: show,
    symbols: show
        ? [...displaySequence(next), if (then != null) ...displaySequence(then)]
        : const [LedSymbol.straight],
    offRoute: false,
    arrived: false,
    flash: flash,
    alongM: 0,
    offsetM: 0,
  );
}

void main(List<String> args) {
  final dir = Directory(args.isEmpty ? 'screens_out' : args.first)..createSync(recursive: true);
  final states = <String, NavState?>{};
  const distances = <double>[0, 3, 4.6, 5, 47, 99, 99.5, 100, 104, 105, 123, 994, 995, 996, 2340, 2350, 9949, 9950, 12400, 65000];
  for (final k in ManoeuvreKind.values) {
    for (final d in distances) {
      states['${k.name}_${d}m'] = _state(_m(k), d);
      states['${k.name}_${d}m_hidden'] = _state(_m(k), d, show: false);
    }
  }
  for (var exit = 1; exit <= 9; exit++) {
    states['roundabout_exit$exit'] = _state(_m(ManoeuvreKind.roundabout, exit), 80);
  }
  for (final a in ManoeuvreKind.values) {
    for (final b in ManoeuvreKind.values) {
      if (b == ManoeuvreKind.arrive) continue;
      states['${a.name}_then_${b.name}'] =
          _state(_m(a, a == ManoeuvreKind.roundabout ? 2 : null), 30, then: _m(b, b == ManoeuvreKind.roundabout ? 3 : null));
    }
  }
  states['flashing_right'] = _state(_m(ManoeuvreKind.right), 4, flash: true);
  states['arrived'] = NavState(next: null, distanceToNextM: 0, showTurn: false, symbols: const [LedSymbol.arrive], offRoute: false, arrived: true, alongM: 0, offsetM: 0);
  states['rerouting'] = NavState(next: _m(ManoeuvreKind.left), distanceToNextM: 50, showTurn: true, symbols: const [LedSymbol.rerouting], offRoute: true, arrived: false, alongM: 0, offsetM: 0);
  states['blank'] = null;

  final packets = StringBuffer(), art = StringBuffer();
  for (final e in states.entries) {
    final hex = encodeNavPacket(e.value).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    packets.writeln('${e.key} $hex');
    final frame = e.value == null ? OledFrame() : renderOled(e.value!);
    art.writeln('== ${e.key}\n${frame.toAscii()}');
  }
  File('${dir.path}/packets.txt').writeAsStringSync(packets.toString());
  File('${dir.path}/dart.txt').writeAsStringSync(art.toString());
  print('${states.length} screens written to ${dir.path}');
}

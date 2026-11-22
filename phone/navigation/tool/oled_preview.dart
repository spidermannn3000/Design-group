// Prints every screen as text art, and writes PBM images for the docs.
//   dart run tool/oled_preview.dart [output_dir]
import 'dart:io';

import 'package:bike_navigation/bike_navigation.dart';

NavState state(ManoeuvreKind kind, double distance,
    {int? exit, ManoeuvreKind? then, bool show = true, bool arrived = false, bool offRoute = false}) {
  Manoeuvre m(ManoeuvreKind k) =>
      Manoeuvre(kind: k, instruction: '', pointIndex: 0, alongM: 0, exitNumber: k == kind ? exit : null);
  return NavState(
    next: m(kind),
    then: then == null ? null : m(then),
    distanceToNextM: distance,
    showTurn: show,
    symbols: const [],
    offRoute: offRoute,
    arrived: arrived,
    alongM: 0,
    offsetM: 0,
  );
}

final screens = <String, NavState>{
  'straight_far': state(ManoeuvreKind.right, 850, show: false),
  'slight_left': state(ManoeuvreKind.slightLeft, 120),
  'left': state(ManoeuvreKind.left, 80),
  'sharp_left': state(ManoeuvreKind.sharpLeft, 40),
  'slight_right': state(ManoeuvreKind.slightRight, 100),
  'right': state(ManoeuvreKind.right, 60),
  'sharp_right': state(ManoeuvreKind.sharpRight, 5),
  'u_turn': state(ManoeuvreKind.uTurn, 30),
  'roundabout_exit_2': state(ManoeuvreKind.roundabout, 90, exit: 2),
  'left_then_right': state(ManoeuvreKind.left, 70, then: ManoeuvreKind.right),
  'long_distance': state(ManoeuvreKind.left, 2340),
  'arrived': state(ManoeuvreKind.arrive, 0, arrived: true),
  'rerouting': state(ManoeuvreKind.left, 0, offRoute: true),
};

void main(List<String> args) {
  final out = args.isEmpty ? null : (Directory(args.first)..createSync(recursive: true));
  for (final e in screens.entries) {
    final frame = renderOled(e.value);
    print('== ${e.key}\n${frame.toAscii()}\n');
    if (out != null) {
      final rows = frame.toAscii().split('\n').map((r) => r.split('').map((c) => c == '#' ? '1' : '0').join(' '));
      File('${out.path}/${e.key}.pbm').writeAsStringSync('P1\n128 64\n${rows.join('\n')}\n');
    }
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:bike_app/screens/ride_screen.dart';
import 'package:bike_app/services/front_module.dart';
import 'package:bike_app/services/place_search.dart';
import 'package:bike_app/widgets/led_matrix.dart';
import 'package:bike_navigation/bike_navigation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

NavRoute dublinRoute() => parseOrsGeoJson(jsonDecode(File(
            '../navigation/test/fixtures/dublin_trinity_to_st_patricks.json')
        .readAsStringSync()) as Map<String, dynamic>);

void main() {
  test('every LED symbol ID has a valid 8x8 bitmap', () {
    final ids = [
      for (var i = 0; i <= 13; i++) i,
      for (var d = 1; d <= 9; d++) LedSymbol.exitDigit(d),
    ];
    for (final id in ids) {
      final rows = ledBitmaps[id];
      expect(rows, isNotNull, reason: 'symbol $id');
      expect(rows!.length, 8, reason: 'symbol $id');
      for (final r in rows) {
        expect(r, matches(RegExp(r'^[.#]{8}$')), reason: 'symbol $id');
      }
    }
  });

  test('parses place search results', () {
    final places = parsePlaces({
      'features': [
        {
          'geometry': {'coordinates': [-6.2546, 53.3438]},
          'properties': {'label': 'Trinity College, Dublin'},
        },
      ],
    });
    expect(places.single.label, 'Trinity College, Dublin');
    expect(places.single.position.lat, 53.3438);
  });

  testWidgets('simulated ride on the Dublin route reaches the destination',
      (tester) async {
    final route = dublinRoute();
    final module = PreviewFrontModule();
    final sent = <List<int>>[];
    module.lastSent.addListener(() => sent.add(module.lastSent.value!.$1));

    await tester.pumpWidget(MaterialApp(
      home: RideScreen(
        start: route.line.points.first,
        destination: route.line.points.last,
        destinationLabel: "St Patrick's Cathedral",
        routeProvider: (a, b) async => route,
        frontModule: module,
        simulate: true,
        simulationInterval: const Duration(milliseconds: 10),
        showMap: false,
      ),
    ));
    await tester.pump();
    expect(find.textContaining('m'), findsWidgets);

    // About 340 simulated GPS fixes, 10 ms apart.
    for (var i = 0; i < 400; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(find.text('You have arrived'), findsOneWidget);
    expect(sent, contains(equals([LedSymbol.left, LedSymbol.right])),
        reason: 'the close left-then-right pair at Parliament Square');
    expect(sent.last, [LedSymbol.arrive]);

    // Leaving the screen blanks the matrix.
    await tester.pumpWidget(const SizedBox());
    expect(module.lastSent.value!.$1, [LedSymbol.blank]);
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:bike_app/screens/ride_screen.dart';
import 'package:bike_app/services/front_module.dart';
import 'package:bike_app/services/place_search.dart';
import 'package:bike_app/widgets/oled_display.dart';
import 'package:bike_navigation/bike_navigation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

NavRoute dublinRoute() => parseOrsGeoJson(jsonDecode(File(
            '../navigation/test/fixtures/dublin_trinity_to_st_patricks.json')
        .readAsStringSync()) as Map<String, dynamic>);

void main() {
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
    var flashed = false;
    module.lastSent.addListener(() {
      final s = module.lastSent.value;
      if (s == null) return;
      sent.add(s.symbols);
      flashed |= s.flash;
    });

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
    expect(find.byType(OledDisplay), findsOneWidget);

    // About 340 simulated GPS fixes, 10 ms apart.
    for (var i = 0; i < 400; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(find.text('You have arrived'), findsOneWidget);
    expect(sent, contains(equals([LedSymbol.left, LedSymbol.right])),
        reason: 'the close left-then-right pair at Parliament Square');
    expect(sent.last, [LedSymbol.arrive]);
    expect(flashed, isTrue, reason: 'the display flashes at each turn');

    // Leaving the screen blanks the matrix.
    await tester.pumpWidget(const SizedBox());
    expect(module.lastSent.value, isNull);
  });
}

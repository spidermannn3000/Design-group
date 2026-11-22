# bike_navigation

Turn-by-turn cycling navigation for the phone app (tasks N1 to N7). This code runs **on the phone**, inside the Flutter app. It is plain Dart, so it can also be tested on a laptop.

Design notes, the provider comparison and the LED symbol table are in [`docs/navigation.md`](../../docs/navigation.md).

| File | Task | What it does |
|------|------|--------------|
| `lib/src/ors_client.dart` | N1, N2 | Requests a cycling route from OpenRouteService and converts its steps into manoeuvres |
| `lib/src/engine.dart` | N2, N3, N4, N5 | Takes each GPS fix and decides the next turn, whether to show it yet, and whether the rider is off-route |
| `lib/src/session.dart` | N5 | One ride: requests the route and reroutes when off-route |
| `lib/src/junctions.dart` | N4 | Finds side-road junctions from OpenStreetMap (Overpass API) |
| `lib/src/symbols.dart` | N6 | Manoeuvre to LED symbol ID table |
| `lib/src/replay.dart`, `bin/replay.dart` | N7 | Replays a GPX track or a simulated ride |
| `lib/src/geo.dart` | | Distances and snapping a GPS fix onto the route |

## Using it from the Flutter app

In the app's `pubspec.yaml`:

```yaml
dependencies:
  bike_navigation:
    path: navigation   # or ../phone/navigation, depending on where the app lives
```

```dart
import 'package:bike_navigation/bike_navigation.dart';
import 'package:geolocator/geolocator.dart';

final ors = OrsClient(apiKey: const String.fromEnvironment('ORS_API_KEY'));

Future<void> startRide(LatLng destination) async {
  final here = await Geolocator.getCurrentPosition();
  final session = NavigationSession(
    routeProvider: ors.route,
    destination: destination,
    config: const NavConfig(mode: TriggerMode.distance), // or always / junction
    prepareRoute: (route) => addJunctions(route),        // needed for junction mode only
  );
  await session.start(LatLng(here.latitude, here.longitude));

  Geolocator.getPositionStream(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 2),
  ).listen((p) async {
    final state = await session.onPosition(LatLng(p.latitude, p.longitude), accuracyM: p.accuracy);
    // P5: send state.symbols (and state.distanceToNextM) to the front module over BLE.
    // UI: show state.next?.instruction and state.distanceToNextM.
  });
}
```

Run with `flutter run --dart-define=ORS_API_KEY=your_key`. Never commit the key.

## Tests

```
dart pub get
dart test
dart run bin/replay.dart --route test/fixtures/ors_sample.json
```

# Bike Nav (phone app)

The Android app for the bike. It runs **on the phone**. Built with Flutter 3.50.

What it does now:
- **Destination entry (P3):** search for a place in Ireland or long-press the map, then see the cycling route, its distance and its time.
- **Display level:** choose Level 1, 2 or 3 (see `docs/navigation.md`).
- **Ride screen:** turn-by-turn navigation from GPS, with automatic rerouting. A preview shows exactly what the handlebar OLED screen would show, including the flash when a turn is 5 m away.
- **Simulate:** rides the route automatically at 4x speed, so you can test indoors.

Navigation logic lives in the separate package `../navigation`. This app only adds the screens, GPS and the map.

Not done yet:
- **P4/P5:** the Bluetooth link to the front module. `lib/services/front_module.dart` defines the interface, and `PreviewFrontModule` shows on screen what would be sent until the S4 message format is agreed.
- **P6:** keeping navigation running with the screen off.
- **P2:** the wireframes. The current layout is functional, not designed.

## Keys

Keys are never committed.

| Key | Used for | Where it goes |
|-----|----------|---------------|
| OpenRouteService | Routes and place search | `flutter run --dart-define=ORS_API_KEY=...` |
| Google Maps (Android) | Drawing the map | `android/local.properties`: `MAPS_API_KEY=...` |

Without a Google Maps key the app still works, but the map is blank.

## Run it

You need Flutter 3.50 or newer and an Android phone with USB debugging on, or the Android emulator.

```bash
cd phone/app
flutter pub get
flutter run --dart-define=ORS_API_KEY=your_key
```

To build an APK to share:

```bash
flutter build apk --dart-define=ORS_API_KEY=your_key
```

The APK ends up in `build/app/outputs/flutter-apk/app-release.apk`.

## Files

| File | What it is |
|------|------------|
| `lib/screens/destination_screen.dart` | Search, route preview, level choice |
| `lib/screens/ride_screen.dart` | Navigation during a ride |
| `lib/widgets/oled_display.dart` | Pixel-exact preview of the 128x64 handlebar OLED |
| `lib/widgets/route_map.dart` | Google map with the route |
| `lib/services/place_search.dart` | Place search (OpenRouteService) |
| `lib/services/location.dart` | Location permission and GPS stream |
| `lib/services/front_module.dart` | Link to the handlebar module (P4/P5 go here) |

## Tests

```bash
flutter test
```

This includes a simulated ride on a real Dublin route, from Trinity College to St Patrick's Cathedral.

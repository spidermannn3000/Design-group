import 'package:bike_navigation/bike_navigation.dart';

/// Keys are passed in at build time and never committed:
///
///   flutter run --dart-define=ORS_API_KEY=your_openrouteservice_key
///
/// The Google Maps key goes in android/local.properties as MAPS_API_KEY=...
const orsApiKey = String.fromEnvironment('ORS_API_KEY');

/// Used when location permission is refused or GPS has no fix yet.
const trinityCollege = LatLng(53.3438, -6.2546);

/// Simulated rides play back this many times faster than real time.
const simulationSpeedUp = 4;

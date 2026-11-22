import 'package:bike_navigation/bike_navigation.dart';
import 'package:geolocator/geolocator.dart';

/// Asks for location permission and returns the current position, or null
/// if location is off or permission is refused.
Future<LatLng?> currentLocation() async {
  if (!await Geolocator.isLocationServiceEnabled()) return null;
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    return null;
  }
  final p = await Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
  );
  return LatLng(p.latitude, p.longitude);
}

/// GPS fixes during a ride, every couple of metres.
Stream<Fix> gpsFixes() => Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 2,
      ),
    ).map((p) => Fix(LatLng(p.latitude, p.longitude), p.timestamp,
        accuracyM: p.accuracy));

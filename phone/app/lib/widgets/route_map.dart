import 'package:bike_navigation/bike_navigation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:material_ui/material_ui.dart';

gm.LatLng toGm(LatLng p) => gm.LatLng(p.lat, p.lng);

/// Google map showing the route, the destination and the rider.
/// Long-press sets a destination when [onLongPress] is given.
class RouteMap extends StatefulWidget {
  final LatLng center;
  final NavRoute? route;
  final LatLng? destination;
  final LatLng? rider;
  final bool follow;
  final void Function(LatLng)? onLongPress;

  const RouteMap({
    super.key,
    required this.center,
    this.route,
    this.destination,
    this.rider,
    this.follow = false,
    this.onLongPress,
  });

  @override
  State<RouteMap> createState() => _RouteMapState();
}

class _RouteMapState extends State<RouteMap> {
  gm.GoogleMapController? _controller;

  @override
  void didUpdateWidget(RouteMap old) {
    super.didUpdateWidget(old);
    final c = _controller;
    if (c == null) return;
    if (widget.follow && widget.rider != null) {
      c.animateCamera(gm.CameraUpdate.newLatLng(toGm(widget.rider!)));
    } else if (widget.route != null && widget.route != old.route) {
      c.animateCamera(gm.CameraUpdate.newLatLngBounds(_bounds(widget.route!), 48));
    }
  }

  gm.LatLngBounds _bounds(NavRoute r) {
    final pts = r.line.points;
    var s = pts.first.lat, n = s, w = pts.first.lng, e = w;
    for (final p in pts) {
      if (p.lat < s) s = p.lat;
      if (p.lat > n) n = p.lat;
      if (p.lng < w) w = p.lng;
      if (p.lng > e) e = p.lng;
    }
    return gm.LatLngBounds(southwest: gm.LatLng(s, w), northeast: gm.LatLng(n, e));
  }

  @override
  Widget build(BuildContext context) {
    return gm.GoogleMap(
      initialCameraPosition: gm.CameraPosition(target: toGm(widget.center), zoom: 15),
      onMapCreated: (c) => _controller = c,
      myLocationEnabled: widget.rider == null,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      onLongPress: widget.onLongPress == null
          ? null
          : (p) => widget.onLongPress!(LatLng(p.latitude, p.longitude)),
      polylines: {
        if (widget.route != null)
          gm.Polyline(
            polylineId: const gm.PolylineId('route'),
            points: widget.route!.line.points.map(toGm).toList(),
            color: const Color(0xFF1565C0),
            width: 6,
          ),
      },
      markers: {
        if (widget.destination != null)
          gm.Marker(markerId: const gm.MarkerId('destination'), position: toGm(widget.destination!)),
        if (widget.rider != null)
          gm.Marker(
            markerId: const gm.MarkerId('rider'),
            position: toGm(widget.rider!),
            icon: gm.BitmapDescriptor.defaultMarkerWithHue(gm.BitmapDescriptor.hueAzure),
          ),
      },
    );
  }
}

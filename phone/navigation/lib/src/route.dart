import 'geo.dart';

/// Provider-independent manoeuvre types. Each routing provider's own types
/// are mapped onto these (see ors_client.dart), and these map onto LED
/// symbols (see symbols.dart), so changing provider only touches one file.
enum ManoeuvreKind {
  straight,
  left,
  right,
  slightLeft,
  slightRight,
  sharpLeft,
  sharpRight,
  uTurn,
  roundabout,
  arrive,
}

class Manoeuvre {
  final ManoeuvreKind kind;

  /// Roundabout exit number (1 = first exit), when the provider gives it.
  final int? exitNumber;

  /// Human-readable instruction from the provider, e.g. "Turn right onto Nassau Street".
  final String instruction;

  /// Index into the route polyline where the manoeuvre happens.
  final int pointIndex;

  /// Distance from the start of the route to the manoeuvre (metres).
  final double alongM;

  /// Distance along the route of the last junction before this manoeuvre
  /// (task N4). Null until junctions are attached, or if there is none.
  double? junctionAlongM;

  Manoeuvre({
    required this.kind,
    required this.instruction,
    required this.pointIndex,
    required this.alongM,
    this.exitNumber,
    this.junctionAlongM,
  });

  @override
  String toString() =>
      '${kind.name}${exitNumber != null ? ' exit $exitNumber' : ''} at ${alongM.round()} m: $instruction';
}

class NavRoute {
  final Polyline line;
  final List<Manoeuvre> manoeuvres;
  final double durationS;

  NavRoute(this.line, this.manoeuvres, {this.durationS = 0});

  double get distanceM => line.lengthM;
}

/// Anything that can produce a route: the ORS client, a saved file, a test stub.
typedef RouteProvider = Future<NavRoute> Function(LatLng from, LatLng to);

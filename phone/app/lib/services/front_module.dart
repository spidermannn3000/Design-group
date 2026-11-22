import 'package:flutter/foundation.dart';

/// The link to the handlebar LED module.
///
/// P4 (Bluetooth LE scan, pair, reconnect) and P5 (send symbols) will
/// implement this once the message format (S4) is agreed. Until then the app
/// uses [PreviewFrontModule], which shows on screen what would be sent.
abstract class FrontModule {
  /// Whether the module is connected.
  ValueListenable<bool> get connected;

  /// Sends the symbols to show (in display order) and the distance to the
  /// turn in metres.
  Future<void> showNavigation(List<int> symbols, int distanceM);
}

class PreviewFrontModule implements FrontModule {
  @override
  final ValueNotifier<bool> connected = ValueNotifier(false);

  /// The last message, for the on-screen preview.
  final ValueNotifier<(List<int>, int)?> lastSent = ValueNotifier(null);

  @override
  Future<void> showNavigation(List<int> symbols, int distanceM) async {
    lastSent.value = (symbols, distanceM);
  }
}

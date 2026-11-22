import 'package:bike_navigation/bike_navigation.dart';
import 'package:flutter/foundation.dart';

/// The link to the handlebar module (0.96" SSD1306 OLED on an ESP32).
///
/// P4 (Bluetooth LE scan, pair, reconnect) and P5 (send navigation) will
/// implement this once the message format (S4) is agreed. The module needs:
/// the symbol IDs, the distance to the turn, and whether to flash. It then
/// draws the screen itself with the same layout as `renderOled`. Until then
/// the app uses [PreviewFrontModule], which shows on screen what would be sent.
abstract class FrontModule {
  /// Whether the module is connected.
  ValueListenable<bool> get connected;

  /// Sends the current navigation state, or null to clear the screen.
  Future<void> showNavigation(NavState? state);
}

class PreviewFrontModule implements FrontModule {
  @override
  final ValueNotifier<bool> connected = ValueNotifier(false);

  /// The last state sent, for the on-screen preview.
  final ValueNotifier<NavState?> lastSent = ValueNotifier(null);

  @override
  Future<void> showNavigation(NavState? state) async {
    lastSent.value = state;
  }
}

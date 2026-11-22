import 'dart:typed_data';

import 'engine.dart';

/// DRAFT Bluetooth LE message from the phone to the front module (part of
/// S4; agree it with the F team before relying on it).
///
/// The front module is a BLE peripheral advertising [frontServiceUuid]. The
/// phone writes each navigation update to [navCharacteristicUuid]:
///
/// | Byte | Meaning |
/// |------|---------|
/// | 0 | Version, currently 1 |
/// | 1 | Flags: bit 0 = flash (turn is 5 m away), bit 1 = arrived |
/// | 2-3 | Distance to the turn in metres, little-endian; 0xFFFF = none |
/// | 4 | Number of symbol IDs that follow, 0-4 (0 = blank screen) |
/// | 5.. | Symbol IDs (see symbols.dart), e.g. [9, 22] = roundabout, exit 2 |
///
/// The module draws the screen itself from this (front-module/src/screen.cpp
/// draws exactly what [renderOled] draws).
const frontServiceUuid = '6e3b0001-8f7a-4c1e-9b52-2d1c0b7a1f10';
const navCharacteristicUuid = '6e3b0002-8f7a-4c1e-9b52-2d1c0b7a1f10';

const navProtocolVersion = 1;

Uint8List encodeNavPacket(NavState? s) {
  if (s == null) return Uint8List.fromList([navProtocolVersion, 0, 0xFF, 0xFF, 0]);
  final symbols = s.symbols.take(4).toList();
  final distance = s.next == null || s.offRoute || s.arrived
      ? 0xFFFF
      : s.distanceToNextM.round().clamp(0, 0xFFFE);
  return Uint8List.fromList([
    navProtocolVersion,
    (s.flash ? 1 : 0) | (s.arrived ? 2 : 0),
    distance & 0xFF,
    distance >> 8,
    symbols.length,
    ...symbols,
  ]);
}

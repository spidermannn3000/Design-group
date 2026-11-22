// Handlebar screen for the 0.96" 128x64 SSD1306 OLED.
//
// Draws exactly what the phone app's preview shows (renderOled in
// phone/navigation/lib/src/oled.dart). Plain C++ with no Arduino
// dependencies, so it can be checked on a laptop against the Dart version
// (see test_native/).
#pragma once

#include <stddef.h>
#include <stdint.h>

namespace screen {

constexpr int kWidth = 128;
constexpr int kHeight = 64;

// Symbol IDs, shared with the phone (phone/navigation/lib/src/symbols.dart).
enum Symbol : uint8_t {
  kBlank = 0,
  kStraight = 1,
  kLeft = 2,
  kRight = 3,
  kSlightLeft = 4,
  kSlightRight = 5,
  kSharpLeft = 6,
  kSharpRight = 7,
  kUTurn = 8,
  kRoundabout = 9,
  kArrive = 10,
  kRerouting = 11,
  kBluetoothLost = 12,
  kLowBattery = 13,
  kExitDigitBase = 20,  // 21-29 = roundabout exit 1-9
};

// Anything that can light a pixel: the SSD1306 driver on the ESP32, or a
// plain buffer in the laptop test.
class Canvas {
 public:
  virtual ~Canvas() {}
  virtual void set(int x, int y) = 0;
};

// One navigation update from the phone (DRAFT protocol v1, see
// phone/navigation/lib/src/protocol.dart).
struct NavMessage {
  bool flash = false;      // turn is 5 m away: flash the screen
  bool arrived = false;
  uint16_t distanceM = 0xFFFF;  // 0xFFFF = no distance
  uint8_t count = 0;            // number of symbols, 0 = blank
  uint8_t symbols[4] = {0, 0, 0, 0};
};

constexpr uint16_t kNoDistance = 0xFFFF;
constexpr uint8_t kProtocolVersion = 1;

// Parses a message written by the phone. Returns false if it is malformed
// or from an unknown protocol version.
bool decode(const uint8_t* data, size_t len, NavMessage& out);

// Draws the navigation screen. The caller clears the display first and
// handles flashing (invert the display while msg.flash is set).
void draw(Canvas& c, const NavMessage& msg);

// Screens the module shows on its own.
void drawNoPhone(Canvas& c);        // Bluetooth lost
void drawWaiting(Canvas& c);        // powered on, waiting for the phone
void drawLowBattery(Canvas& c, int percent);

}  // namespace screen

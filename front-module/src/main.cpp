// Front module firmware: ESP32 + 0.96" 128x64 SSD1306 OLED (I2C).
//
// - Advertises over Bluetooth LE as "BikeNav Front" and receives navigation
//   updates from the phone (DRAFT protocol v1, see screen.h / protocol.dart).
// - Draws the turn arrow, distance and label (screen.cpp).
// - Flashes the screen when the turn is 5 m away by toggling the SSD1306's
//   invert mode, so nothing has to be redrawn.
// - Shows "NO PHONE" if the phone disconnects or goes quiet mid-ride.
// - For bench testing without the app, type messages into the serial
//   monitor (115200 baud), e.g. "2 80" = turn left in 80 m. Type "help".
//
// Wiring (ESP32 DevKit): OLED VCC -> 3V3, GND -> GND, SDA -> GPIO21,
// SCL -> GPIO22 (some boards label SCL as "SCK"). Address is usually 0x3C.

#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <Arduino.h>
#include <NimBLEDevice.h>
#include <Wire.h>

#include "screen.h"

namespace {

constexpr int kSdaPin = 21;
constexpr int kSclPin = 22;
constexpr uint8_t kOledAddress = 0x3C;

// Must match phone/navigation/lib/src/protocol.dart.
const char* kServiceUuid = "6e3b0001-8f7a-4c1e-9b52-2d1c0b7a1f10";
const char* kNavCharUuid = "6e3b0002-8f7a-4c1e-9b52-2d1c0b7a1f10";

constexpr uint32_t kFlashIntervalMs = 125;     // 4 flashes a second
constexpr uint32_t kPhoneTimeoutMs = 10000;    // no update for 10 s = lost

Adafruit_SSD1306 display(screen::kWidth, screen::kHeight, &Wire, -1);

// Lets screen.cpp draw into the Adafruit buffer.
class OledCanvas : public screen::Canvas {
 public:
  void set(int x, int y) override { display.drawPixel(x, y, SSD1306_WHITE); }
};
OledCanvas canvas;

// Shared between the BLE callback (BLE task) and loop().
portMUX_TYPE messageLock = portMUX_INITIALIZER_UNLOCKED;
screen::NavMessage pendingMessage;
volatile bool hasPendingMessage = false;
volatile bool phoneConnected = false;

screen::NavMessage current;
bool navigating = false;          // a ride from the phone is in progress
uint32_t lastUpdateMs = 0;
bool inverted = false;
uint32_t lastFlashMs = 0;

enum class Shown { kWaiting, kNavigation, kNoPhone };
Shown shown = Shown::kWaiting;

void queueMessage(const screen::NavMessage& m) {
  portENTER_CRITICAL(&messageLock);
  pendingMessage = m;
  hasPendingMessage = true;
  portEXIT_CRITICAL(&messageLock);
}

class NavCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* c, NimBLEConnInfo&) override {
    const NimBLEAttValue v = c->getValue();
    screen::NavMessage m;
    if (screen::decode(v.data(), v.length(), m)) {
      queueMessage(m);
    } else {
      Serial.printf("Ignored bad message (%u bytes)\n", (unsigned)v.length());
    }
  }
};

class ServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer*, NimBLEConnInfo&) override {
    phoneConnected = true;
    Serial.println("Phone connected");
  }
  void onDisconnect(NimBLEServer*, NimBLEConnInfo&, int reason) override {
    phoneConnected = false;
    Serial.printf("Phone disconnected (reason %d)\n", reason);
    NimBLEDevice::startAdvertising();
  }
};

void setInverted(bool on) {
  if (on != inverted) {
    display.invertDisplay(on);
    inverted = on;
  }
}

void showWaiting() {
  display.clearDisplay();
  screen::drawWaiting(canvas);
  display.display();
  setInverted(false);
  shown = Shown::kWaiting;
}

void showNoPhone() {
  display.clearDisplay();
  screen::drawNoPhone(canvas);
  display.display();
  setInverted(false);
  shown = Shown::kNoPhone;
}

// fromPhone: false for serial test messages, which never time out.
void showNavigation(const screen::NavMessage& m, bool fromPhone = false) {
  current = m;
  display.clearDisplay();
  screen::draw(canvas, m);
  display.display();
  if (!m.flash) setInverted(false);
  shown = Shown::kNavigation;
  navigating = fromPhone && m.count > 0 && !m.arrived;
  lastUpdateMs = millis();
}

void startBle() {
  NimBLEDevice::init("BikeNav Front");
  NimBLEServer* server = NimBLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());
  NimBLEService* service = server->createService(kServiceUuid);
  NimBLECharacteristic* nav = service->createCharacteristic(
      kNavCharUuid, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR);
  nav->setCallbacks(new NavCallbacks());
  NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
  adv->addServiceUUID(kServiceUuid);
  adv->setName("BikeNav Front");
  adv->start();
  Serial.println("Advertising as \"BikeNav Front\"");
}

// ---- serial test commands ----------------------------------------------------

void printHelp() {
  Serial.println(
      "Type: <symbols> <distance> [flash]   e.g.\n"
      "  2 80          turn left in 80 m\n"
      "  5 120         slight right in 120 m\n"
      "  7 4 flash     sharp right in 4 m, flashing\n"
      "  9,22 90       roundabout exit 2 in 90 m\n"
      "  2,3 60        left then right\n"
      "  arrived | reroute | nophone | battery 15 | clear | demo\n"
      "Symbols: 1 straight 2 left 3 right 4/5 slight L/R 6/7 sharp L/R 8 U-turn\n"
      "         9 roundabout (+21-29 exit) 10 destination");
}

void runDemo();

void handleSerialLine(String line) {
  line.trim();
  if (line.isEmpty()) return;
  screen::NavMessage m;
  if (line == "help") return printHelp();
  if (line == "demo") return runDemo();
  if (line == "nophone") return showNoPhone();
  if (line == "clear") return showNavigation(m);
  if (line == "arrived") {
    m.arrived = true;
    return showNavigation(m);
  }
  if (line == "reroute") {
    m.count = 1;
    m.symbols[0] = screen::kRerouting;
    return showNavigation(m);
  }
  if (line.startsWith("battery")) {
    display.clearDisplay();
    screen::drawLowBattery(canvas, line.substring(7).toInt());
    display.display();
    return;
  }
  // "<s1,s2,...> <distance> [flash]"
  const int space = line.indexOf(' ');
  const String syms = space < 0 ? line : line.substring(0, space);
  String rest = space < 0 ? "" : line.substring(space + 1);
  rest.trim();
  int start = 0;
  while (start < (int)syms.length() && m.count < 4) {
    int comma = syms.indexOf(',', start);
    if (comma < 0) comma = syms.length();
    m.symbols[m.count++] = (uint8_t)syms.substring(start, comma).toInt();
    start = comma + 1;
  }
  if (rest.length() > 0) m.distanceM = (uint16_t)rest.toInt();
  m.flash = rest.indexOf("flash") >= 0;
  showNavigation(m);
}

void pollSerial() {
  static String line;
  while (Serial.available()) {
    const char ch = (char)Serial.read();
    if (ch == '\n' || ch == '\r') {
      handleSerialLine(line);
      line = "";
    } else {
      line += ch;
    }
  }
}

// Steps through every screen, 2 s each.
void runDemo() {
  struct Step {
    uint8_t symbols[4];
    uint8_t count;
    uint16_t distance;
    bool flash;
  };
  const Step steps[] = {
      {{1}, 1, 850, false},  {{4}, 1, 120, false},     {{2}, 1, 80, false},
      {{6}, 1, 40, false},   {{5}, 1, 100, false},     {{3}, 1, 60, false},
      {{7}, 1, 4, true},     {{8}, 1, 30, false},      {{9, 22}, 2, 90, false},
      {{2, 3}, 2, 70, false}, {{2}, 1, 2340, false},   {{10}, 1, 50, false},
  };
  for (const Step& s : steps) {
    screen::NavMessage m;
    memcpy(m.symbols, s.symbols, sizeof m.symbols);
    m.count = s.count;
    m.distanceM = s.distance;
    m.flash = s.flash;
    showNavigation(m);
    const uint32_t until = millis() + 2000;
    while (millis() < until) {
      if (m.flash && millis() - lastFlashMs >= kFlashIntervalMs) {
        lastFlashMs = millis();
        setInverted(!inverted);
      }
      delay(5);
    }
  }
  screen::NavMessage done;
  done.arrived = true;
  showNavigation(done);
}

}  // namespace

void setup() {
  Serial.begin(115200);
  Wire.begin(kSdaPin, kSclPin);
  if (!display.begin(SSD1306_SWITCHCAPVCC, kOledAddress)) {
    Serial.println("OLED not found: check wiring and the I2C address (0x3C or 0x3D)");
  }
  display.setRotation(0);  // use 2 if the screen is mounted upside down
  showWaiting();
  startBle();
  printHelp();
}

void loop() {
  pollSerial();

  if (hasPendingMessage) {
    screen::NavMessage m;
    portENTER_CRITICAL(&messageLock);
    m = pendingMessage;
    hasPendingMessage = false;
    portEXIT_CRITICAL(&messageLock);
    showNavigation(m, /*fromPhone=*/true);
  }

  // Flash while the turn is 5 m away.
  if (shown == Shown::kNavigation && current.flash) {
    if (millis() - lastFlashMs >= kFlashIntervalMs) {
      lastFlashMs = millis();
      setInverted(!inverted);
    }
  }

  // Phone lost mid-ride: disconnected, or connected but silent. The next
  // message from the phone replaces this screen.
  if (navigating && shown != Shown::kNoPhone &&
      (!phoneConnected || millis() - lastUpdateMs > kPhoneTimeoutMs)) {
    showNoPhone();
  }

  delay(5);
}

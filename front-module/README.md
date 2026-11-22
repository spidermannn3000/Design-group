# Front module (handlebar display)

Firmware for the handlebar unit: an **ESP32** with a **0.96" 128x64 SSD1306 OLED** over I2C. It runs **on the ESP32**.

Buy the **Blue** or **White** version of the OLED. On the Yellow Blue version, the top 16 rows can only ever show yellow, so the top of every arrow would be yellow.

It receives navigation from the phone over Bluetooth LE and shows the turn arrow, the distance and what to do. The screen flashes when the turn is 5 m away. Every screen is drawn exactly as the phone app's preview shows it; see the pictures in [`docs/images/oled_screens.png`](../docs/images/oled_screens.png).

## Wiring

| OLED pin | ESP32 DevKit pin |
|----------|------------------|
| VCC | 3V3 |
| GND | GND |
| SDA | GPIO 21 |
| SCL (sometimes labelled SCK) | GPIO 22 |

The I2C address is usually `0x3C`. If the screen stays dark, try `0x3D` (`kOledAddress` in `src/main.cpp`). If it's mounted upside down, change `setRotation(0)` to `setRotation(2)`.

## Build and upload

Install [PlatformIO](https://platformio.org/install), either the VS Code extension or the command line, then with the ESP32 plugged in by USB:

```bash
cd front-module
pio run -t upload
```

```bash
pio device monitor
```

## Testing without the phone

Open the serial monitor (115200 baud) and type a message:

| Type | Screen |
|------|--------|
| `2 80` | Turn left in 80 m |
| `4 120` | Slight left in 120 m |
| `7 4 flash` | Sharp right in 4 m, flashing |
| `9,22 90` | Roundabout, exit 2, in 90 m |
| `2,3 60` | Left then right |
| `arrived` / `reroute` / `nophone` / `battery 15` / `clear` | Those screens |
| `demo` | Steps through every screen |
| `help` | The list |

Symbol numbers: 1 straight, 2 left, 3 right, 4/5 slight left/right, 6/7 sharp left/right, 8 U-turn, 9 roundabout (followed by 21-29 for exit 1-9), 10 destination.

## Bluetooth (DRAFT, part of S4)

The module advertises as **BikeNav Front** with service `6e3b0001-8f7a-4c1e-9b52-2d1c0b7a1f10`. The phone writes each update to characteristic `6e3b0002-8f7a-4c1e-9b52-2d1c0b7a1f10`:

| Byte | Meaning |
|------|---------|
| 0 | Version (1) |
| 1 | Flags: bit 0 = flash, bit 1 = arrived |
| 2-3 | Distance to the turn in metres, little-endian (`0xFFFF` = none) |
| 4 | Number of symbols that follow (0-4; 0 = blank) |
| 5.. | Symbol IDs |

The phone side is `encodeNavPacket` in `phone/navigation/lib/src/protocol.dart`.

If the phone disconnects, or sends nothing for 10 s during a ride, the screen shows **NO PHONE**. It goes back to navigation as soon as the next update arrives.

## Files

| File | What it is |
|------|------------|
| `src/main.cpp` | Display setup, Bluetooth, flashing, phone-lost timeout, serial test commands |
| `src/screen.cpp`, `src/screen.h` | Draws every screen. Plain C++, no Arduino, so it can be tested on a laptop |
| `test_native/check.sh` | Checks that `screen.cpp` draws exactly what the phone draws (needs `g++` and Dart) |

`screen.cpp` is a port of `renderOled` in `phone/navigation/lib/src/oled.dart`. If you change one, change the other and run `test_native/check.sh`. It compares 503 screens pixel for pixel.

## Not done yet

- **Battery level:** reading the battery voltage and sending it to the phone (F4). `drawLowBattery` is ready to use.
- **Brightness:** the SSD1306 contrast setting for daylight (F4).
- **Pairing security:** any phone can connect at the moment. That's fine for a demo, but S4 should decide on bonding.

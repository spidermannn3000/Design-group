// Laptop check: reads "name hexpacket" lines, draws each screen with
// screen.cpp and prints it as text art, for comparing with the phone's
// Dart renderer. Built and run by check.sh.
#include <stdio.h>
#include <string.h>

#include "../src/screen.h"

struct Buffer : screen::Canvas {
  bool px[screen::kHeight][screen::kWidth] = {};
  void set(int x, int y) override { px[y][x] = true; }
};

int main() {
  char name[64], hex[64];
  while (scanf("%63s %63s", name, hex) == 2) {
    uint8_t data[32];
    size_t len = strlen(hex) / 2;
    for (size_t i = 0; i < len; i++) sscanf(hex + 2 * i, "%2hhx", &data[i]);
    screen::NavMessage m;
    if (!screen::decode(data, len, m)) {
      printf("== %s\nDECODE FAILED\n", name);
      continue;
    }
    Buffer b;
    screen::draw(b, m);
    printf("== %s\n", name);
    for (int y = 0; y < screen::kHeight; y++) {
      for (int x = 0; x < screen::kWidth; x++) putchar(b.px[y][x] ? '#' : '.');
      putchar('\n');
    }
  }
  return 0;
}

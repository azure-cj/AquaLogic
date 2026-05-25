# DIYables_LCD_I2C

A comprehensive Arduino library for controlling HD44780-based LCD displays via I2C interface. This library provides full compatibility across all Arduino architectures and platforms.

## Hardware

### Compatible LCD Displays

- [LCD I2C 16x2 (Blue Background)](https://diyables.io/products/lcd-i2c-16x2-blue-background)
- [LCD I2C 20x4 (Blue Backlight)](https://diyables.io/products/lcd-2004-i2c-20x4-display-blue-backlight)

### Tested Hardware

| Board                   | Tested |
|-------------------------|:------:|
| Arduino Uno R3          |   ✅   |
| Arduino Uno R4 WiFi     |   ✅   |
| Arduino Uno R4 Minima   |   ✅   |
| Arduino Mega            |   ✅   |
| Arduino Due             |   ✅   |
| Arduino Giga            |   ✅   |
| [DIYables STEM V4 IoT *(works like Arduino Uno R4 WiFi)*](https://diyables.io/products/diyables-stem-v4-iot-fully-compatible-with-arduino-uno-r4-wifi) |   ✅   |
| [DIYables STEM V4B IoT *(works like Arduino Uno R4 WiFi)*](https://diyables.io/products/diyables-stem-v4b-iot-development-board-compatible-with-arduino-uno-r4-wifi-ra4m1-32-bit-arm-cortex-m4-with-esp32-s3-wifi-bluetooth-usb-c-for-learning-prototyping-education) |   ✅   |
| [DIYables STEM V3 *(works like Arduino Uno R3)*](https://diyables.io/products/diyables-stem-v3-fully-compatible-with-arduino-uno-r3) |   ✅   |
| [DIYables STEM V4 Edu *(works like Arduino Uno R4 Minima)*](https://diyables.io/stem-v4-edu) |   ✅   |
| [DIYables MEGA2560 R3 *(works like Arduino Mega 2560 Rev3)*](https://diyables.io/atmega2560-board) |   ✅   |
| [DIYables Nano R3 *(works like Arduino Nano R3)*](https://diyables.io/nano-board) |   ✅   |
| [DIYables ESP32 Development Board](https://diyables.io/esp32-board) |   ✅   |
| [DIYables ESP32 S3, Uno-form factor](https://diyables.io/products/esp32-s3-development-board-with-esp32-s3-wroom-1-n16r8-wifi-bluetooth-uno-compatible-form-factor-works-with-arduino-ide) |   ✅   |
| Other boards            |   Not yet, expected to work   |

## Features

- Support for HD44780-based LCD displays with I2C interface
- Compatible with all Arduino architectures
- **Multiple I2C bus support** (Wire, Wire1, Wire2, etc.) - perfect for Arduino Giga and other multi-I2C boards
- Control up to 80 characters (e.g., 16x2, 20x4)
- Backlight control
- Custom character support
- Full API compatibility with LiquidCrystal library

## Installation

### Arduino IDE Library Manager

1. Open Arduino IDE
2. Go to Sketch > Include Library > Manage Libraries
3. Search for "DIYables_LCD_I2C"
4. Click Install

### Manual Installation

1. Download the library as a ZIP file
2. In Arduino IDE, go to Sketch > Include Library > Add .ZIP Library
3. Select the downloaded ZIP file

## Usage

### Basic Usage (Default I2C - Wire)

```cpp
#include <DIYables_LCD_I2C.h>

DIYables_LCD_I2C lcd(0x27, 16, 2);  // I2C address 0x27, 16 columns, 2 rows

void setup() {
  lcd.init();
  lcd.backlight();
  lcd.setCursor(0, 0);
  lcd.print("Hello, World!");
}

void loop() {
  // Your code here
}
```

### Multiple I2C Buses (Arduino Giga, etc.)

For boards with multiple I2C buses like Arduino Giga R1 WiFi, you can specify which I2C bus to use:

```cpp
#include <DIYables_LCD_I2C.h>

// Use Wire1 instead of default Wire
DIYables_LCD_I2C lcd(0x27, 16, 2, Wire1);  

void setup() {
  lcd.init();
  lcd.backlight();
  lcd.print("Using Wire1!");
}

void loop() {
  // Your code here
}
```

**Supported I2C Buses:**
- `Wire` - Default I2C bus (if no bus specified)
- `Wire1` - Secondary I2C bus (Arduino Giga, Due, etc.)
- `Wire2` - Tertiary I2C bus (Arduino Giga, etc.)
- Any other `TwoWire` compatible interface

## API Reference

### Initialization
- `DIYables_LCD_I2C(address, cols, rows)` - Constructor using default Wire (I2C bus 0)
- `DIYables_LCD_I2C(address, cols, rows, wire)` - Constructor with custom I2C bus (Wire1, Wire2, etc.)
- `init()` - Initialize the LCD
- `begin(cols, rows)` - Set LCD dimensions

### Display Control
- `clear()` - Clear the display
- `home()` - Move cursor to home position
- `display()` - Turn on the display
- `noDisplay()` - Turn off the display
- `backlight()` - Turn on the backlight
- `noBacklight()` - Turn off the backlight

### Cursor Control
- `setCursor(col, row)` - Set cursor position
- `cursor()` - Show underline cursor
- `noCursor()` - Hide cursor
- `blink()` - Blink cursor
- `noBlink()` - Stop blinking

### Text
- `print(text)` - Print text
- `write(char)` - Write a single character
- `createChar(num, data)` - Create custom character

### Text Direction
- `leftToRight()` - Text flows left to right
- `rightToLeft()` - Text flows right to left
- `autoscroll()` - Enable autoscroll
- `noAutoscroll()` - Disable autoscroll

### Helper Functions
- `clearRow(row)` - Clear a specific row
- `printCenter(text, row)` - Print text centered on a row
- `printRight(text, row)` - Print text right-aligned on a row
- `clearToEOL()` - Clear from cursor to end of line
- `isConnected()` - Check if LCD is responding
- `drawProgressBar(row, percent)` - Draw a progress bar (0-100%)

### Predefined Custom Characters
The library includes ready-to-use custom character patterns in the `LCD_CustomChars` namespace:
- `LCD_CustomChars::HEART` - Heart symbol
- `LCD_CustomChars::ARROW_UP` - Upward arrow
- `LCD_CustomChars::ARROW_DOWN` - Downward arrow
- `LCD_CustomChars::ARROW_LEFT` - Left arrow
- `LCD_CustomChars::ARROW_RIGHT` - Right arrow
- `LCD_CustomChars::DEGREE` - Degree symbol (°)
- `LCD_CustomChars::BELL` - Bell/notification icon
- `LCD_CustomChars::SMILEY` - Smiley face

Example usage:
```cpp
lcd.createChar(0, LCD_CustomChars::HEART);
lcd.write(0);  // Display heart
```

## Examples

See the `examples` folder for complete working examples:

**Basic Examples:**
- `LCD_16x2` - Basic text and number display on 16x2 LCD
- `LCD_20x4` - Multi-row display demonstration on 20x4 LCD
- `CustomChars` - Creating and displaying custom characters

**Advanced Examples:**
- `TextAlignment` - Center and right-align text using helper functions
- `AutoScroll` - Scrolling text with custom heart character
- `ProgressBar` - Display progress/loading bars
- `CountdownTimer` - Countdown timer implementation
- `SensorDisplay` - Display sensor readings without flickering

**Utility Examples:**
- `I2C_Scanner` - Find your LCD's I2C address (troubleshooting tool)
- `MultipleI2C` - Using multiple LCDs on different I2C buses (Wire, Wire1, etc.)

## Common I2C Addresses

If you don't know your LCD's I2C address, try these common values or run the `I2C_Scanner` example:

| Address | Likelihood | Notes |
|---------|------------|-------|
| 0x27 | Very Common | Default for most I2C LCD modules |
| 0x3F | Common | Alternative address |
| 0x20 | Less Common | Some PCF8574 modules |
| 0x26 | Rare | Adjustable via jumpers on some modules |
| 0x38 | Rare | Some older modules |

**Tip:** Run the `I2C_Scanner` example to automatically detect your LCD's address!

## Troubleshooting

### No Display / Blank Screen

**Problem:** LCD backlight is on, but no text appears.

**Solutions:**
1. **Check I2C Address:**
   - Run the `I2C_Scanner` example to find the correct address
   - Try 0x27 or 0x3F (most common)

2. **Check Wiring:**
   ```
   LCD -> Arduino
   VCC -> 5V
   GND -> GND
   SDA -> A4 (Uno) or SDA pin
   SCL -> A5 (Uno) or SCL pin
   ```

3. **Adjust Contrast:**
   - Turn the blue potentiometer on the I2C backpack
   - Turn clockwise/counterclockwise until text appears

4. **Check Initialization:**
   ```cpp
   lcd.init();      // Must be called in setup()
   lcd.backlight(); // Turn on backlight
   ```

### Garbled or Strange Characters

**Problem:** Display shows random symbols or partial characters.

**Solutions:**
1. **Wrong Display Size:** Ensure constructor matches your LCD (16x2, 20x4, etc.)
   ```cpp
   DIYables_LCD_I2C lcd(0x27, 16, 2);  // Must match your LCD!
   ```

2. **Power Issues:** Use external 5V power supply for Arduino + LCD

3. **I2C Pull-up Resistors:** Some modules need external 4.7kΩ pull-ups on SDA/SCL

### Backlight Works But No Text

**Problem:** Backlight is on, but screen is completely blank.

**Solutions:**
1. **Contrast Too Low:** Adjust the potentiometer on the back
2. **Not Initialized:** Call `lcd.init()` before printing
3. **Wrong I2C Address:** Use `I2C_Scanner` to verify

### Display Freezes or Stops Updating

**Problem:** Display stops responding after some time.

**Solutions:**
1. **I2C Bus Hung:** Call `lcd.isConnected()` to check connection
2. **Reset LCD:** Call `lcd.init()` again to reinitialize
3. **Check Power:** Ensure stable 5V supply

### Multiple I2C Devices Conflict

**Problem:** LCD doesn't work when other I2C devices are connected.

**Solutions:**
1. **Address Conflict:** Each I2C device needs a unique address
2. **Use Different I2C Bus:** On Giga/Due, use Wire1 for LCD
   ```cpp
   DIYables_LCD_I2C lcd(0x27, 16, 2, Wire1);
   ```

### Text Doesn't Scroll

**Problem:** `scrollDisplayLeft()` doesn't work as expected.

**Solutions:**
1. **Not Enough Text:** Scrolling moves the entire display, not just text
2. **Use Loop:** Call scroll function repeatedly:
   ```cpp
   for (int i = 0; i < 16; i++) {
     lcd.scrollDisplayLeft();
     delay(300);
   }
   ```

## Performance Tips

1. **Reduce Clear() Calls:** Instead of `lcd.clear()`, update only changed portions
2. **Use clearToEOL():** Clear remainder of line instead of full display
3. **Track Cursor:** Use helper functions to avoid manual position tracking
4. **Buffer Updates:** Group multiple writes before refreshing display

## Hardware Compatibility

### Boards with Multiple I2C Buses

This library supports boards with multiple I2C interfaces:

| Board | I2C Buses | Pins |
|-------|-----------|------|
| Arduino Giga R1 WiFi | Wire, Wire1, Wire2 | Wire: PB9/PB8, Wire1: PB7/PB6, Wire2: PH8/PH7 |
| Arduino Due | Wire, Wire1 | Wire: SDA/SCL, Wire1: SDA1/SCL1 |
| ESP32 | Wire, Wire1 | Configurable via `Wire.begin(SDA, SCL)` |
| STM32 | Wire, Wire1, Wire2 | Board-specific |

For single I2C bus boards (Uno, Nano, Mega, etc.), use the default constructor without specifying a Wire object.

## License

This library is released under the MIT License. See LICENSE file for details.

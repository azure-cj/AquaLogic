/*
 * Multiple I2C Bus Example for DIYables_LCD_I2C Library
 * 
 * This example demonstrates how to use LCD displays on different I2C buses
 * on boards that support multiple I2C interfaces like:
 * - Arduino Giga R1 WiFi (Wire, Wire1, Wire2)
 * - Arduino Due (Wire, Wire1)
 * - ESP32 (Wire, Wire1 with custom pins)
 * 
 * Hardware Setup:
 * - Connect LCD1 to the default I2C bus (Wire) - typically SDA/SCL pins
 * - Connect LCD2 to the secondary I2C bus (Wire1) - board-specific pins
 * 
 * For Arduino Giga R1 WiFi:
 * - Wire:  SDA=PB9, SCL=PB8  (default I2C)
 * - Wire1: SDA=PB7, SCL=PB6  (secondary I2C)
 * - Wire2: SDA=PH8, SCL=PH7  (tertiary I2C)
 * 
 * COMPATIBLE LCD:
 * - LCD I2C 16x2: https://diyables.io/products/lcd-i2c-16x2-blue-background
 * - LCD I2C 20x4: https://diyables.io/products/lcd-2004-i2c-20x4-display-blue-backlight
 * 
 * TESTED HARDWARE:
 * - Arduino Uno R3
 * - Arduino Uno R4 WiFi
 * - Arduino Uno R4 Minima
 * - Arduino Mega
 * - Arduino Due
 * - Arduino Giga
 * - DIYables STEM V3: https://diyables.io/stem-v3
 * - DIYables STEM V4 IoT: https://diyables.io/stem-v4-iot
 * - DIYables STEM V4B IoT: https://diyables.io/stem-v4b-iot
 * - DIYables STEM V4 Edu: https://diyables.io/stem-v4-edu
 * - DIYables MEGA2560 R3: https://diyables.io/atmega2560-board
 * - DIYables ESP32 Board: https://diyables.io/esp32-board
 * - DIYables ESP32 S3, Uno-form factor: https://diyables.io/esp32-s3-uno
 * - It is expected to work with other boards
 * 
 * Author: DIYables
 * Website: https://diyables.io
 */

#include <DIYables_LCD_I2C.h>

// Create two LCD instances using different I2C buses
DIYables_LCD_I2C lcd1(0x27, 16, 2);         // LCD on default Wire (I2C bus 0)
DIYables_LCD_I2C lcd2(0x26, 16, 2, Wire1);  // LCD on Wire1 (I2C bus 1)

void setup() {
  Serial.begin(115200);
  Serial.println("Multiple I2C Bus LCD Example");
  
  // Initialize first LCD on default Wire bus
  Serial.println("Initializing LCD1 on Wire...");
  lcd1.init();
  lcd1.backlight();
  lcd1.setCursor(0, 0);
  lcd1.print("LCD1 on Wire");
  lcd1.setCursor(0, 1);
  lcd1.print("Address: 0x27");
  
  // Initialize second LCD on Wire1 bus
  Serial.println("Initializing LCD2 on Wire1...");
  lcd2.init();
  lcd2.backlight();
  lcd2.setCursor(0, 0);
  lcd2.print("LCD2 on Wire1");
  lcd2.setCursor(0, 1);
  lcd2.print("Address: 0x26");
  
  Serial.println("Both LCDs initialized!");
}

void loop() {
  // Update counter on both displays
  static unsigned long counter = 0;
  
  // Update LCD1
  lcd1.setCursor(0, 1);
  lcd1.print("Count: ");
  lcd1.print(counter);
  lcd1.print("    ");  // Clear remaining characters
  
  // Update LCD2 (with offset for visual difference)
  lcd2.setCursor(0, 1);
  lcd2.print("Count: ");
  lcd2.print(counter * 2);
  lcd2.print("    ");  // Clear remaining characters
  
  counter++;
  delay(1000);
}

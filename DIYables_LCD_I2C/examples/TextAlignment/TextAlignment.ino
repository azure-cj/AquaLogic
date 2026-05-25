/*
 * Text Alignment Example
 * 
 * This example demonstrates how to align text on the LCD display
 * using the helper functions: printCenter() and printRight().
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

DIYables_LCD_I2C lcd(0x27, 16, 2);  // I2C address 0x27, 16 columns, 2 rows

void setup() {
  lcd.init();
  lcd.backlight();
}

void loop() {
  // Example 1: Left-aligned (default)
  lcd.clear();
  lcd.setCursor(0, 0);
  lcd.print("Left aligned");
  lcd.setCursor(0, 1);
  lcd.print("Default");
  delay(2000);
  
  // Example 2: Center-aligned
  lcd.clear();
  lcd.printCenter("Center", 0);
  lcd.printCenter("aligned", 1);
  delay(2000);
  
  // Example 3: Right-aligned
  lcd.clear();
  lcd.printRight("Right", 0);
  lcd.printRight("aligned", 1);
  delay(2000);
  
  // Example 4: Mixed alignment
  lcd.clear();
  lcd.setCursor(0, 0);
  lcd.print("Left");
  lcd.printRight("Right", 0);
  lcd.printCenter("Center", 1);
  delay(2000);
  
  // Example 5: Demonstrate clearRow()
  lcd.clear();
  lcd.setCursor(0, 0);
  lcd.print("Row 0: Keep");
  lcd.setCursor(0, 1);
  lcd.print("Row 1: Clear");
  delay(2000);
  
  lcd.clearRow(1);  // Clear only row 1
  lcd.printCenter("Cleared!", 1);
  delay(2000);
}

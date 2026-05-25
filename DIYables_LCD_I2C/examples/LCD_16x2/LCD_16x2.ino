/*
 * LCD 16x2 Display Example
 * 
 * This example demonstrates basic text display on a 16x2 LCD
 * using the DIYables_LCD_I2C library.
 * 
 * The sketch alternates between displaying:
 * 1. Text message
 * 2. Integer and float numbers
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

DIYables_LCD_I2C lcd(0x27, 16, 2);  // I2C address 0x27, 16 column and 2 rows

void setup() {
  lcd.init();       // initialize the lcd
  lcd.backlight();
}

void loop() {
  lcd.clear();          // clear display
  lcd.setCursor(0, 0);  // move cursor to   (0, 0)
  lcd.print("DIYables");
  lcd.setCursor(0, 1);  //  Move the cursor to column 0, row 1 (second row)
  lcd.print("www.diyables.io");
  delay(2000);  // display the above for two seconds

  lcd.clear();          // clear display
  lcd.setCursor(0, 0);  // move cursor to   (0, 0)
  lcd.print("Int: ");
  lcd.print(1234);  // Print integer
  lcd.setCursor(0, 1);   // Move to the beginning of the second row
  lcd.print("Float: ");
  lcd.print(56.79);  // Print float
  delay(2000);            // display the above for two seconds
}

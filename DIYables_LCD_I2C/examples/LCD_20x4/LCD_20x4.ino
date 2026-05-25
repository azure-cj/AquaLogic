/*
 * LCD 20x4 Display Example
 * 
 * This example demonstrates basic text display on a 20x4 LCD
 * using the DIYables_LCD_I2C library.
 * 
 * The sketch displays text on all four rows of the LCD.
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

DIYables_LCD_I2C lcd(0x27, 20, 4);  // I2C address 0x27, 20 column and 4 rows

void setup() {
  lcd.init();       // initialize the lcd
  lcd.backlight();
}

void loop() {
  lcd.setCursor(0, 0);            // move cursor the first row
  lcd.print("LCD 20x4");          // print message at the first row
  lcd.setCursor(0, 1);            // move cursor to the second row
  lcd.print("I2C Address: 0x27"); // print message at the second row
  lcd.setCursor(0, 2);            // move cursor to the third row
  lcd.print("DIYables");          // print message at the third row
  lcd.setCursor(0, 3);            // move cursor to the fourth row
  lcd.print("www.diyables.io");   // print message the fourth row
  delay(5000);                    // display the above for five seconds
}

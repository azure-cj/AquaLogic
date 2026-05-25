/*
 * Auto-Scroll Text Example
 * 
 * This example demonstrates how to scroll text across the LCD display
 * using the built-in scrollDisplayLeft() and scrollDisplayRight() functions
 * with a custom heart character.
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

// Define custom character 0 (heart shape)
uint8_t heart[8] = {
  0b00000,
  0b01010,
  0b11111,
  0b11111,
  0b01110,
  0b00100,
  0b00000,
  0b00000
};

DIYables_LCD_I2C lcd(0x27, 16, 2);  // I2C address 0x27, 16 columns, 2 rows

void setup() {
  lcd.init();
  lcd.backlight();
  
  // Create the custom heart character at location 0
  lcd.createChar(0, heart);
  
  // Display the message
  lcd.setCursor(0, 0);
  lcd.print("www.diyables.io ");
  lcd.write(0);  // Print heart symbol
}

void loop() {
  // Scroll left 16 positions
  for (int i = 0; i < 16; i++) {
    lcd.scrollDisplayLeft();
    delay(300);  // Adjust speed of scrolling (lower = faster)
  }
  
  delay(1000);  // Pause at the end
  
  // Scroll right 16 positions to return to original position
  for (int i = 0; i < 16; i++) {
    lcd.scrollDisplayRight();
    delay(300);
  }
  
  delay(1000);  // Pause before repeating
}

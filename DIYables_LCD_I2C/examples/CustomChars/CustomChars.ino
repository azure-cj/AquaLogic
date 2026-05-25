/*
 * Custom Characters Example
 * 
 * This example demonstrates how to create and display custom characters
 * on an LCD using the DIYables_LCD_I2C library.
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

// Define custom character 1 (arrow pointing upwards)
uint8_t arrow_up[8] = {
  0b00100,
  0b01110,
  0b11111,
  0b00100,
  0b00100,
  0b00100,
  0b00100,
  0b00100
};

// Define custom character 2 (arrow pointing downwards)
uint8_t arrow_down[8] = {
  0b00100,
  0b00100,
  0b00100,
  0b00100,
  0b00100,
  0b11111,
  0b01110,
  0b00100
};

DIYables_LCD_I2C lcd(0x27, 16, 2);  // I2C address 0x27, 16 columns, 2 rows

void setup() {
  lcd.init();
  lcd.backlight();
  
  // Create the custom character at location 0, 1, 2
  lcd.createChar(0, heart);
  lcd.createChar(1, arrow_up);
  lcd.createChar(2, arrow_down);
  
  // Display the custom character
  lcd.setCursor(0, 0);  // Move the cursor to column 0, row 0 (first row)
  lcd.write(0);         // Display the custom character stored at location 0
  
  lcd.setCursor(5, 0);  // Move the cursor to column 5, row 0 (first row)
  lcd.write(1);         // Display the custom character stored at location 1
  
  lcd.setCursor(10, 0); // Move the cursor to column 10, row 0 (first row)
  lcd.write(2);         // Display the custom character stored at location 2
}

void loop() {
  // Nothing to do here
}


/*
 * Sensor Display Example
 * 
 * This example demonstrates how to display sensor readings on the LCD
 * with proper formatting and update without flickering.
 * 
 * This example simulates temperature and humidity readings.
 * Replace the simulated values with actual sensor readings.
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
  
  // Display labels (only once to avoid flickering)
  lcd.setCursor(0, 0);
  lcd.print("Temp: ");
  lcd.setCursor(0, 1);
  lcd.print("Humid:");
}

void loop() {
  // Simulate sensor readings (replace with actual sensor code)
  float temperature = 20.0 + random(0, 100) / 10.0;  // 20.0 - 30.0°C
  float humidity = 45.0 + random(0, 200) / 10.0;     // 45.0 - 65.0%
  
  // Update temperature value only (not the label)
  lcd.setCursor(6, 0);
  lcd.print(temperature, 1);  // 1 decimal place
  lcd.write(0xDF);             // Built-in degree symbol (°)
  lcd.print("C ");              // Clear extra digits
  
  // Update humidity value only
  lcd.setCursor(7, 1);
  lcd.print(humidity, 1);     // 1 decimal place
  lcd.print("%  ");            // Clear extra digits
  
  delay(2000);  // Update every 2 seconds
}

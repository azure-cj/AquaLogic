/*
 * Progress Bar Example
 * 
 * This example demonstrates how to display a progress bar on the LCD
 * using the built-in drawProgressBar() function.
 * 
 * Perfect for showing loading status, download progress, sensor readings, etc.
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
  
  lcd.setCursor(0, 0);
  lcd.print("Progress Bar");
}

void loop() {
  // Simulate a process with progress from 0% to 100%
  for (int percent = 0; percent <= 100; percent += 5) {
    // Display percentage value
    lcd.setCursor(0, 0);
    lcd.print("Progress: ");
    lcd.print(percent);
    lcd.print("%  ");  // Extra spaces to clear previous digits
    
    // Draw progress bar on row 1
    lcd.drawProgressBar(1, percent);
    
    delay(200);  // Simulate work being done
  }
  
  // Show completion message
  lcd.setCursor(0, 0);
  lcd.print("Complete!       ");
  delay(2000);
  
  // Reset display
  lcd.setCursor(0, 0);
  lcd.print("Progress Bar    ");
  delay(1000);
}

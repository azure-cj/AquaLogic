/*
 * Countdown Timer Example
 * 
 * This example displays a countdown timer on the LCD.
 * Useful for timers, alarms, and time-based projects.
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
  
  lcd.printCenter("Countdown", 0);
  lcd.printCenter("Timer", 1);
  delay(2000);
}

void loop() {
  // Countdown from 10 seconds
  for (int seconds = 10; seconds >= 0; seconds--) {
    lcd.clear();
    lcd.printCenter("Time Left:", 0);
    
    // Format time display
    char timeStr[10];
    sprintf(timeStr, "%02d sec", seconds);
    lcd.printCenter(timeStr, 1);
    
    delay(1000);  // Wait 1 second
  }
  
  // Time's up!
  lcd.clear();
  lcd.printCenter("Time's Up!", 0);
  lcd.printCenter("***", 1);
  
  // Flash the display
  for (int i = 0; i < 3; i++) {
    lcd.noBacklight();
    delay(250);
    lcd.backlight();
    delay(250);
  }
  
  delay(2000);
}

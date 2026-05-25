/*
 * I2C Scanner Example
 * 
 * This example scans the I2C bus for devices and displays their addresses.
 * Useful for finding your LCD's I2C address if you don't know it.
 * 
 * Common LCD I2C addresses:
 * - 0x27 (most common)
 * - 0x3F (alternative)
 * - 0x20, 0x26, 0x38 (less common)
 * 
 * Open Serial Monitor at 115200 baud to see results.
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

#include <Wire.h>

void setup() {
  Serial.begin(115200);
  while (!Serial);  // Wait for Serial Monitor
  
  Serial.println("\n=== I2C Scanner ===");
  Serial.println("Scanning I2C bus...\n");
}

void loop() {
  byte error, address;
  int deviceCount = 0;

  for (address = 1; address < 127; address++) {
    Wire.beginTransmission(address);
    error = Wire.endTransmission();

    if (error == 0) {
      Serial.print("I2C device found at address 0x");
      if (address < 16) {
        Serial.print("0");
      }
      Serial.print(address, HEX);
      Serial.println(" !");
      deviceCount++;
      
      // Provide hints for common addresses
      if (address == 0x27 || address == 0x3F) {
        Serial.println("  -> Likely your LCD I2C address");
      }
    } else if (error == 4) {
      Serial.print("Unknown error at address 0x");
      if (address < 16) {
        Serial.print("0");
      }
      Serial.println(address, HEX);
    }
  }

  if (deviceCount == 0) {
    Serial.println("No I2C devices found.");
    Serial.println("Check your wiring!");
  } else {
    Serial.print("\nFound ");
    Serial.print(deviceCount);
    Serial.println(" device(s).");
  }

  Serial.println("\nScanning again in 5 seconds...\n");
  delay(5000);
}

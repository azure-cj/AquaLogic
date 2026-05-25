// Based on the work by DFRobot

#include "DIYables_LCD_I2C.h"
#include "Wire.h"
#include <inttypes.h>

#if defined(ARDUINO) && ARDUINO >= 100
  #include "Arduino.h"
#else
  #include "WProgram.h"
#endif

// =============================================================================
// Constants
// =============================================================================

// Timing constants (in milliseconds and microseconds)
static const uint8_t LCD_INIT_DELAY_MS = 50;
static const uint16_t LCD_INIT_LONG_DELAY_MS = 1000;
static const uint16_t LCD_INIT_COMMAND_DELAY_US = 4500;
static const uint8_t LCD_INIT_SHORT_DELAY_US = 150;
static const uint16_t LCD_COMMAND_DELAY_US = 2000;

// Row offset addresses for different LCD configurations
static const uint8_t LCD_ROW_OFFSETS[] = {0x00, 0x40, 0x14, 0x54};

// =============================================================================
// Constructor and Initialization
// =============================================================================

DIYables_LCD_I2C::DIYables_LCD_I2C(uint8_t lcd_addr, uint8_t lcd_cols, uint8_t lcd_rows)
  : _addr(lcd_addr),
    _cols(lcd_cols),
    _rows(lcd_rows),
    _backlightval(LCD_NOBACKLIGHT),
    _oled(false),
    _numlines(0),
    _displayfunction(0),
    _displaycontrol(0),
    _displaymode(0),
    _wire(&Wire),
    _currentCol(0),
    _currentRow(0) {  // Default to Wire (primary I2C bus)
  // Constructor body intentionally empty - initialization done in member initializer list
}

DIYables_LCD_I2C::DIYables_LCD_I2C(uint8_t lcd_addr, uint8_t lcd_cols, uint8_t lcd_rows, TwoWire &wire)
  : _addr(lcd_addr),
    _cols(lcd_cols),
    _rows(lcd_rows),
    _backlightval(LCD_NOBACKLIGHT),
    _oled(false),
    _numlines(0),
    _displayfunction(0),
    _displaycontrol(0),
    _displaymode(0),
    _wire(&wire),
    _currentCol(0),
    _currentRow(0) {  // Use specified I2C bus
  // Constructor body intentionally empty - initialization done in member initializer list
}

void DIYables_LCD_I2C::init() {
  init_priv();
}

void DIYables_LCD_I2C::oled_init() {
  _oled = true;
  init_priv();
}

void DIYables_LCD_I2C::init_priv() {
  _wire->begin();
  _displayfunction = LCD_4BITMODE | LCD_1LINE | LCD_5x8DOTS;
  begin(_cols, _rows);
}

void DIYables_LCD_I2C::begin(uint8_t cols, uint8_t lines, uint8_t dotsize) {
  if (lines > 1) {
    _displayfunction |= LCD_2LINE;
  }
  _numlines = lines;

  // For some 1-line displays, you can select a 10-pixel high font
  if ((dotsize != 0) && (lines == 1)) {
    _displayfunction |= LCD_5x10DOTS;
  }

  // Wait for LCD to power up (datasheet requires 40ms after power > 2.7V)
  delay(LCD_INIT_DELAY_MS);

  // Reset expander and turn backlight off
  expanderWrite(_backlightval);
  delay(LCD_INIT_LONG_DELAY_MS);

  // Initialize LCD in 4-bit mode (HD44780 datasheet, page 46, figure 24)
  // Start in 8-bit mode, then switch to 4-bit
  write4bits(0x03 << 4);
  delayMicroseconds(LCD_INIT_COMMAND_DELAY_US);

  write4bits(0x03 << 4);
  delayMicroseconds(LCD_INIT_COMMAND_DELAY_US);

  write4bits(0x03 << 4);
  delayMicroseconds(LCD_INIT_SHORT_DELAY_US);

  // Finally, set to 4-bit interface
  write4bits(0x02 << 4);

  // Configure display function (lines, font size, etc.)
  command(LCD_FUNCTIONSET | _displayfunction);

  // Turn display on with no cursor or blinking
  _displaycontrol = LCD_DISPLAYON | LCD_CURSOROFF | LCD_BLINKOFF;
  display();

  // Clear display
  clear();

  // Set default text direction (left-to-right for Latin scripts)
  _displaymode = LCD_ENTRYLEFT | LCD_ENTRYSHIFTDECREMENT;
  command(LCD_ENTRYMODESET | _displaymode);

  home();
}

// =============================================================================
// High-Level Commands
// =============================================================================

void DIYables_LCD_I2C::clear() {
  command(LCD_CLEARDISPLAY);
  delayMicroseconds(LCD_COMMAND_DELAY_US);  // Clear command takes ~2ms
  if (_oled) {
    setCursor(0, 0);
  }
}

void DIYables_LCD_I2C::home() {
  command(LCD_RETURNHOME);
  delayMicroseconds(LCD_COMMAND_DELAY_US);  // Home command takes ~2ms
}

void DIYables_LCD_I2C::setCursor(uint8_t col, uint8_t row) {
  // Bounds checking
  if (row >= _numlines) {
    row = _numlines - 1;
  }
  if (col >= _cols) {
    col = _cols - 1;
  }
  
  // Track cursor position
  _currentCol = col;
  _currentRow = row;
  
  command(LCD_SETDDRAMADDR | (col + LCD_ROW_OFFSETS[row]));
}

// =============================================================================
// Display Control
// =============================================================================

void DIYables_LCD_I2C::display() {
  _displaycontrol |= LCD_DISPLAYON;
  command(LCD_DISPLAYCONTROL | _displaycontrol);
}

void DIYables_LCD_I2C::noDisplay() {
  _displaycontrol &= ~LCD_DISPLAYON;
  command(LCD_DISPLAYCONTROL | _displaycontrol);
}

// =============================================================================
// Cursor Control
// =============================================================================

void DIYables_LCD_I2C::cursor() {
  _displaycontrol |= LCD_CURSORON;
  command(LCD_DISPLAYCONTROL | _displaycontrol);
}

void DIYables_LCD_I2C::noCursor() {
  _displaycontrol &= ~LCD_CURSORON;
  command(LCD_DISPLAYCONTROL | _displaycontrol);
}

void DIYables_LCD_I2C::blink() {
  _displaycontrol |= LCD_BLINKON;
  command(LCD_DISPLAYCONTROL | _displaycontrol);
}

void DIYables_LCD_I2C::noBlink() {
  _displaycontrol &= ~LCD_BLINKON;
  command(LCD_DISPLAYCONTROL | _displaycontrol);
}

// =============================================================================
// Display Scrolling
// =============================================================================

void DIYables_LCD_I2C::scrollDisplayLeft() {
  command(LCD_CURSORSHIFT | LCD_DISPLAYMOVE | LCD_MOVELEFT);
}

void DIYables_LCD_I2C::scrollDisplayRight() {
  command(LCD_CURSORSHIFT | LCD_DISPLAYMOVE | LCD_MOVERIGHT);
}

// =============================================================================
// Text Direction and Auto-scrolling
// =============================================================================

void DIYables_LCD_I2C::leftToRight() {
  _displaymode |= LCD_ENTRYLEFT;
  command(LCD_ENTRYMODESET | _displaymode);
}

void DIYables_LCD_I2C::rightToLeft() {
  _displaymode &= ~LCD_ENTRYLEFT;
  command(LCD_ENTRYMODESET | _displaymode);
}

void DIYables_LCD_I2C::autoscroll() {
  _displaymode |= LCD_ENTRYSHIFTINCREMENT;
  command(LCD_ENTRYMODESET | _displaymode);
}

void DIYables_LCD_I2C::noAutoscroll() {
  _displaymode &= ~LCD_ENTRYSHIFTINCREMENT;
  command(LCD_ENTRYMODESET | _displaymode);
}

// =============================================================================
// Custom Characters
// =============================================================================

void DIYables_LCD_I2C::createChar(uint8_t location, uint8_t charmap[]) {
  location &= 0x7;  // Only 8 locations available (0-7)
  command(LCD_SETCGRAMADDR | (location << 3));
  for (uint8_t i = 0; i < 8; i++) {
    write(charmap[i]);
  }
}

void DIYables_LCD_I2C::createChar(uint8_t location, const char *charmap) {
  location &= 0x7;  // Only 8 locations available (0-7)
  command(LCD_SETCGRAMADDR | (location << 3));
  for (uint8_t i = 0; i < 8; i++) {
    write(pgm_read_byte_near(charmap++));
  }
}

// =============================================================================
// Backlight Control
// =============================================================================

void DIYables_LCD_I2C::backlight() {
  _backlightval = LCD_BACKLIGHT;
  expanderWrite(0);
}

void DIYables_LCD_I2C::noBacklight() {
  _backlightval = LCD_NOBACKLIGHT;
  expanderWrite(0);
}

// =============================================================================
// Mid-Level Commands
// =============================================================================

#if defined(ARDUINO) && ARDUINO >= 100
inline size_t DIYables_LCD_I2C::write(uint8_t value) {
  send(value, Rs);
  return 1;
}
#else
inline void DIYables_LCD_I2C::write(uint8_t value) {
  send(value, Rs);
}
#endif

inline void DIYables_LCD_I2C::command(uint8_t value) {
  send(value, 0);
}

// =============================================================================
// Low-Level Data Transfer
// =============================================================================

void DIYables_LCD_I2C::send(uint8_t value, uint8_t mode) {
  uint8_t highnib = value & 0xF0;
  uint8_t lownib = (value << 4) & 0xF0;
  write4bits(highnib | mode);
  write4bits(lownib | mode);
}

void DIYables_LCD_I2C::write4bits(uint8_t value) {
  expanderWrite(value);
  pulseEnable(value);
}

void DIYables_LCD_I2C::expanderWrite(uint8_t data) {
  _wire->beginTransmission(_addr);
  _wire->write((int)(data) | _backlightval);
  // Note: Error checking could be added here by checking endTransmission() return value
  // Return values: 0=success, 1=data too long, 2=NACK on address, 3=NACK on data, 4=other
  _wire->endTransmission();
}

void DIYables_LCD_I2C::pulseEnable(uint8_t data) {
  expanderWrite(data | En);       // Enable high
  delayMicroseconds(1);           // Enable pulse must be >450ns

  expanderWrite(data & ~En);      // Enable low
  delayMicroseconds(50);          // Commands need >37us to settle
}

// =============================================================================
// Helper Functions (v2.0+)
// =============================================================================

void DIYables_LCD_I2C::clearRow(uint8_t row) {
  if (row >= _rows) {
    return;  // Invalid row
  }
  
  setCursor(0, row);
  for (uint8_t i = 0; i < _cols; i++) {
    write(' ');
  }
  setCursor(0, row);  // Return to start of row
}

void DIYables_LCD_I2C::printCenter(const char* text, uint8_t row) {
  if (row >= _rows) {
    return;  // Invalid row
  }
  
  uint8_t len = strlen(text);
  if (len >= _cols) {
    // Text too long, print from start
    setCursor(0, row);
    print(text);
    return;
  }
  
  uint8_t startCol = (_cols - len) / 2;
  setCursor(startCol, row);
  print(text);
}

void DIYables_LCD_I2C::printRight(const char* text, uint8_t row) {
  if (row >= _rows) {
    return;  // Invalid row
  }
  
  uint8_t len = strlen(text);
  if (len >= _cols) {
    // Text too long, print from start
    setCursor(0, row);
    print(text);
    return;
  }
  
  uint8_t startCol = _cols - len;
  setCursor(startCol, row);
  print(text);
}

void DIYables_LCD_I2C::clearToEOL() {
  uint8_t remainingCols = _cols - _currentCol;
  for (uint8_t i = 0; i < remainingCols; i++) {
    write(' ');
  }
}

bool DIYables_LCD_I2C::isConnected() {
  _wire->beginTransmission(_addr);
  return (_wire->endTransmission() == 0);
}

void DIYables_LCD_I2C::drawProgressBar(uint8_t row, uint8_t percent) {
  if (row >= _rows || percent > 100) {
    return;  // Invalid parameters
  }
  
  // Use full-width for progress bar
  uint8_t filledChars = (_cols * percent) / 100;
  
  setCursor(0, row);
  
  // Draw filled portion
  for (uint8_t i = 0; i < filledChars; i++) {
    write(0xFF);  // Solid block character
  }
  
  // Draw empty portion
  for (uint8_t i = filledChars; i < _cols; i++) {
    write('-');  // Empty character
  }
}

// =============================================================================
// Compatibility API Aliases
// =============================================================================

void DIYables_LCD_I2C::cursor_on() {
  cursor();
}

void DIYables_LCD_I2C::cursor_off() {
  noCursor();
}

void DIYables_LCD_I2C::blink_on() {
  blink();
}

void DIYables_LCD_I2C::blink_off() {
  noBlink();
}

void DIYables_LCD_I2C::load_custom_character(uint8_t char_num, uint8_t *rows) {
  createChar(char_num, rows);
}

void DIYables_LCD_I2C::setBacklight(uint8_t new_val) {
  if (new_val) {
    backlight();
  } else {
    noBacklight();
  }
}

void DIYables_LCD_I2C::printstr(const char c[]) {
  print(c);
}

// =============================================================================
// Unsupported API Functions (stubs for compatibility)
// =============================================================================

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wunused-parameter"

void DIYables_LCD_I2C::off() {}
void DIYables_LCD_I2C::on() {}
void DIYables_LCD_I2C::setDelay(int cmdDelay, int charDelay) {}
uint8_t DIYables_LCD_I2C::status() { return 0; }
uint8_t DIYables_LCD_I2C::keypad() { return 0; }
uint8_t DIYables_LCD_I2C::init_bargraph(uint8_t graphtype) { return 0; }
void DIYables_LCD_I2C::draw_horizontal_graph(uint8_t row, uint8_t column, uint8_t len, uint8_t pixel_col_end) {}
void DIYables_LCD_I2C::draw_vertical_graph(uint8_t row, uint8_t column, uint8_t len, uint8_t pixel_row_end) {}
void DIYables_LCD_I2C::setContrast(uint8_t new_val) {}

#pragma GCC diagnostic pop
	

#include <Wire.h>
#include <LiquidCrystal_I2C.h>
#include <OneWire.h>
#include <DallasTemperature.h>
#include <WiFi.h>
#include <WebServer.h>

// ========================
// WiFi Credentials
// ========================
const char* ssid     = "SKYFiber_2.4GHz_PdG7";
const char* password = "6xcRBQQX";

#define ONE_WIRE_BUS 27
#define TURBIDITY_PIN 34
#define TDS_PIN 25

LiquidCrystal_I2C lcd(0x27, 16, 2);
OneWire oneWire(ONE_WIRE_BUS);
DallasTemperature sensors(&oneWire);
WebServer server(80);

float temperatureC;
int turbidityRaw;
int tdsRaw;

String tempStatus;
String turbidityStatus;
String tdsStatus;
String overallStatus;

// ========================
// HTML Dashboard
// ========================
const char DASHBOARD_HTML[] PROGMEM = R"rawliteral(
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>AquaLogic Dashboard</title>
<style>
  @import url('https://fonts.googleapis.com/css2?family=Share+Tech+Mono&family=Orbitron:wght@400;700;900&display=swap');
  :root {
    --bg: #020d1a; --panel: #041424; --border: #0a3a5c;
    --accent: #00d4ff; --accent2: #00ff88; --warn: #ffaa00;
    --danger: #ff3355; --text: #c8eaf8; --dim: #3a6070;
  }
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    background: var(--bg); color: var(--text);
    font-family: 'Share Tech Mono', monospace;
    min-height: 100vh; padding: 24px 16px;
    background-image:
      radial-gradient(ellipse at 20% 0%, rgba(0,100,200,0.12) 0%, transparent 60%),
      radial-gradient(ellipse at 80% 100%, rgba(0,212,255,0.08) 0%, transparent 50%);
  }
  header { text-align: center; margin-bottom: 36px; }
  header h1 {
    font-family: 'Orbitron', monospace; font-size: clamp(1.6rem, 5vw, 2.8rem);
    font-weight: 900; letter-spacing: 0.15em; color: var(--accent);
    text-shadow: 0 0 30px rgba(0,212,255,0.5);
  }
  header p { font-size: 0.75rem; color: var(--dim); letter-spacing: 0.2em; margin-top: 6px; }
  .status-bar {
    display: flex; align-items: center; justify-content: center;
    gap: 10px; margin-bottom: 32px; font-size: 0.7rem;
    letter-spacing: 0.2em; color: var(--dim);
  }
  .pulse {
    width: 8px; height: 8px; border-radius: 50%;
    background: var(--accent2); box-shadow: 0 0 8px var(--accent2);
    animation: pulse 1.5s ease-in-out infinite;
  }
  @keyframes pulse {
    0%, 100% { opacity: 1; transform: scale(1); }
    50% { opacity: 0.4; transform: scale(0.7); }
  }
  .grid {
    display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
    gap: 20px; max-width: 1000px; margin: 0 auto 28px;
  }
  .card {
    background: var(--panel); border: 1px solid var(--border);
    border-radius: 4px; padding: 24px; position: relative; overflow: hidden;
  }
  .card::before {
    content: ''; position: absolute; top: 0; left: 0; right: 0;
    height: 2px; background: var(--accent);
  }
  .card.warn::before  { background: var(--warn); }
  .card.danger::before { background: var(--danger); }
  .card.good::before  { background: var(--accent2); }
  .card-label { font-size: 0.65rem; letter-spacing: 0.25em; color: var(--dim); margin-bottom: 12px; }
  .card-value { font-family: 'Orbitron', monospace; font-size: 2.2rem; font-weight: 700; line-height: 1; margin-bottom: 10px; }
  .card.good  .card-value { color: var(--accent2); }
  .card.warn  .card-value { color: var(--warn); }
  .card.danger .card-value { color: var(--danger); }
  .card       .card-value { color: var(--accent); }
  .card-status {
    font-size: 0.7rem; letter-spacing: 0.2em;
    padding: 4px 10px; border-radius: 2px; display: inline-block;
  }
  .card.good   .card-status { background: rgba(0,255,136,0.1); color: var(--accent2); }
  .card.warn   .card-status { background: rgba(255,170,0,0.1);  color: var(--warn); }
  .card.danger .card-status { background: rgba(255,51,85,0.1);   color: var(--danger); }
  .card        .card-status { background: rgba(0,212,255,0.1);   color: var(--accent); }
  .card-raw { position: absolute; bottom: 14px; right: 16px; font-size: 0.6rem; color: var(--dim); }
  .overall {
    max-width: 1000px; margin: 0 auto; border: 1px solid var(--border);
    border-radius: 4px; padding: 20px 28px; display: flex;
    align-items: center; justify-content: space-between; gap: 16px; background: var(--panel);
  }
  .overall-label { font-size: 0.65rem; letter-spacing: 0.25em; color: var(--dim); }
  .overall-value { font-family: 'Orbitron', monospace; font-size: 1.4rem; font-weight: 900; letter-spacing: 0.15em; }
  .overall.good   .overall-value { color: var(--accent2); text-shadow: 0 0 20px rgba(0,255,136,0.4); }
  .overall.warn   .overall-value { color: var(--warn);    text-shadow: 0 0 20px rgba(255,170,0,0.4); }
  .overall.danger .overall-value { color: var(--danger);  text-shadow: 0 0 20px rgba(255,51,85,0.5); }
  .refresh-info { text-align: center; margin-top: 24px; font-size: 0.62rem; color: var(--dim); letter-spacing: 0.15em; }
  #countdown { color: var(--accent); }
</style>
</head>
<body>
<header>
  <h1>AQUALOGIC</h1>
  <p>WATER QUALITY MONITORING SYSTEM</p>
</header>
<div class="status-bar">
  <div class="pulse"></div>
  <span>LIVE DATA — ESP32 SENSOR NODE</span>
</div>
<div class="grid" id="cards"></div>
<div class="overall" id="overall">
  <span class="overall-label">OVERALL WATER STATUS</span>
  <span class="overall-value" id="overall-val">--</span>
</div>
<div class="refresh-info">AUTO-REFRESH IN <span id="countdown">10</span>s</div>
<script>
  async function fetchData() {
    try {
      const res = await fetch('/data');
      const d = await res.json();
      const statusClass = s =>
        s === 'NORMAL' || s === 'CLEAR' || s === 'GOOD'    ? 'good'  :
        s === 'DIRTY'  || s === 'CRITICAL' || s === 'HIGH' ? 'danger' : 'warn';
      const cards = [
        { label: 'TEMPERATURE', value: d.temp_c.toFixed(1) + '°C', status: d.temp_status,       raw: 'DS18B20 Sensor' },
        { label: 'TURBIDITY',   value: d.turbidity_raw,              status: d.turbidity_status,  raw: 'Raw ADC · PIN 34' },
        { label: 'TDS',         value: d.tds_raw,                    status: d.tds_status,        raw: 'Raw ADC · PIN 25' }
      ];
      document.getElementById('cards').innerHTML = cards.map(c => `
        <div class="card ${statusClass(c.status)}">
          <div class="card-label">${c.label}</div>
          <div class="card-value">${c.value}</div>
          <span class="card-status">${c.status}</span>
          <div class="card-raw">${c.raw}</div>
        </div>
      `).join('');
      const overall = document.getElementById('overall');
      overall.className = 'overall ' + statusClass(d.overall_status);
      document.getElementById('overall-val').textContent = d.overall_status;
    } catch (e) { console.warn('Fetch failed', e); }
  }
  let t = 10;
  fetchData();
  setInterval(fetchData, 10000);
  setInterval(() => { t = t <= 1 ? 10 : t - 1; document.getElementById('countdown').textContent = t; }, 1000);
</script>
</body>
</html>
)rawliteral";

// ========================
// Web Handlers
// ========================

void handleRoot() {
  server.send(200, "text/html", DASHBOARD_HTML);
}

void handleData() {
  String json = "{";
  json += "\"temp_c\":"             + String(temperatureC, 2) + ",";
  json += "\"temp_status\":\""      + tempStatus              + "\",";
  json += "\"turbidity_raw\":"      + String(turbidityRaw)    + ",";
  json += "\"turbidity_status\":\"" + turbidityStatus         + "\",";
  json += "\"tds_raw\":"            + String(tdsRaw)          + ",";
  json += "\"tds_status\":\""       + tdsStatus               + "\",";
  json += "\"overall_status\":\""   + overallStatus           + "\"";
  json += "}";
  server.send(200, "application/json", json);
}

// ========================
// Setup
// ========================

void setup() {
  Serial.begin(115200);
  Wire.begin(21, 22);
  lcd.init();
  lcd.backlight();
  sensors.begin();

  lcd.setCursor(0, 0); lcd.print("AquaLogic");
  lcd.setCursor(0, 1); lcd.print("Connecting WiFi");

  WiFi.begin(ssid, password);
  Serial.print("Connecting to WiFi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }

  Serial.println("\nConnected! IP: " + WiFi.localIP().toString());
  lcd.clear();
  lcd.setCursor(0, 0); lcd.print("WiFi OK!");
  lcd.setCursor(0, 1); lcd.print(WiFi.localIP());
  delay(3000);
  lcd.clear();

  server.on("/",     handleRoot);
  server.on("/data", handleData);
  server.begin();
}

// ========================
// Loop
// ========================

void loop() {
  server.handleClient();

  readSensors();
  evaluateTemperature();
  evaluateTurbidity();
  evaluateTDS();
  evaluateOverallStatus();
  serialMonitorOutput();

  displayTemperature();    delay(2500);
  displayTurbidity();      delay(2500);
  displayTDS();            delay(2500);
  displayOverallStatus();  delay(3000);
}

// ========================
// SENSOR READING
// ========================

void readSensors() {
  sensors.requestTemperatures();
  temperatureC = sensors.getTempCByIndex(0);
  turbidityRaw = getAverageAnalog(TURBIDITY_PIN);
  tdsRaw       = getAverageAnalog(TDS_PIN);
}

int getAverageAnalog(int pin) {
  long total = 0;
  for (int i = 0; i < 10; i++) { total += analogRead(pin); delay(10); }
  return total / 10;
}

// ========================
// EVALUATE FUNCTIONS
// ========================

void evaluateTemperature() {
  if (temperatureC == DEVICE_DISCONNECTED_C) tempStatus = "NO SENSOR";
  else if (temperatureC >= 24 && temperatureC <= 30)  tempStatus = "NORMAL";
  else if (temperatureC > 30)  tempStatus = "HIGH";
  else                         tempStatus = "LOW";
}

void evaluateTurbidity() {
  if (turbidityRaw > 2500)       turbidityStatus = "CLEAR";
  else if (turbidityRaw > 1500)  turbidityStatus = "MODERATE";
  else                           turbidityStatus = "DIRTY";
}

void evaluateTDS() {
  if (tdsRaw < 800)        tdsStatus = "LOW";
  else if (tdsRaw <= 2200) tdsStatus = "NORMAL";
  else                     tdsStatus = "HIGH";
}

void evaluateOverallStatus() {
  if (tempStatus == "NORMAL" && turbidityStatus == "CLEAR" && tdsStatus == "NORMAL")
    overallStatus = "GOOD";
  else if (turbidityStatus == "DIRTY" || tdsStatus == "HIGH")
    overallStatus = "CRITICAL";
  else
    overallStatus = "MONITOR";
}

// ========================
// SERIAL OUTPUT
// ========================

void serialMonitorOutput() {
  Serial.println("========== WATER DATA ==========");
  Serial.print("Temperature: "); Serial.print(temperatureC); Serial.print(" C | "); Serial.println(tempStatus);
  Serial.print("Turbidity: ");   Serial.print(turbidityRaw); Serial.print(" | ");   Serial.println(turbidityStatus);
  Serial.print("TDS: ");         Serial.print(tdsRaw);       Serial.print(" | ");   Serial.println(tdsStatus);
  Serial.print("OVERALL STATUS: "); Serial.println(overallStatus);
  Serial.println("================================");
}

// ========================
// LCD DISPLAY FUNCTIONS
// ========================

void displayTemperature() {
  lcd.clear();
  lcd.setCursor(0, 0); lcd.print("Temp:"); lcd.print(temperatureC); lcd.print("C");
  lcd.setCursor(0, 1); lcd.print(tempStatus);
}

void displayTurbidity() {
  lcd.clear();
  lcd.setCursor(0, 0); lcd.print("Turb:"); lcd.print(turbidityRaw);
  lcd.setCursor(0, 1); lcd.print(turbidityStatus);
}

void displayTDS() {
  lcd.clear();
  lcd.setCursor(0, 0); lcd.print("TDS:"); lcd.print(tdsRaw);
  lcd.setCursor(0, 1); lcd.print(tdsStatus);
}

void displayOverallStatus() {
  lcd.clear();
  lcd.setCursor(0, 0); lcd.print("Water Status");
  lcd.setCursor(0, 1); lcd.print(overallStatus);
}
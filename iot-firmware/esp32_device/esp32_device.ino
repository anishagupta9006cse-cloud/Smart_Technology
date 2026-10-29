// ==============================================================================
//  AmbuRoute Smart IoT Device Firmware
//  Target: ESP32 Super Mini (ESP32-C3 SuperMini or Classic ESP32 SuperMini)
//  Components:
//    1. 0.96" I2C OLED Display (SSD1306 128x64, 4-pin: VCC, GND, SCL, SDA)
//    2. Ublox Neo-6M GPS Module (VCC, GND, TX, RX)
//    3. Active / Passive 5V/3.3V Buzzer
//    4. Emergency LED Strobe / Siren Light
//
//  Functionality:
//    - Reads live GPS (Lat, Lng, Speed, Altitude, Satellites) from Neo-6M
//    - Sends telemetry to Backend Server: POST /api/iot/<DEVICE_ID>/telemetry
//    - Receives real-time display messages, buzzer, and LED strobe commands
//    - Displays status & live alerts from Driver App & Police App on 0.96" OLED
//    - Auto-reconnection & 10-second fail-safe audio cutoff
//
//  VERSION 5 (hackathon edition):
//    - TWO device IDs: one for the DRIVER app (ambulance) and one for the POLICE app (post).
//      Commands sent from EITHER app show on this OLED / buzzer.
//    - Optional MAX30102 pulse sensor: heart rate + SpO2 go live to the hospital ER (tele-triage).
//    - Optional railway gate sensor (limit switch): gate OPEN / CLOSED -> ambulance routes avoid closed gates.
// ==============================================================================

#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <TinyGPSPlus.h>
#include <ArduinoJson.h>

// ==============================================================================
// 1. BOARD CONFIGURATION (Select your board type)
// ==============================================================================
// Set to 1 for ESP32-C3 Super Mini (single core RISC-V, 16 pins)
// Set to 0 for Classic ESP32 Super Mini / D1 Mini ESP32 (dual core Tensilica)
#define USE_ESP32_C3_SUPERMINI 1

#if USE_ESP32_C3_SUPERMINI
  // ESP32-C3 Super Mini Pinout:
  #define PIN_I2C_SDA     8
  #define PIN_I2C_SCL     9
  #define PIN_GPS_RX      20    // Connect to Neo-6M TX pin
  #define PIN_GPS_TX      21    // Connect to Neo-6M RX pin (optional)
  #define PIN_BUZZER      3
  #define PIN_LED         4
#else
  // Classic ESP32 Super Mini Pinout:
  #define PIN_I2C_SDA     21
  #define PIN_I2C_SCL     22
  #define PIN_GPS_RX      16    // Connect to Neo-6M TX pin
  #define PIN_GPS_TX      17    // Connect to Neo-6M RX pin (optional)
  #define PIN_BUZZER      25
  #define PIN_LED         26
#endif

// ==============================================================================
// 2. USER CONFIGURATION (WIFI, SERVER, DEVICE ID)
// ==============================================================================
// WiFi Credentials
const char* WIFI_SSID     = "YOUR_WIFI_NAME";
const char* WIFI_PASSWORD = "YOUR_WIFI_PASSWORD";

// Server URL (Can be local server e.g. "http://192.168.1.5:3000" or Cloud URL)
// Do NOT include trailing slash.
const char* SERVER_URL    = "https://smart-technology-ndw9.onrender.com";

// ---- DEVICE IDs (one for EACH app) ----
// AMB_DEVICE_ID    = Device ID used in the DRIVER app  (= ambulance number, example "AMB-101").
//                    GPS of this box moves the ambulance on all maps.
// POLICE_DEVICE_ID = Device ID used in the POLICE app  (= Post ID shown in the police app, example "POST-1").
//                    Leave "" if this box is only in the ambulance.
// Commands from BOTH apps are shown on this OLED / buzzer.
const char* AMB_DEVICE_ID    = "AMB-101";
const char* POLICE_DEVICE_ID = "POST-1";
#define DEVICE_ID AMB_DEVICE_ID   // (old name, kept so old code still compiles)

// Access code (same as in the apps)
const char* ACCESS_CODE   = "Anisha_9631";

// ---- OPTIONAL SENSORS ----
// 1 = MAX30102 pulse-oximeter on I2C (same SDA/SCL as the OLED). Needs library "SparkFun MAX3010x".
#define USE_MAX30102 0
// Railway gate sensor: limit switch between PIN_GATE and GND (closed switch = gate CLOSED).
// Put the crossing ID from the admin page / police app here, or leave "" to switch it off.
const char* RAILWAY_GATE_ID = "";
#define PIN_GATE 5

// ==============================================================================
// 3. HARDWARE & TIMING CONSTANTS
// ==============================================================================
#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
#define OLED_RESET -1
#define OLED_I2C_ADDR 0x3C  // Try 0x3D if your display uses alternative address

Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);
TinyGPSPlus gps;
HardwareSerial gpsSerial(1);

#if USE_MAX30102
  #include "MAX30105.h"
  #include "heartRate.h"
  MAX30105 pulseSensor;
  bool pulseOk = false;
  float beatAvg = 0;
  long lastBeat = 0;
  float spo2Est = 0;
  void readPulse() {
    if (!pulseOk) return;
    long ir = pulseSensor.getIR();
    long red = pulseSensor.getRed();
    if (ir < 50000) { beatAvg = 0; spo2Est = 0; return; }   // no finger
    if (checkForBeat(ir)) {
      long delta = millis() - lastBeat;
      lastBeat = millis();
      float bpm = 60.0 / (delta / 1000.0);
      if (bpm > 30 && bpm < 220) beatAvg = beatAvg == 0 ? bpm : beatAvg * 0.8 + bpm * 0.2;
    }
    // simple ratio estimate (good for demo; use a medical device in real life)
    float ratio = (float)red / (float)ir;
    float s = 110.0 - 25.0 * ratio;
    if (s > 70 && s <= 100) spo2Est = spo2Est == 0 ? s : spo2Est * 0.9 + s * 0.1;
  }
#endif

int lastGateState = -1;
unsigned long lastGateSend = 0;

const unsigned long TELEMETRY_INTERVAL_MS = 1500;  // Send telemetry every 1.5 seconds
const unsigned long FAILSAFE_MS           = 10000; // Silence buzzer & LED if offline > 10s

// Runtime State Variables
unsigned long lastTelemetryTime = 0;
unsigned long lastServerAckTime = 0;
bool isServerConnected = false;

// IoT Command State from Server
bool displayActive = false;
String displayText = "";
String displaySender = "";
bool buzzerActive = false;
String buzzerPattern = "off";  // "beep", "siren", "continuous", "off"
bool ledActive = false;
String ledPattern = "off";     // "strobe", "blink", "solid", "off"
uint32_t currentSeq = 0;

// ==============================================================================
// 4. DISPLAY RENDERING (0.96" OLED SSD1306 128x64)
// ==============================================================================
void renderOLED() {
  display.clearDisplay();
  display.setTextWrap(true);

  // --- Top Status Bar (Height: 12px) ---
  display.fillRect(0, 0, 128, 12, SSD1306_WHITE);
  display.setTextColor(SSD1306_BLACK, SSD1306_WHITE);
  display.setTextSize(1);
  display.setCursor(2, 2);
  // shows the driver-app ID and the police-app ID one after the other
  if (strlen(POLICE_DEVICE_ID) > 0 && (millis() / 3000) % 2 == 1) display.print(POLICE_DEVICE_ID);
  else display.print(AMB_DEVICE_ID);

  // WiFi Indicator
  display.setCursor(58, 2);
  if (WiFi.status() == WL_CONNECTED) {
    display.print("WiFi");
  } else {
    display.print("No-WiFi");
  }

  // GPS Satellite Indicator
  display.setCursor(102, 2);
  if (gps.location.isValid()) {
    display.print(gps.satellites.value());
    display.print("S");
  } else {
    display.print("0S");
  }

  display.setTextColor(SSD1306_WHITE);

  // --- Main Content Area ---
  if (displayActive && displayText.length() > 0) {
    // EMERGENCY / ACTIVE ALERT DISPLAY
    display.setCursor(0, 16);
    display.setTextSize(1);
    display.println(">> EMERGENCY ALERT <<");

    display.setTextSize(1);
    display.setCursor(0, 28);
    // Print message with newline support
    display.println(displayText);

    // Bottom Sender info
    display.setCursor(0, 55);
    display.setTextSize(1);
    if (displaySender.length() > 0) {
      display.print("By: ");
      display.print(displaySender.substring(0, 16));
    } else {
      display.print("Pattern: ");
      display.print(buzzerPattern);
    }
  } else {
    // STANDBY / TELEMETRY MONITOR DISPLAY
    display.setCursor(0, 16);
    display.setTextSize(1);
    display.println("AMBU-ROUTE SYSTEM");

    // Live GPS telemetry
    display.setCursor(0, 28);
    if (gps.location.isValid()) {
      display.print("Lat: ");
      display.println(gps.location.lat(), 4);
      display.print("Lng: ");
      display.println(gps.location.lng(), 4);
      display.print("Spd: ");
      display.print(gps.speed.kmph(), 1);
      display.print(" km/h");
    } else {
      display.println("GPS: Searching Sats...");
      display.println("Waiting for 3D fix");
      display.print("Sats visible: ");
      display.println(gps.satellites.value());
    }

    // Bottom status bar
    display.setCursor(0, 55);
    if (millis() - lastServerAckTime < FAILSAFE_MS && lastServerAckTime > 0) {
      display.print("Server: ONLINE (OK)");
    } else {
      display.print("Server: CONNECTING...");
    }
  }

  display.display();
}

// ==============================================================================
// 5. BUZZER & LED ACTUATION ENGINE
// ==============================================================================
void updateActuators() {
  unsigned long nowMs = millis();
  bool failsafeActive = (lastServerAckTime > 0 && (nowMs - lastServerAckTime > FAILSAFE_MS));

  // --- Buzzer Control ---
  bool buzzState = false;
  if (buzzerActive && !failsafeActive) {
    if (buzzerPattern == "continuous") {
      buzzState = true;
    } else if (buzzerPattern == "siren") {
      // Rapid siren alternation (120ms cycle)
      buzzState = ((nowMs / 120) % 2 == 0);
    } else if (buzzerPattern == "beep") {
      // Standard beep (250ms on / 250ms off)
      buzzState = ((nowMs / 250) % 2 == 0);
    }
  }
  digitalWrite(PIN_BUZZER, buzzState ? HIGH : LOW);

  // --- LED Light Strobe Control ---
  bool ledState = false;
  if (ledActive && !failsafeActive) {
    if (ledPattern == "solid") {
      ledState = true;
    } else if (ledPattern == "strobe") {
      // Emergency vehicle quad-pulse strobe (800ms period)
      unsigned long phase = nowMs % 800;
      if ((phase >= 0 && phase < 50) || (phase >= 100 && phase < 150) ||
          (phase >= 200 && phase < 250) || (phase >= 300 && phase < 350)) {
        ledState = true;
      }
    } else if (ledPattern == "blink") {
      // Synchronous blink (250ms cycle)
      ledState = ((nowMs / 250) % 2 == 0);
    }
  } else if (!ledActive && buzzState) {
    // If buzzer is ringing but no specific LED pattern requested, blink LED with buzzer
    ledState = buzzState;
  }
  digitalWrite(PIN_LED, ledState ? HIGH : LOW);
}

// ==============================================================================
// 6. WIFI RECONNECTION
// ==============================================================================
void checkWiFi() {
  if (WiFi.status() == WL_CONNECTED) return;
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  unsigned long start = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - start < 6000) {
    delay(200);
  }
}

// ==============================================================================
// 7. GPS TELEMETRY & COMMAND SYNC (HTTP POST)
// ==============================================================================
void syncTelemetryAndCommands() {
  checkWiFi();
  if (WiFi.status() != WL_CONNECTED) return;

  WiFiClientSecure secureClient;
  secureClient.setInsecure(); // Permits self-signed & cloud HTTPS certificates

  HTTPClient http;
  String endpoint = String(SERVER_URL) + "/api/iot/" + AMB_DEVICE_ID + "/telemetry";

  if (!http.begin(secureClient, endpoint)) return;
  http.setTimeout(4000);
  http.addHeader("Content-Type", "application/json");
  if (strlen(ACCESS_CODE) > 0) {
    http.addHeader("x-access-code", ACCESS_CODE);
  }

  // Build telemetry JSON payload
  JsonDocument outDoc;
  outDoc["deviceId"] = AMB_DEVICE_ID;
  outDoc["policeDeviceId"] = POLICE_DEVICE_ID;
  bool hasFix = gps.location.isValid();
  outDoc["fix"] = hasFix;

  if (hasFix) {
    outDoc["lat"]      = gps.location.lat();
    outDoc["lng"]      = gps.location.lng();
    outDoc["speed"]    = gps.speed.kmph();
    outDoc["altitude"] = gps.altitude.meters();
    outDoc["hdop"]     = gps.hdop.hdop();
  } else {
    outDoc["lat"]      = nullptr;
    outDoc["lng"]      = nullptr;
    outDoc["speed"]    = 0;
    outDoc["altitude"] = 0;
    outDoc["hdop"]     = 99.0;
  }
  outDoc["sats"] = gps.satellites.value();
#if USE_MAX30102
  if (beatAvg > 0) outDoc["hr"] = (int)beatAvg;
  if (spo2Est > 0) outDoc["spo2"] = (int)spo2Est;
#endif

  String requestBody;
  serializeJson(outDoc, requestBody);

  int httpCode = http.POST(requestBody);
  if (httpCode == 200) {
    String responseBody = http.getString();
    JsonDocument inDoc;
    DeserializationError err = deserializeJson(inDoc, responseBody);

    if (!err) {
      lastServerAckTime = millis();
      isServerConnected = true;

      // Parse Display Instructions
      displayActive = inDoc["display"]["on"] | false;
      displayText   = inDoc["display"]["text"] | "";
      displaySender = inDoc["display"]["by"] | "";

      // Parse Buzzer Instructions
      buzzerActive  = inDoc["buzzer"]["on"] | false;
      buzzerPattern = String((const char*)(inDoc["buzzer"]["pattern"] | "off"));

      // Parse LED Light Instructions
      ledActive     = inDoc["led"]["on"] | false;
      ledPattern    = String((const char*)(inDoc["led"]["pattern"] | "off"));

      currentSeq    = inDoc["seq"] | 0;
    }
  } else {
    isServerConnected = false;
  }
  http.end();
}

// Police app device: download its commands too (display / buzzer / LED). Either app can switch the box on.
void syncPoliceDevice() {
  if (strlen(POLICE_DEVICE_ID) == 0 || WiFi.status() != WL_CONNECTED) return;
  WiFiClientSecure secureClient;
  secureClient.setInsecure();
  HTTPClient http;
  String endpoint = String(SERVER_URL) + "/api/iot/" + POLICE_DEVICE_ID + "/state";
  if (!http.begin(secureClient, endpoint)) return;
  http.setTimeout(4000);
  if (strlen(ACCESS_CODE) > 0) http.addHeader("x-access-code", ACCESS_CODE);
  if (http.GET() == 200) {
    JsonDocument d;
    if (!deserializeJson(d, http.getString())) {
      lastServerAckTime = millis();
      bool pDisp = d["display"]["on"] | false;
      if (pDisp) {
        displayActive = true;
        displayText = d["display"]["text"] | "";
        displaySender = String("Police: ") + String((const char*)(d["display"]["by"] | ""));
      }
      bool pBuzz = d["buzzer"]["on"] | false;
      if (pBuzz) { buzzerActive = true; buzzerPattern = String((const char*)(d["buzzer"]["pattern"] | "beep")); }
      bool pLed = d["led"]["on"] | false;
      if (pLed) { ledActive = true; ledPattern = String((const char*)(d["led"]["pattern"] | "strobe")); }
    }
  }
  http.end();
}

// Railway gate sensor -> server (only when the state changes, or every 60 s as a heartbeat)
void syncRailwayGate() {
  if (strlen(RAILWAY_GATE_ID) == 0 || WiFi.status() != WL_CONNECTED) return;
  int closed = digitalRead(PIN_GATE) == LOW ? 1 : 0;
  if (closed == lastGateState && millis() - lastGateSend < 60000) return;
  WiFiClientSecure secureClient;
  secureClient.setInsecure();
  HTTPClient http;
  String endpoint = String(SERVER_URL) + "/api/railway/" + RAILWAY_GATE_ID + "/status";
  if (!http.begin(secureClient, endpoint)) return;
  http.setTimeout(4000);
  http.addHeader("Content-Type", "application/json");
  if (strlen(ACCESS_CODE) > 0) http.addHeader("x-access-code", ACCESS_CODE);
  String body = String("{\"status\":\"") + (closed ? "closed" : "open") + "\",\"by\":\"IoT gate sensor\"}";
  if (http.POST(body) == 200) { lastGateState = closed; lastGateSend = millis(); }
  http.end();
}

// ==============================================================================
// 8. SETUP & INITIALIZATION
// ==============================================================================
void setup() {
  Serial.begin(115200);

  // Setup Outputs
  pinMode(PIN_BUZZER, OUTPUT);
  pinMode(PIN_LED, OUTPUT);
  digitalWrite(PIN_BUZZER, LOW);
  digitalWrite(PIN_LED, LOW);

  // Startup Beep & LED Flash Test
  digitalWrite(PIN_LED, HIGH);
  digitalWrite(PIN_BUZZER, HIGH);
  delay(100);
  digitalWrite(PIN_LED, LOW);
  digitalWrite(PIN_BUZZER, LOW);

  // Setup I2C & OLED Display
  Wire.begin(PIN_I2C_SDA, PIN_I2C_SCL);
  if (!display.begin(SSD1306_SWITCHCAPVCC, OLED_I2C_ADDR)) {
    Serial.println("Warning: OLED not found at 0x3C, trying 0x3D...");
    display.begin(SSD1306_SWITCHCAPVCC, 0x3D);
  }

  display.clearDisplay();
  display.setTextColor(SSD1306_WHITE);
  display.setTextSize(1);
  display.setCursor(0, 10);
  display.println("AmbuRoute Smart IoT");
  display.println("ESP32 Super Mini");
  display.println("Connecting WiFi...");
  display.display();

#if USE_MAX30102
  pulseOk = pulseSensor.begin(Wire, I2C_SPEED_FAST);
  if (pulseOk) { pulseSensor.setup(); pulseSensor.setPulseAmplitudeRed(0x0A); }
#endif
  pinMode(PIN_GATE, INPUT_PULLUP);

  // Setup Neo-6M GPS UART
  gpsSerial.begin(9600, SERIAL_8N1, PIN_GPS_RX, PIN_GPS_TX);

  // WiFi Init
  checkWiFi();

  display.setCursor(0, 45);
  display.println(WiFi.status() == WL_CONNECTED ? "WiFi: Connected!" : "WiFi: Retrying...");
  display.display();
  delay(800);
}

// ==============================================================================
// 9. MAIN LOOP (NON-BLOCKING)
// ==============================================================================
void loop() {
  // Feed GPS Serial buffer continuously
  while (gpsSerial.available() > 0) {
    gps.encode(gpsSerial.read());
  }

  // Periodic Telemetry Upload & Command Fetch
  if (millis() - lastTelemetryTime >= TELEMETRY_INTERVAL_MS) {
    lastTelemetryTime = millis();
    syncTelemetryAndCommands();   // driver app device (GPS + its commands)
    syncPoliceDevice();           // police app device (its commands)
    syncRailwayGate();            // optional railway gate sensor
  }
#if USE_MAX30102
  readPulse();
#endif

  // Update physical actuators (Buzzer & LED)
  updateActuators();

  // Refresh OLED Display (every 250ms for smooth animation & live GPS)
  static unsigned long lastDisplayRender = 0;
  if (millis() - lastDisplayRender >= 250) {
    lastDisplayRender = millis();
    renderOLED();
  }
}

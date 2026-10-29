# AmbuRoute Smart IoT Kit Guide
### Hardware: ESP32 Super Mini, 0.96" OLED (SSD1306), Ublox Neo-6M GPS, Buzzer & LED Light

---

## 1. Overview & System Architecture
```
[ Neo-6M GPS ] -----> (Live Lat/Lng/Speed)
                           |
                           v
                   [ ESP32 Super Mini ] <=====(WiFi/HTTPS)=====> [ Backend Server ]
                     /     |      \                                    ^
                    /      |       \                                   |
                   v       v        v                                  v
              [ 0.96" ] [Buzzer]  [LED]                     [ Driver App & Police App ]
               OLED      Siren   Strobe                     (Controls & Health Dashboard)
```
1. **Live GPS Tracking**: The Neo-6M module sends latitude, longitude, speed, and satellites to the ESP32.
2. **Server Sync (POST `/api/iot/<DEVICE_ID>/telemetry`)**: Every 1.5 seconds, the ESP32 sends telemetry to the server. If this is an ambulance device (e.g., `AMB-101`), the server automatically moves the live ambulance on the driver and police maps!
3. **Emergency Alerts & Text Display**: In the same response, the server returns active alert text, buzzer patterns, and LED strobe commands from Driver or Police apps, rendering immediately on the 0.96" OLED screen.
4. **Auto-Mode for Police Post**: When an approaching ambulance is within range, the server automatically displays `AMBULANCE COMING / CLEAR THE ROAD`, sounds the siren, and strobes the LED.

---

## 2. Complete Wiring Diagram

### Pin Connections for **ESP32-C3 Super Mini** (Most Common SuperMini)
*(Set `#define USE_ESP32_C3_SUPERMINI 1` in `esp32_device.ino`)*

| Component | Pin on Module | Connect to ESP32-C3 Super Mini Pin | Notes |
| :--- | :--- | :--- | :--- |
| **0.96" OLED (SSD1306)** | **VCC** | **3.3V or 5V** | Power (most have onboard 3.3V regulator) |
| | **GND** | **GND** | Ground |
| | **SCL** | **GPIO 9** | Hardware I2C Clock |
| | **SDA** | **GPIO 8** | Hardware I2C Data |
| **Ublox Neo-6M GPS** | **VCC** | **3.3V or 5V** | Power |
| | **GND** | **GND** | Ground |
| | **TX** | **GPIO 20** | GPS Serial Output -> ESP32 RX |
| | **RX** | **GPIO 21** | Optional (leave disconnected or to GPIO 21) |
| **Active Buzzer** | **(+) Positive** | **GPIO 3** | Audio signal |
| | **(-) Negative** | **GND** | Ground |
| **LED Light** | **(+) Anode** | **GPIO 4** (via 220Ω resistor) | Strobe / Siren Light |
| | **(-) Cathode**| **GND** | Ground |

---

### Alternative Pin Connections for **Classic ESP32 Super Mini / D1 Mini**
*(Set `#define USE_ESP32_C3_SUPERMINI 0` in `esp32_device.ino`)*

| Component | Pin on Module | Connect to Classic ESP32 Pin |
| :--- | :--- | :--- |
| **0.96" OLED** | **SCL / SDA** | **GPIO 22 (SCL) / GPIO 21 (SDA)** |
| **Neo-6M GPS** | **TX / RX** | **GPIO 16 (RX2) / GPIO 17 (TX2)** |
| **Buzzer** | **(+) / (-)** | **GPIO 25 / GND** |
| **LED Light** | **(+) / (-)** | **GPIO 26 / GND** |

---

## 3. Arduino IDE Setup & Flashing Instructions

### Step 1: Install ESP32 Board Package
1. Open **Arduino IDE** -> `File` -> `Preferences`.
2. In *Additional Boards Manager URLs*, add:
   ```
   https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
   ```
3. Go to `Tools` -> `Board` -> `Boards Manager...`, search for **esp32** by Espressif and click **Install**.
4. Select your board:
   - For ESP32-C3 Super Mini: Select **ESP32C3 Dev Module**.
   - For Classic Super Mini: Select **ESP32 Dev Module**.

### Step 2: Install Required Libraries
Open `Sketch` -> `Include Library` -> `Manage Libraries...` and install:
1. **Adafruit SSD1306** (by Adafruit) *(install dependencies like Adafruit GFX when prompted)*
2. **Adafruit GFX Library** (by Adafruit)
3. **TinyGPSPlus** (by Mikal Hart)
4. **ArduinoJson** (by Benoit Blanchon, v6 or v7)

### Step 3: Configure `esp32_device.ino`
Open `iot-firmware/esp32_device/esp32_device.ino`:
```cpp
const char* WIFI_SSID     = "Your_WiFi_Name";
const char* WIFI_PASSWORD = "Your_WiFi_Password";
const char* SERVER_URL    = "https://smart-ambulance-mk2n.onrender.com"; // Or your local IP http://192.168.x.x:3000
const char* DEVICE_ID     = "AMB-101"; // Or your Police Post ID e.g. "POST-1"
```

### Step 4: Upload Code to ESP32 Super Mini
1. Connect ESP32 Super Mini via USB-C cable to your computer.
2. Select COM Port in `Tools` -> `Port`.
3. *(If using ESP32-C3: in Tools, set "USB CDC On Boot" to Enabled).*
4. Click **Upload** (Arrow icon).

---

## 4. Testing Your Hardware Bench

1. **Power Up**:
   - The buzzer will give a short 100ms beep and LED flashes once.
   - The 0.96" OLED screen will illuminate showing:
     ```
     AmbuRoute Smart IoT
     ESP32 Super Mini
     Connecting WiFi...
     ```
   - Once connected, top bar shows: `[AMB-101] [WiFi] [0S]`
2. **GPS Fix**:
   - Indoors, GPS may show `GPS: Searching Sats... Waiting for 3D fix`.
   - Place near a window for 1-2 minutes until satellite count changes to e.g. `[7S]` and live `Lat`, `Lng`, and `Spd` appear!
   - *Note*: Even with 0 satellites indoors, the display and buzzer communication with the server and mobile apps works 100%!
3. **Send Message from Police App or Driver App**:
   - Open Driver App or Police App -> Tap **IOT CONTROL**.
   - The device card will show **Device is online** with live GPS coordinates, speed, and satellites!
   - Tap preset message `CLEAR THE ROAD` -> The 0.96" OLED instantly displays:
     ```
     >> EMERGENCY ALERT <<
     CLEAR THE ROAD
     EMERGENCY
     By: SI Sharma
     ```
   - The buzzer sounds the siren and the LED light strobes!
4. **Automatic Failsafe**:
   - If WiFi or server drops, buzzer & LED turn off automatically after 10 seconds to protect hardware.

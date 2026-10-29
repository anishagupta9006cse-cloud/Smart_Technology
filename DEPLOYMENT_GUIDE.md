# AmbuRoute - Deployment & Folder Structure Guide

This guide clearly explains which folder deploys to **Render**, **Vercel**, **GitHub**, and how the **Android APKs** are built.

---

## 1. Clean Folder Structure Overview

```
Smart_Ambulance/
│
├── ambulance-server/          <=== [DEPLOY TO RENDER / VERCEL]
│   ├── server.js              (Main Node.js Express server)
│   ├── iot.js                 (IoT Telemetry & Command engine)
│   ├── engine.js              (Real-time ambulance trip & police post alert engine)
│   ├── routing.js             (OSRM / OpenStreetMap routing & fallback routing)
│   ├── places.js              (Hospital & police station database)
│   ├── vercel.json            (Configuration to deploy to Vercel)
│   ├── package.json           (Node.js dependencies)
│   └── public/                (Admin dashboard website at /admin)
│
├── ambulance_alert_app/       <=== [MOBILE APPS - FLUTTER]
│   ├── driver_app/            (Ambulance Driver App - Pre Bed Booked, Gate Kit Check, IoT Control)
│   ├── police_app/            (Police Post App - Incoming ambulance siren alert & IoT Control)
│   └── tools/                 (Android manifest permission patchers)
│
├── iot-firmware/              <=== [HARDWARE FIRMWARE - ARDUINO IDE]
│   └── esp32_device/
│       └── esp32_device.ino   (Firmware for ESP32 Super Mini, Neo-6M GPS, 0.96" OLED, Buzzer, LED)
│
├── .github/workflows/         <=== [GITHUB ACTIONS CI/CD]
│   └── build-apk.yml          (Automatically builds Driver & Police APKs on git push)
│
├── IOT_GUIDE.md               (Pin wiring & hardware setup manual)
├── DEPLOYMENT_GUIDE.md        (This file - Deployment instructions)
└── README.md                  (Project overview)
```

---

## 2. Deploying the Backend Server

You can deploy the backend to **Render** (recommended for persistent connections) OR to **Vercel**.

### A. Deploy on Render (Recommended)
1. Log in to [dashboard.render.com](https://dashboard.render.com).
2. Click **New +** -> **Web Service**.
3. Connect your GitHub repository.
4. Set the following settings:
   - **Name**: `smart-ambulance-api` (or your choice)
   - **Root Directory**: `ambulance-server`
   - **Environment**: `Node`
   - **Build Command**: `npm install`
   - **Start Command**: `node server.js`
   - **Plan**: `Free`
5. Click **Create Web Service**.
6. Once deployed, Render will give you a URL like:
   `https://smart-ambulance-api.onrender.com`
7. Copy this URL and update it in:
   - `ambulance-server/.env` (optional)
   - `ambulance_alert_app/driver_app/lib/config.dart` (`defaultServer`)
   - `ambulance_alert_app/police_app/lib/config.dart` (`defaultServer`)
   - `iot-firmware/esp32_device/esp32_device.ino` (`SERVER_URL`)

---

### B. Deploy on Vercel
1. Log in to [vercel.com](https://vercel.com).
2. Click **Add New...** -> **Project**.
3. Import your GitHub repository.
4. In **Root Directory**, click *Edit* and select: `ambulance-server`.
5. In **Framework Preset**, select **Other**.
   *(Vercel will automatically use the included `vercel.json` file).*
6. Click **Deploy**.
7. Your backend API and `/admin` panel will be live on your Vercel URL!

---

## 3. Pushing the Project to GitHub

To push your clean codebase to GitHub:

1. Open PowerShell or Terminal in `Smart_Ambulance`:
   ```powershell
   git init
   git add .
   git commit -m "Clean project: ESP32 Super Mini IoT, Pre Bed Booked, Gate Kit Check, and deployment configs"
   git branch -M main
   git remote add origin https://github.com/YOUR_USERNAME/YOUR_REPOSITORY.git
   git push -u origin main
   ```

---

## 4. How the Android APKs are Built

### Method 1: Automatic Build via GitHub Actions (No local Android Studio needed!)
The repository contains `.github/workflows/build-apk.yml`.
1. As soon as you push your code to GitHub (`main` branch):
2. GitHub automatically launches an Ubuntu runner with Flutter & Android SDK.
3. It builds:
   - `driver_app-apk` (Release APK for Driver App)
   - `police_app-apk` (Release APK for Police App)
4. Go to your GitHub repository -> **Actions** tab -> Click the latest run -> Download the ready-to-install `.apk` files directly to your phone!

### Method 2: Local Build with Flutter SDK
If you have Flutter installed locally:
```powershell
# Build Driver App APK
cd ambulance_alert_app/driver_app
flutter pub get
flutter build apk --release

# Build Police App APK
cd ../police_app
flutter pub get
flutter build apk --release
```
The generated APKs will be in `build/app/outputs/flutter-apk/app-release.apk`.

---

## 5. Flashing the IoT Hardware

1. Open **Arduino IDE**.
2. Install libraries: `Adafruit SSD1306`, `Adafruit GFX Library`, `TinyGPSPlus`, `ArduinoJson`.
3. Open `iot-firmware/esp32_device/esp32_device.ino`.
4. Update your WiFi SSID, Password, and your Render/Vercel server URL.
5. Select board `ESP32C3 Dev Module` (or `ESP32 Dev Module`) and click **Upload**.

# AmbuRoute — Version 5 (Hackathon Edition)

Server default: `https://smart-technology-ndw9.onrender.com` · Access code default: `Anisha_9631`
(both are already inside the Driver, Police and Hospital apps and the ESP32 firmware — nobody types them).

## 60-second demo for judges
1. Open `https://smart-technology-ndw9.onrender.com/admin/live` → admin code `Anisha_9631`
   (or the `ADMIN_CODE` you set on Render).
2. Tab **Demo** → choose *Cardiac* → **Start demo ambulance**.
   The system makes 4 demo hospitals, 2 railway gates (1 CLOSED), pothole data and a moving ambulance.
3. Watch: the ambulance moves, green-corridor signals turn **GREEN → PREPARE → normal**, live vitals
   turn RED (STEMI), and the AI picks the **cardiac** hospital (not the nearest one, whose ICU is full).
4. Click **Open ER screen** → the hospital's big screen with vitals, ETA, BED READY / NO BED buttons and voice.
5. Open `/sos` on a phone → press SOS → the driver app shows *SOS NEAR YOU* → ACCEPT.

## What was added

| # | Feature | Where |
|---|---------|-------|
| 1 | **Push alerts when the app is closed** — background service in Police + Hospital apps (loud notification + voice), plus free *ntfy* push (menu → *Push alerts when app is closed*) | `bg_alerts.dart`, `features.js` |
| 2 | **Auto BEST hospital** — score = ETA + ICU bed + oxygen + emergency doctor + ventilator + blood + specialty (cardiac / trauma / stroke / burn / child / pregnancy) | Driver → **SMART AI**, `GET /api/hospitals/best` |
| 3 | **Personal OTP login** for every driver, officer and hospital. Admin can add/block numbers. Demo mode shows the OTP in the app when no SMS service is set (Fast2SMS / Twilio supported). `REQUIRE_OTP=true` switches the shared code off | `auth.js`, `otp_login.dart`, Command centre → *OTP users* |
| 4 | **Admin live map** — all ambulances, routes, hospitals (ready colour), police posts, railway gates, potholes, SOS, push log; **response-time report** (trips/day, avg minutes, golden-hour %, per ambulance, per emergency type) | `/admin/live` |
| 5 | **Offline mode** — last route saved on the phone; GPS points saved without network (also after restart) and uploaded together when the network returns | `offline.dart`, `POST /api/trips/:id/locations` |
| 6 | **In-transit vitals & tele-triage** — paramedic enters HR, SpO2, BP, breathing, temp, sugar, GCS, ECG; RED / YELLOW / GREEN; hospital app + ER screen show it live; RED = voice + push alert to the hospital | Driver → **PATIENT VITALS**, `/er/<hospitalId>` |
| 7 | **Hospital specialties + blood groups** — hospital app now sets which specialists are on duty | Hospital app |
| 8 | **Pothole-aware SMOOTHEST route** — phone accelerometer in every ambulance crowdsources bumps; server compares up to 4 routes and picks fastest or smoothest | `road_sensor.dart`, `roads.js`, `routing.js` |
| 9 | **Railway gates OPEN / CLOSED** — police app screen, ESP32 gate sensor, admin; routes avoid CLOSED gates; narrow lanes reported by drivers are also avoided | Police → menu → *Railway gates* |
| 10 | **Green corridor simulation** — every junction on the route shows GREEN (≤500 m), PREPARE (≤1.5 km), normal, restored after passing | Live map, `GET /api/trips/:id/corridor` |
| 11 | **Public SOS** (extra) — anyone opens `/sos`, presses SOS, nearest ambulance accepts, the person sees the ambulance coming live | `/sos` |
| 12 | **One-click demo simulator** (extra) | Live map → Demo |
| 13 | **ESP32: two device IDs** (driver app + police app on one box), optional MAX30102 pulse sensor → live vitals, optional railway gate sensor | `iot-firmware/esp32_device/esp32_device.ino`, `IOT_GUIDE.md` |
| 14 | **APK build: every app has its own device / package ID** in BOTH workflow files (`com.amburoute.driver`, `.police`, `.hospital`) | `.github/workflows/build-apk.yml`, `ambulance_alert_app/.github/workflows/build-apks.yml` |

Already in version 4 (kept and connected to the new features): hospital ICU / oxygen status, BED READY / NO BED /
PLEASE CALL with voice, FIND ANOTHER HOSPITAL, family live link (no driver name / phone, closes after the trip).

## New server settings (Render → Environment) — all optional
`ADMIN_CODE`, `REQUIRE_OTP`, `OTP_SELF_SIGNUP`, `FAST2SMS_API_KEY` or `TWILIO_SID/TWILIO_TOKEN/TWILIO_FROM`,
`NTFY_ENABLED`, `NTFY_URL`, `PUSH_SALT` — see `ambulance-server/.env.example`.

## Tests
`cd ambulance-server && npm test` — runs the old tests + `test-features.js` (OTP, best hospital, vitals triage,
offline batch, railway penalty, pothole filter, SOS, live map, pages).

## More ideas for later
- Real traffic-signal control (needs city permission + signal controller API) — today it is a simulation.
- Firebase Cloud Messaging push (needs your own Firebase project + `google-services.json`).
- Hindi / Bhojpuri voice and screens.
- AI ETA model trained on your own trip history (time of day, area).
- Blood bank stock link (eRaktKosh) and Ayushman Bharat card check on arrival.
- Drone first-aid kit for blocked roads; bike-ambulance for narrow lanes.
- Paid map service (Google / MapmyIndia) for real road width and live traffic.
- Release signing key + Play Store listing; iOS build.

## Honest limits
- The apps do not switch real traffic lights; the green corridor is a simulation + police alerts.
- Pothole data improves only as more ambulances drive with the app.
- Background alerts depend on Android battery settings: allow "no battery restriction" when the app asks.
- Demo mode shows the OTP on screen — set an SMS key before real use.

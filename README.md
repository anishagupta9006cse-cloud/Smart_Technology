# AmbuRoute Alert AI - Driver + Police + Hospital apps + Server (version 5 — hackathon edition)

> **NEW in version 5 → read `FEATURES_V5.md`.** Quick demo for judges: open `https://<your-server>/admin/live`,
> enter the admin code, tab **Demo** → **Start demo ambulance**.

Folders:
- `ambulance-server/`    -> Node.js server for Render (database, admin page, alert engine)
- `ambulance_alert_app/` -> Flutter apps (`driver_app`, `police_app`) + GitHub Actions APK build
- `places_template.csv`  -> example file for adding many local places at once
- `SETUP_GUIDE.md`       -> step by step setup for beginners (START HERE)
- `USER_MANUAL.md`       -> manual for drivers, police and admin
- `SUGGESTIONS.md`       -> what is still missing in the project and what to do next

What is new:
1. All app text is simple English. Every button has its own color.
2. Saved local places database: search finds your own hospitals, chowks, markets first.
3. Drivers can tap the map and save a missing place from the app.
4. MongoDB database: places, police posts, ambulances and trip history are saved permanently.
5. Admin page (`/admin`) to enter and edit all data.
6. "How to use" screen inside both apps.

## Version 3 additions
* IoT control (display + buzzer) from both apps, see `IOT_GUIDE.md` and `iot-firmware/`.
* Police app: live ambulance markers + route on the map, ambulance speed, per-button sending (buttons no longer hang).
* Driver app: all online police posts on the map, critical-patient switch, quick messages to police, nearest-hospital button.
* Default server address was changed in version 4 (see below).

## Version 4 additions
1. **Default server + access code.** Both apps (and the new Hospital app) already contain
   `https://smart-technology-ndw9.onrender.com` and the access code. Nobody types them any more.
   Old phones that saved an older server address are moved to the new one automatically.
   > On Render, set **both** `DRIVER_CODE` and `POLICE_CODE` to the same access code
   > (or leave both empty). The hospital app works with either code.
2. **Hospital app (`ambulance_alert_app/hospital_app`)** - the hospital enters ICU beds free, oxygen
   (available / low / none), ventilators, emergency doctor, blood. It also sees every ambulance that is
   coming (ETA, patient brief) and answers with **BED READY / NO BED / PLEASE CALL**.
3. **Driver app** - new screen *Hospitals: ICU & Oxygen (live)*: best hospitals first (green = ICU bed free +
   oxygen + doctor), **GO HERE** sets the route, **CALL** dials the hospital. The hospital's answer
   shows on the trip screen and is read aloud.
4. **Live link for family** - driver taps **FAMILY LINK** and sends it on WhatsApp. The family opens it in any
   browser (no app, no login) and sees the ambulance, route, ETA and speed. The link stops working after the trip.
5. **Fixed app IDs** - each APK has its own Android app ID: `com.amburoute.driver`, `com.amburoute.police`,
   `com.amburoute.hospital`. All three can be installed on one phone. GitHub Actions builds all three APKs.

New server endpoints: `/api/hospitals/register|live|:id|:id/status|:id/incoming|:id/respond`,
`/api/trips/:id/share`, public `/track/:token` and `/api/track/:token`.
Run `npm test` inside `ambulance-server` to test everything (includes `test-hospitals.js`).

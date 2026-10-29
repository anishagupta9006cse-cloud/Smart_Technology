# What is missing and what to do next

## Must do before real use
1. **Push alerts when the police app is closed.** Today police only get alerts while the app is open. Add Firebase Cloud Messaging (FCM) notifications.
2. **Real login.** Access codes are off by default, so anyone who knows the server address can send fake alerts. Give each driver and officer their own login (the admin page already stores ambulances).
3. **Better map and route service.** The free OSRM, Nominatim and OpenStreetMap tile servers are for demos only and can block heavy use. Use a paid or self-hosted service for real use.
4. **Paid always-on server.** The free Render server sleeps and the first request takes up to 1 minute.
5. **Test on real roads** with a real ambulance and police phones. Only the alert engine and server have automatic tests; the Flutter apps have none.

## Good improvements
- ~~Hospital details: phone number, emergency beds, "Call hospital" button.~~ Done in version 4 (Hospital app).
- Automatic "nearest READY hospital" button (nearest hospital that has an ICU bed and oxygen).
- iOS version (only Android is built now).
- Release signing key and Play Store listing.
- Hindi language option.
- Trip reports and charts in the admin page (trip history is already saved).
- Auto-delete old location data to protect privacy.
- Offline map tiles for weak network areas.
- Rate-limit and logging dashboard.

## Limits to tell people honestly
- The apps do NOT change traffic signals. They only inform police.
- Alerts depend on phone GPS and internet signal.

## More feature ideas (after version 4)
- **Push notifications** (FCM) for hospital and police apps, so alerts arrive even when the app is closed.
- **Auto-pick best hospital**: score = ETA + ICU bed + oxygen + specialty (cardiac, trauma, stroke).
- **Patient pre-alert card**: age, pulse, BP, SpO2, blood group sent to the hospital before arrival.
- **SOS button for the public**: a person in an accident taps SOS, the nearest ambulance is alerted.
- **SMS fallback** for the family link when there is no internet.
- **Admin dashboard**: live map of all ambulances, response-time reports, hospital readiness history.
- **Hospital status reminders**: ask the hospital to confirm numbers every 2-3 hours (the app already warns).
- **Ambulance fuel / oxygen / kit checklist** shown to the hospital before dispatch.
- **Multi-language voice alerts** (Hindi, Bhojpuri) for drivers and police.
- **Offline mode**: save the last route and keep sending GPS when the network returns.
- **Login with OTP** per driver / officer / hospital instead of one shared access code.

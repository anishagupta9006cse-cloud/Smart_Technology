#!/usr/bin/env python3
"""Adds permissions and the app name to AndroidManifest.xml (runs after flutter create).
Also sets a fixed Android app ID (package name) so Driver, Police and Hospital apps are
three different apps that can all be installed on the same phone.
Usage: patch_android.py <AndroidManifest.xml> "<App Label>" [<app id, example com.amburoute.driver>]
"""
import os
import re
import sys

path, label = sys.argv[1], sys.argv[2]
app_id = sys.argv[3] if len(sys.argv) > 3 else ""
s = open(path, encoding="utf-8").read()

perms = [
    "android.permission.INTERNET",
    "android.permission.ACCESS_NETWORK_STATE",
    "android.permission.ACCESS_FINE_LOCATION",
    "android.permission.ACCESS_COARSE_LOCATION",
    "android.permission.FOREGROUND_SERVICE",
    "android.permission.FOREGROUND_SERVICE_LOCATION",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.WAKE_LOCK",
    "android.permission.VIBRATE",
]
add = ""
for p in perms:
    if p not in s:
        add += f'    <uses-permission android:name="{p}"/>\n'
if add:
    s = s.replace("<application", add + "    <application", 1)

# Things the app asks Android to open (required on Android 11+):
# text-to-speech, phone dialer (call hospital), web links (WhatsApp share)
wanted = {
    "TTS_SERVICE": '<intent><action android:name="android.intent.action.TTS_SERVICE"/></intent>',
    "android.intent.action.DIAL": '<intent><action android:name="android.intent.action.DIAL"/><data android:scheme="tel"/></intent>',
    'android:scheme="https"': '<intent><action android:name="android.intent.action.VIEW"/><data android:scheme="https"/></intent>',
}
for key, tag in wanted.items():
    if key in s:
        continue
    if "<queries>" in s:
        s = s.replace("<queries>", "<queries>\n        " + tag, 1)
    else:
        s = s.replace("</manifest>", "    <queries>\n        " + tag + "\n    </queries>\n</manifest>", 1)

# App name
s = re.sub(r'android:label="[^"]*"', f'android:label="{label}"', s, count=1)

open(path, "w", encoding="utf-8").write(s)
print("Manifest patched:", label)

# Fixed Android app ID (package name). Each app has its own, so they never replace each other.
if app_id:
    app_dir = os.path.normpath(os.path.join(os.path.dirname(path), "..", ".."))  # android/app
    done = False
    for name in ("build.gradle.kts", "build.gradle"):
        gp = os.path.join(app_dir, name)
        if not os.path.exists(gp):
            continue
        g = open(gp, encoding="utf-8").read()
        g2, n = re.subn(r'applicationId\s*=?\s*"[^"]*"', f'applicationId = "{app_id}"', g, count=1)
        if n:
            open(gp, "w", encoding="utf-8").write(g2)
            print("App ID set:", app_id, "in", name)
            done = True
            break
    if not done:
        print("ERROR: could not find applicationId in android/app/build.gradle(.kts)")
        sys.exit(1)

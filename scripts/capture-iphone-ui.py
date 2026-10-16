#!/usr/bin/env python3
"""Capture only the dedicated R simulator, using account-free preview entry points."""
import os
import plistlib
from pathlib import Path
import subprocess
import sys
import time
from PIL import Image, ImageStat

DEVICE = '74CF31F5-9565-4142-B844-E27058C8F892'
SCREENS = '''home server chat notifications profile custom-status profile-popup create-server create-server-form join-server new-dm group-dm server-settings server-overview server-roles server-members server-invites server-bans create-channel edit-channel invite members members-empty pins pins-empty thread search emoji attachments attachment-draft settings account profile-settings account-credentials username appearance privacy devices notification-settings encryption explore discord-import profile-long video audio create-channel-error create-channel-loading search-error search-loading search-results new-dm-results'''.split()
os.environ['DEVELOPER_DIR'] = '/Applications/Xcode.app/Contents/Developer'
phase = sys.argv[1]
assert phase in ('before', 'after')
app = Path(os.environ.get('MOOD_CAPTURE_APP', 'build/DerivedData/Build/Products/Debug-iphonesimulator/mood.app'))
with (app / 'Info.plist').open('rb') as source:
    bundle = plistlib.load(source)['CFBundleIdentifier']

def sim(*args, timeout=30):
    return subprocess.run(['xcrun', 'simctl', *args], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=timeout)

sim('install', DEVICE, str(app), timeout=90)
sim('status_bar', DEVICE, 'override', '--time', '9:41', '--dataNetwork', 'wifi', '--wifiMode', 'active', '--wifiBars', '3', '--batteryState', 'charged', '--batteryLevel', '100')
for screen in os.environ.get('MOOD_CAPTURE_SCREENS', ' '.join(SCREENS)).split():
    try:
        sim('launch', '--terminate-running-process', DEVICE, bundle, '-uiPreview', '-uiPreviewScreen', screen, timeout=45)
    except (subprocess.TimeoutExpired, subprocess.CalledProcessError):
        print('Recover dedicated simulator before ' + screen, flush=True)
        try:
            sim('shutdown', DEVICE, timeout=30)
        except (subprocess.TimeoutExpired, subprocess.CalledProcessError):
            pass
        sim('boot', DEVICE, timeout=30)
        sim('bootstatus', DEVICE, '-b', timeout=90)
        sim('launch', DEVICE, bundle, '-uiPreview', '-uiPreviewScreen', screen, timeout=30)
    time.sleep(8)
    destination = Path('docs/screenshots/iphone-ui') / phase / (screen + '.png')
    destination.parent.mkdir(parents=True, exist_ok=True)
    for attempt in range(4):
        try:
            sim('io', DEVICE, 'screenshot', str(destination), timeout=20)
            with Image.open(destination) as shot:
                width, height = shot.size
                content = shot.crop((0, int(height * .15), width, int(height * .9))).convert('L')
                statistics = ImageStat.Stat(content)
                deviation = statistics.stddev[0]
                mean = statistics.mean[0]
            # A reference screen can legitimately have only a navigation title.
            # The launch logo has no navigation content in this region.
            with Image.open(destination) as shot:
                navigation = shot.crop((0, int(height * .07), width, int(height * .15))).convert('L')
                title_deviation = ImageStat.Stat(navigation).stddev[0]
            minimum_deviation = 3 if phase == "before" else 9
            if (deviation > minimum_deviation or title_deviation > 15) and mean < 100:
                break
        except subprocess.TimeoutExpired:
            pass
        time.sleep(5)
    else:
        raise RuntimeError('Screenshot did not finish rendering: ' + screen)
    print(str(destination), flush=True)

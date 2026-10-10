#!/usr/bin/env python3
"""Run after flutter create --platforms=ios on a Mac."""
from pathlib import Path
import plistlib
p = Path(__file__).parent / 'ios' / 'Runner' / 'Info.plist'
if not p.exists():
    raise SystemExit('Missing ios/Runner/Info.plist: run flutter create --platforms=ios . on macOS first')
with p.open('rb') as f:
    info = plistlib.load(f)
info['NSLocationWhenInUseUsageDescription'] = 'ROADPRINT uses your location while you record a drive to draw your route and calculate distance.'
info['NSLocationAlwaysAndWhenInUseUsageDescription'] = 'ROADPRINT currently records only while open; background tracking is not enabled.'
info['CFBundleDisplayName'] = 'ROADPRINT'
with p.open('wb') as f:
    plistlib.dump(info, f)
print('Configured iOS foreground location permission and app name.')

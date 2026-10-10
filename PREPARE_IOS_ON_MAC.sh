#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
flutter pub get
flutter create --platforms=ios --project-name roadprint --org com.roadprint .
python3 configure_ios.py
flutter analyze
printf '\nPrepared iOS project. Next: open ios/Runner.xcworkspace in Xcode to set your own signing team and unique bundle ID.\n'

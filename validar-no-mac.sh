#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
xcodebuild -project GIPTV.xcodeproj -scheme GIPTV -destination 'generic/platform=iOS Simulator' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build

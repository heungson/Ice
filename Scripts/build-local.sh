#!/bin/bash
# Build a signed local app without requiring an Apple Developer membership.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICE_DERIVED_DATA="${ICE_DERIVED_DATA:-$PROJECT_ROOT/build/DerivedData}"
ICE_CONFIGURATION="${ICE_CONFIGURATION:-Release}"

xcodebuild -project "$PROJECT_ROOT/Ice.xcodeproj" -scheme Ice \
    -configuration "$ICE_CONFIGURATION" -destination 'platform=macOS' \
    -derivedDataPath "$ICE_DERIVED_DATA" build \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
    CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES \
    PROVISIONING_PROFILE_SPECIFIER= ENABLE_HARDENED_RUNTIME=NO \
    ICE_APP_BUNDLE_IDENTIFIER=com.jordanbaird.Ice.compatibility \
    INFOPLIST_KEY_CFBundleDisplayName='Ice Compatibility' \
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) ICE_LOCAL_BUILD'

ICE_PRODUCT="$ICE_DERIVED_DATA/Build/Products/$ICE_CONFIGURATION/Ice.app"
codesign --verify --deep --strict "$ICE_PRODUCT"
mkdir -p "$PROJECT_ROOT/build"
ICE_OUTPUT="$PROJECT_ROOT/build/Ice Compatibility.app"
if pgrep -fx "$ICE_OUTPUT/Contents/MacOS/Ice" >/dev/null; then
    echo 'Quit Ice Compatibility, then rerun this script to replace the app.' >&2
    exit 1
fi
ICE_STAGING="$(mktemp -d "$PROJECT_ROOT/build/.ice-local.XXXXXX")"
trap 'rm -rf "$ICE_STAGING"' EXIT
ditto "$ICE_PRODUCT" "$ICE_STAGING/Ice Compatibility.app"
codesign --verify --deep --strict "$ICE_STAGING/Ice Compatibility.app"
if [ -e "$ICE_OUTPUT" ]; then
    mv "$ICE_OUTPUT" "$ICE_STAGING/previous.app"
fi
mv "$ICE_STAGING/Ice Compatibility.app" "$ICE_OUTPUT"
codesign --verify --deep --strict "$ICE_OUTPUT"
echo "Built $ICE_OUTPUT"

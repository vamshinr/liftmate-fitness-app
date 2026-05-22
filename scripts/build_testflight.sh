#!/usr/bin/env bash
# Build LiftMate iOS release IPA and (optionally) upload to TestFlight.
#
# Usage:
#   ./scripts/build_testflight.sh build           # build only — produces an IPA
#   ./scripts/build_testflight.sh upload          # build + upload to App Store Connect
#
# Required environment for upload (one-time setup):
#   ASC_KEY_ID         — App Store Connect API key ID (e.g. "ABCD1234EF")
#   ASC_ISSUER_ID      — Issuer ID UUID from App Store Connect → Users and Access → Keys
#   ASC_PRIVATE_KEY    — Path to the .p8 key file you downloaded
#
# One-time prerequisites:
#   1. Apple Developer account ($99/year). The Runner.xcodeproj already has
#      DEVELOPMENT_TEAM = HY92MAM82H configured.
#   2. Bundle ID `com.vamshinr5899.liftmate` registered in your developer
#      portal (https://developer.apple.com/account/resources/identifiers/list).
#   3. App entry created in App Store Connect for that bundle ID.
#   4. App Store Connect API key created — Users & Access → Keys → "+".
#      Role: "Developer" or "App Manager". Download the .p8 once; you can
#      never download it again.
#   5. `xcrun altool` and `xcrun notarytool` ship with Xcode; nothing else
#      to install.

set -euo pipefail

cd "$(dirname "$0")/.."

MODE="${1:-build}"

BUILD_NAME="$(sed -n 's/^version: //p' pubspec.yaml | cut -d+ -f1)"
BUILD_NUMBER="$(sed -n 's/^version: //p' pubspec.yaml | cut -d+ -f2)"

# Auto-bump build number if env is set
if [[ "${BUMP_BUILD:-0}" == "1" ]]; then
  NEW_BUILD=$((BUILD_NUMBER + 1))
  sed -i '' "s/^version: .*/version: ${BUILD_NAME}+${NEW_BUILD}/" pubspec.yaml
  BUILD_NUMBER="$NEW_BUILD"
  echo "→ Bumped build number to $BUILD_NUMBER"
fi

echo "→ Building IPA  (version $BUILD_NAME, build $BUILD_NUMBER)"
flutter clean
flutter pub get
flutter build ipa --release --build-name="$BUILD_NAME" --build-number="$BUILD_NUMBER"

IPA_PATH="$(find build/ios/ipa -name '*.ipa' -depth 1 | head -n1)"
if [[ -z "$IPA_PATH" ]]; then
  echo "✗ No IPA produced. Check the flutter build output above." >&2
  exit 1
fi
echo "✓ IPA: $IPA_PATH"

case "$MODE" in
  build)
    echo
    echo "Done. To install on a device for testing:"
    echo "  open $IPA_PATH"
    echo "or drag it into Devices and Simulators in Xcode (Window menu)."
    echo
    echo "To upload to TestFlight, re-run with: $0 upload"
    ;;
  upload)
    : "${ASC_KEY_ID:?ASC_KEY_ID is required for upload}"
    : "${ASC_ISSUER_ID:?ASC_ISSUER_ID is required for upload}"
    : "${ASC_PRIVATE_KEY:?ASC_PRIVATE_KEY is required for upload (path to .p8)}"

    if [[ ! -f "$ASC_PRIVATE_KEY" ]]; then
      echo "✗ Key file not found: $ASC_PRIVATE_KEY" >&2
      exit 1
    fi

    echo
    echo "→ Uploading to App Store Connect…"
    xcrun altool --upload-app \
      --type ios \
      --file "$IPA_PATH" \
      --apiKey "$ASC_KEY_ID" \
      --apiIssuer "$ASC_ISSUER_ID"

    echo
    echo "✓ Upload submitted. App Store Connect will email you when"
    echo "  processing finishes (usually 5-15 min). Then enable the build"
    echo "  for TestFlight testers in the App Store Connect UI."
    ;;
  *)
    echo "Unknown mode: $MODE"
    echo "Usage: $0 [build|upload]"
    exit 1
    ;;
esac

# LiftMate build scripts

## `build_testflight.sh`

Builds a release IPA and (optionally) uploads to TestFlight.

```bash
./scripts/build_testflight.sh build    # IPA only
./scripts/build_testflight.sh upload   # IPA + upload to App Store Connect
BUMP_BUILD=1 ./scripts/build_testflight.sh upload   # auto-increment build number
```

### One-time TestFlight setup

1. **Apple Developer Program** ($99/year). The repo already has
   `DEVELOPMENT_TEAM = HY92MAM82H` baked in.
2. **Bundle ID registered**: in [Identifiers](https://developer.apple.com/account/resources/identifiers/list),
   create / confirm `com.vamshinr5899.liftmate`.
3. **App created in App Store Connect**: [My Apps → "+"](https://appstoreconnect.apple.com/apps),
   point it at the same Bundle ID. Required before any upload will succeed.
4. **App Store Connect API key** (one-time):
   - Go to [Users and Access → Integrations → App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api).
   - Click **+**, set role to **Developer** or **App Manager**, name it
     "LiftMate CI".
   - Download the `.p8` file **immediately** — you can never download it
     again. Save it somewhere like `~/.keys/liftmate-asc.p8`.
   - Copy the **Key ID** (e.g. `ABCD1234EF`) and **Issuer ID** (UUID) from
     the same page.

Add to your shell rc (`~/.zshrc`):

```bash
export ASC_KEY_ID="ABCD1234EF"
export ASC_ISSUER_ID="69a6de70-..."
export ASC_PRIVATE_KEY="$HOME/.keys/liftmate-asc.p8"
```

Then `source ~/.zshrc` and you're done with one-time setup.

### Typical flow

```bash
# Iterating locally on your dev iPhone:
flutter run -d 00008110-001805960CF9401E    # USB tether is 5-10x faster than wireless

# Shipping a TestFlight build for testers:
BUMP_BUILD=1 ./scripts/build_testflight.sh upload
```

After upload, App Store Connect will email you (usually within 10 min)
when the build finishes processing. Then on the App Store Connect web UI
under **TestFlight → Builds**, enable the build for your testers.

### Troubleshooting

- **`No IPA produced`** — check the flutter build output for code signing errors. Most common cause: provisioning profile missing for the Bundle ID.
- **`No suitable application records were found`** during upload — the app entry doesn't exist yet in App Store Connect (step 3 above).
- **Upload hangs at "Authenticating"** — verify the API key has been activated; new keys take ~5 min to propagate.
- **Build fails on ML Kit arm64 simulator** — covered in `ios/Podfile`; should already be patched.
- **`pod install` warnings about EXCLUDED_ARCHS** — already patched in `ios/Podfile`; if they reappear, run `pod install` from `ios/`.

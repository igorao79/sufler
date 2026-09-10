#!/usr/bin/env bash
#
# Reports privacy-sensitive APIs referenced by a built bundle that have no matching
# NS*UsageDescription in its Info.plist.
#
# Apple's App Store validation rejects a build when any *linked* binary references such an API,
# whether or not the app ever calls it — so a dependency several levels down is enough. Finding
# that out from a rejection email costs an upload and a build number each time; this finds it in
# a second, before the upload.
#
# Usage: scripts/check-purpose-strings.sh <path to .xcarchive or .app>
set -uo pipefail

target="${1:-}"
if [[ -z "$target" ]]; then
  echo "usage: $0 <path to .xcarchive or .app>" >&2
  exit 2
fi

app="$target"
if [[ "$target" == *.xcarchive ]]; then
  app="$(find "$target/Products/Applications" -maxdepth 1 -name '*.app' | head -1)"
fi
if [[ ! -d "$app" ]]; then
  echo "no .app found at $target" >&2
  exit 2
fi

plist="$app/Info.plist"

# ObjC class -> the Info.plist key Apple wants when it is referenced.
read -r -d '' MAP <<'MAPEOF' || true
PHPhotoLibrary NSPhotoLibraryUsageDescription
PHAsset NSPhotoLibraryUsageDescription
PHImageManager NSPhotoLibraryUsageDescription
PHPickerViewController NSPhotoLibraryUsageDescription
UIImagePickerController NSPhotoLibraryUsageDescription
PHAssetCreationRequest NSPhotoLibraryAddUsageDescription
PHAssetChangeRequest NSPhotoLibraryAddUsageDescription
AVCaptureDevice NSCameraUsageDescription
AVCaptureSession NSCameraUsageDescription
AVAudioSession NSMicrophoneUsageDescription
AVAudioApplication NSMicrophoneUsageDescription
AVAudioRecorder NSMicrophoneUsageDescription
SFSpeechRecognizer NSSpeechRecognitionUsageDescription
CMMotionManager NSMotionUsageDescription
CMPedometer NSMotionUsageDescription
CMAltimeter NSMotionUsageDescription
CLLocationManager NSLocationWhenInUseUsageDescription
CNContactStore NSContactsUsageDescription
EKEventStore NSCalendarsUsageDescription
HKHealthStore NSHealthShareUsageDescription
LAContext NSFaceIDUsageDescription
ATTrackingManager NSUserTrackingUsageDescription
MPMediaLibrary NSAppleMusicUsageDescription
MPMediaPickerController NSAppleMusicUsageDescription
CBCentralManager NSBluetoothAlwaysUsageDescription
MAPEOF

# Every Mach-O in the bundle, frameworks and app extensions included — a reference anywhere
# inside counts. `nm -mu` annotates each symbol with " (from Framework)", hence the trim.
refs="$(
  find "$app" -type f -print0 | while IFS= read -r -d '' f; do
    file "$f" 2>/dev/null | grep -q 'Mach-O' || continue
    nm -mu "$f" 2>/dev/null | sed -n 's/.*_OBJC_CLASS_\$_//p' | sed 's/ (from .*//' \
      | sed "s|\$|\t${f#"$app"/}|"
  done
)"

missing=0
while read -r class key; do
  [[ -z "$class" ]] && continue
  where="$(grep -F "$(printf '%s\t' "$class")" <<<"$refs" | cut -f2 | sort -u | paste -sd', ' -)"
  [[ -z "$where" ]] && continue
  if /usr/libexec/PlistBuddy -c "Print :$key" "$plist" >/dev/null 2>&1; then
    printf '  ok      %-34s <- %s\n' "$key" "$class"
  else
    printf '  MISSING %-34s <- %s (in %s)\n' "$key" "$class" "$where"
    missing=$((missing + 1))
  fi
done <<<"$MAP"

if (( missing > 0 )); then
  echo
  echo "$missing purpose string(s) missing — add them to ios.infoPlist in app.config.ts."
  exit 1
fi
echo
echo "All referenced sensitive APIs have a purpose string."

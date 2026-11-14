#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: scripts/release.sh [--release | --publish]

  scripts/release.sh            Archive, export with Developer ID, notarize and staple the app, make and
                                notarize the DMG, sign the update archive, write the appcast, stage
                                build/release/artifact/, and run an upload dry run.
  scripts/release.sh --publish  Upload the staged directory to the public/upshot artifact, check the review
                                copy, publish it, and check the permanent URL.
  scripts/release.sh --release  Do both in one run.

Environment: UPSHOT_NOTARY_PROFILE (notarytool keychain profile, default "development"),
UPSHOT_ARTIFACT_CLI (the publish-html-artifact skill's artifact launcher).
USAGE
}

MODE=build
MODE_SET=0
while (($#)); do
    case "$1" in
        -h | --help) usage; exit 0 ;;
        --release | --publish)
            ((MODE_SET == 0)) || { printf 'Choose exactly one release mode.\n' >&2; exit 2; }
            MODE_SET=1
            MODE="${1#--}"
            ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME=Upshot
XCODE_PROJECT="$PROJECT_DIR/Upshot.xcodeproj"
XCODE_SCHEME=Upshot

TEAM_ID="HD93SAW6ZT"
SIGNING_IDENTITY="Developer ID Application: Christopher York ($TEAM_ID)"
NOTARY_PROFILE="${UPSHOT_NOTARY_PROFILE:-development}"
SPARKLE_KEY_ACCOUNT=upshot
ARTIFACT_SCOPE=public
ARTIFACT_NAME=upshot
ARTIFACT_URL="https://artifacts.chrisyork.co/${ARTIFACT_SCOPE}/${ARTIFACT_NAME}/"
FEED_URL="${ARTIFACT_URL}appcast.xml"
ARTIFACT_CLI="${UPSHOT_ARTIFACT_CLI:-${HOME}/.agents/skills/cyhq/publish-html-artifact/bin/artifact}"

DERIVED_DATA="$PROJECT_DIR/.local/release-derived-data"
SPARKLE_BIN="$DERIVED_DATA/SourcePackages/artifacts/sparkle/Sparkle/bin"
DIST_DIR="$PROJECT_DIR/build/release"
STAGE_DIR="$DIST_DIR/artifact"
MANIFEST="$DIST_DIR/release.env"
RELEASE_HOME="${HOME}/.local/share/upshot-release"
UPDATES_DIR="$RELEASE_HOME/updates"

fail() {
    printf 'release: %s\n' "$*" >&2
    exit 1
}

step() {
    printf '\n== %s\n' "$*"
}

sha256_of() {
    shasum -a 256 "$1" | cut -d' ' -f1
}

appcast_max_build() {
    local highest=0 build
    while IFS= read -r build; do
        if ((build > highest)); then highest="$build"; fi
    done < <(grep -oE '<sparkle:version>[0-9]+</sparkle:version>' "$1" | grep -oE '[0-9]+')
    printf '%s\n' "$highest"
}

check_served_file() {
    local url="$1" local_file="$2" downloaded headers
    downloaded="$(mktemp "${DIST_DIR}/served.XXXXXX")"
    headers="${downloaded}.headers"
    curl -sS --fail --retry 3 --retry-all-errors --max-time 900 -D "$headers" -o "$downloaded" "$url" || fail "Could not download $url."
    [[ "$(sha256_of "$downloaded")" == "$(sha256_of "$local_file")" ]] ||
        fail "$url does not serve the bytes of $local_file."
    printf '%s  %s bytes  %s\n' "$url" "$(stat -f %z "$downloaded")" \
        "$(tr -d '\r' < "$headers" | grep -i '^content-type:' | head -1)"
    rm -f "$downloaded" "$headers"
}

publish_release() {
    [[ -f "$MANIFEST" && -d "$STAGE_DIR" ]] || fail 'Nothing is staged. Run scripts/release.sh first.'
    source "$MANIFEST"
    local dmg="${STAGE_DIR}/${DMG_NAME}"
    [[ "$(sha256_of "$dmg")" == "$DMG_SHA256" ]] || fail "The staged ${DMG_NAME} changed after it was built."
    spctl -a -vv -t install "$dmg"
    [[ -x "$ARTIFACT_CLI" ]] || fail "The artifact launcher is missing: $ARTIFACT_CLI"

    step "Upload ${STAGE_DIR} to ${ARTIFACT_SCOPE}/${ARTIFACT_NAME}"
    local upload version_id review_url file
    upload="$("$ARTIFACT_CLI" upload "$STAGE_DIR" --entry index.html --name "$ARTIFACT_NAME" \
        --scope "$ARTIFACT_SCOPE" --title "$APP_NAME" --json)" || fail 'The upload failed.'
    version_id="$(jq -r '.result.version.version_id // empty' <<< "$upload")"
    review_url="$(jq -r '.result.version.review_url // empty' <<< "$upload")"
    [[ -n "$version_id" && -n "$review_url" ]] || fail "The upload returned no version: $upload"
    printf 'Version %s\nReview URL %s\n' "$version_id" "$review_url"

    step 'Check the review copy'
    for file in "$STAGE_DIR"/*; do
        check_served_file "${review_url%/}/$(basename "$file")" "$file"
    done

    step "Publish version ${version_id}"
    "$ARTIFACT_CLI" publish --name "$ARTIFACT_NAME" --scope "$ARTIFACT_SCOPE" --version "$version_id" ||
        fail "Publication failed. Inspect it with: $ARTIFACT_CLI show --name $ARTIFACT_NAME --scope $ARTIFACT_SCOPE"

    step "Check ${ARTIFACT_URL}"
    for file in "$STAGE_DIR"/*; do
        check_served_file "${ARTIFACT_URL}$(basename "$file")" "$file"
    done
    check_served_file "$ARTIFACT_URL" "${STAGE_DIR}/index.html"

    printf '\nPublished %s %s (build %s) at %s\n' "$APP_NAME" "$VERSION" "$BUILD" "$ARTIFACT_URL"
}

if [[ "$MODE" == publish ]]; then
    publish_release
    exit 0
fi

if [[ "$MODE" == release && ! -x "$ARTIFACT_CLI" ]]; then
    fail "The artifact launcher is missing: $ARTIFACT_CLI"
fi

step 'Preflight'
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 ||
    fail "No notarytool keychain profile named \"$NOTARY_PROFILE\". Create it once with: xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <Apple ID> --team-id $TEAM_ID"
security find-identity -v -p codesigning | grep -qF "$SIGNING_IDENTITY" ||
    fail "The login keychain has no \"$SIGNING_IDENTITY\" certificate."
CONFIGURED_FEED="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$PROJECT_DIR/Upshot/Info.plist")"
[[ "$CONFIGURED_FEED" == "$FEED_URL" ]] || fail "Upshot/Info.plist sets SUFeedURL to \"$CONFIGURED_FEED\", which is not $FEED_URL."

mkdir -p "$UPDATES_DIR"
PUBLISHED_APPCAST="$(mktemp "${TMPDIR:-/tmp}/upshot-appcast.XXXXXX")"
trap 'rm -f "$PUBLISHED_APPCAST"' EXIT
FEED_STATUS="$(curl -sS --max-time 30 -o "$PUBLISHED_APPCAST" -w '%{http_code}' "$FEED_URL")" ||
    fail "Could not read $FEED_URL."
case "$FEED_STATUS" in
    200)
        grep -q '<sparkle:version>' "$PUBLISHED_APPCAST" || fail "$FEED_URL returned HTTP 200 without a Sparkle appcast."
        PUBLISHED_BUILD="$(appcast_max_build "$PUBLISHED_APPCAST")"
        cp "$PUBLISHED_APPCAST" "$UPDATES_DIR/appcast.xml"
        ;;
    404)
        PUBLISHED_BUILD=0
        rm -f "$UPDATES_DIR/appcast.xml"
        ;;
    *) fail "Reading $FEED_URL returned HTTP $FEED_STATUS." ;;
esac
shopt -s nullglob
for file in "$UPDATES_DIR"/"$APP_NAME"-*.zip "$UPDATES_DIR"/"$APP_NAME"*.delta; do
    name="$(basename "$file")"
    if [[ "$name" =~ ^${APP_NAME}-.+-([0-9]+)\.zip$ || "$name" =~ ^${APP_NAME}([0-9]+)-[0-9]+\.delta$ ]]; then
        if ((BASH_REMATCH[1] > PUBLISHED_BUILD)); then rm -f "$file"; fi
    fi
done
shopt -u nullglob

BUILD="$(date +%s)"
printf '%s build %s (published build %s), notarization profile %s\n' "$APP_NAME" "$BUILD" "$PUBLISHED_BUILD" "$NOTARY_PROFILE"

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"
ARCHIVE_PATH="$DIST_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$DIST_DIR/export"
APP="$EXPORT_DIR/$APP_NAME.app"

step 'Archive'
xcodebuild \
    -project "$XCODE_PROJECT" \
    -scheme "$XCODE_SCHEME" \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA" \
    -archivePath "$ARCHIVE_PATH" \
    -skipPackagePluginValidation \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CURRENT_PROJECT_VERSION="$BUILD" \
    UPSHOT_SPARKLE_UPDATES_ENABLED=YES \
    archive

step 'Export with Developer ID signing'
cat > "$DIST_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>destination</key>
    <string>export</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$DIST_DIR/ExportOptions.plist" \
    -allowProvisioningUpdates

plist() { /usr/libexec/PlistBuddy -c "$1" "$APP/Contents/Info.plist"; }
VERSION="$(plist 'Print :CFBundleShortVersionString')"
[[ "$(plist 'Print :CFBundleVersion')" == "$BUILD" ]] || fail "The exported app is not build $BUILD."
[[ "$(plist 'Print :UpshotSparkleUpdatesEnabled')" == YES ]] || fail 'The exported app has Sparkle updates turned off.'
[[ "$(plist 'Print :SUFeedURL')" == "$FEED_URL" ]] || fail "The exported app does not read $FEED_URL."
APP_SIGNATURE="$(codesign -d --verbose=2 "$APP" 2>&1)"
grep -qF "Authority=$SIGNING_IDENTITY" <<< "$APP_SIGNATURE" || fail "The exported app is not signed by $SIGNING_IDENTITY."
codesign --verify --deep --strict "$APP"

notarize() {
    local file="$1" record="${DIST_DIR}/notarization-$2.json" status id
    xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" --wait --timeout 30m \
        --output-format json > "$record" || true
    status="$(jq -r '.status // empty' "$record")"
    if [[ "$status" != Accepted ]]; then
        id="$(jq -r '.id // empty' "$record")"
        [[ -z "$id" ]] || xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" >&2 || true
        fail "Notarization of $(basename "$file") returned status \"${status:-none}\"."
    fi
    printf 'Notarized %s (submission %s)\n' "$(basename "$file")" "$(jq -r .id "$record")"
}

step "Notarize and staple $APP_NAME.app"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST_DIR/notarization-app.zip"
notarize "$DIST_DIR/notarization-app.zip" app
rm -f "$DIST_DIR/notarization-app.zip"
xcrun stapler staple "$APP"
spctl -a -vv -t execute "$APP"

DMG_NAME="$APP_NAME-$VERSION.dmg"
ARCHIVE_NAME="$APP_NAME-$VERSION-$BUILD.zip"
DMG="$DIST_DIR/$DMG_NAME"

step "Make $DMG_NAME"
mkdir -p "$DIST_DIR/dmg-root"
/usr/bin/ditto "$APP" "$DIST_DIR/dmg-root/$APP_NAME.app"
ln -s /Applications "$DIST_DIR/dmg-root/Applications"
hdiutil create -quiet -fs APFS -format ULFO -volname "$APP_NAME" -srcfolder "$DIST_DIR/dmg-root" "$DMG"
rm -rf "$DIST_DIR/dmg-root"
/usr/bin/codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG"
/usr/bin/codesign --verify --strict "$DMG"

step "Notarize and staple $DMG_NAME"
notarize "$DMG" dmg
xcrun stapler staple "$DMG"
spctl -a -vv -t install "$DMG"

step 'Sign the update archive and write the appcast'
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$UPDATES_DIR/$ARCHIVE_NAME"
"$SPARKLE_BIN/generate_appcast" --account "$SPARKLE_KEY_ACCOUNT" --download-url-prefix "$ARTIFACT_URL" \
    --link "$ARTIFACT_URL" --maximum-versions 3 "$UPDATES_DIR"
APPCAST="$UPDATES_DIR/appcast.xml"
[[ "$(appcast_max_build "$APPCAST")" == "$BUILD" ]] || fail "The appcast's newest item is not build $BUILD."
ITEM_SIGNATURE="$(grep -oE "url=\"${ARTIFACT_URL}${ARCHIVE_NAME}\"[^>]*" "$APPCAST" |
    grep -oE 'sparkle:edSignature="[^"]+"' | head -1 | cut -d'"' -f2)"
[[ -n "$ITEM_SIGNATURE" ]] || fail "The appcast has no signed enclosure for $ARCHIVE_NAME."
/usr/bin/swift "$SCRIPT_DIR/verify-sparkle-signature.swift" \
    "$(plist 'Print :SUPublicEDKey')" "$ITEM_SIGNATURE" "$UPDATES_DIR/$ARCHIVE_NAME"

step "Stage $STAGE_DIR"
mkdir -p "$STAGE_DIR"
cp "$APPCAST" "$STAGE_DIR/appcast.xml"
while IFS= read -r url; do
    file="${url#"$ARTIFACT_URL"}"
    [[ -f "$UPDATES_DIR/$file" ]] || fail "The appcast links $url, which is not in $UPDATES_DIR."
    cp "$UPDATES_DIR/$file" "$STAGE_DIR/$file"
done < <(grep -oE "url=\"${ARTIFACT_URL}[^\"]+\"" "$APPCAST" | cut -d'"' -f2 | sort -u)
cp "$DMG" "$STAGE_DIR/$DMG_NAME"
cp "$DMG" "$STAGE_DIR/$APP_NAME.dmg"

ICON_PNG="$DIST_DIR/AppIcon.png"
/usr/bin/sips -s format png "$APP/Contents/Resources/$APP_NAME.icns" --out "$ICON_PNG" >/dev/null
ARCHITECTURES="$(lipo -archs "$APP/Contents/MacOS/$APP_NAME")"
case "$ARCHITECTURES" in
    *arm64*x86_64* | *x86_64*arm64*) PLATFORM_NOTE="Apple&nbsp;silicon and Intel" ;;
    arm64) PLATFORM_NOTE="Apple&nbsp;silicon" ;;
    *) PLATFORM_NOTE="$ARCHITECTURES" ;;
esac

DMG_SHA256="$(sha256_of "$DMG")"
DMG_BYTES="$(stat -f %z "$DMG")"
ARCHIVE_SHA256="$(sha256_of "$UPDATES_DIR/$ARCHIVE_NAME")"
ARCHIVE_BYTES="$(stat -f %z "$UPDATES_DIR/$ARCHIVE_NAME")"
MINIMUM_SYSTEM="$(plist 'Print :LSMinimumSystemVersion')"
RELEASED="$(date +%Y-%m-%d)"
VERSION="$VERSION" BUILD="$BUILD" RELEASED="$RELEASED" MINIMUM_SYSTEM="$MINIMUM_SYSTEM" \
  DMG_NAME="$DMG_NAME" DMG_BYTES="$DMG_BYTES" DMG_SHA256="$DMG_SHA256" \
  ARCHIVE_NAME="$ARCHIVE_NAME" ARCHIVE_BYTES="$ARCHIVE_BYTES" ARCHIVE_SHA256="$ARCHIVE_SHA256" \
  APP_NAME="$APP_NAME" FEED_NOTE="Update feed. $APP_NAME checks it automatically and from Check for Updates." \
  ICON_SOURCE="$ICON_PNG" PLATFORM_NOTE="$PLATFORM_NOTE" \
  "$SCRIPT_DIR/write-release-download-page.sh" "${STAGE_DIR}/index.html"

cat > "$MANIFEST" <<ENV
VERSION=${VERSION}
BUILD=${BUILD}
DMG_NAME=${DMG_NAME}
DMG_SHA256=${DMG_SHA256}
ARCHIVE_NAME=${ARCHIVE_NAME}
ENV

step 'Upload plan (dry run)'
"$ARTIFACT_CLI" upload "$STAGE_DIR" --entry index.html --name "$ARTIFACT_NAME" --scope "$ARTIFACT_SCOPE" \
    --title "$APP_NAME" --dry-run --json > "$DIST_DIR/upload-plan.json"
jq -r '.result.version.files[] | "\(.path)  \(.content_type)  \(.byte_length) bytes"' "$DIST_DIR/upload-plan.json"

printf '\nStaged %s %s (build %s) in %s\n' "$APP_NAME" "$VERSION" "$BUILD" "$STAGE_DIR"
printf 'Publish it to %s with: scripts/release.sh --publish\n' "$ARTIFACT_URL"

if [[ "$MODE" == release ]]; then
    publish_release
fi

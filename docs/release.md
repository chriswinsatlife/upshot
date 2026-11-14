---
review_status: unreviewed
approval_status: not_approved
---

# Release

`scripts/release.sh` builds a Developer ID release, and `scripts/release.sh --publish` puts it on the download page at https://artifacts.chrisyork.co/public/upshot/. The page, the disk image, the update archive, and the Sparkle feed `appcast.xml` are files of the `public/upshot` artifact.

## Prerequisites

- Xcode with `xcodebuild`, `xcrun`, `notarytool`, and `stapler`, plus `jq` and `curl`.
- The `Developer ID Application: Christopher York (HD93SAW6ZT)` certificate in the login keychain.
- A notarytool keychain profile, `development` by default. `UPSHOT_NOTARY_PROFILE` names another one.
- The Sparkle EdDSA private key in the login keychain under the Sparkle account `upshot`. Its public key is `SUPublicEDKey` in `Upshot/Info.plist`.
- The artifact launcher of the publish-html-artifact skill at `~/.agents/skills/cyhq/publish-html-artifact/bin/artifact`. `UPSHOT_ARTIFACT_CLI` names another path.

## Build and Stage

`scripts/release.sh` runs these steps and stops at the first failure:

- Reads the published feed. A 404 starts a new feed.
- Archives the Release configuration with the build number set to the current Unix time and `UPSHOT_SPARKLE_UPDATES_ENABLED=YES`.
- Exports with Developer ID signing and checks the build number, the Sparkle switch, the feed address, and the signature.
- Notarizes and staples the app, then builds, signs, notarizes, and staples `Upshot-<version>.dmg`.
- Zips the app as the update archive, runs Sparkle's `generate_appcast` with the `upshot` key account, and checks the archive's signature against the app's `SUPublicEDKey` with `scripts/verify-sparkle-signature.swift`.
- Stages `build/release/artifact/` with the appcast, the update archives it lists, the versioned DMG, `Upshot.dmg`, and the page written by `scripts/write-release-download-page.sh`.
- Runs an upload dry run.

Update archives of published builds stay in `~/.local/share/upshot-release/updates/`, so the feed lists the last three builds and Sparkle can make delta updates.

## Publish

`scripts/release.sh --publish` uploads the staged directory, downloads every file from the review copy and compares its bytes, publishes that version, and repeats the comparison at the permanent address. `scripts/release.sh --release` builds, stages, and publishes in one run.

## Updates

Only builds made by `scripts/release.sh` set `UpshotSparkleUpdatesEnabled` to `YES` in `Info.plist`. `UpdaterManager` starts Sparkle only in those builds, so a build made in Xcode or with `xcodebuild` never offers to replace itself with a published release. The marketing version is `MARKETING_VERSION` in `Upshot.xcodeproj/project.pbxproj`. Sparkle compares the build numbers, which always increase because they are Unix times.

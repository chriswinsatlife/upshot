---
review_status: unreviewed
approval_status: not_approved
---

# Release

Releases use the Go tool in `cmd/upshot-release`, run from the repository root. It finds the repository from `UPSHOT_REPO`, then the current directory.

## Prerequisites

- `create-dmg`, an authenticated `gh`, `git`, `plutil`, and Xcode's `xcodebuild`, `xcrun`, and `ditto`.
- A notarytool keychain profile named `upshot-notary`, created once with `xcrun notarytool store-credentials "upshot-notary" --key <AuthKey.p8> --key-id <key id> --issuer <issuer id>`.
- The Sparkle EdDSA private key in the login keychain under the Sparkle account `upshot`. The matching public key is `SUPublicEDKey` in `Upshot/Info.plist`.

## Full Release

The build number (`CURRENT_PROJECT_VERSION`) must increase every release, or Sparkle does not offer the update. Check the current values with `rg 'MARKETING_VERSION|CURRENT_PROJECT_VERSION' Upshot.xcodeproj/project.pbxproj`. Commit and push code changes to `main` first, then run:

```bash
go run ./cmd/upshot-release -build -yes -set-version <x.y.z> -set-build <n> -notes "First note
Second note"
```

Notarization takes several minutes.

## Flags

- `-build`: archive, export with Developer ID, notarize, and staple into `~/Downloads/Upshot.app` before packaging. Without it, the tool packages an app already exported to `~/Downloads/Upshot.app`.
- `-set-version` and `-set-build`: set and commit `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` before archiving.
- `-scheme`: the scheme to archive, `Upshot` by default.
- `-notes` or `-notes-file`: release notes, one per line.
- `-notary-profile`: the notarytool keychain profile, `upshot-notary` by default.
- `-yes` or `-y`: answer yes to every confirmation.

## Steps

After the optional build phase, the tool validates the app's version, build, and Sparkle keys; creates `~/Downloads/Upshot.dmg`; signs it with Sparkle's `sign_update` using the `upshot` key account; pushes local commits; creates the GitHub release `vX.Y.Z` on `chriswinsatlife/upshot` with the DMG; prepends the release to `appcast.xml` and pushes it; and updates the cask in `chriswinsatlife/homebrew-tap`. Re-running the same release replaces the DMG and the appcast entry instead of duplicating them.

The update feed is `https://raw.githubusercontent.com/chriswinsatlife/upshot/main/appcast.xml`.

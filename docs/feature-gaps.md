---
review_status: unreviewed
approval_status: not_approved
sources:
  - docs/cleanshot-x-feature-parity.md
  - docs/snapzy-better-shot-comparison.md
---

# Feature Gaps

Each item is a feature that Upshot lacks, or implements only in part, and that at least one of CleanShot X, Snapzy, or Better Shot has. The apps that have the feature follow the colon. Listing a gap does not mean the feature is wanted.

## Screenshot Capture

- Color picker: Snapzy and Better Shot. Upshot has no command that reads a pixel color from the screen. The annotation editor's custom color tile opens the system color panel through `AnnotationColorPanelBridge` in `Upshot/AnnotationInspectorStyleMenus.swift`.
- Screen ruler: Snapzy. Upshot has no on-screen ruler. The Measure tool, defined in `Upshot/AnnotationTool.swift` and drawn by `Upshot/AnnotationMeasurement.swift`, measures an arrow inside an open screenshot in the annotation editor.
- Object cutout: Snapzy. Upshot has no subject lifting for screenshots. Its only person segmentation, `Upshot/StudioCameraCutout.swift`, cuts the camera subject out of Studio recordings.

## Text Recognition

- Remote OCR engine: Snapzy. Upshot has no remote OCR request code. Text recognition uses `ImageAnalyzer` for Live Text and `VNRecognizeTextRequest` for Vision in `Upshot/ImageTextRecognizer.swift`.

## Sharing and Storage

- Hosted cloud account: CleanShot X. Upshot has no account sign-in. The user deploys a Cloudflare Worker to their own Cloudflare account and enters its URL and upload token in `Upshot/SettingsCloudPane.swift`. The values are stored by `Upshot/CloudCredentialStore.swift`.
- S3, R2, and Google Drive upload with link expiry: Snapzy. Upshot uploads only through the Upshot Cloud worker to R2, in `Upshot/CloudUploader.swift`. The legacy S3 settings are deleted by `migrateFromLegacyS3Credentials` in `Upshot/CloudCredentialStore.swift`. Upshot has no Google Drive upload and no link expiry.
- Direct R2 upload with a share viewer: Better Shot. The app sends each upload to the worker, which streams it to R2 through a Worker binding, so the app does not write to R2 directly (`Upshot/CloudUploader.swift`). The worker's share page for recordings receives a poster frame, title, and transcript from `Upshot/CloudSidecarUploader.swift`.

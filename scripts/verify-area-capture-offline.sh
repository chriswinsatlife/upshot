#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .local/verification
if ! xcrun swiftc -swift-version 6 -default-isolation MainActor -parse-as-library \
    Upshot/AreaCaptureSnapshot.swift Upshot/AreaCaptureFrameStream.swift Upshot/AreaCaptureWindowSnapshot.swift \
    scripts/verify-area-capture-offline.swift -o .local/verification/verify-area-capture-offline \
    > .local/verification/offline-build.log 2>&1; then
    cat .local/verification/offline-build.log
    exit 1
fi
NSUnbufferedIO=YES .local/verification/verify-area-capture-offline 2>&1 | tee .local/verification/offline-results.log

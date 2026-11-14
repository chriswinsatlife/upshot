#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
work=".local/verification/studio-camera-motion"
mkdir -p "$work"
sources=(
    Upshot/AnnotationBackgroundStyle.swift
    Upshot/RecordingCameraLayout.swift
    Upshot/RecordingClipTimeline.swift
    Upshot/RecordingExportReframe.swift
    Upshot/RecordingMotionSpring.swift
    Upshot/RecordingPointerEvents.swift
    Upshot/RecordingPointerShapes.swift
    Upshot/RecordingStudioMotionTimeline.swift
    Upshot/RecordingStudioStyle.swift
    Upshot/RecordingViewportTimeline.swift
    Upshot/RecordingZoomAnimationStyle.swift
    Upshot/StudioCameraBeauty.swift
)
if ! xcrun swiftc -swift-version 5 -default-isolation MainActor -parse-as-library \
    -module-cache-path "$work/ModuleCache" "${sources[@]}" scripts/check-studio-camera-motion.swift \
    -o "$work/check-studio-camera-motion" > "$work/build.log" 2>&1; then
    cat "$work/build.log"
    exit 1
fi
"$work/check-studio-camera-motion"

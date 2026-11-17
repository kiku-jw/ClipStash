#!/bin/bash
set -euo pipefail

# Compile actual app sources without launching AppDelegate or its clipboard monitor.
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
qa_dir="$(mktemp -d "${TMPDIR:-/tmp}/clipstash-offline-qa.XXXXXX")"
trap 'rm -rf -- "$qa_dir"' EXIT
mkdir -p "$qa_dir/Sources/ClipStash" "$qa_dir/Tests/ClipStashTests"

cp "$repo_dir/ClipStash/Core/StorageManager.swift" \
   "$repo_dir/ClipStash/Core/ExportService.swift" \
   "$repo_dir/ClipStash/Core/Models/ClipItem.swift" \
   "$repo_dir/ClipStash/UI/ClipboardViewModel.swift" \
   "$qa_dir/Sources/ClipStash/"
cp "$repo_dir/ClipStashTests/ClipboardViewModelTests.swift" \
   "$qa_dir/Tests/ClipStashTests/"
cat > "$qa_dir/Package.swift" <<'SWIFT'
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClipStash",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ClipStash"),
        .testTarget(name: "ClipStashTests", dependencies: ["ClipStash"])
    ]
)
SWIFT

xcrun swift test --package-path "$qa_dir" --scratch-path "$qa_dir/build" \
    --filter ClipboardViewModelTests

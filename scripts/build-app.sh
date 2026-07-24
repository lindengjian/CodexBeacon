#!/bin/zsh

set -euo pipefail

script_directory=${0:A:h}
repository_root=${script_directory:h}
application_bundle="${repository_root}/.build/CodexBeacon.app"
contents_directory="${application_bundle}/Contents"
macos_directory="${contents_directory}/MacOS"

swift build \
    --package-path "${repository_root}" \
    --configuration release \
    --arch arm64 \
    --product CodexBeacon

mkdir -p "${macos_directory}"
install -m 755 \
    "${repository_root}/.build/arm64-apple-macosx/release/CodexBeacon" \
    "${macos_directory}/CodexBeacon"
install -m 644 \
    "${repository_root}/Resources/Info.plist" \
    "${contents_directory}/Info.plist"

printf 'Built %s\n' "${application_bundle}"

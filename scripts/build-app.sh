#!/bin/zsh

set -euo pipefail

script_directory=${0:A:h}
repository_root=${script_directory:h}
application_bundle="${repository_root}/.build/CodexBeacon.app"
contents_directory="${application_bundle}/Contents"
macos_directory="${contents_directory}/MacOS"
resources_directory="${contents_directory}/Resources"
icon_source="${repository_root}/docs/images/codex-beacon-icon-glass.png"
iconset_directory="${repository_root}/.build/CodexBeacon.iconset"
icon_destination="${resources_directory}/CodexBeacon.icns"

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

rm -rf "${iconset_directory}"
mkdir -p "${iconset_directory}" "${resources_directory}"
for icon_size in 16 32 128 256 512; do
    sips -z "${icon_size}" "${icon_size}" "${icon_source}" \
        --out "${iconset_directory}/icon_${icon_size}x${icon_size}.png" >/dev/null
    double_size=$((icon_size * 2))
    sips -z "${double_size}" "${double_size}" "${icon_source}" \
        --out "${iconset_directory}/icon_${icon_size}x${icon_size}@2x.png" >/dev/null
done
iconutil --convert icns "${iconset_directory}" --output "${icon_destination}"

# Signing after the bundle is assembled binds Info.plist to the app identity.
# UserNotifications rejects an unsigned or inconsistently signed bundle.
codesign --force --sign - "${application_bundle}"

printf 'Built %s\n' "${application_bundle}"

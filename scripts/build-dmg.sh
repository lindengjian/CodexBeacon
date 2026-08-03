#!/bin/zsh

set -euo pipefail

script_directory=${0:A:h}
repository_root=${script_directory:h}
version=1.0.9
application_name=CodexBeacon.app
application_bundle="${repository_root}/.build/${application_name}"
staging_directory="${repository_root}/.build/dmg-root"
distribution_directory="${repository_root}/dist"
disk_image="${distribution_directory}/CodexBeacon-${version}-arm64.dmg"
temporary_directory=$(mktemp -d)
temporary_disk_image="${temporary_directory}/CodexBeacon-${version}-arm64.dmg"

cleanup() {
    rm -rf "${temporary_directory}"
}
trap cleanup EXIT

"${script_directory}/build-app.sh"
codesign --verify --strict --verbose=4 "${application_bundle}"

rm -rf "${staging_directory}"
mkdir -p "${staging_directory}" "${distribution_directory}"
ditto "${application_bundle}" "${staging_directory}/${application_name}"
ln -s /Applications "${staging_directory}/Applications"

hdiutil create \
    -volname "Codex Beacon ${version}" \
    -srcfolder "${staging_directory}" \
    -format UDZO \
    -imagekey zlib-level=9 \
    "${temporary_disk_image}"
mv -f "${temporary_disk_image}" "${disk_image}"

printf 'Built %s\n' "${disk_image}"

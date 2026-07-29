#!/bin/bash

set -euo pipefail

repository="lindengjian/CodexBeacon"
release_api="https://api.github.com/repos/${repository}/releases/latest"
applications_directory="${HOME}/Applications"
application_name="CodexBeacon.app"
installed_application="${applications_directory}/${application_name}"
temporary_directory=""
mount_directory=""
mounted=false

fail() {
  printf 'Codex Beacon 安装失败：%s\n' "$1" >&2
  exit 1
}

cleanup() {
  if [ "${mounted}" = true ] && [ -n "${mount_directory}" ]; then
    /usr/bin/hdiutil detach "${mount_directory}" -quiet || true
  fi
  if [ -n "${temporary_directory}" ]; then
    /bin/rm -rf "${temporary_directory}"
  fi
}

trap cleanup EXIT

if [ "$(/usr/bin/uname -s)" != "Darwin" ]; then
  fail "仅支持 macOS。"
fi

if [ "$(/usr/bin/uname -m)" != "arm64" ]; then
  fail "仅支持 Apple Silicon Mac。"
fi

macos_version=$(/usr/bin/sw_vers -productVersion)
macos_major_version=${macos_version%%.*}
if [ "${macos_major_version}" -lt 15 ]; then
  fail "需要 macOS 15 或更高版本（当前为 ${macos_version}）。"
fi

for command in curl hdiutil ditto codesign open grep head shasum; do
  command -v "${command}" >/dev/null 2>&1 || fail "缺少系统命令：${command}。"
done

temporary_directory=$(/usr/bin/mktemp -d -t codex-beacon-install)
release_json="${temporary_directory}/release.json"
disk_image="${temporary_directory}/CodexBeacon.dmg"
mount_directory="${temporary_directory}/mount"

printf '正在获取最新版本…\n'
/usr/bin/curl -fsSL --retry 3 --retry-delay 1 "${release_api}" -o "${release_json}" \
  || fail "无法连接 GitHub Release。"

disk_image_url=$(
  { /usr/bin/grep -Eo 'https://[^\"]+CodexBeacon-[^\"]+-arm64\.dmg' "${release_json}" || true; } \
    | /usr/bin/head -n 1
)
[ -n "${disk_image_url}" ] || fail "最新 Release 中未找到 Apple Silicon 安装包。"

expected_digest=$(
  { /usr/bin/grep -Eo 'sha256:[[:xdigit:]]{64}' "${release_json}" || true; } \
    | /usr/bin/head -n 1
)

printf '正在下载 Codex Beacon…\n'
/usr/bin/curl -fL --retry 3 --retry-delay 1 "${disk_image_url}" -o "${disk_image}" \
  || fail "下载安装包失败。"

if [ -n "${expected_digest}" ]; then
  actual_digest="sha256:$(/usr/bin/shasum -a 256 "${disk_image}" | /usr/bin/awk '{print $1}')"
  [ "${actual_digest}" = "${expected_digest}" ] || fail "安装包校验和不匹配。"
fi

/bin/mkdir -p "${mount_directory}"
/usr/bin/hdiutil attach -nobrowse -readonly -mountpoint "${mount_directory}" "${disk_image}" >/dev/null \
  || fail "无法打开下载的安装包。"
mounted=true

source_application="${mount_directory}/${application_name}"
[ -d "${source_application}" ] || fail "安装包中缺少 ${application_name}。"

printf '正在验证并安装…\n'
/usr/bin/codesign --verify --strict --verbose=2 "${source_application}" \
  || fail "安装包的签名验证失败。"

/bin/mkdir -p "${applications_directory}"
staged_application="${applications_directory}/.${application_name}.install-$$"
backup_application="${applications_directory}/.${application_name}.backup-$$"
/bin/rm -rf "${staged_application}" "${backup_application}"
/usr/bin/ditto "${source_application}" "${staged_application}"
/usr/bin/codesign --verify --strict --verbose=2 "${staged_application}" \
  || fail "复制后的应用签名验证失败。"

if [ -e "${installed_application}" ]; then
  /bin/mv "${installed_application}" "${backup_application}"
fi

if /bin/mv "${staged_application}" "${installed_application}"; then
  /bin/rm -rf "${backup_application}"
else
  if [ -e "${backup_application}" ] && [ ! -e "${installed_application}" ]; then
    /bin/mv "${backup_application}" "${installed_application}"
  fi
  fail "无法替换现有安装。"
fi

printf '已安装到 %s，正在打开…\n' "${installed_application}"
/usr/bin/open "${installed_application}"

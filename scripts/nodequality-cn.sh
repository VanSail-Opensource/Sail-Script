#!/usr/bin/env bash
# NodeQuality mainland-friendly launcher for Sail Script.
# It does NOT vendor NodeQuality source code. Instead, it fetches the current
# upstream script from a CDN, rewrites GitHub-hosted dependencies to CDN/proxy
# endpoints, validates the resulting shell script, and then executes it.
#
# Upstream: https://github.com/LloydAsp/NodeQuality

set -euo pipefail

NQ_UPSTREAM_RAW="https://raw.githubusercontent.com/LloydAsp/NodeQuality/refs/heads/main/NodeQuality.sh"
NQ_MAIN_CDN="${NQ_MAIN_CDN:-https://cdn.jsdelivr.net/gh/LloydAsp/NodeQuality@main/NodeQuality.sh}"
NQ_RAW_CDN="${NQ_RAW_CDN:-https://cdn.jsdelivr.net/gh/LloydAsp/NodeQuality@main}"
NQ_GITHUB_PROXY="${NQ_GITHUB_PROXY:-https://gh-proxy.com/}"

if ! command -v curl >/dev/null 2>&1; then
    echo "[ERR] 需要 curl 才能运行 NodeQuality 国内网络受阻版。" >&2
    exit 1
fi

work_file="$(mktemp)"
patched_file="$(mktemp)"
cleanup() {
    rm -f "$work_file" "$patched_file"
}
trap cleanup EXIT

echo "[INFO] 正在通过 CDN 获取最新版 NodeQuality..."
if ! curl -fsSL --connect-timeout 10 --retry 2 --retry-delay 1 "$NQ_MAIN_CDN" -o "$work_file"; then
    echo "[WARN] jsDelivr 获取失败，尝试 GitHub 加速代理..." >&2
    curl -fsSL --connect-timeout 10 --retry 2 --retry-delay 1 \
        "${NQ_GITHUB_PROXY}${NQ_UPSTREAM_RAW}" -o "$work_file"
fi

# NodeQuality currently loads part/*.sh from raw.githubusercontent.com and
# downloads BenchOS / NextTrace from github.com release assets. The former is
# redirected to jsDelivr; GitHub release downloads use the configurable proxy.
sed \
    -e "s#https://raw.githubusercontent.com/LloydAsp/NodeQuality/refs/heads/main#${NQ_RAW_CDN}#g" \
    "$work_file" > "$patched_file"

if [[ -n "$NQ_GITHUB_PROXY" ]]; then
    sed \
        -e "s#https://github.com/#${NQ_GITHUB_PROXY}https://github.com/#g" \
        "$patched_file" > "${patched_file}.tmp"
    mv "${patched_file}.tmp" "$patched_file"
fi

if ! bash -n "$patched_file"; then
    echo "[ERR] CDN 版本 NodeQuality 未通过 Bash 语法检查，已停止执行。" >&2
    exit 1
fi

echo "[INFO] NodeQuality 已加载；Raw 依赖使用 jsDelivr，GitHub Release 使用加速代理。"
echo "[INFO] 上游项目：https://github.com/LloydAsp/NodeQuality"

bash "$patched_file" "$@"

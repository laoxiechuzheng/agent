#!/bin/sh

set -eu

NZ_AGENT_REPOSITORY="laoxiechuzheng/agent"
NZ_BASE_PATH="${NZ_BASE_PATH:-/opt/nezha}"
NZ_AGENT_PATH="${NZ_BASE_PATH}/agent"

err() {
    printf '\033[0;31m%s\033[0m\n' "$*" >&2
}

success() {
    printf '\033[0;32m%s\033[0m\n' "$*"
}

info() {
    printf '\033[0;33m%s\033[0m\n' "$*"
}

run_as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
        return
    fi
    if command -v sudo >/dev/null 2>&1; then
        command sudo "$@"
        return
    fi
    err "sudo is required to install nezha-agent"
    exit 1
}

has_downloader() {
    command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1
}

download() {
    url="$1"
    output="$2"
    if command -v curl >/dev/null 2>&1; then
        curl --fail --location --retry 3 --connect-timeout 15 --max-time 180 \
            --silent --show-error "$url" -o "$output"
        return
    fi
    if command -v wget >/dev/null 2>&1; then
        wget --timeout=60 --tries=3 --quiet -O "$output" "$url"
        return
    fi
    err "curl or wget is required"
    exit 1
}

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
        return
    fi
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
        return
    fi
    err "sha256sum or shasum is required"
    exit 1
}

detect_platform() {
    machine="$(uname -m)"
    case "$machine" in
        amd64|x86_64) os_arch="amd64" ;;
        i386|i686) os_arch="386" ;;
        aarch64|arm64) os_arch="arm64" ;;
        *arm*) os_arch="arm" ;;
        s390x) os_arch="s390x" ;;
        riscv64) os_arch="riscv64" ;;
        mips) os_arch="mips" ;;
        mipsel|mipsle) os_arch="mipsle" ;;
        loongarch64) os_arch="loong64" ;;
        *) err "unsupported architecture: $machine"; exit 1 ;;
    esac

    system="$(uname -s)"
    case "$system" in
        Linux) os="linux" ;;
        Darwin) os="darwin" ;;
        FreeBSD) os="freebsd" ;;
        *) err "unsupported operating system: $system"; exit 1 ;;
    esac
}

install_agent() {
    has_downloader || { err "curl or wget is required"; exit 1; }
    command -v unzip >/dev/null 2>&1 || { err "unzip is required"; exit 1; }
    command -v awk >/dev/null 2>&1 || { err "awk is required"; exit 1; }

    if [ -z "${NZ_SERVER:-}" ]; then
        err "NZ_SERVER must not be empty"
        exit 1
    fi
    if [ -z "${NZ_CLIENT_SECRET:-}" ]; then
        err "NZ_CLIENT_SECRET must not be empty"
        exit 1
    fi

    detect_platform
    archive_name="nezha-agent_${os}_${os_arch}.zip"
    release_base="https://github.com/${NZ_AGENT_REPOSITORY}/releases/latest/download"
    tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/nezha-agent.XXXXXX")"
    trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM

    info "Downloading ${archive_name} from ${NZ_AGENT_REPOSITORY}"
    download "${release_base}/${archive_name}" "${tmp_dir}/${archive_name}"
    download "${release_base}/checksums.txt" "${tmp_dir}/checksums.txt"

    expected_hash="$(awk -v name="$archive_name" '$2 == name { print $1; exit }' "${tmp_dir}/checksums.txt")"
    if [ -z "$expected_hash" ]; then
        err "checksum entry for ${archive_name} was not found"
        exit 1
    fi
    actual_hash="$(sha256_file "${tmp_dir}/${archive_name}")"
    if [ "$expected_hash" != "$actual_hash" ]; then
        err "checksum verification failed for ${archive_name}"
        exit 1
    fi

    run_as_root mkdir -p "$NZ_AGENT_PATH"
    run_as_root unzip -oq "${tmp_dir}/${archive_name}" -d "$NZ_AGENT_PATH"
    run_as_root chmod 0755 "${NZ_AGENT_PATH}/nezha-agent"

    config_path="${NZ_AGENT_PATH}/config.yml"
    if [ -f "$config_path" ]; then
        config_path="${NZ_AGENT_PATH}/config-$(date +%s)-$$.yml"
    fi

    NZ_TLS="${NZ_TLS:-false}"
    NZ_DISABLE_AUTO_UPDATE="${NZ_DISABLE_AUTO_UPDATE:-false}"
    NZ_DISABLE_FORCE_UPDATE="${NZ_DISABLE_FORCE_UPDATE:-false}"
    NZ_DISABLE_COMMAND_EXECUTE="${NZ_DISABLE_COMMAND_EXECUTE:-false}"
    NZ_SKIP_CONNECTION_COUNT="${NZ_SKIP_CONNECTION_COUNT:-false}"
    NZ_SKIP_PROCS_COUNT="${NZ_SKIP_PROCS_COUNT:-false}"

    run_as_root env \
        "NZ_SERVER=${NZ_SERVER}" \
        "NZ_CLIENT_SECRET=${NZ_CLIENT_SECRET}" \
        "NZ_UUID=${NZ_UUID:-}" \
        "NZ_TLS=${NZ_TLS}" \
        "NZ_DISABLE_AUTO_UPDATE=${NZ_DISABLE_AUTO_UPDATE}" \
        "NZ_DISABLE_FORCE_UPDATE=${NZ_DISABLE_FORCE_UPDATE}" \
        "NZ_DISABLE_COMMAND_EXECUTE=${NZ_DISABLE_COMMAND_EXECUTE}" \
        "NZ_SKIP_CONNECTION_COUNT=${NZ_SKIP_CONNECTION_COUNT}" \
        "NZ_SKIP_PROCS_COUNT=${NZ_SKIP_PROCS_COUNT}" \
        "NZ_UPDATE_REPOSITORY=${NZ_AGENT_REPOSITORY}" \
        "NZ_USE_GITEE_TO_UPGRADE=false" \
        "NZ_USE_ATOMGIT_TO_UPGRADE=false" \
        "${NZ_AGENT_PATH}/nezha-agent" service -c "$config_path" install

    if [ ! -f "$config_path" ]; then
        err "agent installed but configuration was not created at ${config_path}"
        exit 1
    fi

    success "nezha-agent installed from ${NZ_AGENT_REPOSITORY}"
    info "Agent self-updates are locked to ${NZ_AGENT_REPOSITORY}"
}

uninstall_agent() {
    if [ ! -d "$NZ_AGENT_PATH" ]; then
        info "nezha-agent is not installed"
        return
    fi

    find "$NZ_AGENT_PATH" -type f -name 'config*.yml' | while IFS= read -r config_file; do
        if [ -x "${NZ_AGENT_PATH}/nezha-agent" ]; then
            run_as_root "${NZ_AGENT_PATH}/nezha-agent" service -c "$config_file" uninstall >/dev/null 2>&1 || true
        fi
        run_as_root rm -f "$config_file"
    done
    info "nezha-agent services were removed; the binary directory was preserved"
}

if [ "${1:-}" = "uninstall" ]; then
    uninstall_agent
    exit 0
fi

install_agent

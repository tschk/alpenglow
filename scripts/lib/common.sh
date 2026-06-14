#!/usr/bin/env bash
# Common shell functions for Alpenglow scripts
# Source this file in other scripts: source "${SCRIPT_DIR}/lib/common.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[alpenglow]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[alpenglow]${NC} ✓ $1"
}

log_warn() {
    echo -e "${YELLOW}[alpenglow]${NC} ⚠ $1"
}

log_error() {
    echo -e "${RED}[alpenglow]${NC} ✗ $1" >&2
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${CYAN}[debug]${NC} $1"
    fi
}

# Check if a command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Get project root
get_project_root() {
    local script_dir="$1"
    cd "${script_dir}/.." && pwd
}

# Check if running in CI
is_ci() {
    [[ -n "${CI:-}" ]] || [[ -n "${GITHUB_ACTIONS:-}" ]]
}

# Wait for a service to be ready
wait_for_service() {
    local url="$1"
    local timeout="${2:-30}"
    local interval="${3:-1}"
    
    log_info "Waiting for ${url}..."
    
    for ((i=0; i<timeout; i++)); do
        if curl -s "$url" > /dev/null 2>&1; then
            return 0
        fi
        sleep "$interval"
    done
    
    return 1
}

# Check required tools
check_tools() {
    local missing=()
    
    for tool in "$@"; do
        if ! command_exists "$tool"; then
            missing+=("$tool")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing[*]}"
        return 1
    fi
    
    return 0
}

# Create a temporary directory
create_temp_dir() {
    local prefix="${1:-alpenglow}"
    mktemp -d -t "${prefix}.XXXXXX"
}

# JSON helpers (requires jq)
json_get() {
    local json="$1"
    local key="$2"
    echo "$json" | jq -r "$key" 2>/dev/null
}

# Platform detection
get_platform() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "linux"
    else
        echo "unknown"
    fi
}

get_arch() {
    local arch=$(uname -m)
    case "$arch" in
        x86_64)
            echo "amd64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        *)
            echo "$arch"
            ;;
    esac
}

# Print a separator line
print_separator() {
    echo "─────────────────────────────────────────────────────"
}

# Print a header
print_header() {
    echo ""
    print_separator
    echo "  $1"
    print_separator
    echo ""
}

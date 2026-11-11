#!/usr/bin/env bash
set -u

missing_required=0

if [[ -t 1 ]]; then
    green=$'\033[32m'
    red=$'\033[31m'
    yellow=$'\033[33m'
    cyan=$'\033[36m'
    reset=$'\033[0m'
else
    green=''
    red=''
    yellow=''
    cyan=''
    reset=''
fi

status_ok() {
    printf '%s[OK]      %s: %s%s\n' "$green" "$1" "$2" "$reset"
}

status_missing() {
    local required="$3"
    if [[ "$required" == "true" ]]; then
        missing_required=$((missing_required + 1))
        printf '%s[MISSING] %s: %s%s\n' "$red" "$1" "$2" "$reset"
    else
        printf '%s[INFO]    %s: %s%s\n' "$yellow" "$1" "$2" "$reset"
    fi
}

check_command() {
    local name="$1"
    local required="$2"
    shift 2
    local version_arg='--version'

    if [[ "${1:-}" == '--version-arg' ]]; then
        version_arg="$2"
        shift 2
    fi

    local command_name
    for command_name in "$@"; do
        if command -v "$command_name" >/dev/null 2>&1; then
            local version
            version="$($command_name "$version_arg" 2>&1 | head -n 1)"
            [[ -z "$version" ]] && version='found'
            status_ok "$name" "$version"
            return 0
        fi
    done

    status_missing "$name" "not found; tried: $*" "$required"
    return 1
}

python_runner=''
check_python_version() {
    local command_name
    local version
    local major
    local minor
    local below_minimum=''

    for command_name in python3 python; do
        if ! command -v "$command_name" >/dev/null 2>&1; then
            continue
        fi

        version="$($command_name --version 2>&1 | head -n 1)"
        if [[ "$version" =~ Python[[:space:]]+([0-9]+)\.([0-9]+) ]]; then
            major="${BASH_REMATCH[1]}"
            minor="${BASH_REMATCH[2]}"
            if (( major > 3 || (major == 3 && minor >= 11) )); then
                python_runner="$command_name"
                status_ok 'Python' "$version (minimum 3.11)"
                return 0
            fi
            below_minimum+="${command_name}: ${version}; "
        else
            below_minimum+="${command_name}: version unavailable; "
        fi
    done

    if [[ -n "$below_minimum" ]]; then
        status_missing 'Python' "Python 3.11+ required; found ${below_minimum}" true
    else
        status_missing 'Python' 'Python 3.11+ required; command not found' true
    fi
    return 1
}

check_python_module() {
    local name="$1"
    local module="$2"
    local required="$3"

    local runner="${python_runner:-python3}"
    if ! command -v "$runner" >/dev/null 2>&1; then
        status_missing "$name" 'python3 is not available' "$required"
        return 1
    fi

    if "$runner" -c "import $module" >/dev/null 2>&1; then
        status_ok "$name" "Python module $module"
    else
        status_missing "$name" "Python module $module is not installed" "$required"
    fi
}

printf '%sTang Nano 9K development prerequisites%s\n' "$cyan" "$reset"
printf 'macOS: %s\n\n' "$(sw_vers -productVersion 2>/dev/null || echo unknown)"

check_command 'Git' true git
check_python_version
check_command 'Node.js' true node
check_command 'RISC-V GCC' true riscv-none-elf-gcc riscv32-unknown-elf-gcc riscv-none-embed-gcc riscv64-elf-gcc
check_command 'RISC-V objcopy' true riscv-none-elf-objcopy riscv32-unknown-elf-objcopy riscv-none-embed-objcopy riscv64-elf-objcopy
check_command 'Make' true make
check_command 'Verilator' true verilator
check_command 'Icarus Verilog' true --version-arg -V iverilog
check_command 'GTKWave' true gtkwave
check_command 'clang-format' false clang-format

check_python_module 'pytest' pytest true
check_python_module 'Pillow' PIL true

found_gowin=false
gowin_details='manual installation or GOWIN_EDA_HOME required'
if [[ -n "${GOWIN_EDA_HOME:-}" ]]; then
    for candidate in \
        "$GOWIN_EDA_HOME/IDE/bin/gw_sh" \
        "$GOWIN_EDA_HOME/IDE/bin/programmer" \
        "$GOWIN_EDA_HOME/IDE/bin/gw_sh.app/Contents/MacOS/gw_sh"; do
        if [[ -x "$candidate" ]]; then
            found_gowin=true
            gowin_details="$candidate"
            break
        fi
    done
fi

if [[ "$found_gowin" == true ]] || command -v gw_sh >/dev/null 2>&1 || command -v programmer >/dev/null 2>&1; then
    status_ok 'Gowin EDA/Programmer' "${gowin_details}"
else
    status_missing 'Gowin EDA/Programmer' "$gowin_details; use Windows/Linux if unsupported on macOS" false
fi

printf '\n'
if [[ "$missing_required" -eq 0 ]]; then
    printf '%sAll required checks passed.%s\n' "$green" "$reset"
    exit 0
fi

printf '%sMissing required checks: %s%s\n' "$red" "$missing_required" "$reset"
exit 1

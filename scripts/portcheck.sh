#!/bin/sh
# portcheck - Check and manage processes using specific ports
#
# Usage:
#   portcheck <port>           Show process using the port
#   portcheck <port> --kill    Kill the process (with confirmation)
#   portcheck <port> -k        Kill the process immediately
#   portcheck --list           List all listening ports
#   portcheck --help           Show this help
#   portcheck --version        Show version

VERSION="0.1.0"
SCRIPT_NAME="portcheck"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

show_help() {
    printf "%b\n" "${CYAN}${SCRIPT_NAME} v${MS_INSTALLED_VERSION:-$VERSION}${NC}"
    printf "Check and manage processes using specific ports\n\n"
    printf "Usage:\n"
    printf "  %b\n" "${CYAN}${SCRIPT_NAME} <port>${NC}              Show process using the port"
    printf "  %b\n" "${CYAN}${SCRIPT_NAME} <port> --kill${NC}       Kill the process (with confirmation)"
    printf "  %b\n" "${CYAN}${SCRIPT_NAME} <port> -k${NC}           Kill the process immediately"
    printf "  %b\n" "${CYAN}${SCRIPT_NAME} --list${NC}              List all listening ports"
    printf "  %b\n\n" "${CYAN}${SCRIPT_NAME} --list --all${NC}       List all open connections"
    printf "Examples:\n"
    printf "  %b\n" "${CYAN}${SCRIPT_NAME} 3000${NC}"
    printf "  %b\n" "${CYAN}${SCRIPT_NAME} 8080 --kill${NC}"
    printf "  %b\n" "${CYAN}${SCRIPT_NAME} 5432 -k${NC}"
    printf "  %b\n" "${CYAN}${SCRIPT_NAME} --list${NC}"
}

show_version() {
    printf "%s v%s\n" "$SCRIPT_NAME" "${MS_INSTALLED_VERSION:-$VERSION}"
}

# Check if lsof is available
check_lsof() {
    if ! command -v lsof >/dev/null 2>&1; then
        printf "%bError: 'lsof' is required but not installed.%b\n" "${RED}" "${NC}" >&2
        printf "Install it with:\n" >&2
        printf "  macOS/BSD: already included\n" >&2
        printf "  Debian/Ubuntu: sudo apt-get install lsof\n" >&2
        printf "  RHEL/CentOS:   sudo yum install lsof\n" >&2
        return 1
    fi
}

# Validate port number
validate_port() {
    local port="$1"
    case "$port" in
        ''|*[!0-9]*)
            printf "%bError: '%s' is not a valid port number.%b\n" "${RED}" "$port" "${NC}" >&2
            return 1
            ;;
    esac
    if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        printf "%bError: Port must be between 1 and 65535.%b\n" "${RED}" "${NC}" >&2
        return 1
    fi
}

# Get process info for a port
get_port_info() {
    local port="$1"
    lsof -i :"$port" -n -P 2>/dev/null | grep -v "^COMMAND"
}

# Show process using a port
show_port() {
    local port="$1"

    check_lsof || return 1
    validate_port "$port" || return 1

    local info
    info=$(get_port_info "$port")

    if [ -z "$info" ]; then
        printf "%bNo process found on port %s.%b\n" "${GREEN}" "$port" "${NC}"
        return 0
    fi

    printf "%bPort %s is in use:%b\n\n" "${YELLOW}" "$port" "${NC}"
    printf "%b%-12s %-8s %-8s %-6s %s%b\n" "${BOLD}" "COMMAND" "PID" "USER" "FD" "ADDRESS" "${NC}"

    printf '%s\n' "$info" | while IFS= read -r line; do
        cmd=$(printf '%s' "$line" | awk '{print $1}')
        pid=$(printf '%s' "$line" | awk '{print $2}')
        user=$(printf '%s' "$line" | awk '{print $3}')
        fd=$(printf '%s' "$line" | awk '{print $4}')
        addr=$(printf '%s' "$line" | awk '{print $9}')
        printf "%-12s %-8s %-8s %-6s %s\n" "$cmd" "$pid" "$user" "$fd" "$addr"
    done
}

# Kill process(es) using a port
kill_port() {
    local port="$1"
    local force="$2"  # "force" = skip confirmation

    check_lsof || return 1
    validate_port "$port" || return 1

    local info
    info=$(get_port_info "$port")

    if [ -z "$info" ]; then
        printf "%bNo process found on port %s.%b\n" "${GREEN}" "$port" "${NC}"
        return 0
    fi

    # Collect unique PIDs
    local pids
    pids=$(printf '%s\n' "$info" | awk '{print $2}' | sort -u)

    printf "%bProcess(es) using port %s:%b\n" "${YELLOW}" "$port" "${NC}"
    printf '%s\n' "$info" | awk '{printf "  %-12s PID=%-8s USER=%s\n", $1, $2, $3}' | sort -u

    if [ "$force" != "force" ]; then
        printf "\n%bKill the above process(es)? [y/N]%b " "${RED}" "${NC}"
        read -r answer < /dev/tty
        case "$answer" in
            y|Y|yes|YES) ;;
            *)
                printf "Aborted.\n"
                return 0
                ;;
        esac
    fi

    local killed=0
    local failed=0
    for pid in $pids; do
        if kill -TERM "$pid" 2>/dev/null; then
            printf "%bKilled PID %s%b\n" "${GREEN}" "$pid" "${NC}"
            killed=$((killed + 1))
        else
            printf "%bFailed to kill PID %s (try with sudo?)%b\n" "${RED}" "$pid" "${NC}" >&2
            failed=$((failed + 1))
        fi
    done

    if [ "$killed" -gt 0 ]; then
        printf "\n%b%s process(es) terminated on port %s.%b\n" "${GREEN}" "$killed" "$port" "${NC}"
    fi
    if [ "$failed" -gt 0 ]; then
        return 1
    fi
}

# List all listening ports
list_ports() {
    local show_all="$1"

    check_lsof || return 1

    if [ "$show_all" = "all" ]; then
        printf "%bAll open connections:%b\n\n" "${YELLOW}" "${NC}"
        printf "%b%-12s %-8s %-8s %s%b\n" "${BOLD}" "COMMAND" "PID" "USER" "ADDRESS" "${NC}"
        lsof -i -n -P 2>/dev/null | grep -v "^COMMAND" | \
            awk '{printf "%-12s %-8s %-8s %s\n", $1, $2, $3, $9}' | sort -u
    else
        printf "%bListening ports:%b\n\n" "${YELLOW}" "${NC}"
        printf "%b%-8s %-12s %-8s %s%b\n" "${BOLD}" "PORT" "COMMAND" "PID" "USER" "${NC}"
        lsof -i -n -P 2>/dev/null | grep LISTEN | \
            awk '{
                addr = $9
                split(addr, parts, ":")
                port = parts[length(parts)]
                printf "%-8s %-12s %-8s %s\n", port, $1, $2, $3
            }' | sort -t' ' -k1 -n | sort -u -k1,1
    fi
}

# Main
case "$1" in
    -h|--help|help)
        show_help
        exit 0
        ;;
    -v|--version)
        show_version
        exit 0
        ;;
    --list|-l)
        if [ "$2" = "--all" ] || [ "$2" = "-a" ]; then
            list_ports "all"
        else
            list_ports
        fi
        exit $?
        ;;
    ''|-*)
        show_help
        exit 1
        ;;
    *)
        PORT="$1"
        shift
        case "$1" in
            --kill)
                kill_port "$PORT"
                ;;
            -k)
                kill_port "$PORT" "force"
                ;;
            '')
                show_port "$PORT"
                ;;
            *)
                printf "%bUnknown option: %s%b\n" "${RED}" "$1" "${NC}" >&2
                show_help
                exit 1
                ;;
        esac
        exit $?
        ;;
esac

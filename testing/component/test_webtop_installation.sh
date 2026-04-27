#!/bin/bash

# TEST_DESCRIPTION: Validate webtop component installation and configuration

set -euo pipefail

# Test configuration
TEST_NAME="webtop_installation"
COMPONENT="webtop"

# Test results
PASS=0
FAIL=1

# Helper functions
log_info() { echo "[INFO] $1"; }
log_pass() { echo "[PASS] $1"; }
log_fail() { echo "[FAIL] $1"; }

# =============================================================================
# WEBTOP INSTALLATION TESTS
# =============================================================================

test_webtop_packages() {
    log_info "Testing webtop package installation..."
    
    local packages=(
        "chromium"
        "mousepad"
        "gnome-terminal"
        "gnome-session-flashback"
        "metacity"
    )
    
    for package in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii.*$package"; then
            log_fail "Package not installed: $package"
            return $FAIL
        fi
    done
    
    log_pass "All required packages are installed"
    return $PASS
}

test_webtop_directories() {
    log_info "Testing webtop directory structure..."
    
    # Check if required directories exist
    local directories=(
        "/defaults/gnome"
        "/usr/share/selkies/www"
        "/usr/bin"
        "/usr/local/bin"
        "/etc/selkies"
    )
    
    for directory in "${directories[@]}"; do
        if [[ ! -d "$directory" ]]; then
            log_fail "Directory not found: $directory"
            return $FAIL
        fi
    done
    
    log_pass "All required directories exist"
    return $PASS
}

test_webtop_binaries() {
    log_info "Testing webtop binary modifications..."
    
    local binaries=(
        "/usr/bin/chromium"
        "/usr/local/bin/wrapped-chromium"
    )
    
    for binary in "${binaries[@]}"; do
        if [[ ! -f "$binary" ]]; then
            log_fail "Binary not found: $binary"
            return $FAIL
        fi
    done
    
    for binary in "${binaries[@]}"; do
        if [[ ! -x "$binary" ]]; then
            log_fail "Binary is not executable: $binary"
            return $FAIL
        fi
    done
    
    if [[ ! -f /usr/bin/chromium-browser ]]; then
        log_fail "Real Chromium binary not found at /usr/bin/chromium-browser"
        return $FAIL
    fi
    
    log_pass "All required binaries exist and are executable"
    return $PASS
}

test_webtop_configuration() {
    log_info "Testing webtop configuration files..."
    
    local config_files=(
        "/defaults/startwm.sh"
        "/defaults/gnome/wallpapers/appbox.svg"
    )
    
    for config_file in "${config_files[@]}"; do
        if [[ ! -f "$config_file" ]]; then
            log_fail "Configuration file not found: $config_file"
            return $FAIL
        fi
    done
    
    if [[ ! -x "/defaults/startwm.sh" ]]; then
        log_fail "startwm.sh is not executable"
        return $FAIL
    fi
    
    if ! grep -q "gnome-flashback-metacity" /defaults/startwm.sh; then
        log_fail "startwm.sh does not start GNOME Flashback"
        return $FAIL
    fi
    
    log_pass "All configuration files exist and are valid"
    return $PASS
}

test_webtop_integration() {
    log_info "Testing webtop integration with selkies..."
    
    # Check if webtop flag file exists
    if [[ ! -f "/etc/selkies/webtop-installed" ]]; then
        log_fail "Webtop integration flag file not found"
        return $FAIL
    fi
    
    # Check if selkies desktop service is updated
    if ! grep -q "webtop-installed" /etc/selkies/svc-de.sh; then
        log_fail "Selkies desktop service not updated for webtop integration"
        return $FAIL
    fi
    
    log_pass "Webtop integration is properly configured"
    return $PASS
}

test_webtop_environment() {
    log_info "Testing webtop environment variables..."
    
    # Check if webtop environment variables are set
    local env_vars=(
        'TITLE="Ubuntu GNOME"'
    )
    
    for env_var in "${env_vars[@]}"; do
        if ! grep -q "$env_var" /etc/environment; then
            log_fail "Environment variable not found: $env_var"
            return $FAIL
        fi
    done
    
    log_pass "All required environment variables are set"
    return $PASS
}

test_webtop_icon() {
    log_info "Testing webtop icon installation..."
    
    # Check if webtop icon exists
    if [[ ! -f "/usr/share/selkies/www/icon.png" ]]; then
        log_fail "Webtop icon not found"
        return $FAIL
    fi
    
    # Check if icon is readable
    if [[ ! -r "/usr/share/selkies/www/icon.png" ]]; then
        log_fail "Webtop icon is not readable"
        return $FAIL
    fi
    
    # Check if icon is a valid PNG file
    if ! file /usr/share/selkies/www/icon.png | grep -q "PNG image"; then
        log_fail "Webtop icon is not a valid PNG file"
        return $FAIL
    fi
    
    log_pass "Webtop icon is properly installed"
    return $PASS
}

test_webtop_desktop_entry() {
    log_info "Testing webtop desktop entry modifications..."
    
    local desktop=""
    for candidate in /usr/share/applications/chromium.desktop /usr/share/applications/chromium-browser.desktop; do
        if [[ -f "$candidate" ]]; then
            desktop="$candidate"
            break
        fi
    done
    if [[ -z "$desktop" ]]; then
        log_fail "No chromium .desktop under /usr/share/applications"
        return $FAIL
    fi
    
    if ! grep -q "wrapped-chromium" "$desktop"; then
        log_fail "Chromium desktop entry not modified to use wrapped chromium ($desktop)"
        return $FAIL
    fi
    
    log_pass "Desktop entry modifications are correct"
    return $PASS
}

test_webtop_xscreensaver() {
    log_info "Testing xscreensaver autostart removal..."
    
    # Check if xscreensaver autostart is removed
    if [[ -f "/etc/xdg/autostart/xscreensaver.desktop" ]]; then
        log_fail "xscreensaver autostart file still exists"
        return $FAIL
    fi
    
    log_pass "xscreensaver autostart properly removed"
    return $PASS
}

test_webtop_repository() {
    log_info "Testing webtop repository configuration..."
    
    # Check if xtradeb repository is added
    if [[ ! -f "/etc/apt/sources.list.d/xtradeb.list" ]]; then
        log_fail "xtradeb repository not added"
        return $FAIL
    fi
    
    if ! grep -qE "ppa.launchpadcontent.net/xtradeb/apps/ubuntu (noble|resolute)" /etc/apt/sources.list.d/xtradeb.list; then
        log_fail "xtradeb repository entry is incorrect"
        return $FAIL
    fi
    
    log_pass "Repository configuration is correct"
    return $PASS
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

main() {
    log_info "Starting webtop installation validation tests..."
    
    local test_results=()
    local tests=(
        "test_webtop_packages"
        "test_webtop_directories"
        "test_webtop_binaries"
        "test_webtop_configuration"
        "test_webtop_integration"
        "test_webtop_environment"
        "test_webtop_icon"
        "test_webtop_desktop_entry"
        "test_webtop_xscreensaver"
        "test_webtop_repository"
    )
    
    # Run all tests
    for test_function in "${tests[@]}"; do
        if $test_function; then
            test_results+=("PASS")
        else
            test_results+=("FAIL")
        fi
    done
    
    # Calculate results
    local total_tests=${#tests[@]}
    local passed_tests=$(printf '%s\n' "${test_results[@]}" | grep -c "PASS")
    local failed_tests=$(printf '%s\n' "${test_results[@]}" | grep -c "FAIL")
    
    echo ""
    echo "=================================="
    echo "  WEBTOP INSTALLATION TEST RESULTS"
    echo "=================================="
    echo "Total Tests: $total_tests"
    echo "Passed:      $passed_tests"
    echo "Failed:      $failed_tests"
    echo "=================================="
    
    # Return appropriate exit code
    if [[ $failed_tests -eq 0 ]]; then
        log_pass "All webtop installation tests passed"
        exit $PASS
    else
        log_fail "Some webtop installation tests failed"
        exit $FAIL
    fi
}

# Run main function
main "$@" 
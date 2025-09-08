#!/bin/bash

# TEST_DESCRIPTION: Validate selkies component installation and configuration

set -euo pipefail

# Test configuration
TEST_NAME="selkies_installation"
COMPONENT="selkies"

# Test results
PASS=0
FAIL=1

# Helper functions
log_info() { echo "[INFO] $1"; }
log_pass() { echo "[PASS] $1"; }
log_fail() { echo "[FAIL] $1"; }

# =============================================================================
# SELKIES INSTALLATION TESTS
# =============================================================================

test_selkies_packages() {
    log_info "Testing selkies package installation..."
    
    # Check if key packages are installed
    local packages=(
        "nginx"
        "pulseaudio"
        "xvfb"
        "docker.io"
        "nodejs"
        "npm"
        "python3"
        "python3-pip"
        "openbox"
        "xorg"
        "mesa-utils"
        "curl"
        "wget"
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

test_selkies_directories() {
    log_info "Testing selkies directory structure..."
    
    # Check if required directories exist
    local directories=(
        "/usr/share/selkies"
        "/usr/share/selkies/www"
        "/usr/lib"
        "/opt/lib"
        "/etc/selkies"
        "/defaults"
        "/config"
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

test_selkies_binaries() {
    log_info "Testing selkies binary files..."
    
    # Check if required binaries exist
    local binaries=(
        "/usr/local/bin/Xvfb"
        "/usr/lib/selkies_joystick_interposer.so"
        "/opt/lib/libudev.so.1.0.0-fake"
    )
    
    for binary in "${binaries[@]}"; do
        if [[ ! -f "$binary" ]]; then
            log_fail "Binary not found: $binary"
            return $FAIL
        fi
    done
    
    # Check if binaries are executable
    if [[ ! -x "/usr/local/bin/Xvfb" ]]; then
        log_fail "Xvfb binary is not executable"
        return $FAIL
    fi
    
    log_pass "All required binaries exist and are executable"
    return $PASS
}

test_selkies_services() {
    log_info "Testing selkies systemd services..."
    
    # Check if systemd service files exist
    local services=(
        "xvfb.service"
        "selkies-pulseaudio.service"
        "selkies-docker.service"
        "selkies-nginx.service"
        "selkies.service"
        "selkies-desktop.service"
    )
    
    for service in "${services[@]}"; do
        if [[ ! -f "/etc/systemd/system/$service" ]]; then
            log_fail "Service file not found: $service"
            return $FAIL
        fi
    done
    
    # Check if services are enabled
    for service in "${services[@]}"; do
        if ! systemctl is-enabled "$service" >/dev/null 2>&1; then
            log_fail "Service not enabled: $service"
            return $FAIL
        fi
    done
    
    log_pass "All systemd services exist and are enabled"
    return $PASS
}

test_selkies_configuration() {
    log_info "Testing selkies configuration files..."
    
    # Check if configuration files exist
    local config_files=(
        "/defaults/autostart"
        "/defaults/menu.xml"
        "/defaults/startwm.sh"
        "/defaults/default.conf"
        "/etc/selkies/init-nginx.sh"
        "/etc/selkies/init-selkies-config.sh"
        "/etc/selkies/init-video.sh"
        "/etc/selkies/svc-de.sh"
    )
    
    for config_file in "${config_files[@]}"; do
        if [[ ! -f "$config_file" ]]; then
            log_fail "Configuration file not found: $config_file"
            return $FAIL
        fi
    done
    
    # Check if scripts are executable
    local scripts=(
        "/defaults/startwm.sh"
        "/etc/selkies/init-nginx.sh"
        "/etc/selkies/init-selkies-config.sh"
        "/etc/selkies/init-video.sh"
        "/etc/selkies/svc-de.sh"
    )
    
    for script in "${scripts[@]}"; do
        if [[ ! -x "$script" ]]; then
            log_fail "Script is not executable: $script"
            return $FAIL
        fi
    done
    
    log_pass "All configuration files exist and scripts are executable"
    return $PASS
}

test_selkies_user() {
    log_info "Testing selkies user configuration..."
    
    # Check if appbox user exists
    if ! id -u appbox >/dev/null 2>&1; then
        log_fail "User 'appbox' does not exist"
        return $FAIL
    fi
    
    # Check if appbox user is in required groups
    local groups=("docker" "audio" "video" "pulse" "pulse-access")
    for group in "${groups[@]}"; do
        if ! id -nG appbox | grep -q "$group"; then
            log_fail "User 'appbox' is not in group: $group"
            return $FAIL
        fi
    done
    
    # Check if home directory exists and has correct permissions
    if [[ ! -d "/config" ]]; then
        log_fail "User home directory /config does not exist"
        return $FAIL
    fi
    
    local owner=$(stat -c "%U" /config)
    if [[ "$owner" != "appbox" ]]; then
        log_fail "/config directory is not owned by appbox user (owner: $owner)"
        return $FAIL
    fi
    
    log_pass "User 'appbox' is properly configured"
    return $PASS
}

test_selkies_environment() {
    log_info "Testing selkies environment variables..."
    
    # Check if environment variables are set
    local env_vars=(
        "DISPLAY=:1"
        "PULSE_RUNTIME_PATH=/defaults"
        "SELKIES_INTERPOSER=/usr/lib/selkies_joystick_interposer.so"
        "TITLE=Selkies"
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

test_selkies_web_interface() {
    log_info "Testing selkies web interface files..."
    
    # Check if web interface files exist
    local web_files=(
        "/usr/share/selkies/www/index.html"
        "/usr/share/selkies/www/manifest.json"
    )
    
    for web_file in "${web_files[@]}"; do
        if [[ ! -f "$web_file" ]]; then
            log_fail "Web interface file not found: $web_file"
            return $FAIL
        fi
    done
    
    # Check if web files are readable
    for web_file in "${web_files[@]}"; do
        if [[ ! -r "$web_file" ]]; then
            log_fail "Web interface file is not readable: $web_file"
            return $FAIL
        fi
    done
    
    log_pass "Web interface files exist and are readable"
    return $PASS
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

main() {
    log_info "Starting selkies installation validation tests..."
    
    local test_results=()
    local tests=(
        "test_selkies_packages"
        "test_selkies_directories"
        "test_selkies_binaries"
        "test_selkies_services"
        "test_selkies_configuration"
        "test_selkies_user"
        "test_selkies_environment"
        "test_selkies_web_interface"
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
    echo "  SELKIES INSTALLATION TEST RESULTS"
    echo "=================================="
    echo "Total Tests: $total_tests"
    echo "Passed:      $passed_tests"
    echo "Failed:      $failed_tests"
    echo "=================================="
    
    # Return appropriate exit code
    if [[ $failed_tests -eq 0 ]]; then
        log_pass "All selkies installation tests passed"
        exit $PASS
    else
        log_fail "Some selkies installation tests failed"
        exit $FAIL
    fi
}

# Run main function
main "$@" 
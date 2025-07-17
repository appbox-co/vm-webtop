#!/bin/bash

# TEST_DESCRIPTION: End-to-end integration test for complete webtop functionality

set -euo pipefail

# Test configuration
TEST_NAME="end_to_end_integration"
COMPONENT="integration"

# Test results
PASS=0
FAIL=1

# Test timeouts (seconds)
SERVICE_START_TIMEOUT=60
WEB_INTERFACE_TIMEOUT=30
DESKTOP_STARTUP_TIMEOUT=90

# Helper functions
log_info() { echo "[INFO] $1"; }
log_pass() { echo "[PASS] $1"; }
log_fail() { echo "[FAIL] $1"; }

# =============================================================================
# INTEGRATION TESTS
# =============================================================================

test_service_startup_sequence() {
    log_info "Testing service startup sequence..."
    
    # Stop all services first
    local services=(
        "selkies-desktop.service"
        "selkies.service"
        "selkies-nginx.service"
        "selkies-docker.service"
        "selkies-pulseaudio.service"
        "xvfb.service"
    )
    
    for service in "${services[@]}"; do
        systemctl stop "$service" 2>/dev/null || true
    done
    
    # Wait a moment for services to stop
    sleep 5
    
    # Start the main service (should start all dependencies)
    log_info "Starting selkies-desktop.service..."
    systemctl start selkies-desktop.service
    
    # Wait for services to start
    local timeout=$SERVICE_START_TIMEOUT
    while [[ $timeout -gt 0 ]]; do
        local all_active=true
        
        for service in "${services[@]}"; do
            if ! systemctl is-active "$service" >/dev/null 2>&1; then
                all_active=false
                break
            fi
        done
        
        if [[ "$all_active" == true ]]; then
            log_pass "All services started successfully"
            return $PASS
        fi
        
        sleep 1
        ((timeout--))
    done
    
    log_fail "Service startup timeout or failure"
    
    # Log service statuses for debugging
    for service in "${services[@]}"; do
        echo "Status of $service:"
        systemctl status "$service" --no-pager -l || true
        echo ""
    done
    
    return $FAIL
}

test_web_interface_accessibility() {
    log_info "Testing web interface accessibility..."
    
    # Wait for nginx to be ready
    local timeout=$WEB_INTERFACE_TIMEOUT
    while [[ $timeout -gt 0 ]]; do
        if curl -s -f http://localhost:3000 >/dev/null 2>&1; then
            log_pass "Web interface is accessible"
            return $PASS
        fi
        sleep 1
        ((timeout--))
    done
    
    log_fail "Web interface not accessible after $WEB_INTERFACE_TIMEOUT seconds"
    
    # Log nginx status for debugging
    echo "Nginx status:"
    systemctl status selkies-nginx.service --no-pager -l || true
    echo ""
    
    return $FAIL
}

test_web_interface_content() {
    log_info "Testing web interface content..."
    
    # Download web interface content
    local response=$(curl -s http://localhost:3000 2>/dev/null)
    
    if [[ -z "$response" ]]; then
        log_fail "Web interface returned empty response"
        return $FAIL
    fi
    
    # Check if response contains expected content
    if ! echo "$response" | grep -q "selkies"; then
        log_fail "Web interface does not contain expected selkies content"
        return $FAIL
    fi
    
    # Check if title is correct
    if grep -q 'TITLE="Ubuntu XFCE"' /etc/environment; then
        if ! echo "$response" | grep -q "Ubuntu XFCE"; then
            log_fail "Web interface does not contain expected title"
            return $FAIL
        fi
    fi
    
    log_pass "Web interface content is correct"
    return $PASS
}

test_display_server() {
    log_info "Testing display server functionality..."
    
    # Check if Xvfb is running
    if ! pgrep -f "[X]vfb" >/dev/null; then
        log_fail "Xvfb process not found"
        return $FAIL
    fi
    
    # Check if display :1 is available
    if ! DISPLAY=:1 xset q >/dev/null 2>&1; then
        log_fail "Display :1 is not available"
        return $FAIL
    fi
    
    # Check if display has correct resolution
    local resolution=$(DISPLAY=:1 xrandr | grep -o "[0-9]*x[0-9]*" | head -1)
    if [[ -z "$resolution" ]]; then
        log_fail "Could not determine display resolution"
        return $FAIL
    fi
    
    log_pass "Display server is functioning correctly (resolution: $resolution)"
    return $PASS
}

test_desktop_environment() {
    log_info "Testing desktop environment..."
    
    # Check if webtop is installed
    if [[ -f "/etc/selkies/webtop-installed" ]]; then
        log_info "Webtop is installed, testing XFCE desktop environment..."
        
        # Check if XFCE processes are running
        local timeout=$DESKTOP_STARTUP_TIMEOUT
        while [[ $timeout -gt 0 ]]; do
            if pgrep -f "xfce4-session" >/dev/null; then
                log_pass "XFCE desktop environment is running"
                return $PASS
            fi
            sleep 1
            ((timeout--))
        done
        
        log_fail "XFCE desktop environment not running after $DESKTOP_STARTUP_TIMEOUT seconds"
        return $FAIL
    else
        log_info "Webtop not installed, testing OpenBox desktop environment..."
        
        # Check if OpenBox processes are running
        local timeout=$DESKTOP_STARTUP_TIMEOUT
        while [[ $timeout -gt 0 ]]; do
            if pgrep -f "openbox" >/dev/null; then
                log_pass "OpenBox desktop environment is running"
                return $PASS
            fi
            sleep 1
            ((timeout--))
        done
        
        log_fail "OpenBox desktop environment not running after $DESKTOP_STARTUP_TIMEOUT seconds"
        return $FAIL
    fi
}

test_audio_system() {
    log_info "Testing audio system..."
    
    # Check if PulseAudio is running
    if ! pgrep -f "pulseaudio" >/dev/null; then
        log_fail "PulseAudio process not found"
        return $FAIL
    fi
    
    # Check if audio devices are available
    if ! sudo -u abc PULSE_RUNTIME_PATH=/defaults pactl info >/dev/null 2>&1; then
        log_fail "Could not connect to PulseAudio server"
        return $FAIL
    fi
    
    # Check if audio modules are loaded
    if ! sudo -u abc PULSE_RUNTIME_PATH=/defaults pactl list modules | grep -q "module-null-sink"; then
        log_fail "Audio modules not loaded"
        return $FAIL
    fi
    
    log_pass "Audio system is functioning correctly"
    return $PASS
}

test_docker_integration() {
    log_info "Testing Docker integration..."
    
    # Check if Docker daemon is running
    if ! systemctl is-active docker >/dev/null 2>&1; then
        log_fail "Docker daemon is not running"
        return $FAIL
    fi
    
    # Check if Docker is accessible
    if ! docker info >/dev/null 2>&1; then
        log_fail "Docker daemon is not accessible"
        return $FAIL
    fi
    
    # Check if abc user can access Docker
    if ! sudo -u abc docker info >/dev/null 2>&1; then
        log_fail "User 'abc' cannot access Docker"
        return $FAIL
    fi
    
    log_pass "Docker integration is functioning correctly"
    return $PASS
}

test_browser_functionality() {
    log_info "Testing browser functionality..."
    
    # Check if chromium wrapper exists and is executable
    if [[ ! -x "/usr/bin/chromium" ]]; then
        log_fail "Chromium wrapper not found or not executable"
        return $FAIL
    fi
    
    # Check if wrapped chromium exists
    if [[ ! -x "/usr/local/bin/wrapped-chromium" ]]; then
        log_fail "Wrapped chromium not found or not executable"
        return $FAIL
    fi
    
    # Check if desktop entry is modified
    if [[ -f "/usr/share/applications/chromium.desktop" ]]; then
        if ! grep -q "wrapped-chromium" /usr/share/applications/chromium.desktop; then
            log_fail "Chromium desktop entry not modified"
            return $FAIL
        fi
    fi
    
    log_pass "Browser functionality is correctly configured"
    return $PASS
}

test_websocket_connection() {
    log_info "Testing WebSocket connection..."
    
    # Check if selkies WebSocket endpoint is available
    if ! curl -s -f http://localhost:8082 >/dev/null 2>&1; then
        log_fail "Selkies WebSocket endpoint not available"
        return $FAIL
    fi
    
    # Test WebSocket upgrade (basic check)
    local websocket_test=$(curl -s -H "Upgrade: websocket" -H "Connection: Upgrade" -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: test" http://localhost:8082 2>&1)
    
    if [[ $? -ne 0 ]]; then
        log_fail "WebSocket connection test failed"
        return $FAIL
    fi
    
    log_pass "WebSocket connection is functioning"
    return $PASS
}

test_file_system_permissions() {
    log_info "Testing file system permissions..."
    
    # Check if abc user can write to /config
    if ! sudo -u abc test -w /config; then
        log_fail "User 'abc' cannot write to /config directory"
        return $FAIL
    fi
    
    # Check if Desktop directory exists and is writable
    if [[ ! -d "/config/Desktop" ]]; then
        log_fail "Desktop directory not found"
        return $FAIL
    fi
    
    if ! sudo -u abc test -w /config/Desktop; then
        log_fail "User 'abc' cannot write to Desktop directory"
        return $FAIL
    fi
    
    # Test file creation
    local test_file="/config/test_file.tmp"
    if ! sudo -u abc touch "$test_file"; then
        log_fail "User 'abc' cannot create files in /config"
        return $FAIL
    fi
    
    # Cleanup test file
    rm -f "$test_file"
    
    log_pass "File system permissions are correct"
    return $PASS
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

main() {
    log_info "Starting end-to-end integration tests..."
    
    local test_results=()
    local tests=(
        "test_service_startup_sequence"
        "test_web_interface_accessibility"
        "test_web_interface_content"
        "test_display_server"
        "test_desktop_environment"
        "test_audio_system"
        "test_docker_integration"
        "test_browser_functionality"
        "test_websocket_connection"
        "test_file_system_permissions"
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
    echo "  END-TO-END INTEGRATION TEST RESULTS"
    echo "=================================="
    echo "Total Tests: $total_tests"
    echo "Passed:      $passed_tests"
    echo "Failed:      $failed_tests"
    echo "=================================="
    
    # Return appropriate exit code
    if [[ $failed_tests -eq 0 ]]; then
        log_pass "All end-to-end integration tests passed"
        exit $PASS
    else
        log_fail "Some end-to-end integration tests failed"
        exit $FAIL
    fi
}

# Run main function
main "$@" 
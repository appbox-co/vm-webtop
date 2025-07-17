#!/bin/bash

# TEST_DESCRIPTION: User acceptance tests for webtop system usability and functionality

set -euo pipefail

# Test configuration
TEST_NAME="user_acceptance"
COMPONENT="user-acceptance"

# Test results
PASS=0
FAIL=1

# Test timeouts (seconds)
DESKTOP_LOAD_TIMEOUT=120
APPLICATION_START_TIMEOUT=30

# Helper functions
log_info() { echo "[INFO] $1"; }
log_pass() { echo "[PASS] $1"; }
log_fail() { echo "[FAIL] $1"; }
log_test() { echo "[TEST] $1"; }

# =============================================================================
# USER ACCEPTANCE TESTS
# =============================================================================

test_web_interface_accessibility() {
    log_test "Testing web interface accessibility..."
    
    # Test web interface is accessible
    local response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000)
    if [[ "$response" != "200" ]]; then
        log_fail "Web interface is not accessible (HTTP $response)"
        return $FAIL
    fi
    
    # Test web interface loads correctly
    local content=$(curl -s http://localhost:3000)
    if [[ -z "$content" ]]; then
        log_fail "Web interface returns empty content"
        return $FAIL
    fi
    
    # Test if web interface contains expected elements
    if ! echo "$content" | grep -qi "selkies"; then
        log_fail "Web interface does not contain expected content"
        return $FAIL
    fi
    
    log_pass "Web interface is accessible and functional"
    return $PASS
}

test_desktop_environment_startup() {
    log_test "Testing desktop environment startup..."
    
    # Check if desktop environment is running
    local timeout=$DESKTOP_LOAD_TIMEOUT
    local desktop_started=false
    
    while [[ $timeout -gt 0 ]]; do
        if [[ -f "/etc/selkies/webtop-installed" ]]; then
            # Check for XFCE desktop
            if pgrep -f "xfce4-session" >/dev/null; then
                desktop_started=true
                break
            fi
        else
            # Check for OpenBox desktop
            if pgrep -f "openbox" >/dev/null; then
                desktop_started=true
                break
            fi
        fi
        
        sleep 1
        ((timeout--))
    done
    
    if [[ "$desktop_started" == false ]]; then
        log_fail "Desktop environment did not start within $DESKTOP_LOAD_TIMEOUT seconds"
        return $FAIL
    fi
    
    log_pass "Desktop environment started successfully"
    return $PASS
}

test_browser_functionality() {
    log_test "Testing browser functionality..."
    
    # Check if browser wrapper exists
    if [[ ! -x "/usr/bin/chromium" ]]; then
        log_fail "Browser wrapper not found or not executable"
        return $FAIL
    fi
    
    # Check if wrapped browser exists
    if [[ ! -x "/usr/local/bin/wrapped-chromium" ]]; then
        log_fail "Wrapped browser not found or not executable"
        return $FAIL
    fi
    
    # Test browser can be launched (check if it starts without crashing)
    timeout $APPLICATION_START_TIMEOUT sudo -u abc DISPLAY=:1 /usr/bin/chromium --version >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        log_fail "Browser cannot be launched or crashes immediately"
        return $FAIL
    fi
    
    log_pass "Browser functionality is working correctly"
    return $PASS
}

test_file_manager_functionality() {
    log_test "Testing file manager functionality..."
    
    # Check if file manager (thunar) is available
    if [[ ! -x "/usr/bin/thunar" ]]; then
        log_fail "File manager not found or not executable"
        return $FAIL
    fi
    
    # Test file manager can be launched
    timeout $APPLICATION_START_TIMEOUT sudo -u abc DISPLAY=:1 thunar --version >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        log_fail "File manager cannot be launched or crashes immediately"
        return $FAIL
    fi
    
    log_pass "File manager functionality is working correctly"
    return $PASS
}

test_terminal_functionality() {
    log_test "Testing terminal functionality..."
    
    # Check if terminal is available
    if [[ ! -x "/usr/bin/xfce4-terminal" ]]; then
        log_fail "Terminal application not found or not executable"
        return $FAIL
    fi
    
    # Test terminal can be launched
    timeout $APPLICATION_START_TIMEOUT sudo -u abc DISPLAY=:1 xfce4-terminal --version >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        log_fail "Terminal cannot be launched or crashes immediately"
        return $FAIL
    fi
    
    log_pass "Terminal functionality is working correctly"
    return $PASS
}

test_text_editor_functionality() {
    log_test "Testing text editor functionality..."
    
    # Check if text editor (mousepad) is available
    if [[ ! -x "/usr/bin/mousepad" ]]; then
        log_fail "Text editor not found or not executable"
        return $FAIL
    fi
    
    # Test text editor can be launched
    timeout $APPLICATION_START_TIMEOUT sudo -u abc DISPLAY=:1 mousepad --version >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        log_fail "Text editor cannot be launched or crashes immediately"
        return $FAIL
    fi
    
    log_pass "Text editor functionality is working correctly"
    return $PASS
}

test_audio_functionality() {
    log_test "Testing audio functionality..."
    
    # Check if audio system is running
    if ! pgrep -f "pulseaudio" >/dev/null; then
        log_fail "Audio system is not running"
        return $FAIL
    fi
    
    # Test audio server connectivity
    if ! sudo -u abc PULSE_RUNTIME_PATH=/defaults pactl info >/dev/null 2>&1; then
        log_fail "Cannot connect to audio server"
        return $FAIL
    fi
    
    # Check if audio devices are available
    local audio_devices=$(sudo -u abc PULSE_RUNTIME_PATH=/defaults pactl list sinks | grep -c "Sink #")
    if [[ $audio_devices -lt 1 ]]; then
        log_fail "No audio devices available"
        return $FAIL
    fi
    
    log_pass "Audio functionality is working correctly"
    return $PASS
}

test_file_operations() {
    log_test "Testing file operations..."
    
    # Create test file
    local test_file="/config/user_test_file.txt"
    local test_content="This is a test file for user acceptance testing"
    
    # Test file creation
    if ! sudo -u abc bash -c "echo '$test_content' > '$test_file'"; then
        log_fail "Cannot create files in user directory"
        return $FAIL
    fi
    
    # Test file reading
    local file_content=$(sudo -u abc cat "$test_file")
    if [[ "$file_content" != "$test_content" ]]; then
        log_fail "Cannot read files from user directory"
        return $FAIL
    fi
    
    # Test file modification
    local modified_content="Modified content"
    if ! sudo -u abc bash -c "echo '$modified_content' >> '$test_file'"; then
        log_fail "Cannot modify files in user directory"
        return $FAIL
    fi
    
    # Test file deletion
    if ! sudo -u abc rm "$test_file"; then
        log_fail "Cannot delete files from user directory"
        return $FAIL
    fi
    
    log_pass "File operations are working correctly"
    return $PASS
}

test_desktop_customization() {
    log_test "Testing desktop customization..."
    
    # Check if desktop configuration directory exists
    if [[ ! -d "/config/.config" ]]; then
        log_fail "Desktop configuration directory not found"
        return $FAIL
    fi
    
    # Check if user can modify desktop configuration
    local config_dir="/config/.config/test_config"
    if ! sudo -u abc mkdir -p "$config_dir"; then
        log_fail "Cannot create configuration directories"
        return $FAIL
    fi
    
    # Test configuration file creation
    local config_file="$config_dir/test.conf"
    if ! sudo -u abc bash -c "echo 'test=value' > '$config_file'"; then
        log_fail "Cannot create configuration files"
        return $FAIL
    fi
    
    # Cleanup test configuration
    sudo -u abc rm -rf "$config_dir"
    
    log_pass "Desktop customization is working correctly"
    return $PASS
}

test_clipboard_functionality() {
    log_test "Testing clipboard functionality..."
    
    # Check if clipboard utilities are available
    if ! command -v xclip >/dev/null 2>&1; then
        log_info "xclip not available, installing for clipboard testing..."
        apt-get update && apt-get install -y xclip
    fi
    
    # Test clipboard operations
    local test_text="Clipboard test content"
    
    # Test clipboard writing
    if ! sudo -u abc bash -c "echo '$test_text' | DISPLAY=:1 xclip -selection clipboard"; then
        log_fail "Cannot write to clipboard"
        return $FAIL
    fi
    
    # Test clipboard reading
    local clipboard_content=$(sudo -u abc bash -c "DISPLAY=:1 xclip -selection clipboard -o")
    if [[ "$clipboard_content" != "$test_text" ]]; then
        log_fail "Cannot read from clipboard"
        return $FAIL
    fi
    
    log_pass "Clipboard functionality is working correctly"
    return $PASS
}

test_web_interface_interaction() {
    log_test "Testing web interface interaction..."
    
    # Test if web interface responds to different endpoints
    local endpoints=("/" "/websocket")
    
    for endpoint in "${endpoints[@]}"; do
        local response=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:3000$endpoint")
        if [[ "$response" != "200" && "$response" != "404" && "$response" != "426" ]]; then
            log_fail "Web interface endpoint $endpoint returned unexpected response: $response"
            return $FAIL
        fi
    done
    
    # Test if WebSocket endpoint is accessible
    if ! curl -s -f http://localhost:8082 >/dev/null 2>&1; then
        log_fail "WebSocket endpoint is not accessible"
        return $FAIL
    fi
    
    log_pass "Web interface interaction is working correctly"
    return $PASS
}

test_docker_integration() {
    log_test "Testing Docker integration..."
    
    # Check if Docker is accessible to user
    if ! sudo -u abc docker info >/dev/null 2>&1; then
        log_fail "Docker is not accessible to user"
        return $FAIL
    fi
    
    # Test basic Docker operations
    if ! sudo -u abc docker ps >/dev/null 2>&1; then
        log_fail "Cannot list Docker containers"
        return $FAIL
    fi
    
    # Test Docker image operations
    if ! sudo -u abc docker images >/dev/null 2>&1; then
        log_fail "Cannot list Docker images"
        return $FAIL
    fi
    
    log_pass "Docker integration is working correctly"
    return $PASS
}

test_system_responsiveness() {
    log_test "Testing system responsiveness..."
    
    # Test web interface response time
    local start_time=$(date +%s.%3N)
    curl -s -f http://localhost:3000 >/dev/null 2>&1
    local end_time=$(date +%s.%3N)
    local response_time=$(echo "$end_time - $start_time" | bc)
    
    if [[ $(echo "$response_time > 5.0" | bc) -eq 1 ]]; then
        log_fail "Web interface response time too slow: ${response_time}s"
        return $FAIL
    fi
    
    # Test display server responsiveness
    local start_time=$(date +%s.%3N)
    sudo -u abc DISPLAY=:1 xset q >/dev/null 2>&1
    local end_time=$(date +%s.%3N)
    local display_time=$(echo "$end_time - $start_time" | bc)
    
    if [[ $(echo "$display_time > 1.0" | bc) -eq 1 ]]; then
        log_fail "Display server response time too slow: ${display_time}s"
        return $FAIL
    fi
    
    log_pass "System responsiveness is acceptable"
    return $PASS
}

test_error_handling() {
    log_test "Testing error handling..."
    
    # Test handling of invalid file operations
    if sudo -u abc touch "/root/invalid_file.txt" 2>/dev/null; then
        log_fail "System allows invalid file operations"
        return $FAIL
    fi
    
    # Test handling of invalid commands
    if sudo -u abc DISPLAY=:1 /nonexistent/command 2>/dev/null; then
        log_fail "System does not handle invalid commands properly"
        return $FAIL
    fi
    
    log_pass "Error handling is working correctly"
    return $PASS
}

generate_user_acceptance_report() {
    log_info "Generating user acceptance report..."
    
    local report_file="/tmp/webtop-tests/user-acceptance-report.txt"
    
    cat > "$report_file" << EOF
Ubuntu VM Webtop Environment - User Acceptance Test Report
Generated: $(date)

Test Categories:
- Web Interface Accessibility
- Desktop Environment Startup
- Application Functionality (Browser, File Manager, Terminal, Text Editor)
- Audio System
- File Operations
- Desktop Customization
- Clipboard Operations
- Web Interface Interaction
- Docker Integration
- System Responsiveness
- Error Handling

User Experience Criteria:
- Applications start within 30 seconds
- Desktop loads within 120 seconds
- Web interface responds within 5 seconds
- System handles errors gracefully
- All core applications function properly

Report saved to: $report_file
EOF
    
    echo "User acceptance report saved to: $report_file"
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

main() {
    log_info "Starting user acceptance tests..."
    
    # Check if bc is available for calculations
    if ! command -v bc >/dev/null 2>&1; then
        log_info "Installing bc for calculations..."
        apt-get update && apt-get install -y bc
    fi
    
    local test_results=()
    local tests=(
        "test_web_interface_accessibility"
        "test_desktop_environment_startup"
        "test_browser_functionality"
        "test_file_manager_functionality"
        "test_terminal_functionality"
        "test_text_editor_functionality"
        "test_audio_functionality"
        "test_file_operations"
        "test_desktop_customization"
        "test_clipboard_functionality"
        "test_web_interface_interaction"
        "test_docker_integration"
        "test_system_responsiveness"
        "test_error_handling"
    )
    
    # Run all tests
    for test_function in "${tests[@]}"; do
        if $test_function; then
            test_results+=("PASS")
        else
            test_results+=("FAIL")
        fi
    done
    
    # Generate user acceptance report
    generate_user_acceptance_report
    
    # Calculate results
    local total_tests=${#tests[@]}
    local passed_tests=$(printf '%s\n' "${test_results[@]}" | grep -c "PASS")
    local failed_tests=$(printf '%s\n' "${test_results[@]}" | grep -c "FAIL")
    
    echo ""
    echo "=================================="
    echo "    USER ACCEPTANCE TEST RESULTS"
    echo "=================================="
    echo "Total Tests: $total_tests"
    echo "Passed:      $passed_tests"
    echo "Failed:      $failed_tests"
    echo "=================================="
    
    # Return appropriate exit code
    if [[ $failed_tests -eq 0 ]]; then
        log_pass "All user acceptance tests passed"
        exit $PASS
    else
        log_fail "Some user acceptance tests failed"
        exit $FAIL
    fi
}

# Run main function
main "$@" 
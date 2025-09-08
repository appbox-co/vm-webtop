#!/bin/bash

# TEST_DESCRIPTION: Security validation tests for webtop system

set -euo pipefail

# Test configuration
TEST_NAME="security_validation"
COMPONENT="security"

# Test results
PASS=0
FAIL=1

# Helper functions
log_info() { echo "[INFO] $1"; }
log_pass() { echo "[PASS] $1"; }
log_fail() { echo "[FAIL] $1"; }
log_warning() { echo "[WARNING] $1"; }

# =============================================================================
# SECURITY VALIDATION TESTS
# =============================================================================

test_file_permissions() {
    log_info "Testing file permissions..."
    
    # Check critical file permissions
    local critical_files=(
        "/etc/passwd:644"
        "/etc/shadow:640"
        "/etc/group:644"
        "/etc/gshadow:640"
        "/etc/sudoers:440"
        "/etc/ssh/sshd_config:644"
    )
    
    for file_perm in "${critical_files[@]}"; do
        local file="${file_perm%:*}"
        local expected_perm="${file_perm#*:}"
        
        if [[ -f "$file" ]]; then
            local actual_perm=$(stat -c "%a" "$file")
            if [[ "$actual_perm" != "$expected_perm" ]]; then
                log_fail "Incorrect permissions on $file: $actual_perm (expected: $expected_perm)"
                return $FAIL
            fi
        fi
    done
    
    # Check webtop-specific file permissions
    local webtop_files=(
        "/etc/selkies:755"
        "/defaults:755"
        "/config:755"
        "/usr/share/selkies:755"
    )
    
    for file_perm in "${webtop_files[@]}"; do
        local file="${file_perm%:*}"
        local expected_perm="${file_perm#*:}"
        
        if [[ -e "$file" ]]; then
            local actual_perm=$(stat -c "%a" "$file")
            if [[ "$actual_perm" != "$expected_perm" ]]; then
                log_fail "Incorrect permissions on $file: $actual_perm (expected: $expected_perm)"
                return $FAIL
            fi
        fi
    done
    
    log_pass "File permissions are correct"
    return $PASS
}

test_user_privileges() {
    log_info "Testing user privileges..."
    
    # Check if abc user has appropriate privileges
    if ! id -u abc >/dev/null 2>&1; then
        log_fail "User 'abc' does not exist"
        return $FAIL
    fi
    
    # Check if abc user is not in sudo group (should not have sudo access)
    if id -nG abc | grep -q "sudo"; then
        log_fail "User 'abc' has sudo privileges (security risk)"
        return $FAIL
    fi
    
    # Check if abc user has appropriate group memberships
    local required_groups=("docker" "audio" "video" "pulse" "pulse-access")
    for group in "${required_groups[@]}"; do
        if ! id -nG abc | grep -q "$group"; then
            log_fail "User 'abc' is not in required group: $group"
            return $FAIL
        fi
    done
    
    # Check if abc user home directory is properly restricted
    local home_owner=$(stat -c "%U" /config)
    if [[ "$home_owner" != "abc" ]]; then
        log_fail "/config directory is not owned by abc user"
        return $FAIL
    fi
    
    log_pass "User privileges are correctly configured"
    return $PASS
}

test_network_security() {
    log_info "Testing network security..."
    
    # Check if only necessary ports are exposed
    local allowed_ports=("443" "8082" "9081")
    local listening_ports=$(netstat -tlnp | grep LISTEN | awk '{print $4}' | cut -d: -f2 | sort -u)
    
    for port in $listening_ports; do
        local port_allowed=false
        for allowed_port in "${allowed_ports[@]}"; do
            if [[ "$port" == "$allowed_port" ]]; then
                port_allowed=true
                break
            fi
        done
        
        if [[ "$port_allowed" == false ]]; then
            log_warning "Unexpected port listening: $port"
        fi
    done
    
    # Check if web interface is not accessible from all interfaces
    if netstat -tlnp | grep ":443" | grep -q "0.0.0.0"; then
        log_warning "Web interface is accessible from all interfaces"
    fi
    
    # Check if SSL/TLS is properly configured
    if [[ -f "/config/ssl/cert.pem" ]] && [[ -f "/config/ssl/cert.key" ]]; then
        local cert_perms=$(stat -c "%a" /config/ssl/cert.key)
        if [[ "$cert_perms" != "600" ]]; then
            log_fail "SSL private key has incorrect permissions: $cert_perms (expected: 600)"
            return $FAIL
        fi
    fi
    
    log_pass "Network security configuration is acceptable"
    return $PASS
}

test_service_security() {
    log_info "Testing service security..."
    
    # Check if services are running as non-root user
    local services=("selkies" "selkies-desktop" "selkies-pulseaudio")
    for service in "${services[@]}"; do
        if systemctl is-active "$service" >/dev/null 2>&1; then
            local service_user=$(systemctl show "$service" -p User --value)
            if [[ "$service_user" == "root" ]] || [[ -z "$service_user" ]]; then
                log_fail "Service $service is running as root user"
                return $FAIL
            fi
        fi
    done
    
    # Check if Docker daemon is properly secured
    if systemctl is-active docker >/dev/null 2>&1; then
        # Check if Docker socket has proper permissions
        if [[ -S "/var/run/docker.sock" ]]; then
            local socket_perms=$(stat -c "%a" /var/run/docker.sock)
            if [[ "$socket_perms" == "666" ]]; then
                log_fail "Docker socket has overly permissive permissions"
                return $FAIL
            fi
        fi
    fi
    
    log_pass "Service security configuration is correct"
    return $PASS
}

test_port_security() {
    log_info "Testing port security..."
    
    # Define allowed ports (updated for HTTPS-only)
    local allowed_ports=("443" "8082" "9081")
    
    # Test for exposed ports
    local exposed_ports=$(netstat -tlnp | grep -E ":(443|8082|9081)\b" | wc -l)
    
    if [[ $exposed_ports -gt 0 ]]; then
        log_pass "Required ports are exposed"
    else
        log_fail "Required ports are not exposed"
        return $FAIL
    fi
    
    # Test for insecure bindings
    if netstat -tlnp | grep ":443" | grep -q "0.0.0.0"; then
        log_warning "Port 443 is bound to all interfaces (0.0.0.0)"
    fi
    
    return $PASS
}

test_web_security() {
    log_info "Testing web security headers..."
    
    # Test security headers
    local response_headers=$(curl -s -I https://localhost:443 2>/dev/null)
    if [[ -z "$response_headers" ]]; then
        log_fail "Cannot connect to web interface"
        return $FAIL
    fi
    
    # Check for basic security headers
    if ! echo "$response_headers" | grep -qi "x-frame-options"; then
        log_warning "Missing X-Frame-Options header"
    fi
    
    if ! echo "$response_headers" | grep -qi "x-content-type-options"; then
        log_warning "Missing X-Content-Type-Options header"
    fi
    
    # Test directory listing
    local dir_listing_test=$(curl -s https://localhost:443/test-nonexistent-dir/ 2>/dev/null)
    if [[ "$dir_listing_test" == *"Index of"* ]]; then
        log_fail "Directory listing is enabled"
        return $FAIL
    fi
    
    # Test status page
    local status_test=$(curl -s https://localhost:443/nginx_status 2>/dev/null)
    if [[ "$status_test" == *"Active connections"* ]]; then
        log_fail "Nginx status page is accessible"
        return $FAIL
    fi
    
    log_pass "Web security configuration is acceptable"
    return $PASS
}

test_container_security() {
    log_info "Testing container security..."
    
    # Check if Docker is configured securely
    if command -v docker >/dev/null 2>&1; then
        # Check if Docker daemon is running with security options
        local docker_info=$(docker info 2>/dev/null)
        
        if echo "$docker_info" | grep -qi "Security Options"; then
            log_info "Docker security options are enabled"
        else
            log_warning "Docker security options may not be enabled"
        fi
        
        # Check if user namespace is enabled
        if ! echo "$docker_info" | grep -qi "userns"; then
            log_warning "Docker user namespace remapping is not enabled"
        fi
    fi
    
    log_pass "Container security configuration is acceptable"
    return $PASS
}

test_log_security() {
    log_info "Testing log security..."
    
    # Check if log files have proper permissions
    local log_dirs=("/var/log" "/tmp/webtop-tests")
    for log_dir in "${log_dirs[@]}"; do
        if [[ -d "$log_dir" ]]; then
            local log_perms=$(stat -c "%a" "$log_dir")
            if [[ "$log_perms" == "777" ]]; then
                log_fail "Log directory $log_dir has overly permissive permissions"
                return $FAIL
            fi
        fi
    done
    
    # Check if sensitive information is not logged
    local log_files=("/var/log/syslog" "/var/log/auth.log" "/var/log/nginx/access.log")
    for log_file in "${log_files[@]}"; do
        if [[ -f "$log_file" ]]; then
            # Check for potential password leaks
            if grep -qi "password" "$log_file"; then
                log_warning "Potential password information in log file: $log_file"
            fi
        fi
    done
    
    log_pass "Log security configuration is acceptable"
    return $PASS
}

test_browser_security() {
    log_info "Testing browser security..."
    
    # Check if browser is configured securely
    if [[ -f "/usr/bin/chromium" ]]; then
        local chromium_content=$(cat /usr/bin/chromium)
        
        # Check if sandbox is properly configured
        if echo "$chromium_content" | grep -q "no-sandbox"; then
            log_info "Browser sandbox is disabled for container environment"
        fi
        
        # Check if browser runs with appropriate security flags
        if ! echo "$chromium_content" | grep -q "password-store=basic"; then
            log_warning "Browser may not be configured with secure password store"
        fi
    fi
    
    log_pass "Browser security configuration is acceptable"
    return $PASS
}

test_system_hardening() {
    log_info "Testing system hardening..."
    
    # Check if unnecessary services are disabled
    local unnecessary_services=("telnet" "ftp" "rsh" "rlogin")
    for service in "${unnecessary_services[@]}"; do
        if systemctl is-enabled "$service" >/dev/null 2>&1; then
            log_fail "Unnecessary service is enabled: $service"
            return $FAIL
        fi
    done
    
    # Check if kernel parameters are properly configured
    local kernel_params=(
        "net.ipv4.ip_forward:0"
        "net.ipv4.conf.all.accept_source_route:0"
        "net.ipv4.conf.all.accept_redirects:0"
    )
    
    for param_value in "${kernel_params[@]}"; do
        local param="${param_value%:*}"
        local expected_value="${param_value#*:}"
        
        if [[ -f "/proc/sys/${param//./\/}" ]]; then
            local actual_value=$(cat "/proc/sys/${param//./\/}")
            if [[ "$actual_value" != "$expected_value" ]]; then
                log_warning "Kernel parameter $param has value $actual_value (recommended: $expected_value)"
            fi
        fi
    done
    
    log_pass "System hardening configuration is acceptable"
    return $PASS
}

test_update_security() {
    log_info "Testing update security..."
    
    # Check if system packages are up to date
    local updates_available=$(apt list --upgradable 2>/dev/null | wc -l)
    if [[ $updates_available -gt 10 ]]; then
        log_warning "Many package updates available ($updates_available)"
    fi
    
    # Check if automatic updates are configured
    if [[ -f "/etc/apt/apt.conf.d/20auto-upgrades" ]]; then
        log_info "Automatic updates are configured"
    else
        log_warning "Automatic updates are not configured"
    fi
    
    log_pass "Update security configuration is acceptable"
    return $PASS
}

generate_security_report() {
    log_info "Generating security report..."
    
    local report_file="/tmp/webtop-tests/security-report.txt"
    
    cat > "$report_file" << EOF
Ubuntu VM Webtop Environment - Security Report
Generated: $(date)

System Information:
- OS: $(lsb_release -d | cut -f2)
- Kernel: $(uname -r)
- Hostname: $(hostname)
- Uptime: $(uptime -p)

Security Checks Performed:
- File permissions validation
- User privilege verification
- Network security assessment
- Service security review
- Web security evaluation
- Container security check
- Log security analysis
- Browser security review
- System hardening assessment
- Update security review

Report saved to: $report_file
EOF
    
    echo "Security report saved to: $report_file"
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

main() {
    log_info "Starting security validation tests..."
    
    local test_results=()
    local tests=(
        "test_file_permissions"
        "test_user_privileges"
        "test_network_security"
        "test_service_security"
        "test_web_security"
        "test_container_security"
        "test_log_security"
        "test_browser_security"
        "test_system_hardening"
        "test_update_security"
    )
    
    # Run all tests
    for test_function in "${tests[@]}"; do
        if $test_function; then
            test_results+=("PASS")
        else
            test_results+=("FAIL")
        fi
    done
    
    # Generate security report
    generate_security_report
    
    # Calculate results
    local total_tests=${#tests[@]}
    local passed_tests=$(printf '%s\n' "${test_results[@]}" | grep -c "PASS")
    local failed_tests=$(printf '%s\n' "${test_results[@]}" | grep -c "FAIL")
    
    echo ""
    echo "=================================="
    echo "    SECURITY VALIDATION RESULTS"
    echo "=================================="
    echo "Total Tests: $total_tests"
    echo "Passed:      $passed_tests"
    echo "Failed:      $failed_tests"
    echo "=================================="
    
    # Return appropriate exit code
    if [[ $failed_tests -eq 0 ]]; then
        log_pass "All security validation tests passed"
        exit $PASS
    else
        log_fail "Some security validation tests failed"
        exit $FAIL
    fi
}

# Run main function
main "$@" 
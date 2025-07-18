#!/bin/bash

# TEST_DESCRIPTION: Performance benchmarking tests for webtop system

set -euo pipefail

# Test configuration
TEST_NAME="performance_benchmarks"
COMPONENT="performance"

# Test results
PASS=0
FAIL=1

# Performance thresholds
MAX_SERVICE_START_TIME=30  # seconds
MAX_WEB_RESPONSE_TIME=5    # seconds
MAX_MEMORY_USAGE=2048      # MB
MAX_CPU_USAGE=80           # percentage
MIN_DISK_SPACE=1024        # MB

# Helper functions
log_info() { echo "[INFO] $1"; }
log_pass() { echo "[PASS] $1"; }
log_fail() { echo "[FAIL] $1"; }
log_metric() { echo "[METRIC] $1"; }

# =============================================================================
# PERFORMANCE BENCHMARKING TESTS
# =============================================================================

test_service_startup_performance() {
    log_info "Testing service startup performance..."
    
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
    
    # Wait for services to stop
    sleep 5
    
    # Measure startup time
    local start_time=$(date +%s)
    systemctl start selkies-desktop.service
    
    # Wait for all services to be active
    local timeout=60
    while [[ $timeout -gt 0 ]]; do
        local all_active=true
        
        for service in "${services[@]}"; do
            if ! systemctl is-active "$service" >/dev/null 2>&1; then
                all_active=false
                break
            fi
        done
        
        if [[ "$all_active" == true ]]; then
            break
        fi
        
        sleep 1
        ((timeout--))
    done
    
    local end_time=$(date +%s)
    local startup_time=$((end_time - start_time))
    
    log_metric "Service startup time: ${startup_time}s"
    
    if [[ $startup_time -le $MAX_SERVICE_START_TIME ]]; then
        log_pass "Service startup time within acceptable range (${startup_time}s <= ${MAX_SERVICE_START_TIME}s)"
        return $PASS
    else
        log_fail "Service startup time too high (${startup_time}s > ${MAX_SERVICE_START_TIME}s)"
        return $FAIL
    fi
}

test_web_interface_response_time() {
    log_info "Testing web interface response time..."
    
    # Test multiple requests and calculate average
    local total_time=0
    local requests=10
    
    for i in $(seq 1 $requests); do
        local start_time=$(date +%s.%3N)
        curl -s -f https://localhost:443 >/dev/null 2>&1
        local end_time=$(date +%s.%3N)
        local request_time=$(echo "$end_time - $start_time" | bc)
        total_time=$(echo "$total_time + $request_time" | bc)
    done
    
    local avg_response_time=$(echo "scale=3; $total_time / $requests" | bc)
    
    log_metric "Average web interface response time: ${avg_response_time}s"
    
    if [[ $(echo "$avg_response_time <= $MAX_WEB_RESPONSE_TIME" | bc) -eq 1 ]]; then
        log_pass "Web interface response time within acceptable range (${avg_response_time}s <= ${MAX_WEB_RESPONSE_TIME}s)"
        return $PASS
    else
        log_fail "Web interface response time too high (${avg_response_time}s > ${MAX_WEB_RESPONSE_TIME}s)"
        return $FAIL
    fi
}

test_memory_usage() {
    log_info "Testing memory usage..."
    
    # Wait for system to stabilize
    sleep 10
    
    # Get memory usage for all selkies processes
    local total_memory=0
    local processes=(
        "Xvfb"
        "pulseaudio"
        "nginx"
        "selkies"
        "xfce4-session"
        "openbox"
        "dockerd"
    )
    
    for process in "${processes[@]}"; do
        local memory=$(ps -C "$process" -o rss= 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
        if [[ -n "$memory" && "$memory" -gt 0 ]]; then
            total_memory=$((total_memory + memory))
            log_metric "$process memory usage: $((memory / 1024))MB"
        fi
    done
    
    local total_memory_mb=$((total_memory / 1024))
    log_metric "Total system memory usage: ${total_memory_mb}MB"
    
    if [[ $total_memory_mb -le $MAX_MEMORY_USAGE ]]; then
        log_pass "Memory usage within acceptable range (${total_memory_mb}MB <= ${MAX_MEMORY_USAGE}MB)"
        return $PASS
    else
        log_fail "Memory usage too high (${total_memory_mb}MB > ${MAX_MEMORY_USAGE}MB)"
        return $FAIL
    fi
}

test_cpu_usage() {
    log_info "Testing CPU usage..."
    
    # Monitor CPU usage for 30 seconds
    local duration=30
    local samples=6
    local interval=$((duration / samples))
    local total_cpu=0
    
    for i in $(seq 1 $samples); do
        local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
        total_cpu=$(echo "$total_cpu + $cpu_usage" | bc)
        log_metric "CPU usage sample $i: ${cpu_usage}%"
        sleep $interval
    done
    
    local avg_cpu=$(echo "scale=1; $total_cpu / $samples" | bc)
    log_metric "Average CPU usage: ${avg_cpu}%"
    
    if [[ $(echo "$avg_cpu <= $MAX_CPU_USAGE" | bc) -eq 1 ]]; then
        log_pass "CPU usage within acceptable range (${avg_cpu}% <= ${MAX_CPU_USAGE}%)"
        return $PASS
    else
        log_fail "CPU usage too high (${avg_cpu}% > ${MAX_CPU_USAGE}%)"
        return $FAIL
    fi
}

test_disk_space() {
    log_info "Testing disk space usage..."
    
    # Check available disk space
    local available_space=$(df /config --output=avail | tail -1)
    local available_mb=$((available_space / 1024))
    
    log_metric "Available disk space: ${available_mb}MB"
    
    if [[ $available_mb -ge $MIN_DISK_SPACE ]]; then
        log_pass "Disk space within acceptable range (${available_mb}MB >= ${MIN_DISK_SPACE}MB)"
        return $PASS
    else
        log_fail "Insufficient disk space (${available_mb}MB < ${MIN_DISK_SPACE}MB)"
        return $FAIL
    fi
}

test_websocket_throughput() {
    log_info "Testing WebSocket throughput..."
    
    # Test WebSocket connection performance
    local start_time=$(date +%s.%3N)
    
    # Send multiple requests to WebSocket endpoint
    for i in $(seq 1 20); do
        curl -s -f http://localhost:8082 >/dev/null 2>&1
    done
    
    local end_time=$(date +%s.%3N)
    local total_time=$(echo "$end_time - $start_time" | bc)
    local avg_time=$(echo "scale=3; $total_time / 20" | bc)
    
    log_metric "WebSocket average response time: ${avg_time}s"
    
    if [[ $(echo "$avg_time <= 1.0" | bc) -eq 1 ]]; then
        log_pass "WebSocket throughput within acceptable range (${avg_time}s <= 1.0s)"
        return $PASS
    else
        log_fail "WebSocket throughput too low (${avg_time}s > 1.0s)"
        return $FAIL
    fi
}

test_display_performance() {
    log_info "Testing display performance..."
    
    # Test X11 display performance
    local start_time=$(date +%s.%3N)
    
    # Run multiple X11 operations
    for i in $(seq 1 10); do
        DISPLAY=:1 xset q >/dev/null 2>&1
        DISPLAY=:1 xrandr >/dev/null 2>&1
    done
    
    local end_time=$(date +%s.%3N)
    local total_time=$(echo "$end_time - $start_time" | bc)
    local avg_time=$(echo "scale=3; $total_time / 10" | bc)
    
    log_metric "Display operation average time: ${avg_time}s"
    
    if [[ $(echo "$avg_time <= 0.5" | bc) -eq 1 ]]; then
        log_pass "Display performance within acceptable range (${avg_time}s <= 0.5s)"
        return $PASS
    else
        log_fail "Display performance too slow (${avg_time}s > 0.5s)"
        return $FAIL
    fi
}

test_audio_latency() {
    log_info "Testing audio latency..."
    
    # Test PulseAudio latency
    local start_time=$(date +%s.%3N)
    
    # Run multiple audio operations
    for i in $(seq 1 5); do
        sudo -u abc PULSE_RUNTIME_PATH=/defaults pactl info >/dev/null 2>&1
    done
    
    local end_time=$(date +%s.%3N)
    local total_time=$(echo "$end_time - $start_time" | bc)
    local avg_time=$(echo "scale=3; $total_time / 5" | bc)
    
    log_metric "Audio operation average time: ${avg_time}s"
    
    if [[ $(echo "$avg_time <= 1.0" | bc) -eq 1 ]]; then
        log_pass "Audio latency within acceptable range (${avg_time}s <= 1.0s)"
        return $PASS
    else
        log_fail "Audio latency too high (${avg_time}s > 1.0s)"
        return $FAIL
    fi
}

test_docker_performance() {
    log_info "Testing Docker performance..."
    
    # Test Docker operation performance
    local start_time=$(date +%s.%3N)
    
    # Run Docker operations
    sudo -u abc docker info >/dev/null 2>&1
    sudo -u abc docker ps >/dev/null 2>&1
    sudo -u abc docker images >/dev/null 2>&1
    
    local end_time=$(date +%s.%3N)
    local total_time=$(echo "$end_time - $start_time" | bc)
    
    log_metric "Docker operations time: ${total_time}s"
    
    if [[ $(echo "$total_time <= 3.0" | bc) -eq 1 ]]; then
        log_pass "Docker performance within acceptable range (${total_time}s <= 3.0s)"
        return $PASS
    else
        log_fail "Docker performance too slow (${total_time}s > 3.0s)"
        return $FAIL
    fi
}

generate_performance_report() {
    log_info "Generating performance report..."
    
    local report_file="/tmp/webtop-tests/performance-report.txt"
    
    cat > "$report_file" << EOF
Ubuntu VM Webtop Environment - Performance Report
Generated: $(date)

System Information:
- OS: $(lsb_release -d | cut -f2)
- Kernel: $(uname -r)
- CPU: $(lscpu | grep "Model name" | cut -d: -f2 | xargs)
- Memory: $(free -h | grep "^Mem:" | awk '{print $2}')
- Disk: $(df -h /config | tail -1 | awk '{print $2}')

Performance Thresholds:
- Max Service Start Time: ${MAX_SERVICE_START_TIME}s
- Max Web Response Time: ${MAX_WEB_RESPONSE_TIME}s
- Max Memory Usage: ${MAX_MEMORY_USAGE}MB
- Max CPU Usage: ${MAX_CPU_USAGE}%
- Min Disk Space: ${MIN_DISK_SPACE}MB

Test Results:
EOF
    
    echo "Performance report saved to: $report_file"
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

main() {
    log_info "Starting performance benchmarking tests..."
    
    # Check if bc is available for calculations
    if ! command -v bc >/dev/null 2>&1; then
        log_info "Installing bc for calculations..."
        apt-get update && apt-get install -y bc
    fi
    
    local test_results=()
    local tests=(
        "test_service_startup_performance"
        "test_web_interface_response_time"
        "test_memory_usage"
        "test_cpu_usage"
        "test_disk_space"
        "test_websocket_throughput"
        "test_display_performance"
        "test_audio_latency"
        "test_docker_performance"
    )
    
    # Run all tests
    for test_function in "${tests[@]}"; do
        if $test_function; then
            test_results+=("PASS")
        else
            test_results+=("FAIL")
        fi
    done
    
    # Generate performance report
    generate_performance_report
    
    # Calculate results
    local total_tests=${#tests[@]}
    local passed_tests=$(printf '%s\n' "${test_results[@]}" | grep -c "PASS")
    local failed_tests=$(printf '%s\n' "${test_results[@]}" | grep -c "FAIL")
    
    echo ""
    echo "=================================="
    echo "  PERFORMANCE BENCHMARK RESULTS"
    echo "=================================="
    echo "Total Tests: $total_tests"
    echo "Passed:      $passed_tests"
    echo "Failed:      $failed_tests"
    echo "=================================="
    
    # Return appropriate exit code
    if [[ $failed_tests -eq 0 ]]; then
        log_pass "All performance benchmarks passed"
        exit $PASS
    else
        log_fail "Some performance benchmarks failed"
        exit $FAIL
    fi
}

# Run main function
main "$@" 
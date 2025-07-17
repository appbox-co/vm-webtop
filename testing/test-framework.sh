#!/bin/bash

# =============================================================================
# Ubuntu VM Webtop Environment - Testing Framework
# Phase 5: Integration and Testing
# =============================================================================

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Test configuration
TEST_LOG_DIR="/tmp/webtop-tests"
TEST_RESULTS_FILE="$TEST_LOG_DIR/test-results.json"
TEST_REPORT_FILE="$TEST_LOG_DIR/test-report.html"

# Test categories
declare -A TEST_CATEGORIES=(
    ["component"]="Component Tests"
    ["integration"]="Integration Tests"
    ["performance"]="Performance Tests"
    ["security"]="Security Tests"
    ["user-acceptance"]="User Acceptance Tests"
)

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$TEST_LOG_DIR/test.log"; }
log_success() { echo -e "${GREEN}[PASS]${NC} $1" | tee -a "$TEST_LOG_DIR/test.log"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$TEST_LOG_DIR/test.log"; }
log_error() { echo -e "${RED}[FAIL]${NC} $1" | tee -a "$TEST_LOG_DIR/test.log"; }
log_test() { echo -e "${CYAN}[TEST]${NC} $1" | tee -a "$TEST_LOG_DIR/test.log"; }

# =============================================================================
# TEST FRAMEWORK INITIALIZATION
# =============================================================================

init_test_framework() {
    log_info "Initializing test framework..."
    
    # Create test directories
    mkdir -p "$TEST_LOG_DIR"
    rm -f "$TEST_LOG_DIR"/*
    
    # Initialize test results
    cat > "$TEST_RESULTS_FILE" << 'EOF'
{
    "test_run": {
        "timestamp": "",
        "duration": 0,
        "total_tests": 0,
        "passed": 0,
        "failed": 0,
        "skipped": 0,
        "warnings": 0
    },
    "categories": {},
    "tests": []
}
EOF
    
    # Set test start time
    echo "$(date -Iseconds)" > "$TEST_LOG_DIR/start_time"
    
    log_success "Test framework initialized"
}

# =============================================================================
# TEST EXECUTION ENGINE
# =============================================================================

run_test() {
    local test_name="$1"
    local test_script="$2"
    local category="$3"
    local description="$4"
    
    log_test "Running: $test_name"
    
    local start_time=$(date +%s)
    local result="PASS"
    local output=""
    local error=""
    
    # Run the test script
    if [[ -f "$test_script" ]]; then
        set +e
        output=$(timeout 300 bash "$test_script" 2>&1)
        local exit_code=$?
        set -e
        
        if [[ $exit_code -eq 0 ]]; then
            log_success "$test_name: PASSED"
            result="PASS"
        elif [[ $exit_code -eq 124 ]]; then
            log_error "$test_name: TIMEOUT"
            result="TIMEOUT"
            error="Test timed out after 300 seconds"
        else
            log_error "$test_name: FAILED (exit code: $exit_code)"
            result="FAIL"
            error="Test failed with exit code $exit_code"
        fi
    else
        log_error "$test_name: SCRIPT NOT FOUND"
        result="FAIL"
        error="Test script not found: $test_script"
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Record test result
    record_test_result "$test_name" "$category" "$description" "$result" "$duration" "$output" "$error"
}

record_test_result() {
    local test_name="$1"
    local category="$2"
    local description="$3"
    local result="$4"
    local duration="$5"
    local output="$6"
    local error="$7"
    
    # Add to test results JSON (simplified version)
    local test_entry="{\"name\":\"$test_name\",\"category\":\"$category\",\"description\":\"$description\",\"result\":\"$result\",\"duration\":$duration,\"output\":\"$(echo "$output" | sed 's/"/\\"/g' | tr '\n' ' ')\",\"error\":\"$(echo "$error" | sed 's/"/\\"/g' | tr '\n' ' ')\"}"
    
    echo "$test_entry" >> "$TEST_LOG_DIR/test_results.tmp"
}

# =============================================================================
# TEST DISCOVERY
# =============================================================================

discover_tests() {
    local category="$1"
    local test_dir="$SCRIPT_DIR/$category"
    
    if [[ ! -d "$test_dir" ]]; then
        log_warning "Test directory not found: $test_dir"
        return
    fi
    
    log_info "Discovering tests in category: $category"
    
    # Find all test scripts
    find "$test_dir" -name "test_*.sh" -type f | sort | while read -r test_script; do
        local test_name=$(basename "$test_script" .sh)
        local description=""
        
        # Extract description from test script
        if [[ -f "$test_script" ]]; then
            description=$(grep -m1 "^# TEST_DESCRIPTION:" "$test_script" | sed 's/^# TEST_DESCRIPTION: *//' || echo "No description")
        fi
        
        echo "$test_name|$test_script|$category|$description"
    done
}

# =============================================================================
# TEST RUNNER
# =============================================================================

run_test_category() {
    local category="$1"
    
    log_info "Running ${TEST_CATEGORIES[$category]}"
    
    local test_count=0
    local passed=0
    local failed=0
    
    discover_tests "$category" | while IFS='|' read -r test_name test_script category description; do
        run_test "$test_name" "$test_script" "$category" "$description"
        ((test_count++))
    done
    
    log_info "Completed ${TEST_CATEGORIES[$category]} ($test_count tests)"
}

run_all_tests() {
    log_info "Starting comprehensive test suite"
    
    # Run tests in order
    for category in "component" "integration" "performance" "security" "user-acceptance"; do
        if [[ -n "${TEST_CATEGORIES[$category]:-}" ]]; then
            run_test_category "$category"
        fi
    done
    
    # Generate final report
    generate_test_report
}

# =============================================================================
# REPORTING
# =============================================================================

generate_test_report() {
    log_info "Generating test report..."
    
    local start_time=$(cat "$TEST_LOG_DIR/start_time")
    local end_time=$(date -Iseconds)
    local duration=$(($(date +%s) - $(date -d "$start_time" +%s)))
    
    # Count results
    local total_tests=0
    local passed=0
    local failed=0
    local timeouts=0
    
    if [[ -f "$TEST_LOG_DIR/test_results.tmp" ]]; then
        total_tests=$(wc -l < "$TEST_LOG_DIR/test_results.tmp")
        passed=$(grep -c '"result":"PASS"' "$TEST_LOG_DIR/test_results.tmp" || echo 0)
        failed=$(grep -c '"result":"FAIL"' "$TEST_LOG_DIR/test_results.tmp" || echo 0)
        timeouts=$(grep -c '"result":"TIMEOUT"' "$TEST_LOG_DIR/test_results.tmp" || echo 0)
    fi
    
    # Generate HTML report
    cat > "$TEST_REPORT_FILE" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Ubuntu VM Webtop Environment - Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background: #f0f0f0; padding: 20px; border-radius: 5px; }
        .summary { display: flex; gap: 20px; margin: 20px 0; }
        .metric { background: #e7f3ff; padding: 15px; border-radius: 5px; text-align: center; }
        .pass { color: #28a745; }
        .fail { color: #dc3545; }
        .timeout { color: #ffc107; }
        .test-results { margin: 20px 0; }
        .test-item { margin: 10px 0; padding: 10px; border: 1px solid #ddd; border-radius: 5px; }
        .test-pass { border-left: 4px solid #28a745; }
        .test-fail { border-left: 4px solid #dc3545; }
        .test-timeout { border-left: 4px solid #ffc107; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Ubuntu VM Webtop Environment - Test Report</h1>
        <p><strong>Test Run:</strong> $start_time</p>
        <p><strong>Duration:</strong> ${duration}s</p>
        <p><strong>Generated:</strong> $(date)</p>
    </div>
    
    <div class="summary">
        <div class="metric">
            <h3>Total Tests</h3>
            <div style="font-size: 24px; font-weight: bold;">$total_tests</div>
        </div>
        <div class="metric">
            <h3 class="pass">Passed</h3>
            <div style="font-size: 24px; font-weight: bold; color: #28a745;">$passed</div>
        </div>
        <div class="metric">
            <h3 class="fail">Failed</h3>
            <div style="font-size: 24px; font-weight: bold; color: #dc3545;">$failed</div>
        </div>
        <div class="metric">
            <h3 class="timeout">Timeouts</h3>
            <div style="font-size: 24px; font-weight: bold; color: #ffc107;">$timeouts</div>
        </div>
    </div>
    
    <div class="test-results">
        <h2>Test Results</h2>
EOF
    
    # Add test results if available
    if [[ -f "$TEST_LOG_DIR/test_results.tmp" ]]; then
        while read -r test_result; do
            local name=$(echo "$test_result" | grep -o '"name":"[^"]*"' | cut -d'"' -f4)
            local category=$(echo "$test_result" | grep -o '"category":"[^"]*"' | cut -d'"' -f4)
            local result=$(echo "$test_result" | grep -o '"result":"[^"]*"' | cut -d'"' -f4)
            local duration=$(echo "$test_result" | grep -o '"duration":[0-9]*' | cut -d':' -f2)
            local description=$(echo "$test_result" | grep -o '"description":"[^"]*"' | cut -d'"' -f4)
            
            local class="test-pass"
            if [[ "$result" == "FAIL" ]]; then
                class="test-fail"
            elif [[ "$result" == "TIMEOUT" ]]; then
                class="test-timeout"
            fi
            
            cat >> "$TEST_REPORT_FILE" << EOF
        <div class="test-item $class">
            <h4>$name</h4>
            <p><strong>Category:</strong> $category</p>
            <p><strong>Description:</strong> $description</p>
            <p><strong>Result:</strong> <span class="$(echo $result | tr '[:upper:]' '[:lower:]')">$result</span></p>
            <p><strong>Duration:</strong> ${duration}s</p>
        </div>
EOF
        done < "$TEST_LOG_DIR/test_results.tmp"
    fi
    
    cat >> "$TEST_REPORT_FILE" << EOF
    </div>
    
    <div style="margin-top: 40px; padding: 20px; background: #f8f9fa; border-radius: 5px;">
        <h3>Test Logs</h3>
        <pre style="background: #ffffff; padding: 10px; border-radius: 5px; overflow-x: auto;">
$(cat "$TEST_LOG_DIR/test.log" | tail -50)
        </pre>
    </div>
</body>
</html>
EOF
    
    log_success "Test report generated: $TEST_REPORT_FILE"
    
    # Print summary
    echo ""
    echo "=================================="
    echo "    TEST EXECUTION SUMMARY"
    echo "=================================="
    echo "Total Tests: $total_tests"
    echo "Passed:      $passed"
    echo "Failed:      $failed"
    echo "Timeouts:    $timeouts"
    echo "Duration:    ${duration}s"
    echo "Report:      $TEST_REPORT_FILE"
    echo "=================================="
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

show_help() {
    cat << EOF
Ubuntu VM Webtop Environment - Testing Framework

Usage: $0 [OPTIONS] [CATEGORY]

Options:
    -h, --help          Show this help message
    -v, --verbose       Enable verbose output
    -c, --category      Run specific test category only
    -l, --list          List available test categories and tests
    -r, --report        Generate report from previous test run

Categories:
    component           Component validation tests
    integration         End-to-end integration tests
    performance         Performance benchmarking tests
    security            Security validation tests
    user-acceptance     User acceptance tests
    all                 Run all test categories (default)

Examples:
    $0                              # Run all tests
    $0 -c component                 # Run only component tests
    $0 -c integration               # Run only integration tests
    $0 -l                           # List available tests
    $0 -r                           # Generate report from previous run

EOF
}

main() {
    local category="all"
    local verbose=false
    local list_tests=false
    local report_only=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            -c|--category)
                category="$2"
                shift 2
                ;;
            -l|--list)
                list_tests=true
                shift
                ;;
            -r|--report)
                report_only=true
                shift
                ;;
            *)
                category="$1"
                shift
                ;;
        esac
    done
    
    # Initialize test framework
    init_test_framework
    
    # Handle special modes
    if [[ "$list_tests" == true ]]; then
        log_info "Available test categories and tests:"
        for cat in "${!TEST_CATEGORIES[@]}"; do
            echo ""
            echo "${TEST_CATEGORIES[$cat]}:"
            discover_tests "$cat" | while IFS='|' read -r test_name test_script category description; do
                echo "  - $test_name: $description"
            done
        done
        exit 0
    fi
    
    if [[ "$report_only" == true ]]; then
        generate_test_report
        exit 0
    fi
    
    # Run tests
    if [[ "$category" == "all" ]]; then
        run_all_tests
    elif [[ -n "${TEST_CATEGORIES[$category]:-}" ]]; then
        run_test_category "$category"
        generate_test_report
    else
        log_error "Invalid test category: $category"
        log_info "Available categories: ${!TEST_CATEGORIES[*]}"
        exit 1
    fi
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[ERROR]${NC} This testing framework must be run as root"
    echo "Please run with: sudo $0 $*"
    exit 1
fi

# Check if running in Ubuntu Noble
if ! grep -q "Ubuntu 24.04" /etc/os-release 2>/dev/null; then
    echo -e "${YELLOW}[WARNING]${NC} This testing framework is designed for Ubuntu 24.04 (Noble)"
    echo "Current system may not be supported"
fi

# Run main function
main "$@" 
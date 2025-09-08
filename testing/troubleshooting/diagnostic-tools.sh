#!/bin/bash

# =============================================================================
# Ubuntu VM Webtop Environment - Diagnostic Tools
# Comprehensive troubleshooting and diagnostic utilities
# =============================================================================

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_debug() { echo -e "${CYAN}[DEBUG]${NC} $1"; }

# Diagnostic output directory
DIAG_DIR="/tmp/webtop-diagnostics"

# =============================================================================
# SYSTEM INFORMATION COLLECTION
# =============================================================================

collect_system_info() {
    log_info "Collecting system information..."
    
    local output_file="$DIAG_DIR/system-info.txt"
    
    {
        echo "==================== SYSTEM INFORMATION ===================="
        echo "Date: $(date)"
        echo "Hostname: $(hostname)"
        echo "Uptime: $(uptime)"
        echo ""
        
        echo "==================== OS INFORMATION ===================="
        lsb_release -a
        echo ""
        
        echo "==================== KERNEL INFORMATION ===================="
        uname -a
        echo ""
        
        echo "==================== HARDWARE INFORMATION ===================="
        echo "CPU:"
        lscpu
        echo ""
        
        echo "Memory:"
        free -h
        echo ""
        
        echo "Disk Usage:"
        df -h
        echo ""
        
        echo "==================== NETWORK INFORMATION ===================="
        ip addr show
        echo ""
        
        echo "Listening Ports:"
        netstat -tlnp
        echo ""
        
    } > "$output_file"
    
    log_success "System information saved to: $output_file"
}

# =============================================================================
# SERVICE DIAGNOSTICS
# =============================================================================

diagnose_services() {
    log_info "Diagnosing systemd services..."
    
    local output_file="$DIAG_DIR/services-status.txt"
    local services=(
        "xvfb.service"
        "selkies-pulseaudio.service"
        "selkies-docker.service"
        "selkies-nginx.service"
        "selkies.service"
        "selkies-desktop.service"
        "docker.service"
    )
    
    {
        echo "==================== SERVICE STATUS ===================="
        echo "Date: $(date)"
        echo ""
        
        for service in "${services[@]}"; do
            echo "==================== $service ===================="
            echo "Status:"
            systemctl status "$service" --no-pager -l || echo "Service not found"
            echo ""
            
            echo "Is Active:"
            systemctl is-active "$service" || echo "Not active"
            echo ""
            
            echo "Is Enabled:"
            systemctl is-enabled "$service" || echo "Not enabled"
            echo ""
            
            echo "Recent Logs:"
            journalctl -u "$service" --no-pager -n 20 || echo "No logs available"
            echo ""
            echo "================================================="
            echo ""
        done
        
    } > "$output_file"
    
    log_success "Service diagnostics saved to: $output_file"
}

# =============================================================================
# PROCESS DIAGNOSTICS
# =============================================================================

diagnose_processes() {
    log_info "Diagnosing running processes..."
    
    local output_file="$DIAG_DIR/processes-status.txt"
    
    {
        echo "==================== PROCESS STATUS ===================="
        echo "Date: $(date)"
        echo ""
        
        echo "==================== ALL PROCESSES ===================="
        ps aux --sort=-%mem | head -20
        echo ""
        
        echo "==================== WEBTOP PROCESSES ===================="
        echo "Xvfb processes:"
        pgrep -af "Xvfb" || echo "No Xvfb processes found"
        echo ""
        
        echo "PulseAudio processes:"
        pgrep -af "pulseaudio" || echo "No PulseAudio processes found"
        echo ""
        
        echo "Nginx processes:"
        pgrep -af "nginx" || echo "No nginx processes found"
        echo ""
        
        echo "Selkies processes:"
        pgrep -af "selkies" || echo "No selkies processes found"
        echo ""
        
        echo "Desktop processes:"
        pgrep -af "xfce4-session\|openbox" || echo "No desktop processes found"
        echo ""
        
        echo "Docker processes:"
        pgrep -af "docker" || echo "No docker processes found"
        echo ""
        
        echo "==================== PROCESS TREE ===================="
        pstree -p || echo "pstree not available"
        echo ""
        
    } > "$output_file"
    
    log_success "Process diagnostics saved to: $output_file"
}

# =============================================================================
# NETWORK DIAGNOSTICS
# =============================================================================

diagnose_network() {
    log_info "Diagnosing network connectivity..."
    
    local output_file="$DIAG_DIR/network-status.txt"
    
    {
        echo "==================== NETWORK DIAGNOSTICS ===================="
        echo "Date: $(date)"
        echo ""
        
        echo "==================== LISTENING PORTS ===================="
        netstat -tlnp
        echo ""
        
        echo "==================== WEB INTERFACE TESTS ===================="
        echo "Testing localhost:443..."
        curl -s -I https://localhost:443 || echo "Web interface not accessible"
        echo ""
        
        echo "Testing localhost:443..."
        curl -s -I https://localhost:443 || echo "HTTPS interface not accessible"
        echo ""
        
        echo "Testing localhost:8082..."
        curl -s -I http://localhost:8082 || echo "WebSocket interface not accessible"
        echo ""
        
        echo "==================== NGINX STATUS ===================="
        if systemctl is-active nginx >/dev/null 2>&1; then
            echo "Nginx is running"
            echo "Nginx configuration test:"
            nginx -t || echo "Nginx configuration test failed"
        else
            echo "Nginx is not running"
        fi
        echo ""
        
    } > "$output_file"
    
    log_success "Network diagnostics saved to: $output_file"
}

# =============================================================================
# AUDIO DIAGNOSTICS
# =============================================================================

diagnose_audio() {
    log_info "Diagnosing audio system..."
    
    local output_file="$DIAG_DIR/audio-status.txt"
    
    {
        echo "==================== AUDIO DIAGNOSTICS ===================="
        echo "Date: $(date)"
        echo ""
        
        echo "==================== PULSEAUDIO STATUS ===================="
        if pgrep -f "pulseaudio" >/dev/null; then
            echo "PulseAudio is running"
            echo ""
            
            echo "PulseAudio info:"
            sudo -u appbox PULSE_RUNTIME_PATH=/defaults pactl info || echo "Cannot get PulseAudio info"
            echo ""
            
            echo "Audio sinks:"
            sudo -u appbox PULSE_RUNTIME_PATH=/defaults pactl list sinks || echo "Cannot list audio sinks"
            echo ""
            
            echo "Audio sources:"
            sudo -u appbox PULSE_RUNTIME_PATH=/defaults pactl list sources || echo "Cannot list audio sources"
            echo ""
            
            echo "Audio modules:"
            sudo -u appbox PULSE_RUNTIME_PATH=/defaults pactl list modules || echo "Cannot list audio modules"
            echo ""
        else
            echo "PulseAudio is not running"
        fi
        
    } > "$output_file"
    
    log_success "Audio diagnostics saved to: $output_file"
}

# =============================================================================
# DISPLAY DIAGNOSTICS
# =============================================================================

diagnose_display() {
    log_info "Diagnosing display system..."
    
    local output_file="$DIAG_DIR/display-status.txt"
    
    {
        echo "==================== DISPLAY DIAGNOSTICS ===================="
        echo "Date: $(date)"
        echo ""
        
        echo "==================== XVFB STATUS ===================="
        if pgrep -f "Xvfb" >/dev/null; then
            echo "Xvfb is running"
            echo ""
            
            echo "Display :1 test:"
            DISPLAY=:1 xset q || echo "Cannot access display :1"
            echo ""
            
            echo "Display resolution:"
            DISPLAY=:1 xrandr || echo "Cannot get display resolution"
            echo ""
            
            echo "X11 processes:"
            DISPLAY=:1 xlsclients || echo "Cannot list X11 clients"
            echo ""
        else
            echo "Xvfb is not running"
        fi
        
        echo "==================== DESKTOP ENVIRONMENT ===================="
        if [[ -f "/etc/selkies/webtop-installed" ]]; then
            echo "Webtop is installed (XFCE desktop)"
            if pgrep -f "xfce4-session" >/dev/null; then
                echo "XFCE desktop is running"
            else
                echo "XFCE desktop is not running"
            fi
        else
            echo "Webtop is not installed (OpenBox desktop)"
            if pgrep -f "openbox" >/dev/null; then
                echo "OpenBox desktop is running"
            else
                echo "OpenBox desktop is not running"
            fi
        fi
        echo ""
        
    } > "$output_file"
    
    log_success "Display diagnostics saved to: $output_file"
}

# =============================================================================
# DOCKER DIAGNOSTICS
# =============================================================================

diagnose_docker() {
    log_info "Diagnosing Docker system..."
    
    local output_file="$DIAG_DIR/docker-status.txt"
    
    {
        echo "==================== DOCKER DIAGNOSTICS ===================="
        echo "Date: $(date)"
        echo ""
        
        echo "==================== DOCKER STATUS ===================="
        if systemctl is-active docker >/dev/null 2>&1; then
            echo "Docker service is running"
            echo ""
            
            echo "Docker info:"
            docker info || echo "Cannot get Docker info"
            echo ""
            
            echo "Docker version:"
            docker version || echo "Cannot get Docker version"
            echo ""
            
            echo "Docker containers:"
            docker ps -a || echo "Cannot list Docker containers"
            echo ""
            
            echo "Docker images:"
            docker images || echo "Cannot list Docker images"
            echo ""
            
            echo "Docker networks:"
            docker network ls || echo "Cannot list Docker networks"
            echo ""
            
            echo "Docker volumes:"
            docker volume ls || echo "Cannot list Docker volumes"
            echo ""
            
            echo "User access test:"
            sudo -u appbox docker info >/dev/null 2>&1 && echo "User 'appbox' can access Docker" || echo "User 'appbox' cannot access Docker"
            echo ""
        else
            echo "Docker service is not running"
        fi
        
    } > "$output_file"
    
    log_success "Docker diagnostics saved to: $output_file"
}

# =============================================================================
# FILE SYSTEM DIAGNOSTICS
# =============================================================================

diagnose_filesystem() {
    log_info "Diagnosing file system..."
    
    local output_file="$DIAG_DIR/filesystem-status.txt"
    
    {
        echo "==================== FILESYSTEM DIAGNOSTICS ===================="
        echo "Date: $(date)"
        echo ""
        
        echo "==================== DISK USAGE ===================="
        df -h
        echo ""
        
        echo "==================== INODE USAGE ===================="
        df -i
        echo ""
        
        echo "==================== CRITICAL DIRECTORIES ===================="
        local dirs=(
            "/config"
            "/defaults"
            "/usr/share/selkies"
            "/etc/selkies"
            "/usr/local/bin"
            "/opt/lib"
        )
        
        for dir in "${dirs[@]}"; do
            echo "Directory: $dir"
            if [[ -d "$dir" ]]; then
                ls -la "$dir" || echo "Cannot list directory contents"
                echo "Permissions: $(stat -c "%a %U:%G" "$dir")"
            else
                echo "Directory does not exist"
            fi
            echo ""
        done
        
        echo "==================== CRITICAL FILES ===================="
        local files=(
            "/usr/local/bin/Xvfb"
            "/usr/lib/selkies_joystick_interposer.so"
            "/opt/lib/libudev.so.1.0.0-fake"
            "/usr/share/selkies/www/index.html"
            "/etc/selkies/webtop-installed"
        )
        
        for file in "${files[@]}"; do
            echo "File: $file"
            if [[ -f "$file" ]]; then
                echo "Exists: Yes"
                echo "Permissions: $(stat -c "%a %U:%G" "$file")"
                echo "Size: $(stat -c "%s" "$file") bytes"
            else
                echo "Exists: No"
            fi
            echo ""
        done
        
    } > "$output_file"
    
    log_success "File system diagnostics saved to: $output_file"
}

# =============================================================================
# LOG COLLECTION
# =============================================================================

collect_logs() {
    log_info "Collecting system logs..."
    
    local logs_dir="$DIAG_DIR/logs"
    mkdir -p "$logs_dir"
    
    # System logs
    journalctl --no-pager -n 100 > "$logs_dir/system.log" 2>/dev/null || echo "Cannot collect system logs"
    
    # Service logs
    local services=(
        "xvfb"
        "selkies-pulseaudio"
        "selkies-docker"
        "selkies-nginx"
        "selkies"
        "selkies-desktop"
        "docker"
    )
    
    for service in "${services[@]}"; do
        journalctl -u "$service" --no-pager -n 50 > "$logs_dir/${service}.log" 2>/dev/null || echo "Cannot collect logs for $service"
    done
    
    # Application logs
    if [[ -f "/var/log/nginx/access.log" ]]; then
        tail -50 /var/log/nginx/access.log > "$logs_dir/nginx-access.log" 2>/dev/null || true
    fi
    
    if [[ -f "/var/log/nginx/error.log" ]]; then
        tail -50 /var/log/nginx/error.log > "$logs_dir/nginx-error.log" 2>/dev/null || true
    fi
    
    # X11 logs
    if [[ -f "/var/log/Xorg.0.log" ]]; then
        tail -50 /var/log/Xorg.0.log > "$logs_dir/xorg.log" 2>/dev/null || true
    fi
    
    log_success "Logs collected in: $logs_dir"
}

# =============================================================================
# CONFIGURATION VALIDATION
# =============================================================================

validate_configuration() {
    log_info "Validating configuration..."
    
    local output_file="$DIAG_DIR/configuration-validation.txt"
    
    {
        echo "==================== CONFIGURATION VALIDATION ===================="
        echo "Date: $(date)"
        echo ""
        
        echo "==================== ENVIRONMENT VARIABLES ===================="
        cat /etc/environment || echo "Cannot read environment file"
        echo ""
        
        echo "==================== SYSTEMD SERVICES ===================="
        local services=(
            "xvfb.service"
            "selkies-pulseaudio.service"
            "selkies-docker.service"
            "selkies-nginx.service"
            "selkies.service"
            "selkies-desktop.service"
        )
        
        for service in "${services[@]}"; do
            echo "Service: $service"
            if [[ -f "/etc/systemd/system/$service" ]]; then
                echo "Exists: Yes"
                echo "Content:"
                cat "/etc/systemd/system/$service"
            else
                echo "Exists: No"
            fi
            echo ""
        done
        
        echo "==================== NGINX CONFIGURATION ===================="
        if [[ -f "/etc/nginx/sites-available/default" ]]; then
            echo "Nginx configuration:"
            cat /etc/nginx/sites-available/default
        else
            echo "Nginx configuration not found"
        fi
        echo ""
        
        echo "==================== USER CONFIGURATION ===================="
        echo "User 'appbox' info:"
        id appbox || echo "User 'appbox' not found"
        echo ""
        
        echo "User 'appbox' groups:"
        groups appbox || echo "Cannot get user groups"
        echo ""
        
        echo "User 'appbox' home directory:"
        ls -la /config || echo "Cannot list home directory"
        echo ""
        
    } > "$output_file"
    
    log_success "Configuration validation saved to: $output_file"
}

# =============================================================================
# PERFORMANCE ANALYSIS
# =============================================================================

analyze_performance() {
    log_info "Analyzing system performance..."
    
    local output_file="$DIAG_DIR/performance-analysis.txt"
    
    {
        echo "==================== PERFORMANCE ANALYSIS ===================="
        echo "Date: $(date)"
        echo ""
        
        echo "==================== CPU USAGE ===================="
        top -bn1 | head -20
        echo ""
        
        echo "==================== MEMORY USAGE ===================="
        free -h
        echo ""
        
        echo "Memory usage by process:"
        ps aux --sort=-%mem | head -10
        echo ""
        
        echo "==================== DISK I/O ===================="
        iostat -x 1 3 2>/dev/null || echo "iostat not available"
        echo ""
        
        echo "==================== NETWORK PERFORMANCE ===================="
        echo "Network interface statistics:"
        cat /proc/net/dev
        echo ""
        
        echo "==================== LOAD AVERAGE ===================="
        uptime
        echo ""
        
        echo "Load average history:"
        sar -q 1 3 2>/dev/null || echo "sar not available"
        echo ""
        
    } > "$output_file"
    
    log_success "Performance analysis saved to: $output_file"
}

# =============================================================================
# REPORT GENERATION
# =============================================================================

generate_diagnostic_report() {
    log_info "Generating diagnostic report..."
    
    local report_file="$DIAG_DIR/diagnostic-report.html"
    
    cat > "$report_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Ubuntu VM Webtop Environment - Diagnostic Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background: #f0f0f0; padding: 20px; border-radius: 5px; }
        .section { margin: 20px 0; padding: 15px; border: 1px solid #ddd; border-radius: 5px; }
        .error { background: #ffebee; border-left: 4px solid #f44336; }
        .warning { background: #fff3e0; border-left: 4px solid #ff9800; }
        .success { background: #e8f5e8; border-left: 4px solid #4caf50; }
        .info { background: #e3f2fd; border-left: 4px solid #2196f3; }
        pre { background: #f5f5f5; padding: 10px; border-radius: 3px; overflow-x: auto; }
        .file-list { list-style-type: none; padding: 0; }
        .file-list li { margin: 5px 0; }
        .file-list a { color: #1976d2; text-decoration: none; }
        .file-list a:hover { text-decoration: underline; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Ubuntu VM Webtop Environment - Diagnostic Report</h1>
        <p><strong>Generated:</strong> $(date)</p>
        <p><strong>Hostname:</strong> $(hostname)</p>
        <p><strong>System:</strong> $(lsb_release -d | cut -f2)</p>
    </div>
    
    <div class="section info">
        <h2>Diagnostic Summary</h2>
        <p>This report contains comprehensive diagnostic information about the Ubuntu VM Webtop Environment.</p>
        <p>All diagnostic files are stored in: <code>$DIAG_DIR</code></p>
    </div>
    
    <div class="section">
        <h2>Generated Files</h2>
        <ul class="file-list">
EOF
    
    # Add file list
    for file in "$DIAG_DIR"/*.txt "$DIAG_DIR"/logs/*.log; do
        if [[ -f "$file" ]]; then
            local filename=$(basename "$file")
            echo "            <li><a href=\"$filename\">$filename</a></li>" >> "$report_file"
        fi
    done
    
    cat >> "$report_file" << EOF
        </ul>
    </div>
    
    <div class="section">
        <h2>Quick Status Check</h2>
        <p><strong>System Status:</strong> $(systemctl is-system-running 2>/dev/null || echo "Unknown")</p>
        <p><strong>Selkies Services:</strong> $(systemctl is-active selkies-desktop 2>/dev/null || echo "Not running")</p>
        <p><strong>Web Interface:</strong> $(curl -s -o /dev/null -w "%{http_code}" https://localhost:443 2>/dev/null || echo "Not accessible")</p>
        <p><strong>Docker Status:</strong> $(systemctl is-active docker 2>/dev/null || echo "Not running")</p>
    </div>
    
    <div class="section">
        <h2>Troubleshooting Steps</h2>
        <ol>
            <li>Check service status: <code>systemctl status selkies-desktop</code></li>
            <li>Review service logs: <code>journalctl -u selkies-desktop -f</code></li>
            <li>Verify web interface: <code>curl -I https://localhost:443</code></li>
            <li>Check file permissions: <code>ls -la /config /defaults /usr/share/selkies</code></li>
            <li>Validate configuration: <code>nginx -t</code></li>
        </ol>
    </div>
    
    <div class="section">
        <h2>Common Issues</h2>
        <ul>
            <li><strong>Web interface not accessible:</strong> Check nginx service and port 443</li>
            <li><strong>Desktop not starting:</strong> Check xvfb and display server</li>
            <li><strong>Audio not working:</strong> Check pulseaudio service and modules</li>
            <li><strong>Docker not accessible:</strong> Check user permissions and docker group</li>
            <li><strong>Performance issues:</strong> Check system resources and load</li>
        </ul>
    </div>
    
    <div class="section">
        <h2>Support Information</h2>
        <p>For additional support, please provide this diagnostic report along with:</p>
        <ul>
            <li>Description of the issue</li>
            <li>Steps to reproduce</li>
            <li>Any error messages</li>
            <li>System specifications</li>
        </ul>
    </div>
</body>
</html>
EOF
    
    log_success "Diagnostic report generated: $report_file"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

show_help() {
    cat << EOF
Ubuntu VM Webtop Environment - Diagnostic Tools

Usage: $0 [OPTIONS]

Options:
    -h, --help          Show this help message
    -a, --all           Run all diagnostic tests (default)
    -s, --system        Collect system information only
    -v, --services      Diagnose services only
    -p, --processes     Diagnose processes only
    -n, --network       Diagnose network only
    -d, --display       Diagnose display only
    -o, --docker        Diagnose Docker only
    -f, --filesystem    Diagnose file system only
    -l, --logs          Collect logs only
    -c, --config        Validate configuration only
    -r, --performance   Analyze performance only
    --report            Generate HTML report only

Examples:
    $0                  # Run all diagnostics
    $0 -s               # Collect system info only
    $0 -v -l            # Diagnose services and collect logs
    $0 --report         # Generate HTML report from existing data

Output Directory: $DIAG_DIR

EOF
}

main() {
    local run_all=true
    local run_system=false
    local run_services=false
    local run_processes=false
    local run_network=false
    local run_display=false
    local run_docker=false
    local run_filesystem=false
    local run_logs=false
    local run_config=false
    local run_performance=false
    local run_report=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -a|--all)
                run_all=true
                shift
                ;;
            -s|--system)
                run_all=false
                run_system=true
                shift
                ;;
            -v|--services)
                run_all=false
                run_services=true
                shift
                ;;
            -p|--processes)
                run_all=false
                run_processes=true
                shift
                ;;
            -n|--network)
                run_all=false
                run_network=true
                shift
                ;;
            -d|--display)
                run_all=false
                run_display=true
                shift
                ;;
            -o|--docker)
                run_all=false
                run_docker=true
                shift
                ;;
            -f|--filesystem)
                run_all=false
                run_filesystem=true
                shift
                ;;
            -l|--logs)
                run_all=false
                run_logs=true
                shift
                ;;
            -c|--config)
                run_all=false
                run_config=true
                shift
                ;;
            -r|--performance)
                run_all=false
                run_performance=true
                shift
                ;;
            --report)
                run_all=false
                run_report=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Create diagnostic directory
    mkdir -p "$DIAG_DIR"
    
    log_info "Starting diagnostic collection..."
    log_info "Output directory: $DIAG_DIR"
    
    # Run diagnostics based on options
    if [[ "$run_all" == true ]]; then
        collect_system_info
        diagnose_services
        diagnose_processes
        diagnose_network
        diagnose_audio
        diagnose_display
        diagnose_docker
        diagnose_filesystem
        collect_logs
        validate_configuration
        analyze_performance
        generate_diagnostic_report
    else
        if [[ "$run_system" == true ]]; then collect_system_info; fi
        if [[ "$run_services" == true ]]; then diagnose_services; fi
        if [[ "$run_processes" == true ]]; then diagnose_processes; fi
        if [[ "$run_network" == true ]]; then diagnose_network; fi
        if [[ "$run_display" == true ]]; then diagnose_display; fi
        if [[ "$run_docker" == true ]]; then diagnose_docker; fi
        if [[ "$run_filesystem" == true ]]; then diagnose_filesystem; fi
        if [[ "$run_logs" == true ]]; then collect_logs; fi
        if [[ "$run_config" == true ]]; then validate_configuration; fi
        if [[ "$run_performance" == true ]]; then analyze_performance; fi
        if [[ "$run_report" == true ]]; then generate_diagnostic_report; fi
    fi
    
    log_success "Diagnostic collection completed"
    log_info "Results saved in: $DIAG_DIR"
    
    if [[ -f "$DIAG_DIR/diagnostic-report.html" ]]; then
        log_info "HTML report available at: $DIAG_DIR/diagnostic-report.html"
    fi
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    log_error "This diagnostic tool must be run as root"
    echo "Please run with: sudo $0 $*"
    exit 1
fi

# Run main function
main "$@" 
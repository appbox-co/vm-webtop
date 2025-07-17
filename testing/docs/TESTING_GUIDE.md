# Ubuntu VM Webtop Environment - Testing Guide

## Overview

This testing guide provides comprehensive information about testing the Ubuntu VM Webtop Environment, including automated test suites, manual testing procedures, troubleshooting, and validation processes.

## Test Suite Structure

### Directory Layout
```
testing/
├── test-framework.sh          # Main test orchestration framework
├── component/                 # Component validation tests
│   ├── test_selkies_installation.sh
│   └── test_webtop_installation.sh
├── integration/               # End-to-end integration tests
│   └── test_end_to_end.sh
├── performance/               # Performance benchmarking tests
│   └── test_performance_benchmarks.sh
├── security/                  # Security validation tests
│   └── test_security_validation.sh
├── user-acceptance/           # User acceptance tests
│   └── test_user_acceptance.sh
├── troubleshooting/           # Diagnostic and troubleshooting tools
│   └── diagnostic-tools.sh
└── docs/                      # Testing documentation
    └── TESTING_GUIDE.md       # This file
```

## Quick Start

### Running All Tests
```bash
# Run complete test suite
sudo ./testing/test-framework.sh

# Run specific test category
sudo ./testing/test-framework.sh -c component
sudo ./testing/test-framework.sh -c integration
sudo ./testing/test-framework.sh -c performance
sudo ./testing/test-framework.sh -c security
sudo ./testing/test-framework.sh -c user-acceptance
```

### Test Framework Options
```bash
# Show help
./testing/test-framework.sh -h

# List available tests
./testing/test-framework.sh -l

# Run with verbose output
./testing/test-framework.sh -v

# Generate report from previous run
./testing/test-framework.sh -r
```

## Test Categories

### 1. Component Tests
**Purpose**: Validate individual component installation and configuration

**Tests Include**:
- Selkies installation validation
- Webtop installation validation
- Package verification
- Service configuration
- File permissions
- Environment variables

**Run Command**:
```bash
sudo ./testing/test-framework.sh -c component
```

### 2. Integration Tests
**Purpose**: Test complete system functionality end-to-end

**Tests Include**:
- Service startup sequence
- Web interface accessibility
- Display server functionality
- Desktop environment startup
- Audio system integration
- Docker integration
- WebSocket connections
- File system permissions

**Run Command**:
```bash
sudo ./testing/test-framework.sh -c integration
```

### 3. Performance Tests
**Purpose**: Benchmark system performance against acceptable thresholds

**Tests Include**:
- Service startup time
- Web interface response time
- Memory usage analysis
- CPU utilization monitoring
- Disk space validation
- WebSocket throughput
- Display performance
- Audio latency
- Docker performance

**Thresholds**:
- Max Service Start Time: 30 seconds
- Max Web Response Time: 5 seconds
- Max Memory Usage: 2048 MB
- Max CPU Usage: 80%
- Min Disk Space: 1024 MB

**Run Command**:
```bash
sudo ./testing/test-framework.sh -c performance
```

### 4. Security Tests
**Purpose**: Validate security configuration and identify vulnerabilities

**Tests Include**:
- File permission validation
- User privilege verification
- Network security assessment
- Service security review
- Web security headers
- Container security
- Log security analysis
- Browser security settings
- System hardening verification

**Run Command**:
```bash
sudo ./testing/test-framework.sh -c security
```

### 5. User Acceptance Tests
**Purpose**: Verify system meets user requirements and expectations

**Tests Include**:
- Web interface usability
- Desktop environment functionality
- Application launching (browser, terminal, file manager, text editor)
- Audio functionality
- File operations
- Desktop customization
- Clipboard functionality
- System responsiveness
- Error handling

**Run Command**:
```bash
sudo ./testing/test-framework.sh -c user-acceptance
```

## Manual Testing Procedures

### Pre-Installation Testing
1. **System Requirements**:
   - Ubuntu 24.04 (Noble) VM
   - Minimum 4GB RAM
   - 20GB disk space
   - Internet connectivity
   - Root access

2. **Baseline Tests**:
   ```bash
   # Check OS version
   lsb_release -a
   
   # Check available resources
   free -h
   df -h
   
   # Test internet connectivity
   ping -c 4 google.com
   ```

### Post-Installation Testing
1. **Service Verification**:
   ```bash
   # Check all services are running
   systemctl status selkies-desktop
   systemctl status selkies
   systemctl status selkies-nginx
   systemctl status docker
   
   # Check service dependencies
   systemctl list-dependencies selkies-desktop
   ```

2. **Web Interface Testing**:
   ```bash
   # Test web interface accessibility
   curl -I http://localhost:3000
   
   # Test HTTPS interface
   curl -I -k https://localhost:3001
   
   # Test WebSocket endpoint
   curl -I http://localhost:8082
   ```

3. **Desktop Environment Testing**:
   ```bash
   # Check display server
   DISPLAY=:1 xset q
   
   # Check desktop processes
   pgrep -af "xfce4-session|openbox"
   
   # Test audio system
   sudo -u abc PULSE_RUNTIME_PATH=/defaults pactl info
   ```

### Functional Testing
1. **Browser Testing**:
   - Launch browser from web interface
   - Navigate to test websites
   - Test file downloads
   - Verify browser wrappers work

2. **File Manager Testing**:
   - Open file manager
   - Navigate directories
   - Create/edit/delete files
   - Test permissions

3. **Terminal Testing**:
   - Open terminal
   - Execute commands
   - Test Docker access
   - Verify environment variables

4. **Audio Testing**:
   - Test audio playback
   - Check audio devices
   - Verify audio streaming

## Troubleshooting

### Diagnostic Tools
The testing framework includes comprehensive diagnostic tools:

```bash
# Run full diagnostic
sudo ./testing/troubleshooting/diagnostic-tools.sh

# Specific diagnostics
sudo ./testing/troubleshooting/diagnostic-tools.sh -s    # System info
sudo ./testing/troubleshooting/diagnostic-tools.sh -v    # Services
sudo ./testing/troubleshooting/diagnostic-tools.sh -n    # Network
sudo ./testing/troubleshooting/diagnostic-tools.sh -d    # Display
sudo ./testing/troubleshooting/diagnostic-tools.sh -o    # Docker
sudo ./testing/troubleshooting/diagnostic-tools.sh -l    # Logs
```

### Common Issues and Solutions

#### 1. Web Interface Not Accessible
**Symptoms**: Cannot access http://localhost:3000
**Solutions**:
```bash
# Check nginx service
systemctl status selkies-nginx

# Check nginx configuration
nginx -t

# Check listening ports
netstat -tlnp | grep :3000

# Restart nginx service
systemctl restart selkies-nginx
```

#### 2. Desktop Environment Not Starting
**Symptoms**: Black screen or no desktop visible
**Solutions**:
```bash
# Check display server
DISPLAY=:1 xset q

# Check desktop process
pgrep -af "xfce4-session|openbox"

# Check service logs
journalctl -u selkies-desktop -f

# Restart desktop service
systemctl restart selkies-desktop
```

#### 3. Audio Not Working
**Symptoms**: No audio output or input
**Solutions**:
```bash
# Check PulseAudio service
systemctl status selkies-pulseaudio

# Check audio devices
sudo -u abc PULSE_RUNTIME_PATH=/defaults pactl list sinks

# Check audio modules
sudo -u abc PULSE_RUNTIME_PATH=/defaults pactl list modules

# Restart audio service
systemctl restart selkies-pulseaudio
```

#### 4. Docker Not Accessible
**Symptoms**: User cannot access Docker
**Solutions**:
```bash
# Check Docker service
systemctl status docker

# Check user groups
groups abc

# Add user to docker group
usermod -aG docker abc

# Restart Docker service
systemctl restart docker
```

#### 5. Performance Issues
**Symptoms**: Slow response times or high resource usage
**Solutions**:
```bash
# Check system resources
top
free -h
df -h

# Check service performance
systemctl status selkies-desktop
journalctl -u selkies -f

# Monitor resource usage
./testing/test-framework.sh -c performance
```

## Test Reports

### Report Generation
Test results are automatically generated in HTML format:
- **Location**: `/tmp/webtop-tests/test-report.html`
- **Content**: Test results, metrics, logs, and recommendations
- **Access**: Open in web browser or copy to local machine

### Report Components
1. **Test Summary**: Pass/fail counts and overall results
2. **Detailed Results**: Individual test outcomes and timings
3. **Performance Metrics**: Response times, resource usage, benchmarks
4. **Error Analysis**: Failed test details and error messages
5. **Recommendations**: Suggested fixes and improvements

### Log Files
- **Test Logs**: `/tmp/webtop-tests/test.log`
- **Diagnostic Reports**: `/tmp/webtop-diagnostics/`
- **Service Logs**: `journalctl -u <service-name>`
- **System Logs**: `/var/log/syslog`

## Continuous Testing

### Automated Testing
Set up automated testing for continuous validation:

```bash
# Create test cron job
cat > /etc/cron.d/webtop-tests << 'EOF'
# Run daily health checks
0 2 * * * root /path/to/testing/test-framework.sh -c integration
EOF

# Create systemd timer
systemctl enable webtop-tests.timer
systemctl start webtop-tests.timer
```

### Monitoring Integration
Integrate with monitoring systems:
- **Prometheus**: Export test metrics
- **Grafana**: Create dashboards
- **AlertManager**: Set up alerts for test failures

## Best Practices

### Test Environment
1. **Isolation**: Run tests in isolated environment
2. **Cleanup**: Clean up test artifacts after completion
3. **Documentation**: Document test procedures and results
4. **Version Control**: Track test configurations and results

### Test Execution
1. **Prerequisites**: Verify system requirements before testing
2. **Sequence**: Follow proper test execution order
3. **Logging**: Enable verbose logging for debugging
4. **Validation**: Verify test results before proceeding

### Troubleshooting
1. **Systematic**: Follow systematic troubleshooting approach
2. **Documentation**: Document issues and resolutions
3. **Logs**: Collect comprehensive logs for analysis
4. **Escalation**: Know when to escalate issues

## Support and Resources

### Getting Help
- **Documentation**: Review testing documentation
- **Logs**: Check test logs and diagnostic reports
- **Community**: Consult community forums and resources
- **Support**: Contact technical support with diagnostic reports

### Additional Resources
- **Project Documentation**: `../OVERVIEW.md`, `../ARCHITECTURE.md`
- **Installation Guides**: Component-specific installation scripts
- **Troubleshooting**: Diagnostic tools and procedures
- **Performance Tuning**: Optimization guides and best practices

## Conclusion

This testing framework provides comprehensive validation of the Ubuntu VM Webtop Environment. Regular testing ensures system reliability, performance, and security. Use the automated test suites for routine validation and the diagnostic tools for troubleshooting issues.

For questions or issues, refer to the diagnostic reports and follow the troubleshooting procedures outlined in this guide. 
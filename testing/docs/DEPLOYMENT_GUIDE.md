# Ubuntu VM Webtop Environment - Deployment Guide

## Overview

This deployment guide provides step-by-step instructions for deploying the Ubuntu VM Webtop Environment from installation through testing and maintenance. Follow this guide to ensure a successful deployment.

## Prerequisites

### System Requirements
- **OS**: Ubuntu 24.04 (Noble) VM
- **RAM**: Minimum 4GB (8GB recommended)
- **Disk**: 20GB available space
- **Network**: Internet connectivity for package downloads
- **Access**: Root/sudo privileges

### VM Configuration
- **CPU**: 2+ cores recommended
- **GPU**: Optional (for hardware acceleration)
- **Network**: NAT or bridged network for web access
- **Storage**: SSD recommended for better performance

## Phase 1: Pre-Deployment Preparation

### 1. System Validation
```bash
# Check OS version
lsb_release -a
# Should show: Ubuntu 24.04 LTS (Noble Numbat)

# Check available resources
free -h
df -h

# Test internet connectivity
ping -c 4 google.com
curl -I https://google.com
```

### 2. Update System
```bash
# Update package lists
apt update

# Upgrade system packages
apt upgrade -y

# Install essential tools
apt install -y curl wget git vim htop
```

### 3. Create Backup
```bash
# Create system snapshot (if using VM)
# Or create backup of important data
rsync -av /home/ /backup/home/
```

## Phase 2: Foundation Deployment

### 1. Download Project
```bash
# Clone or download the project
git clone <repository-url> /opt/webtop-environment
cd /opt/webtop-environment

# Or extract from archive
tar -xzf webtop-environment.tar.gz -C /opt/
cd /opt/webtop-environment
```

### 2. Install Master Framework
```bash
# Make installer executable
chmod +x install.sh

# Run master installation (dry run first)
./install.sh --dry-run

# Run actual installation
./install.sh
```

### 3. Verify Foundation
```bash
# Check installation status
./install.sh --help

# Verify directory structure
ls -la selkies/ webtop/ testing/
```

## Phase 3: Selkies Framework Deployment

### 1. Install Selkies Component
```bash
# Navigate to selkies directory
cd selkies/

# Run selkies installation
./install.sh

# Verify installation
systemctl status selkies-desktop
```

### 2. Test Selkies Functionality
```bash
# Start selkies services
systemctl start selkies-desktop

# Check service status
systemctl status selkies
systemctl status selkies-nginx
systemctl status xvfb

# Test web interface
curl -I https://localhost:443
```

### 3. Configure Selkies
```bash
# Verify configuration files
ls -la /defaults/
ls -la /etc/selkies/

# Check environment variables
cat /etc/environment

# Test user setup
su - appbox -c "id"
```

## Phase 4: Webtop Component Deployment

### 1. Install Webtop Component
```bash
# Navigate to webtop directory
cd webtop/

# Run webtop installation
./install.sh

# Verify installation
ls -la /defaults/xfce/
systemctl status selkies-desktop
```

### 2. Test XFCE Desktop
```bash
# Restart desktop service
systemctl restart selkies-desktop

# Check desktop process
pgrep -af "xfce4-session"

# Test web interface with XFCE
curl -I https://localhost:443
```

### 3. Verify Webtop Integration
```bash
# Check webtop flag
ls -la /etc/selkies/webtop-installed

# Test desktop environment selection
cat /etc/selkies/svc-de.sh | grep -A 10 "webtop-installed"
```

## Phase 5: Testing and Validation

### 1. Run Component Tests
```bash
# Navigate to testing directory
cd testing/

# Run component validation
./test-framework.sh -c component

# Check results
cat /tmp/webtop-tests/test.log
```

### 2. Run Integration Tests
```bash
# Run end-to-end integration tests
./test-framework.sh -c integration

# View HTML report
# Copy /tmp/webtop-tests/test-report.html to local machine
```

### 3. Performance Validation
```bash
# Run performance benchmarks
./test-framework.sh -c performance

# Check performance metrics
cat /tmp/webtop-tests/performance-report.txt
```

### 4. Security Validation
```bash
# Run security tests
./test-framework.sh -c security

# Review security report
cat /tmp/webtop-tests/security-report.txt
```

### 5. User Acceptance Testing
```bash
# Run user acceptance tests
./test-framework.sh -c user-acceptance

# Test manual functionality
# - Access web interface
# - Test desktop environment
# - Verify applications work
```

## Phase 6: Production Configuration

### 1. Security Hardening
```bash
# Set up firewall
ufw enable
ufw allow 443/tcp

# Configure SSL certificates
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /config/ssl/cert.key \
    -out /config/ssl/cert.pem

# Set proper permissions
chmod 600 /config/ssl/cert.key
chown appbox:appbox /config/ssl/cert.*
```

### 2. Performance Optimization
```bash
# Optimize systemd services
systemctl daemon-reload

# Configure resource limits
echo "appbox soft nofile 65536" >> /etc/security/limits.conf
echo "appbox hard nofile 65536" >> /etc/security/limits.conf

# Optimize kernel parameters
echo "net.core.rmem_max = 16777216" >> /etc/sysctl.conf
echo "net.core.wmem_max = 16777216" >> /etc/sysctl.conf
sysctl -p
```

### 3. Monitoring Setup
```bash
# Enable service monitoring
systemctl enable selkies-desktop
systemctl enable docker

# Set up log rotation
cat > /etc/logrotate.d/webtop << 'EOF'
/var/log/nginx/*.log {
    daily
    missingok
    rotate 52
    compress
    delaycompress
    notifempty
    create 644 www-data adm
}
EOF
```

## Phase 7: Operational Procedures

### 1. Service Management
```bash
# Start all services
systemctl start selkies-desktop

# Stop all services
systemctl stop selkies-desktop

# Restart services
systemctl restart selkies-desktop

# Check service status
systemctl status selkies-desktop
```

### 2. User Management
```bash
# Check user configuration
id appbox
groups appbox

# Reset user password (if needed)
passwd appbox

# Update user permissions
usermod -aG docker appbox
```

### 3. Configuration Updates
```bash
# Update environment variables
vim /etc/environment

# Update nginx configuration
vim /etc/nginx/sites-available/default
nginx -t
systemctl reload nginx

# Update XFCE configuration
vim /defaults/xfce/xfce4-panel.xml
systemctl restart selkies-desktop
```

## Maintenance and Troubleshooting

### 1. Regular Maintenance
```bash
# Update system packages
apt update && apt upgrade -y

# Clean up logs
journalctl --vacuum-time=30d

# Check disk space
df -h
du -sh /config /var/log

# Monitor system performance
top
htop
```

### 2. Backup Procedures
```bash
# Backup configuration
tar -czf /backup/webtop-config-$(date +%Y%m%d).tar.gz \
    /etc/selkies \
    /defaults \
    /config \
    /etc/systemd/system/selkies-*

# Backup user data
rsync -av /config/ /backup/user-data/
```

### 3. Troubleshooting Tools
```bash
# Run diagnostic tools
./testing/troubleshooting/diagnostic-tools.sh

# Check specific components
./testing/troubleshooting/diagnostic-tools.sh -v  # Services
./testing/troubleshooting/diagnostic-tools.sh -n  # Network
./testing/troubleshooting/diagnostic-tools.sh -d  # Display

# View diagnostic report
cat /tmp/webtop-diagnostics/diagnostic-report.html
```

### 4. Common Issues

#### Service Startup Issues
```bash
# Check service logs
journalctl -u selkies-desktop -f

# Verify dependencies
systemctl list-dependencies selkies-desktop

# Reset services
systemctl daemon-reload
systemctl reset-failed
systemctl start selkies-desktop
```

#### Web Interface Issues
```bash
# Check nginx status
systemctl status selkies-nginx

# Test configuration
nginx -t

# Check listening ports
netstat -tlnp | grep :443
```

#### Performance Issues
```bash
# Check system resources
top
free -h
df -h

# Monitor service performance
systemctl status selkies-desktop
journalctl -u selkies -f
```

## Scaling and High Availability

### 1. Resource Scaling
```bash
# Monitor resource usage
./testing/test-framework.sh -c performance

# Scale VM resources
# - Increase RAM
# - Add CPU cores
# - Expand disk space
```

### 2. Load Balancing
```bash
# Set up nginx load balancing
vim /etc/nginx/sites-available/default

# Configure multiple instances
# (Advanced configuration)
```

### 3. Backup and Recovery
```bash
# Automated backup script
cat > /usr/local/bin/webtop-backup.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/backup/webtop-$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"
tar -czf "$BACKUP_DIR/system-config.tar.gz" /etc/selkies /defaults
rsync -av /config/ "$BACKUP_DIR/user-data/"
EOF

chmod +x /usr/local/bin/webtop-backup.sh

# Schedule automated backups
echo "0 3 * * * root /usr/local/bin/webtop-backup.sh" >> /etc/crontab
```

## Best Practices

### 1. Security
- Keep system updated
- Use strong passwords
- Enable firewall
- Regular security audits
- Monitor logs

### 2. Performance
- Monitor resource usage
- Optimize configurations
- Regular maintenance
- Performance testing

### 3. Reliability
- Regular backups
- Service monitoring
- Automated testing
- Documentation updates

## Support and Resources

### 1. Documentation
- **Testing Guide**: `testing/docs/TESTING_GUIDE.md`
- **Project Overview**: `OVERVIEW.md`
- **Architecture**: `ARCHITECTURE.md`
- **Changelog**: `CHANGELOG.md`

### 2. Troubleshooting
- **Diagnostic Tools**: `testing/troubleshooting/diagnostic-tools.sh`
- **Test Framework**: `testing/test-framework.sh`
- **Component Tests**: `testing/component/`

### 3. Community
- Project documentation
- Issue tracking
- Community forums
- Technical support

## Conclusion

This deployment guide provides a comprehensive approach to deploying the Ubuntu VM Webtop Environment. Follow the phases sequentially, validate each step, and maintain regular testing and monitoring for optimal performance.

For additional support, use the diagnostic tools and refer to the troubleshooting procedures outlined in this guide. 
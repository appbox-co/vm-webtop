# Differences from docker-webtop

## Overview
This document outlines the differences between the original `docker-webtop` Dockerfile and the VM implementation for Ubuntu Noble with systemd.

## Key Changes

### 1. Base Image Dependency
- **Original**: Uses `ghcr.io/linuxserver/baseimage-selkies:ubuntunoble` as base image
- **VM Implementation**: Requires separate selkies component installation first
- **Impact**: Webtop depends on selkies being installed and configured

### 2. Package Installation
- **Original**: Single `apt-get install` command in Dockerfile
- **VM Implementation**: Structured installation with repository setup
- **Packages**: Same 6 packages installed:
  - `chromium`
  - `mousepad`
  - `xfce4-terminal`
  - `xfce4`
  - `xubuntu-default-settings`
  - `xubuntu-icon-theme`

### 3. Repository Setup
- **Original**: Inline repository configuration in Dockerfile
- **VM Implementation**: Structured repository setup with GPG key validation
- **Repository**: xtradeb PPA (ppa:xtradeb/apps) for Ubuntu Noble

### 4. Icon Management
- **Original**: Downloaded during Docker build process
- **VM Implementation**: Downloaded during installation to `/usr/share/selkies/www/icon.png`
- **URL**: `https://raw.githubusercontent.com/linuxserver/docker-templates/master/linuxserver.io/img/webtop-logo.png`

### 5. Binary Modifications
- **Original**: Direct file operations in Dockerfile
- **VM Implementation**: Structured binary replacement with backup
- **Changes**:
  - `chromium` → `chromium-browser` (original backed up)
  - `exo-open` → `exo-open-real` (original backed up)
  - `thunar` → `thunar-real` (original backed up)
  - New wrapper scripts installed in place of originals

### 6. Desktop Integration
- **Original**: Direct integration with selkies base image
- **VM Implementation**: Flag-based integration with selkies desktop service
- **Method**: Creates `/etc/selkies/webtop-installed` flag file
- **Detection**: selkies desktop service checks flag and uses appropriate DE

### 7. Configuration Files
- **Original**: Files copied via `COPY /root /` in Dockerfile
- **VM Implementation**: Files stored in `rootfs/` structure and copied during installation
- **Structure**:
  - `defaults/startwm.sh` - XFCE startup script
  - `defaults/xfce/*.xml` - XFCE configuration files
  - `usr/bin/*` - Modified browser wrappers
  - `usr/local/bin/wrapped-chromium` - Wrapped chromium binary

### 8. Environment Variables
- **Original**: `ENV TITLE="Ubuntu XFCE"` in Dockerfile
- **VM Implementation**: Added to `/etc/environment` during installation
- **Variable**: `TITLE=Ubuntu XFCE`

### 9. Service Architecture
- **Original**: Inherits selkies service structure from base image
- **VM Implementation**: Integrates with existing selkies systemd services
- **Services**: No new services created, uses existing selkies-desktop.service
- **Integration**: Desktop service detects webtop and uses XFCE instead of OpenBox

### 10. File System Structure

#### Original Docker Structure:
```
/root/
├── defaults/
│   ├── startwm.sh
│   └── xfce/
│       ├── xfce4-panel.xml
│       ├── xfwm4.xml
│       └── xsettings.xml
├── usr/
│   ├── bin/
│   │   ├── chromium
│   │   ├── exo-open
│   │   └── thunar
│   └── local/
│       └── bin/
│           └── wrapped-chromium
```

#### VM Implementation Structure:
```
webtop/
├── rootfs/
│   ├── defaults/
│   │   ├── startwm.sh
│   │   └── xfce/
│   │       ├── xfce4-panel.xml
│   │       ├── xfwm4.xml
│   │       └── xsettings.xml
│   ├── usr/
│   │   ├── bin/
│   │   │   ├── chromium
│   │   │   ├── exo-open
│   │   │   └── thunar
│   │   └── local/
│   │       └── bin/
│   │           └── wrapped-chromium
│   └── etc/
│       └── environment
└── install.sh
```

### 11. Installation Process

#### Original Docker Build:
1. Single RUN command with all operations
2. Repository setup, package installation, tweaks in one layer
3. COPY command for file addition
4. Inherits selkies functionality from base image

#### VM Installation:
1. Dependency validation (selkies must be installed)
2. Repository setup with GPG key validation
3. Package installation with proper error handling
4. Icon download with validation
5. Binary modifications with backup
6. Configuration file deployment
7. Environment variable setup
8. Service integration with flag file
9. Cleanup and validation

### 12. Desktop Environment Selection
- **Original**: Always uses XFCE (inherited from selkies base)
- **VM Implementation**: Dynamic selection based on webtop installation
- **Logic**: 
  - If webtop installed: Use XFCE via `/defaults/startwm.sh`
  - If webtop not installed: Use OpenBox via `openbox-session`
- **Detection**: Checks for `/etc/selkies/webtop-installed` flag file

### 13. Cleanup Strategy
- **Original**: Single cleanup command in Dockerfile
- **VM Implementation**: Structured cleanup with multiple targets
- **Targets**:
  - Package cache cleanup
  - Config cache removal
  - Temporary file cleanup
  - Same directories as original

### 14. Error Handling
- **Original**: Basic Docker build error handling
- **VM Implementation**: Comprehensive error handling with validation
- **Features**:
  - Dependency validation
  - Installation validation
  - Rollback capabilities
  - Colored output for better user experience

### 15. Security Considerations
- **Original**: Container-based security model
- **VM Implementation**: VM-based security with proper file permissions
- **Permissions**: All files properly owned by abc:abc user
- **Executable**: Scripts properly marked as executable

## Environment Variables

### Preserved Variables:
- `TITLE=Ubuntu XFCE` (set in `/etc/environment`)

### Integration Variables:
- All selkies environment variables are preserved
- Webtop adds to existing environment rather than replacing

## Compatibility

### Maintained Features:
- Same XFCE desktop environment
- Same browser wrapper functionality
- Same configuration file structure
- Same web interface accessibility (port 3000)
- Same icon and branding

### Enhanced Features:
- Better error handling and validation
- Structured installation process
- Integration with existing selkies services
- Dynamic desktop environment selection
- Comprehensive logging and feedback

## Installation Dependencies

### Prerequisites:
1. Ubuntu Noble VM environment
2. Selkies component installed and configured
3. systemd service management
4. Root access for installation

### Installation Order:
1. Base system setup (Phase 1-2)
2. Selkies installation (Phase 3)
3. Webtop installation (Phase 4)
4. Additional components (Phase 5)

## Testing and Validation

### Installation Validation:
- Package installation verification
- Configuration file validation
- Binary modification verification
- Service integration testing
- Icon download validation

### Runtime Validation:
- Desktop environment starts correctly
- Browser wrappers function properly
- XFCE configuration applies correctly
- Web interface accessibility
- Title display in web interface 
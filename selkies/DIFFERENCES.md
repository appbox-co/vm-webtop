# Differences from docker-baseimage-selkies

## Overview
This document outlines the differences between the original `docker-baseimage-selkies` Dockerfile and the VM implementation for Ubuntu Noble with systemd.

## Key Changes

### 1. Init System Conversion
- **Original**: Uses s6-overlay for service management
- **VM Implementation**: Uses systemd services
- **Impact**: All s6 services converted to systemd units with proper dependencies

### 2. Service Structure Changes

#### s6-overlay to systemd mapping:
| Original s6 Service | systemd Service | Function |
|-------------------|-----------------|----------|
| `init-selkies` | N/A (initialization in service scripts) | Basic selkies init |
| `init-nginx` | ExecStartPre in `selkies-nginx.service` | Nginx configuration |
| `init-selkies-config` | ExecStartPre in `selkies.service` | Main selkies configuration |
| `init-video` | ExecStartPre in `selkies-desktop.service` | Video device permissions |
| `svc-xorg` | `xvfb.service` | X server (Xvfb) |
| `svc-pulseaudio` | `selkies-pulseaudio.service` | Audio server |
| `svc-docker` | `selkies-docker.service` | Docker daemon |
| `svc-nginx` | `selkies-nginx.service` | Web server |
| `svc-selkies` | `selkies.service` | Main selkies process |
| `svc-de` | `selkies-desktop.service` | Desktop environment |

### 3. File System Changes

#### Configuration Files:
- **Original**: Files in `/defaults/` accessed directly
- **VM Implementation**: Files copied to `/defaults/` during installation
- **Location**: Configuration files stored in `rootfs/defaults/`

#### Service Scripts:
- **Original**: s6-overlay service scripts in `/etc/s6-overlay/s6-rc.d/`
- **VM Implementation**: systemd service scripts in `/etc/selkies/`
- **Scripts Created**:
  - `/etc/selkies/init-nginx.sh` - Nginx configuration setup
  - `/etc/selkies/init-selkies-config.sh` - Main selkies configuration
  - `/etc/selkies/init-video.sh` - Video device permissions
  - `/etc/selkies/svc-de.sh` - Desktop environment startup

### 4. Environment Variable Handling
- **Original**: Environment variables managed by s6-overlay
- **VM Implementation**: Environment variables set in `/etc/environment` and service files
- **Method**: Combined approach using environment files and systemd Environment directives

### 5. User Management
- **Original**: Container-based user management
- **VM Implementation**: Standard Linux user management
- **Changes**: 
  - User `abc` created with proper home directory
  - Docker group membership handled during installation
  - Sudo permissions configured for VM environment

### 6. Multi-Stage Build Simulation
- **Original**: Docker multi-stage build with frontend and xvfb stages
- **VM Implementation**: Sequential extraction and build process
- **Process**:
  1. Extract custom Xvfb binary from `lscr.io/linuxserver/xvfb:ubuntunoble`
  2. Build selkies frontend components using npm
  3. Build selkies Python packages from source
  4. Build joystick interposer and fake udev libraries

### 7. Service Dependencies
- **Original**: s6-overlay dependency management
- **VM Implementation**: systemd dependency management
- **Dependency Chain**: 
  ```
  xvfb.service
  ↓
  selkies-pulseaudio.service
  ↓
  selkies-docker.service
  ↓
  selkies-nginx.service
  ↓
  selkies.service
  ↓
  selkies-desktop.service
  ```

### 8. Package Management
- **Original**: Single RUN command with package installation
- **VM Implementation**: Structured package installation with repository setup
- **Changes**:
  - Added explicit repository setup for Docker and Node.js
  - Maintained all 60+ package dependencies
  - Added development dependencies management with cleanup

### 9. Build Process
- **Original**: Docker COPY commands for adding files
- **VM Implementation**: Pre-organized files in `rootfs/` structure, copied during installation
- **Structure**: All configuration files stored in `rootfs/` directory following Linux filesystem hierarchy
- **Improvement**: Configuration files are version-controlled and easily maintainable (no dynamic generation)

### 10. Logging and Monitoring
- **Original**: s6-overlay logging
- **VM Implementation**: systemd journal logging
- **Benefits**: Integration with system logging infrastructure

## Environment Variables

### Preserved Environment Variables:
- `DISPLAY=:1`
- `HOME=/config`
- `START_DOCKER=true`
- `PULSE_RUNTIME_PATH=/defaults`
- `SELKIES_INTERPOSER=/usr/lib/selkies_joystick_interposer.so`
- `NVIDIA_DRIVER_CAPABILITIES=all`
- `DISABLE_ZINK=false`
- `TITLE=Selkies`
- `GST_DEBUG=*:1`
- `SELKIES_ENCODER=x264enc`
- `SELKIES_FRAMERATE=60`
- `SELKIES_ENABLE_RESIZE=true`
- `DISPLAY_SIZEW=1024`
- `DISPLAY_SIZEH=768`
- `DISPLAY_REFRESH=60`
- `DISPLAY_DPI=96`
- `DISPLAY_CDEPTH=24`

### New Environment Variables:
- `PERL5LIB=/usr/local/bin` (moved from Dockerfile ENV)

## Installation Process

### Original Docker Build:
1. Multi-stage build with frontend compilation
2. Package installation
3. Source code compilation
4. File copying with COPY commands
5. Service setup with s6-overlay

### VM Installation:
1. Repository setup and package installation
2. Docker image extraction for pre-built components
3. Source code compilation and building
4. Configuration file verification (all files pre-stored in rootfs/)
5. systemd service verification (all services pre-created in rootfs/)
6. File copying from rootfs/ to system root
7. Environment configuration
8. User and permission setup
9. Service enablement

## Compatibility Considerations

### Maintained Features:
- All original functionality preserved
- Same web interface accessibility (port 443)
- Same environment variables and configuration options
- Same build dependencies and source compilation
- Same user experience and desktop environment

### VM-Specific Adaptations:
- systemd service management instead of s6-overlay
- Standard Linux user management
- Integration with system logging
- Proper filesystem hierarchy usage
- VM-appropriate file permissions
- Pre-organized configuration files in rootfs/ structure (improved maintainability)

## Testing and Validation

### Service Testing:
- Each systemd service can be tested independently
- Service dependencies ensure proper startup order
- systemd provides better process management and restart policies

### Functionality Testing:
- Web interface accessibility
- Desktop environment functionality
- Audio and video device access
- Docker-in-Docker functionality
- Joystick and gamepad support

This implementation maintains full compatibility with the original docker-baseimage-selkies while adapting it for systemd-based VM environments. 
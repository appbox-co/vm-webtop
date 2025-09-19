# Differences from docker-baseimage-selkies

## Overview
This document outlines the differences between the original `docker-baseimage-selkies` Dockerfile and the VM implementation for Ubuntu Noble with systemd.

## Key Changes

### Version Updates
- **Selkies Commit**: Updated from `e1adbd8c5213fcc00b56d05337cf62d5701b2ed7` to `6cbd7f04cdf88a4cf90dbdbc398407746718e33d`
- **Alpine Base**: Updated from `3.21` to `3.22` for frontend extraction

### Major Enhancements Beyond Original
- **Kernel Bug Fix**: Critical update to linux-image-generic-6.14 to fix virtiofs execv() bug affecting kernels < 6.11
- **Audio Stuttering Fix**: Implemented `pulse-alsa-fix` to eliminate audio stuttering in all applications
- **Snap Store Integration**: Full snap application support with desktop menu integration
- **Flatpak Integration**: Complete Flatpak support with permissions and desktop integration
- **User Systemd Integration**: Proper systemd --user session management with D-Bus integration
- **Application Store Support**: Both Snap Store and Flatpak appear in desktop menu automatically

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
| `svc-docker` | N/A (uses system docker.service) | Docker daemon |
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
  - User `appbox` created with proper home directory
  - Docker group membership handled during installation
  - Sudo permissions configured for VM environment

### 6. Multi-Stage Build Simulation
- **Original**: Docker multi-stage build with frontend and xvfb stages
- **VM Implementation**: Sequential extraction and build process
- **Process**:
  1. Extract custom Xvfb binary from `lscr.io/linuxserver/xvfb:ubuntunoble`
  2. Extract pre-built frontend from `ghcr.io/linuxserver/baseimage-alpine:3.22`
  3. Build selkies Python packages in virtual environment
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
  - Updated to 70+ package dependencies including new GUI libraries
  - Added temporary development dependencies with cleanup
  - Added packages: libatk1.0-0, libatk-bridge2.0-0, libgtk-3.0, libnss3, libxcb-icccm4, libxcb-image0, libxcb-keysyms1, libxcb-render-util0, libxkbcommon-x11-0, python3-venv, xsettingsd

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
3. Python virtual environment creation and selkies installation
4. Source code compilation (joystick interposer, fake udev)
5. Configuration file verification (all files pre-stored in rootfs/)
6. systemd service verification (all services pre-created in rootfs/)
7. File copying from rootfs/ to system root
8. Environment configuration
9. User and permission setup
10. Service enablement

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
- Python virtual environment for selkies installation
- Removal of cryptography dependency from selkies build
- Updated OpenBox configuration (single desktop)

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

## 🎵 Audio and Application Integration Enhancements

### Audio Stuttering Resolution
- **Problem**: ALSA applications (especially snaps) experienced audio stuttering due to PulseAudio null sink timing issues
- **Solution**: `pulse-alsa-fix` script creates 25Hz peak detection streams with 40ms latency (simulates pavucontrol behavior)
- **Implementation**: `/usr/local/bin/pulse-alsa-fix` runs continuously, maintaining low-latency audio pipeline
- **Result**: Eliminated stuttering in all applications including Spotify snap, Discord, and other audio applications

### Snap Store Integration
- **Package Installation**: Added `snapd`, `ibus` packages for full snap support
- **PolicyKit Rules**: `/etc/polkit-1/rules.d/50-snap-appbox.rules` grants appbox user snap management permissions
- **Desktop Integration**: XDG_DATA_DIRS includes `/var/lib/snapd/desktop` for menu entries
- **Audio Support**: Dual PulseAudio socket configuration (`/run/user/1000/pulse/native` and `/defaults/native`)
- **ALSA Configuration**: `/etc/asound.conf` routes all ALSA audio through PulseAudio for snap compatibility

### Flatpak Integration
- **Remote Setup**: Flathub remote configured automatically during installation
- **PolicyKit Rules**: `/etc/polkit-1/rules.d/50-flatpak-appbox.rules` grants appbox user Flatpak permissions
- **Desktop Integration**: XDG_DATA_DIRS includes Flatpak export directories for menu entries
- **Directory Setup**: Proper `/var/lib/flatpak/exports/share` and user-specific directories created

### User Systemd Integration
- **Session Management**: PAM-based XDG_RUNTIME_DIR creation and systemd --user startup
- **D-Bus Integration**: `dbus-run-session` ensures proper D-Bus session for desktop applications
- **Environment Variables**: XDG_SESSION_TYPE, XDG_SESSION_CLASS, XDG_DATA_DIRS properly configured
- **Service Dependencies**: `selkies-desktop.service` uses `PAMName=login` for proper session setup
- **User Services**: Conflicting PulseAudio user services disabled to prevent interference

### Desktop Environment Polish
- **Terminal Wrapper**: `/usr/local/bin/terminal-wrapper` ensures proper environment for terminal launches
- **Application Launching**: Fixed exo-open recursion issues with terminal and browser launching
- **Menu Integration**: Automatic desktop database updates for all application stores
- **Fork Bomb Prevention**: Resolved infinite recursion in application wrapper scripts

### Enhanced Audio Pipeline
- **Dual Socket Support**: PulseAudio accessible via both legacy and modern paths
- **Low Latency Configuration**: 40ms latency maintained through continuous peak detection
- **ALSA Plugin Integration**: All ALSA applications automatically route through PulseAudio
- **Snap Audio Support**: Special configuration for confined snap applications
- **Client Configuration**: `/etc/pulse/client.conf` optimized for multi-application access

### Virtiofs Compatibility Fix
- **Critical Bug**: Kernels < 6.11 have a bug where `execv()` system call fails on virtiofs filesystem mounts
- **VM Impact**: This affects VM environments using virtiofs for shared directories (common in modern VM setups)
- **Symptoms**: Applications fail to launch with "Exec format error" or similar errors on virtiofs mounts
- **Solution**: Kernel 6.14 includes the upstream fix for proper virtiofs executable support
- **Implementation**: `update_kernel()` function automatically detects affected kernels and updates
- **Detection**: Script checks kernel version and warns if < 6.11 (affected by bug)

## Project Status

This implementation not only maintains full compatibility with the original docker-baseimage-selkies but significantly enhances it with:
- ✅ Critical virtiofs execv() bug fix for proper VM compatibility
- ✅ Complete application store integration (Snap Store + Flatpak)
- ✅ Resolved audio stuttering issues affecting all applications
- ✅ Proper user systemd and D-Bus session management
- ✅ Enhanced desktop environment with seamless application launching
- ✅ Production-ready multimedia support for all application types

**The VM implementation now exceeds the original Docker container's capabilities while maintaining full compatibility and addressing critical VM-specific issues.** 
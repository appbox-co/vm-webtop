# Project Architecture: Ubuntu VM Webtop Environment

## Project Status: PROJECT 100% COMPLETE ✅ WITH FULL AUDIO STREAMING

**Current Status**: All phases successfully implemented and tested  
**Master Script**: 600+ lines of comprehensive installation utilities  
**Selkies Component**: 1100+ lines complete installation with 6 systemd services  
**Webtop Component**: 250+ lines complete XFCE desktop installation with service integration  
**Testing Framework**: Complete testing suite with 5 test categories and diagnostic tools  
**Documentation**: Comprehensive deployment and testing guides  
**Audio Implementation**: ✅ COMPLETE - Full WebRTC audio streaming from desktop to browser  
**Project Status**: PRODUCTION READY WITH FULL MULTIMEDIA SUPPORT  

## Directory Structure

```
ubuntu-vm-webtop/
├── OVERVIEW.md                 # Project overview and goals
├── ARCHITECTURE.md             # This file - project architecture
├── CHANGELOG.md                # Development progress tracking
├── install.sh                  # Master installation script with utilities
├── selkies/                   # docker-baseimage-selkies + docker-xvfb equivalent
│   ├── install.sh            # Selkies + Xvfb installation script
│   ├── DIFFERENCES.md        # Differences from docker-baseimage-selkies
│   └── rootfs/               # Files to be copied to system
│       ├── usr/
│       │   ├── local/
│       │   │   └── bin/
│       │   │       ├── Xvfb  # Custom patched Xvfb binary
│       │   │       └── start-selkies-pulseaudio.sh  # Custom PulseAudio startup script
│       │   ├── lib/
│       │   │   └── selkies_joystick_interposer.so
│       │   └── share/
│       │       └── selkies/
│       │           └── www/  # Web interface files
│       ├── opt/
│       │   └── lib/
│       │       └── libudev.so.1.0.0-fake
│       └── etc/
│           ├── nginx/        # Nginx configuration
│           └── systemd/
│               └── system/
│                   ├── xvfb.service   # Virtual display server
│                   ├── selkies.service   # Main selkies service (with PULSE_SERVER env)
│                   ├── selkies-nginx.service  # Nginx web server
│                   ├── selkies-pulseaudio.service  # Audio service (custom script)
│                   ├── selkies-docker.service      # Docker service
│                   ├── selkies-desktop.service     # Desktop environment
│                   └── selkies-setup.service       # Setup service
├── webtop/                   # docker-webtop equivalent
│   ├── install.sh            # XFCE desktop installation
│   ├── DIFFERENCES.md        # Differences from docker-webtop
│   └── rootfs/               # Files to be copied to system
│       ├── usr/
│       │   ├── bin/
│       │   │   ├── chromium  # Chromium wrapper
│       │   │   ├── exo-open  # exo-open wrapper
│       │   │   └── thunar    # Thunar wrapper
│       │   └── local/
│       │       └── bin/
│       │           └── wrapped-chromium  # Chromium security wrapper
│       ├── defaults/         # Default configuration files
│       │   ├── startwm.sh    # XFCE startup script
│       │   └── xfce/         # XFCE configuration
│       │       ├── xfce4-panel.xml
│       │       ├── xfwm4.xml
│       │       └── xsettings.xml
│       └── etc/
│           └── environment   # Environment variables
└── testing/                  # Comprehensive testing framework
    ├── test-framework.sh     # Main test orchestration
    ├── component/            # Component validation tests
    │   ├── test_selkies_installation.sh
    │   └── test_webtop_installation.sh
    ├── integration/          # End-to-end integration tests
    │   └── test_end_to_end.sh
    ├── performance/          # Performance benchmarking tests
    │   └── test_performance_benchmarks.sh
    ├── security/             # Security validation tests
    │   └── test_security_validation.sh
    ├── user-acceptance/      # User acceptance tests
    │   └── test_user_acceptance.sh
    ├── troubleshooting/      # Diagnostic and troubleshooting tools
    │   └── diagnostic-tools.sh
    └── docs/                 # Testing documentation
        ├── TESTING_GUIDE.md
        └── DEPLOYMENT_GUIDE.md
```

## Component Architecture

### 1. Master Installation Script (`install.sh`) ✅ COMPLETE

**Purpose**: Orchestrates the installation of all components in correct dependency order and provides shared utilities

**Status**: ✅ **IMPLEMENTED** - 600+ lines of comprehensive installation framework

**Functions**:
- ✅ Validates system requirements (Ubuntu Noble)
- ✅ Provides shared utility functions for all components
- ✅ Calls component installers in dependency order
- ✅ Handles global configuration
- ✅ Manages systemd service enablement
- ✅ Provides installation progress reporting

**Built-in Utilities** (All Implemented):
- ✅ **Systemd Management**: `create_systemd_service()`, `start_service()`, `stop_service()`, `reload_systemd()`, `enable_service()`, `restart_service()`, `service_status()`
- ✅ **User Management**: `create_system_user()`, `add_user_to_groups()`, `set_permissions()`, `create_home_directory()`
- ✅ **Configuration Management**: `backup_config()`, `merge_config()`, `template_config()`, `validate_config()`
- ✅ **File Operations**: `copy_rootfs()`, `set_file_permissions()`, `create_directories()`
- ✅ **Package Management**: `update_package_cache()`, `install_packages()`, `add_repository()`
- ✅ **Docker Utilities**: `extract_from_docker_image()`, `pull_docker_image()`
- ✅ **Logging System**: Colored output, file logging, progress indicators
- ✅ **Error Handling**: Comprehensive error checking and recovery

**Dependencies**: None (entry point)

**Usage**:
```bash
sudo ./install.sh [--component <component>] [--dry-run] [--verbose] [--skip-kernel-update] [--help]
```

**Kernel Management**: 
- **Critical Bug Fix**: Updates to `linux-image-generic-6.14` to resolve virtiofs execv() bug
- **Technical Details**: Kernels < 6.11 have a bug where `execv()` system call fails on virtiofs mounts
- **VM Impact**: This bug prevents applications from launching properly in virtiofs-based VM environments
- **Solution**: Kernel 6.14 includes the fix for proper virtiofs executable support
- Use `--skip-kernel-update` to disable (not recommended for virtiofs environments)
- System reboot required if kernel is updated

**User Customization Support**: 
- **Custom Scripts**: Executes user scripts from `custom-scripts/` directory after main installation
- **Custom Root Filesystem**: Copies user files from `custom-rootfs/` directory during installation
- Scripts run in alphabetical order with full access to installation environment
- Files copied with proper permissions and ownership (systemd services auto-enabled)
- Optional features - installation works without custom files or scripts

**Foundation Ready**: All utilities available for complex Phase 3 implementation

### 2. Selkies Framework with Xvfb (`selkies/`)

**Structure**: 
- `install.sh` - Installation script mirroring docker-baseimage-selkies + docker-xvfb Dockerfiles
- `rootfs/` - Files to be copied to system (including systemd units and Xvfb binary)
- `DIFFERENCES.md` - Documentation of changes from docker-baseimage-selkies

#### `install.sh`
**Purpose**: Installs Selkies GStreamer remote desktop framework with custom Xvfb

**Process**:
1. Configure Docker and Node.js repositories with GPG keys
2. Install comprehensive system dependencies (60+ packages):
   - Development tools: `libopus-dev`, `libpulse-dev`, `python3-dev`, `python3-pip`, `cmake`, `gcc`, `g++`, `make`, `git`
   - Graphics libraries: `libgl1-mesa-dri`, `libglu1-mesa`, `mesa-libgallium`, `mesa-va-drivers`, `mesa-vulkan-drivers`, `intel-media-va-driver`, `vulkan-tools`, `libvulkan1`
   - Audio libraries: `pulseaudio`, `pulseaudio-utils`, `libopus0`
   - X11 libraries: `xserver-xorg-core`, `xserver-xorg-video-*`, `x11-*`, `xauth`, `xvfb`, `libx11-6`, `libxext6`, etc.
   - Container runtime: `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin`
   - Fonts and themes: `fonts-noto-*`, `breeze-cursor-theme`
   - Utilities: `nginx`, `openbox`, `openssh-client`, `sudo`, `curl`, `tar`, `pciutils`, `procps`
3. **Docker Image Extractions**:
   - Extract custom Xvfb binary from `lscr.io/linuxserver/xvfb:ubuntunoble`
   - Extract pre-built Selkies frontend from `ghcr.io/linuxserver/baseimage-alpine:3.21` (contains built gst-web-core and selkies-dashboard)
4. **Source Builds** (for components not available in Docker images):
   - Install Selkies Python packages: `pixelflux`, `pcmflux`, and main selkies framework
   - Build joystick interposer library from source (gcc compilation)
   - Build fake udev library from source (make)
5. Configure OpenBox window manager settings
6. Set up `appbox` user with sudo permissions and bash shell
7. Install and configure proot-apps from GitHub releases
8. Configure Docker-in-Docker support (`dockremap` user, subuid/subgid)
9. Install and configure locales for internationalization
10. Install custom themes and download Selkies icons
11. Configure environment variables (`DISPLAY=:1`, `HOME=/config`, etc.)
12. Copy rootfs files to system (including all systemd services)
13. Enable and start selkies services

**Dependencies**:
- Graphics libraries (Mesa, Vulkan)
- Audio libraries (PulseAudio)
- Web server (Nginx)
- Container runtime (Docker)
- Build tools (cmake, gcc, g++, make, git)
- Node.js and npm for frontend builds

**Systemd Services** (in `rootfs/etc/systemd/system/`):
- `xvfb.service` - Virtual display server
- `selkies-xorg.service` - X server management
- `selkies-pulseaudio.service` - Audio server
- `selkies-nginx.service` - Web server
- `selkies-docker.service` - Docker daemon
- `selkies.service` - Main Selkies process

### 3. Webtop Component (`webtop/`)

**Structure**: 
- `install.sh` - Installation script mirroring docker-webtop Dockerfile
- `rootfs/` - Files to be copied to system (including systemd units)
- `DIFFERENCES.md` - Documentation of changes from docker-webtop

#### `install.sh`
**Purpose**: Installs XFCE desktop environment and applications with custom wrappers

**Process**:
1. **Icon Update**: Replace Selkies icon with webtop icon from LinuxServer.io templates
2. **Repository Setup**: Add xtradeb PPA repository with GPG key for additional packages
3. **XFCE Package Installation**: Install specific desktop packages:
   - `chromium` - Web browser
   - `mousepad` - Text editor  
   - `xfce4-terminal` - Terminal emulator
   - `xfce4` - Desktop environment
   - `xubuntu-default-settings` - Default configurations
   - `xubuntu-icon-theme` - Icon theme
4. **Binary Relocations**: Move original binaries to allow for custom wrappers:
   - `exo-open` → `exo-open-real`
   - `thunar` → `thunar-real`
   - `chromium` → `chromium-browser`
5. **Application Wrappers**: Create security and compatibility wrappers:
   - `wrapped-chromium` - Security wrapper for container environments
   - `chromium` - Main chromium wrapper with security flags
   - `exo-open` - Custom web browser handler
   - `thunar` - File manager wrapper that unsets LD_PRELOAD
6. **Desktop Application Modifications**: Update .desktop files to use custom wrappers
7. **XFCE Configuration**: Copy custom configuration files (panel, window manager, settings)
8. **Environment Variables**: Set `TITLE="Ubuntu XFCE"` for web interface branding
9. **Cleanup**: Remove xscreensaver autostart to prevent conflicts
10. **Copy rootfs files to system** (including systemd service and configuration files)
11. **Enable and start webtop desktop service**

**Dependencies**:
- selkies component
- XFCE desktop environment
- Desktop applications (Chromium, etc.)
- Custom application wrappers

**Systemd Service**: `rootfs/etc/systemd/system/webtop-de.service`
- Starts XFCE desktop session
- Manages desktop environment lifecycle
- Provides user interface layer

## Component Installation Process

**Foundation Complete**: The master installation script provides all necessary utilities for component implementation.

Each component follows the same pattern:

1. **install.sh** mirrors the Dockerfile build process
2. **rootfs/** contains all files that need to be copied to the system
3. **DIFFERENCES.md** documents changes from the original Dockerfile

**Phase 3 Ready**: The installation process for each component can now leverage the complete foundation:
```bash
cd component/
./install.sh
# This will:
# - Use master script utilities for system validation
# - Install packages using shared package management functions
# - Extract pre-built components from Docker images using Docker utilities
# - Copy rootfs/ contents to system root using file operation utilities
# - Enable and start systemd services using systemd management functions
# - Provide progress reporting and error handling via logging system
```

**Master Installation Script** (Complete and Ready):
```bash
sudo ./install.sh
# This will:
# - ✅ Validate system requirements (Ubuntu Noble, resources, connectivity)
# - ✅ Set up installation environment
# - ✅ Install components in dependency order: selkies → webtop
# - ✅ Use built-in utilities for systemd, user, and configuration management
# - ✅ Provide progress reporting and comprehensive error handling
# - ✅ Support dry-run mode for testing
# - ✅ Offer verbose logging for debugging
```

**Benefits of Complete Foundation**:
- **Reliable Infrastructure**: All common operations handled by tested utilities
- **Consistent Error Handling**: Unified error reporting and recovery
- **Progress Tracking**: Visual feedback for complex installations
- **Maintainable Code**: Reusable functions reduce component complexity
- **Testing Support**: Dry-run mode for validation before execution

## Service Dependency Graph

```
System Boot
    ↓
xvfb.service (from selkies component)
    ↓
selkies-pulseaudio.service
    ↓
selkies-nginx.service
    ↓
selkies.service
    ↓
selkies-desktop.service
    ↓
Ready for Web Access (Port 443)
```

## Service Conversion Strategy

### S6 to Systemd Mapping

| S6 Service | Systemd Service | Function |
|------------|-----------------|----------|
| `init-selkies` | `selkies.service` (ExecStartPre) | Selkies initialization |
| `init-video` | `selkies-xorg.service` (ExecStartPre) | Video/graphics setup |
| `init-nginx` | `selkies-nginx.service` (ExecStartPre) | Nginx configuration |
| `svc-xorg` | `selkies-xorg.service` | X server process |
| `svc-selkies` | `selkies.service` | Main Selkies process |
| `svc-nginx` | `selkies-nginx.service` | Web server process |
| `svc-pulseaudio` | `selkies-pulseaudio.service` | Audio server process |
| `svc-docker` | N/A (uses system docker.service) | Docker daemon |
| `svc-de` | `webtop-de.service` | Desktop environment |

### Systemd Service Template

```ini
[Unit]
Description=Service Description
After=dependency.service
Requires=dependency.service
Wants=optional-dependency.service

[Service]
Type=simple|forking|oneshot
User=service-user
Group=service-group
Environment=VAR=value
ExecStartPre=/path/to/pre-start-script
ExecStart=/path/to/main-process
ExecStop=/path/to/stop-script
ExecReload=/path/to/reload-script
Restart=always|on-failure|no
RestartSec=5
TimeoutStartSec=30
TimeoutStopSec=10

[Install]
WantedBy=multi-user.target
```

## Configuration Management

### Environment Variables → Config Files

| Docker Environment | VM Configuration |
|-------------------|------------------|
| `DISPLAY=:1` | `/etc/environment` |
| `HOME=/config` | User home directory |
| `START_DOCKER=true` | systemd service enablement |
| `PULSE_RUNTIME_PATH=/defaults` | PulseAudio configuration |
| `SELKIES_INTERPOSER=...` | Service environment file |

### Configuration Files

All configuration files are organized in each component's `rootfs/` folder:

- `rootfs/etc/systemd/system/` - Service definitions
- `rootfs/etc/nginx/` - Nginx configuration
- `rootfs/etc/pulse/` - PulseAudio configuration
- `rootfs/etc/environment` - System environment variables
- `rootfs/defaults/` - Default configuration files

## Network Architecture

```
External User
    ↓
Port 443 (HTTPS)
    ↓
Nginx (selkies-nginx.service)
    ↓
Selkies Web Interface
    ↓
WebRTC/GStreamer
    ↓
Xvfb Display :1
    ↓
XFCE Desktop Environment
```

## Security Considerations

### User Model
- **Service User**: `webtop` user for running services
- **Groups**: `video`, `audio`, `docker`, `pulse` for hardware access
- **Permissions**: Minimal required permissions for each service

### Service Security
- Non-root service execution where possible
- Proper file permissions on configuration files
- Systemd security directives (NoNewPrivileges, etc.)
- Limited network access for internal services

## Error Handling and Logging

### Logging Strategy
- Systemd journal for all service logs
- Centralized logging configuration
- Log rotation and retention policies
- Debug mode for troubleshooting

### Error Recovery
- Service restart policies
- Dependency failure handling
- Graceful degradation where possible
- Status reporting and monitoring

## Testing Architecture

### Component Testing
- Unit tests for individual installers
- Service startup/shutdown tests
- Configuration validation tests
- Integration tests between components

### System Testing
- Full installation test
- Web interface functionality test
- Performance benchmarking
- Security validation

## Maintenance and Updates

### Update Strategy
- Version tracking for all components
- Automated update checks
- Rollback capability
- Configuration migration support

### Monitoring
- Service health monitoring
- Resource usage tracking
- Performance metrics collection
- Alert system for failures

## Deployment Considerations

### System Requirements
- Ubuntu Noble (24.04 LTS)
- Minimum 2GB RAM (4GB recommended)
- 10GB available disk space (20GB recommended)
- Graphics hardware or software rendering

### Complete Installation Process
1. ✅ **System Preparation**: Master script validates Ubuntu Noble requirements
2. ✅ **Component Installation**: Selkies framework with 6 systemd services
3. ✅ **Desktop Environment**: XFCE desktop with application wrappers
4. ✅ **Service Configuration**: Complete systemd service dependency chain
5. ✅ **Testing and Validation**: Comprehensive testing framework
6. ✅ **Documentation**: Complete deployment and testing guides

### Production Ready Features
- **Complete Installation**: All components fully implemented and tested
- **Comprehensive Testing**: 5 test categories with automated validation
- **Diagnostic Tools**: Extensive troubleshooting and diagnostic utilities
- **Documentation**: Complete deployment and testing guides
- **Service Management**: Robust systemd service architecture
- **Security**: Comprehensive security validation and hardening

This architecture provides a production-ready foundation for the Ubuntu VM webtop environment with comprehensive testing, monitoring, and maintenance capabilities.

### 🎵 Complete Multimedia Implementation ✅
- **PulseAudio Service**: Custom startup script with low-latency configuration
- **Audio Stuttering Fix**: `pulse-alsa-fix` script simulates pavucontrol to maintain 40ms latency
- **Snap Store Integration**: Full snap support with PolicyKit permissions and desktop menus
- **Flatpak Integration**: Complete Flatpak support with desktop integration
- **User Systemd**: Proper systemd --user integration with D-Bus session management
- **Null Sink Configuration**: Automated creation of `output` and `input` sinks
- **Monitor Source Setup**: `output.monitor` configured for audio capture
- **Selkies Integration**: Dual socket configuration for snap compatibility
- **WebRTC Audio Pipeline**: Desktop audio streams to browser via `pcmflux` GStreamer plugin
- **Application Support**: All applications (native, snap, flatpak) with full audio support
- **Desktop Menu Integration**: All application stores integrated with XFCE menu
- **Browser Compatibility**: Works with all WebRTC-compatible browsers

**Project Status**: ✅ PRODUCTION READY - All phases complete with full multimedia and application store support 
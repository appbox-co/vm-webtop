#!/bin/bash
# Selkies Component Installation Script - Phase 3
# Based on docker-baseimage-selkies Dockerfile
# Converts s6-overlay services to systemd

set -euo pipefail

# Set non-interactive mode globally to prevent apt hangs
export DEBIAN_FRONTEND=noninteractive

# Configure needrestart to prevent interactive prompts
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
LOG_FILE="/var/log/ubuntu-vm-webtop-install.log"
VERBOSE=false
DRY_RUN=false

# Ensure log directory exists and is writable
if [[ $EUID -eq 0 ]]; then
    mkdir -p "$(dirname "$LOG_FILE")"
    if [[ ! -w "$(dirname "$LOG_FILE")" ]]; then
        LOG_FILE="$SCRIPT_DIR/ubuntu-vm-webtop-install.log"
    fi
else
    LOG_FILE="$SCRIPT_DIR/ubuntu-vm-webtop-install.log"
fi

# Logging functions
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")  echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE" ;;
        "DEBUG") [[ "$VERBOSE" == true ]] && echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE" ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

info() { log "INFO" "$@"; }
warn() { log "WARN" "$@"; }
error() { log "ERROR" "$@"; }
debug() { log "DEBUG" "$@"; }

# Package management functions
update_package_cache() {
    debug "Updating package cache..."
    if [[ "$DRY_RUN" == false ]]; then
        apt-get update -qq
    fi
}

install_packages() {
    local -a packages=("$@")
    debug "Installing packages: ${packages[*]}"
    if [[ "$DRY_RUN" == false ]]; then
        apt-get install -y "${packages[@]}"
    fi
}

# File operations functions
copy_rootfs() {
    local source_dir="$1"
    local target_dir="${2:-/}"
    
    debug "Copying rootfs from $source_dir to $target_dir"
    
    if [[ ! -d "$source_dir" ]]; then
        warn "Source directory does not exist: $source_dir"
        return 1
    fi
    
    if [[ "$DRY_RUN" == false ]]; then
        # Use rsync for better handling of permissions and symlinks
        if command -v rsync &> /dev/null; then
            rsync -av --no-owner --no-group "$source_dir/" "$target_dir/"
        else
            # Fallback to cp
            cp -r "$source_dir/"* "$target_dir/"
        fi
    fi
}

# Systemd functions
reload_systemd() {
    debug "Reloading systemd daemon..."
    if [[ "$DRY_RUN" == false ]]; then
        systemctl daemon-reload
    fi
}

enable_service() {
    local service_name="$1"
    debug "Enabling systemd service: $service_name"
    if [[ "$DRY_RUN" == false ]]; then
        systemctl enable "$service_name"
    fi
}

create_directories() {
    local -a dirs=("$@")
    debug "Creating directories: ${dirs[*]}"
    if [[ "$DRY_RUN" == false ]]; then
        for dir in "${dirs[@]}"; do
            mkdir -p "$dir"
        done
    fi
}

set_permissions() {
    local path="$1"
    local owner="$2"
    local permissions="$3"
    
    debug "Setting permissions on $path: $owner:$permissions"
    if [[ "$DRY_RUN" == false ]]; then
        if [[ -e "$path" ]]; then
            chown -R "$owner" "$path"
            chmod -R "$permissions" "$path"
        fi
    fi
}

create_system_user() {
    local username="$1"
    local home_dir="$2"
    local shell="${3:-/bin/bash}"
    local create_home="${4:-true}"
    
    debug "Creating system user: $username"
    
    if id "$username" &>/dev/null; then
        debug "User $username already exists"
        return 0
    fi
    
    if [[ "$DRY_RUN" == false ]]; then
        local useradd_opts=("-r" "-s" "$shell")
        
        if [[ "$create_home" == true ]]; then
            useradd_opts+=("-m" "-d" "$home_dir")
        else
            useradd_opts+=("-M")
        fi
        
        useradd "${useradd_opts[@]}" "$username"
        
        if [[ "$create_home" == true && ! -d "$home_dir" ]]; then
            mkdir -p "$home_dir"
            chown "$username:$username" "$home_dir"
        fi
    fi
}

# Docker utility functions
extract_from_docker_image() {
    local image_name="$1"
    local source_path="$2"
    local dest_path="$3"
    
    debug "Extracting $source_path from $image_name to $dest_path"
    
    if [[ "$DRY_RUN" == false ]]; then
        # Check if Docker is running
        if ! docker info &>/dev/null; then
            warn "Docker is not running. Attempting to start..."
            systemctl start docker || service docker start || {
                error "Failed to start Docker service"
                return 1
            }
            sleep 2
        fi
        # Create container with dummy command since we only need to extract files
        local container_id
        container_id=$(docker create "$image_name" /bin/true)
        if [[ -z "$container_id" ]]; then
            error "Failed to create container from image: $image_name"
            return 1
        fi
        
        # Extract the file/directory
        if ! docker cp "$container_id:$source_path" "$dest_path"; then
            error "Failed to extract $source_path from container"
            docker rm "$container_id" 2>/dev/null || true
            return 1
        fi
        
        # Clean up container
        docker rm "$container_id" || warn "Failed to remove container $container_id"
    fi
}

pull_docker_image() {
    local image_name="$1"
    
    debug "Pulling Docker image: $image_name"
    
    if [[ "$DRY_RUN" == false ]]; then
        # Check if Docker is running
        if ! docker info &>/dev/null; then
            warn "Docker is not running. Attempting to start..."
            systemctl start docker || service docker start || {
                error "Failed to start Docker service"
                return 1
            }
            sleep 2
        fi
        docker pull "$image_name"
    fi
}

info "Starting Selkies Framework with Xvfb installation (Phase 3)"
info "This will install Selkies GStreamer remote desktop framework"

# =============================================================================
# DEVELOPMENT DEPENDENCIES
# =============================================================================

install_dev_dependencies() {
    info "Installing development dependencies..."
    
    update_package_cache
    
    # Install temporary development dependencies
    info "Installing temporary development dependencies..."
    install_packages \
        python3-dev \
        python3-av \
        cython3 \
        pkg-config \
        ffmpeg \
        libavcodec-dev \
        libavdevice-dev \
        libavfilter-dev \
        libavformat-dev \
        libavutil-dev \
        libswresample-dev \
        libswscale-dev
}

# =============================================================================
# REPOSITORY SETUP
# =============================================================================

setup_repositories() {
    info "Setting up Docker and Node.js repositories..."
    local ubuntu_codename
    ubuntu_codename="$(
        . /etc/os-release
        printf '%s' "${VERSION_CODENAME:-noble}"
    )"
    
    # Docker repository
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | tee /usr/share/keyrings/docker.asc >/dev/null
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${ubuntu_codename} stable" > /etc/apt/sources.list.d/docker.list
    
    # Node.js repository
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
    
    update_package_cache
}

# =============================================================================
# MAIN PACKAGE INSTALLATION
# =============================================================================

install_main_packages() {
    info "Installing main packages in groups for better organization..."
    
    # Group 1: Core system packages
    info "Installing core system packages..."
    install_packages \
        ca-certificates \
        console-data \
        dbus-x11 \
        dbus-user-session \
        file \
        kbd \
        locales-all \
        openssh-client \
        openssl \
        pciutils \
        procps \
        software-properties-common \
        ssl-cert \
        sudo \
        systemd-container \
        tar \
        util-linux \
        zlib1g
    
    # Group 2: Docker packages
    info "Installing Docker packages..."
    install_packages \
        containerd.io \
        docker-buildx-plugin \
        docker-ce \
        docker-ce-cli \
        docker-compose-plugin \
        fuse-overlayfs
    
    # Group 3: Development tools
    info "Installing development tools..."
    install_packages \
        cmake \
        g++ \
        gcc \
        git \
        make \
        nodejs \
        python3 \
        python3-venv
    
    # Group 4: Basic X11 libraries
    info "Installing basic X11 libraries..."
    install_packages \
        libatk1.0-0 \
        libatk-bridge2.0-0 \
        libev4 \
        libfontenc1 \
        libfreetype6 \
        libgbm1 \
        libgcrypt20 \
        libgirepository-1.0-1 \
        libgnutls30 \
        libgtk-3-0t64 \
        libjpeg-turbo8 \
        libnss3 \
        libnotify-bin \
        libopus0 \
        libp11-kit0 \
        libpam0g \
        libtasn1-6 \
        libvulkan1 \
        libx11-6 \
        libxau6 \
        libxcb1 \
        libxcb-icccm4 \
        libxcb-image0 \
        libxcb-keysyms1 \
        libxcb-render-util0 \
        libxcursor1 \
        libxdmcp6 \
        libxext6 \
        libxfconf-0-3 \
        libxfixes3 \
        libxfont2 \
        libxinerama1 \
        libxkbcommon-x11-0 \
        libxshmfence1 \
        libxtst6

    local x264_package
    x264_package=$(apt-cache search '^libx264-[0-9]+' | awk 'NR == 1 {print $1}')
    if [[ -n "$x264_package" ]]; then
        install_packages "$x264_package"
    else
        warn "No libx264 runtime package found; continuing without explicit libx264 install"
    fi
    
    # Group 5: Mesa and graphics drivers
    info "Installing Mesa and graphics drivers..."
    install_packages \
        intel-media-va-driver \
        libgl1-mesa-dri \
        libglu1-mesa \
        mesa-libgallium \
        mesa-va-drivers \
        mesa-vulkan-drivers \
        vulkan-tools
    
    # Group 6: Fonts and themes
    info "Installing fonts and themes..."
    install_packages \
        breeze-cursor-theme \
        fonts-noto-cjk \
        fonts-noto-color-emoji \
        fonts-noto-core \
        xfonts-base
    
    # Group 7: Desktop environment and utilities
    info "Installing desktop environment and utilities..."
    install_packages \
        dunst \
        flatpak \
        ibus \
        libnginx-mod-http-fancyindex \
        nginx \
        openbox \
        pavucontrol \
        pulseaudio \
        pulseaudio-utils \
        alsa-base \
        alsa-utils \
        libasound2t64 \
        libasound2-plugins \
        snapd \
        stterm \
        xdg-utils \
        xdotool \
        xfconf \
        xsettingsd
    
    # Group 8: X11 utilities and tools
    info "Installing X11 utilities and tools..."
    install_packages \
        x11-apps \
        x11-common \
        x11-utils \
        x11-xkb-utils \
        x11-xserver-utils \
        xauth \
        xclip \
        xcvt \
        xkb-data \
        xsel \
        xterm \
        xutils \
        xvfb
    
    # Group 9: X server and drivers
    info "Installing X server and graphics drivers..."
    install_packages \
        xserver-common \
        xserver-xorg-core \
        xserver-xorg-video-amdgpu \
        xserver-xorg-video-ati \
        xserver-xorg-video-intel \
        xserver-xorg-video-nouveau \
        xserver-xorg-video-qxl
    
    info "✓ Main packages installed successfully"
}

# =============================================================================
# DOCKER IMAGE EXTRACTIONS
# =============================================================================

extract_docker_images() {
    info "Extracting pre-built components from Docker images..."
    
    # Extract Xvfb binary from xvfb image
    info "Extracting custom Xvfb binary..."
    pull_docker_image "lscr.io/linuxserver/xvfb:ubuntunoble"
    
    # Create temporary directory for extraction
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Extract Xvfb binary
    extract_from_docker_image "lscr.io/linuxserver/xvfb:ubuntunoble" "/usr/bin/Xvfb" "$temp_dir/Xvfb"
    
    # Copy to rootfs
    mkdir -p "$SCRIPT_DIR/rootfs/usr/bin"
    cp "$temp_dir/Xvfb" "$SCRIPT_DIR/rootfs/usr/bin/Xvfb"
    chmod +x "$SCRIPT_DIR/rootfs/usr/bin/Xvfb"
    
    # Extract Selkies frontend from Alpine image
    info "Extracting pre-built Selkies frontend..."
    pull_docker_image "ghcr.io/linuxserver/baseimage-alpine:3.22"
    
    # This will be extracted during the frontend build process in the multi-stage build
    # For now, we'll handle this in the source build section
    
    # Cleanup
    rm -rf "$temp_dir"
    
    info "✓ Docker image extraction completed"
}

# =============================================================================
# SOURCE BUILDS
# =============================================================================

build_selkies_from_source() {
    info "Building Selkies from source..."
    
    # Download and build selkies
    local temp_dir
    temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    curl -o selkies.tar.gz -L "https://github.com/selkies-project/selkies/archive/4561221b16593d463df7ccb7ccb2a36dcea6ab31.tar.gz"
    tar xf selkies.tar.gz
    cd selkies-*
    
    # Use Ubuntu-provided Python packages where newer distro libraries have
    # outpaced upstream Selkies' pinned Python dependencies.
    sed -i '/cryptography/d' pyproject.toml
    sed -i '/^[[:space:]]*"av[<>=]/d' pyproject.toml

    # Carry small audio fixes on top of the pinned Selkies revision:
    # - Set pcmflux latency so PulseAudio does not negotiate multi-second
    #   capture buffers.
    # - Use a remap source for browser microphone forwarding. PipeWire's
    #   module-virtual-source exposes output.<name>, while Selkies expects the
    #   exact source name it requests.
    python3 - <<'PY'
from pathlib import Path

path = Path("src/selkies/selkies.py")
text = path.read_text()

latency_old = "            settings.use_silence_gate = False\n            self.pcmflux_settings = settings\n"
latency_new = "            settings.use_silence_gate = False\n            settings.latency_ms = 10\n            self.pcmflux_settings = settings\n"
if latency_new not in text:
    if latency_old not in text:
        raise SystemExit("Could not locate pcmflux settings block to patch")
    text = text.replace(latency_old, latency_new, 1)

mic_args_old = '                                    load_args = f"source_name={virtual_source_name} master={master_monitor}"\n'
mic_args_new = '                                    load_args = f"source_name={virtual_source_name} master={master_monitor} source_properties=device.description={virtual_source_name}"\n'
if mic_args_new not in text:
    if mic_args_old not in text:
        raise SystemExit("Could not locate microphone source args to patch")
    text = text.replace(mic_args_old, mic_args_new, 1)

mic_module_old = '                                        "module-virtual-source", load_args\n'
mic_module_new = '                                        "module-remap-source", load_args\n'
if mic_module_new not in text:
    if mic_module_old not in text:
        raise SystemExit("Could not locate microphone source module to patch")
    text = text.replace(mic_module_old, mic_module_new, 1)

default_source_old = """                                if mic_setup_done:
                                    current_source_list = (
                                        pulse.source_list()
                                    )
                                    # Mic is automatically set to the source for recording (pcmflux) and input
"""
default_source_new = """                                if mic_setup_done:
                                    current_source_list = (
                                        pulse.source_list()
                                    )
                                    virtual_source_info = None
                                    for source_obj_default in current_source_list:
                                        if source_obj_default.name == virtual_source_name:
                                            virtual_source_info = source_obj_default
                                            break
                                    if virtual_source_info:
                                        try:
                                            if os.system(f"pactl set-default-source {virtual_source_name}") == 0:
                                                data_logger.info(f"Set default PulseAudio source to '{virtual_source_name}'.")
                                            else:
                                                data_logger.warning(f"pactl failed to set default PulseAudio source to '{virtual_source_name}'.")
                                        except Exception as e_default_source:
                                            data_logger.warning(f"Could not set default PulseAudio source to '{virtual_source_name}': {e_default_source}")
                                    # Mic is automatically set to the source for recording (pcmflux) and input
"""
if default_source_new not in text:
    if default_source_old not in text:
        raise SystemExit("Could not locate microphone default source block to patch")
    text = text.replace(default_source_old, default_source_new, 1)

shared_viewers_registration_old = """        data_logger.info(f"Data WebSocket connected from {raddr}")
        self.clients.add(websocket)
        self.data_ws = (
            websocket  # self.data_ws is specific to this handler instance/connection
        )
        self.jpeg_capture_loop = self.jpeg_capture_loop or asyncio.get_running_loop()
        self.client_settings_received = asyncio.Event()
        initial_settings_processed = False
        self._sent_frame_timestamps.clear()
        self._rtt_samples.clear()
        self._smoothed_rtt_ms = 0.0
"""
shared_viewers_registration_new = """        data_logger.info(f"Data WebSocket connected from {raddr}")
        previous_primary = self.data_ws
        self.data_ws = websocket
        if previous_primary is None:
            data_logger.info(f"Client {raddr} assigned as primary Selkies controller.")
        else:
            data_logger.info(
                f"Client {raddr} took over as primary Selkies controller; previous primary was {previous_primary.remote_address}."
            )
        self.clients.add(websocket)

        def is_primary_client():
            return self.data_ws is websocket

        self.jpeg_capture_loop = self.jpeg_capture_loop or asyncio.get_running_loop()
        if is_primary_client():
            self.client_settings_received = asyncio.Event()
            initial_settings_processed = False
            self._sent_frame_timestamps.clear()
            self._rtt_samples.clear()
            self._smoothed_rtt_ms = 0.0
        else:
            initial_settings_processed = True
            if self.client_settings_received is None:
                self.client_settings_received = asyncio.Event()
                self.client_settings_received.set()
"""
if shared_viewers_registration_new not in text:
    if shared_viewers_registration_old not in text:
        raise SystemExit("Could not locate WebSocket client registration block to patch")
    text = text.replace(shared_viewers_registration_old, shared_viewers_registration_new, 1)

primary_state_reset_old = """        self._initial_target_bitrate_kbps = self.app.video_bitrate
        self._current_target_bitrate_kbps = self._initial_target_bitrate_kbps
        self._last_adjustment_time = self._last_time_client_ok = time.monotonic()
        self._active_pipeline_last_sent_frame_id = 0
        self._client_acknowledged_frame_id = -1
        self._last_client_acknowledged_frame_id_update_time = time.monotonic()
        self._previous_ack_id_for_stall_check = -1
        self._previous_sent_id_for_stall_check = -1
        self._last_client_stable_report_time = time.monotonic()
        self._initial_x264_crf = self.cli_args.h264_crf
        self.h264_crf = self._initial_x264_crf
        self.h264_fullcolor = self._initial_h264_fullcolor
        self.h264_streaming_mode = self._initial_h264_streaming_mode
        self.jpeg_quality = self._initial_jpeg_quality
        self.paint_over_jpeg_quality = self._initial_paint_over_jpeg_quality
        self.use_cpu = self._initial_use_cpu
        self.h264_paintover_crf = self._initial_h264_paintover_crf
        self.h264_paintover_burst_frames = self._initial_h264_paintover_burst_frames
        self.use_paint_over_quality = self._initial_use_paint_over_quality

        self._backpressure_send_frames_enabled = True
"""
primary_state_reset_new = """        if is_primary_client():
            self._initial_target_bitrate_kbps = self.app.video_bitrate
            self._current_target_bitrate_kbps = self._initial_target_bitrate_kbps
            self._last_adjustment_time = self._last_time_client_ok = time.monotonic()
            self._active_pipeline_last_sent_frame_id = 0
            self._client_acknowledged_frame_id = -1
            self._last_client_acknowledged_frame_id_update_time = time.monotonic()
            self._previous_ack_id_for_stall_check = -1
            self._previous_sent_id_for_stall_check = -1
            self._last_client_stable_report_time = time.monotonic()
            self._initial_x264_crf = self.cli_args.h264_crf
            self.h264_crf = self._initial_x264_crf
            self.h264_fullcolor = self._initial_h264_fullcolor
            self.h264_streaming_mode = self._initial_h264_streaming_mode
            self.jpeg_quality = self._initial_jpeg_quality
            self.paint_over_jpeg_quality = self._initial_paint_over_jpeg_quality
            self.use_cpu = self._initial_use_cpu
            self.h264_paintover_crf = self._initial_h264_paintover_crf
            self.h264_paintover_burst_frames = self._initial_h264_paintover_burst_frames
            self.use_paint_over_quality = self._initial_use_paint_over_quality

            self._backpressure_send_frames_enabled = True
"""
if primary_state_reset_new not in text:
    if primary_state_reset_old not in text:
        raise SystemExit("Could not locate primary state reset block to patch")
    text = text.replace(primary_state_reset_old, primary_state_reset_new, 1)

settings_resize_old = """        if (target_w_for_app != old_display_width or target_h_for_app != old_display_height):
            self.app.display_width = target_w_for_app
            self.app.display_height = target_h_for_app
            effective_resize_enabled = ENABLE_RESIZE and settings.get("resizeRemote", True)
            if effective_resize_enabled:
                await on_resize_handler(f"{self.app.display_width}x{self.app.display_height}", self.app, self)
"""
settings_resize_new = """        if (target_w_for_app != old_display_width or target_h_for_app != old_display_height):
            encoder_before_settings_resize = str(self.app.encoder)
            if self.is_jpeg_capturing and encoder_before_settings_resize == "jpeg":
                data_logger.info("Settings resize: stopping JPEG pipeline before applying new resolution.")
                await self._stop_jpeg_pipeline()
            elif self.is_x264_striped_capturing and (encoder_before_settings_resize in PIXELFLUX_VIDEO_ENCODERS and encoder_before_settings_resize != "jpeg"):
                data_logger.info(f"Settings resize: stopping {encoder_before_settings_resize} pipeline before applying new resolution.")
                await self._stop_x264_striped_pipeline()
            self.app.display_width = target_w_for_app
            self.app.display_height = target_h_for_app
            effective_resize_enabled = ENABLE_RESIZE and settings.get("resizeRemote", True)
            if effective_resize_enabled:
                await on_resize_handler(f"{self.app.display_width}x{self.app.display_height}", self.app, self)
"""
if settings_resize_new not in text:
    if settings_resize_old not in text:
        raise SystemExit("Could not locate settings resize block to patch")
    text = text.replace(settings_resize_old, settings_resize_new, 1)

pulse_setup_old = """            if PULSEAUDIO_AVAILABLE:
"""
pulse_setup_new = """            if is_primary_client() and PULSEAUDIO_AVAILABLE:
"""
if pulse_setup_new not in text:
    if pulse_setup_old not in text:
        raise SystemExit("Could not locate PulseAudio setup block to patch")
    text = text.replace(pulse_setup_old, pulse_setup_new, 1)

secondary_binary_guard_old = """                if isinstance(message, bytes):
                    msg_type, payload = message[0], message[1:]
                    if msg_type == 0x01:  # File data
"""
secondary_binary_guard_new = """                if isinstance(message, bytes):
                    msg_type, payload = message[0], message[1:]
                    if not is_primary_client():
                        continue
                    if msg_type == 0x01:  # File data
"""
if secondary_binary_guard_new not in text:
    if secondary_binary_guard_old not in text:
        raise SystemExit("Could not locate binary message handler block to patch")
    text = text.replace(secondary_binary_guard_old, secondary_binary_guard_new, 1)

secondary_string_guard_old = """                elif isinstance(message, str):
                    if message.startswith("FILE_UPLOAD_START:"):
"""
secondary_string_guard_new = """                elif isinstance(message, str):
                    if not is_primary_client():
                        if message.startswith("SETTINGS,"):
                            data_logger.info(f"Ignoring SETTINGS from secondary viewer {raddr}; keeping primary stream settings.")
                            try:
                                await self.broadcast_stream_resolution()
                                if self.is_jpeg_capturing or self.is_x264_striped_capturing:
                                    await websocket.send("VIDEO_STARTED")
                                if self.is_pcmflux_capturing:
                                    await websocket.send("AUDIO_STARTED")
                            except websockets.exceptions.ConnectionClosed:
                                raise
                            except Exception as e_viewer_notify:
                                data_logger.warning(f"Failed to notify secondary viewer {raddr} of active stream state: {e_viewer_notify}")
                        elif message == "START_VIDEO":
                            if self.is_jpeg_capturing or self.is_x264_striped_capturing:
                                await websocket.send("VIDEO_STARTED")
                        elif message == "START_AUDIO":
                            if self.is_pcmflux_capturing:
                                await websocket.send("AUDIO_STARTED")
                        elif message.startswith("CLIENT_FRAME_ACK"):
                            pass
                        else:
                            data_logger.debug(f"Ignoring secondary viewer message from {raddr}: {message[:80]}")
                        continue

                    if message.startswith("FILE_UPLOAD_START:"):
"""
if secondary_string_guard_new not in text:
    if secondary_string_guard_old not in text:
        raise SystemExit("Could not locate string message handler block to patch")
    text = text.replace(secondary_string_guard_old, secondary_string_guard_new, 1)

primary_promotion_old = """            self.clients.discard(websocket)
            if self.data_ws is websocket:
                self.data_ws = None
"""
primary_promotion_new = """            self.clients.discard(websocket)
            if self.data_ws is websocket:
                self.data_ws = next(iter(self.clients), None)
                if self.data_ws is not None:
                    data_logger.info(f"Promoted remaining client {self.data_ws.remote_address} to primary Selkies controller.")
"""
if primary_promotion_new not in text:
    if primary_promotion_old not in text:
        raise SystemExit("Could not locate primary promotion cleanup block to patch")
    text = text.replace(primary_promotion_old, primary_promotion_new, 1)

text = text.replace(
    "Loaded module-virtual-source with index",
    "Loaded module-remap-source with index",
    1,
)
path.write_text(text)
PY
    
    # Create virtual environment and install selkies
    python3 -m venv --system-site-packages /lsiopy
    /lsiopy/bin/pip install .
    /lsiopy/bin/pip install setuptools
    
    # Make selkies command available globally
    ln -sf /lsiopy/bin/selkies /usr/local/bin/selkies
    
    # Build joystick interposer
    info "Building joystick interposer..."
    cd addons/js-interposer
    gcc -shared -fPIC -ldl -o selkies_joystick_interposer.so joystick_interposer.c
    
    # Copy to rootfs
    mkdir -p "$SCRIPT_DIR/rootfs/usr/lib"
    cp selkies_joystick_interposer.so "$SCRIPT_DIR/rootfs/usr/lib/selkies_joystick_interposer.so"
    
    # Build fake udev
    info "Building fake udev library..."
    cd ../fake-udev
    make
    
    # Copy to rootfs
    mkdir -p "$SCRIPT_DIR/rootfs/opt/lib"
    cp libudev.so.1.0.0-fake "$SCRIPT_DIR/rootfs/opt/lib/libudev.so.1.0.0-fake"
    
    # Frontend build (simulating the multi-stage build)
    info "Building frontend components..."
    cd ../gst-web-core
    npm install
    npm run build
    
    # Copy selkies-core.js to selkies-dashboard src before building
    cp dist/selkies-core.js ../selkies-dashboard/src/
    
    cd ../selkies-dashboard
    npm install
    npm run build

    local dashboard_bundle
    dashboard_bundle=$(ls dist/assets/index-*.js 2>/dev/null | head -1 || true)
    if [[ -n "$dashboard_bundle" ]]; then
        # Keep scaling options available, but default first load to 100%/96 DPI
        # instead of auto-selecting a HiDPI value from browser devicePixelRatio.
        python3 - "$dashboard_bundle" <<'PY'
import pathlib
import re
import sys

bundle = pathlib.Path(sys.argv[1])
content = bundle.read_text(encoding="utf-8")

content = content.replace("(window.devicePixelRatio||1)*96", "96")
content = content.replace('ga("useCssScaling",!1)', '!0')
content = content.replace(
    'const _=window.devicePixelRatio||1,T=Math.round(_*4)*24,z=[120,144,168,192,216,240,288];ba=_>1&&z.includes(T)?T:96',
    'ba=96',
)
content = re.sub(
    r'if\(_i\("scaling_dpi",null\)===null\)\{const _=window\.devicePixelRatio\|\|1,T=Math\.round\(_\*4\)\*24,z=\[120,144,168,192,216,240,288\];ba=_>1&&z\.includes\(T\)\?T:96\}else ba=Pt\("scaling_dpi",96\);',
    'if(_i("scaling_dpi",null)===null){ba=96}else ba=Pt("scaling_dpi",96);',
    content,
)
content, _ = re.subn(
    r'([a-zA-Z_$][a-zA-Z0-9_$]*)\("scaling_dpi",null\)===null\)\{const _=window\.devicePixelRatio\|\|1,w=Math\.round\(_\*4\)\*24,R=\[120,144,168,192,216,240,288\];([a-zA-Z_$][a-zA-Z0-9_$]*)=_>1&&R\.includes\(w\)\?w:96\}else \2=([a-zA-Z_$][a-zA-Z0-9_$]*)\("scaling_dpi",96\)',
    r'\1("scaling_dpi",null)===null){\2=96}else \2=\3("scaling_dpi",96)',
    content,
)
content, _ = re.subn(
    r'([a-zA-Z_$][a-zA-Z0-9_$]*)=([a-zA-Z_$][a-zA-Z0-9_$]*)\("useCssScaling",!1\)',
    r'\1=!0',
    content,
)

cache_busted_bundle = bundle.with_name(f"{bundle.stem}-appbox.js")
cache_busted_bundle.write_text(content, encoding="utf-8")
index_html = pathlib.Path("dist/index.html")
if index_html.exists():
    index_content = index_html.read_text(encoding="utf-8")
    index_html.write_text(index_content.replace(bundle.name, cache_busted_bundle.name), encoding="utf-8")
PY
        info "Applied dashboard scaling default hotfix (96 DPI and CSS scaling first load)"
    else
        warn "Dashboard bundle not found; skipping scaling default hotfix"
    fi
    
    # Create frontend directory structure
    mkdir -p dist/src dist/nginx
    cp ../universal-touch-gamepad/universalTouchGamepad.js dist/src/
    cp ../gst-web-core/nginx/* dist/nginx/
    cp -r ../gst-web-core/dist/jsdb dist/
    
    # Copy frontend to rootfs
    mkdir -p "$SCRIPT_DIR/rootfs/usr/share/selkies/www"
    cp -ar dist/* "$SCRIPT_DIR/rootfs/usr/share/selkies/www/"
    
    # Cleanup
    cd /
    rm -rf "$temp_dir"
    
    info "✓ Source builds completed successfully"
}

# =============================================================================
# ICONS AND ASSETS
# =============================================================================

setup_icons() {
    info "Setting up icons and assets..."
    
    # Download selkies icons
    mkdir -p "$SCRIPT_DIR/rootfs/usr/share/selkies/www"
    curl -o "$SCRIPT_DIR/rootfs/usr/share/selkies/www/icon.png" \
        "https://raw.githubusercontent.com/linuxserver/docker-templates/master/linuxserver.io/img/selkies-logo.png"
    curl -o "$SCRIPT_DIR/rootfs/usr/share/selkies/www/favicon.ico" \
        "https://raw.githubusercontent.com/linuxserver/docker-templates/refs/heads/master/linuxserver.io/img/selkies-icon.ico"
    
    info "✓ Icons and assets setup completed"
}

# =============================================================================
# OPENBOX CONFIGURATION
# =============================================================================

configure_openbox() {
    info "Configuring OpenBox window manager..."
    
    # Apply OpenBox tweaks from Dockerfile
    sed -i \
        -e 's/NLIMC/NLMC/g' \
        -e '/debian-menu/d' \
        -e 's|</applications>|  <application class="*"><maximized>yes</maximized></application>\n</applications>|' \
        -e 's|</keyboard>|  <keybind key="C-S-d"><action name="ToggleDecorations"/></keybind>\n</keyboard>|' \
        -e 's|<number>4</number>|<number>1</number>|' \
        /etc/xdg/openbox/rc.xml
    
    info "✓ OpenBox configuration completed"
}

# =============================================================================
# USER SETUP
# =============================================================================

setup_users() {
    info "Setting up users and permissions..."
    
    # Configure sudo for appbox user
    sed -e 's/%sudo	ALL=(ALL:ALL) ALL/%sudo ALL=(ALL:ALL) NOPASSWD: ALL/g' -i /etc/sudoers
    
    # Create appbox user if it doesn't exist
    if ! id appbox &>/dev/null; then
        useradd -m -s /bin/bash appbox
    fi
    
    # Set groups, don't set password
    usermod -s /bin/bash appbox
    usermod -aG sudo appbox
    
    # Docker-in-Docker support
    useradd -U dockremap || true
    usermod -G dockremap dockremap
    echo 'dockremap:165536:65536' >> /etc/subuid
    echo 'dockremap:165536:65536' >> /etc/subgid
    
    # Add appbox to docker group
    usermod -aG docker appbox
    
    # Enable systemd lingering for appbox user (allows user systemd to work)
    info "Enabling systemd lingering for appbox user..."
    loginctl enable-linger appbox
    
    # Ensure user systemd directories exist
    mkdir -p /home/appbox/.config/systemd/user
    mkdir -p /home/appbox/.bashrc.d
    chown -R appbox:appbox /home/appbox/.config
    
    # Copy user systemd bashrc setup if it exists
    if [[ -f /etc/skel/.bashrc.d/user-systemd.bashrc ]]; then
        cp /etc/skel/.bashrc.d/user-systemd.bashrc /home/appbox/.bashrc.d/
        chown appbox:appbox /home/appbox/.bashrc.d/user-systemd.bashrc
        
        # Ensure it's sourced from .bashrc
        if ! grep -q "source.*bashrc.d" /home/appbox/.bashrc 2>/dev/null; then
            echo '' >> /home/appbox/.bashrc
            echo '# Source additional bashrc files' >> /home/appbox/.bashrc
            echo 'for f in ~/.bashrc.d/*.bashrc; do' >> /home/appbox/.bashrc
            echo '    [ -f "$f" ] && source "$f"' >> /home/appbox/.bashrc
            echo 'done' >> /home/appbox/.bashrc
            chown appbox:appbox /home/appbox/.bashrc
        fi
    fi
    
    # Enable systemd-logind for proper user sessions
    systemctl enable systemd-logind
    
    # Set up Flatpak for appbox user
    info "Setting up Flatpak for appbox user..."
    mkdir -p /var/lib/flatpak
    mkdir -p /home/appbox/.local/share/flatpak
    chown -R appbox:appbox /home/appbox/.local/share/flatpak
    
    # Add Flathub repository system-wide
    if command -v flatpak >/dev/null 2>&1; then
        flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
        info "Flathub repository added"
    fi
    
    # Set up Snap and install snap-store
    info "Setting up Snap and installing snap-store..."
    if command -v snap >/dev/null 2>&1; then
        # Enable snapd service
        systemctl enable snapd
        systemctl start snapd
        
        # Wait for snapd to be ready
        sleep 3
        
        # Install snap-store
        snap install snap-store 2>/dev/null || true
        
        # Create necessary directories for appbox user
        mkdir -p /home/appbox/snap/snap-store/common/.cache
        chown -R appbox:appbox /home/appbox/snap
        
        # Connect common snap interfaces for audio support
        info "Connecting snap audio interfaces..."
        snap connect snap-store:audio-playback :audio-playback 2>/dev/null || true
        snap connect snap-store:pulseaudio :pulseaudio 2>/dev/null || true
        
        # Pre-connect interfaces for common snaps that might be installed later
        info "Setting up auto-connections for audio interfaces..."
        # This ensures future snap installs will have audio working
        
        # Ensure snap desktop integration
        # Snap applications create their own desktop files in /var/lib/snapd/desktop/applications/
        # and symlink them to /snap/bin/ - we need to ensure these are accessible
        
        # Update desktop database to include snap applications
        update-desktop-database /usr/share/applications/ 2>/dev/null || true
        
        info "snap-store installed and configured"
    fi
    
    # Disable user PulseAudio services since we use system services
    info "Disabling user PulseAudio services (using system services instead)..."
    sudo -u appbox XDG_RUNTIME_DIR="/run/user/$(id -u appbox)" systemctl --user disable pulseaudio.service pulseaudio.socket 2>/dev/null || true
    sudo -u appbox XDG_RUNTIME_DIR="/run/user/$(id -u appbox)" systemctl --user mask pulseaudio.service pulseaudio.socket 2>/dev/null || true
    
    info "✓ User setup completed"
}

# =============================================================================
# PROOT-APPS SETUP
# =============================================================================

setup_proot_apps() {
    info "Setting up proot-apps..."
    
    mkdir -p /proot-apps/
    local papps_release
    papps_release=$(curl -sX GET "https://api.github.com/repos/linuxserver/proot-apps/releases/latest" \
        | awk '/tag_name/{print $4;exit}' FS='[""]')
    
    curl -L "https://github.com/linuxserver/proot-apps/releases/download/${papps_release}/proot-apps-x86_64.tar.gz" \
        | tar -xzf - -C /proot-apps/
    
    echo "${papps_release}" > /proot-apps/pversion
    
    info "✓ proot-apps setup completed"
}

# =============================================================================
# DOCKER-IN-DOCKER SETUP
# =============================================================================

setup_docker_in_docker() {
    info "Setting up Docker-in-Docker support..."
    
    # Download dind script
    curl -o /usr/local/bin/dind -L "https://raw.githubusercontent.com/moby/moby/master/hack/dind"
    chmod +x /usr/local/bin/dind
    
    # Configure only host lookup while preserving passwd/group/systemd entries.
    if grep -q '^hosts:' /etc/nsswitch.conf; then
        sed -i 's/^hosts:.*/hosts: files dns/' /etc/nsswitch.conf
    else
        printf '%s\n' 'hosts: files dns' >> /etc/nsswitch.conf
    fi
    
    info "✓ Docker-in-Docker setup completed"
}

# =============================================================================
# LOCALE SETUP
# =============================================================================

setup_locales() {
    info "Setting up locales..."
    
    # Enable locales (only if excludes file exists - LinuxServer.io specific)
    if [[ -f /etc/dpkg/dpkg.cfg.d/excludes ]]; then
        debug "Found dpkg excludes file, enabling locales"
        sed -i '/locale/d' /etc/dpkg/dpkg.cfg.d/excludes
    else
        debug "No dpkg excludes file found, skipping locale exclusion removal"
    fi
    
    # Install locales from lang-stash
    debug "Installing locales from lang-stash..."
    for locale in $(curl -sL https://raw.githubusercontent.com/thelamer/lang-stash/master/langs 2>/dev/null || echo ""); do
        if [[ -n "$locale" ]]; then
            debug "Installing locale: $locale"
            localedef -i "$locale" -f UTF-8 "$locale".UTF-8 || warn "Failed to install locale: $locale"
        fi
    done
    
    # Ensure basic locales are available
    if ! locale -a | grep -q "en_US.utf8"; then
        debug "Installing basic en_US.UTF-8 locale"
        localedef -i en_US -f UTF-8 en_US.UTF-8 || warn "Failed to install en_US.UTF-8 locale"
    fi
    
    info "✓ Locale setup completed"
}

# =============================================================================
# THEME SETUP
# =============================================================================

setup_theme() {
    info "Setting up themes..."
    
    # Download and install theme
    curl -s https://raw.githubusercontent.com/thelamer/lang-stash/master/theme.tar.gz \
        | tar xzvf - -C /usr/share/themes/Clearlooks/openbox-3/
    
    info "✓ Theme setup completed"
}

# =============================================================================
# CONFIGURATION FILES
# =============================================================================

setup_configuration_files() {
    info "Setting up configuration files..."
    
    # Configuration files are already in rootfs structure
    # Just verify they exist
    if [[ ! -f "$SCRIPT_DIR/rootfs/defaults/autostart" ]]; then
        error "Missing autostart file in rootfs"
        return 1
    fi
    
    if [[ ! -f "$SCRIPT_DIR/rootfs/defaults/menu.xml" ]]; then
        error "Missing menu.xml file in rootfs"
        return 1
    fi
    
    if [[ ! -f "$SCRIPT_DIR/rootfs/defaults/startwm.sh" ]]; then
        error "Missing startwm.sh file in rootfs"
        return 1
    fi
    
    if [[ ! -f "$SCRIPT_DIR/rootfs/defaults/default.conf" ]]; then
        error "Missing default.conf file in rootfs"
        return 1
    fi
    
    info "✓ Configuration files verified in rootfs"
}

# =============================================================================
# SYSTEMD SERVICES
# =============================================================================

create_systemd_services() {
    info "Verifying systemd services in rootfs..."
    
    # Verify all systemd service files exist in rootfs
    local services=("selkies-setup.service" "xvfb.service" "selkies-pulseaudio.service" "selkies-nginx.service" "selkies.service" "selkies-desktop.service")
    
    for service in "${services[@]}"; do
        if [[ ! -f "$SCRIPT_DIR/rootfs/etc/systemd/system/$service" ]]; then
            error "Missing systemd service file: $service"
            return 1
        fi
    done
    
    info "✓ All systemd service files verified in rootfs"
}

# =============================================================================
# SYSTEMD SCRIPTS
# =============================================================================

create_systemd_scripts() {
    info "Verifying systemd helper scripts in rootfs..."
    
    # Verify all helper scripts exist in rootfs
    local scripts=("init-nginx.sh" "init-selkies-config.sh" "init-video.sh" "svc-de.sh" "setup-user-systemd.sh")
    
    for script in "${scripts[@]}"; do
        if [[ ! -f "$SCRIPT_DIR/rootfs/etc/selkies/$script" ]]; then
            error "Missing systemd helper script: $script"
            return 1
        fi
        if [[ ! -x "$SCRIPT_DIR/rootfs/etc/selkies/$script" ]]; then
            error "Helper script not executable: $script"
            return 1
        fi
    done
    
    info "✓ All systemd helper scripts verified in rootfs"
}

# =============================================================================
# ENVIRONMENT SETUP
# =============================================================================

setup_environment() {
    info "Verifying environment configuration..."
    
    # Verify environment file exists in rootfs
    if [[ ! -f "$SCRIPT_DIR/rootfs/etc/environment" ]]; then
        error "Missing environment file in rootfs"
        return 1
    fi
    
    # Verify /config directory exists in rootfs
    if [[ ! -d "$SCRIPT_DIR/rootfs/config" ]]; then
        mkdir -p "$SCRIPT_DIR/rootfs/config"
        info "Created /config directory in rootfs"
    fi
    
    info "✓ Environment configuration verified"
}

# =============================================================================
# CLEANUP
# =============================================================================

cleanup_installation() {
    info "Cleaning up installation..."
    
    # Remove development dependencies
    apt-get purge -y --autoremove \
        python3-dev || true
    
    # Clean package cache
    apt-get autoclean
    
    # Remove temporary files
    rm -rf \
        /config/.cache \
        /config/.npm \
        /var/lib/apt/lists/* \
        /var/tmp/* \
        /tmp/*
    
    info "✓ Cleanup completed"
}

# =============================================================================
# MAIN INSTALLATION PROCESS
# =============================================================================

main() {
    info "Starting Selkies installation process..."
    
    # Update TODO status
    # Phase 3 tasks
    install_dev_dependencies
    setup_repositories
    install_main_packages
    extract_docker_images
    build_selkies_from_source
    setup_icons
    configure_openbox
    setup_users
    setup_proot_apps
    setup_docker_in_docker
    setup_locales
    setup_theme
    setup_configuration_files
    create_systemd_services
    create_systemd_scripts
    setup_environment
    
    # Copy rootfs to system
    info "Copying rootfs files to system..."
    copy_rootfs "$SCRIPT_DIR/rootfs"
    
    # Create /config directory and set permissions
    mkdir -p /config
    chown appbox:appbox /config
    chmod 755 /config
    
    # Create /defaults directory and copy files
    mkdir -p /defaults
    cp "$SCRIPT_DIR/rootfs/defaults"/* /defaults/
    chown -R appbox:appbox /defaults
    
    # Disable system nginx service to prevent port conflicts with selkies-nginx
    info "Disabling system nginx service to prevent conflicts..."
    systemctl stop nginx 2>/dev/null || true
    systemctl disable nginx 2>/dev/null || true
    
    # Enable systemd services (only top-level services with WantedBy directives)
    info "Enabling systemd services..."
    enable_service "selkies-setup"
    enable_service "selkies"
    enable_service "selkies-desktop"
    
    # Note: xvfb, selkies-pulseaudio, and selkies-nginx services
    # are started automatically by dependency chains and should not be enabled directly
    # This prevents circular dependencies that caused services to be skipped at boot
    
    # Start Docker service
    systemctl start docker
    systemctl enable docker
    
    # Cleanup
    cleanup_installation
    
    info "✅ Selkies installation completed successfully!"
    info "Services enabled:"
    info "  - selkies-setup.service (Device and permission setup)"
    info "  - selkies.service (Main selkies process)"
    info "  - selkies-desktop.service (Desktop environment)"
    info ""
    info "Dependency services (started automatically):"
    info "  - xvfb.service (Virtual display server)"
    info "  - selkies-pulseaudio.service (Audio server)"
    info "  - selkies-nginx.service (Web server)"
    info "  - docker.service (System Docker daemon)"
    info ""
    info "To start all services: systemctl start selkies-desktop"
    info "To check status: systemctl status selkies"
    info "Web interface will be available at: https://localhost:443"
}

# Run main installation
main "$@" 
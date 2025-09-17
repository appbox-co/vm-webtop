#!/bin/bash
set -e

# Enable debug logging
exec > /tmp/pulseaudio-service.log 2>&1
echo "$(date): Starting PulseAudio service script"

# Kill only the actual PulseAudio daemon, not this script
echo "$(date): Stopping existing PulseAudio daemon..."
pkill -f "/usr/bin/pulseaudio" || true
sleep 2

# Clean up any stale files
echo "$(date): Cleaning up stale files..."
rm -f /defaults/pid /defaults/native || true

# Create runtime directory for PulseAudio
echo "$(date): Creating PulseAudio runtime directory..."
mkdir -p /run/user/1000/pulse
mkdir -p /defaults
chown -R appbox:appbox /run/user/1000/pulse
chown -R appbox:appbox /defaults
chmod 755 /run/user/1000/pulse
chmod 755 /defaults

# Create a shared cookie for authentication
echo "$(date): Creating PulseAudio cookie..."
touch /tmp/pulse-cookie
chmod 644 /tmp/pulse-cookie

# Start fresh PulseAudio daemon
echo "$(date): Starting fresh PulseAudio daemon..."
cd /config
PULSE_RUNTIME_PATH=/run/user/1000/pulse /usr/bin/pulseaudio --log-level=4 --log-target=stderr --exit-idle-time=-1 &
PULSE_PID=$!
echo "$(date): PulseAudio started with PID: $PULSE_PID"

# Wait for PulseAudio to be ready
echo "$(date): Waiting for PulseAudio to be ready..."
sleep 3
ATTEMPTS=0
until PULSE_SERVER=unix:/run/user/1000/pulse/native pactl info >/dev/null 2>&1; do 
    ATTEMPTS=$((ATTEMPTS + 1))
    echo "$(date): Attempt $ATTEMPTS - PulseAudio not ready yet, sleeping..."
    if [ $ATTEMPTS -gt 20 ]; then
        echo "$(date): ERROR - PulseAudio failed to start after 20 attempts"
        # Check if PulseAudio is still running
        if ! kill -0 $PULSE_PID 2>/dev/null; then
            echo "$(date): PulseAudio process died. Checking for errors..."
            tail -n 50 /var/log/syslog | grep pulseaudio || true
        fi
        exit 1
    fi
    sleep 0.5
done
echo "$(date): PulseAudio is ready!"

# Now load the additional protocol modules for both socket locations
echo "$(date): Loading native protocol modules..."
pactl load-module module-native-protocol-unix auth-anonymous=1 socket=/run/user/1000/pulse/native || echo "$(date): Native protocol at /run/user/1000/pulse/native may already be loaded"
pactl load-module module-native-protocol-unix auth-anonymous=1 socket=/defaults/native || echo "$(date): Native protocol at /defaults/native may already be loaded"

# Completely disable suspension by not loading the module at all
echo "$(date): Unloading module-suspend-on-idle to prevent any suspension..."
pactl unload-module module-suspend-on-idle 2>/dev/null || true

# Check if output sink already exists before creating
echo "$(date): Checking for existing sinks..."
if ! pactl list short sinks | grep -q "^[0-9]*[[:space:]]*output[[:space:]]"; then
    echo "$(date): Creating output sink..."
    pactl load-module module-null-sink sink_name=output sink_properties=device.description=\"output\" rate=44100 channels=2
else
    echo "$(date): Output sink already exists, skipping creation"
fi

# Check if input sink already exists before creating (for microphone from browser)
if ! pactl list short sinks | grep -q "^[0-9]*[[:space:]]*input[[:space:]]"; then
    echo "$(date): Creating input sink for browser microphone..."
    pactl load-module module-null-sink sink_name=input sink_properties=device.description=\"input\" rate=44100 channels=2
else
    echo "$(date): Input sink already exists, skipping creation"
fi

# Set the default sink
echo "$(date): Setting default sink to output..."
pactl set-default-sink output || true

# Wait a bit for sockets to be created
echo "$(date): Waiting for PulseAudio sockets..."
sleep 2

# Ensure proper permissions
echo "$(date): Setting proper permissions for PulseAudio sockets..."
chown -R appbox:appbox /run/user/1000/pulse
chmod 755 /run/user/1000/pulse
if [ -S /run/user/1000/pulse/native ]; then
    chmod 666 /run/user/1000/pulse/native
    echo "$(date): PulseAudio socket created at /run/user/1000/pulse/native"
else
    echo "$(date): WARNING: PulseAudio socket not found at /run/user/1000/pulse/native"
fi

# Start alsa fix to prevent stuttering (simulates pavucontrol)
echo "$(date): Starting peak detector to prevent stuttering..."
PULSE_SERVER=unix:/run/user/1000/pulse/native /usr/local/bin/pulse-alsa-fix &
ALSA_FIX_PID=$!
echo "$(date): Peak detector started with PID: $ALSA_FIX_PID"

# Ensure sinks are not suspended
echo "$(date): Ensuring all sinks are active..."
pactl suspend-sink output 0 || true
pactl suspend-sink input 0 || true

echo "$(date): PulseAudio setup completed successfully with anti-stuttering measures"

# Wait for the PulseAudio process
echo "$(date): Waiting for PulseAudio process..."
wait $PULSE_PID

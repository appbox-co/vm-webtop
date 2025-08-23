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

# Start fresh PulseAudio daemon
echo "$(date): Starting fresh PulseAudio daemon..."
cd /config
PULSE_RUNTIME_PATH=/defaults /usr/bin/pulseaudio --log-level=4 --log-target=stderr --exit-idle-time=-1 &
PULSE_PID=$!
echo "$(date): PulseAudio started with PID: $PULSE_PID"

# Wait for PulseAudio to be ready
echo "$(date): Waiting for PulseAudio to be ready..."
sleep 3
ATTEMPTS=0
until pactl info >/dev/null 2>&1; do 
    ATTEMPTS=$((ATTEMPTS + 1))
    echo "$(date): Attempt $ATTEMPTS - PulseAudio not ready yet, sleeping..."
    if [ $ATTEMPTS -gt 20 ]; then
        echo "$(date): ERROR - PulseAudio failed to start after 20 attempts"
        exit 1
    fi
    sleep 0.5
done
echo "$(date): PulseAudio is ready!"

# Check if output sink already exists before creating
echo "$(date): Checking for existing sinks..."
if ! pactl list short sinks | grep -q "^[0-9]*[[:space:]]*output[[:space:]]"; then
    echo "$(date): Creating output sink..."
    pactl load-module module-null-sink sink_name="output" sink_properties=device.description="output"
else
    echo "$(date): Output sink already exists, skipping creation"
fi

# Create input sink for microphone forwarding
if ! pactl list short sinks | grep -q "^[0-9]*[[:space:]]*input[[:space:]]"; then
    echo "$(date): Creating input sink for Selkies microphone forwarding..."
    pactl load-module module-null-sink sink_name="input" sink_properties=device.description="input"
else
    echo "$(date): Input sink already exists, skipping creation"
fi

# Create virtual microphone source that monitors input.monitor for desktop apps
echo "$(date): Creating virtual microphone source for desktop apps..."
if ! pactl list short sources | grep -q "SelkiesVirtualMic"; then
    echo "$(date): Creating SelkiesVirtualMic to monitor input.monitor..."
    pactl load-module module-virtual-source source_name="SelkiesVirtualMic" master="input.monitor"
else
    echo "$(date): SelkiesVirtualMic already exists, checking master device..."
    # Note: Selkies may recreate this later, but we set the correct one first
fi

# Set defaults
echo "$(date): Setting defaults..."
pactl set-default-sink output || true
# Keep output.monitor as default source so pcmflux stays on desktop audio
pactl set-default-source output.monitor || true

echo "$(date): Audio routing setup:"
echo "$(date): - Desktop audio output -> 'output' sink -> 'output.monitor' source -> Selkies (SELKIES_AUDIO_DEVICE) -> WebRTC to browser"
echo "$(date): - Browser microphone -> WebRTC -> Selkies pasimple -> 'input' sink -> 'input.monitor' -> 'SelkiesVirtualMic' -> desktop apps"

echo "$(date): PulseAudio setup completed successfully"

# Wait for the PulseAudio process
echo "$(date): Waiting for PulseAudio process..."
wait $PULSE_PID

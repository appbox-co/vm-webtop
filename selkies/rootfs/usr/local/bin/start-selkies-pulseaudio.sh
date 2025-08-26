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

# Check if input sink already exists before creating (for microphone from browser)
if ! pactl list short sinks | grep -q "^[0-9]*[[:space:]]*input[[:space:]]"; then
    echo "$(date): Creating input sink for browser microphone..."
    pactl load-module module-null-sink sink_name="input" sink_properties=device.description="input"
else
    echo "$(date): Input sink already exists, skipping creation"
fi

# Create virtual microphone source for WebRTC input (monitor the input sink where browser sends mic audio)
echo "$(date): Creating virtual microphone source for WebRTC..."
if ! pactl list short sources | grep -q "VirtualMic"; then
    echo "$(date): Creating VirtualMic source to monitor input sink..."
    pactl load-module module-virtual-source source_name=VirtualMic master=input.monitor
    echo "$(date): VirtualMic source created - will capture browser microphone audio from input sink"
else
    echo "$(date): VirtualMic source already exists, skipping creation"
fi

# Set defaults (must run as abc user to affect the correct PulseAudio instance)
echo "$(date): Setting defaults..."
su - abc -c 'export PULSE_SERVER=unix:/defaults/native; pactl set-default-sink output' || true
su - abc -c 'export PULSE_SERVER=unix:/defaults/native; pactl set-default-source VirtualMic' || true

echo "$(date): VirtualMic set as default microphone input for browser"

echo "$(date): Audio routing setup:"
echo "$(date): - Desktop audio output -> 'output' sink -> 'output.monitor' source -> WebRTC to browser"
echo "$(date): - Browser microphone -> WebRTC -> 'input' sink -> 'input.monitor' source -> 'VirtualMic' -> desktop apps"

echo "$(date): PulseAudio setup completed successfully"

# Start background monitoring to ensure VirtualMic stays as default source
echo "$(date): Starting background task to monitor and maintain VirtualMic as default..."
(
    sleep 15  # Wait for Selkies to fully start
    while true; do
        # Check if Selkies is running and PulseAudio is responsive
        if pgrep -f "selkies.*audio_device_name" >/dev/null 2>&1; then
            # Check current default source
            CURRENT_DEFAULT=$(su - abc -c 'export PULSE_SERVER=unix:/defaults/native; pactl info 2>/dev/null | grep "Default Source"' | awk '{print $3}' 2>/dev/null || echo "")
            
            if [ -n "$CURRENT_DEFAULT" ] && [ "$CURRENT_DEFAULT" != "VirtualMic" ]; then
                echo "$(date): Default source is '$CURRENT_DEFAULT', should be 'VirtualMic'. Fixing..."
                
                # Ensure our VirtualMic source exists
                if su - abc -c 'export PULSE_SERVER=unix:/defaults/native; pactl list sources short' | grep -q "VirtualMic"; then
                    # Set VirtualMic as default
                    if su - abc -c 'export PULSE_SERVER=unix:/defaults/native; pactl set-default-source VirtualMic' 2>/dev/null; then
                        echo "$(date): ✅ VirtualMic restored as default source"
                    else
                        echo "$(date): ⚠️ Failed to set VirtualMic as default"
                    fi
                else
                    echo "$(date): ⚠️ VirtualMic source not found, recreating..."
                    su - abc -c 'export PULSE_SERVER=unix:/defaults/native; pactl load-module module-virtual-source source_name=VirtualMic master=input.monitor' 2>/dev/null || true
                fi
            else
                # VirtualMic is already default or no default found
                if [ "$CURRENT_DEFAULT" = "VirtualMic" ]; then
                    echo "$(date): ✅ VirtualMic is correctly set as default source"
                fi
            fi
        fi
        sleep 10  # Check every 10 seconds
    done
) &
MONITOR_PID=$!
echo "$(date): Background monitor started with PID: $MONITOR_PID"

# Wait for the PulseAudio process
echo "$(date): Waiting for PulseAudio process..."
wait $PULSE_PID

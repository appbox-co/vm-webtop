#!/bin/bash
set -e

# Monitor and fix Selkies microphone configuration
# This script runs continuously and ensures SelkiesVirtualMic always monitors input.monitor

echo "$(date): Starting Selkies microphone monitor service..."

export PULSE_SERVER=unix:/defaults/native

# Function to check and fix SelkiesVirtualMic
fix_selkies_mic() {
    # Check if SelkiesVirtualMic exists and what it's monitoring
    if pactl list sources short | grep -q "SelkiesVirtualMic"; then
        # Get the module index and check master device
        local module_info=$(pactl list modules | grep -A20 "module-virtual-source" | grep -B5 -A15 "source_name=SelkiesVirtualMic")
        
        if echo "$module_info" | grep -q "master=output.monitor"; then
            echo "$(date): Found SelkiesVirtualMic monitoring output.monitor (wrong!), fixing..."
            
            # Get the module index
            local module_index=$(pactl list modules short | grep "module-virtual-source" | grep "SelkiesVirtualMic" | awk '{print $1}')
            
            if [ -n "$module_index" ]; then
                # Unload the incorrect module
                echo "$(date): Unloading incorrect SelkiesVirtualMic module $module_index"
                pactl unload-module "$module_index" || true
                
                # Wait a moment for it to be fully unloaded
                sleep 0.5
                
                # Create the correct one
                echo "$(date): Creating correct SelkiesVirtualMic that monitors input.monitor"
                pactl load-module module-virtual-source source_name="SelkiesVirtualMic" master="input.monitor" || true
                
                # Set it as default source
                echo "$(date): Setting SelkiesVirtualMic as default source"
                pactl set-default-source SelkiesVirtualMic || true
                
                echo "$(date): Fixed SelkiesVirtualMic configuration"
                return 0
            fi
        elif echo "$module_info" | grep -q "master=input.monitor"; then
            # Already correct, but make sure it's the default source
            local current_default=$(pactl info | grep "Default Source:" | awk '{print $3}')
            if [ "$current_default" != "SelkiesVirtualMic" ]; then
                echo "$(date): SelkiesVirtualMic is correct but not default, setting as default"
                pactl set-default-source SelkiesVirtualMic || true
            fi
        fi
    fi
}

# Main monitoring loop
while true; do
    # Wait for PulseAudio to be available
    until pactl info >/dev/null 2>&1; do
        echo "$(date): Waiting for PulseAudio to be available..."
        sleep 5
    done
    
    # Check and fix the configuration
    fix_selkies_mic
    
    # Wait before next check
    sleep 2
done

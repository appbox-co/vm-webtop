#!/bin/bash
set -e

# Adaptive Selkies Microphone Patch Script
# This script attempts to patch the Selkies source code to fix microphone routing
# Falls back to monitoring service if patching fails

echo "$(date): Starting Selkies microphone patch process..."

# Function to find Selkies installation
find_selkies_websocket() {
    local websocket_file=""
    
    # Try to find selkies_gstreamer module location
    echo "$(date): Attempting to locate selkies_gstreamer module..."
    
    # Method 1: Use Python to find the module
    if command -v python3 >/dev/null 2>&1; then
        local module_path=$(python3 -c "
try:
    import selkies_gstreamer
    print(selkies_gstreamer.__file__)
except ImportError:
    pass
" 2>/dev/null)
        
        if [ -n "$module_path" ]; then
            local module_dir=$(dirname "$module_path")
            websocket_file="$module_dir/websocket.py"
            if [ -f "$websocket_file" ]; then
                echo "$(date): Found websocket.py via Python import: $websocket_file"
                echo "$websocket_file"
                return 0
            fi
        fi
    fi
    
    # Method 2: Search common Python installation paths
    echo "$(date): Searching common Python paths..."
    local python_version=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null || echo "3.12")
    
    local search_paths=(
        "/usr/local/lib/python${python_version}/dist-packages/selkies_gstreamer"
        "/usr/lib/python${python_version}/dist-packages/selkies_gstreamer"
        "/usr/local/lib/python${python_version}/site-packages/selkies_gstreamer"
        "/usr/lib/python${python_version}/site-packages/selkies_gstreamer"
    )
    
    for path in "${search_paths[@]}"; do
        if [ -f "$path/websocket.py" ]; then
            echo "$(date): Found websocket.py at: $path/websocket.py"
            echo "$path/websocket.py"
            return 0
        fi
    done
    
    # Method 3: Find using locate/find
    echo "$(date): Using find command to search filesystem..."
    local found_file=$(find /usr -name "websocket.py" -path "*/selkies_gstreamer/*" 2>/dev/null | head -1)
    if [ -n "$found_file" ]; then
        echo "$(date): Found websocket.py via find: $found_file"
        echo "$found_file"
        return 0
    fi
    
    echo "$(date): Could not locate selkies_gstreamer/websocket.py"
    return 1
}

# Function to patch the websocket.py file
patch_websocket_file() {
    local websocket_file="$1"
    
    echo "$(date): Attempting to patch $websocket_file..."
    
    # Check if the file contains the target line
    if ! grep -q 'master_monitor.*=.*"output\.monitor"' "$websocket_file"; then
        echo "$(date): Target line not found in $websocket_file"
        return 1
    fi
    
    # Create backup
    local backup_file="${websocket_file}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$websocket_file" "$backup_file"
    echo "$(date): Created backup: $backup_file"
    
    # Apply patch
    if sed -i 's/master_monitor = "output\.monitor"/master_monitor = "input.monitor"/' "$websocket_file"; then
        echo "$(date): Successfully patched $websocket_file"
        
        # Verify the patch
        if grep -q 'master_monitor.*=.*"input\.monitor"' "$websocket_file"; then
            echo "$(date): Patch verification successful"
            return 0
        else
            echo "$(date): Patch verification failed, restoring backup"
            cp "$backup_file" "$websocket_file"
            return 1
        fi
    else
        echo "$(date): Failed to apply patch, restoring backup"
        cp "$backup_file" "$websocket_file"
        return 1
    fi
}

# Function to enable monitoring service fallback
enable_monitoring_fallback() {
    echo "$(date): Enabling monitoring service fallback..."
    
    # Check if monitor service exists
    if [ -f "/etc/systemd/system/selkies-mic-monitor.service" ]; then
        systemctl daemon-reload
        systemctl enable selkies-mic-monitor.service
        systemctl start selkies-mic-monitor.service
        echo "$(date): Monitoring service enabled and started"
        return 0
    else
        echo "$(date): Warning: Monitor service file not found at /etc/systemd/system/selkies-mic-monitor.service"
        return 1
    fi
}

# Function to disable monitoring service (when patch succeeds)
disable_monitoring_fallback() {
    echo "$(date): Disabling monitoring service (patch successful)..."
    
    if systemctl is-enabled selkies-mic-monitor.service >/dev/null 2>&1; then
        systemctl stop selkies-mic-monitor.service 2>/dev/null || true
        systemctl disable selkies-mic-monitor.service 2>/dev/null || true
        echo "$(date): Monitoring service disabled"
    fi
}

# Main execution
main() {
    echo "$(date): === Selkies Microphone Patch Process ==="
    
    # Find the websocket.py file
    local websocket_file
    if websocket_file=$(find_selkies_websocket); then
        echo "$(date): Found Selkies websocket file: $websocket_file"
        
        # Attempt to patch
        if patch_websocket_file "$websocket_file"; then
            echo "$(date): ✅ Patch applied successfully!"
            echo "$(date): Microphone routing will now work correctly"
            echo "$(date): Browser microphone → input sink → input.monitor → SelkiesVirtualMic → desktop apps"
            
            # Disable monitoring service since patch worked
            disable_monitoring_fallback
            
            # Restart selkies service to apply changes
            echo "$(date): Restarting selkies service to apply changes..."
            systemctl restart selkies.service || true
            
            return 0
        else
            echo "$(date): ❌ Failed to patch websocket file"
        fi
    else
        echo "$(date): ❌ Could not locate Selkies websocket file"
    fi
    
    # Fallback to monitoring service
    echo "$(date): 🔄 Falling back to monitoring service approach..."
    if enable_monitoring_fallback; then
        echo "$(date): ✅ Monitoring service fallback enabled"
        echo "$(date): The service will automatically fix microphone routing when needed"
        return 0
    else
        echo "$(date): ❌ Failed to enable monitoring service fallback"
        echo "$(date): Manual intervention may be required"
        return 1
    fi
}

# Execute main function
main "$@"

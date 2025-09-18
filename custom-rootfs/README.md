# Custom Root Filesystem Directory

This directory allows you to add custom files that will be copied to the system during installation, following the same pattern as component `rootfs/` directories.

## Usage

1. Create the directory structure mirroring the target system filesystem
2. Place your custom files in the appropriate locations
3. Files will be copied during installation with proper permissions
4. Directory structure follows standard Linux filesystem hierarchy

## Directory Structure

The `custom-rootfs/` directory mirrors the target system filesystem:

```
custom-rootfs/
├── etc/
│   ├── systemd/system/          # Custom systemd services
│   ├── nginx/                   # Custom nginx configuration
│   └── cron.d/                  # Custom cron jobs
├── usr/
│   ├── local/bin/               # Custom scripts and binaries
│   ├── share/applications/      # Custom .desktop files
│   └── lib/                     # Custom libraries
├── opt/
│   └── my-application/          # Custom application files
└── home/appbox/
    ├── .config/                 # User configuration files
    └── Desktop/                 # Desktop shortcuts
```

## Examples

### Custom Systemd Service
```bash
# Create custom service
mkdir -p custom-rootfs/etc/systemd/system
cat > custom-rootfs/etc/systemd/system/my-service.service << 'EOF'
[Unit]
Description=My Custom Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/my-script.sh
Restart=always
User=appbox

[Install]
WantedBy=multi-user.target
EOF
```

### Custom Script
```bash
# Create custom script
mkdir -p custom-rootfs/usr/local/bin
cat > custom-rootfs/usr/local/bin/my-script.sh << 'EOF'
#!/bin/bash
echo "Custom script running..."
# Your custom logic here
EOF
chmod +x custom-rootfs/usr/local/bin/my-script.sh
```

### Custom Desktop Application
```bash
# Create desktop entry
mkdir -p custom-rootfs/usr/share/applications
cat > custom-rootfs/usr/share/applications/my-app.desktop << 'EOF'
[Desktop Entry]
Name=My Application
Comment=My custom application
Exec=/usr/local/bin/my-app
Icon=my-app
Terminal=false
Type=Application
Categories=Utility;
EOF
```

### User Configuration Files
```bash
# Create user config (will be owned by appbox user)
mkdir -p custom-rootfs/home/appbox/.config/my-app
cat > custom-rootfs/home/appbox/.config/my-app/config.json << 'EOF'
{
  "setting1": "value1",
  "setting2": "value2"
}
EOF
```

### Custom Nginx Configuration
```bash
# Create custom nginx site
mkdir -p custom-rootfs/etc/nginx/sites-available
cat > custom-rootfs/etc/nginx/sites-available/my-site << 'EOF'
server {
    listen 8080;
    server_name localhost;
    
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
EOF
```

## File Permissions

- **Executable files**: Automatically detected and permissions preserved
- **Configuration files**: Set to 644 (readable by all, writable by owner)
- **Scripts in `/usr/local/bin/`**: Automatically made executable (755)
- **Systemd services**: Set to 644 with proper ownership
- **User files** (`/home/appbox/`): Owned by appbox user with appropriate permissions

## Integration with Installation

1. **Timing**: Custom rootfs files are copied after main components but before custom scripts
2. **Permissions**: Proper ownership and permissions are set automatically
3. **Systemd Services**: Custom services are automatically enabled if found in `/etc/systemd/system/`
4. **User Files**: Files in `/home/appbox/` are automatically owned by the appbox user

## Best Practices

- **Use standard paths**: Follow Linux filesystem hierarchy standards
- **Test permissions**: Ensure files have appropriate permissions before copying
- **Document changes**: Consider adding comments in configuration files
- **Backup originals**: Custom files may override existing system files
- **Use templates**: Consider using environment variables in configuration files

## Notes

- This directory is ignored by git (see `.gitignore`)
- Files are copied recursively maintaining directory structure
- Existing system files will be overwritten by custom files
- Custom systemd services are automatically enabled during installation
- User-specific files are automatically assigned to the appbox user

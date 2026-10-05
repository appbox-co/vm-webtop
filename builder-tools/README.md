# Builder desktop command

Install from the exact pushed Git commit on builder VM 254280:

```sh
sudo bash builder-tools/install.sh
desktop off
```

The installed command is available in the shell:

```sh
desktop on       # Start Selkies, KDE, the virtual display and audio
desktop off      # Stop desktop services and keep them off after reboot
desktop status  # Show desktop mode and service state
```

The command checks the builder's VM UUID and uses sudo when needed. Turning
the desktop off closes its graphical session. SSH, Docker, BuildKit and other
build tools remain available.

Builder-only systemd drop-ins prevent desktop and audio services from starting
while the desktop is off. Their marker is
`/var/lib/appbox-builder-desktop/enabled`. Existing service files and user
settings are retained.

This directory is outside the image rootfs and is not called by any image
installer or release script. Installing it does not change published VM images
or customer VM defaults.

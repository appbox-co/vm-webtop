#!/bin/bash
set -euo pipefail

APPBOX_HOME="$(getent passwd appbox | awk -F: '{print $6}')"
CONFIG_ROOTS=()

if [[ -n "${HOME:-}" ]]; then
    CONFIG_ROOTS+=("$HOME")
fi
CONFIG_ROOTS+=("/config" "$APPBOX_HOME")

mapfile -t CONFIG_ROOTS < <(printf '%s\n' "${CONFIG_ROOTS[@]}" | awk 'NF && !seen[$0]++')

for config_root in "${CONFIG_ROOTS[@]}"; do
    CONFIG_DIR="${config_root}/.config"
    CONFIG_FILE="${CONFIG_DIR}/plasma-org.kde.plasma.desktop-appletsrc"
    DESKTOP_DIR="${config_root}/Desktop"
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$DESKTOP_DIR"

    cat > "${CONFIG_DIR}/user-dirs.dirs" <<EOF
XDG_DESKTOP_DIR="${DESKTOP_DIR}"
XDG_DOWNLOAD_DIR="${config_root}/Downloads"
XDG_TEMPLATES_DIR="${config_root}/Templates"
XDG_PUBLICSHARE_DIR="${config_root}/Public"
XDG_DOCUMENTS_DIR="${config_root}/Documents"
XDG_MUSIC_DIR="${config_root}/Music"
XDG_PICTURES_DIR="${config_root}/Pictures"
XDG_VIDEOS_DIR="${config_root}/Videos"
EOF

    python3 - "$CONFIG_FILE" "$DESKTOP_DIR" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
desktop_url = Path(sys.argv[2]).as_uri()
wallpaper = "file:///usr/share/backgrounds/appbox/appbox.svg"
wallpaper_color = "#0e0f15"
launchers = ",".join(
    [
        "applications:org.kde.dolphin.desktop",
        "applications:org.kde.konsole.desktop",
        "applications:chromium_chromium.desktop",
        "applications:snap-store_snap-store.desktop",
    ]
)

if path.exists():
    lines = path.read_text().splitlines()
else:
    lines = [
        "[Containments][1]",
        "formfactor=0",
        "immutability=1",
        "lastScreen=0",
        "location=0",
        "plugin=org.kde.plasma.folder",
        "wallpaperplugin=org.kde.image",
        "",
        "[Containments][2]",
        "formfactor=2",
        "immutability=1",
        "lastScreen=0",
        "location=4",
        "plugin=org.kde.panel",
        "",
        "[Containments][2][Applets][3]",
        "immutability=1",
        "plugin=org.kde.plasma.kickoff",
        "",
        "[Containments][2][Applets][5]",
        "immutability=1",
        "plugin=org.kde.plasma.icontasks",
        "",
        "[Containments][2][Applets][6]",
        "immutability=1",
        "plugin=org.kde.plasma.marginsseparator",
        "",
        "[Containments][2][Applets][7]",
        "immutability=1",
        "plugin=org.kde.plasma.systemtray",
        "",
        "[Containments][2][Applets][18]",
        "immutability=1",
        "plugin=org.kde.plasma.digitalclock",
        "",
        "[Containments][2][Applets][19]",
        "immutability=1",
        "plugin=org.kde.plasma.showdesktop",
        "",
        "[Containments][2][General]",
        "AppletOrder=3;5;6;7;18;19",
        "",
    ]


def section_indices():
    sections = {}
    current = None
    for index, line in enumerate(lines):
        if line.startswith("[") and line.endswith("]"):
            current = line[1:-1]
            sections[current] = index
    return sections


def set_key(section, key, value):
    global lines
    header = f"[{section}]"
    sections = section_indices()

    if section not in sections:
        if lines and lines[-1] != "":
            lines.append("")
        lines.extend([header, f"{key}={value}"])
        return

    start = sections[section] + 1
    end = len(lines)
    for index in range(start, len(lines)):
        if lines[index].startswith("[") and lines[index].endswith("]"):
            end = index
            break

    prefix = f"{key}="
    for index in range(start, end):
        if lines[index].startswith(prefix):
            lines[index] = f"{key}={value}"
            return

    lines.insert(end, f"{key}={value}")


def plugins_by_section():
    plugins = {}
    current = None
    for line in lines:
        if line.startswith("[") and line.endswith("]"):
            current = line[1:-1]
        elif current and line.startswith("plugin="):
            plugins[current] = line.split("=", 1)[1]
    return plugins


plugins = plugins_by_section()
desktop_sections = [
    section for section, plugin in plugins.items() if plugin == "org.kde.plasma.folder"
]
icontask_sections = [
    section for section, plugin in plugins.items() if plugin == "org.kde.plasma.icontasks"
]

if not desktop_sections:
    desktop_sections = ["Containments][1"]
if not icontask_sections:
    icontask_sections = ["Containments][2][Applets][5"]

for section in desktop_sections:
    set_key(section, "url", desktop_url)
    set_key(section, "wallpaperplugin", "org.kde.image")
    wallpaper_section = f"{section}][Wallpaper][org.kde.image][General"
    set_key(wallpaper_section, "Color", wallpaper_color)
    set_key(wallpaper_section, "FillMode", "6")
    set_key(wallpaper_section, "Image", wallpaper)
    set_key(wallpaper_section, "PreviewImage", wallpaper)

for section in icontask_sections:
    set_key(f"{section}][Configuration][General", "launchers", launchers)

path.write_text("\n".join(lines) + "\n")
PY

    if [[ "$(id -u)" -eq 0 ]]; then
        chown -R appbox:appbox "$CONFIG_DIR" "$DESKTOP_DIR"
    fi
done

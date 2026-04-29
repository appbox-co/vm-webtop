#!/bin/bash

# Desktop environment startup script
# This script runs as user appbox and starts the desktop environment

# Set up user systemd environment
echo "Setting up user systemd environment..."
USER_ID="$(id -u)"
export XDG_RUNTIME_DIR="/run/user/${USER_ID}"
/etc/selkies/setup-user-systemd.sh

export XDG_SESSION_TYPE=x11
export XDG_SESSION_CLASS=user
export XDG_SESSION_DESKTOP=KDE
export XDG_CURRENT_DESKTOP=KDE
export DESKTOP_SESSION=plasma
export KDE_FULL_SESSION=true
export KDE_SESSION_VERSION=6
export QT_QPA_PLATFORM=xcb
export GDK_BACKEND=x11

cleanup_stale_plasma_session() {
  echo "Cleaning up stale Plasma processes..."
  pkill -u "$(id -u)" -f 'startplasma-x11|plasmashell|kwin_x11|ksmserver|kded[0-9]*|kglobalacceld|kactivitymanagerd|kioworker' 2>/dev/null || true
  sleep 1
}

# wait for X server to be ready
echo "Waiting for X server to be ready..."
until xdpyinfo -display :1 >/dev/null 2>&1; do
    echo "X server not ready, waiting..."
    sleep 1
done
echo "X server is ready."
cleanup_stale_plasma_session

# set locale and keyboard
if [ ! -z "$LANG" ]; then
  export LANG="$LANG"
fi

# Set default keyboard layout
XKB_LAYOUT_ARGS=""
if [ ! -z "$KEYBOARD_LAYOUT" ]; then
  XKB_LAYOUT_ARGS="$KEYBOARD_LAYOUT"
elif [ ! -z "$LANG" ]; then
  # Extract locale from LANG variable
  normalized_locale=$(echo "$LANG" | sed 's/[._@].*//')
  normalized_locale_lower=$(echo "$normalized_locale" | tr '[:upper:]' '[:lower:]')
  
  # Map common locales to keyboard layouts
  declare -A LOCALE_TO_XKB_MAP=(
    ["en_us"]="us" ["en_gb"]="gb" ["de_de"]="de" ["fr_fr"]="fr" ["es_es"]="es" ["it_it"]="it"
    ["pt_br"]="br" ["pt_pt"]="pt" ["ru_ru"]="ru" ["ja_jp"]="jp" ["ko_kr"]="kr" ["zh_cn"]="cn"
    ["zh_tw"]="tw" ["ar_sa"]="ara" ["hi_in"]="in -variant hin" ["th_th"]="th" ["vi_vn"]="vn"
    ["pl_pl"]="pl" ["cs_cz"]="cz -variant qwerty" ["hu_hu"]="hu" ["ro_ro"]="ro" ["bg_bg"]="bg"
    ["hr_hr"]="hr" ["sk_sk"]="sk -variant qwerty" ["sl_si"]="si" ["et_ee"]="ee" ["lv_lv"]="lv"
    ["lt_lt"]="lt" ["fi_fi"]="fi" ["sv_se"]="se" ["no_no"]="no" ["da_dk"]="dk" ["nl_nl"]="nl"
    ["be_by"]="by" ["uk_ua"]="ua" ["mk_mk"]="mk" ["al_al"]="al" ["mt_mt"]="mt" ["is_is"]="is"
    ["fo_fo"]="fo" ["ga_ie"]="ie" ["cy_gb"]="gb -variant colemak" ["gd_gb"]="gb -variant colemak"
    ["ca_es"]="es -variant cat" ["eu_es"]="es" ["gl_es"]="es" ["oc_fr"]="fr" ["br_fr"]="fr"
    ["co_fr"]="fr" ["wa_be"]="be" ["lb_lu"]="lu" ["de_at"]="at" ["de_ch"]="ch" ["fr_ch"]="ch -variant fr"
    ["it_ch"]="ch" ["rm_ch"]="ch" ["fur_it"]="it" ["sc_it"]="it" ["lij_it"]="it" ["vec_it"]="it"
    ["nap_it"]="it" ["scn_it"]="it" ["an_es"]="es" ["ast_es"]="es" ["ext_es"]="es" ["mwl_pt"]="pt"
    ["lo_la"]="la" ["si_lk"]="lk -variant sinhala_qwerty_us" ["ta_lk"]="lk -variant tam_unicode"
    ["ka_ge"]="ge" ["hy_am"]="am -variant eastern" ["az_az"]="az -variant latin" ["kk_kz"]="kz"
    ["ky_kg"]="kg" ["uz_uz"]="uz -variant latin" ["tg_tj"]="tj" ["mn_mn"]="mn" ["bo_cn"]="cn -variant tib"
    ["bo_in"]="in -variant tib" ["dz_bt"]="bt" ["ne_np"]="np" ["si_lk"]="lk -variant sinhala_qwerty_us"
    ["my_mm"]="mm" ["km_kh"]="kh" ["lo_la"]="la"
  )

  if [[ -v "LOCALE_TO_XKB_MAP[$normalized_locale_lower]" ]]; then
    XKB_LAYOUT_ARGS="${LOCALE_TO_XKB_MAP[$normalized_locale_lower]}"
  fi
fi

if [ ! -z "$XKB_LAYOUT_ARGS" ]; then
  echo "Setting keyboard layout: $XKB_LAYOUT_ARGS"
  setxkbmap ${XKB_LAYOUT_ARGS} 2>/dev/null || echo "Warning: Could not set keyboard layout"
fi

# Set permissions on temporary files
chmod 777 /tmp/selkies* 2>/dev/null || true

# Set PulseAudio environment variables for desktop applications
echo "Setting PulseAudio environment..."
export PULSE_SERVER=unix:${XDG_RUNTIME_DIR}/pulse/native
export PULSE_RUNTIME_PATH=${XDG_RUNTIME_DIR}/pulse
# Also keep the legacy socket for compatibility
export PULSE_SERVER_LEGACY=unix:/defaults/native

# Use the D-Bus session from systemd --user
if [ -S "${XDG_RUNTIME_DIR}/bus" ]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
    echo "Using systemd --user D-Bus session"
else
    echo "Warning: systemd --user D-Bus socket not found"
fi

# Set sane resolution before starting apps with better error handling
echo "Configuring display resolution..."

# Check if xrandr is working
if ! xrandr >/dev/null 2>&1; then
    echo "Warning: xrandr is not available or not working properly"
else
    # Get current display info
    CURRENT_DISPLAY=$(xrandr | grep " connected" | awk '{print $1}' | head -1)
    if [ -z "$CURRENT_DISPLAY" ]; then
        CURRENT_DISPLAY="screen"
    fi
    
    echo "Using display: $CURRENT_DISPLAY"
    
    INITIAL_WIDTH="${DISPLAY_SIZEW:-1920}"
    INITIAL_HEIGHT="${DISPLAY_SIZEH:-1080}"
    INITIAL_REFRESH="${DISPLAY_REFRESH:-60}"
    INITIAL_DPI="${DISPLAY_DPI:-96}"
    INITIAL_MODE="${INITIAL_WIDTH}x${INITIAL_HEIGHT}"

    if xrandr | grep -q "${INITIAL_MODE}"; then
        echo "Using existing display mode ${INITIAL_MODE}"
    elif command -v cvt >/dev/null 2>&1 || command -v xcvt >/dev/null 2>&1; then
        CVT_COMMAND="$(command -v cvt || command -v xcvt)"
        MODELINE="$("$CVT_COMMAND" "$INITIAL_WIDTH" "$INITIAL_HEIGHT" "$INITIAL_REFRESH" | awk '/Modeline/ {$1=""; sub(/^ /, ""); print}')"
        if [ -n "$MODELINE" ] && xrandr --newmode $MODELINE 2>/dev/null; then
            echo "Created display mode ${INITIAL_MODE}"
            xrandr --addmode "$CURRENT_DISPLAY" "$INITIAL_MODE" 2>/dev/null || true
        else
            echo "Warning: Could not create display mode ${INITIAL_MODE}, using default resolution"
        fi
    fi

    if xrandr --output "$CURRENT_DISPLAY" --mode "$INITIAL_MODE" --dpi "$INITIAL_DPI" 2>/dev/null; then
        echo "Set display mode to ${INITIAL_MODE}"
    else
        echo "Warning: Could not set display mode ${INITIAL_MODE}, using default"
    fi
fi

# set xresources
echo "Setting X resources..."
if [ -f "${HOME}/.Xresources" ]; then
  xrdb "${HOME}/.Xresources" 2>/dev/null || echo "Warning: Could not load .Xresources"
else
  echo "Xcursor.theme: breeze" > "${HOME}/.Xresources"
  xrdb "${HOME}/.Xresources" 2>/dev/null || echo "Warning: Could not load .Xresources"
fi
chown appbox:appbox "${HOME}/.Xresources" 2>/dev/null || true

if [ -x /usr/local/sbin/appbox-apply-kde-defaults.sh ]; then
  /usr/local/sbin/appbox-apply-kde-defaults.sh || echo "Warning: Could not apply KDE defaults"
fi

# run desktop environment
echo "Starting desktop environment..."
cd "$HOME" || exit 1

if command -v startplasma-x11 >/dev/null 2>&1; then
  echo "Starting KDE Plasma X11 session..."
  if [ -S "${XDG_RUNTIME_DIR}/bus" ]; then
    exec startplasma-x11
  fi
  exec dbus-run-session startplasma-x11
fi 

echo "Warning: startplasma-x11 is unavailable; falling back to OpenBox."
exec /usr/bin/openbox-session
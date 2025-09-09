#!/bin/bash

# Desktop environment startup script
# This script runs as user appbox and starts the desktop environment

# Set up user systemd environment
echo "Setting up user systemd environment..."
/etc/selkies/setup-user-systemd.sh

# wait for X server to be ready
echo "Waiting for X server to be ready..."
until xdpyinfo -display :1 >/dev/null 2>&1; do
    echo "X server not ready, waiting..."
    sleep 1
done
echo "X server is ready."

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
export PULSE_SERVER=unix:/defaults/native
export PULSE_RUNTIME_PATH=/defaults

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
    
    # Try to create and set display mode with error handling
    if xrandr --newmode "1024x768" 63.50 1024 1072 1176 1328 768 771 775 798 -hsync +vsync 2>/dev/null; then
        echo "Created display mode 1024x768"
        if xrandr --addmode "$CURRENT_DISPLAY" "1024x768" 2>/dev/null; then
            echo "Added mode to display"
            if xrandr --output "$CURRENT_DISPLAY" --mode "1024x768" --dpi 96 2>/dev/null; then
                echo "Set display mode successfully"
            else
                echo "Warning: Could not set display mode, using default"
            fi
        else
            echo "Warning: Could not add mode to display, using default"
        fi
    else
        echo "Warning: Could not create display mode, using default resolution"
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

# run desktop environment
echo "Starting desktop environment..."
cd $HOME

# Check if webtop is installed and use appropriate desktop environment
if [ -f "/etc/selkies/webtop-installed" ]; then
  # Use XFCE desktop environment (webtop)
  echo "Starting XFCE desktop environment..."
  exec /bin/bash /defaults/startwm.sh
else
  # Use OpenBox desktop environment (default selkies)
  echo "Starting OpenBox desktop environment..."
  exec /usr/bin/openbox-session
fi 
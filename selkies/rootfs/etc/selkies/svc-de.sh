#!/bin/bash

# wait for X to be running
while true; do
  if xset q &>/dev/null; then
    break
  fi
  sleep .5
done

# set the keyboard map by LC if known
if [ ! -z "${LC_ALL}" ]; then
  normalized_locale_full=${LC_ALL%%.*}
  normalized_locale_lower=$(echo "$normalized_locale_full" | tr '[:upper:]' '[:lower:]')

  declare -A LOCALE_TO_XKB_MAP=(
    ["af_za"]="za" ["am_et"]="et -variant am" ["ar_sa"]="sa" ["ar_eg"]="eg" ["ar"]="ara"
    ["en_us"]="us" ["en_gb"]="gb" ["en_ca"]="ca -variant eng" ["en_au"]="au" ["en_ie"]="ie"
    ["en_in"]="in -variant eng" ["en"]="us" ["es_es"]="es" ["es_mx"]="latam" ["es_ar"]="latam"
    ["es_us"]="us -variant intl" ["es"]="es" ["fr_fr"]="fr" ["fr_ca"]="ca -variant fr"
    ["fr_be"]="be" ["fr_ch"]="ch -variant fr" ["fr_lu"]="lu" ["fr"]="fr" ["de_de"]="de"
    ["de_ch"]="ch -variant de" ["de_at"]="at" ["de_lu"]="lu" ["de_be"]="be" ["de"]="de"
    ["it_it"]="it" ["it_ch"]="ch -variant it" ["it"]="it" ["ja_jp"]="jp" ["ko_kr"]="kr"
    ["zh_cn"]="cn" ["zh_hk"]="hk" ["zh_sg"]="sg" ["zh_tw"]="tw" ["zh"]="cn" ["ru_ru"]="ru"
    ["ru_ua"]="ua -variant ru" ["ru"]="ru" ["pt_pt"]="pt" ["pt_br"]="br" ["pt"]="pt"
    ["pl_pl"]="pl" ["nl_nl"]="nl" ["nl_be"]="be" ["nl"]="nl" ["sv_se"]="se" ["sv_fi"]="fi -variant se"
    ["sv"]="se" ["da_dk"]="dk" ["no"]="no" ["fi_fi"]="fi" ["cs_cz"]="cz" ["sk_sk"]="sk"
    ["hu_hu"]="hu" ["el_gr"]="gr" ["el_cy"]="cy" ["el"]="gr" ["tr_tr"]="tr" ["tr"]="tr"
    ["he_il"]="il" ["ar_sa"]="sa" ["th_th"]="th" ["vi_vn"]="vn" ["hi_in"]="in -variant hin"
    ["bn_bd"]="bd -variant probhat" ["bn_in"]="in -variant ben" ["ta_in"]="in -variant tam"
    ["te_in"]="in -variant tel" ["mr_in"]="in -variant mar" ["gu_in"]="in -variant guj"
    ["kn_in"]="in -variant kan" ["ml_in"]="in -variant mal" ["or_in"]="in -variant ori"
    ["pa_in"]="in -variant pan" ["as_in"]="in -variant asm" ["ur_in"]="in -variant urd"
    ["ur_pk"]="pk -variant ur" ["fa_ir"]="ir" ["ps_af"]="ps" ["my_mm"]="mm" ["km_kh"]="kh"
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
  setxkbmap ${XKB_LAYOUT_ARGS}
fi
chmod 777 /tmp/selkies* || true

# set sane resolution before starting apps
xrandr --newmode "1024x768" 63.50  1024 1072 1176 1328  768 771 775 798 -hsync +vsync
xrandr --addmode screen "1024x768"
xrandr --output screen --mode "1024x768" --dpi 96

# set xresources
if [ -f "${HOME}/.Xresources" ]; then
  xrdb "${HOME}/.Xresources"
else
  echo "Xcursor.theme: breeze" > "${HOME}/.Xresources"
  xrdb "${HOME}/.Xresources"
fi
chown abc:abc "${HOME}/.Xresources"

# run
cd $HOME

# Check if webtop is installed and use appropriate desktop environment
if [ -f "/etc/selkies/webtop-installed" ]; then
  # Use XFCE desktop environment (webtop)
  exec /bin/bash /defaults/startwm.sh
else
  # Use OpenBox desktop environment (default selkies)
  exec /usr/bin/openbox-session
fi 
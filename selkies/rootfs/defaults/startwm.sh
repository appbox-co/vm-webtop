#!/usr/bin/env bash

# Enable Nvidia GPU support if detected
if which nvidia-smi && [ "${DISABLE_ZINK}" == "false" ]; then
  export LIBGL_KOPPER_DRI2=1
  export MESA_LOADER_DRIVER_OVERRIDE=zink
  export GALLIUM_DRIVER=zink
fi

if command -v startplasma-x11 >/dev/null 2>&1; then
  exec startplasma-x11
fi

exec /usr/bin/openbox-session
#!/bin/bash
set -euo pipefail
set +x
if [[ $# != 1 || -z "$1" ]]; then
    printf 'Usage: /moduser.sh <new-password>\n' >&2
    exit 1
fi
# Pass the recovery password through stdin; never echo it or add it to docker argv.
printf '%s' "$1" | /usr/local/lib/appbox-coolify/runtime.py reset-password

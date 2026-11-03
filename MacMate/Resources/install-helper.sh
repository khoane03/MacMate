#!/bin/bash
set -euo pipefail
umask 022

SRC_SMC="$1"
SRC_HELPER="$2"

if [ -z "$SRC_SMC" ] || [ -z "$SRC_HELPER" ]; then
    echo "Error: Missing source paths"
    exit 1
fi

if [ ! -f "$SRC_SMC" ] || [ ! -f "$SRC_HELPER" ]; then
    echo "Error: Source files do not exist"
    exit 1
fi

/usr/bin/install -d -o root -g wheel -m 755 /usr/local/bin
/usr/bin/install -o root -g wheel -m 755 "$SRC_SMC" /usr/local/bin/displaycontrol-smc
/usr/bin/install -o root -g wheel -m 755 "$SRC_HELPER" /usr/local/bin/displaycontrol-power

/usr/bin/install -d -o root -g wheel -m 755 /etc/sudoers.d
SUDOERS_TMP="$(/usr/bin/mktemp /tmp/macmate-sudoers.XXXXXX)"
trap '/bin/rm -f "$SUDOERS_TMP"' EXIT
/usr/bin/printf '%%admin ALL = (root) NOPASSWD: /usr/local/bin/displaycontrol-power\n' > "$SUDOERS_TMP"
/bin/chmod 440 "$SUDOERS_TMP"
/usr/sbin/visudo -cf "$SUDOERS_TMP" >/dev/null
/usr/bin/install -o root -g wheel -m 440 "$SUDOERS_TMP" /etc/sudoers.d/displaycontrol_power

echo "SUCCESS"

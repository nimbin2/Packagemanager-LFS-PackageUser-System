#!/bin/bash
# bootscripts.sh -- give every installed service the bootscript it needs.
#
# THE PACKAGE AND THE THING THAT STARTS IT COME FROM DIFFERENT TARBALLS.
# A BLFS package installs a daemon; blfs-bootscripts installs the script that
# runs it at boot, one `make install-<target>` per service.  Nothing connects
# them, so a package added to a stack later has no bootscript and its service
# quietly never starts -- which is how `install-service-dhcpcd` came to be
# missing from a list that already had nine other targets in it.
#
# This reads bootscripts.conf, which is that list as a MAPPING, and installs
# the targets whose package is here and whose script is not.  Idempotent: it
# checks what exists before and after, and a package that is not installed is
# skipped -- an init script for something absent is a symlink in rc?.d that
# fails at boot.
set -u

CONF="${BOOTSCRIPTS_CONF:-/etc/pkgusr/stacks/bootscripts.conf}"
SRC="${BOOTSCRIPTS_SRC:-}"
BASE="${PKGUSR_BASE:-/usr/src}"
DO_IFCONFIG="${BOOTSCRIPTS_IFCONFIG:-yes}"
SYSCONFIG="${BOOTSCRIPTS_SYSCONFIG:-/etc/sysconfig}"
SYSNET="${BOOTSCRIPTS_SYSNET:-/sys/class/net}"
fail=0
note() { echo "#  $*"; }
warn() { echo "!! $*"; fail=1; }
trim() { printf '%s' "${1:-}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'; }

# a path is tested, a bare name is looked up on PATH; ANY alternative counts,
# because a daemon that moved between /sbin and /usr/sbin is still installed
have_any() {
    local _c
    for _c in $(printf '%s' "${1:-}" | tr ',' ' '); do
        case "$_c" in
            -)  return 0 ;;
            /*) [ -e "$_c" ] && return 0 ;;
            *)  command -v "$_c" >/dev/null 2>&1 && return 0 ;;
        esac
    done
    return 1
}

[ -r "$CONF" ] || { warn "no $CONF to read"; exit 1; }

# ---- 1. the unpacked blfs-bootscripts tree --------------------------------
# It is a `tar` entry in services.stack, so its source sits in its package
# user's home like any other.  Newest wins: an older copy must not.
if [ -z "$SRC" ]; then
    for d in "$BASE"/*/blfs-bootscripts-* "$BASE"/blfs-bootscripts-*; do
        [ -f "$d/Makefile" ] || continue
        if [ -z "$SRC" ] || [ "$d" -nt "$SRC" ]; then SRC="$d"; fi
    done
fi
if [ -z "$SRC" ] || [ ! -f "$SRC/Makefile" ]; then
    warn "no unpacked blfs-bootscripts tree under $BASE -- nothing to install from"
    note "   unpack it again:"
    note "     packagemanager stack services --only blfs-bootscripts --run --force"
    exit 1
fi
note "bootscripts: $SRC"

# ---- 2. what is missing ---------------------------------------------------
targets=""; skipped=""; already=""; checks=""
while IFS= read -r raw || [ -n "$raw" ]; do
    case "$(trim "$raw")" in ""|\#*) continue ;; esac
    IFS='|' read -r f1 f2 f3 f4 <<< "$raw"
    pkg="$(trim "$f1")"; proof="$(trim "$f2")"
    tgts="$(trim "$f3")"; creates="$(trim "$f4")"
    case "$pkg" in package|user) continue ;; esac
    [ -n "$tgts" ] || continue
    if ! have_any "$proof"; then skipped="$skipped $pkg"; continue; fi
    if have_any "$creates"; then already="$already $pkg"; continue; fi
    note "$pkg is here, ${creates%%,*} is not -- $tgts"
    targets="$targets $tgts"
    checks="$checks$pkg|$creates
"
done < "$CONF"

[ -n "$already" ] && note "already installed:$already"
[ -n "$skipped" ] && note "package not installed, so no bootscript:$skipped"

# ---- 3. install them, as whoever owns the tree ----------------------------
# The first install ran as the package user, so /etc/rc.d/init.d and the rest
# are that user's.  Running make as root would work and leave root's files in
# a tree a package owns -- ownership is what says who installed what here, and
# it should keep saying it.  Root is the fallback, said out loud.
if [ -n "$targets" ]; then
    owner="$(stat -c %U "$SRC" 2>/dev/null || echo root)"
    note "make$targets   (as $owner)"
    ok=0
    if [ "$owner" != root ] && id "$owner" >/dev/null 2>&1; then
        su - "$owner" -c "cd $(printf '%q' "$SRC") && make$targets" && ok=1
        [ "$ok" = 1 ] || note "   as $owner that failed -- trying as root"
    fi
    if [ "$ok" != 1 ]; then
        ( cd "$SRC" && make$targets ) && ok=1
    fi
    [ "$ok" = 1 ] || warn "make$targets failed"
    # A MAKE THAT PRINTS NO ERROR IS NOT A FILE THAT EXISTS.  Ask the disk.
    while IFS='|' read -r pkg creates; do
        [ -n "${pkg:-}" ] || continue
        have_any "$creates" \
            && note "   now there: ${creates%%,*}  ($pkg)" \
            || warn "   $pkg: make ran, ${creates%%,*} still is not there"
    done <<< "$checks"
else
    note "every installed service already has its bootscript"
fi
echo

# ---- 4. dhcpcd needs one more thing, and it is not a bootscript -----------
# /lib/services/dhcpcd is not started by anything on its own, and BLFS has no
# init.d/dhcpcd at all.  The LFS `network` script reads /etc/sysconfig/
# ifconfig.* at boot and hands each interface to the service ITS file names --
# so a machine with dhcpcd installed and its service script in place still
# comes up with no address when no such file exists.  That is the whole of
# "my DHCP does not start automatically".
#
# WIRELESS IS NOT DONE HERE.  That file needs an SSID and a key, which nothing
# may invent; `check net-wifi` prints it for you to paste.  A WIRED file holds
# no secret at all -- interface, service, two flags -- so there is no reason to
# make anyone type it.
if [ "$DO_IFCONFIG" = yes ] && have_any "/lib/services/dhcpcd,/usr/lib/services/dhcpcd"; then
    wrote=0
    for d in "$SYSNET"/*; do
        [ -d "$d" ] || continue
        i="$(basename "$d")"
        [ "$i" = lo ] && continue
        if [ -e "$d/wireless" ] || [ -e "$d/phy80211" ]; then
            note "$i is wireless -- its file needs an SSID: check net-wifi"
            continue
        fi
        f="$SYSCONFIG/ifconfig.$i"
        if [ -e "$f" ]; then
            if grep -qE '^[[:space:]]*SERVICE=.?dhcpcd' "$f"; then
                note "$f already hands $i to dhcpcd"
            else
                note "$f exists and names another service -- left alone"
            fi
            continue
        fi
        mkdir -p "$SYSCONFIG"
        cat > "$f" <<EOF
# written by stacks/bootscripts.sh -- safe to delete
# $i takes its address from DHCP at boot.  ONBOOT="no" turns that off
# without removing the file; SERVICE names /lib/services/dhcpcd.
ONBOOT="yes"
IFACE="$i"
SERVICE="dhcpcd"
DHCP_START="-b -q"
DHCP_STOP="-k"
EOF
        chmod 644 "$f"; chown root:root "$f" 2>/dev/null
        note "wrote $f -- $i now asks for an address at boot"
        note "   without rebooting:  ifup $i"
        wrote=$((wrote + 1))
    done
    [ "$wrote" = 0 ] || note "$wrote interface file(s) written"
fi

echo
if [ "$fail" = 0 ]; then
    echo "# bootscripts: done."
    echo "#   what starts at boot:  ls /etc/rc.d/rc3.d"
    echo "#   wireless needs an SSID, which nothing here can write:"
    echo "#     packagemanager stack network --only net-wifi --run"
else
    echo "# the !! lines above need attention; everything else was applied."
fi
exit $fail

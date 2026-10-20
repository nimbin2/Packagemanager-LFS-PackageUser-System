#!/bin/bash
# net-wifi.sh -- REPORT what is still missing to bring a wireless link up.
# Builds nothing, writes nothing.  Every line names a file or a binary and
# says whether it is there.
#
# This exists because "wifi does not come up" has five separate causes on a
# SysV system and the error from `ifup` names at most one of them: no DHCP
# client, no ifconfig.<iface> file, a file named for the wrong interface, no
# per-SSID wpa_supplicant config, or a SERVICE= that no installed service
# script implements.
#
# THE SERVICE NAMES ARE READ OFF THE DISK, not remembered.  Which variable
# the wpa service uses to chain to a DHCP client differs between bootscript
# releases, and guessing it is how you get a link with no address.
# TWO KINDS OF FINDING, AND ONLY ONE OF THEM IS THE STACK'S FAULT.
#
# This check stopped the whole stack at 8 of 9 because no
# /etc/sysconfig/ifconfig.wlan0 existed -- a file that holds the user's SSID
# and cannot be built by anything here.  A step must not fail for work it
# was never going to do:
#   warn  something the stack should have installed  -> exit 1
#   todo  something only you can write               -> printed, exit 0
fail=0
warn() { echo "!! $*"; fail=1; }
did() { echo "++ $*"; }
todo() { echo "-> $*"; todos=$((todos + 1)); }
note() { echo "#  $*"; }
todos=0

# ---- 0. the settings ------------------------------------------------------
CONF="${NET_WIFI_CONF:-/etc/pkgusr/stacks/net-wifi.conf}"
[ -r "$CONF" ] && . "$CONF"
: "${WRITE:=no}"; : "${PREFER:=}"; : "${COPY_WPA:=no}"
: "${METRIC_PREFERRED:=100}"; : "${METRIC_OTHER:=300}"
: "${USB_RENAME:=no}"; : "${USB_NAME:=wl-ext}"
SYSCONF="${NET_WIFI_SYSCONF:-/etc/sysconfig}"
NETSYS="${NET_WIFI_SYSFS:-/sys/class/net}"
UDEVDIR="${NET_WIFI_UDEVDIR:-/etc/udev/rules.d}"
MARKER="# written by stacks/net-wifi.sh -- safe to delete, regenerated"
[ -r "$CONF" ] && note "settings: $CONF" || note "no $CONF -- reporting only"

# ---- 1. the binaries ------------------------------------------------------
for b in /sbin/wpa_supplicant /usr/sbin/wpa_supplicant; do
    [ -x "$b" ] && wpa="$b" && break
done
[ -n "${wpa:-}" ] || warn "no wpa_supplicant in /sbin or /usr/sbin"
command -v dhcpcd >/dev/null 2>&1 \
    || warn "no dhcpcd: a joined link will have no address (book: dhcpcd)"
command -v ip >/dev/null 2>&1 || command -v ifconfig >/dev/null 2>&1 \
    || warn "neither ip nor ifconfig is installed"

# ---- 1b. a stable name for the USB adapter --------------------------------
# Written before the interfaces are listed, because the name it gives is the
# one the rest of this script should be configuring.
_usb_rule="$UDEVDIR/80-wifi-$USB_NAME.rules"
case "$USB_RENAME" in yes|1|true)
    if [ -z "${USB_VENDOR:-}" ] || [ -z "${USB_PRODUCT:-}" ]; then
        warn "USB_RENAME=yes but USB_VENDOR/USB_PRODUCT are not set in $CONF"
    elif [ -e "$_usb_rule" ] && ! grep -qF "$MARKER" "$_usb_rule"; then
        note "$_usb_rule exists and is not ours -- left alone"
    else
        install -d "$UDEVDIR"
        cat > "$_usb_rule" <<RULE
$MARKER
# Name the $USB_VENDOR:$USB_PRODUCT wireless adapter "$USB_NAME" whatever port it
# is in.  Without this its name comes from its place on the bus (wlp7s0f4u2),
# which changes with the socket -- and /etc/sysconfig/ifconfig.<name> cannot
# follow that.
SUBSYSTEM=="net", ACTION=="add", ATTRS{idVendor}=="$USB_VENDOR", ATTRS{idProduct}=="$USB_PRODUCT", NAME="$USB_NAME"
RULE
        chmod 644 "$_usb_rule"
        did "wrote $_usb_rule  ($USB_VENDOR:$USB_PRODUCT -> $USB_NAME)"
        # IT DOES NOT APPLY TO AN INTERFACE THAT IS ALREADY THERE.  Renaming
        # happens when the device appears, so a plugged-in adapter keeps the
        # name it was given until it is unplugged or the machine reboots.
        if [ ! -e "$NETSYS/$USB_NAME" ] \
           && ls -1 "$NETSYS" 2>/dev/null | grep -q '^wl.*u[0-9]'; then
            note "   unplug the adapter and plug it back in to take the name"
            note "   (or reboot; udev renames a device when it APPEARS)"
        fi
    fi ;;
esac

# ---- 2. the interfaces the kernel actually has ----------------------------
# The name matters: ifconfig.<name> must match the interface, and predictable
# names (wlp3s0) are not the wlan0/wifi0 that examples use.
ifaces=""
for d in "$NETSYS"/*; do
    [ -e "$d/wireless" ] || [ -e "$d/phy80211" ] || continue
    ifaces="$ifaces $(basename "$d")"
done
if [ -z "$ifaces" ]; then
    todo "the kernel has no wireless interface at all"
    note "that is a driver or firmware problem, not a configuration one:"
    note "    lfs-kernel firmware --missing"
    exit 0
fi
note "wireless interface(s):$ifaces"

# ---- 3. the service scripts that exist ------------------------------------
svcdir=/lib/services
[ -d "$svcdir" ] || svcdir=/usr/lib/services
if [ -d "$svcdir" ]; then
    have_svc="$(ls -1 "$svcdir" 2>/dev/null | tr '\n' ' ')"
    note "services installed in $svcdir: $have_svc"
    case " $have_svc " in
        *" wpa "*) ;;
        *) warn "no '$svcdir/wpa' service: SERVICE=wpa cannot work"
           note "that script comes from blfs-bootscripts (services stack)" ;;
    esac
    case " $have_svc " in
        *" dhcpcd "*) ;;
        *) warn "no '$svcdir/dhcpcd' service: nothing will fetch an address"
           note "   the dhcpcd PACKAGE ships no service script -- it comes"
           note "   from blfs-bootscripts' install-service-dhcpcd target:"
           note "     packagemanager stack services --only blfs-bootscripts --run" ;;
    esac
    # WHERE THE SERVICE LOOKS FOR THE CONFIG -- ASK THE SCRIPT.
    #
    # This machine's boot said:
    #     wpa_supplicant configuration file
    #     /etc/sysconfig/wpa_supplicant-wlan0.conf not present   FAIL
    # ...while the file sat in /etc/sysconfig/wpa_supplicant/ -- the
    # SUBDIRECTORY, which is where other bootscript releases keep it.  So
    # wpa_supplicant never started, the card never associated, and dhcpcd
    # had nothing to ask for an address on.  Two directories, one word
    # apart, and no output anywhere said which one this machine reads.
    # The service script names it; read it rather than remember it.
    if [ -r "$svcdir/wpa" ]; then
        _wpa_pat="$(grep -ohE '/[A-Za-z0-9_./${}-]*wpa_supplicant[A-Za-z0-9_.${}-]*\.conf' \
                    "$svcdir/wpa" 2>/dev/null | head -n1)"
        if [ -n "$_wpa_pat" ]; then
            WPA_DIR="$(dirname "$_wpa_pat")"
            # NET_WIFI_SYSCONF overrides /etc/sysconfig (the tests use it);
            # a path read out of the service script has to follow it too.
            case "$WPA_DIR" in
                /etc/sysconfig*) WPA_DIR="$SYSCONF${WPA_DIR#/etc/sysconfig}" ;;
            esac
            note "the wpa service reads: $_wpa_pat"
            note "   -> $WPA_DIR/wpa_supplicant-<iface>.conf"
        fi
    fi
    # which variable the wpa service reads to chain onward -- from the script
    if [ -r "$svcdir/wpa" ]; then
        chain="$(grep -oE '\$\{?[A-Z_]*SERVICE[A-Z_]*' "$svcdir/wpa" \
                 | tr -d '${' | sort -u | grep -v '^SERVICE$' | tr '\n' ' ')"
        [ -n "$chain" ] \
            && note "the wpa service hands off using: $chain" \
            || note "the wpa service names no hand-off variable; it may start"
        [ -n "$chain" ] || note "dhcpcd itself, or expect a second ifconfig file"
    fi
else
    warn "no $svcdir: blfs-bootscripts is not installed"
fi

# A SECOND ADAPTER JOINS THE SAME NETWORKS.
#
# The wpa service reads wpa_supplicant-<iface>.conf, so a new interface has
# nothing to join with even though this machine has known the SSID and the
# key for months.  Copying your own file is the whole job; it is said out
# loud every time, because a key is being duplicated.
# The directory the SERVICE reads, when it told us; otherwise the one this
# script has always assumed.
_wpadir="${WPA_DIR:-$SYSCONF/wpa_supplicant}"
case "$COPY_WPA" in yes|1|true)
    for i in $ifaces; do
        _dst="$_wpadir/wpa_supplicant-$i.conf"
        [ -e "$_dst" ] && continue
        _srcconf=""
        # A CONFIG IN THE OTHER DIRECTORY IS STILL YOUR CONFIG.  The two
        # layouts -- /etc/sysconfig/wpa_supplicant-<iface>.conf and
        # /etc/sysconfig/wpa_supplicant/wpa_supplicant-<iface>.conf -- have
        # both been right at some point, and a machine can easily have the
        # file in the one its service does not read.
        for _c in "$_wpadir"/wpa_supplicant-*.conf \
                  "$SYSCONF"/wpa_supplicant-*.conf \
                  "$SYSCONF"/wpa_supplicant/wpa_supplicant-*.conf; do
            [ -r "$_c" ] || continue
            case "$(basename "$_c")" in *__*__*|*example*|*template*|*sample*) continue ;; esac
            grep -q 'psk\|key_mgmt=NONE' "$_c" 2>/dev/null || continue
            _srcconf="$_c"; break
        done
        [ -n "$_srcconf" ] || continue
        install -d -m 755 "$_wpadir"
        cp "$_srcconf" "$_dst" && chmod 600 "$_dst" \
            && did "copied $(basename "$_srcconf") -> $(basename "$_dst") (chmod 600; it holds your key)"
    done ;;
esac

# ---- 4. the per-interface configuration -----------------------------------
for i in $ifaces; do
    f="$SYSCONF/ifconfig.$i"
    # WHICH INTERFACE WINS.  The first PREFER pattern that matches something
    # this machine has gets the low metric; everything else gets the high
    # one, so an external antenna takes over while it is plugged in and the
    # card inside carries on when it is not.
    _metric="$METRIC_OTHER"
    for _p in $PREFER; do
        _hit=""
        for _c in $ifaces; do
            case "$_c" in $_p) _hit="$_c"; break ;; esac
        done
        [ -n "$_hit" ] || continue
        [ "$_hit" = "$i" ] && _metric="$METRIC_PREFERRED"
        break
    done
    if [ ! -r "$f" ] && [ "$WRITE" = yes ]; then
        _chain_var="$(printf '%s' "${chain:-WPA_SERVICE}" | awk '{print $1}')"
        install -d "$SYSCONF"
        cat > "$f" <<IFCFG
$MARKER
# $i -- what ifup reads.  No SSID and no key are in here; those live in
# $SYSCONF/wpa_supplicant/wpa_supplicant-$i.conf, which nothing writes for
# you.  -m <metric> decides which link the machine prefers when two are up:
# the lower number wins.
ONBOOT="yes"
IFACE="$i"
SERVICE="wpa"
${_chain_var:-WPA_SERVICE}="dhcpcd"
DHCP_START="-b -m $_metric"
DHCP_STOP="-k"
IFCFG
        chmod 644 "$f"
        did "wrote $f  (route metric $_metric$([ "$_metric" = "$METRIC_PREFERRED" ] && echo " -- preferred"))"
    fi
    if [ ! -r "$f" ]; then
        todo "write $f -- ifup $i has nothing to read"
        note "   or let this step do it:  WRITE=yes in $CONF"
        # THIS FILE HOLDS NO SECRET.  Only the wpa_supplicant conf does, so
        # there is no reason to make the reader work out the syntax: print
        # the file, with the interface that exists and the hand-off variable
        # this machine's wpa service actually reads.
        _chain_var="$(printf '%s' "${chain:-WPA_SERVICE}" | awk '{print $1}')"
        note "   it has no SSID and no key in it -- this is the whole file:"
        echo "       cat > $f << \"EOF\""
        echo "       ONBOOT=\"yes\""
        echo "       IFACE=\"$i\""
        echo "       SERVICE=\"wpa\""
        echo "       ${_chain_var:-WPA_SERVICE}=\"dhcpcd\""
        echo "       DHCP_START=\"-b\""
        echo "       DHCP_STOP=\"-k\""
        echo "       EOF"
        note "a file for a DIFFERENT interface will not do; these exist:"
        # the || never fired: the pipeline's status was sed's, not ls's, so an
        # empty listing printed nothing at all where it mattered most
        others="$(ls -1 /etc/sysconfig/ifconfig.* 2>/dev/null)"
        if [ -n "$others" ]; then
            printf '%s\n' "$others" | sed 's/^/#    /'
        else
            note "   (none at all)"
        fi
        continue
    fi
    # SERVICE must name a script that is installed
    for s in $(sed -n 's/^[[:space:]]*[A-Z_]*SERVICE[A-Z_]*=["'"'"']\{0,1\}\([a-z0-9-]*\).*/\1/p' "$f"); do
        [ -n "$s" ] || continue
        [ -x "$svcdir/$s" ] \
            && note "$f: SERVICE $s -> $svcdir/$s" \
            || warn "$f names service '$s', which is not in $svcdir"   # ours
    done
    grep -qE '^[[:space:]]*ONBOOT=.?yes' "$f" \
        || note "$f: ONBOOT is not yes, so boot will not bring it up"
    # THE HAND-OFF IS OPTIONAL, AND WITHOUT IT THERE IS NO ADDRESS.
    # services/wpa runs the next service only `if [ -n "${WPA_SERVICE}" ]`.
    # A file with SERVICE="wpa" alone associates perfectly and never starts
    # dhcpcd -- a connected radio with no address, and nothing in the boot
    # log says why, because nothing failed.
    _hv="$(printf '%s' "${chain:-WPA_SERVICE}" | awk '{print $1}')"
    if grep -qE '^[[:space:]]*SERVICE=.?wpa' "$f" \
       && ! grep -qE "^[[:space:]]*${_hv}=.?[a-z]" "$f"; then
        todo "$f: SERVICE=wpa with no $_hv -- it associates and never asks"
        note "   for an address.  Add these two lines to it:"
        note "     $_hv=\"dhcpcd\""
        note "     DHCP_START=\"-b\""
    fi
    # THE CONFIG THE SERVICE WILL LOOK FOR, FOR THIS INTERFACE.
    if grep -qE '^[[:space:]]*SERVICE=.?wpa' "$f"; then
        if [ -r "$_wpadir/wpa_supplicant-$i.conf" ]; then
            note "$f: wpa config $_wpadir/wpa_supplicant-$i.conf"
        else
            todo "no $_wpadir/wpa_supplicant-$i.conf -- at boot this reads:"
            note "     wpa_supplicant configuration file ... not present  FAIL"
            note "   and nothing associates, so dhcpcd has no link to ask on."
            _other="$(ls -1 "$SYSCONF"/wpa_supplicant-*.conf \
                            "$SYSCONF"/wpa_supplicant/wpa_supplicant-*.conf \
                            2>/dev/null | head -n1)"
            [ -n "$_other" ] \
                && note "   you have one for another interface: $_other" \
                && note "   cp '$_other' '$_wpadir/wpa_supplicant-$i.conf' && chmod 600 \$_" \
                || note "   wpa_passphrase '<SSID>' '<key>' > $_wpadir/wpa_supplicant-$i.conf"
        fi
    fi
    # dhcpcd IN THE FOREGROUND MISSES ITS OWN LINK.  A wireless interface
    # is up before it is associated; a dhcpcd without -b waits for a lease
    # that cannot arrive yet and the boot line says FAIL.  -b puts it in
    # the background, where it keeps trying and succeeds a second later.
    if grep -qE '^[[:space:]]*DHCP_START=' "$f" \
       && ! grep -qE '^[[:space:]]*DHCP_START=.*-b' "$f"; then
        todo "$f: DHCP_START has no -b, so dhcpcd waits for a lease it cannot"
        note "   have yet -- that is the 'Starting dhcpcd ... FAIL' at boot."
        note "   sed -i 's/^DHCP_START=.*/DHCP_START=\"-b\"/' '$f'"
    fi
    # OURS, AND NOW WRONG.  A file this step wrote may carry yesterday's
    # metric after PREFER changed; one of yours is never touched.
    if grep -qF "$MARKER" "$f" 2>/dev/null \
       && ! grep -qE "^DHCP_START=.*-m $_metric([^0-9]|$)" "$f"; then
        if [ "$WRITE" = yes ]; then
            cp -p "$f" "$f.bak-$(date +%Y%m%d-%H%M%S)"
            sed -i "s/^DHCP_START=.*/DHCP_START=\"-b -m $_metric\"/" "$f"
            did "$f: route metric is now $_metric"
        else
            todo "$f says another metric than PREFER does ($_metric)"
        fi
    fi
done

# A CONFIG FOR AN INTERFACE THAT IS NOT HERE.  After a rename (or a card
# taken out) its ifconfig file stays, and ifup at boot fails on a name the
# kernel does not have.  Named, never deleted: it may be the adapter you
# unplugged this morning.
for f in "$SYSCONF"/ifconfig.*; do
    [ -f "$f" ] || continue
    case "$f" in *.bak-*) continue ;; esac
    _n="$(basename "$f" | sed 's/^ifconfig\.//')"
    [ -e "$NETSYS/$_n" ] && continue
    grep -qE '^[[:space:]]*ONBOOT=.?yes' "$f" 2>/dev/null || continue
    # AT BOOT THIS IS A RED LINE ON THE SCREEN.
    #     Bringing up the eth0 interface... Interface eth0 doesn't exist. FAIL
    # The file is for a card that was taken out, an interface that was
    # renamed, or an adapter that is simply not plugged in right now -- so
    # it is never deleted here.  ONBOOT=no stops the boot from trying.
    if [ "${DISABLE_MISSING:-no}" = yes ]; then
        cp -p "$f" "$f.bak-$(date +%Y%m%d-%H%M%S)"
        sed -i 's/^[[:space:]]*ONBOOT=.*/ONBOOT="no"/' "$f"
        did "$f: $_n is not here -- ONBOOT=no (it was failing at every boot)"
        note "   bring it up by hand when it is:  ifup $_n"
    else
        todo "$f names $_n, which this kernel does not have -- it FAILS at boot"
        note "   removable, renamed, or gone?  Either delete the file, or:"
        note "     sed -i 's/^ONBOOT=.*/ONBOOT=\"no\"/' '$f'"
        note "   (DISABLE_MISSING=yes in $CONF does that for every one of them)"
    fi
done

# ---- 4b. the firewall: userspace and kernel must agree --------------------
# A legacy iptables binary on an nft-only kernel fails on every rule with
# "Module ip_tables not found", and an nft binary on a legacy-only kernel
# fails the other way.  Both halves are checkable, so check both rather than
# leaving it to the first boot that needs a rule.
if command -v iptables >/dev/null 2>&1; then
    _ipt="$(iptables --version 2>/dev/null)"
    case "$_ipt" in
        *nf_tables*) _ipt_kind=nft ;;
        *legacy*)    _ipt_kind=legacy ;;
        *)           _ipt_kind=unknown ;;
    esac
    note "iptables: $_ipt  -> $_ipt_kind"
    # what the kernel offers.  /proc/net/nf_tables exists when nf_tables is
    # loaded or built in; the module names are the fallback.
    _k_nft=no; _k_legacy=no
    { [ -e /proc/net/nf_tables ]       || grep -qw nf_tables /proc/modules 2>/dev/null       || [ -e "/lib/modules/$(uname -r)/kernel/net/netfilter/nf_tables.ko" ]       || [ -e "/lib/modules/$(uname -r)/kernel/net/netfilter/nf_tables.ko.xz" ]; }         && _k_nft=yes
    { grep -qw ip_tables /proc/modules 2>/dev/null       || [ -e "/lib/modules/$(uname -r)/kernel/net/ipv4/netfilter/ip_tables.ko" ]       || [ -e "/lib/modules/$(uname -r)/kernel/net/ipv4/netfilter/ip_tables.ko.xz" ]       || [ -d /proc/net/ip_tables_names ]       || [ -e /proc/net/ip_tables_names ]; }         && _k_legacy=yes
    note "kernel: nf_tables=$_k_nft  ip_tables(legacy)=$_k_legacy"
    if [ "$_ipt_kind" = legacy ] && [ "$_k_legacy" = no ]; then
        warn "a LEGACY iptables on a kernel with no ip_tables: every rule will fail"
        note "   rebuild it against nftables -- machine.conf already asks for it:"
        note "     [iptables]"
        note "     configure_args = --enable-nftables"
        note "     packagemanager update iptables --reinstall --regenerate --run --yes"
    elif [ "$_ipt_kind" = nft ] && [ "$_k_nft" = no ]; then
        warn "an nft iptables on a kernel with no nf_tables: every rule will fail"
        note "   add CONFIG_NF_TABLES (and NFT_COMPAT) to the kernel, or build"
        note "   iptables legacy-only by dropping --enable-nftables"
    elif [ "$_ipt_kind" = unknown ]; then
        todo "cannot tell which iptables this is: $_ipt"
    else
        note "iptables and the kernel agree"
    fi
fi
echo

# ---- 5. the wpa_supplicant configuration ----------------------------------
found_conf=""
for c in "$_wpadir"/wpa_supplicant-*.conf \
         "$SYSCONF"/wpa_supplicant-*.conf \
         "$SYSCONF"/wpa_supplicant/wpa_supplicant-*.conf \
         /etc/wpa_supplicant/wpa_supplicant*.conf /etc/wpa_supplicant.conf; do
    [ -r "$c" ] && found_conf="$found_conf $c"
done
if [ -z "$found_conf" ]; then
    todo "write a wpa_supplicant configuration: there is no SSID to join"
    note "    wpa_passphrase '<SSID>' '<passphrase>' \\"
    note "      > /etc/sysconfig/wpa_supplicant/wpa_supplicant-<iface>.conf"
    note "    chmod 600 that file"
else
    for c in $found_conf; do
        # A PLACEHOLDER NAME IS A TEMPLATE.  wpa_supplicant-__wifi0__.conf is
        # something's example, not a network you configured, and reporting it
        # as a broken config sends you to fix a file you should copy.
        case "$(basename "$c")" in
            *__*__*|*example*|*template*|*sample*)
                note "template: $c (copy it to wpa_supplicant-<iface>.conf)"
                continue ;;
        esac
        if grep -q 'psk\|key_mgmt=NONE' "$c" 2>/dev/null; then
            note "config: $c"
            # only a file that HOLDS a key can leak one.  Saying both "has no
            # psk" and "holds a key" about the same file, two lines apart, is
            # a contradiction the reader has to resolve.
            case "$(stat -c %a "$c" 2>/dev/null)" in
                *[4567]) todo "chmod 600 $c -- it holds a key and is world-readable" ;;
            esac
        else
            todo "$c has no psk and no key_mgmt=NONE: nothing to join with"
        fi
    done
fi

echo
if [ "$fail" != 0 ]; then
    echo "# the !! lines are this stack's to fix -- it stops here so they do"
    echo "# not get lost in the next package's output"
elif [ "$todos" -gt 0 ]; then
    echo "# $todos thing(s) left.  The interface file above has no secret in"
    echo "# it -- paste it as shown.  Only the wpa_supplicant config holds a"
    echo "# key, which is why nothing here writes that one for you."
    echo "# The stack is otherwise complete."
else
    echo "# wireless: the pieces are all in place; bring it up with"
    echo "#     ifup $(set -- $ifaces; echo "$1")"
    if [ -n "$PREFER" ]; then
        for _p in $PREFER; do
            for _c in $ifaces; do
                case "$_c" in $_p)
                    echo "#   preferred while it is there: $_c (metric $METRIC_PREFERRED)"
                    break 2 ;;
                esac
            done
        done
    fi
fi
# -> lines do not fail the step; !! lines do
exit $fail

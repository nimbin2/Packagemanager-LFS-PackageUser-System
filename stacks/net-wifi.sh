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
todo() { echo "-> $*"; todos=$((todos + 1)); }
note() { echo "#  $*"; }
todos=0

# ---- 1. the binaries ------------------------------------------------------
for b in /sbin/wpa_supplicant /usr/sbin/wpa_supplicant; do
    [ -x "$b" ] && wpa="$b" && break
done
[ -n "${wpa:-}" ] || warn "no wpa_supplicant in /sbin or /usr/sbin"
command -v dhcpcd >/dev/null 2>&1 \
    || warn "no dhcpcd: a joined link will have no address (book: dhcpcd)"
command -v ip >/dev/null 2>&1 || command -v ifconfig >/dev/null 2>&1 \
    || warn "neither ip nor ifconfig is installed"

# ---- 2. the interfaces the kernel actually has ----------------------------
# The name matters: ifconfig.<name> must match the interface, and predictable
# names (wlp3s0) are not the wlan0/wifi0 that examples use.
ifaces=""
for d in /sys/class/net/*; do
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

# ---- 4. the per-interface configuration -----------------------------------
for i in $ifaces; do
    f="/etc/sysconfig/ifconfig.$i"
    if [ ! -r "$f" ]; then
        todo "write $f -- ifup $i has nothing to read"
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
for c in /etc/sysconfig/wpa_supplicant/wpa_supplicant-*.conf \
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
fi
# -> lines do not fail the step; !! lines do
exit $fail

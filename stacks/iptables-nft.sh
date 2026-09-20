#!/bin/bash
# iptables-nft.sh -- point the generic iptables names at the nft backend.
#
# BUILDING NFTABLES SUPPORT DOES NOT SWITCH TO IT.  `--enable-nftables`
# produces BOTH backends and upstream's `make install` leaves the plain names
# on the legacy one:
#
#     /usr/sbin/iptables      -> xtables-legacy-multi
#     /usr/sbin/iptables-nft  -> xtables-nft-multi
#
# so `iptables --version` says (legacy), and on a kernel with no ip_tables
# every rule fails -- with a build log that says "nftables support: yes".
# Distributions flip these links (Debian with alternatives, Arch in the
# package); here it is this step.
#
# Reversible, and says how: the legacy binary is not removed, only unlinked
# from the generic name.
set -u

NFT=/usr/sbin/xtables-nft-multi
LEGACY=/usr/sbin/xtables-legacy-multi
fail=0
note() { echo "#  $*"; }
warn() { echo "!! $*"; fail=1; }

if [ ! -x "$NFT" ]; then
    warn "no $NFT -- iptables was built without nftables support"
    note "   add this to /etc/pkgusr/stacks/machine.conf:"
    note "     [iptables]"
    note "     configure_args = --enable-nftables"
    note "   then:  packagemanager update iptables --reinstall --regenerate --run --yes"
    exit 1
fi

# The generic names, and the per-family ones that go with them.  ebtables and
# arptables have no legacy build here, so they are already nft and are left
# alone.
changed=0
for n in iptables iptables-save iptables-restore \
         ip6tables ip6tables-save ip6tables-restore; do
    t="/usr/sbin/$n"
    if [ -L "$t" ] && [ "$(readlink "$t")" = "$(basename "$NFT")" ]; then
        note "$n already uses the nft backend"
        continue
    fi
    if [ -e "$t" ] && [ ! -L "$t" ]; then
        # A REAL FILE IS NOT OURS TO REPLACE.  Everything iptables installs
        # under these names is a symlink into one of the two multi binaries;
        # a regular file here is something else, and guessing is worse than
        # stopping.
        warn "$t is a real file, not a symlink -- left alone"
        note "   whatever installed it is not this iptables build; look at it"
        note "   before switching backends:  packagemanager which-package $t"
        continue
    fi
    if ln -sfn "$(basename "$NFT")" "$t"; then
        note "$n -> $(basename "$NFT")"
        changed=$((changed + 1))
    else
        warn "could not point $n at the nft backend"
    fi
done

# CONFIRM YOUR OWN EFFECT: the whole point is what --version prints.
echo
got="$(iptables --version 2>/dev/null)"
case "$got" in
    *nf_tables*) note "iptables now reports: $got" ;;
    *)
        warn "iptables still reports: ${got:-<nothing>}"
        note "   the links are set but the binary disagrees; check:"
        note "     ls -l /usr/sbin/iptables /usr/sbin/xtables-nft-multi"
        ;;
esac

if [ "$fail" = 0 ]; then
    echo "# iptables: nft backend, $changed link(s) changed."
    echo "#   the legacy binary is still there and still usable by name:"
    echo "#     iptables-legacy --version"
    echo "#   to go back:  ln -sfn xtables-legacy-multi /usr/sbin/iptables"
    echo "#   rules in /etc/rc.d/rc.iptables are read by either backend;"
    echo "#   the nft one needs CONFIG_NFT_COMPAT in the kernel."
else
    echo "# fix the !! lines above"
fi
exit $fail

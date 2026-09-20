#!/bin/bash
# power.sh -- delegate shutdown, reboot and suspend to a GROUP.
#
# A PACKAGE USER OWNS FILES, NOT IDENTITY.  halt, poweroff and reboot have to
# become root and are therefore root's, with a group deciding who may run
# them -- the same shape as seatd-<user> in mytools.  This step does only
# what a package user may not: the group, the membership, the setuid bits,
# and one boot script.
#
# WHAT UDEV CAN AND CANNOT DO.  A rule like
#     SUBSYSTEM=="power", KERNEL=="state", MODE="4550", GROUP="<g>"
# never fires: /sys/power/state is a kernel attribute, not a device with a
# uevent, so udev is never asked about it.  And the mode is wrong twice --
# setuid means nothing on a sysfs file, and 550 has no write bit, so a group
# member could not write `mem` to it even if the rule had applied.  The boot
# script below is what actually does the work; it is not a fallback.
set -u

fail=0
warn() { echo "!! $*"; fail=1; }
note() { echo "#  $*"; }

# ---- 1. the group ---------------------------------------------------------
# Named with the collector prefix, like every other group this system makes,
# and READ from the config rather than defaulted: reporting a built-in
# default as though it were the configured value is a bug this project has
# already paid for once.
grp="${POWER_GROUP:-}"
if [ -z "$grp" ]; then
    # packagemanager exports the RESOLVED prefix (lfs config, its own conf,
    # or the collector groups already on the system).  This parsed
    # packagemanager.conf as JSON -- it is key=value -- and found nothing.
    pfx="${LFS_COLLECTOR_PREFIX:-}"
    [ -z "$pfx" ] && pfx="$(sed -n 's/^collector_prefix=\(.*\)$/\1/p' \
                            /etc/pkgusr/packagemanager.conf 2>/dev/null | head -n1)"
    if [ -z "$pfx" ]; then
        warn "no collector prefix: not in the environment, not in /etc/pkgusr/packagemanager.conf"
        note "set it once:      packagemanager config --collector-prefix <prefix>"
        note "or the group:     POWER_GROUP=<name> packagemanager stack services --only power --run"
        exit 1
    fi
    grp="${pfx%_}_power"
fi
# IN THE COLLECTOR RANGE.  A system-range groupadd took gid 997, the only
# collector-prefixed group outside 90000+.  packagemanager places it.
if getent group "$grp" >/dev/null 2>&1; then
    note "group $grp exists"
else
    packagemanager sysgroup create "$grp" >/dev/null 2>&1 || true
    getent group "$grp" >/dev/null 2>&1 \
        || { warn "could not create the group $grp"; exit 1; }
    note "created group $grp (gid $(getent group "$grp" | cut -d: -f3))"
fi

# ---- 2. who is in it ------------------------------------------------------
u="${LFS_DESKTOP_USER:-}"
[ -z "$u" ] && [ -r /etc/pkgusr/desktop-user ] && u="$(head -n1 /etc/pkgusr/desktop-user)"
if [ -n "$u" ] && id "$u" >/dev/null 2>&1; then
    if id -nG "$u" 2>/dev/null | tr ' ' '\n' | grep -qx "$grp"; then
        note "$u is already in $grp"
    else
        usermod -aG "$grp" "$u" || warn "could not add $u to $grp"
        # CONFIRM YOUR OWN EFFECT: usermod has returned 0 and changed nothing
        # on this project before, three times.
        id -nG "$u" 2>/dev/null | tr ' ' '\n' | grep -qx "$grp" \
            && note "added $u to $grp (they must log in again for it to count)" \
            || warn "usermod said nothing, and $u is still not in $grp"
    fi
else
    note "no desktop user known; add members by hand:  usermod -aG $grp <name>"
fi

# ---- 3. the binaries ------------------------------------------------------
# 4550 root:<group>: setuid root, and only group members may execute it.
# Anything not installed is skipped -- pm-utils is not in the book, and
# shutdown is a symlink in some sysvinit builds.
# A SYMLINK IS ITS TARGET.  poweroff and reboot are links to halt; stat
# without -L read the link (777 p_sysvinit) and called it a failure while
# halt, the file they point to, was already right.
did=0
seen=" "
for b in /usr/bin/halt /usr/bin/poweroff /usr/bin/reboot /usr/bin/pm-suspend \
         /usr/bin/pm-hibernate /sbin/halt /sbin/poweroff /sbin/reboot; do
    [ -f "$b" ] || continue
    b="$(readlink -f "$b")" || continue
    case "$seen" in *" $b "*) continue ;; esac
    seen="$seen$b "
    case "$(stat -c '%a %U:%G' "$b" 2>/dev/null)" in
        "4550 root:$grp") note "$(basename "$b") already 4550 root:$grp"; continue ;;
    esac
    chown "root:$grp" "$b" && chmod 4550 "$b" || { warn "could not set up $b"; continue; }
    got="$(stat -c '%a %U:%G' "$b" 2>/dev/null)"
    if [ "$got" = "4550 root:$grp" ]; then
        note "$b -> 4550 root:$grp"
        did=$((did + 1))
    else
        warn "$b reads '$got', not '4550 root:$grp'"
        warn "   (a nosuid mount cannot hold a setuid bit: findmnt -T $b)"
    fi
done
[ "$did" = 0 ] && note "no binary needed changing"

# ---- 4. the boot script ---------------------------------------------------
# /sys and /run are made fresh on every boot, so the ownership has to be
# re-applied on every boot.  ONE file, symlinked into the runlevel -- a
# second copy under rc3.d is a second place to edit, and they drift.
init=/etc/rc.d/init.d/power-perms
if [ ! -d /etc/rc.d/init.d ]; then
    warn "no /etc/rc.d/init.d: the bootscripts are not installed"
    note "build them first:  packagemanager stack services --run"
else
    cat > "$init" << EOF
#!/bin/sh
# power-perms -- give $grp the kernel's power interface, every boot.
#
# Installed by stacks/power.sh.  /sys and /run do not survive a reboot, so
# neither do these modes; this is the only thing that re-applies them.
### BEGIN INIT INFO
# Provides:            power-perms
# Required-Start:
# Should-Start:        \$local_fs
# Required-Stop:
# Default-Start:       S
# Short-Description:   group access to suspend and hibernate
### END INIT INFO

GRP="$grp"
LOCKDIR=/run/pm-utils/locks
STORAGE=/run/pm-utils/pm-suspend/storage
LOGFILE=/var/log/pm-suspend.log

case "\$1" in
  start)
    for d in "\$LOCKDIR" "\$STORAGE"; do
        [ -d "\$d" ] || mkdir -p "\$d" || continue
        chown "root:\$GRP" "\$d" && chmod 2775 "\$d"
    done
    # 0660, not 0550: writing "mem" to it IS the suspend.
    for f in /sys/power/state /sys/power/disk; do
        [ -e "\$f" ] || continue
        chown "root:\$GRP" "\$f" && chmod 0660 "\$f"
    done
    if [ -f "\$LOGFILE" ]; then
        chgrp "\$GRP" "\$LOGFILE" && chmod 0664 "\$LOGFILE"
    fi
    ;;
  status)
    for f in /sys/power/state /sys/power/disk "\$LOCKDIR" "\$STORAGE"; do
        [ -e "\$f" ] && printf '%s  %s\n' "\$(stat -c '%a %U:%G' "\$f")" "\$f"
    done
    ;;
  stop|restart|reload) ;;
  *) echo "Usage: \$0 {start|status}"; exit 1 ;;
esac
exit 0
EOF
    chmod 754 "$init"
    note "wrote $init"
    # The sysinit runlevel, because /sys/power/state exists from the first
    # moment and a suspend attempt can come before any runlevel finishes.
    # LFS's bootscripts call it rcS.d (inittab: `rc S`); rcsysinit.d is
    # the old name, and the only one this looked for.
    linked=0
    for d in /etc/rc.d/rcS.d /etc/rc.d/rcsysinit.d; do
        [ -d "$d" ] || continue
        ln -sf ../init.d/power-perms "$d/S99power-perms"
        note "linked $d/S99power-perms"
        linked=1
        break
    done
    [ "$linked" = 1 ] || warn "no /etc/rc.d/rcS.d (or rcsysinit.d) to link it into"
    "$init" start && note "applied now, without waiting for a reboot"
fi

# ---- 5. rules that cannot fire -------------------------------------------
# Removed, not explained.  /sys/power/state has no uevent, and /run/bootlog
# is a file the bootscripts write, not a device: neither line was ever
# applied.  power-perms does the first one's work.
for r in /etc/udev/rules.d/*.rules; do
    [ -r "$r" ] || continue
    grep -qE 'KERNEL=="(state|bootlog)"' "$r" 2>/dev/null || continue
    sed -i -E '/KERNEL=="(state|bootlog)"/d' "$r"
    note "removed the state/bootlog lines from $r (they never matched)"
    grep -q '[^[:space:]]' "$r" || { rm -f "$r"; note "  $r was empty -- removed"; }
done

echo
if [ "$fail" = 0 ]; then
    echo "# power: $grp may halt, reboot and suspend"
    echo "#   check after a reboot:  $init status"
    [ -n "$u" ] && echo "#   $u must log out and in before the group counts"
else
    echo "# fix the !! lines above"
fi
exit $fail

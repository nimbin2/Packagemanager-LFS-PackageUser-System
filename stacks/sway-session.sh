#!/bin/bash
# sway-session.sh -- wire the session together (root step, idempotent).
set -u
# The desktop user: LFS_DESKTOP_USER, or what mytools.sh recorded in
# /etc/pkgusr/desktop-user -- one answer for both scripts.  (LFS_HOME_USER
# is still honoured for old invocations.)  Unknown = skip the config
# skeleton below, nothing else here needs it.
HOME_USER="${LFS_DESKTOP_USER:-${LFS_HOME_USER:-}}"
[ -z "$HOME_USER" ] && [ -r /etc/pkgusr/desktop-user ] \
    && HOME_USER="$(head -n1 /etc/pkgusr/desktop-user)"
[ -n "$HOME_USER" ] && printf '%s\n' "$HOME_USER" > /etc/pkgusr/desktop-user
HOME_DIR="/home/${HOME_USER:-nobody-set}"

# 1. one launcher: a dbus session around sway.
#
# The seat comes from seatd, not elogind: elogind only registers a session
# through pam_elogind, and Linux-PAM is not on this system, so a tty login
# has no logind session for libseat to find.  Saying the backend explicitly
# means libseat does not try logind first and fail with a puzzling message.
cat > /usr/bin/sway-session <<'LAUNCH'
#!/bin/bash
# start sway inside a dbus session; run from a plain tty login
export XDG_CURRENT_DESKTOP=sway
export LIBSEAT_BACKEND=seatd

# The seat comes from seatd-user: a setuid wrapper compiled for one username,
# installed as /usr/bin/seatd-<user> by the mytools step.  No daemon runs at
# boot and there is no `seat` group, so check for the wrapper instead.
# (It said /bin here while mytools installs to /usr/bin -- on a system where
#  /bin is a symlink to /usr/bin that works by accident, and on one where it
#  is not it reports a missing file that exists.)
if ! command -v "seatd-$(id -un)" >/dev/null 2>&1; then
    echo "sway-session: seatd-$(id -un) is not on PATH -- nothing will give" >&2
    echo "  sway a seat.  As root:  packagemanager stack services --run --only mytools" >&2
    echo "  (or use your own launcher: sway_start)" >&2
    exit 1
fi
# INPUT DEVICES COME FROM UDEV, NOT FROM /dev.
#
# libinput enumerates through libudev, which reads /run/udev -- so in a
# chroot without the host's /run bind-mounted there are no input devices at
# all, and the failure names libinput rather than the chroot:
#     libinput initialization failed, no input devices
#     Failed to start backend
# The compositor is fine; it has nothing to listen to.
if [ ! -d /run/udev ]; then
    echo "sway-session: /run/udev is missing, so libinput will find no input" >&2
    echo "  devices and the backend will fail.  Two causes:" >&2
    echo "    * a chroot -- udev's database lives in the host's /run." >&2
    echo "      Boot the system, or bind-mount /run and /dev into the chroot." >&2
    echo "    * udev is not running -- check /etc/rc.d/init.d/udev status" >&2
    echo "  To prove the REST works anyway, with no keyboard or mouse:" >&2
    echo "    WLR_LIBINPUT_NO_DEVICES=1 sway_start" >&2
    exit 1
fi
# ...and a compositor needs the VT it was started from.  Started from a
# different tty than the one seatd bound, it opens nothing.
if [ -n "${XDG_VTNR:-}" ] && [ -r /sys/class/tty/tty0/active ]; then
    _active="$(cat /sys/class/tty/tty0/active 2>/dev/null)"
    if [ -n "$_active" ] && [ "$_active" != "tty$XDG_VTNR" ]; then
        echo "sway-session: you are on tty$XDG_VTNR but $_active is the active" >&2
        echo "  console.  Switch to it and start sway there." >&2
        exit 1
    fi
fi

if [ -z "${XDG_RUNTIME_DIR:-}" ]; then
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
    mkdir -p "$XDG_RUNTIME_DIR" 2>/dev/null && chmod 700 "$XDG_RUNTIME_DIR"
fi
exec dbus-run-session -- sway "$@"
LAUNCH
chmod 755 /usr/bin/sway-session

# 2. pipewire on demand, not at boot
cat > /usr/bin/pipewire-start <<'PW'
#!/bin/bash
# start pipewire + wireplumber for this session, if not already up
pgrep -x pipewire >/dev/null || { pipewire & disown; }
pgrep -x wireplumber >/dev/null || { wireplumber & disown; }
echo "# pipewire is up (pipewire-pulse socket in $XDG_RUNTIME_DIR)"
PW
chmod 755 /usr/bin/pipewire-start

# 3. a sway config skeleton for the desktop user, only if none exists
if [ -d "$HOME_DIR" ] && [ ! -f "$HOME_DIR/.config/sway/config" ]; then
    mkdir -p "$HOME_DIR/.config/sway"
    cp /etc/sway/config "$HOME_DIR/.config/sway/config" 2>/dev/null || true
    {
        echo ""
        echo "# --- added by the sway stack ---"
        echo "exec swbr"
        echo "# audio when needed:  exec pipewire-start"
        echo 'bindsym Mod4+b exec minibrowser'
        echo 'bindsym Mod4+a exec swas'
        echo 'bindsym Mod4+Tab exec swov'
    } >> "$HOME_DIR/.config/sway/config"
    chown -R "$HOME_USER:" "$HOME_DIR/.config/sway" 2>/dev/null || true
    echo "# wrote $HOME_DIR/.config/sway/config"
fi
[ -n "$HOME_USER" ] || echo "# no desktop user known (LFS_DESKTOP_USER unset, no /etc/pkgusr/desktop-user): sway config skeleton skipped"
echo "# session wired: log in on a tty and run: sway  (alias for sway_start)"

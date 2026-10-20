#!/bin/bash
# kernel-sway.sh -- VERIFY the running kernel carries what sway + webkit need.
# Builds nothing; a missing feature fails the stack with its name.
fail=0
need() {  # need <config-option> <why>
    local cfg="" opt="$1" why="$2"
    for c in /proc/config.gz "/boot/config-$(uname -r)" /boot/config; do
        [ -r "$c" ] && cfg="$c" && break
    done
    if [ -z "$cfg" ]; then
        echo "!! cannot read a kernel config (/proc/config.gz or /boot/config*)"
        echo "   enable CONFIG_IKCONFIG_PROC, or place the config in /boot"
        exit 1
    fi
    case "$cfg" in
        *.gz) zgrep -qE "^$opt=(y|m)" "$cfg" ;;
        *)    grep  -qE "^$opt=(y|m)" "$cfg" ;;
    esac || { echo "!! $opt is not set -- $why"; fail=1; }
}
need CONFIG_DRM               "no DRM: no wayland compositor"
need CONFIG_DRM_AMDGPU        "the amdgpu KMS driver (radeonsi machines)"
need CONFIG_INPUT_EVDEV       "libinput reads /dev/input/event*"
need CONFIG_SND               "sound core"
need CONFIG_SECCOMP           "webkit's sandbox"
need CONFIG_USER_NS           "webkit's sandbox (bubblewrap)"
need CONFIG_TMPFS             "XDG_RUNTIME_DIR lives on tmpfs"
# THE SOFTWARE RENDERER NEEDS ITS OWN KERNEL OPTION.  The book's mesa page:
# "For llvmpipe or softpipe, CONFIG_DRM_VGEM is required or X clients will
# fail".  Without it the software fallback that exists to save you when the
# hardware path fails cannot be used either -- and the symptom is the same
# "failed to create dri2 screen".  A note, not a failure: a machine that
# never falls back does not need it.
# `need` fails the stack; this one only reports, so it reads the config the
# same way rather than inventing a second reader.
want() {  # want <config-option> <why>
    local cfg="" opt="$1" why="$2"
    for c in /proc/config.gz "/boot/config-$(uname -r)" /boot/config; do
        [ -r "$c" ] && cfg="$c" && break
    done
    [ -n "$cfg" ] || return 0
    if case "$cfg" in
           *.gz) zgrep -qE "^$opt=(y|m)" "$cfg" ;;
           *)    grep  -qE "^$opt=(y|m)" "$cfg" ;;
       esac
    then echo "#  $opt is set -- $why"
    else echo "-> $opt is NOT set -- $why"
    fi
}
want CONFIG_DRM_VGEM "the book: llvmpipe/softpipe need it or X clients fail"
# runtime, not config: the render node must exist
[ -e /dev/dri/renderD128 ] || { echo "!! no /dev/dri/renderD* render node"; fail=1; }
[ "$fail" = 0 ] && echo "# kernel: everything sway + webkit need is present"
exit $fail

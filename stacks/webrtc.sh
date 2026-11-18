#!/bin/bash
# AI-modified: Claude Opus 5.5 (1.14.426)
# webrtc.sh -- REPORT what the browser needs for a call and a camera.
# Builds nothing, writes nothing.  Every line names a thing and says whether
# it is there.
#
# WHY THIS EXISTS.  gst-plugins-bad always builds libgstwebrtc-1.0.so, so
# `packagemanager verify` is clean and the file list looks complete -- while
# the webrtcbin ELEMENT, which is what a browser loads, is compiled only if
# libnice was installed at configure time.  The browser says
#     GstWebRTC plugin not found.  Make sure to install gst-plugins-bad
#     >= 1.20 with the webrtc plugin enabled.
# and nothing on the system disagrees with it.  A library present is not a
# feature present, and only the element registry knows the difference.
set -u

fail=0; todos=0
warn() { echo "!! $*"; fail=1; }
todo() { echo "-> $*"; todos=$((todos + 1)); }
note() { echo "#  $*"; }

have_el() { gst-inspect-1.0 "$1" >/dev/null 2>&1; }

if ! command -v gst-inspect-1.0 >/dev/null 2>&1; then
    warn "no gst-inspect-1.0: gstreamer itself is not installed"
    exit 1
fi
note "gstreamer: $(gst-inspect-1.0 --version 2>/dev/null | sed -n 2p)"
echo

# ---- 1. the elements a call is made of -----------------------------------
# element|what it is for|which package builds it|which library it needs
while IFS='|' read -r el what pkg lib; do
    [ -n "$el" ] || continue
    if have_el "$el"; then
        note "$el  ($what)"
        continue
    fi
    warn "$el is MISSING -- $what"
    note "   it comes from $pkg, and only if $lib was installed first"
    note "   rebuild:  packagemanager stack sway --only $pkg --run"
done <<'ELEMENTS'
webrtcbin|the WebRTC session itself|gst10-plugins-bad|libnice
dtlssrtpenc|DTLS key exchange|gst10-plugins-bad|openssl
srtpenc|encrypted media transport|gst10-plugins-bad|libsrtp
sctpenc|WebRTC data channels|gst10-plugins-bad|usrsctp
opusenc|the audio codec every call negotiates|gst10-plugins-base|opus
vp8enc|the video codec every call negotiates|gst10-plugins-good|libvpx
avdec_h264|decoding H.264 (most video on the web)|gst10-libav|ffmpeg
x264enc|ENCODING H.264 -- what a camera site needs to publish|gst10-plugins-ugly|x264 and -D gpl=enabled
openh264enc|the other H.264 encoder, used by some sites|gst10-plugins-bad|openh264 (install it, then REBUILD -bad)
v4l2src|the camera|gst10-plugins-good|v4l-utils
alsasrc|the microphone|gst10-plugins-base|alsa-lib
ELEMENTS
echo

# ---- 1b. nice to have, not required -------------------------------------
# gst-plugins-rs is not a BLFS page and not everyone builds it, so a missing
# element here is a note, never a failure: the chain works without it.
for el in webrtcsink webrtcsrc gtk4paintablesink audiornnoise; do
    if have_el "$el"; then
        note "$el  (gst-plugins-rs)"
    else
        todo "$el is absent -- gst-plugins-rs is not built (optional)"
        [ "$el" = audiornnoise ] && note "   (noise suppression for a microphone in a call)"
    fi
done
echo

# ---- 2. the libraries, so a missing element says WHY ---------------------
for pc in nice libsrtp2 usrsctp vpx opus webrtc-audio-processing-2 \
          gstreamer-webrtc-1.0; do
    if pkg-config --exists "$pc" 2>/dev/null; then
        note "$pc $(pkg-config --modversion "$pc" 2>/dev/null)"
    else
        todo "$pc is not installed (pkg-config cannot see it)"
    fi
done
echo

# ---- 3. the camera itself -------------------------------------------------
# A device node that exists is not a device you may read: on this system the
# video group is what decides, and a browser is run by a person.
cams="$(ls -1 /dev/video* 2>/dev/null)"
if [ -z "$cams" ]; then
    todo "no /dev/video* -- no camera now (driver not loaded, switched off, or no firmware)"
    note "   fine if you load the driver by hand (webcam enable);"
    note "   otherwise check:  lfs-kernel firmware --missing"
else
    for c in $cams; do
        note "$c  $(stat -c '%a %U:%G' "$c")"
    done
    u="${LFS_DESKTOP_USER:-}"
    [ -z "$u" ] && [ -r /etc/pkgusr/desktop-user ] && u="$(head -n1 /etc/pkgusr/desktop-user)"
    if [ -n "$u" ]; then
        if id -nG "$u" 2>/dev/null | tr ' ' '\n' | grep -qx video; then
            note "$u is in the video group"
        else
            todo "$u is not in the video group: usermod -aG video $u"
        fi
    fi
fi
echo

# ---- 4. what the browser was built with ----------------------------------
# webkitgtk's own switches are not introspectable at run time, so read the
# generated script that built it -- the record of what was asked for.
wk="$(ls -1d /usr/src/pkgusr/p_webkitgtk/install_last 2>/dev/null | head -n1)"
if [ -r "$wk" ]; then
    for opt in ENABLE_WEB_RTC ENABLE_MEDIA_STREAM USE_GSTREAMER_WEBRTC; do
        if grep -q -- "$opt=ON" "$wk" 2>/dev/null; then
            note "webkitgtk: $opt=ON"
        else
            todo "webkitgtk was not built with $opt=ON"
            note "   add it under [webkitgtk] in /etc/pkgusr/stacks/machine.conf,"
            note "   then: packagemanager stack sway --only webkitgtk --run  (hours)"
        fi
    done
else
    note "no /usr/src/pkgusr/p_webkitgtk/install_last: cannot say what the"
    note "   browser was built with"
fi

# WHEN WAS IT BUILT, AND WITH WHAT AROUND IT.  A script generated by an older
# blfs than the libraries beside it was configured before they existed --
# which is exactly how this package came to have no webrtc element.
#
# THE BUILD'S TIME, NOT THE SCRIPT'S.  gst-plugins-bad was built minutes
# after libnice 0.1.23 -- it needs >= 0.1.23 to configure at all -- and was
# still reported as "built BEFORE libnice": install_last is a copy of a
# script generated earlier, and keeps that script's time.
# .pkgusr-installed is written when a build FINISHES.  And the element is
# the real answer: when webrtcbin is registered, nothing is missing.
for pkgdir in /usr/src/pkgusr/p_gst10-plugins-bad /usr/src/pkgusr/p_webkitgtk; do
    sc="$pkgdir/install_last"
    [ -r "$sc" ] || continue
    gen="$(sed -n 's/.*generated by blfs \([0-9.]*\).*/\1/p' "$sc" | head -n1)"
    [ -n "$gen" ] || continue
    built="$pkgdir/.pkgusr-installed"
    [ -e "$built" ] || built="$sc"
    case "$pkgdir" in
        */p_gst10-plugins-bad)
            if gst-inspect-1.0 webrtcbin >/dev/null 2>&1; then
                note "$(basename "$pkgdir"): script from blfs $gen, webrtcbin present"
                continue
            fi ;;
    esac
    if [ -e /usr/lib/pkgconfig/nice.pc ] \
       && [ "$built" -ot /usr/lib/pkgconfig/nice.pc ]; then
        warn "$(basename "$pkgdir") was built BEFORE libnice was installed"
        warn "   (its script is older than nice.pc), so its optional"
        warn "   features were detected as absent.  Rebuild it."
    else
        note "$(basename "$pkgdir"): script from blfs $gen"
    fi
done

echo
if [ "$fail" != 0 ]; then
    echo "# the !! lines are missing features, not missing files: the package"
    echo "# is installed and was configured without them.  Rebuilding it now"
    echo "# picks them up, because the libraries are there this time."
elif [ "$todos" -gt 0 ]; then
    echo "# $todos optional piece(s) absent; a call will work without some of"
    echo "# them (data channels, echo cancellation) and not without others."
    echo "# The stack is otherwise complete."
else
    echo "# the whole chain is here: camera, microphone, codecs, transport."
fi
exit $fail

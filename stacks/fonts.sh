#!/bin/bash
# fonts.sh -- icon, patched and Noto fonts, from release archives.
#
# None of these is a BLFS page, so the URLs and versions are OURS to keep
# true -- the same deal as gst-plugins-rs.  Each line below is one font set:
#
#     <name>|<url>|<glob of font files inside the archive>
#
# WHAT WAS CHECKED, AND HOW.  Every URL here answered `wget --spider` from
# the machine this was written on.  The Noto ones are individual faces from
# noto-fonts' hinted tree: the release-asset zips this first used
# (notofonts.github.io/.../Noto_Sans.zip) do not exist -- that repository
# publishes per-script archives under names this did not guess, and guessing
# cost a run.  Six faces, fetched directly, are smaller than the zips anyway.
#
# A line can still go stale.  When one does it fails on ITS OWN line with the
# URL printed, the others carry on, and the step says so at the end.  Fix the
# line and run it again; what is installed is skipped.
#
# The same name may appear more than once -- each line is one file, and they
# accumulate in the same directory.
#
# THREE UNPACKERS, WHICHEVER IS THERE.  bsdtar (libarchive) reads zip as
# happily as tar; unzip may not be installed at all (BLFS's UnZip is a
# separate page and nothing here requires it); python3 always is, because
# packagemanager is written in it.  Depending on exactly one of the three is
# how a font step fails on a system that could perfectly well unpack the
# archive.
set -u

FONTDIR=/usr/share/fonts
fail=0
note() { echo "#  $*"; }
warn() { echo "!! $*"; fail=1; }

fonts() {
    cat <<'FONTS'
fontawesome|https://github.com/FortAwesome/Font-Awesome/releases/download/6.7.2/fontawesome-free-6.7.2-desktop.zip|*otfs/*.otf
nerd-symbols|https://github.com/ryanoasis/nerd-fonts/releases/download/v3.3.0/NerdFontsSymbolsOnly.zip|*.ttf
nerd-jetbrains|https://github.com/ryanoasis/nerd-fonts/releases/download/v3.3.0/JetBrainsMono.zip|*.ttf
noto-sans|https://github.com/googlefonts/noto-fonts/raw/main/hinted/ttf/NotoSans/NotoSans-Regular.ttf|NotoSans-Regular.ttf
noto-sans|https://github.com/googlefonts/noto-fonts/raw/main/hinted/ttf/NotoSans/NotoSans-Bold.ttf|NotoSans-Bold.ttf
noto-sans|https://github.com/googlefonts/noto-fonts/raw/main/hinted/ttf/NotoSans/NotoSans-Italic.ttf|NotoSans-Italic.ttf
noto-serif|https://github.com/googlefonts/noto-fonts/raw/main/hinted/ttf/NotoSerif/NotoSerif-Regular.ttf|NotoSerif-Regular.ttf
noto-serif|https://github.com/googlefonts/noto-fonts/raw/main/hinted/ttf/NotoSerif/NotoSerif-Bold.ttf|NotoSerif-Bold.ttf
noto-mono|https://github.com/googlefonts/noto-fonts/raw/main/hinted/ttf/NotoSansMono/NotoSansMono-Regular.ttf|NotoSansMono-Regular.ttf
noto-emoji|https://github.com/googlefonts/noto-emoji/raw/main/fonts/NotoColorEmoji.ttf|NotoColorEmoji.ttf
FONTS
}

unpack() {   # unpack <archive> <into>
    if command -v bsdtar >/dev/null 2>&1 && bsdtar -xf "$1" -C "$2" 2>/dev/null; then
        return 0
    fi
    case "$1" in
        *) if command -v unzip >/dev/null 2>&1 \
                && unzip -qo "$1" -d "$2" 2>/dev/null; then return 0; fi ;;
    esac
    if command -v tar >/dev/null 2>&1 && tar -xf "$1" -C "$2" 2>/dev/null; then
        return 0
    fi
    python3 - "$1" "$2" <<'PYUNPACK' 2>/dev/null
import sys, zipfile, tarfile
src, dst = sys.argv[1], sys.argv[2]
if zipfile.is_zipfile(src):
    zipfile.ZipFile(src).extractall(dst)
else:
    tarfile.open(src).extractall(dst)
PYUNPACK
}

installed=0
while IFS='|' read -r name url glob; do
    [ -n "$name" ] || continue
    dest="$FONTDIR/$name"
    # ALREADY THERE IS DONE.  This step runs on every stack replay, and
    # re-downloading a font nobody changed is time spent for nothing.
    if [ -d "$dest" ] && [ -n "$(ls -A "$dest" 2>/dev/null)" ]; then
        note "$name: already installed ($(ls -1 "$dest" | wc -l) file(s))"
        continue
    fi
    tmp="$(mktemp -d)"
    note "$name: fetching $(basename "$url")"
    if ! wget -q -O "$tmp/archive" "$url"; then
        warn "$name: could not download"
        note "   $url"
        rm -rf "$tmp"; continue
    fi
    # a bare .ttf is not an archive: NotoColorEmoji is published as the font
    case "$url" in
        *.ttf|*.otf)
            mkdir -p "$tmp/x" && cp "$tmp/archive" "$tmp/x/$(basename "$url")" ;;
        *)
            mkdir -p "$tmp/x"
            if ! unpack "$tmp/archive" "$tmp/x"; then
                warn "$name: downloaded, but nothing here could unpack it"
                note "   is $url still an archive?  $(stat -c %s "$tmp/archive") bytes"
                rm -rf "$tmp"; continue
            fi ;;
    esac
    # find -path, NOT a shell glob.  `*` does not cross a `/`, so
    # `*otfs/*.otf` could never match
    # fontawesome-free-6.7.2-desktop/otfs/fa-solid-900.otf -- the archive
    # everyone actually publishes, with one directory at the top.  find's
    # -path does cross slashes, and then one pattern covers both layouts.
    files="$(cd "$tmp/x" && find . -type f -path "*/$glob" -o -type f -path "./$glob" 2>/dev/null | head -400)"
    if [ -z "$files" ]; then
        warn "$name: nothing matched '$glob' in the archive"
        note "   what it contains: $(cd "$tmp/x" && ls -1 | head -5 | tr '\n' ' ')"
        rm -rf "$tmp"; continue
    fi
    install -v -d -m755 "$dest" >/dev/null
    ( cd "$tmp/x" && printf '%s\n' "$files" | while IFS= read -r ff; do
          [ -n "$ff" ] && cp -f "$ff" "$dest/"
      done ) 2>/dev/null \
        || { warn "$name: could not copy into $dest"; rm -rf "$tmp"; continue; }
    chmod 644 "$dest"/* 2>/dev/null
    note "$name: $(ls -1 "$dest" | wc -l) file(s) -> $dest"
    installed=$((installed + 1))
    rm -rf "$tmp"
done < <(fonts)

# ONE CACHE REBUILD, AT THE END.  fc-cache per font set is the same work
# repeated, and a font that is present but uncached is a font nothing can
# find -- which looks exactly like a font that is not installed.
if [ "$installed" -gt 0 ]; then
    note "rebuilding the font cache"
    fc-cache -f >/dev/null 2>&1 || warn "fc-cache failed; fonts are installed but not indexed"
fi

# CONFIRM YOUR OWN EFFECT: fontconfig has to be able to see them.
echo
for want in "Font Awesome" "Symbols Nerd Font" "Noto Sans"; do
    if fc-list 2>/dev/null | grep -qi "$want"; then
        note "fontconfig sees: $want"
    else
        echo "-> fontconfig does not see '$want' yet"
    fi
done

echo
if [ "$fail" = 0 ]; then
    echo "# fonts: done.  $(fc-list 2>/dev/null | wc -l) font file(s) known to fontconfig"
else
    echo "# the !! lines are URLs or archive layouts that have moved."
    echo "# Each one is a single line in this script's table; fix it and"
    echo "# run the step again -- what is installed is skipped."
fi
exit $fail

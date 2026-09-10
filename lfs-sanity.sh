#!/bin/bash
# lfs-sanity.sh -- read-only survey of an lfs-pkgusr tree.
#
# Run it INSIDE the chroot, as root.  It changes nothing: no chown, no chmod,
# no files created outside the report.  Everything lands in ONE file so it can
# be handed over whole.
#
#   ./lfs-sanity.sh                  -> /tmp/lfs-sanity.txt
#   ./lfs-sanity.sh /path/report.txt
#
# Each section says what it checks and what a hit MEANS, so the report is
# readable on its own.

OUT="${1:-/tmp/lfs-sanity.txt}"
: > "$OUT" || { echo "cannot write $OUT" >&2; exit 1; }
exec 3>&1 1>>"$OUT" 2>&1

PKGROOT="${LFS_PKGUSR_ROOT:-/usr/src/pkgusr}"
CFGROOT="${LFS_CFGUSR_ROOT:-/usr/src/cfg}"
STATE="${LFS_PKGUSR_DIR:-${LFS_SRC_ROOT:-/usr/src}/lfs-pkgusr}"
hits=0
# the package-user prefix, as the tools compute it
PFX="$(sed -n 's/^pkgusr_prefix=\(.*\)$/\1/p' /etc/pkgusr/packagemanager.conf 2>/dev/null | head -1)"
PFX="${PFX:-p}"; PFX="${PFX%_}_"

sec() { echo; echo "=============================================================="; \
        echo "== $*"; echo "=============================================================="; }
# One colour rule, same as every other tool here: red is a problem, green is a
# clean result, plain is information.  The report is often read in a hurry,
# scrolled fast, or grepped -- a problem that is not red is a problem missed.
# Colour only on a terminal, so the saved report file stays clean text.
if [ -t 1 ]; then
    _C_ERR=$'\033[0;31m'; _C_OK=$'\033[0;32m'; _C_OFF=$'\033[0m'
else
    _C_ERR=""; _C_OK=""; _C_OFF=""
fi
note(){ echo "   $*"; }
hit() { echo "${_C_ERR}!! $*${_C_OFF}"; hits=$((hits+1)); }

echo "lfs-pkgusr sanity report -- $(date '+%Y-%m-%d %H:%M:%S')"
echo "host: $(uname -srm)"
echo "roots: PKGROOT=$PKGROOT  CFGROOT=$CFGROOT  STATE=$STATE"

sec "0. tool versions  (host and chroot copies must MATCH)"
# A stale chroot copy running old code has cost more debugging time in this
# project than anything else, which is why each tool prints a build id.
for t in lfs-helper lfs packagemanager blfs; do
    if command -v "$t" >/dev/null 2>&1; then
        printf '   %-22s %s\n' "$t" \
            "$("$t" --version 2>/dev/null | head -1 || echo '(no --version)')"
    else
        note "$(printf '%-22s NOT INSTALLED' "$t")"
    fi
done

# Is the build finished?
#
# The sticky bit means opposite things on either side of that line.  DURING the
# build it is a bug -- package users could not replace the temporary system's
# files.  AFTER it, seal-install-dirs is supposed to have set it, and its
# ABSENCE is the bug.  Reporting one rule for both flagged six directories on a
# completed 105/105 tree where every one of them was correct.
BUILD_FINISHED=0
if [ -f "$STATE/progress/steporder" ] && [ -f "$STATE/progress/steps-built" ]; then
    _todo="$(grep -c . "$STATE/progress/steporder" 2>/dev/null)"
    _done="$(grep -c . "$STATE/progress/steps-built" 2>/dev/null)"
    [ -n "$_todo" ] && [ "$_todo" -gt 0 ] && [ "${_done:-0}" -ge "$_todo" ] \
        && BUILD_FINISHED=1
fi

sec "1. shared directories: owner, group and mode"
[ "$BUILD_FINISHED" = 1 ] \
    && note "the build is finished, so install directories SHOULD be sticky" \
    || note "the build is not finished, so install directories should NOT be sticky yet"
# Install dirs are root:install and group-writable DURING the build, and only
# become sticky (o+t) at the very end.  Sticky early stops package users
# writing into shared directories for the rest of chapter 8.
# /sources and /build are different: book 3.1 makes them root:root 1777.
for d in / /usr /usr/bin /usr/lib /usr/share /usr/include /etc \
         /usr/src "$PKGROOT" "$CFGROOT" /sources /build /bin /sbin /lib; do
    [ -e "$d" ] || continue
    printf '   %-22s %-16s %s%s\n' "$d" \
        "$(stat -c '%U:%G' "$d" 2>/dev/null)" \
        "$(stat -c '%A' "$d" 2>/dev/null)" \
        "$([ -L "$d" ] && echo '   (symlink)')"
done
echo
for d in /usr /usr/bin /usr/lib /usr/share /usr/include; do
    [ -d "$d" ] || continue
    [ -L "$d" ] && continue
    m="$(stat -c %A "$d" 2>/dev/null)"
    [ "${m:5:1}" = w ] || hit "$d is NOT group-writable ($m) -- package users cannot install"
    case "$m" in
        *t) [ "$BUILD_FINISHED" = 1 ] \
                || hit "$d is already STICKY ($m) -- sealed before the build finished" ;;
        *)  [ "$BUILD_FINISHED" = 1 ] \
                && hit "$d is NOT sticky ($m) -- the build finished but the seal never fired" ;;
    esac
    # THE GROUP, not just the mode.
    #
    # This section printed owner:group from the start and only ever checked the
    # mode.  A tree ran 34 packages with every install directory at root:root
    # 775 -- group-writable, but group `root`, and package users are in
    # `install`.  The scheme was inert and the report said nothing, because the
    # one column that would have shown it was decoration.
    g="$(stat -c %G "$d" 2>/dev/null)"
    o="$(stat -c %U "$d" 2>/dev/null)"
    [ "$g" = install ] || hit "$d is group '$g', want 'install' -- package users cannot write here"
    [ "$o" = root ] || hit "$d is owned by '$o', want 'root' -- a package has taken a shared directory"
done
for d in /usr/src "$PKGROOT" "$CFGROOT"; do
    [ -d "$d" ] || continue
    case "$(stat -c %A "$d" 2>/dev/null)" in
        *t) [ "$BUILD_FINISHED" = 1 ] \
                || hit "$d is STICKY -- the seal fired early (it belongs at the end)" ;;
    esac
done
for d in /sources /build; do
    [ -d "$d" ] || continue
    o="$(stat -c '%U:%G' "$d")"; m="$(stat -c %A "$d")"
    [ "$o" = "root:root" ] || hit "$d is $o -- book 3.1 says root:root"
    [ "$m" = "drwxrwxrwt" ] || hit "$d is $m -- book 3.1 says 1777"
done

sec "2. ids: uid must equal gid, and nothing may share an id"
# Ownership is stored as a NUMBER.  Two names on one id makes files report as
# the wrong package and a package unable to write its own files.
awk -F: '$3>=1000 && $3!=$4 {printf "!! %s has uid %s but gid %s\n", $1,$3,$4}' /etc/passwd
awk -F: '$3>=1000 && $3!=$4' /etc/passwd | grep -q . \
    && hits=$((hits+1)) || note "every account has uid == gid"
d="$(awk -F: '{print $3}' /etc/passwd | sort | uniq -d)"
if [ -n "$d" ]; then
    hit "duplicate UIDs: $(echo $d)"
    for u in $d; do awk -F: -v u="$u" '$3==u{print "     "$1" uid "$3}' /etc/passwd; done
else
    note "no duplicate uids"
fi
d="$(awk -F: '{print $3}' /etc/group | sort | uniq -d)"
[ -n "$d" ] && hit "duplicate GIDs: $(echo $d)" || note "no duplicate gids"

sec "3. account names: every one should carry its prefix"
# Three kinds, three prefixes: p_ packages, cfg_ config steps, u_ application
# users.  Anything else escaped the naming scheme -- created before it landed,
# or by a path that bypasses pkg_owner_name.
#
# There is no tmp_ and no init_.  A temporary step is the same package chapter 8
# rebuilds and is built as that package's user, so it is a p_.  An init step
# owns no files and gets no account at all.  Either prefix appearing here means
# a tool created an account it should not have.
# nobody is 65534 and belongs to the system, not to us -- cap the range
bad="$(awk -F: '$3>=10000 && $3<65000 {print $1}' /etc/passwd \
       | grep -v '^p_\|^u_\|^cfg_')"
if [ -n "$bad" ]; then
    hit "accounts without a known prefix:"; printf '     %s\n' $bad
else
    note "every account >= 10000 carries a prefix"
fi

# One account, ONE prefix.  `p_cfg_bootscripts` wore both: the package prefix
# stacked on the config step's own.  Nothing creates those any more, so finding
# one means a tool is still applying the package prefix regardless of kind.
stacked="$(awk -F: '$3>=10000 && $3<65000 {print $1}' /etc/passwd \
           | grep '^p_cfg_\|^p_u_\|^p_p_')"
if [ -n "$stacked" ]; then
    hit "accounts wearing two prefixes:"; printf '     %s\n' $stacked
else
    note "no account carries more than one prefix"
fi
note "counts: $(awk -F: '$3>=10000 && $3<65000' /etc/passwd | wc -l) build accounts"

sec "4. homes: each must be owned by its own user"
# A home owned by root cannot be written by the package user that lives in it.
n=0
for d in "$PKGROOT"/*/ "$CFGROOT"/*/; do
    [ -d "$d" ] || continue
    b="$(basename "$d")"; o="$(stat -c %U "$d" 2>/dev/null)"
    if ! id "$b" >/dev/null 2>&1; then
        echo "   ?  $d  has no matching account (stray directory)"
    elif [ "$o" != "$b" ]; then
        echo "!! $d  owned by '$o', want '$b'"; n=$((n+1))
    fi
done
[ "$n" -gt 0 ] && { hit "$n home(s) not owned by their user"; \
    note "repair: lfs-helper verify --fix"; } || note "every home is owned by its user"

sec "5. files owned by a uid with NO name"
# The sharp version of the /sources problem: a uid that resolves to nothing is
# unambiguous, whereas a uid that resolves to the WRONG name looks fine.
# /tmp, /build, /sources AND every package's unpacked source tree are scratch:
# nothing there has to have an owner.  Build trees moved from /build into each
# package user's home, and this scan did not follow -- so a finished tree filled
# the report with tcl's own documentation:
#     !! files with no owner (first 40):
#          /usr/src/pkgusr/p_tcl/src/tcl8.6.16/html/Keywords/Z.htm
# A tarball can carry any uid it likes.  Unpacked sources are not installed,
# nothing owns them, and asking who does has no answer.
o="$(find / -xdev \( -path /tmp -o -path /build -o -path /sources \
        -o -path "$STATE" \
        -o -path "$PKGROOT/*/src" -o -path "$CFGROOT/*/src" \) -prune \
     -o -xdev \( -nouser -o -nogroup \) -print 2>/dev/null | head -40)"
if [ -n "$o" ]; then
    hit "files with no owner (first 40):"; printf '     %s\n' $o
else
    note "every file resolves to a real user and group"
fi

sec "6. groups: install and the collectors"
getent group install 2>/dev/null | sed 's/^/   /' \
    || hit "no 'install' group -- shared directories cannot work"
getent group install 2>/dev/null | awk -F: '$3!=9999{print "!! install is gid "$3", want 9999"}'
c="$(getent group 2>/dev/null | awk -F: '$3>=90000' | wc -l)"
note "$c collector group(s) in the 90000+ range"
# same cap as the accounts: nogroup is 65534 and belongs to the system.
#
# COUNTED, not just printed.  This awk wrote its own "!!" line and never
# touched $hits, so a report that flagged
#     !! group nimgnu_p_openssl (gid 10093) is outside every convention
# ended with "no problems found by these checks".  A summary that disagrees
# with the body teaches you to skip the summary.
_badgrp="$(getent group 2>/dev/null \
    | awk -F: '$3>=10000 && $3<65000 && $1 !~ /^p_|^u_|^cfg_/ {print $1" (gid "$3")"}')"
if [ -n "$_badgrp" ]; then
    hit "group(s) outside every convention -- collector groups belong at 90000+:"
    printf '     %s\n' $_badgrp
fi

sec "7. how much of the tree still belongs to root"
# Root-owned files under the install dirs are normally the temporary system's,
# waiting to be adopted.  A large number late in the build means adoption is
# not running.
for d in /usr/bin /usr/lib /usr/share /usr/include /etc; do
    [ -d "$d" ] || continue
    printf '   %-16s %6s root-owned of %6s total\n' "$d" \
        "$(find "$d" -xdev -type f -user root 2>/dev/null | wc -l)" \
        "$(find "$d" -xdev -type f 2>/dev/null | wc -l)"
done

sec "8. build state"
# The state directory is sorted: progress/ holds what the build has done.
# Reading the old flat paths reported `adopted.list: MISSING (the adoption gate
# will never close)` on a tree where adoption had completed perfectly.
PROG="$STATE/progress"
[ -f "$PROG/steporder" ] && note "steps in order: $(grep -c . "$PROG/steporder")"
if [ -f "$PROG/steps-built" ]; then
    _nb="$(grep -c . "$PROG/steps-built")"
    _no="$(grep -c . "$PROG/steporder" 2>/dev/null || echo 0)"
    note "steps built: $_nb"
    # More built than exist means the progress file remembers steps the current
    # step order no longer has -- usually one removed from the tools since this
    # tree was generated (last-step, refind).  Harmless, but it makes "104 of
    # 105" arithmetic wrong for the rest of the build.
    if [ "$_nb" -gt "$_no" ] 2>/dev/null; then
        note "  ($((_nb - _no)) built step(s) are not in the current order --"
        note "   left over from a step removed since; clear with: lfs-helper undone <name>)"
    fi
fi
[ -d "$STATE/manifests" ] && note "manifests: $(ls -1 "$STATE/manifests"/*.files 2>/dev/null | wc -l)"
[ -f "$PROG/adopted.list" ] \
    && note "adopted.list: $(grep -c . "$PROG/adopted.list") entries" \
    || note "adopted.list: MISSING (the adoption gate will never close)"
# A manifest whose owner does not exist can never be adopted.
#
# An EMPTY manifest is not that.  A prose configuration step -- cfg_clock,
# cfg_hosts, cfg_locale -- writes into files another package already owns, so
# its manifest legitimately records nothing and it legitimately has no account.
# Reporting those listed fourteen findings on a perfect tree:
#     ?  manifest 'cfg_clock' -> no account 'cfg_clock'
# which is noise, and noise is what makes a real finding easy to miss.
for m in "$STATE"/manifests/*.files; do
    [ -e "$m" ] || continue
    b="$(basename "${m%.files}")"
    case "$b" in last-step|init-*|refind|pkgusr) continue ;; esac
    # nothing installed -> nothing to own
    grep -q . "$m" 2>/dev/null || continue
    # Manifests are named by STEP ("bash", "gcc-pass1", "python-tmp"); accounts
    # are named by OWNER ("p_bash").  Comparing the two directly reported every
    # manifest in the tree as orphaned.  Apply the same mapping the tools do:
    # prefix, lowercase, fold -tmp/-passN.
    a="$(printf '%s' "$b" | tr 'A-Z' 'a-z' | sed 's/-tmp$//; s/-pass[0-9]$//')"
    case "$a" in cfg_*|p_*) ;; *) a="${PFX}${a}" ;; esac
    id "$a" >/dev/null 2>&1 && continue
    # Last resort: ask the tool who owns the files.  A step can install under a
    # name that is not its own -- libstdcpp's files belong to p_gcc, because the
    # book builds it out of the gcc tree -- and only lfs-helper knows that.
    _f="$(grep -m1 . "$m")"
    _own=""
    command -v lfs-helper >/dev/null 2>&1 && [ -e "$_f" ] \
        && _own="$(stat -c %U "$_f" 2>/dev/null)"
    case "$_own" in
        p_*|cfg_*)
            note "manifest '$b' -> no account '$a', but its files belong to '$_own'" ;;
        root)
            # A configuration step that writes ROOT-owned files.  cfg_clock
            # writes /etc/adjtime, cfg_hosts writes /etc/hosts: root's files,
            # by design, and the step has no account because it installs no
            # software.  There is nothing here that adoption could ever want,
            # so reporting it listed eleven findings on a perfect tree.
            : ;;
        *) echo "   ?  manifest '$b' -> no account '$a'" ;;
    esac
done
command -v lfs-helper >/dev/null 2>&1 && { echo; echo "--- lfs-helper list ---"; \
    lfs-helper list 2>&1 | tail -25; }

sec "SUMMARY"
if [ "$hits" -eq 0 ]; then
    echo "   ${_C_OK}no problems found by these checks${_C_OFF}"
else
    echo "   ${_C_ERR}$hits problem area(s) flagged above -- search this file for '!!'${_C_OFF}"
fi
echo
echo "Nothing was changed.  This report is read-only."

exec 1>&3
echo "wrote $OUT  ($hits problem area(s) flagged)"
echo "hand over with:  cat $OUT"

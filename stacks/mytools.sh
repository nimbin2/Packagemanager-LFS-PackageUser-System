#!/bin/bash
# mytools.sh -- install everything of your own under ONE package user.
#
# The work is in stacks/mytools/install_mytools, an ordinary package-user
# script: p_mytools owns the files, pkg.lst records them, `verify` lists it,
# and `packagemanager remove mytools` takes it all away again.  This step
# only does the two things a package user may not do itself: create the
# account, and set the setuid bit on the seatd wrapper.
set -u

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/mytools/install_mytools"
[ -f "$script" ] || { echo "!! missing $script"; exit 1; }

u="${LFS_DESKTOP_USER:-}"
[ -z "$u" ] && [ -r /etc/pkgusr/desktop-user ] && u="$(head -n1 /etc/pkgusr/desktop-user)"
if [ -z "$u" ] || ! id "$u" >/dev/null 2>&1; then
    echo "!! no desktop user.  seatd-user is compiled for ONE username."
    echo "     useradd -m -G audio,video,input,wheel <name> && passwd <name>"
    echo "     LFS_DESKTOP_USER=<name> packagemanager stack services --run"
    exit 1
fi
printf '%s\n' "$u" > /etc/pkgusr/desktop-user
echo "# desktop user: $u"

# 1. the account, named after the person: p_<user>.  Their software, their
#    name -- `verify`, pkg.lst and `packagemanager remove` all say it.
pkg="${MYTOOLS_NAME:-$u}"
acct="p_$pkg"
if ! id "$acct" >/dev/null 2>&1; then
    packagemanager add-user "$pkg" || {
        echo "!! could not create the package user '$pkg'"; exit 1; }
fi

# 2. CLEAR THE WAY FOR THE WRAPPER.
#
# /usr/bin is sticky (drwxrwxr-t), so only a file's owner may replace it --
# and once step 3 below has made seatd-<user> root-owned and setuid, the
# package user can no longer overwrite it:
#     install: cannot remove '/usr/bin/seatd-n76310': Operation not permitted
# Root can, and root is running this.  Remove it before the build so the
# package user writes a fresh one, and step 3 puts the bit back.
w="/usr/bin/seatd-$u"
if [ -e "$w" ] && [ "$(stat -c %U "$w")" != "$acct" ]; then
    rm -f "$w" && echo "# removed the old $w (root-owned; the build replaces it)"
fi

# 3. THE HOME MUST BE WHERE EVERY TOOL LOOKS.
#
# add_package_user (the hint's helper) puts a new account's home at
# /usr/src/<acct>, without the pkgusr/ component, and pm-install then works
# there while `verify` scans /usr/src/pkgusr -- so the package installs and
# is reported "not installed", with its pkg.lst in a directory nothing reads.
# fix-home is the repair; run it before anything else touches the account.
lfs-helper fix-home "$acct" --run >/dev/null 2>&1 || true
canon="/usr/src/pkgusr/$acct"
real="$(getent passwd "$acct" | cut -d: -f6)"
if [ "$real" != "$canon" ]; then
    echo "!! $acct's home is $real, but every tool looks in $canon."
    echo "   Repair it, then re-run this step:"
    echo "     lfs-helper fix-home $acct --run"
    exit 1
fi

# 4. REFRESH THE HOME COPY.
#
# pm-install prefers the script already in the package home (1.14.21): an
# edit there survives, which is right for a book page someone tweaked.  But
# THIS script is shipped and updated by releases, and the home copy is a
# stale duplicate -- the run kept using an old one and the fixes never took
# effect.  Root owns this decision: copy when they differ.
home_script="$(getent passwd "$acct" | cut -d: -f6)/$(basename "$script")"
if [ -f "$home_script" ] && ! cmp -s "$script" "$home_script"; then
    install -m 755 -o "$acct" -g "$acct" "$script" "$home_script" \
        && echo "# refreshed $home_script from the shipped copy"
fi

# 5. build and install as that user, through the one runner
DESKTOP_USER="$u" MYTOOLS_NAME="$pkg" lfs-helper pm-install "$acct" "$script" || exit 1

# 6. the setuid bit: root's job, refused to the package user on purpose
if [ -f "$w" ]; then
    chown root:"$u" "$w" && chmod 4750 "$w" \
        && echo "# $w  -> $(stat -c '%a %U:%G' "$w")"
else
    echo "!! $w was not installed -- see the build output above"
    exit 1
fi

# 7. `sway` should start the wrapper
home="$(getent passwd "$u" | cut -d: -f6)"
if ! grep -qs "alias sway=" "$home/.bashrc" 2>/dev/null; then
    printf "\n# start sway through the wrapper\nalias sway='sway_start'\n" >> "$home/.bashrc"
    chown "$u:$u" "$home/.bashrc"
    echo "# added  alias sway='sway_start'  to $home/.bashrc"
fi
# 8. the manifest must exist where verify reads it, or the package is
#    installed and invisible
if [ ! -s "$canon/pkg.lst" ]; then
    echo "!! $canon/pkg.lst is missing or empty -- the files were installed"
    echo "   but nothing records them, so verify will say 'not installed'."
    echo "     packagemanager reload-pkg-list $pkg"
    exit 1
fi
echo "# $(grep -c . "$canon/pkg.lst") file(s) recorded in $canon/pkg.lst"
echo "# done -- everything of yours is owned by $acct:"
echo "#     packagemanager verify | grep $pkg"
echo "#     cat /usr/src/pkgusr/$acct/pkg.lst"

#!/bin/bash
# shadow-pam.sh -- make `su` actually use PAM, and put the setuid bits back.
#
# TWO THINGS THAT ONLY MAKE SENSE TOGETHER.
#
# Linux-PAM installs a library and changes nothing: until shadow is REBUILT
# against it, nothing reads /etc/pam.d at all -- so `su - u_claude` keeps
# asking for a password however right /etc/pam.d/su_u_user is.  The book's
# own Linux-PAM page ends with "You should now reinstall the Shadow
# package", and that is this step.
#
# And rebuilding shadow strips the setuid bit from /usr/bin/su, because the
# BLFS page never sets it (the LFS page does).  Warning about that and
# leaving it is no good: `su` is broken either way, and the fix is a mode.
# So the bits come from setid.conf and are APPLIED here.
#
# Both halves are idempotent and both check their own effect: pam linkage by
# `ldd`, the modes by reading them back.
set -u

CONF="${SETID_CONF:-/etc/pkgusr/stacks/setid.conf}"
PM="${SHADOW_PAM_PM:-packagemanager}"
SU="${SHADOW_PAM_SU:-/usr/bin/su}"
fail=0
note() { echo "#  $*"; }
warn() { echo "!! $*"; fail=1; }

# Defined before BOTH steps use them: step 1 asked _pam_installed forty
# lines above where it was defined, which under `set -u` is a command that
# does not exist yet -- the config would silently never be written.
_su_has_pam() { ldd "$SU" 2>/dev/null | grep -q 'libpam\.so'; }
_pam_installed() { [ -e /usr/lib/libpam.so ] || [ -e /lib/libpam.so ]; }

# CONFIG BEFORE REBUILD, AND THAT ORDER IS THE WHOLE POINT.
#
# The first version rebuilt shadow and THEN wrote /etc/pam.d.  Between the
# two, su links libpam and has no service file -- and every build in this
# system runs as its package user through `su - p_<pkg>`, so that window is
# one where NOTHING can be built, including the very configure phases that
# would write the missing files.  Root's own `su` survives it only because
# pam_rootok is sufficient.
#
# So: write the config while su still works, then rebuild.  A system that
# stops midway is then left with pam config and a non-pam su -- harmless --
# rather than a pam su and no config.

# ---- 1. the pam config files su will read --------------------------
# A PAM-LINKED su WITH NO /etc/pam.d/su IS WORSE THAN A NON-PAM ONE:
#
#     su: pam_start: error 26          (PAM_ABORT -- no service file)
#
# `update` runs install, not configure, and those files are written by the
# CONFIGURE phase of linux-pam (/etc/pam.d/system-auth and friends) and
# shadow (/etc/pam.d/su, login, passwd, chage...).  So a rebuild leaves su
# linked against a library with nothing to read.
# THE SET THE BOOK WRITES, NOT A SAMPLE OF IT.
#
# This checked su and system-auth.  Both existed, so it said "in place"
# while login, passwd, chage and twelve admin tools had no file:
#     passwd: pam_start() failed, error 26
#     login: PAM Failure, aborting
# Two files out of sixteen.  The set now comes from the same place the files
# do: the package's configure_pkg, generated from the book.  Every
# /etc/pam.d/<n> it names is expected, and a `for VAR in a b c` loop that
# writes /etc/pam.d/${VAR} contributes a, b and c.  Commented (skipped)
# lines are not the book's commands and are not counted.
PAM_PKGS="${SHADOW_PAM_PKGS:-linux-pam shadow}"
PAM_DIR="${SHADOW_PAM_DIR:-/etc/pam.d}"

HELPER="${SHADOW_PAM_HELPER:-lfs-helper}"
# ONE READER OF WHAT A SCRIPT WRITES.  1.14.262 had its own awk here; the
# lease in lfs-helper (1.14.263) needs the same list for every package, so
# this asks it.  Names under /etc/pam.d, one per line.
_book_pam_set() {       # $1 = generated install script
    $HELPER script-targets "$1" configure_pkg 2>/dev/null \
        | sed -n 's|^/etc/pam\.d/||p' | sort -u
}

# THE SCRIPT ON DISK MAY BE THE PROBLEM.  Shadow's was generated before
# blfs read sub-sections, so its configure phase is prose and a bare `:` --
# it names no pam file, and `script configure` would run it again and write
# nothing.  So: read the script that is there; if it names no pam file,
# regenerate it (an edited copy is kept as .edited) and read that.  A script
# that is already right is never regenerated just because this step ran.
_fetch_script() {       # $1 = package, $2 = optional --regenerate -> path
    $PM script fetch "$1" ${2:-} 2>/dev/null \
        | sed 's/\x1b\[[0-9;]*m//g' \
        | sed -n 's/^script: //p; s/^already there: //p' | tail -1
}

_missing_pam=""
_want_pam=""
_scripts=""
if _pam_installed; then
    for _cfgpkg in $PAM_PKGS; do
        _sp_path="$(_fetch_script "$_cfgpkg")"
        _set=""
        [ -f "$_sp_path" ] && _set="$(_book_pam_set "$_sp_path" | tr '\n' ' ')"
        if [ -z "$(printf '%s' "$_set" | tr -d ' ')" ]; then
            note "$_cfgpkg's script names no $PAM_DIR file -- regenerating it from the book"
            _sp_path="$(_fetch_script "$_cfgpkg" --regenerate)"
            [ -f "$_sp_path" ] && _set="$(_book_pam_set "$_sp_path" | tr '\n' ' ')"
        fi
        if [ -z "$_sp_path" ] || [ ! -f "$_sp_path" ]; then
            warn "could not get $_cfgpkg's install script -- cannot tell what it writes"
            note "   by hand:  packagemanager script fetch $_cfgpkg --regenerate"
            continue
        fi
        _scripts="$_scripts $_cfgpkg=$_sp_path"
        if [ -z "$(printf '%s' "$_set" | tr -d ' ')" ]; then
            # a pam package whose configure names no pam file is the bug
            # this check exists for, not an empty requirement
            warn "$_cfgpkg's configure phase writes no $PAM_DIR file"
            note "   the generator dropped them -- look at configure_pkg in $_sp_path"
            continue
        fi
        _want_pam="$_want_pam $_set"
        for _n in $_set; do
            [ -f "$PAM_DIR/$_n" ] || _missing_pam="$_missing_pam $_n"
        done
    done
fi

if _pam_installed && [ -n "$_want_pam" ]; then
    if [ -z "$_missing_pam" ]; then
        note "all $(echo $_want_pam | wc -w) $PAM_DIR files the book writes are in place"
    else
        note "missing from $PAM_DIR:$_missing_pam"
        note "   running the CONFIGURE phases that write them (update installs;"
        note "   it does not configure)"
        # THE su TRAP.  Shadow's page writes $PAM_DIR/su too, WITHOUT the
        # pam_exec line that makes application users passwordless -- so this
        # step silently undoes `cfg app-users`.  app-users is the next entry
        # in services.stack and puts it back (the suite asserts that order);
        # say so here, so `su - u_<n>` asking for a password is not a mystery.
        _had_exec=0
        grep -q 'pam_exec\.so' "$PAM_DIR/su" 2>/dev/null && _had_exec=1
        for _cfgpkg in $PAM_PKGS; do
            case "$_scripts" in *" $_cfgpkg="*) ;; *) continue ;; esac
            if $PM script configure "$_cfgpkg" >/dev/null 2>&1; then
                note "   configured $_cfgpkg"
            else
                warn "could not run $_cfgpkg's configure phase"
                note "     by hand:  packagemanager script configure $_cfgpkg"
            fi
        done
        # CONFIRM IT -- every file, by name.
        _still=""
        for _n in $_want_pam; do
            [ -f "$PAM_DIR/$_n" ] || _still="$_still $_n"
        done
        if [ -z "$_still" ]; then
            note "   all $(echo $_want_pam | wc -w) written"
        else
            warn "still missing from $PAM_DIR:$_still"
            note "     a missing service file is \"pam_start: error 26\" for that program"
        fi
        if [ "$_had_exec" = 1 ] && ! grep -q 'pam_exec\.so' "$PAM_DIR/su" 2>/dev/null; then
            note "   shadow's configure rewrote $PAM_DIR/su without the pam_exec line:"
            note "   application users need a password until app-users runs again."
            note "   services.stack runs it next; on its own:"
            note "     packagemanager stack services --only app-users --run"
        fi
    fi
elif _pam_installed; then
    warn "could not work out which $PAM_DIR files the book writes -- nothing checked"
fi
echo

# ---- 2. is su PAM-aware? -------------------------------------------------

if ! _pam_installed; then
    note "Linux-PAM is not installed -- nothing to rebuild shadow against."
    note "   passwordless su needs it:  packagemanager stack services --only linux-pam --run"
elif _su_has_pam; then
    note "$SU already links libpam -- no rebuild needed"
else
    note "$SU does not link libpam: shadow was built before PAM existed."
    note "   rebuilding it now (this is the step the book's Linux-PAM page asks for)"
    # REGENERATE, because the script on disk was written before pam was
    # here and its configure line has no --with-libpam to gain.
    if $PM update shadow --reinstall --regenerate --run --yes; then
        if _su_has_pam; then
            note "   $SU now links libpam"
        else
            warn "shadow rebuilt and $SU still does not link libpam"
            note "   check the configure line:  grep -n configure \\"
            note "     /usr/src/pkgusr/p_shadow/install_Shadow-*"
            note "   the book's page may need --with-libpam for this system."
        fi
    else
        warn "rebuilding shadow failed -- su is unchanged, which is the safe outcome"
        note "   logs:  packagemanager errors"
    fi
fi
echo

# ---- 3. the setuid bits, applied ----------------------------------------
# A rebuild of shadow resets these every time, so this runs whether or not
# the rebuild above did anything.
[ -r "$CONF" ] || { warn "no $CONF -- cannot restore the setuid bits"; exit 1; }

applied=0 checked=0
# FIVE COLUMNS.  This read four, so since the package column arrived
# (1.14.310) `group` held "- | shadow" -- "-|shadow" once the blanks were
# gone -- and every chown below asked for group "-|shadow" and failed.
while IFS='|' read -r path mode owner group _pkg; do
    path="$(printf '%s' "${path:-}" | tr -d '[:space:]')"
    case "$path" in ""|\#*) continue ;; esac
    mode="$(printf '%s' "${mode:-}" | tr -d '[:space:]')"
    owner="$(printf '%s' "${owner:-}" | tr -d '[:space:]')"
    group="$(printf '%s' "${group:-}" | tr -d '[:space:]')"
    [ -n "$mode" ] || { warn "$path: no mode in $CONF"; continue; }
    # "-": keep the mode the file has (a line that exists only so the lease
    # may hand the file to its package) -- nothing for this script to set
    [ "$mode" = "-" ] && continue
    if [ ! -e "$path" ]; then
        # NOT AN ERROR.  Not every package here installs every file --
        # unix_chkpwd only exists once Linux-PAM is in.
        note "$path is not installed -- skipped"
        continue
    fi
    checked=$((checked + 1))
    now="$(stat -c '%a %U %G' "$path" 2>/dev/null)"
    want_owner="${owner:--}"
    [ "$want_owner" = "-" ] && want_owner="$(printf '%s' "$now" | awk '{print $2}')"
    want_group="${group:--}"
    [ "$want_group" = "-" ] && want_group="$(printf '%s' "$now" | awk '{print $3}')"
    if [ "$now" = "$mode $want_owner $want_group" ]; then
        continue
    fi
    note "$path is $now, should be $mode $want_owner $want_group"
    # ORDER MATTERS: chown CLEARS the setuid bit, so chmod goes last.
    chown "$want_owner:$want_group" "$path" 2>/dev/null \
        || warn "   could not chown $path"
    if chmod "$mode" "$path" 2>/dev/null; then
        # CONFIRM IT.  A setuid bit that did not take is the whole failure
        # this step exists to end.
        after="$(stat -c '%a %U %G' "$path" 2>/dev/null)"
        if [ "$after" = "$mode $want_owner $want_group" ]; then
            note "   -> $after"
            applied=$((applied + 1))
        else
            warn "   $path is $after after chmod $mode -- not what was asked"
        fi
    else
        warn "   could not chmod $mode $path"
    fi
done < "$CONF"

echo

# ---- 4. accounts pam can actually look up --------------------------------
# EVERY BUILD IS A `su - p_<pkg>`, so this line is not cosmetic:
#
#     su: Authentication service cannot retrieve authentication info
#     (Ignored)
#
# pam_unix reads /etc/shadow.  `add_package_user` writes /etc/passwd and
# leaves no shadow entry, so pam_unix cannot find the account and says so --
# on every package build, in every log, for ever.  It is "(Ignored)" only
# because pam_rootok already succeeded for root; for any non-root caller it
# is a real failure.
#
# `pwconv` is shadow's own tool for exactly this: it adds a shadow entry for
# every passwd entry that lacks one, with the password field locked.  It
# rewrites /etc/shadow, so: back it up, run it, read it back.
#
# UNVERIFIED FROM WHERE THIS WAS WRITTEN: the detection, the backup and the
# read-back were exercised against a fixture; `pwconv` itself was not (it
# edits the real /etc/shadow and there is no safe way to run it in that
# sandbox).  If it turns out not to cover these accounts, the read-back
# below says so by name and the backup is beside the file -- which is why
# both are here.
_no_shadow() {
    # accounts in passwd with no /etc/shadow line
    while IFS=: read -r _n _rest; do
        case "$_n" in ""|\#*) continue ;; esac
        grep -q "^$_n:" /etc/shadow 2>/dev/null || printf '%s\n' "$_n"
    done < /etc/passwd
}

# NO /etc/shadow AT ALL IS THE CASE THIS MISSED.
#
# The guard was `[ -r /etc/passwd ] && [ -r /etc/shadow ]`, so on a system
# with no shadow file it skipped in silence -- which is exactly the system
# that needs it most: pam_unix has nowhere to look for ANY account, and
# every `su - p_<pkg>` says "cannot retrieve authentication info".
#
# pwconv CREATES /etc/shadow from /etc/passwd, moving each password hash out
# of passwd and leaving `x` behind.  That is a change to how this machine
# authenticates, so:
#   * /etc/passwd is backed up FIRST (it is the file that changes),
#   * root's own line is checked afterwards, by name,
#   * and if anything is wrong, passwd is put back and shadow removed.
if [ ! -r /etc/passwd ]; then
    warn "cannot read /etc/passwd -- skipping the shadow check"
elif [ ! -e /etc/shadow ]; then
    note "there is no /etc/shadow at all: pam_unix cannot look up ANY account,"
    note "   which is the \"cannot retrieve authentication info\" on every build."
    note "   pwconv creates it from /etc/passwd (hashes move; passwd keeps 'x')."
    _pwbak="/etc/passwd.bak-$(date +%Y%m%d-%H%M%S)"
    if ! cp -p /etc/passwd "$_pwbak"; then
        warn "could not back up /etc/passwd -- not running pwconv"
    else
        note "   backed up /etc/passwd -> $(basename "$_pwbak")"
        if pwconv && [ -s /etc/shadow ] && grep -q '^root:' /etc/shadow \
           && grep -q '^root:' /etc/passwd; then
            chmod 600 /etc/shadow 2>/dev/null
            note "   /etc/shadow created, root is in it, $(grep -c . /etc/shadow) entries"
            note "   VERIFY BEFORE LOGGING OUT, from another terminal:"
            note "     su - $(awk -F: '$3>=1000 && $3<60000 {print $1; exit}' /etc/passwd) -c id"
            note "   if login is broken:  cp -p $_pwbak /etc/passwd && rm -f /etc/shadow"
        else
            warn "pwconv did not produce a usable /etc/shadow -- putting"
            warn "   /etc/passwd back and removing the half-made file"
            cp -p "$_pwbak" /etc/passwd
            rm -f /etc/shadow
            note "   nothing changed; the backup is still at $_pwbak"
        fi
    fi
elif [ -r /etc/shadow ]; then
    _missing_sh="$(_no_shadow | tr '\n' ' ')"
    if [ -z "$(printf '%s' "$_missing_sh" | tr -d ' ')" ]; then
        note "every account has an /etc/shadow entry (pam_unix can read them)"
    else
        note "accounts with no /etc/shadow entry:$_missing_sh"
        note "   pam_unix cannot look those up -- that is the"
        note "   \"cannot retrieve authentication info\" line on every build."
        _shbak="/etc/shadow.bak-$(date +%Y%m%d-%H%M%S)"
        if cp -p /etc/shadow "$_shbak"; then
            note "   backed up /etc/shadow -> $(basename "$_shbak")"
            if pwconv; then
                _still="$(_no_shadow | tr '\n' ' ')"
                if [ -z "$(printf '%s' "$_still" | tr -d ' ')" ]; then
                    note "   pwconv added the missing entries (passwords locked)"
                else
                    warn "still without a shadow entry:$_still"
                    note "     pwconv ran and did not cover them; look at /etc/passwd"
                fi
            else
                warn "pwconv failed -- /etc/shadow is unchanged"
                note "     the backup is $_shbak if anything looks wrong"
            fi
        else
            warn "could not back up /etc/shadow -- not running pwconv"
        fi
    fi
fi

echo
if [ "$fail" = 0 ]; then
    echo "# shadow-pam: $checked file(s) checked, $applied corrected."
    echo "#   try it, in ANOTHER terminal, before closing this one:"
    echo "#     su - <an application user> -c id"
    echo "#   if su is broken, this is the file to look at: /etc/pam.d/su"
else
    echo "# the !! lines above need attention"
fi
exit $fail

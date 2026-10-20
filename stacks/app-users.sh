#!/bin/bash
# app-users.sh -- create the application accounts declared in app-users.conf.
#
# Everything here goes through `packagemanager user setup`, which is
# idempotent and already knows how to join the session group, make the home
# unreadable to others, and write a launcher.  This step is the part that
# reads a FILE instead of a command line, plus the two things no per-account
# command can do: merge /etc/pam.d/su_u_user (one file listing every
# account) and write the shell variables (one file enumerating them).
#
# NOTHING HERE OVERWRITES A FILE IT DID NOT WRITE.  The PAM file is merged
# and backed up; the profile fragment is only written if absent or if it
# carries this script's marker; a shared directory that exists as a real
# directory is left alone.
set -u

CONF="${APP_USERS_CONF:-/etc/pkgusr/stacks/app-users.conf}"
PAM_FILE="${APP_USERS_PAM:-/etc/pam.d/su_u_user}"
PROFILE_D="${APP_USERS_PROFILE_D:-/etc/profile.d}"
PM="${APP_USERS_PM:-packagemanager}"
MARKER="# written by stacks/app-users.sh -- safe to delete, regenerated"
fail=0
note() { echo "#  $*"; }
warn() { echo "!! $*"; fail=1; }

[ -r "$CONF" ] || { warn "no $CONF to read"; exit 1; }

# ASK, DO NOT GUESS.  `packagemanager env --system` writes these facts to
# /etc/profile.d/pkgusr-system.sh precisely so that three scripts stop
# rediscovering them three different ways.  Use them when they are there,
# fall back to asking the tool, and only then to the old file.
MAIN="${PKGUSR_SYS_MAIN_USER:-}"
[ -n "$MAIN" ] || MAIN="$($PM config --show main-user 2>/dev/null | tr -d ' ')"
[ -n "$MAIN" ] || MAIN="$(cat /etc/pkgusr/desktop-user 2>/dev/null || true)"
if [ -z "$MAIN" ]; then
    warn "no main user configured -- there is nobody to grant access to"
    note "   packagemanager config --main-user <your-login>"
    exit 1
fi
PREFIX="${PKGUSR_SYS_USER_PREFIX:-}"
[ -n "$PREFIX" ] || PREFIX="$($PM config --show user-prefix 2>/dev/null | tr -d ' ')"
[ -n "$PREFIX" ] || PREFIX="u_"
note "main user: $MAIN   account prefix: $PREFIX"
# ...and keep those facts current for everything else, since this step is
# where the main user is first really needed.
$PM env --system --run >/dev/null 2>&1 \
    && note "refreshed /etc/profile.d/pkgusr-system.sh (PKGUSR_SYS_*)" \
    || true

# THE HUB: where the links to every shared directory live (1.14.312).  Asked
# of the tool, NOT read from $PKGUSR_SYS_SHARED -- this shell inherited that
# at login, and before 1.14.312 it named ~/Shared.  /home/Shared
# unless `packagemanager config --shared-hub DIR` says otherwise.
HUB="$($PM env --system 2>/dev/null | sed -n 's/^export PKGUSR_SYS_SHARED="\(.*\)"$/\1/p' | head -n1)"
[ -n "$HUB" ] || HUB="/home/Shared"
note "shared hub: $HUB"

# CONFIRM THE COMMAND EXISTS BEFORE THE LOOP.  Every line would otherwise
# fail the same way, three times, with the parser's error rather than ours.
if ! $PM user setup --help >/dev/null 2>&1; then
    warn "'$PM user setup' is not available -- nothing here can run"
    note "   check:  $PM user --help"
    exit 1
fi
echo

# ---- 1. the accounts, then their launchers ---------------------------------
# ONE ACCOUNT, SEVERAL LAUNCHERS.  A line is
#     account | name | app | share | dir | desktop | launcher | groups | icon
# so browser-mini, browser-big, google and duckduckgo can all run as
# u_browser.  `name` empty means the account's own name.  The account gets
# the strongest `share` of its lines (full beats slim), a shared directory
# if any line asks, and the union of the groups.  The older 7-column format
# (name | app | share | dir | desktop | launcher | groups) still reads: the
# account is the name.  Missing trailing fields take the defaults
# (slim, yes, yes, yes, -, auto icon).
trim() { printf '%s' "${1:-}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'; }
declare -A A_SHARE A_DIR A_GROUPS
accounts=""
L_ACCT=(); L_NAME=(); L_APP=(); L_DESK=(); L_LAUNCH=(); L_ICON=()
format=new
S_ACCT=(); S_CMD=()
while IFS= read -r raw || [ -n "$raw" ]; do
    case "$(trim "$raw")" in ""|\#*) continue ;; esac
    # @setup <account|*> <command | URL | /path/script> -- run AS the
    # account once (see step 1a).  Not split on `|`: a command may pipe.
    case "$(trim "$raw")" in
        @setup[[:space:]]*)
            rest="$(trim "${raw#*@setup}")"
            sacct="${rest%%[[:space:]]*}"
            scmd="$(trim "${rest#"$sacct"}")"
            case "$sacct" in
                \*|[a-z0-9_-]*) ;;
                *) warn "line '$raw': '$sacct' is not an account -- skipped"; continue ;;
            esac
            [ -n "$scmd" ] || { warn "line '$raw': @setup without a command -- skipped"; continue; }
            S_ACCT+=("$sacct"); S_CMD+=("$scmd")
            continue ;;
        @*) warn "line '$raw': unknown directive -- skipped"; continue ;;
    esac
    IFS='|' read -r f1 f2 f3 f4 f5 f6 f7 f8 f9 <<< "$raw"
    f1="$(trim "$f1")"
    # the header tells the format
    case "$f1" in
        name)         format=old; continue ;;
        user|account) format=new; continue ;;
    esac
    if [ "$format" = old ]; then
        acct="$f1"; lname="$f1"; app="$(trim "$f2")"; share="$(trim "$f3")"
        dir="$(trim "$f4")"; desktop="$(trim "$f5")"; launcher="$(trim "$f6")"
        groups="$(trim "$f7")"; icon=""
    else
        acct="$f1"; lname="$(trim "$f2")"; app="$(trim "$f3")"; share="$(trim "$f4")"
        dir="$(trim "$f5")"; desktop="$(trim "$f6")"; launcher="$(trim "$f7")"
        groups="$(trim "$f8")"; icon="$(trim "$f9")"
    fi
    case "$acct" in *[!a-z0-9_-]*|"") warn "line '$raw': account '$acct' is not a plain name -- skipped"; continue ;; esac
    [ -n "$lname" ] && [ "$lname" != - ] || lname="$acct"
    case "$lname" in *[!a-zA-Z0-9_.-]*) warn "$acct: launcher name '$lname' is not a plain name -- skipped"; continue ;; esac
    share="${share:-slim}"; dir="${dir:-yes}"; desktop="${desktop:-yes}"; launcher="${launcher:-yes}"
    case "$share" in slim|full|no|-) ;; *) warn "$lname: share='$share' is not slim, full or no -- skipped"; continue ;; esac
    # the account's settings: the strongest share, any dir, all groups
    case "$share:${A_SHARE[$acct]:-}" in
        full:*) A_SHARE[$acct]=full ;;
        slim:full) ;;
        slim:*) A_SHARE[$acct]=slim ;;
        *) A_SHARE[$acct]="${A_SHARE[$acct]:-no}" ;;
    esac
    [ "$dir" = yes ] && A_DIR[$acct]=yes
    case "$groups" in -|"") ;; *) A_GROUPS[$acct]="${A_GROUPS[$acct]:+${A_GROUPS[$acct]},}$groups" ;; esac
    case " $accounts " in *" $acct "*) ;; *) accounts="$accounts $acct" ;; esac
    case "$app" in -|"") continue ;; esac
    L_ACCT+=("$acct"); L_NAME+=("$lname"); L_APP+=("$app")
    L_DESK+=("$desktop"); L_LAUNCH+=("$launcher"); L_ICON+=("$icon")
done < "$CONF"

names=""
for name in $accounts; do
    # CREATE IT IF IT IS NOT THERE: `user setup` needs an existing account,
    # `user create` makes one and then applies the same setup.
    if id "$PREFIX$name" >/dev/null 2>&1; then
        set -- user setup "$name"
    else
        note "$PREFIX$name does not exist yet -- creating it"
        set -- user create "$name"
    fi
    case "${A_SHARE[$name]}" in
        slim) set -- "$@" --shared-slim ;;
        full) set -- "$@" --shared-full ;;
    esac
    [ "${A_DIR[$name]:-}" = yes ] && set -- "$@" --share-dir
    [ -n "${A_GROUPS[$name]:-}" ] && set -- "$@" --groups "${A_GROUPS[$name]}"
    note "$name: $PM $*"
    if $PM "$@"; then
        names="$names $name"
    else
        warn "$name: setup failed -- not added to the PAM list, no launchers"
    fi
    echo
done

for i in "${!L_NAME[@]}"; do
    acct="${L_ACCT[$i]}"
    case " $names " in *" $acct "*) ;; *) continue ;; esac
    # a menu entry runs the launcher, so either one needs the launcher
    [ "${L_LAUNCH[$i]}" = yes ] || [ "${L_DESK[$i]}" = yes ] || continue
    set -- user launcher "$acct" "${L_NAME[$i]}" --app "${L_APP[$i]}"
    [ "${L_DESK[$i]}" = yes ] || set -- "$@" --no-desktop
    [ -n "${L_ICON[$i]}" ] && set -- "$@" --icon "${L_ICON[$i]}"
    note "${L_NAME[$i]} (as $PREFIX$acct)"
    $PM "$@" || warn "${L_NAME[$i]}: launcher failed"
done
echo

[ -n "$names" ] || { warn "no usable lines in $CONF"; exit 1; }

# ---- 1a. @setup: the account's own extra steps ------------------------------
# A command, a local script or a URL to a bash script, run AS the account
# (login shell, its own HOME) -- never as root.  ONCE: a step that ran is
# recorded by its text in $SETUP_DB/<account>, so a later run skips it and
# a CHANGED line runs again.  APP_USERS_RERUN=1 runs them all again.
SETUP_DB="${APP_USERS_SETUP_DB:-/var/lib/pkgusr/app-setup}"
fetch_to() {  # url file
    if command -v curl >/dev/null 2>&1; then curl -fsSL "$1" -o "$2"
    elif command -v wget >/dev/null 2>&1; then wget -q -O "$2" "$1"
    else echo "no curl or wget" >&2; return 1; fi
}
if [ "${#S_CMD[@]}" -gt 0 ]; then
    mkdir -p "$SETUP_DB" && chmod 700 "$SETUP_DB"
    for i in "${!S_CMD[@]}"; do
        cmd="${S_CMD[$i]}"
        if [ "${S_ACCT[$i]}" = "*" ]; then targets="$names"; else targets="${S_ACCT[$i]}"; fi
        key="$(printf '%s' "$cmd" | md5sum | cut -c1-12)"
        for acct in $targets; do
            case " $names " in *" $acct "*) ;; *) warn "@setup $acct: no such account in $CONF -- skipped"; continue ;; esac
            db="$SETUP_DB/$acct"
            if [ "${APP_USERS_RERUN:-0}" != 1 ] && grep -qx "$key" "$db" 2>/dev/null; then
                note "$acct: setup already done -- $cmd"
                continue
            fi
            note "$acct: setup -- $cmd"
            case "$cmd" in
                http://*|https://*)
                    tmp="$(mktemp /tmp/app-setup.XXXXXX)"
                    if ! fetch_to "$cmd" "$tmp"; then
                        rm -f "$tmp"; warn "$acct: could not download $cmd"; continue
                    fi
                    chmod 644 "$tmp"
                    su - "$PREFIX$acct" -s /bin/bash -c "bash '$tmp'"; rc=$?
                    rm -f "$tmp" ;;
                /*)
                    if [ -f "$cmd" ]; then
                        su - "$PREFIX$acct" -s /bin/bash -c "bash '$cmd'"; rc=$?
                    else
                        su - "$PREFIX$acct" -s /bin/bash -c "$cmd"; rc=$?
                    fi ;;
                *)  su - "$PREFIX$acct" -s /bin/bash -c "$cmd"; rc=$? ;;
            esac
            if [ "$rc" = 0 ]; then
                grep -qx "$key" "$db" 2>/dev/null || echo "$key" >> "$db"
            else
                warn "$acct: setup failed (exit $rc) -- runs again next time: $cmd"
            fi
        done
    done
    echo
fi
# TRIM ONCE, HERE.  $names is built by appending " $n", so it starts with a
# space and ${names%% *} is empty -- which printed `su - u_` twice before,
# in two different blocks.  One trim, at the top, and every later use is
# right.
names="$(printf '%s' "$names" | sed 's/^ *//')"

# ---- 1b. a line that STOPPED asking for a shared directory -----------------
# `user setup` makes what the line asks for; it never takes away, so an
# account switched from dir=yes to dir=no keeps its /home/Shared/<Name> --
# and /etc/profile.d/shared-dirs.sh keeps exporting $SHARED_<NAME> for it.
# An EMPTY leftover is removed here (nothing can be lost).  One with files in
# it is yours: this says where it is and what would remove it.
MAIN_HOME="$(getent passwd "$MAIN" | cut -d: -f6)"
for name in $accounts; do
    [ "${A_DIR[$name]:-}" = yes ] && continue
    cap="$(printf '%s' "$name" | cut -c1 | tr '[:lower:]' '[:upper:]')$(printf '%s' "$name" | cut -c2-)"
    d="$HUB/$cap"
    # since 1.14.315 the hub holds the DIRECTORY and the account's ~/Shared
    # is the link; before that, the hub held a link.  Either is handled.
    ah="$(getent passwd "$PREFIX$name" | cut -d: -f6)"
    if [ -L "$d" ]; then
        tgt="$(readlink -f "$d" 2>/dev/null || true)"
    elif [ -d "$d" ]; then
        tgt="$d"
    else
        continue
    fi
    if [ ! -d "$tgt" ] || [ -z "$(ls -A "$tgt" 2>/dev/null)" ]; then
        [ -L "$d" ] && rm -f "$d"
        [ -d "$tgt" ] && rmdir "$tgt" 2>/dev/null
        note "$name: dir=no -- removed the empty $d"
        if [ -n "$ah" ] && [ -L "$ah/Shared" ] && [ ! -e "$ah/Shared" ]; then
            rm -f "$ah/Shared" && note "   and the link $ah/Shared"
        fi
    else
        note "$name: dir=no, but $d still has files in it -- left alone"
        note "   look, then remove it yourself"
    fi
done
echo

# ---- 2. /etc/pam.d/su_u_user, MERGED --------------------------------------
# One file lists every account your login may become without a password.
# It is hand-editable and may well have entries this file knows nothing
# about, so: keep what is there, add what is missing, back it up first.
pam_has() { grep -qE "^[[:space:]]*$1\)" "$PAM_FILE" 2>/dev/null; }

missing=""
for n in $names; do
    pam_has "$PREFIX$n" || missing="$missing $n"
done

if [ ! -e "$PAM_FILE" ]; then
    note "writing $PAM_FILE (it did not exist)"
    mkdir -p "$(dirname "$PAM_FILE")"
    {
        echo '#!/bin/bash'
        echo "$MARKER"
        echo '# Which accounts may be entered with `su -` without a password.'
        echo '# Hand-edited entries are kept: this file is MERGED, never'
        echo '# overwritten.'
        echo ''
        echo '# PAM_USER is the account being entered, PAM_RUSER the one asking.'
        echo '# No caller, no pass: su always sets it.'
        echo '[[ -n $PAM_RUSER ]] || exit 1'
        echo '[[ "$PAM_TYPE" == "auth" ]] || exit 1'
        echo 'case "$PAM_USER" in'
        for n in $names; do
            printf '  %s%s) USERS="%s%s %s"; ;;\n' \
                   "$PREFIX" "$n" "$PREFIX" "$n" "$MAIN"
        done
        echo '  *)            exit 1 ; ;;'
        echo 'esac'
        echo '[[ " $USERS " == *" $PAM_RUSER "* ]]'
    } > "$PAM_FILE"
    # IT IS A SCRIPT, NOT A CONFIG FILE.  /etc/pam.d/su_u_user starts
    # with `#!/bin/bash` and is RUN by pam_exec.so.  At 644 pam cannot
    # execute it, and `su - u_claude` then just asks for a password
    # with nothing in the logs to say why.
    chmod 755 "$PAM_FILE"
    note "   $(grep -c ') USERS=' "$PAM_FILE") account(s) listed"
elif [ -z "$missing" ]; then
    note "$PAM_FILE already lists every account here"
else
    # BACK IT UP BEFORE TOUCHING IT, with a name that says when.
    bak="$PAM_FILE.bak-$(date +%Y%m%d-%H%M%S)"
    cp -p "$PAM_FILE" "$bak" || { warn "could not back up $PAM_FILE"; exit 1; }
    note "backed up $PAM_FILE -> $(basename "$bak")"
    # insert before the `*)` default, which is where new cases belong; if
    # there is no default we cannot know the shape and will not guess.
    if grep -qE '^[[:space:]]*\*\)' "$PAM_FILE"; then
        tmp="$(mktemp)"
        ins="$tmp.ins"
        : > "$ins"
        for n in $missing; do
            printf '  %s%s) USERS="%s%s %s"; ;;\n' \
                   "$PREFIX" "$n" "$PREFIX" "$n" "$MAIN" >> "$ins"
        done
        awk -v ins="$ins" '
            /^[[:space:]]*\*\)/ && !done {
                while ((getline line < ins) > 0) print line
                close(ins); done = 1
            }
            { print }
        ' "$PAM_FILE" > "$tmp" && cat "$tmp" > "$PAM_FILE"
        rm -f "$tmp" "$ins"
        for n in $missing; do
            pam_has "$PREFIX$n" \
                || warn "$PREFIX$n is still not in $PAM_FILE after the merge"
        done
        # the merge rewrites the file, so re-assert the exec bit: pam
        # cannot run a 644 script, and a merge that silently drops it
        # breaks su for every account in there.
        chmod 755 "$PAM_FILE"
        note "added to $PAM_FILE:$missing"
    else
        warn "$PAM_FILE has no '*)' default case -- not editing it"
        note "   add these lines yourself, before the end of the case:"
        for n in $missing; do
            printf '     %s%s) USERS="%s%s %s"; ;;\n' \
                   "$PREFIX" "$n" "$PREFIX" "$n" "$MAIN"
        done
    fi
fi

# THE CHECK MUST BE ON THE CALLER.
#
# The last line compared the TARGET with a list that contains the target:
#     [[ "$USERS" =~ "$PAM_USER" ]]
# which is always true, and an empty PAM_RUSER was filled with PAM_USER.  So
# pam_exec let ANY account -- another u_*, any package user -- enter every
# listed account without a password.  The intended test is "is the account
# ASKING in the list", as a whole word (=~ also matched u_claude inside
# u_claudex).  A file written before this is repaired in place, with a backup.
if [ -f "$PAM_FILE" ] && grep -qE '^\[\[ "\$USERS" =~ "\$PAM_USER" \]\]|^\[\[ -z \$PAM_RUSER \]\] && PAM_RUSER=\$PAM_USER' "$PAM_FILE"; then
    bak="$PAM_FILE.bak-$(date +%Y%m%d-%H%M%S)"
    cp -p "$PAM_FILE" "$bak" || { warn "could not back up $PAM_FILE"; exit 1; }
    sed -i \
        -e 's/^\[\[ -z \$PAM_RUSER \]\] && PAM_RUSER=\$PAM_USER$/[[ -n $PAM_RUSER ]] || exit 1/' \
        -e 's/^\[\[ "\$USERS" =~ "\$PAM_USER" \]\]$/[[ " $USERS " == *" $PAM_RUSER "* ]]/' \
        "$PAM_FILE"
    if grep -qF '[[ " $USERS " == *" $PAM_RUSER "* ]]' "$PAM_FILE" \
       && ! grep -qF '=~ "$PAM_USER"' "$PAM_FILE"; then
        note "fixed $PAM_FILE: it let ANY account in without a password;"
        note "   it now checks the account asking (backup: $(basename "$bak"))"
    else
        warn "could not repair the caller check in $PAM_FILE -- restoring the backup"
        cp -p "$bak" "$PAM_FILE"
        note "   its last line must read:  [[ \" \$USERS \" == *\" \$PAM_RUSER \"* ]]"
    fi
fi

# THE ACCOUNTS THEMSELVES: LOCKED, AND NOT DUE A PASSWORD CHANGE.
#
#     su: Authentication token manipulation error
#
# That is pam asking for a NEW password: /etc/shadow's "last changed" field
# is 0, which means "must change at next login", and su -- run by a user --
# cannot change another account's password.  pam_exec lets the AUTH step
# through, but the ACCOUNT step (pam_unix in system-account) still enforces
# it.  And an EMPTY password field would let anyone in with Enter.  Each
# account is locked (no password at all; only su from a listed account enters
# it) and its last-change date set when it is 0.  Nothing else is touched.
if [ -r /etc/shadow ]; then
    for n in $names; do
        u="$PREFIX$n"
        line="$(grep "^$u:" /etc/shadow 2>/dev/null)" || continue
        pwf="$(printf '%s' "$line" | cut -d: -f2)"
        lastchg="$(printf '%s' "$line" | cut -d: -f3)"
        if [ -z "$pwf" ]; then
            usermod -L "$u" >/dev/null 2>&1 && note "$u had an EMPTY password -- locked"
            grep -q "^$u:!" /etc/shadow || warn "$u still has an empty password field"
        fi
        if [ "$lastchg" = 0 ]; then
            chage -d "$(date +%Y-%m-%d)" "$u" \
                && note "$u was marked 'must change password' -- cleared (su would fail)"
        fi
    done
fi

# ROOT RUNS IT, SO ROOT OWNS IT.  pam_exec executes this as root; it was
# owned by p_librice (written while librice's build window was open, and
# attributed to it), so anything building as p_librice could replace a script
# root runs on every su.  Re-asserted on every run.
if [ -f "$PAM_FILE" ]; then
    chown root:root "$PAM_FILE" && chmod 755 "$PAM_FILE"
    [ "$(stat -c %U:%G:%a "$PAM_FILE")" = root:root:755 ] \
        || warn "$PAM_FILE is $(stat -c %U:%G:%a "$PAM_FILE"), not root:root:755"
fi
echo

# ---- 3. the shell variables ----------------------------------------------
# ENUMERATE, DO NOT LIST.  The fragment reads the hub at login, so an
# account added to the conf file shows up in the next shell without this
# file being rewritten -- and a link you make by hand appears too.
frag="$PROFILE_D/shared-dirs.sh"
if [ -d "$PROFILE_D" ]; then
    if [ -e "$frag" ] && ! grep -qF "$MARKER" "$frag"; then
        warn "$frag exists and is not ours -- left alone"
        note "   it would have exported SHARED_<NAME> for each $HUB/<Name>"
    else
        cat > "$frag" <<PROF
$MARKER
# One variable per shared directory: $HUB/Claude -> \$SHARED_CLAUDE.
# The SAME set in every account: the hub is a system path, not \$HOME/Shared
# (which in an app account is its own data directory -- enumerating that
# exported one SHARED_* per FILE in it, before 1.14.312).
# Enumerated, not listed, so an account added or removed needs no change
# here -- and a link you make by hand appears too.
#
# IT ALSO TAKES AWAY.  An account removed after you logged in leaves its
# variable in the environment, pointing at nothing, and every shell started
# from that session inherits it.  So: drop the ones whose directory is gone,
# then export what is really there.  Safe to source again at any time.
for _v in \$(env | sed -n 's/^\(SHARED_[A-Z0-9_]*\)=.*/\1/p'); do
    eval "_p=\\\${\$_v}"
    [ -d "\$_p" ] || unset "\$_v"
done
if [ -d "$HUB" ]; then
    for _sd in "$HUB"/*; do
        [ -e "\$_sd" ] || continue
        _n="\$(basename "\$_sd" | tr '[:lower:]-' '[:upper:]_')"
        export "SHARED_\$_n=\$_sd"
    done
fi
unset _sd _n _v _p
PROF
        chmod 644 "$frag"; chown root:root "$frag" 2>/dev/null
        note "wrote $frag"
        note "   in a new login shell:  echo \$SHARED_CLAUDE"
        note "   (login shells read /etc/profile, which reads this directory."
        note "    Nothing of yours was edited -- no .bashrc, no .bash_profile.)"
    fi
    # ...AND IN A TERMINAL THAT IS NOT A LOGIN SHELL.
    #
    # /etc/profile.d is read by LOGIN shells.  A terminal opened inside sway
    # is not one: it reads ~/.bashrc, so it shows whatever the session
    # inherited when you logged in -- which is why the variables looked
    # "not set up" while the file was right.  /etc/bashrc is the file every
    # interactive shell reads (shell-env.sh writes it, ~/.bashrc sources
    # it), so the fragment is sourced from there too.  Only if that file is
    # the one shell-env.sh wrote; anything else is yours and only gets the
    # line printed.
    # WHICH /etc/bashrc COUNTS AS THE SYSTEM'S.  Looking only for the line
    # shell-env.sh writes was too narrow: a machine that took the BLFS
    # "Bash Shell Startup Files" file instead has a perfectly ordinary
    # /etc/bashrc, and the step just printed the line and left the variables
    # unreachable.  Both start `# Begin /etc/bashrc`, which is the marker.
    # ONE line is APPENDED -- nothing is rewritten -- after a backup, and
    # starting with a newline: a file here ends in `# End /etc/bashrcCK=$(tput
    # setaf 0)`, which is what an append without one does.
    BASHRC="${APP_USERS_BASHRC:-/etc/bashrc}"
    SRC_LINE='[ -r '"$frag"' ] && . '"$frag"
    if [ ! -f "$BASHRC" ]; then
        note "no $BASHRC -- add this line to ~/.bashrc so a NEW TERMINAL sees them:"
        note "     $SRC_LINE"
    elif grep -qF "$frag" "$BASHRC"; then
        note "$BASHRC already sources $(basename "$frag")"
    elif head -n1 "$BASHRC" | grep -q '^# Begin /etc/bashrc' \
         || grep -q 'Based on the BLFS "Bash Shell Startup Files" page' "$BASHRC"; then
        bak="$BASHRC.bak-$(date +%Y%m%d-%H%M%S)"
        if cp -p "$BASHRC" "$bak"; then
            printf '\n# the shared application directories (SHARED_<NAME>), for shells\n# that are not login shells -- a terminal opened inside the session\n%s\n' \
                "$SRC_LINE" >> "$BASHRC"
            note "added one line to $BASHRC (backup: $(basename "$bak"))"
            note "   a NEW TERMINAL now has the variables, without logging in again"
        else
            warn "could not back up $BASHRC -- not touching it"
            note "   add by hand:  $SRC_LINE"
        fi
    else
        note "$BASHRC is not the system's -- add this line to it, or to ~/.bashrc,"
        note "   so a NEW TERMINAL sees the variables without logging in again:"
        note "     $SRC_LINE"
    fi
else
    warn "no $PROFILE_D -- cannot install the SHARED_* variables"
    note "   source this from your own shell instead, and it stays yours:"
    note "     for d in $HUB/*; do export \"SHARED_\$(basename \$d | tr a-z- A-Z_)=\$d\"; done"
fi

# ---- 3b. the session group, applied by the session -------------------------
# Shared accounts reach the main user's display through the XDG runtime
# directory, which needs the group <prefix>_xdg-runtime (created and joined
# by `user setup`).  The directory is made fresh at every boot (and chmod-ed
# 0700 by whatever creates it), so root cannot set its group once and for
# all: the main user's own session has to.  Two pieces, both idempotent:
#   /usr/bin/xdg-runtime-share        run in the session (sway: exec it) --
#                                     the directory, then the wayland and
#                                     pipewire sockets as they appear
#   /etc/profile.d/xdg-runtime-share.sh  the directory, at every login shell
pfx="${LFS_COLLECTOR_PREFIX:-}"
[ -n "$pfx" ] || pfx="$(sed -n 's/^collector_prefix=\(.*\)$/\1/p' /etc/pkgusr/packagemanager.conf 2>/dev/null | head -n1)"
if [ -z "$pfx" ]; then
    warn "no collector prefix -- the session group cannot be named"
else
    XDG_GROUP="${pfx%_}_xdg-runtime"
    cat > /usr/bin/xdg-runtime-share <<SHARE
#!/bin/bash
$MARKER
# xdg-runtime-share -- open THIS session to the shared application accounts.
# Run it as $MAIN inside the session; in ~/.config/sway/config:
#     exec xdg-runtime-share
# Group $XDG_GROUP on \$XDG_RUNTIME_DIR (0750: enter, not list-and-write),
# then group read/write on the sockets a shared program connects to.  The
# session bus is NOT shared: dbus refuses other uids anyway.
g=$XDG_GROUP
d="\${XDG_RUNTIME_DIR:-}"
if [ -z "\$d" ] || [ ! -d "\$d" ] || [ ! -O "\$d" ]; then
    echo "xdg-runtime-share: XDG_RUNTIME_DIR is not a directory of yours" >&2; exit 1
fi
if ! id -Gn | tr ' ' '\n' | grep -qx "\$g"; then
    echo "xdg-runtime-share: you are not in \$g yet -- log out and in again" >&2; exit 1
fi
chgrp "\$g" "\$d" && chmod 0750 "\$d" || exit 1
# the sockets appear as the compositor and pipewire start: look for a while
for _i in \$(seq 1 "\${1:-30}"); do
    for s in "\$d"/wayland-[0-9]* "\$d"/pipewire-0 "\$d"/pipewire-0-manager; do
        case "\$s" in *.lock) continue ;; esac
        [ -S "\$s" ] && [ -O "\$s" ] || continue
        chgrp "\$g" "\$s" && chmod g+rw "\$s"
    done
    sleep 1
done
SHARE
    chmod 755 /usr/bin/xdg-runtime-share
    chown root:root /usr/bin/xdg-runtime-share 2>/dev/null
    cat > "$PROFILE_D/xdg-runtime-share.sh" <<PROF
$MARKER
# The runtime directory of $MAIN is entered by the shared accounts through
# group $XDG_GROUP.  Applied at every login shell; the sockets are done by
# xdg-runtime-share inside the session.
if [ "\$(id -un)" = "$MAIN" ] && [ -n "\${XDG_RUNTIME_DIR:-}" ] && [ -O "\$XDG_RUNTIME_DIR" ]; then
    chgrp $XDG_GROUP "\$XDG_RUNTIME_DIR" 2>/dev/null && chmod 0750 "\$XDG_RUNTIME_DIR" 2>/dev/null
fi
PROF
    chmod 644 "$PROFILE_D/xdg-runtime-share.sh"
    chown root:root "$PROFILE_D/xdg-runtime-share.sh" 2>/dev/null
    note "session group: $XDG_GROUP"
    note "   wrote /usr/bin/xdg-runtime-share and $PROFILE_D/xdg-runtime-share.sh"
    _mh="$(getent passwd "$MAIN" | cut -d: -f6)"
    if [ -f "$_mh/.config/sway/config" ] \
       && ! grep -q 'xdg-runtime-share' "$_mh/.config/sway/config"; then
        note "   add to $_mh/.config/sway/config (not edited -- it is yours):"
        note "     exec xdg-runtime-share"
    fi
    note "   $MAIN must log in again once to be in $XDG_GROUP"
fi
echo

# ---- 2b. tell pam to run it -----------------------------------------------
# The script decides WHO may be entered without a password, and pam only
# consults it if /etc/pam.d/su says so.  That line is added here, with a
# backup -- but only when there is a PAM to add it to.
PAM_SU="${APP_USERS_PAM_SU:-/etc/pam.d/su}"
PAM_LINE="auth      sufficient  pam_exec.so quiet $PAM_FILE"

if [ ! -d "$(dirname "$PAM_SU")" ]; then
    # NO PAM ON THIS MACHINE, AND THAT IS A DECISION, NOT AN OVERSIGHT.
    # avoid.stack avoids linux-pam (it arrived only as systemd's dependency),
    # so there is no /etc/pam.d at all -- and LFS's shadow is built without
    # PAM.  Adding a line to a file pam never reads would look like a fix
    # and change nothing.
    warn "no $(dirname "$PAM_SU") -- Linux-PAM is not installed here"
    note "   so `su - ${PREFIX}<name>` will keep asking for a password."
    note "   The accounts, groups, shared directories and launchers above are"
    note "   all real and working; only PASSWORDLESS su needs pam."
    note "   To get it, deliberately:"
    note "     packagemanager install linux-pam --run --recursive"
    note "     packagemanager update shadow --reinstall --regenerate --run"
    note "       (shadow must be REBUILT against pam, or nothing reads"
    note "        /etc/pam.d at all -- and read the book's Shadow page first:"
    note "        a wrong pam setup can lock you out of su and login.)"
    note "   $PAM_FILE is written and ready for when pam is there."
elif [ ! -f "$PAM_SU" ]; then
    warn "$PAM_SU does not exist -- not creating it"
    note "   /etc/pam.d exists, so pam is here, but su has no pam file: that"
    note "   comes from the book's Shadow page and this is not the place to"
    note "   invent one.  The line it needs:"
    note "     $PAM_LINE"
elif grep -qE "^[[:space:]]*auth[[:space:]]+sufficient[[:space:]]+pam_exec\.so.*$(basename "$PAM_FILE")" "$PAM_SU"; then
    # an ACTIVE auth line -- a comment or a backup note naming the file is
    # not pam calling it
    note "$PAM_SU already calls $(basename "$PAM_FILE")"
else
    bak="$PAM_SU.bak-$(date +%Y%m%d-%H%M%S)"
    if cp -p "$PAM_SU" "$bak"; then
        note "backed up $PAM_SU -> $(basename "$bak")"
        # ABOVE THE OTHER auth LINES.  `sufficient` succeeds the stack
        # immediately, so it has to be reached before the password prompt;
        # after them it would never run for the accounts it exists for.
        tmp="$(mktemp)"
        awk -v line="$PAM_LINE" '
            !done && /^[[:space:]]*auth[[:space:]]/ { print line; done = 1 }
            { print }
            END { if (!done) print line }
        ' "$PAM_SU" > "$tmp" && cat "$tmp" > "$PAM_SU"
        rm -f "$tmp"
        if grep -qF "$(basename "$PAM_FILE")" "$PAM_SU"; then
            note "added to $PAM_SU:"
            note "    $PAM_LINE"
            note "   test it now, in another terminal, BEFORE logging out:"
            note "     su - ${PREFIX}${names%% *} -c id"
            note "   if su is broken, put the backup back:  cp -p $bak $PAM_SU"
        else
            warn "could not add the line to $PAM_SU -- restoring the backup"
            cp -p "$bak" "$PAM_SU"
            note "   add it by hand, above the other auth lines:"
            note "     $PAM_LINE"
        fi
    else
        warn "could not back up $PAM_SU -- not touching it"
        note "   add by hand, above the other auth lines:  $PAM_LINE"
    fi
fi

echo
if [ "$fail" = 0 ]; then
    # $names is built by appending " $n", so it starts with a space and
    # ${names%% *} was empty -- the hint read `su - u_`.
    set -- $names
    echo "# app-users: done.  accounts:$names"
    echo "#   what they can reach:  packagemanager user list"
    echo "#   try one:              su - ${PREFIX}${1}   # no password"
else
    echo "# the !! lines above need attention; everything else was applied."
fi
exit $fail

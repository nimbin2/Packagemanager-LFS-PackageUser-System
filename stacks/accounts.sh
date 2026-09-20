#!/bin/bash
# accounts.sh -- create the system accounts declared in accounts.conf.
#
# SYSTEM ACCOUNTS ARE ROOT'S, AND THIS IS WHERE THEY HAPPEN.  A package user
# cannot create one, so a book's `useradd` line is refused mid-build and
# recorded; that refusal is correct, and the answer is not to type the
# command from the failure box later but to have created the account first.
#
# Idempotent: an account that exists is left exactly as it is, including a
# uid that does not match the file -- changing the uid of an account that
# already owns files is how a system loses track of who owns what, and it is
# not something a stack step should do behind anyone's back.
set -u

CONF="${ACCOUNTS_CONF:-/etc/pkgusr/stacks/accounts.conf}"
fail=0
note() { echo "#  $*"; }
warn() { echo "!! $*"; fail=1; }

[ -r "$CONF" ] || { warn "no $CONF to read"; exit 1; }

made=0 kept=0
while IFS=: read -r name uid gid home shell comment; do
    case "${name:-}" in ""|\#*) continue ;; esac
    [ -n "$comment" ] || comment="declared in $(basename "$CONF")"

    # ---- the group first: useradd -g needs it to exist ----------------
    if getent group "$name" >/dev/null 2>&1; then
        note "group $name exists (gid $(getent group "$name" | cut -d: -f3))"
    else
        if [ "$gid" = "-" ]; then
            groupadd -r "$name" || { warn "could not create group $name"; continue; }
        elif ! groupadd -g "$gid" "$name"; then
            # SAY WHO HOLDS THE NUMBER.  "could not create group sshd (gid
            # 50)" leaves the reader to find out why; groupadd knows, and
            # the answer decides what to do about it.
            _held="$(getent group "$gid" | cut -d: -f1)"
            if [ -n "$_held" ]; then
                warn "gid $gid is already group '$_held', so $name cannot have it"
                note "   either give $name another number in accounts.conf,"
                note "   or write '-' there and let the system choose one."
                note "   The book's number only matters if files from another"
                note "   system will arrive owned by it."
            else
                warn "could not create group $name with gid $gid"
            fi
            continue
        else
            note "created group $name"
        fi
    fi

    # ---- then the account --------------------------------------------
    if id "$name" >/dev/null 2>&1; then
        # SAY WHAT IS THERE, including a mismatch, and change nothing.
        _have="$(id -u "$name")"
        if [ "$uid" != "-" ] && [ "$_have" != "$uid" ]; then
            note "$name exists with uid $_have, not the declared $uid --"
            note "   left alone: it may own files.  To move it, deliberately:"
            note "     find / -xdev -user $name | head   then usermod -u $uid $name"
        else
            note "$name exists (uid $_have)"
        fi
        kept=$((kept + 1))
        continue
    fi

    set -- -c "$comment" -g "$name"
    # -r WHEN NO NUMBER IS GIVEN.  Without it useradd hands out the next
    # ordinary uid: `picky` came out as 1016, in the range real people get,
    # for an account that is meant to be a daemon's.
    if [ "$uid" = "-" ]; then
        set -- "$@" -r
    else
        set -- "$@" -u "$uid"
    fi
    case "$home" in
        -) set -- "$@" -M -d /dev/null ;;
        *) set -- "$@" -m -d "$home" ;;
    esac
    case "$shell" in
        -) set -- "$@" -s /bin/false ;;
        *) set -- "$@" -s "$shell" ;;
    esac
    if useradd "$@" "$name"; then
        # CONFIRM YOUR OWN EFFECT: useradd has returned 0 and created
        # nothing on this project before.
        if id "$name" >/dev/null 2>&1; then
            note "created $name (uid $(id -u "$name")), home ${home/-//dev/null}"
            made=$((made + 1))
        else
            warn "useradd $name returned 0 and the account is not there"
        fi
    else
        warn "could not create $name"
    fi

    # the home of a daemon account belongs to it, and nothing else should be
    # able to write there
    case "$home" in
        -) ;;
        *) if [ -d "$home" ]; then
               chown "$name:$name" "$home" && chmod 700 "$home" \
                   && note "   $home is $name's, mode 700"
           fi ;;
    esac
done < "$CONF"

echo
note "$made created, $kept already there"
if [ "$fail" = 0 ]; then
    echo "# accounts: every line in $(basename "$CONF") exists now."
    echo "#   what a build refused, and still wants doing:  lfs-helper setid"
else
    echo "# fix the !! lines; each is one line of $CONF"
fi
exit $fail

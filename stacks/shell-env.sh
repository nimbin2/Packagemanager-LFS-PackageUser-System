#!/bin/bash
# shell-env.sh -- interactive shell environment: the system locale, coloured
# ls, bash completion, and username completion for su (root step, idempotent).
#
# BLFS's "The Bash Shell Startup Files" page writes /etc/profile and
# /etc/bashrc, and /etc/bashrc is what makes ls colourful -- it evals
# dircolors and aliases ls --color=auto.  It is a config page, not a
# package, so nothing in a package stack ever ran it.
#
# bash-completion is not a BLFS package at all; it comes from upstream and
# is a `tar` entry in the stack beside this script.
set -u

# ROOT WROTE IT, SO ROOT OWNS IT.
#
# On a package-user system a file's owner records which package installed it,
# and anything written while a build window is open is attributed to that
# package user -- /etc/profile.d/pkgusr-system.sh owned by p_gstreamer10,
# 00-path-functions.sh by p_gettext, /etc/profile.d itself by p_libnice.
# For a file a PACKAGE installed that is correct and useful.  For a config
# file root writes it is wrong twice over: it says a package owns something
# no package installed, and every login shell sources it, so whoever can
# write it can run code as everyone who logs in.  Re-asserted on every run.
own_root() { [ -e "$1" ] && chown root:root "$1" 2>/dev/null; return 0; }

# 1. /etc/dircolors -- the database ls colours come from
if [ ! -f /etc/dircolors ]; then
    if command -v dircolors >/dev/null 2>&1; then
        dircolors -p > /etc/dircolors
        own_root /etc/dircolors
        echo "# wrote /etc/dircolors (from dircolors -p)"
    fi
else
    echo "# /etc/dircolors exists -- left alone"
fi

# 2. /etc/bashrc -- colours, prompt, and the completion loader.
#    Written only if absent: this is a file people edit.
if [ -f /etc/bashrc ]; then
    echo "# /etc/bashrc exists -- left alone (see /etc/bashrc.new)"
    _dest=/etc/bashrc.new
else
    _dest=/etc/bashrc
fi
cat > "$_dest" <<'BASHRC'
# Begin /etc/bashrc
# Based on the BLFS "Bash Shell Startup Files" page.

# Coloured ls and grep.
if [ -f /etc/dircolors ] ; then
    eval "$(dircolors -b /etc/dircolors)"
fi
if [ -f "$HOME/.dircolors" ] ; then
    eval "$(dircolors -b "$HOME/.dircolors")"
fi
alias ls='ls --color=auto'
alias grep='grep --color=auto'

# Prompt: red for root, green for everyone else.
NORMAL="\[\e[0m\]"
RED="\[\e[1;31m\]"
GREEN="\[\e[1;32m\]"
if [[ $EUID == 0 ]] ; then
    PS1="$RED\u [ $NORMAL\w$RED ]# $NORMAL"
else
    PS1="$GREEN\u [ $NORMAL\w$GREEN ]\$ $NORMAL"
fi
unset RED GREEN NORMAL

# bash-completion, if it is installed.  Loads every completion in
# /usr/share/bash-completion/completions, including the package-user
# accounts for `su`.
if [ -r /usr/share/bash-completion/bash_completion ] ; then
    . /usr/share/bash-completion/bash_completion
fi

# Complete USER NAMES after su and friends.  bash-completion supplies this
# too, but these three cost nothing and work without it -- which matters on
# a package-user system, where `su - p_<tab>` is a daily action.
complete -A user su sudo passwd chage groups id

# End /etc/bashrc
BASHRC
chmod 644 "$_dest"
own_root "$_dest"
echo "# wrote $_dest"

# 3. make sure /etc/profile actually sources it, and profile.d
if [ -f /etc/profile ] && ! grep -q '/etc/bashrc' /etc/profile 2>/dev/null; then
    echo "# NOTE: /etc/profile does not source /etc/bashrc."
    echo "#   Interactive non-login shells read ~/.bashrc, which on this"
    echo "#   system should contain:  . /etc/bashrc"
fi

# 4. the package users' own bashrc: they share /etc/pkgusr/bashrc
if [ -f /etc/pkgusr/bashrc ] && ! grep -q '/etc/bashrc' /etc/pkgusr/bashrc; then
    printf '\n# colours, completion and the shared aliases\n[ -r /etc/bashrc ] && . /etc/bashrc\n' \
        >> /etc/pkgusr/bashrc
    echo "# package users now source /etc/bashrc too"
fi


# 5. THE SYSTEM LOCALE -- $LANG, and why a terminal says the locale is "C"
#
#     warning: foot: 'C' is not a UTF-8 locale, falling back to 'C.UTF-8'
#
# Nothing is compiled wrong when that appears: LANG is simply not in the
# environment.  LFS's own /etc/profile reads /etc/locale.conf, but BLFS's
# "The Bash Shell Startup Files" page REPLACES /etc/profile with one that
# reads /etc/profile.d/*.sh instead -- and its i18n.sh, the piece that
# exports LANG, is a separate block on that page that is easy to walk past.
# Take either route: this writes both files, and neither profile minds the
# other's.
#
# Without it every program falls back to the C locale: sorting, dates,
# translated messages, and anything that has to decide whether a byte is a
# character.
LOCALE_CONF="${SHELL_ENV_LOCALE_CONF:-/etc/locale.conf}"   # overridable, for tests
I18N_SH="${PROFILE_D:-/etc/profile.d}/i18n.sh"
LFS_CONFIG_JSON="${LFS_STORE:-/usr/share/lfs}/config.json"
_norm() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/utf-8/utf8/; s/-//g'; }
_have_locale() {
    [ -n "$1" ] || return 1
    locale -a 2>/dev/null | while read -r l; do
        [ "$(_norm "$l")" = "$(_norm "$1")" ] && echo yes
    done | grep -q yes
}

# WHAT THIS MACHINE ALREADY SAYS IT WANTS, in order.  Nothing is guessed
# from the keyboard or the timezone: a wrong locale is worse than none.
conf_lang="$(sed -n 's/^[[:space:]]*LANG=//p' "$LOCALE_CONF" 2>/dev/null \
             | tr -d '"'"'"' ' | head -n1)"
asked="${LFS_LOCALE:-$conf_lang}"
[ -n "$asked" ] || asked="$(sed -n 's/.*"locale"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
                            "$LFS_CONFIG_JSON" 2>/dev/null | head -n1)"
# A NAME IS NOT A LOCALE UNTIL glibc HAS BUILT IT.  locale.conf may well name
# one nobody ever generated, and then LANG is set to something that does not
# exist -- which looks exactly like not setting it at all.
want=""
for _c in "$asked" en_US.UTF-8 C.UTF-8; do
    if _have_locale "$_c"; then want="$_c"; break; fi
done
if [ -n "$asked" ] && [ "$(_norm "$asked")" != "$(_norm "${want:-}")" ]; then
    echo "!! $asked is asked for but not installed (see: locale -a)"
    echo "#   make it as glibc's package user:  localedef -i ${asked%%.*} -f UTF-8 $asked"
    [ -n "$want" ] && echo "#   using $want until then"
fi

if [ -z "$want" ]; then
    echo "!! no UTF-8 locale is installed -- \$LANG cannot be set to one"
    echo "#   glibc builds them; the archive is glibc's, so make one as its"
    echo "#   package user (p_glibc here) rather than as root:"
    echo "#     localedef -i en_US -f UTF-8 en_US.UTF-8"
    echo "#   then run this step again."
else
    case "$(_norm "$want")" in
        *utf8) ;;
        *) echo "!! $want is not a UTF-8 locale -- a terminal will still complain" ;;
    esac
    if [ -f "$LOCALE_CONF" ] && [ "$(_norm "$conf_lang")" = "$(_norm "$want")" ]; then
        echo "# $LOCALE_CONF already says LANG=$conf_lang"
    elif [ -f "$LOCALE_CONF" ]; then
        echo "# $LOCALE_CONF says LANG=${conf_lang:-nothing} -- left alone (it is yours)"
        echo "#   $want is what works here; change it there if you want it"
    else
        printf 'LANG=%s\n' "$want" > "$LOCALE_CONF"
        chmod 644 "$LOCALE_CONF"; own_root "$LOCALE_CONF"
        echo "# wrote $LOCALE_CONF (LANG=$want)"
    fi
    # i18n.sh: JUDGED BY WHAT IT PRODUCES, NOT BY WHO WROTE IT.
    #
    # BLFS's page ships an i18n.sh of its own, and it is usually already
    # there -- `. /etc/locale.conf` and export what came out.  "Exists and is
    # not ours, left alone" would have been the end of it, and $LANG would
    # still be empty: the file was never the problem, the missing
    # /etc/locale.conf above was.  So source it in an empty environment and
    # look at the LANG that comes out.  TERM is set to something that is not
    # `linux`, because both the LFS and BLFS versions special-case the
    # console with a hard-coded C.UTF-8.
    _i18n_gives() {
        env -i HOME=/root TERM=xterm bash --noprofile --norc -c \
            ". \"\$1\" >/dev/null 2>&1; printf '%s' \"\${LANG:-}\"" _ "$1" 2>/dev/null
    }
    # WHOSE FILE IS IT.  Three writers put an i18n.sh here and all three can
    # leave LANG unset, so all three are ours to replace:
    #   this script          -- its own marker
    #   the book             -- `Begin /etc/profile.d/i18n.sh`, placeholder
    #                           LANG that was never filled in
    #   lfs-helper           -- its marker, and before 1.14.298 an i18n.sh
    #                           with the export COMMENTED OUT:
    #                               : # export LANG=en_US.UTF-8
    #                           which is what is on a machine built with it
    _ours_i18n() {
        grep -q '^# written by stacks/shell-env.sh' "$1" \
        || grep -q '^# written by lfs-helper' "$1" \
        || grep -q 'Begin /etc/profile.d/i18n.sh' "$1" \
        || grep -q '^[[:space:]]*:[[:space:]]*#[[:space:]]*export LANG=' "$1"
    }
    got=""
    [ -f "$I18N_SH" ] && got="$(_i18n_gives "$I18N_SH")"
    if [ -f "$I18N_SH" ] && [ "$(_norm "$got")" = "$(_norm "$want")" ]; then
        echo "# $I18N_SH already gives LANG=$got -- left alone"
    elif [ -f "$I18N_SH" ] && ! _ours_i18n "$I18N_SH"; then
        # not ours, and not the book's either: somebody wrote this on purpose
        echo "# $I18N_SH is hand-written and gives LANG=${got:-nothing} -- left alone"
        echo "#   $want is what this machine has; set it there, or delete the file"
    else
        if [ -f "$I18N_SH" ]; then
            bak="$I18N_SH.bak-$(date +%Y%m%d-%H%M%S)"
            cp -p "$I18N_SH" "$bak" \
                && echo "# $I18N_SH gave LANG=${got:-nothing} -- replaced (backup: $(basename "$bak"))"
        fi
        cat > "$I18N_SH" <<'I18N'
# written by stacks/shell-env.sh -- safe to delete, regenerated
# Begin /etc/profile.d/i18n.sh
#
# $LANG for every login shell, from /etc/locale.conf.  BLFS's /etc/profile
# reads this directory; LFS's reads /etc/locale.conf itself.  Either way the
# locale comes from one file.
if [ -r /etc/locale.conf ]; then
    . /etc/locale.conf
    export LANG
    if [ -n "${LC_ALL:-}" ]; then export LC_ALL; fi
fi
# less(1) needs telling separately -- it reads this, not the locale.
export LESSCHARSET="${LESSCHARSET:-utf-8}"
# End /etc/profile.d/i18n.sh
:
I18N
        chmod 644 "$I18N_SH"; own_root "$I18N_SH"
        echo "# wrote $I18N_SH (exports LANG from $LOCALE_CONF)"
    fi
    if [ "$(_norm "${LANG:-C}")" != "$(_norm "$want")" ]; then
        echo "#   this shell still has LANG=${LANG:-unset}: /etc/profile.d is read at"
        echo "#   LOGIN, so log in again -- or now:  . $I18N_SH"
    fi
fi

echo "# done -- open a new shell, or:  . /etc/bashrc"

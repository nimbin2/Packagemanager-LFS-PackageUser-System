#!/bin/bash
# shell-env.sh -- interactive shell environment: coloured ls, bash
# completion, and username completion for su (root step, idempotent).
#
# BLFS's "The Bash Shell Startup Files" page writes /etc/profile and
# /etc/bashrc, and /etc/bashrc is what makes ls colourful -- it evals
# dircolors and aliases ls --color=auto.  It is a config page, not a
# package, so nothing in a package stack ever ran it.
#
# bash-completion is not a BLFS package at all; it comes from upstream and
# is a `tar` entry in the stack beside this script.
set -u

# 1. /etc/dircolors -- the database ls colours come from
if [ ! -f /etc/dircolors ]; then
    if command -v dircolors >/dev/null 2>&1; then
        dircolors -p > /etc/dircolors
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

echo "# done -- open a new shell, or:  . /etc/bashrc"

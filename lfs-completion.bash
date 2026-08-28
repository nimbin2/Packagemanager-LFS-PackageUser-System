# Bash completion for the LFS package-user toolchain.
#
#   install:  cp lfs-completion.bash /usr/share/bash-completion/completions/lfs
#             ln -sf lfs /usr/share/bash-completion/completions/blfs
#             ln -sf lfs /usr/share/bash-completion/completions/packagemanager
#             ln -sf lfs /usr/share/bash-completion/completions/lfs-helper
#   or just:  source lfs-completion.bash
#
# Subcommands come from each tool's own --help, so this does not go stale when
# a command is added -- there is no second list to keep in sync.

_lfs_tool_subcommands() {
    local tool="$1" parent="${2:-}"
    # argparse prints the subcommand list as a {a,b,c} choices line -- that is
    # exact, unlike scraping indented help text, where a wrapped description
    # line looks just like a command name.
    local help out

    # lfs-helper is a bash script: its usage lists commands as
    #     lfs-helper <command> ...
    # so take the word after the tool's own name.
    case "$tool" in
        *lfs-helper)
            "$tool" --help 2>/dev/null \
                | grep -oE '^    lfs-helper [a-z][a-z0-9-]*' \
                | awk '{print $2}' | sort -u
            return ;;
    esac

    help="$("$tool" $parent --help 2>/dev/null)"

    # argparse usually prints the subcommands as a {a,b,c} choices line, which
    # is exact.  A parser with metavar= set (the top level here) shows the
    # metavar instead, so fall back to the entry lines: a command is indented
    # exactly four spaces, while a wrapped description is indented much more.
    out="$(printf '%s\n' "$help" | grep -oE '\{[a-z][a-z0-9,_-]*\}' | head -n1 \
           | tr -d '{}' | tr ',' '\n')"
    if [ -z "$out" ]; then
        out="$(printf '%s\n' "$help" \
               | sed -n '/^positional arguments:/,/^options:/p' \
               | grep -E '^ {4}[a-z][a-z0-9_-]*( |$)' \
               | awk '{print $1}')"
    fi
    printf '%s\n' "$out"
}

_lfs_packages() {
    # Accounts own a directory under /usr/src, grouped by kind, and carry a
    # prefix (p_gcc).  Completing on the raw directory names would offer
    # "p_gcc" where every command wants "gcc", so strip it back off.
    # Still the cheapest list of what is installed, and no python needed.
    local d n root
    for root in "${LFS_PKGUSR_ROOT:-/usr/src/pkgusr}" \
                "${LFS_CFGUSR_ROOT:-/usr/src/cfg}"; do
        for d in "$root"/*/; do
            [ -d "$d" ] || continue
            n="$(basename "$d")"
            printf '%s\n' "${n#${LFS_PKGUSR_PREFIX-p_}}"
        done
    done
}

_lfs_book_versions() {
    local d
    for d in /usr/share/lfs/books/LFS-BOOK-*-NOCHUNKS.html; do
        [ -e "$d" ] || continue
        basename "$d" | sed 's/^LFS-BOOK-//; s/-NOCHUNKS\.html$//'
    done
}

_lfs_snapshots() {
    local d
    for d in /usr/share/lfs/snapshots/*.tar*; do
        [ -e "$d" ] || continue
        basename "$d" | sed 's/\.tar\(\.[a-z]*\)\?$//'
    done
}

_lfs_complete() {
    local cur prev cmd tool
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    tool="${COMP_WORDS[0]}"
    cmd="${COMP_WORDS[1]:-}"

    # an option's argument
    case "$prev" in
        --book|--book-file)
            COMPREPLY=($(compgen -W "$(_lfs_book_versions)" -- "$cur")); return ;;
        --phase)
            COMPREPLY=($(compgen -W "all unpack build install configure test" \
                         -- "$cur")); return ;;
        --jobs) return ;;
    esac

    # options, whenever the word starts with a dash
    if [[ "$cur" == -* ]]; then
        local opts
        opts="$("$tool" ${cmd:+$cmd} --help 2>/dev/null \
                | grep -oE '(^|\s)--[a-z][a-z-]*' | tr -d ' ' | sort -u)"
        COMPREPLY=($(compgen -W "$opts" -- "$cur"))
        return
    fi

    # first word: the tool's own subcommands
    if [ "$COMP_CWORD" = 1 ]; then
        COMPREPLY=($(compgen -W "$(_lfs_tool_subcommands "$tool")" -- "$cur"))
        return
    fi

    # second word: either a nested subcommand, or an argument
    case "$cmd" in
        build-system|user|nimgnu|pip|script|snapshot)
            if [ "$COMP_CWORD" = 2 ]; then
                COMPREPLY=($(compgen -W \
                    "$(_lfs_tool_subcommands "$tool" "$cmd")" -- "$cur"))
                return
            fi ;;
    esac

    case "$cmd" in
        install|update|remove|info|deps|rdeps|order|sources|which-package|script)
            COMPREPLY=($(compgen -W "$(_lfs_packages)" -- "$cur")) ;;
        set-default|fetch|set-book)
            COMPREPLY=($(compgen -W "$(_lfs_book_versions)" -- "$cur")) ;;
        build|done|undone|fix-ownership|fix-perms|add-user)
            COMPREPLY=($(compgen -W "$(_lfs_packages)" -- "$cur")) ;;
        *)
            if [ "${COMP_WORDS[1]}" = "snapshot" ]; then
                COMPREPLY=($(compgen -W "$(_lfs_snapshots)" -- "$cur"))
            else
                COMPREPLY=($(compgen -f -- "$cur"))
            fi ;;
    esac
}

complete -F _lfs_complete lfs
complete -F _lfs_complete blfs
complete -F _lfs_complete packagemanager
complete -F _lfs_complete lfs-helper

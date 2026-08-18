# pkgusr package manager for BLFS / LFS

> **🎲 100% vibecode** — this whole toolchain was built by prompting an AI.
> It's not a polished distro tool. That said, The Prompter
> actually runis it on his own BLFS/LFS system.
> Still, read the code and test on something
> disposable before you point it at yours.

A small toolchain for building and maintaining a BLFS/LFS system with the
**package-user** scheme: every package is built and owned by its own user, so
you always know which package installed which file, and removing a package is
just removing its files.

It works **offline** from a downloaded copy of the BLFS book — no network needed
to resolve dependencies, versions, or build commands.

## The package-user scheme

Instead of installing everything as `root`, each package gets its own
unprivileged user that owns that package's files. Because ownership maps 1:1 to a
package, you can list exactly what a package installed (via `find` / the
`pkg.lst` manifest), spot stray files, and uninstall by removing one user's
files — no separate package database to drift out of sync. Shared write access to
install directories is granted through an `install` group, and packages that drop
files into another package's tree are tracked with **collector groups**.

This is the classic LFS "More Control and Package Management" hint; if the idea
is new to you, read it first:
<https://www.linuxfromscratch.org/hints/downloads/files/more_control_and_pkg_man.txt>

## The three programs

- **`blfs`** — parses the BLFS book (one cached HTML copy) and answers questions
  about it: versions, dependencies, build order, and it generates phased install
  scripts. Machine-readable output; safe to script against.
- **`packagemanager`** — the thing you use day to day: install, update, verify,
  and manage package-users, their scripts, and their groups.
- **`packagemanager_install`** — the privileged engine `packagemanager` calls to
  run an install script *as the package user*. You normally don't call it
  directly.

Run any command with `-h`/`--help` for its options — this README stays short on
purpose and does **not** document every flag.

## What makes it different

- **One user per package.** Files are owned by the package's user; `verify`
  tells you what's installed and *why* (see validation below).
- **Phased install scripts.** Generated scripts split into
  `unpack | build | test | install | configure`. You can re-run a single phase —
  e.g. `packagemanager script install <pkg>` reinstalls without recompiling.
- **Real install validation.** A package counts as *installed* only when it can
  be validated: the script's `installed_program/library/directory` exist, a
  versioned directory matches, or a per-package `validate` command reports the
  right version (`verify --set-validate-command <pkg>`). Otherwise it's
  *unvalidated* — looks installed but couldn't be confirmed.
- **Dry-run by default.** `install`/`update` show a plan first; add `--run` to
  execute. Plans are cached, so `--run` reuses/resumes them. `--select` lets you
  pick a subset (`1,3,5-8`, `all,!4`, `!4,!7`).
- **Safe updates.** `update` shows *required/recommended by which package*,
  can rebuild reverse-dependencies (`-R`), and `--clean` removes old-version
  files an upgrade left behind while keeping configs and the source tree
  (install → clean → reapply install, so nothing current is lost).
- **Edit-tracked scripts.** Generated scripts carry a checksum, so
  `script-status` shows whether you edited a script or the book moved ahead of
  it. `migrate-scripts` upgrades unedited scripts automatically and opens
  `vimdiff` (new on the left, yours on the right) only for the ones you changed.
- **Custom & git packages.** `template` scaffolds an install script for anything
  not in the book, including git repos; `install`/`update --local <script>` build
  from it.

## Typical flow

```sh
packagemanager config --collector-prefix nimgnu --user-prefix u --main-user <you>
packagemanager install <pkg>            # dry-run plan (deps first)
packagemanager install <pkg> --run      # build + install
packagemanager update                   # what's outdated
packagemanager update <pkg> --run       # upgrade (add --clean to drop old files)
packagemanager verify                   # installed / unvalidated / not installed
packagemanager errors                   # failures from the last run + log paths
```

## Configuration

`packagemanager config` shows and sets a few things once, up front:

- **`--collector-prefix`** — the prefix for *collector groups*. When package A
  needs to install files into package B's directory, those files are made
  group-owned by a collector group named `<prefix>_<owner>` (e.g.
  `nimgnu_python-modules`), and A is added to it. This is how cross-package
  installs stay tracked under the package-user scheme instead of silently
  becoming root-owned. Pick a short, distinctive prefix — it namespaces every
  collector group on your system.
- **`--user-prefix`** — the prefix for *shared users* you create to **run**
  software (as opposed to the package-users that **build** it). A shared user is
  named `<prefix>_<name>` (e.g. `u_media`) and can be granted supplementary
  groups. Keeps run-time accounts clearly separate from package accounts.
- **`--main-user`** — your normal login account (used as a sensible default in a
  few places).
- **`--editor`** / **`--difftool`** — the editor for `verify --set-validate-command`
  and the diff tool for `migrate-scripts` (default `vimdiff`).

Set them once, e.g.:

```sh
packagemanager config --collector-prefix nimgnu --user-prefix u --main-user <you>
```

Storage locations are shown by `packagemanager paths`.

## Notes

- Most operations need root (they create users, groups, and write system files).
- Set `BLFS_BOOK_FILE` to your book HTML, or point the store with `BLFS_STORE`.
- Not for reproducing distro packaging — this is for hand-built BLFS/LFS systems.

# Handoff: SysV-on-13.0 session

Base for everything here was the 1.11.26 files.zip + HANDOFF.md.
Read the DRIFT section before overwriting anything.

## New tool: lfs-sysvbook 1.0.0 (build 62ebe64)

LFS 13.0 dropped the SysV edition. This tool grafts the SysV flavour of the
last SysV book (12.4, donor) onto a systemd-only release (target) and stores
the result as a normal book in the lfs store, with wget-list + md5sums
generated offline from the books' own chapter 3.

    lfs fetch 12.4 && lfs fetch 13.0-systemd
    lfs-sysvbook make                       # -> 13.0-sysv
    lfs-sysvbook check --book 13.0-sysv     # 12 checks, fails loudly
    lfs --book 13.0-sysv run

What make does: replaces Systemd section with 12.4's "Udev from Systemd",
removes D-Bus, inserts Sysklogd + SysVinit after E2fsprogs, swaps chapter 9
and the fstab wholesale, filters systemd-* accounts out of 7.6's heredocs,
applies the three SysV configure-flag edits (Man-DB, Procps-ng, Util-linux
ch8), relabels /etc/lfs-release and the kernel image to <out>. Transplanted
sections stay pinned at donor versions; everything else builds at target
versions. Section NUMBERS on transplanted pages keep donor numbering --
cosmetic, build order is by document position. Rules are declarative tables
at the top of the file for future migrations (make --target 13.1-systemd).

Verified: a full 13.0-sysv build ran into chapter 8 + BLFS bootstrap on the
real system.

## lfs 1.11.26 -> 1.11.29 (build 42ca92a)

1. "download the sources" pipeline step: done = every basename of the
   CURRENT book's wget-list present in $LFS/sources, not "any tarball
   exists". Leftovers from an older book no longer skip the download step.
   Shows "download the sources (N missing)". Falls back to the old
   heuristic only when no wget-list is cached.
2. Fresh-run confirmation in cmd_bs_run (both `build-system run` and the
   `lfs run` alias): mounted tree with no layout yet + tty -> prints the
   book and the whole session config once, asks [Y/n/e(dit)]. n stops with
   pointers, e runs _prompt_session_config(force=True). Never asks on
   resume or non-interactively.
3. _pkg_glob_for: last-resort infix pattern name-*version (SQLite-3510200
   ships as sqlite-autoconf-3510200.tar.gz -- new package in 13.0, broke
   unpack). Unpack doc-filter extended with infix spellings
   (*-doc-*|*-docs-*|*-html-*|*-man-pages-*|*-tests-*) so the new pattern
   cannot grab sqlite-doc-* or systemd-man-pages-*. Unit-tested: sqlite,
   systemd, tcl, expect, python all pick the right tarball.
   After installing: regenerate scripts (gen-chroot-scripts --run
   --overwrite) so the fix reaches the chroot.

## packagemanager_install 1.11.26 -> 1.11.27 (build d6b1854)

The "could not write to <dir>" failure box printed a wrong remedy
(add-dir-to-sysgroup with swapped args, prefixed name for script install).
Now: reads the blocking dir's group owner; if it is already a collector
group it prints `packagemanager sysgroup add <group> <user>`; only an
unshared dir gets add-dir-to-sysgroup (correct order: group first) plus the
membership step. `script install` line uses the bare package name.
Hit in the wild: p11-kit vs /usr/share/zsh/site-functions (nimgnu_zsh).

## Makefile / README.md

Makefile: lfs-sysvbook added to TOOLS (install/uninstall/check covered).
README.md: tool table row + short "SysV on LFS 13.0+" section.

## DRIFT -- read before installing

The user's installed lfs-helper reports 1.11.53; the files.zip copy is
1.11.26. Do NOT overwrite it from this set. Three pending lfs-helper fixes
are in lfs-helper-1.11.53.patchnotes.txt (progress line before the manifest
scan, chown 0:0 instead of root:root pre-7.6, mkdir /tmp early); apply them
to the CURRENT lfs-helper. The scripts-vs-tools version-mismatch warning in
the chroot is this drift, advisory only; it goes away once the version
lines agree again.
Also check `packagemanager_install --version` before overwriting: if it is
newer than 1.11.26, port the remedy fix instead. packagemanager and blfs
were not touched this session.

## Open items

- lfs-helper fixes above: pending, need the current 1.11.53 file.
- blfs set-default flavour issue from the old HANDOFF: unresolved, now
  doubly relevant (BLFS must not pick a systemd-flavour default).
- Not tested: booting the finished 13.0-sysv system (build reached BLFS
  bootstrap; boot untested).

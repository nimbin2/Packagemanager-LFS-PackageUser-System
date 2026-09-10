# lfs-pkgusr — handoff

Tools for building Linux From Scratch and Beyond LFS as **package users**: one
account per package, so every file on the system has an owner, and
`packagemanager verify` can say what is installed and what is not.

Written for a **SysV** system (no systemd) built from the **systemd** BLFS
book, because BLFS stopped publishing a SysV edition after 12.4.

    all five tools at 1.14.146
    lfs               c0858da
    lfs-helper        bf6756c
    packagemanager    367a690
    blfs              877e4cb
    lfs-phases        ba72201
    lfs-kernel        1aa3396   (no version line of its own)
    lfs-sysvbook      62ebe64   (1.0.0; untouched since it was written)

**`BUILD.md` is the one document for building a whole system**, host to
desktop, with what to configure before each step. README.md points at it.
Keep it true: when a command or a config key changes, it changes there too.

`test_lfs_crosschain.sh` is the regression suite. It no longer finishes inside
one command slot in the authoring sandbox; run it whole on a real machine, or
one block at a time (each starts `# ---- <title>`). One check fails by
environment only: **rc.site** needs a SysV LFS book on disk.

The full per-release history — 144 entries, every bug and what it taught — is
`HANDOFF-history.md`. It is worth grepping when something looks familiar; it
is too long to read.

---

## The state of the machine

A ThinkPad-class AMD Renoir laptop, SysV init, 93 package accounts, collector
prefix `nimgnu`, package prefix `p`.

**Built and verified: 319 packages**, `packagemanager verify` clean. That
includes the whole sway stack (wlroots, sway, swaybg, foot, seatd, elogind,
webkitgtk, pipewire, mesa, gtk3/4, gstreamer), the network stack (wpa_supplicant,
libnl, iptables-nft with libnftnl, net-tools), services (dbus, alsa, bluetooth,
acpid, fcron, blfs-bootscripts) and bash-completion.

**Kernel 7.2.4 built, installed and verified** by `lfs-kernel`: image on the
ESP, modules with a depmod index, headers, v4l2loopback, and 15 embedded
firmware blobs. `lfs-kernel verify` reports 32 checks green.

**The machine is still running 7.2.0.** 7.2.4 is on the ESP as
`vmlinuz_new`, beside the working `vmlinuz`, and has never been booted.
Nothing is recorded as known-good yet, which is correct and deliberate.

**Nothing in the desktop has ever run.** The last sway attempt failed in the
chroot for want of `/run/udev`, which is the expected result there.

---

## What to do next, in order

1. **Point rEFInd at `/boot/efi/EFI/NimGnu/vmlinuz_new`** as a second entry.
   Keep the existing `vmlinuz` entry: it is the way back.
2. **Reboot into 7.2.4.** Then `uname -r`, `lfs-kernel verify` (last-good
   should read "it is running now"), and `dmesg | grep -i firmware` — that
   last one is the definitive `FIRMWARE_ONLY` list for this hardware.
3. **Start sway** as the desktop user, on a tty: `sway` (an alias for their
   own `sway_start`). The seat comes from `/usr/bin/seatd-<user>`, a setuid
   wrapper compiled for one username; there is no seatd daemon and no `seat`
   group. If it fails, `stacks/sway-session.sh`'s launcher checks the three
   things that were each a separate bug: the wrapper, `/run/udev`, and
   whether this tty is the active console.
4. **Bring up wifi.** `wifi` is in `/bin`, `wpa_supplicant`/`wpa_cli` in
   `/usr/sbin`. Still missing: `/etc/sysconfig/ifconfig.wifi0` (with
   `SERVICE=wpa`) and the per-SSID files under
   `/etc/sysconfig/wpa_supplicant/`. Note their `wifi` script calls
   `ifup $IFNAME wifi0` with `IFNAME` unset while `INTERFACE` is set and
   unused — one of the two should go.
5. **make-ca's weekly job.** The systemd book enables a timer, which the shim
   skips. fcron exists now, so add the 12.4 book's cron entry by hand:

       cat > /etc/cron.weekly/update-pki.sh << "EOF"
       #!/bin/bash
       /usr/sbin/make-ca -g
       EOF
       chmod 754 /etc/cron.weekly/update-pki.sh

Smaller, none blocking: `dbus` was built before `[dbus] systemd = disabled`
went into machine.conf (rebuild or accept); a stray `.service` from
at-spi2-core sits in `/usr/lib/systemd/user`; root cannot log in after boot
and the cause is unknown — wants `ls -l /etc/shadow`, `getent shadow root`,
and whether `/bin/bash` is in `/etc/shells`.

---

## The tools

    lfs                 the LFS build: interview, chroot, chapters 5-8
    lfs-helper          the in-chroot driver (bash; no Python in the chroot)
    packagemanager      BLFS packages, stacks, accounts, verify
    blfs                turns book pages into install scripts
    lfs-phases          the phase runner every generated script sources
    lfs-kernel          build/install/verify a kernel and its firmware
    lfs-sysvbook        graft the 12.4 SysV flavour onto a systemd-only LFS
                        book -> 13.0-sysv (LFS only; BLFS has no counterpart
                        yet, see deferred).  Its own notes:
                        HANDOFF-sysv-session.md (old; its DRIFT section is
                        history now)

Everything installs with `make install` (default prefix `/usr/bin`; `make
clean` and `make uninstall` exist). `lfs run` refreshes the tools, the stack
files and `kernel.conf` into the chroot; the list of tools comes from the
Makefile's `TOOLS` line, so a new tool needs no second edit.

### Things worth knowing before changing anything

- **Config files under `/etc/pkgusr/` are never overwritten once edited.**
  `make install` records what it shipped in `stacks/.shipped/`; if your copy
  still matches that record it is updated, otherwise the new one lands as
  `.new` and `packagemanager stack <name> --take-new` takes it.
- **`--only <entry>`** runs one stack entry, ignoring the done-cache.
- **`packagemanager reclaim <pkg> --run`** gives a package back files another
  package took from it.
- **`lfs-kernel`** is configured by `/etc/pkgusr/kernel.conf` alone:
  `VERSION` (`latest` asks kernel.org), `ESP`+`KERNEL_NAME` (which decides
  test vs real kernel), `JOBS`, `CONFIG_FROM`, `CONFIG_REFRESH`,
  `FIRMWARE_FROM`/`FIRMWARE_ONLY`, `HEADERS`, `V4L2LOOPBACK`. `lfs-kernel
  list` shows what kernel.org offers; `lfs-kernel verify` checks the result.

---

## Rules this project learned the hard way

These are the ones that cost releases. They are worth applying to new code
without waiting for the failure that proves them again.

**Confirm your own effects.** A zero exit is not proof: a phase whose log
says "make: *** Error 1" failed whatever it returned; a write must be read
back (`usermod -d` returned 0 and changed nothing, three times); a step that
installed nothing must not be cached as done; a manifest must exist where
`verify` looks, not merely be written. Five separate bugs, one rule.

**A message that names a thing must be checked against the thing.** Paths,
package names, flags, commands — all machine-checkable, and all were wrong at
some point. The suite now asserts that every flag the failure box suggests is
one the command accepts. If a message contains a path, build it with the code
that builds that path.

**Prose is not code.** A book's example, a NOTE mentioning `cmake`, a shell
diagnostic saying `not: command not found` — five filters and one *injector*
were caught treating text about a command as the command. Anything scanning
generated scripts skips comments unless it has a reason not to.

**Derive lists, never repeat them.** Adding one file meant editing four
places that enumerated files (Makefile, chroot refresh, `.shipped`, the tool
list). When adding something, grep for a sibling's name first: every place it
appears is a place the new thing belongs.

**Two settings must not answer one question.** `pkgusr_home` and
`pkgusr_subdir` could each be read as "where homes live", and two programs
read them differently, so every account had two homes and two tools took
turns correcting each other.

**A package user owns files, not identity.** Ownership, setuid bits, system
accounts and anything on a vfat mount are root's. Do those explicitly, once,
and record what was refused — a silent refusal becomes a mystery hours later
in a different phase.

**Handing over files is for genuine overlap.** A package installing another
package's whole output is duplicating, not overlapping; stop the bundling
(`wrap_mode=nodownload`) rather than transferring ownership one file per
retry round.

**Report what you found, not what you expected.** Four releases went into
guessing linux-firmware's directory layout; one `git ls-files` answered it.
When a tool needs a fact about someone else's data, the first version should
go and read it.

**Say it before it takes a while.** A tool silent for two minutes is
indistinguishable from one that has hung.

**A check must be cheaper and quieter than the thing it checks.** `verify`
was resolving versions over the network and would have created accounts. If
a check needs the network, the accounts and the config to be right, it cannot
tell you whether they are.

**Never record a guess as a fact.** `last-good` named a kernel that had never
booted, because an empty file looked like something to fill in.

---

## This session (1.14.146)

- `BUILD.md` written; README tightened (kernel caveat was stale: it said
  nothing builds a kernel, `lfs-kernel` does).
- `lfs-helper`: the end-of-build message pointed at book 10.3 by hand;
  now points at `kernel.conf` + `lfs-kernel`.
- `stacks/sway-session.sh` hardcoded one username as the desktop user while
  `mytools.sh` read `/etc/pkgusr/desktop-user` -- two settings, one
  question.  Both now take `LFS_DESKTOP_USER` or that file, and both write
  it.  Installed copies of the stack file are unedited, so `make install`
  updates them in place.
- Not run: the regression suite (sandbox slot).  `bash -n` / `py_compile`
  and `--version` only.

## Deferred tool work

None of this blocks the machine.

- The regression suite exceeds one execution slot; make it splittable
  (`--from N`, or per-tool) before it grows further.
- Three functions move stack files (Makefile, chroot refresh, `--take-new`);
  they should be one, and the whole `.new` mechanism deserves rethinking
  around a single source of truth.
- Should the CONFIGURE phase run as root? Every BLFS "Configuring" section is
  written for root. Files it creates would become root-owned, which the file
  tracking does not expect. Decide at the start of a session, not the end.
- `needs=` is set for sway only; the other git entries' dependencies are
  discoverable only by building them. Each such failure deserves a line in
  the stack, not a package installed by hand.
- `--check-refs` cannot see tar URLs. A `have=`-style check for tarballs
  would close the gap libnftnl exposed.
- The "busy tree" test is flaky: it races a `sleep` in the process table and
  should use a private marker.
- The rc.site test should say it needs a SysV book rather than failing.
- The whole-book invariants (954 scripts, 0 syntax errors, 0 empty install
  phases) have caught or confirmed nearly every filter change. Extend them to
  build phases, listing the known-empty pages by name.
- A BLFS-SysV counterpart tool: apply 12.4's init differences to 13.x pages.
  `blfs diff-init` is the survey that would drive it.

# Build a whole system

From an empty partition to a booted SysV desktop, with every file owned by a
package user. One document, in build order. Every step says what to
**configure first**, because the tools read their settings when a step
starts, not before.

> **100% vibecode, but tested.** These are the commands that built the
> reference machine. Dry run is the default everywhere; `--run` applies.

---

## The shape of it

| Where | You run | It does |
|---|---|---|
| host | `lfs run` | books, session, sources, cross toolchain, enters the chroot |
| chroot | `lfs-helper build-all` | chapters 7-9, one package user each |
| host | `lfs build-system install-tools --run` | hands over from `lfs-helper` to `packagemanager` |
| chroot | `packagemanager bootstrap --run` | wget, Python modules, BLFS book, certificates |
| chroot | `packagemanager stack <name> --run` | BLFS packages, in stacks |
| chroot | `lfs-kernel` | kernel, modules, firmware, headers |
| host | `lfs-helper build refind` | a boot entry beside your current one |
| booted | `packagemanager verify` | is everything where it should be |

`lfs run` and `lfs-helper build-all` both continue from wherever they
stopped. Run them again after a failure, a cancel or a reboot.

---

## 0. Install the tools on the host

```sh
make install                # /usr/bin; make uninstall exists
lfs --version
```

Needs Python 3.9+, `beautifulsoup4`, `requests`, bash, tar.

---

## 1. Books

LFS stopped shipping a SysV edition with 13.0. Make one:

```sh
lfs fetch 12.4                     # donor: last SysV book
lfs fetch 13.0-systemd             # target: current release
lfs-sysvbook make                  # -> 13.0-sysv in the store
lfs-sysvbook check --book 13.0-sysv
lfs build-system set-book 13.0-sysv
```

For a plain systemd system, `lfs fetch 13.0-systemd` and `set-book` that.

`lfs run` also asks for the **BLFS** book and copies it into the tree. Say
yes: the built system cannot fetch it until it has wget, and wget is looked
up in that book.

---

## 2. Session and settings

**Configure first.** These become the generated scripts; a wrong value only
shows up hours later inside the chroot.

```sh
lfs build-system session           # the interview: partition, prefixes, locale,
                                   # timezone, hostname, login account, strip
lfs config --target --ask          # the BUILT system's prefixes and homes
lfs config                         # everything else, grouped
```

Worth setting before `run`:

| Key | Default | Why |
|---|---|---|
| `lfs_mount`, `lfs_device` | `/mnt/lfs`, – | the partition; the tool refuses a host path |
| `pkgusr_prefix` / `cfguser_prefix` / `collector_prefix` | `p` / `cfg` / `sysgroup` | account names: `p_gcc`, `cfg_bootscripts`, `sysgroup_glibc`. Hard to change later |
| `locale`, `charmap`, `paper_size`, `timezone` | `en_US.UTF-8`, `UTF-8`, `A4`, – | baked into chapter 9 |
| `hostname`, `network` | `lfs`, `dhcp` | `static` writes interface files; `dhcp` expects dhcpcd from BLFS |
| `main_user` | – | your login. `init-accounts` creates it (group `users`) and asks for root's and its password. Blank = root only, no password |
| `makeflags` | `-j$(nproc)` | |
| `remove_tools` | no | delete `/tools` at the end; it is your way back if chapter 8 needs redoing |
| `bootloader`, `esp` | `none`, – | `refind` + `/boot/efi` generates a rEFInd step that only *adds* an entry |
| `collector_import_file` | – | groups export from a previous build; skips every sharing question |
| `strip` | off | strip debug symbols at the end, as each file's owner |

Change one: `lfs config <key> <value>`. See all with meaning: `lfs config --long`.

Stack files and `kernel.conf` are copied into the chroot by `lfs run`, so
edit those now too (sections 5 and 6 say what).

---

## 3. Host: up to the chroot

```sh
lfs run
```

On a fresh tree it prints the book and every session setting once and asks
`[Y/n/e(dit)]`. Then, in order: layout, sync-tools, lfs user, BLFS book,
sources (`get-sources` also downloads what `packagemanager bootstrap` will
need), cross toolchain (chapters 5-6), chroot prepare, script generation.
It ends inside the chroot.

Follow along or fix a step by hand:

```sh
lfs build-system next              # what is done, what is next
lfs build-system list              # every step and its state
lfs build-system snapshot save <name> --run
lfs build-system crosschain --list # the editable chapter 5-6 scripts
```

---

## 4. Chroot: the LFS system

```sh
lfs-helper next                    # where the build stands
lfs-helper build-all               # chapters 7-9
```

What happens along the way:

- Book 7.6 creates `/etc/passwd`; before it nothing can be owned.
  `init-ownership` runs right after and adopts everything built so far.
- A step that installs into another package's directory asks which
  collector group to use. Answers are saved; `lfs-helper export-groups`
  writes them out for the next build (`collector_import_file`).
- The first failure stops the run. Fix, then `build-all` again; it continues
  from that step. One step: `lfs-helper build <name> [--phase p] [--force]`.
- At the end the install directories become sticky and `/etc/passwd` is
  sorted. It then prints the two things left: the kernel and the bootloader.

Then hand over to the Python tools, from the **host**:

```sh
lfs build-system install-tools --run --force
```

It copies the tools, the book and the scripts in and writes
`/etc/pkgusr/packagemanager.conf` from your session settings. `--force`
because the Python modules `lfs` and `blfs` need are not there yet; the next
section's `bootstrap` installs them as package users. `packagemanager`
itself works now.

---

## 5. Chroot: BLFS

### Bootstrap

```sh
lfs build-system chroot resolv     # host: network inside the chroot
packagemanager bootstrap           # where you are, five stages
packagemanager bootstrap --run     # wget, Python modules, BLFS book, make-ca, certs
packagemanager blfs set-default 13.0-systemd
```

Stages 1-2 use tarballs `get-sources` already downloaded, so they work
offline. The rest needs the network `resolv` just gave you.

### Configure first

| File | What it holds |
|---|---|
| `/etc/pkgusr/stacks/machine.conf` | this machine's build options (`[mesa] gallium-drivers = radeonsi`, `[iptables] configure_args = --enable-nftables`, `[dbus] systemd = disabled`). Merged into generated scripts when they are born, so set it **before** the stack runs |
| `/etc/pkgusr/stacks/package-fixes.conf` | workarounds the tools ship. Replaced on every `lfs run`; put yours in `machine.conf`, which wins |
| `/etc/pkgusr/stacks/*.stack` | which packages, in order; `avoid` lines; pinned git refs |
| `/etc/pkgusr/desktop-user` | the login that owns the desktop. Set once with `LFS_DESKTOP_USER=<name>`; `sway-session` and `mytools` both read the file |

Files under `/etc/pkgusr/` are yours once edited. `make install` updates a
copy you never touched, otherwise it lands as `.new`
(`packagemanager stack <name> --take-new` accepts it).

### The stacks, in order

```sh
usermod -aG audio,video,input <name>          # the main_user from the interview
export LFS_DESKTOP_USER=<name>

packagemanager stack sway --check-refs        # every git ref still exists?
packagemanager stack sway --run               # desktop: wlroots, sway, foot, webkit, pipewire, mesa
packagemanager stack network --check-refs
packagemanager stack network --run            # wpa_supplicant, iptables-nft, net-tools
packagemanager stack services --run           # bootscripts, fcron, acpid, mytools, shell-env
```

`sway` includes `check kernel-sway`, which reads the running kernel's config
and fails naming the missing option. In the chroot that is the host kernel;
section 6 builds the real one.

Useful while a stack runs:

```sh
packagemanager stack sway --status            # how far, what is next
packagemanager stack sway --only <entry> --run
packagemanager errors                         # what failed, with logs
packagemanager verify                         # every package, with why
```

---

## 6. Kernel

**Configure first:** `/etc/pkgusr/kernel.conf`. It is installed, not
generated, so it can be edited before the first build.

| Key | Decide |
|---|---|
| `VERSION` | exact, or `latest` (asks kernel.org). `lfs-kernel list` shows what is there |
| `ESP`, `KERNEL_NAME` | *which* kernel this is. `vmlinuz_new` lands beside the working one; `vmlinuz` replaces it. Previous file is kept as `_old` |
| `JOBS` | leave a core free |
| `CONFIG_FROM`, `CONFIG_REFRESH` | `running` + `olddefconfig` for unattended; `oldconfig`/`menuconfig` to decide yourself |
| `FIRMWARE_FROM`, `FIRMWARE_ONLY` | `git` and a short list (`amdgpu amd-ucode amd intel`). Empty means 10 GB |
| `HEADERS`, `V4L2LOOPBACK`, `BOOTLOGO` | as you like |

```sh
lfs-kernel                         # build, install, record as p_linux
lfs-kernel verify                  # image, modules, depmod, headers, firmware
```

The kernel is a package: `packagemanager remove linux` takes it away. The
tree of the last kernel known to boot is never deleted, and nothing is
recorded as known-good until it has actually booted.

---

## 7. Bootloader

Nothing so far has written to any ESP, boot sector or partition table.
Either add an entry to your current bootloader by hand, or:

```sh
lfs config bootloader refind
lfs config esp /boot/efi
lfs-helper build refind --force    # adds beside what boots you today
```

Then point the entry at `ESP/KERNEL_NAME` from `kernel.conf`, keeping the
old entry as the way back.

---

## 8. Reboot and check

```sh
uname -r
lfs-kernel verify                  # last-good should now say "running now"
dmesg | grep -i firmware           # the definitive FIRMWARE_ONLY list
packagemanager verify
```

Things a first boot commonly still wants:

- **wifi:** `/etc/sysconfig/ifconfig.wifi0` with `SERVICE=wpa`, and one
  file per SSID in `/etc/sysconfig/wpa_supplicant/`.
- **certificates:** `make-ca -g` weekly, as a cron entry in
  `/etc/cron.weekly/` (the systemd book used a timer).
- **desktop:** log in on the active tty as the desktop user, run `sway`.
  The seat comes from `/usr/bin/seatd-<user>`, a setuid wrapper `mytools`
  built for that one name. If it fails, the launcher checks the wrapper,
  `/run/udev` and whether this tty is the active console.

---

## 9. Living with it

```sh
packagemanager install <pkg> --run           # a BLFS package, deps first
packagemanager update <pkg> --run            # what the book has newer
packagemanager which-package /usr/bin/foo
packagemanager reclaim <pkg> --run           # give files back another package took
packagemanager user create firefox --shared --share-dir --launcher   # an app account
lfs-kernel latest                            # try a newer kernel beside this one
```

A new BLFS release: `blfs fetch`, `packagemanager blfs set-default`,
`packagemanager script-status`, then `update`.

A new LFS release: `lfs-sysvbook make --target 13.1-systemd`, `check`, and
start again from section 2 with `collector_import_file` set.

---

## When something is wrong

| Symptom | Look at |
|---|---|
| `lfs run` stops | `lfs build-system next` names the step and the command |
| a chroot step fails | `/usr/src/lfs-pkgusr/logs/<step>.log`; `lfs-helper check-toolchain` |
| a stack entry fails | `packagemanager errors`; `--only <entry> --run` to retry one |
| files owned by nobody | `lfs-helper fix-orphans --run`, `packagemanager files_with_broken_id` |
| ownership drifted | `packagemanager verify --fix`; `lfs-helper fix-ownership --run` |
| tools and scripts disagree | `lfs build-system gen-chroot-scripts --run --overwrite` (host) |

# lfs-pkgusr

Build and maintain an LFS/BLFS system where **every package is owned by its own
user**.

> **100% vibecode, but tested.** Prompted into existence rather than hand
> written. Every fix carries a regression test. It builds my own system —
> read it before you point it at yours.

---

## What it does

Each package gets an unprivileged user that owns the files it installs.

- You always know which package installed which file.
- Removing a package is removing that user's files.
- A broken build cannot overwrite another package's files.

Directories shared by several packages are handled by **collector groups**
(`<prefix>_<owner>`), so a package may install into another's directory without
owning it.

Works **offline** from a downloaded copy of the books.

---

## The tools

| Tool | Runs | Does |
|---|---|---|
| `lfs` | host | Drives the whole build, chapters 1-10 |
| `lfs-helper` | inside the chroot | Builds each package as its user (bash, no Python needed) |
| `packagemanager` | built system | Installs and updates packages |
| `blfs` | built system | Reads the BLFS book, generates install scripts |
| `lfs-sysvbook` | host | Grafts SysV init onto a systemd-only LFS book |
| `lfs-phases` | everywhere | The runner every generated install script sources |
| `lfs-kernel` | booted system or chroot | Build, install and verify a kernel, its firmware and its headers |

---

## Install

```sh
make install                        # to /usr
make install PREFIX=/usr/local
make install DESTDIR=/mnt/lfs       # into a tree, not the running system
make uninstall
```

`/usr` is the default: the chroot invokes these by name, and
`packagemanager` runs `lfs-helper pm-install` for installs.

Installs the tools, the stack files and `kernel.conf` (never over an edited
copy — a changed one lands beside yours as `.new`), and the completion
script.

**Requires:** Python 3.9+, bash, coreutils, tar. Book parsing needs
`beautifulsoup4` and `requests`.

---

## Build a system

**Read [BUILD.md](BUILD.md).** It walks the whole thing, host to desktop, and
says at each step what to configure first. The short form:

```sh
lfs build-system session      # the interview: partition, prefixes, locale, login
lfs run                       # everything up to the chroot, then enter it
lfs-helper build-all          # inside: chapters 7-9
packagemanager bootstrap --run   # wget, Python modules, BLFS book, certificates
packagemanager stack            # list the stacks
packagemanager stack sway --run  # then network, services; apps and tools when wanted
lfs-kernel --run              # the kernel, from /etc/pkgusr/kernel.conf
```

`lfs run` and `build-all` continue from wherever they stopped. Run them again
after a reboot, a failure, or a cancel.

An entry can carry `when="<shell>"`: it is built only where that command
succeeds. `btrfs-progs` in services.stack is built on btrfs machines only.

A stack can read its packages from another book. `from-book svn` in a stack
file puts every book entry below it on the development book. Dependencies
outside the stack stay on the default book. `packagemanager stack <name>
--avoided` lists what the stack never builds; the plan shows only the count.

| Command | Does |
|---|---|
| `lfs build-system next` | What is done, what comes next |
| `lfs build-system list` | Every step and its state |
| `lfs build-system snapshot save <name> --run` | Save the build |
| `lfs build-system snapshot restore <name> --run` | Put it back |
| `lfs build-system restart --run` | Delete it all and start over |

---

## SysV on LFS 13.0+

LFS dropped the SysV edition with 13.0. `lfs-sysvbook` grafts the SysV
flavour of the last SysV book (12.4) onto a new systemd release and stores
the result as a normal book:

```sh
lfs fetch 12.4                # donor: the last SysV book
lfs fetch 13.0-systemd        # target: the new release
lfs-sysvbook make             # -> 13.0-sysv (book + wget-list + md5sums)
lfs-sysvbook check --book 13.0-sysv
lfs --book 13.0-sysv run
```

Everything builds at 13.0 versions. The transplanted SysV pieces (udev from
systemd, sysvinit, sysklogd, bootscripts, chapter 9) stay pinned at the
donor's versions — those instructions are known to work. Section numbers on
transplanted pages keep the donor's numbering; the build order is by document
position and is correct.

For a newer release later: `lfs-sysvbook make --target 13.1-systemd`.
`check` fails loudly if a future book layout breaks a rule.

---

## Install scripts

A generated script is the package's variables and its commands, nothing else:

```sh
name_version="binutils-2.45"
pkg_glob="binutils-2.45.tar.*"
pkgusr_stage="cross"

build_pkg() {
mkdir -v build
cd       build
../configure --prefix=$LFS/tools ...
make
}
install_pkg() {
make install
}
test_pkg() {
make check
}

. "${PKGUSR_LIB:-lfs-phases}" && pkgusr_run "$@"
```

The last line hands over to `lfs-phases`: it finds or fetches the tarball,
unpacks it, runs each phase as its own process under `set -e`, resumes in the
build directory, and takes `all | unpack | build | test | install | configure
| update` as `$1`. Edit the functions; the rest is shared.

Tests run only with `PKGUSR_TESTS=1` and never stop the install. The runner is
found on `PATH` or through `PKGUSR_LIB`.

Scripts written by 1.13 and earlier carry their own runner and keep working;
`--regenerate` produces the new shape.

---

## Use the built system

A freshly booted system has no download tool, no Python modules to read a book
with, no BLFS book and no certificates. `bootstrap` shows all five stages and
does the two that need no network:

```sh
packagemanager bootstrap        # where you are
packagemanager bootstrap --run  # wget and the Python modules, offline
```

Stages 1 and 2 come from what `get-sources` already downloaded, so they need no
network. Each module is installed as its own package user. The rest — the BLFS
book, `make-ca`, the certificate bundle — needs a working download, which is
what stages 1 and 2 buy you, so `--run` does those too. A stage whose
dependency failed is skipped, not attempted. Run it again after fixing
anything; it does only what is left.

```sh
packagemanager install <pkg> --recursive --run   # missing deps only; installed ones are left alone
packagemanager update <pkg> --run
packagemanager install <gitpkg> --reinstall --clean --run   # git packages: no book lookup
packagemanager which-package /usr/bin/foo
blfs order <pkg>                     # build order, dependencies first
blfs sources <pkg>                   # download URLs
```

### Application users

Separate from package users. An account a program **runs as**, so a browser
cannot read your files:

```sh
packagemanager user create firefox --shared --share-dir --launcher
```

| Flag | Does |
|---|---|
| `--shared` | Joins the group on your XDG runtime dir, and links `/etc/pkgusr/skel-u_xdg/.bash_profile` — display, session bus, audio |
| `--share-dir` | A directory both accounts can write, linked into your home |
| `--launcher` | A wrapper in `~/bin` that runs the program as that account |

The session group is read from the runtime directory, not assumed. Set it up
once for your own account; every shared user then joins whatever is there.

Many accounts at once come from `/etc/pkgusr/stacks/app-users.conf`, one line
per launcher, applied by `packagemanager stack services --only app-users
--run`. A line `@setup <account|*> <command | URL | script>` runs extra
setup as that account, once; a changed line runs again. Undoing them:

| Command | Removes |
|---|---|
| `packagemanager user remove-launcher <name> --run` | one launcher, its menu entry and icon |
| `packagemanager user delete <account> --run` | the account; its home is archived to `/root` first |
| `packagemanager user purge --run` | all of them, plus the session group, the profile fragments and the PAM wiring |

A home with a browser profile in it is archived to `/root/u_<name>-home-<date>.tar.gz`
(0600) before the account goes — logins, cookies and downloads that nothing
else can give back. A home that was never used is not archived. Drop the
archives when you no longer want them: `rm /root/u_*-home-*.tar.gz`.

Each is a dry run without `--run`. `$SHARED_*` comes from
`/etc/profile.d/shared-dirs.sh`. `/etc/profile.d` is read by **login** shells
only, so a terminal opened inside your session shows what it inherited at
login. The step also sources the fragment from `/etc/bashrc`; any shell can
refresh itself with `. /etc/profile.d/shared-dirs.sh`, which also drops the
variables whose directory is gone.

### Wireless

`packagemanager stack network --only net-wifi --run` reports what a wireless
link still needs and, with `WRITE=yes` in
`/etc/pkgusr/stacks/net-wifi.conf`, writes the parts that hold no secret: an
`/etc/sysconfig/ifconfig.<iface>` per wireless interface, and a udev rule
that gives a USB adapter the same name in every port. `PREFER` names the
interfaces best first — the first one present gets the low route metric, so
an external antenna is used while it is plugged in. The wpa_supplicant
config is never written (it holds your passphrase), but an existing one is
copied to a new interface when `COPY_WPA=yes`.

---

## Services

SysV, so a service is an init script in `/etc/rc.d/init.d` plus S/K symlinks
in `/etc/rc.d/rc<N>.d`. **Starting is not enabling** — `start` runs the script
now, whatever the links say.

```sh
packagemanager service                     # what exists, at boot, running
packagemanager service sshd start          # now, enabled or not
packagemanager service sshd enable         # at boot, without starting it
packagemanager service sshd disable        # boot only; it keeps running
```

`disable` records the links it removed, so `enable` puts back exactly what was
there — the priority number lives in the blfs-bootscripts Makefile and is the
one thing that cannot be worked out again. With no record, the runlevels come
from the script's own `Default-Start`. `status` exits 0 when running, 3 when
not, so it works in an `if`.

The scripts themselves come from blfs-bootscripts, one `make install-<target>`
per service. `packagemanager stack services --only bootscripts --run` installs
the ones whose package is here and whose script is not, from the mapping in
`/etc/pkgusr/stacks/bootscripts.conf`.

---

## When ownership starts

Book 7.6 creates `/etc/passwd`. Before that no name resolves, so ownership has
no meaning and nothing tries to set it.

`init-ownership` is a step in the build, right after `init-files` (book 7.6).
It creates the install group, sets the install directories, gives package users
to everything already built, and adopts it. From there on every install is owned
by the package that made it.

```sh
lfs-helper establish-ownership      # by hand, or to check whether it happened
```

---

## Repair

Everything is dry-run by default. `--run` applies.

| Command | Fixes |
|---|---|
| `lfs-helper check-toolchain` | Can the compiler build anything? |
| `lfs-helper fix-ownership --run` | Give each package its files |
| `lfs-helper fix-orphans --run` | Files whose owner does not exist |
| `lfs-helper which-package <path>` | Which package installed this |
| `lfs-helper manifests` | What each package installed |
| `lfs-helper sort-users --run` | Sort passwd and group by id |
| `lfs-helper setid [--run]` | Setuid/setgid bits the build refused (`su`, `passwd`, ...) |
| `lfs-backup create --run` | Back up the files in `/etc/pkgusr/backup.conf` (modes, owners) |
| `lfs-backup restore <archive> [--skip accounts,ssh] [--run]` | Put them on a new system: creates missing files, writes `.new` for the rest |
| `lfs-backup plan <archive> [file]` | A restore plan to edit: skip files, or send them elsewhere |
| `lfs-backup restore <archive> --plan <file> [--run]` | Restore by that plan |
| `lfs-backup merge <archive>` | Go through the `.new` files: diff, keep live, take backup, or edit |
| `lfs-backup clean <archive> [--run]` | Remove those `.new` files after merging (edited ones are kept) |

---

## Names and places

Three kinds of account share one passwd file, so each carries a prefix.
Without one a package called `man` or `news` collides with a real account.

**One account, one prefix — its own.**

| Thing | Looks like | Lives in |
|---|---|---|
| package user | `p_gcc` | `/usr/src/pkgusr/p_gcc` |
| config-step user | `cfg_bootscripts` | `/usr/src/cfg/cfg_bootscripts` |
| application user | `u_firefox` | `/usr/src/u_firefox` |

There is no `tmp_` and no `init_`. A temporary step is the same package
chapter 8 rebuilds, so it is built as that package's user. An init step owns no
files and gets no account.

Prefixes and locations are set once, in `lfs build-system session`.

Sources, build trees and state are three different things:

| Directory | Job |
|---|---|
| `$LFS/sources` | downloaded tarballs, never written by a build |
| `<package home>/src` | where that package unpacks and builds, owned by its user |
| `$LFS/build` | scratch for steps with no account. Deleted whole |

Everything the build knows about the tree lives in `/usr/src/lfs-pkgusr`,
beside the accounts it describes:

| | |
|---|---|
| `scripts/` | one shell script per build step |
| `manifests/` | what each package installed |
| `logs/` | one log per step, plus `verify.log` |
| `progress/` | what has been built, and how far |
| `groups/` | collector groups |
| `config/` | settings you may edit |

## Conventions

| Range | Used for |
|---|---|
| 9998 | `lfs` build user |
| 9999 | `install` group |
| 10000+ | Package users, in build order |
| 90000+ | Collector groups |

Install directories are group-writable during the build and become sticky
(`o+t`) at the end, so packages can no longer overwrite each other.

The account roots are **not** install directories. Only root creates a home
there, so they stay `root:root 0755` — group-writable with no sticky bit would
let any package user delete another package's home.

---

## The kernel

`lfs-kernel` treats the kernel as a package: its sources live in
`/usr/src/pkgusr/p_linux/src`, its files are recorded in that account's
manifest, and `packagemanager remove linux` takes it away. Firmware is its
own package (`p_linux-firmware`) and the headers update the package that owns
`/usr/include`.

```sh
lfs-kernel list          # what kernel.org offers
lfs-kernel               # what a build would do (nothing is built)
lfs-kernel --run         # build the version in /etc/pkgusr/kernel.conf
lfs-kernel 6.12.40 --run # that version, once
lfs-kernel load ath9k_htc --boot        # load a module now and at every boot
lfs-kernel verify        # is everything installed?
lfs-kernel firmware --missing [--fix]   # firmware this machine wants and lacks
lfs-kernel status               # how far the last build got, what is installed
lfs-kernel enable --list        # hardware this tool knows by name
lfs-kernel enable ath9k-htc     # its symbols into CONFIG_SET, its firmware
                                # into FIRMWARE_ONLY -- kernel.conf, backed up
lfs-kernel modules [text]       # what this kernel has, and what is loaded
lfs-kernel config               # where the next .config comes from
lfs-kernel config search atheros           # symbols by name or prompt
lfs-kernel config save --good   # keep the running config as a known-good one
lfs-kernel config from last-good           # build from it, not from /proc
lfs-kernel config diff          # prev-good -> last-good
```

Every config the tool builds with is copied to `/etc/pkgusr/kernel-configs`,
outside the source tree, so removing the package cannot take it: the last
`CONFIG_KEEP` builds, plus
`last-good.config` and `prev-good.config` — the two that booted.
`CONFIG_FROM=last-good` starts from one of them.

Everything it does is configured in `/etc/pkgusr/kernel.conf`, which is
installed rather than generated so it can be edited first. `ESP` and
`KERNEL_NAME` together decide whether a build replaces the working kernel or
lands beside it as something to try; the tree of the last kernel known to
boot is never deleted.

---

## Checking your version

The tools print a fingerprint of their own contents:

```sh
lfs --version              # name, version, build id
lfs-helper --version       # inside the chroot
```

Same build id means same code. The chroot copy refreshes automatically when you
enter it.

---

## Tests

```sh
bash test_lfs_crosschain.sh ./lfs          # all of it
bash test_lfs_crosschain.sh --list         # numbered blocks
bash test_lfs_crosschain.sh --from 300 --to 340 ./lfs
bash test_lfs_crosschain.sh --only firmware ./lfs
```

Each test encodes a bug that actually happened, with a comment explaining
what broke.

Run it from a directory holding all the tools — about 100 tests skip without
them. A selection re-executes a generated subset (preamble + chosen blocks +
summary); a block that needs something an earlier one computed says so
instead of passing quietly.

---

## Caveats

- **The kernel and the bootloader are separate, deliberate steps.**
  `build-all` builds neither; it ends by saying so. `lfs-kernel` builds the
  kernel from a config you edit first. Nothing is ever written to an ESP,
  boot sector or partition table unless you ask (`lfs config bootloader
  refind` adds an entry beside your existing one, on a mounted ESP).
- Built for SysV init. BLFS pages from the systemd book are used with a
  shim that turns `systemctl` calls into visible skips; `services.stack`
  installs the SysV boot scripts instead.
- Tested on x86_64 only.

---

## Licence

GPLv2-or-later.

# lfs-pkgusr

Build and maintain an LFS/BLFS system where **every package is owned by its own
user**.

> **100% vibecode, but tested.** Prompted into existence rather than hand
> written. 387 regression tests pass. It builds my own system — read it before
> you point it at yours.

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

## The four tools

| Tool | Runs | Does |
|---|---|---|
| `lfs` | host | Drives the whole build, chapters 1-10 |
| `lfs-helper` | inside the chroot | Builds each package as its user (bash, no Python needed) |
| `packagemanager` | built system | Installs and updates packages |
| `blfs` | built system | Reads the BLFS book, generates install scripts |

---

## Install

```sh
make install          # to /usr/local
make install PREFIX=/usr
make uninstall
```

Installs the four tools, the completion script, and `last_build_step.sh`.

**Requires:** Python 3.9+, bash, coreutils, tar. Book parsing needs
`beautifulsoup4` and `requests`.

---

## Build a system

```sh
lfs build-system session      # partition, mount point, prefix, locale
lfs run                       # everything up to the chroot, then enter it
lfs-helper build-all          # inside: build chapters 7-9
```

`lfs run` continues from wherever it stopped. Run it again after a reboot, a
failure, or a cancel.

| Command | Does |
|---|---|
| `lfs build-system next` | What is done, what comes next |
| `lfs build-system list` | Every step and its state |
| `lfs build-system snapshot save <name> --run` | Save the build |
| `lfs build-system snapshot restore <name> --run` | Put it back |
| `lfs build-system restart --run` | Delete it all and start over |

---

## Use the built system

```sh
packagemanager install <pkg> --recursive --run
packagemanager update <pkg> --run
packagemanager which-package /usr/bin/foo
blfs order <pkg>                     # build order, dependencies first
blfs sources <pkg>                   # download URLs
```

### Application users

Separate from package users. An account a program **runs as**, so a browser
cannot read your files:

```sh
packagemanager user create firefox --shared --launcher
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

---

## Conventions

| Range | Used for |
|---|---|
| 9998 | `lfs` build user |
| 9999 | `install` group |
| 10000+ | Package users, in build order |
| 90000+ | Collector groups |

Install directories are group-writable during the build and become sticky
(`o+t`) at the end, so packages can no longer overwrite each other.

---

## Checking your version

The tools print a fingerprint of their own contents:

```sh
lfs --version              # lfs 1.7.0 (build d64e55c)
lfs-helper --version       # inside the chroot
```

Same build id means same code. The chroot copy refreshes automatically when you
enter it.

---

## Tests

```sh
bash test_lfs_crosschain.sh ./lfs
```

387 tests. Each encodes a bug that actually happened, with a comment explaining
what broke.

---

## Caveats

- The kernel and the bootloader's kernel line are yours to finish.
- `lfs-helper` and `packagemanager_install` duplicate some logic. Unifying them
  is worthwhile but not done.
- Tested on x86_64 only.

---

## Licence

GPLv2-or-later.

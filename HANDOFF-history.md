# lfs-pkgusr — context for a new chat

Four tools that build and maintain an LFS/BLFS system where **every package
is owned by its own unprivileged user**.

Attach: the four tools (`lfs`, `lfs-helper`, `packagemanager`, `blfs` --
`packagemanager_install` was retired in 1.12.0), plus
`test_lfs_crosschain.sh`, `lfs-sanity.sh`, `stacks/` and this file.

**New here? "Start here" below says what to read and in what order.**

**ALWAYS TREAT THE CAUSE.**  The user's standing instruction, and the rule
this whole project is built on.  Shielding a path, special-casing a package
or silencing a message is acceptable only as a stopgap that is written down
HERE as unfinished, with the real cause named.  A symptom fixed and called
done is how one bug becomes a species.  (Said after 1.12.11 shielded five
paths without fixing why manifests over-claimed -- 1.12.13 fixed the cause.)


## Current state

FOUR tools at **1.14.144** (packagemanager_install is retired), plus
**lfs-phases 1.14.144** (the phase runner every generated script sources, new
in 1.14.0) and **lfs-sysvbook 1.0.0** (its own version line — it is a book
converter, not part of the build engine). Build ids — check these match what
is installed:

    lfs                     a28626f
    lfs-helper              b266328
    packagemanager          f23fb4c
    blfs                    b4c59f0
    lfs-phases              3eb3e81
    lfs-sysvbook            62ebe64  (1.0.0)

687 regression tests pass in a bare checkout with the books beside the tool;
the one failure (rc.site) needs the SysV book.  **1.14.0 has not built a
system yet** -- the script format changed (lfs v18, blfs v17) and the user is
starting a fresh build on it.

644 regression tests (counted results), 640 pass in a bare checkout; the 4
failures need the book HTML findable (beside the tool or in
`$LFS_STORE/books`). **The suite has run CLEAN on the built system**: 607 pass, 0 fail, one
honest SKIP (bootstrap already done), on 1.11.29 installed at builds
209ac78/b0213c4/c3eea26. Only the slice-noise open item below still prints
to stderr; every counted result passes.

**The bootstrap chain works end to end.** A real system: wget installed offline
from a staged tarball, make-ca fetched over the temporary unverified
connection, 172 certificates in /etc/ssl/certs, the wgetrc weakening removed,
and `wget https://ftp.gnu.org/` verifying.

**1.11.6 built a complete system**, chapters 1-10, and the reported problem was
a false alarm in the snapshot's own toolchain check. Work has moved to the
booted system: `bootstrap`. The five failures are
environment-only: four need the book HTML beside the tool, one needs
`skel-u_xdg/.bash_profile`.

**A full 104/104 build has completed on 1.10.1** and verified clean: 66265
paths owned by the right package, every account prefixed, every home owned by
its user, install directories sealed, `check-toolchain` usable.

**A full build on 1.9.3 verified clean: 66265 paths owned by the right
package, nothing else outstanding.** The one failure is `the XDG profile is not
shipped`, which looks for `skel-u_xdg/.bash_profile` next to the tool —
environment-only, it passes where the repo is laid out properly.

**A full 104/104 build has completed** on the 1.8.2 code. Everything since is
either a fix for something that build revealed, or the 1.9.0 cleanup.

(History: the 1.9.0 rename required a fresh build — account names, homes,
scratch and state all moved. That build happened; nothing above applies to a
tree at the current version.)

Kernel and bootloader are DONE — the system boots standalone.

## The user's system, in numbers

The real machine this history happened on (so a new session can check claims
against it): collector_prefix `nimgnu`, pkgusr_prefix `p`, cfguser_prefix
`cfg`, main_user `n76310`, pkgusr_home `/usr/src/pkgusr`, appuser_home
`/home/shared_user`, SysV init, 93 build accounts, 66230 paths verified owned,
7 collector groups at 90000+ (plus the malformed one below). The user's
systemctl-removal edit lives in
`/usr/src/pkgusr/p_make-ca/install_make-ca-1.16.1` — `--regenerate` would
discard it.

## Pending on the real system  (as of 1.14.94, 2026-09-09)

The previous version of this section dated from 1.11.x and every item in it
had long been closed -- including the one that matters most for orientation:
**the system already boots standalone; kernel and bootloader exist.**  What is
pending now is a Wayland desktop and the services around it, all of which are
BUILT (319 packages, `verify` clean) and none of which has been run.

Things to check or do, in order of likely payoff:

1. **Kernel options for what was added since it last booted.**  The kernel
   that boots today predates sway, iptables-nft and pipewire.  Confirm, in its
   config: `CONFIG_DRM_<your gpu>` with KMS, `CONFIG_INPUT_EVDEV`,
   `CONFIG_NF_TABLES` + `NFT_COMPAT` (iptables-nft is useless without them),
   `CONFIG_SND_*` for the sound card.  Rebuild only if something is missing.

2. **The desktop user and the seat.**  Create the user, then run the services
   stack -- `cfg mytools` builds everything of yours under ONE package user
   (p_mytools): /usr/bin/seatd-<user> (-rwsr-x--- root:<user>), sway_start,
   wifi, and the `sway` alias:
       useradd -m -G audio,video,input,wheel <name> && passwd <name>
       LFS_DESKTOP_USER=<name> packagemanager stack services --yes --run
   No seatd daemon and no `seat` group: the wrapper is setuid and built for
   one user, so the seat exists only while that user asks for it.  (elogind
   cannot provide one here -- it needs pam_elogind at login, and Linux-PAM
   is avoided.)

3. **First launch, on a tty**: log in as that user and run `sway-session`.
   This is where a missing RUNTIME dependency shows; a build cannot catch it.

4. **iptables really is nft**: `iptables -V` must say `(nf_tables)`.  If it
   says `(legacy)`, libnftnl did not land before iptables, or the machine.conf
   [iptables] section was not present when it built.

5. **wifi**: the user's script needs `/etc/sysconfig/ifconfig.wifi0` (with
   SERVICE=wpa, which `install-service-wpa` provided) and per-SSID files
   under `/etc/sysconfig/wpa_supplicant/`.  The script's `wpaUp` calls
   `ifup $IFNAME wifi0` with IFNAME unset -- `INTERFACE` is defined and
   never used; one of them should go.

6. **make-ca's weekly update** -- the systemd book's page enables a timer,
   which the shim skipped.  Now that fcron exists, add the 12.4 SysV book's
   cron job by hand:
       cat > /etc/cron.weekly/update-pki.sh << "EOF"
       #!/bin/bash
       /usr/sbin/make-ca -g
       EOF
       chmod 754 /etc/cron.weekly/update-pki.sh

7. **dbus**: machine.conf carries `[dbus] systemd = disabled`, added AFTER
   dbus was built.  Either rebuild dbus (`packagemanager install dbus --run
   --regenerate`) or accept the systemd-flavoured build; it works under
   elogind either way, the difference is a few files nothing reads.

8. **Stray `.service` in /usr/lib/systemd/user** from at-spi2-core: harmless.

Tool work deferred, none blocking:

- Whether the CONFIGURE phase should run as root (1.14.79).  The book says
  root for every "Configuring" section.  Decide at the start of a session.
- `needs=` for the remaining git entries (swaybg, wlroots, seatd, ...): their
  dependencies are only discoverable by building; add a line per discovery.
- `--check-refs` cannot see tar URLs; a `have=`-style check for tarballs
  (HEAD request, or a sha256 beside the entry) would close the gap libnftnl
  exposed.
- The "busy tree" test is flaky (races a `sleep`); use a private marker.
- The rc.site test needs a SysV LFS book to pass; it should say so instead
  of failing.
- The whole-book invariant "no empty install phase" should be extended to
  build phases, with the known-empty pages listed by name.

## Start here

If you are picking this up cold, read in this order:

1. **The core idea** — one paragraph, and everything else follows from it.
2. **Where everything lives** — the layout changed in 1.9.0.
3. **The ownership epoch** — the single moment the scheme turns on.
4. **One bug, twelve times** — every failure this project has had was the same
   shape. Knowing the shape is worth more than knowing the twelve.
5. **Open items** — item 1 is the next job.

## The core idea

Each package gets a user that owns the files it installs.

- Every file traces to the package that installed it.
- Removing a package is removing that user's files.
- A broken build cannot overwrite another package's files.

Directories several packages install into are shared via **collector groups**
(`<prefix>_<owner>`, e.g. `nimgnu_python`). The install group (`install`, gid
9999) means "anyone may install here" and is only for genuinely shared dirs —
never a package's own tree, and never `/root` or `/home`.

## The five scripts

| Script | Runs | Purpose |
|---|---|---|
| `lfs` | host, Python | Drives the build: partition, sources, chapters 5-6, chroot, snapshots |
| `lfs-helper` | inside the chroot, **bash** | Builds each package as its user. Bash because there is no Python in the chroot yet |
| `packagemanager` | built system, Python | Installs/updates packages, application users, config |
| `packagemanager_install` | built system, bash | The install engine `packagemanager` calls |
| `blfs` | built system, Python | Parses the BLFS book, generates install scripts, resolves dependencies |
| `lfs-phases` | everywhere, **bash** | The runner every generated install script sources: fetch, unpack, phases, dispatcher |


## Where everything lives

Two trees under `/usr/src`: the accounts, and what the build knows about them.

```
/usr/src/pkgusr/p_gcc            a package's account
/usr/src/pkgusr/p_gcc/src        where gcc unpacks and builds
/usr/src/cfg/cfg_bootscripts     a config step's account
/usr/src/u_firefox               an application user
/usr/src/lfs-pkgusr/             what the build knows about all of them
```

`SRCROOT` (`/usr/src`) is the parent and stays whole-tree, **deliberately**:
every ownership pass excludes it as one path (`-not -path "$SRCROOT/*"`).
Splitting that exclusion would silently un-exclude half the accounts.

That is also why the state directory moved here in 1.9.0. It was
`/.lfs-pkgusr` — a hidden directory at the root of the filesystem, sitting
beside `/boot` and `/etc` as if it were part of the system being built. It is
not; it is this toolchain's working notes *about* that system. Under
`/usr/src` the scans exclude one path instead of two.

The state directory is sorted, so opening it tells you what is in it:

| | |
|---|---|
| `scripts/` | one shell script per build step, generated from the book |
| `manifests/` | what each package installed (`.files`, `.dirs`) |
| `logs/` | one log per step, plus `verify.log` |
| `progress/` | `steps-built`, `steporder`, `adopted.list`, tree snapshots, the ownership marker |
| `groups/` | collector groups and the grants that created them |
| `config/` | `installdirs.lst`, `env` — settings you may edit |
| `stage/` `steps/` `tmp/` | transient, only during a build |

Both tools name it once: `STATE` in `lfs-helper`, `PKGUSR_DIR` +
`pkgusr_state()` in `lfs`. They read each other's manifests, so a disagreement
here is a silent one.

**Definition order matters.** `SRCROOT` must be set before anything derived
from it. Under `set -u` a forward reference is not a subtle bug — the tool
will not print its own version. There is a test on the ordering.

## The build scratch is the package's

A package unpacks and builds in `<its home>/src` — not in a shared `/build`
that every package writes into at once.

The shared scratch was a permanent ownership fight. Every build's touched-file
scan swept it in, so each manifest claimed every other package's sources and
chowned them; the next package chowned them back. A real `verify` reported
3363 wrong-owner and 3348 of them were `/build`:

    /build/bash-5.3.tar.gz  is p_shadow  want p_acl
    /build/bash-5.3.tar.gz  is p_zstd    want p_acl     (after "repairing" it)

Under the package user's home it is settled by construction: the user creates
the tree so the user owns it, `$SRCROOT` is already excluded from every scan so
it can never reach a manifest, and removing a package removes its build tree.
Steps with no account keep the shared `/build` — they run as root, which owns
everything there anyway.

`~/src`, not `~/build`: `~/build` is already the hint's build helper script,
symlinked into every package user's home. `pkgusr_skel_links` names the
skeleton once and a test checks the build subdir is not one of them.

## Names and places

Three kinds of account share one passwd file, so each carries a prefix.
Without one, a package called `man` or `news` collides with a real system
account and nothing says which accounts belong to the build.

| Thing | Looks like | Lives in |
|---|---|---|
| package user | `p_gcc` | `/usr/src/pkgusr/p_gcc` |
| config-step user | `cfg_bootscripts` | `/usr/src/cfg/cfg_bootscripts` |
| application user | `u_firefox` | `/usr/src/u_firefox` |
| collector group | `<prefix>_python` | — |

**One account, one prefix — its own.**

| Range | Used for |
|---|---|
| 9998 | `lfs` build user *(inside the chroot; the host's is unpinned)* |
| 9999 | `install` group |
| 10000+ | Package users, in build order (binutils first) |
| 90000+ | Collector groups |

**Prefixing is idempotent, and that is load-bearing.** It is applied to names
a person typed (`gcc`), to directory names read back from disk (`p_gcc`), and
to values that already went through it. Because a second pass cannot produce
`p_p_gcc`, every call site can apply it without first knowing which kind of
name it holds — which is what made 24 call sites a mechanical change instead
of 24 judgement calls.

**One chokepoint per tool.** Never build a home by hand:

- `lfs-helper` — `pkgusr_kind()`, `pkgusr_prefix_for()`, `pkgusr_root_for()`,
  `pkgusr_home_for()`, `pkgusr_roots()`, `unprefix_pkg_user()`,
  `step_stage_dir()`
- `packagemanager` — `pkgusr_kind()`, `pkgusr_name()`, `unprefix_pkgusr()`,
  `pkgusr_root()`, `pkgusr_roots()`, `pkgusr_home()`
- `lfs` — `pkgusr_prefix()`, `cfguser_prefix()`, `LAYOUT_DEFAULTS`, `layout()`

`pkgusr_kind()` is the top of that chain: it decides the kind once and the
prefix and the root are both answered from it, so a name cannot be given one
kind's prefix and placed in another kind's root.

`lfs-helper pkgusr-home <name>` exposes the rule to shell scripts, so nothing
else re-derives it. `packagemanager_install` and `lfs-completion.bash` go
through a chokepoint now; a test fails if either builds `/usr/src/$something`
by hand.

**The chokepoint must resolve to the ACCOUNT home, not just the root.**
Callers pass a mixture and always will: `build_pkg` has the step name
(`man-pages`, `util-linux-tmp`), the staging code has the owner
(`p_man-pages`). `pkg_owner_name` maps one to the other — prefix, lowercase,
fold `-tmp`/`-passN` onto the real package — and it is idempotent. Routing by
kind without that mapping shipped once and broke the build at step 9:

    # created package user p_man-pages ...
    line 2673: cd: /usr/src/pkgusr/man-pages: No such file or directory

Chapter 7 did not catch it — root steps `mkdir -p` their own directory first,
so it surfaced at the first real package user.

**A step that is not a package has no home.** `pkgusr_home_for` answers for
accounts; `step_stage_dir` answers for steps, and routes `init-*`, `last-step`,
`refind` and prose `cfg_*` sections to `$STATE/steps/<name>` because they never
get an account. Asking `pkgusr_home_for` for their home is what left
`/usr/src/pkgusr/p_init-dirs` behind.

Note `SRCROOT` in `lfs-helper` is the **parent** (`/usr/src`), deliberately.
Tree scans exclude it as one path (`-not -path "$SRCROOT/*"`); splitting it
there would silently un-exclude half the accounts from every ownership pass.


## Two directories, two jobs

| Directory | Job | Permissions |
|---|---|---|
| `$LFS/sources` | downloaded tarballs, never written by a build | `root:root 1777` |
| `<package home>/src` | where that package unpacks and builds | owned by its user |
| `$LFS/build` | scratch for steps with no account | `root:root 1777` |

Book 3.1 settles the ownership — `chmod a+wt`, then
`chown root:root $LFS/sources/*` — and gives the reason: a host uid means
nothing in the built system. Here it is sharper than the book's case. The host
`lfs` account is created by book 4.3's own `useradd`, which pins no uid, so it
lands wherever the host had a gap — 10753 on a Debian host. Package users start
at 10000, so it does not merely show as a number, it **collides with a real
package user** and tarballs report as owned by something unrelated.

`/sources` and `/build` are in `never_adopt_list` and NOT in
`install_dirs_list`. Being in both made `/sources` `root:install 775`,
dropping the `o+w` that lets the unprivileged build user unpack at all.

**The symlink farm.** `unpack_pkg` links every downloaded file into
`BUILD_ROOT`, because the book reaches sibling tarballs through `..`:

    cd ..
    tar -xf ../tcl8.6.16-html.tar.gz --strip-components=1

`cd ..` leaves the build subdirectory, so `..` is then `BUILD_ROOT`. Linking
everything rather than a known list means any future book works without a
second thing to keep in sync.


## The ownership epoch

**Before book 7.6 there is no `/etc/passwd`, so ownership is not wrong — it is
meaningless.** No name resolves, not even root's; the prompt in the chroot
reads `I have no name!`. Every ownership question asked before that point gets
a confident wrong answer:

    chown root:install fails on every directory  ->  "# 0 install directories"
    find -nouser matches every file in the tree  ->  11802 "orphans", incl. / and /proc

There is one gate:

| | |
|---|---|
| `ownership_established()` | is it done? (`progress/ownership-established`) |
| `ownership_possible()` | can it be? (passwd + chown/chgrp/chmod) |
| `establish_ownership()` | do it |
| `_ownership_checkpoint()` | the one call site, after every step |

`init-ownership` is a **step you can see**, inserted straight after
`init-files` (book 7.6). `lfs-helper` performs it itself — there is no book
script — and marks it done, so `list` and `next` agree with reality:

    3. init-ownership         built

It does everything in order: install group and install directories, the build
user's leftovers handed back to root, package users for everything already
built, adoption, our own tools, then orphans. Idempotent, and the marker is
durable, so a resumed or restored build crosses it once.
`lfs-helper establish-ownership` runs it by hand.

Everything that needs a user database refuses without one: `_vfy_orphans`,
`_has_orphaned_files`, `_vfy_build_user_leftovers`, `_vfy_install_dirs`.

Install directories are set and read back **by number** (`0:$INSTALL_GID`) —
`root` need not be a name.

## The two chowns that can destroy a tree

Book 4.3 gives the tree to the build user; book 7.2 gives it back. Both are
recursive, and each is catastrophic on the wrong side of chapter 7.

- **4.3 on a built tree** hands the finished system to the host's build
  account. `_chown_tree_to_lfs` refuses when `_handover_is_safe` is false.

  There were **four doors to that chown** and only one had the guard:
  `_chown_tree_to_lfs` (book 4.3), `session --run` re-applying it by hand,
  the pre-build ownership check, and `fix-ownership --run`. All four now ask.
  A test walks every `chown -R lfs` in the file and fails on any whose
  enclosing function does not consult `_handover_is_safe` — the property, not
  the four paths, because a fifth door would otherwise be silent too.
- **7.2 on a built tree** strips every package user in one pass. Refused for
  the same reason.

Refusing both left a tree with no way forward, so there is a third, precise
form: `_handover_build_user_only` selects on the **build user's uid**, taking
back exactly what 4.3 took and leaving every package user's files alone. Safe
at any stage. `chroot prepare` runs it instead of refusing, and `chroot enter`
runs it before deciding to stop.

`chown -h root`, user only — 4.3 chowns the user, so the inverse does too;
taking `root:root` would strip `install` off every shared directory. And `-h`,
because `/bin`, `/lib` and `/sbin` are symlinks.

`_handover_is_safe` asks the **tree's own passwd** which accounts are package
users (`_pkg_users_in_tree`), never a uid range. Book 4.3's `useradd` pins no
uid, so the host's `lfs` came out **10753** on one machine — inside the package
range — while the chroot's own `lfs` is 9998. Across that boundary only the
number means anything.

## Saying things

Four colours, one meaning each, identical in both tools — they print into the
same terminal one after the other, and a log where the same colour means two
things is worse than no colour at all.

| | |
|---|---|
| green | something finished, and finished correctly |
| yellow | something needs your attention |
| red | something failed |
| dim | detail you can skip: provenance, and what to do next |

Prose gets none. Colour on every other line stops carrying information.

`lfs-helper`: `say` (prose) `ok` `warn` (stderr) `note` (stdout) `detail`
`hint` `fail` `die`. `lfs`: `warn` `note` `ok` `fail` `hint`.

**Use the helper, never the variable.** A colour opened in one `echo` and
closed in another leaves the terminal painted if anything between them writes —
the failure banner was 22 lines inside a single open/close. The only direct use
left is the status column in `list`, where the colour *is* the information.

## One bug, twelve times

Every failure this project has had was the same shape: **one decision held in
more than one place, free to disagree.** They are worth reading as one list,
because the next one will look like them.

| What disagreed | How it showed up |
|---|---|
| Package prefix applied regardless of kind | `p_cfg_bootscripts` — two prefixes, in the config root, claiming to be a package |
| Two wrapper directories | `make_wrappers` wrote `$STATE/wrappers`; the profile said `/usr/lib/pkgusr`, which nothing created |
| Two copy routines for the tools | `install_helper` claimed ownership, `_install_pkgusr_helpers` did not — eight files owned by nobody |
| `chgrp` vs `chown root:install` | `init-pkgusr` set the group, `verify` demanded owner+group; `/usr/share` sat at `lfs:install` |
| Install-dir rule in three places | `cmd_verify` carried inline copies without the guards the helpers had grown |
| **`cmd_verify` defined twice** | bash keeps the last; the tidy one had never run |
| Scratch scanned by two rules | the snapshot scans excluded `/build`, the build's own scan did not — 3348 false findings |
| Build tree named `build` | collided with `~/build`, the hint's helper script |
| Wrapper `chgrp` shadowing root's | reported 46 successes, changed nothing, and `verify --fix` could not repair it either |
| Handover guarded by one inode | `_owner_is_root` checks `$LFS/usr`; the pass it guards covers eight trees |
| uid range used to identify the build user | host `lfs` was 10753, inside the package range |
| Adoption reached from two directions | an up-front pass and a mid-loop "late" pass with its own flag |
| Ownership scans kept their own exclusion lists | build trees moved into the package homes in 1.7.6, the snapshot scans followed and the ownership scans did not — `verify` ran for minutes walking every unpacked source tree |
| Generated scripts had no version stamp | the step order lives in the tree, the tools outside it — a tree generated by an older version went on running `last-step` under a lfs-helper that had removed it |
| Collector export written and read in two places | 1.9.0 sorted the state dir; the writer stayed at the top level, the reader moved into `groups/` |
| `pkgusr-home` was exposed, `owner-name` was not | a script could ask where a package lives but not what its user is called, so `last_build_step.sh` assumed — `chown: invalid user: 'wget:wget'` at step 104 of 105 |
| `add-user` named the account raw, the home prefixed | `add-user wget` gave account `wget` in `/usr/src/pkgusr/p_wget` — every caller but `last_build_step.sh` passed an already-prefixed name, so it never showed |
| Tree snapshot written and read in two places | same move, same shape: `lfs` kept `.snapshot`, `lfs-helper` read `progress/tree-snapshot` — the chapter 6→7 handover snapshot was lost |

**Half a chokepoint is not a chokepoint.** `pkgusr_home_for` was reachable from
outside as `lfs-helper pkgusr-home`; `pkg_owner_name` was not. So a shell script
could ask where a package lives but had to *guess* what its user is called —
right by accident until `add-user` started applying the prefix, then wrong at
step 104 of a 105-step build. `lfs-helper owner-name <package>` is the other
half, and a test checks the two agree.

The fix is always the same: **name the decision once, and make everything ask
that one thing.** `pkgusr_kind()`, `build_root_for()`, `never_claim_list()`,
`ownership_possible()`, `pkgusr_skel_links()`, `_real_tool()` all exist for
this reason.

Two rules follow from it, and both have tests:

- **No function may be defined twice.** A duplicate is invisible — both parse,
  one silently wins.
- **Every `cmd_*` a tool calls must be defined in that tool.** `verify --fix`
  called `cmd_fix_orphans`, which never existed, and died mid-repair after
  chowning 3473 paths.

## The collector export

A previous build's group decisions, so a rebuild does not ask
"which group should share this directory?" for every package again.

    lfs-helper export-groups            # write one out
    collector_import_file = <path>      # session setting on the host

`lfs` copies it into `groups/collector-groups.import`; `lfs-helper` reads it
from there in `choose_collector_group`, **before** asking. Those two paths are
the whole mechanism, and nothing else connects them — when the state directory
was sorted in 1.9.0 the writer stayed at the top level while the reader moved,
and a rebuild with a perfectly good export asked about `/usr/lib/bfd-plugins`
anyway. Silent, because a question that gets asked looks exactly like a
question that was never answered. There is a test that the two paths match.

It is re-copied on **every chroot entry**, so editing it on the host reaches
the next build without regenerating the scripts. It only prints when the
contents changed.

`session` reports what is in the file (`N directory decision(s), M group(s)`)
rather than echoing a path — a file that was configured, present and never read
looked identical to one that was working.

## One rule for /usr/src

Everything under `/usr/src` is `root:install 1775`: `/usr/src` itself, the
account roots, and the state directory.

The account roots were `root:root 0755` — defensible, since only root creates
an account home, but it made one subtree with two rules and a special case to
remember. **The sticky bit is what makes group-writable safe and is not
optional:** without it any member of `install` could delete or rename another
package's home. With it, only the owner can, so group write grants only the
ability to *create*, which nothing unprivileged does (`add-user` is root-only).

Sharing the mode is not sharing the meaning. The account roots and the state
directory are still in `never_adopt_list`, so no package may ever take one as
its own, and `install_dirs_list` does not contain them.

**The state directory is in `never_claim_list`.** It lives under `/usr/src`,
which IS an install directory, so `verify` walked its own manifests, scripts
and logs and reported each as a root-owned file no package claims. A clean
104/104 build came back with `448 root-owned file(s) that NO manifest claims`
and all 448 were this directory — including the two temp files the scan had
just written for itself.

## Reading a sanity report

Three of its findings used to be about the report, not the tree. All fixed, but
worth knowing the shape:

- **The sticky bit means opposite things on either side of the finish line.**
  During the build it is a bug — package users cannot replace the temporary
  system's files. After `seal-install-dirs` it is the point, and its *absence*
  is the bug. The report works out `BUILD_FINISHED` from `progress/steporder`
  vs `progress/steps-built` and judges accordingly.
- **An empty manifest is not an orphan.** A prose config step — `cfg_clock`,
  `cfg_hosts`, `cfg_locale` — writes into files another package owns, so it
  records nothing and legitimately has no account. Fourteen of those were
  reported on a perfect tree.
- **A step can install under a name that is not its own.** `libstdcpp`'s files
  belong to `p_gcc`, because the book builds it out of the gcc tree. When the
  name lookup fails, the report now asks the filesystem who owns the files
  before calling it a finding.

`packagemanager_install` has `--version` now, so section 0 can read all five
tools. A tool you cannot ask "which build are you?" is the one that quietly
goes stale.

## comm needs one collation

The snapshot diff is `comm -13 <(before) <(after)`. **comm compares line by
line and trusts both sides to be sorted the same way. It cannot detect
otherwise; it returns the wrong answer.** Two things broke that:

- the two snapshots may have been written under different locales — a package
  user's profile sets `LC_ALL=POSIX`, root's shell may not;
- `load_snapshot` rewrites only the lines carrying the host mount prefix, so a
  file holding both forms comes back sorted under neither.

`snapshot`, `snapshot_dirs` and `load_snapshot` all pin `LC_ALL=C sort`, and
`load_snapshot` re-sorts after the rewrite. The visible symptom is a package
installing forty files and being told it installed none.

**A re-run over its own work is not a silent failure.** The zero-files check
counts what *this run* wrote, which is the wrong question the second time a
package is built: many installers skip a file that is already up to date --
perl's ExtUtils::Install prints "Installing <path>" for every target and copies
only the stale ones. So the run writes nothing, the snapshot diff sees nothing
new, no mtime beats the stamp, and the count is 0 for the best possible reason.

`xml-parser` hit exactly that: forty files on disk, every one owned by
`p_xml-parser`, and the step failed as a no-op. `_package_already_owns_files`
asks the tree instead of the counters. A package owning nothing is still a
failure.

**"installed NO files" now shows its working.** There are exactly three ways to
reach zero and they need different fixes: nothing was written, it was written
somewhere excluded from tracking, or it was written over files another package
owns and dropped by the ownership filter. The message reports the snapshot-diff
count, the touched count, and which of the three it is.

## A bootloader is opt-in

`bootloader` defaults to **none**. It used to default to `refind`, on the
reasoning that rEFInd only ever adds files to an already-mounted ESP — true,
and still the safe choice, but it stopped a finished build to ask about a
bootloader on a machine that already had one. The machine booted in order to
build LFS at all. A bootloader is a decision about the whole machine, not a
package.

    lfs config bootloader refind
    lfs config esp /boot/efi
    lfs build-system gen-chroot-scripts --run --overwrite

Skipping it is not silent — `gen-chroot-scripts` says so and prints those three
lines, because someone who *does* need a bootloader would otherwise reach a
finished, unbootable system without ever having been offered one.

GRUB is unchanged and still withheld unless explicitly chosen: its book
instructions run `grub-install /dev/sda`, which writes a disk's boot sector.

## The group belongs to the tree, and a name is a question  (1.12.43)

1.12.42 created the directories correctly and then put the wrong group on
them:
    /usr/share/vim/vimfiles  p_cmake  nimgnu_cmake

grant_dir_access names the group after the DIRECTORY'S owner -- which, for a
directory cmake had just been given, is cmake.  The group belongs to the
TREE: another package installing into vim's directories will look for
nimgnu_vim, and nimgnu_cmake tells it nothing.

share_new_dir_with_tree_owner replaces that call:
  * the tree owner's group exists  -> reuse it, silently
  * it does not exist, terminal    -> ASK, offering the tree's name first,
                                      the creator's second, or a typed name
  * no terminal                    -> the TREE's name, never the creator's
--yes deliberately does NOT skip this: it means "do not ask me to confirm",
not "pick a name for me" (the user's words, and they are right -- a name is
a decision, and a wrong one is permanent).

## The portal tail  (1.13.1)

With the status finally honest it read 255, and the list said why: xfce4-*,
lxqt-*, gnome-keyring, ModemManager, ruby, aspell, openssh -- and Systemd, on
a SysV system.  None are avoided by name; they are the TAILS of things that
are, and since the automatic prune was reverted (1.12.83, it dropped
graphite2) tails have to be named too.

They arrive through one edge: the book makes xdg-desktop-portal REQUIRE all
four backends (gtk, wlr, gnome, lxqt), so a single gtk4 recommendation drags
in the whole of xfce and lxqt.  Named now, with the rest of the
not-this-desktop list.

    273 -> 226 packages, 43 named exclusions
    webkitgtk, gtk4, mpv all still in.

REMAINING, and the honest limit: roughly thirty packages in that 226 exist
only to serve something avoided (Qt's double-conversion/jasper/libmng, the
cups tail).  Pruning them needs EVERY edge, and `blfs order --anchors` emits
one parent per package.  The real fix is to make blfs emit the full edge list
so the plan can prune by reachability properly -- the 1.12.82 attempt failed
precisely because it used the one-parent output.  Worth doing; not worth
guessing at again.

## Stopping the bug is not undoing it  (1.13.25)

mesa failed again with `Unknown option: "needs"` after 1.13.24 stopped adding
-Dneeds= -- because the flag was already IN the script on disk, and the merge
is idempotent, so nothing would ever have taken it out.  A fix that prevents
a bad write must also repair what the bad write left behind.

apply_machine_opts now strips -Dneeds= from an existing meson line and says
so.

Also: the stale-script box (1.13.21) said
    packagemanager install p_mesa --run --yes --regenerate
-- the ACCOUNT, which names no package.  unprefix_pkg_user uses
PKGUSR_PREFIX, empty on that system, so the p_ survived; the tools' own
default prefix is stripped as well now (same fix as 1.13.5 for group names).
That is the third place this year where an empty PKGUSR_PREFIX let an
account name leak into somewhere expecting a package name -- worth one sweep
for `unprefix_pkg_user` calls that do not also strip p_.

## The book already knew the flag  (1.13.44)

    vala: configure: error: Package requirements (libgvc >= 2.16) were not met

libgvc is Graphviz, which this desktop avoids.  Rather than guess a flag --
which is exactly how the libassuan --disable-doc mistake cost three releases
-- the book's own page was read first, and it says:

    "--disable-valadoc: This option is required if Graphviz is not installed."

    [vala]
    configure_args = --disable-valadoc

A useful habit confirmed: when a package fails for a missing OPTIONAL
dependency, the book's Command Explanations usually name the switch that
turns it off.  Reading them costs one grep; guessing costs releases.

WORTH BUILDING NEXT: the failure box could do this grep itself.  A
"Package requirements (X) were not met" error plus the book's page for the
failing package is enough to find the sentence with the switch in it.

## A refusal has to say who is refusing  (1.14.5)

The 1.14.1 chroot fix was reported as still broken:

    root ~ # lfs run
    You are inside the LFS chroot, ...
    root ~ # packagemanager --version
    packagemanager 1.11.26 (build 2daedaf, plan cache v1)

The detection was fine.  The binary being run was three minor versions old --
`make install` had been landing somewhere other than the copy on $PATH -- and
nothing on screen said which `lfs` was talking or what convinced it.  So a
stale install presented as a bug in the current one, and the debugging went
to the wrong place.

The refusal now ends with its own path, version, build id, and the signal it
used (LFS_IN_CHROOT / the kernel / the fallback).  Cheap, and it turns "this
is still broken" into "that is not the binary I installed" at a glance.

Also in this release: `make install` no longer aborts when
lfs-completion.bash is absent from a checkout -- it skipped nothing and
failed the whole target after the tools were already in place, which is the
same failure shape as above (a run that mostly worked, reported as a failure).

## A health check must lead with what is wrong  (1.14.34)

A real verify on a working tree:

    broken: 4   not installed: 12   unvalidated: 226

The 226 are normal -- "unvalidated" only means the page named no file to
check.  The twelve that need action were buried inside them, and three of the
four "broken" were nimgnu_* COLLECTOR GROUPS: groups, not packages, reported
as "has a user but no home dir" because `list_all_users` lists every directory
under the account roots.  A false alarm in a health check is worse than no
check -- it teaches people to skip the output.

Collector groups are filtered out (by the CONFIGURED prefix, not a hardcoded
`nimgnu`), and verify ends with the packages that actually need attention,
their reasons, and the command to rebuild them -- or says nothing does.

Also worth recording, since it cost the user a wasted pass: the filter
suggested in chat was `grep -vE "installed "`, which also matches "not
installed " and hid exactly the lines that mattered.  The tool should not need
a filter to be readable, which is what this change is for.

## Your packages, under your name  (1.14.106)

Three things from one run.

**The account.**  "the user should be called p_n76310 -- that's a fixed name
for those packages as they come from me."  Right, and better than `mytools`:
p_<your user> is where anyone would look.  Both the script and the step take
the name from the desktop user (MYTOOLS_NAME overrides).

**The build line.**  It died with `error: 'n76310' undeclared`.  The SOURCES
element was DOUBLE-quoted, so the escaped quotes collapsed before eval and gcc
received a bare identifier.  Single-quoted now, and the command is the
author's own, verbatim -- the C program stringifies the macro itself, so
copying what works by hand beats reasoning about which form "should" be
right.

**--only.**  Declared in the parser long ago, documented as "repeatable or
comma-separated ... rebuilt even if the cache says done", and NEVER
IMPLEMENTED.  It works now: named entries are exempt from the done-cache,
everything else is skipped, and an unknown name is refused with the list of
what the stack has.  A stack is long and its entries fail one at a time;
re-running all six to retry one is not an answer.

An option that exists in --help and does nothing is worse than a missing one:
the help is a promise, and this one had been lying for as long as it existed.

## Only a kernel that has booted is known to boot  (1.14.144)

The kernel step is complete: 32 checks green, the manifest down from 268815
to 36539 (modules plus ~12k Documentation files -- no source tree), 199
Intel wireless blobs in place, v4l2loopback loaded into modules.dep.

One line in that report was false:

    note  last kernel known to boot: 7.2.4

7.2.4 has never booted.  7.2.0 is carrying the machine.  The old fallback
wrote the version just built into last-good whenever the file was empty, so
the file that exists to name SOMETHING YOU CAN GO BACK TO named the one
thing that had never been tried.  A record holding a guess is worse than an
empty one.

Three cases now, and only the first two write anything: the built version IS
the running one (it demonstrably boots); the running version has a tree here
(that is the fallback); or nothing has been shown to boot, in which case the
tool says so and records nothing.  verify explains an empty record rather
than omitting the line, and says when the known-good kernel is the live one.

The pattern is 1.14.64's again, one level up: a default that fills a gap with
something plausible is indistinguishable from knowledge, and this file is
only useful if its contents were EARNED.

## A config from one kernel is never complete for another  (1.14.143)

"do we do an 'make old_config' when installing a new version?"  It did --
`make olddefconfig`, one line, undocumented and not selectable.  Which is the
right default and the wrong silence: every kernel version adds symbols the
old .config has no answer for, and olddefconfig answers all of them with
UPSTREAM'S defaults without saying so.  On a config taken from a
distribution kernel that can quietly turn things on or off that the person
had chosen deliberately.

CONFIG_REFRESH now selects it, documented with what each choice costs:

    olddefconfig   upstream's default for each new symbol, silently
    oldconfig      ask about each one (needs someone at the terminal)
    menuconfig     decide everything at once, in the editor
    none           leave the .config alone and let `make` deal with it

And it reports the size of what happened -- "47 config line(s) differ from
the config you started from" -- because a number is the difference between
knowing a refresh occurred and knowing it mattered.

## Three ways to be wrong about a path  (1.14.142)

**The headers.**  Copying them AS p_linux-headers cannot work: the source is
inside p_linux's home, which is 0750, so that account cannot even stat it --
"cp: cannot stat .../usr/include: Permission denied".  Opening one account's
home to another would undo the point of having accounts.  Root copies (it
reads both sides) and then chowns to p_linux-headers; ownership afterwards is
what makes the files that package's.  Same shape as the ESP copies and the
setuid bit.

**The manifest, still 268815.**  The filter was there and did nothing,
because `index($0,h)==1` assumes every line is an absolute path beginning
exactly at the home.  Matching the home ANYWHERE in the line cannot be fooled
by a leading ./ or a relative listing, and no installed file has a package
home in its path.  Verify now FAILS on an implausible count and PRINTS the
offending lines -- two releases went into reasoning about a filter without
once looking at what it failed to match, which is the actual lesson here.

**The iwlwifi question.**  The firmware was installed all along -- under
intel/iwlwifi/ -- and verify never mentioned it, because its firmware checks
came from CONFIG_EXTRA_FIRMWARE, which lists only what the IMAGE embeds.
Run-time firmware was covered by nothing.  verify now checks every
FIRMWARE_ONLY entry and counts the Intel wireless blobs by name.  A check
that covers one of two sources looks complete and is not.

## Say it before it takes a while  (1.14.141)

"after that output nothing happens and i do not know whats going on,..
please always provide output before we get a long loading process."  Fair,
and it applies to four steps: the Documentation copy (~10k small files), the
compile, modules_install, and the manifest scan that walks the filesystem.
Each now announces itself BEFORE it starts, and a test asserts the
announcement comes before the command rather than after it -- an "installing
X" printed afterwards is a log, not a progress message.

Second, the headers.  /usr/include/asm/*.h is owned by **p_linux-headers**
-- the LFS step that installed them -- and /usr/include is sticky, so p_linux
could not replace a single file.  Installing a newer kernel's headers is an
UPDATE OF THAT PACKAGE, so the copy runs as that account and its manifest is
refreshed.  HEADERS=no leaves /usr/include alone, which is right when the
running system's headers are deliberately older.  This is the same boundary
as the firmware directory and the setuid bit: when another package owns the
destination, either become that package or do not write there.

AND A NEAR MISS WORTH RECORDING: two edits to lfs-kernel in this release
collided and deleted `make $JOBS` outright -- the tool would have installed
modules from a tree it never compiled.  Nothing in the suite noticed, because
no test asserted that the build script builds.  It does now, including that
the compile precedes modules_install.  A test suite for a build tool should
start from "does it build".

## ...and not through a symlink into it  (1.14.140)

    note  p_linux records 266623 file(s)

and the "includes its own home" check added one release earlier said NOTHING
about it -- because the paths are not under the home.  modules_install leaves
**/lib/modules/<ver>/build as a symlink to the source tree**, the scan
follows it, and the whole tree comes back recorded as
/lib/modules/7.2.4/build/... .  Outside the home, so the home filter never
saw a single one.

The filter drops anything under /lib/modules/*/build/ or /source/ and KEEPS
the symlink itself, which is a genuine installed file.  verify reports that
case separately, in its own words -- "the manifest was scanned THROUGH
/lib/modules/7.2.4/build" -- because "includes its own home" would have been
the wrong explanation for the right symptom.

Two releases to fix one number, and the reason is worth keeping: 1.14.138
found A path into the sources and assumed it was THE path.  A filter is only
as good as the enumeration behind it, and following a symlink is a second
door into the same room.

## Verify must check what it installs  (1.14.139)

THE KERNEL STEP IS DONE.  26 checks green on the real system: image,
System.map, config, /lib/modules/7.2.4 with a full depmod index, headers, all
15 embedded firmware blobs, both manifests.

Which exposed the last gap in verify: it checked everything the tool installs
EXCEPT the out-of-tree module -- the one piece whose build had failed three
times.  A report that omits the flakiest thing it covers is worth less than
its length suggests.  When V4L2LOOPBACK is on, verify now checks for
v4l2loopback.ko under /lib/modules/<version> and that modules.dep knows it.

It also reports the manifest's size and FAILS if the account's own home has
reappeared in it -- the 266k-entry bug from 1.14.138 would have been caught by
its own verify, which is the standard the rest of the checks are held to.

WHAT REMAINS, and none of it is software: point rEFInd at vmlinuz_new (or
rename it over vmlinuz), reboot into 7.2.4, then run sway_start as the
desktop user with /run/udev present.  The tools have nothing left to install.

## The home is not installed files  (1.14.138)

    # recorded 266621 file(s) for p_linux

That is the kernel SOURCE TREE.  `list_package` lists everything an account
owns and its home is included -- sources, build trees, the install script.  A
manifest is what a package put ON THE SYSTEM: it is what `verify` checks and
what `remove` DELETES.  266k source paths in it make the first meaningless
and the second dangerous.

write_pkg_list filters the home (and the mail spool) out of the listing.  awk
rather than grep, because a filter that removes every line must still exit 0
-- with grep, a package whose files were all excluded would fail the `&& mv`
and silently keep its old manifest.  This affects every package, not just the
kernel; the build's own snapshot tracking always excluded the home, and only
the rescan did not.

Second bug, same run: `git pull` ran as ROOT with the chown afterwards, so
the next command -- as the package user -- met a repository owned by somebody
else, and git refused with "detected dubious ownership".  The directory is
created owned by the account and every git command runs as it, which removes
the class rather than adding safe.directory to work around it.

A note on the test for this: two assertions failed against correct code
because `grep` over the source matched the COMMENT explaining the fix.  Any
check that greps for an anti-pattern has to exclude comment lines, or the
explanation of why something is wrong reads as the wrong thing itself.

## A report should not build anything  (1.14.137)

`lfs-kernel verify` on the real system: twenty-five checks, one failure.

    FAIL  p_linux records its files

The kernel is completely installed -- image, System.map, config, modules,
depmod, headers, and every one of the 15 embedded firmware blobs.  The
manifest was missing because reload-pkg-list ran at the very END, after
v4l2loopback, and that step had failed.  So a perfectly installed kernel
reported itself unrecorded.  The manifest is written as soon as depmod
finishes -- the files exist at that point -- and again after the headers.

The other half is what verify printed before the report: it resolved
"latest" over the network, announced the chroot paths it was never going to
write, and would have CREATED the package account if it were missing.  A
report that fetches, announces and creates is not a report.  Four guards, and
a test that verify shares as little of the build path as possible.

Worth stating as a rule, because it took the user asking for a validation
command to notice any of this: A CHECK MUST BE CHEAPER AND QUIETER THAN THE
THING IT CHECKS.  If it needs the network, the accounts, or the config to be
right, it cannot be trusted to tell you whether those things are right.

## uname -r is not the version being built  (1.14.136)

THE KERNEL BUILT AND INSTALLED.  bzImage, System.map and config are on the
ESP, /lib/modules/7.2.4 is populated.  Everything after that failed for one
reason:

    depmod: ERROR: could not open directory /lib/modules/7.2.0
    make[1]: *** /lib/modules/7.2.0/build: No such file or directory

7.2.0 is the RUNNING kernel -- what this chroot booted.  `depmod -a` with no
argument means `uname -r`, and an out-of-tree module's Makefile defaults to
/lib/modules/`uname -r`/build.  Both are the wrong tree whenever the version
being built is not the version running, which in a chroot is always.

depmod takes "$VERSION" now, and v4l2loopback is driven from the tree
directly -- `make -C "$tree" M="$d" clean|modules|modules_install` -- which
sidesteps every such default and works for any out-of-tree module rather than
just this one.  A test asserts that uname -r appears only in REPORTING and in
last-good tracking, never in a path.

The user's original script had this right for its own situation: on a host
building the kernel it is already running, uname -r and $VERSION are the same
string.  Every difference between "the machine I am on" and "the machine I am
building for" has cost a release this session.

## lfs-kernel verify  (1.14.135)

"is the kernel part done?  if yes do we have a validation command so we know
everything is installed as expected?"  It was not done -- three more embedded
blobs (amd-ucode/*, amd/*) stopped it, and those are in the shipped
FIRMWARE_ONLY now: `amdgpu amd-ucode amd intel`.

And there was no validation command, which is why every answer to "is it
done" so far has been me reading a transcript.  `lfs-kernel verify [version]`
looks at the SYSTEM:

    ok    /boot/efi/EFI/NimGnu/vmlinuz_new       (what the firmware loads)
    ok    .../vmlinuz_new-7.2.4
    ok    the two are the same image
    ok    .../System.map-7.2.4  .../config-7.2.4
    ok    /lib/modules/7.2.4    modules.dep (depmod has run)
    ok    headers in /usr/include/linux
    ok    firmware /lib/firmware/amd-ucode/microcode_amd.bin
    ok    p_linux records its files    p_linux-firmware records its files
    note  last kernel known to boot: 7.2

With no version it takes the most recently installed one from the ESP, not
whatever kernel.org offers today.  Two checks are worth their place on their
own: `test -s` rejects a zero-byte image (a truncated copy to a full ESP),
and `cmp` catches $KERNEL_NAME differing from $KERNEL_NAME-$VERSION, which is
what happens when a later build fails halfway through the copies.  The
embedded-firmware list is read from the INSTALLED config, so it verifies what
that image actually needs rather than what the current config says.

## intel/iwlwifi  (1.14.134)

    git ls-files | grep -i iwlwifi
    LICENSES/LICENCE.iwlwifi_firmware
    intel/iwlwifi/iwlwifi-100-5.ucode
    ...

There it is.  Current linux-firmware nests the wireless blobs INSIDE intel/,
so `intel` -- which was already in FIRMWARE_ONLY and already installed --
covers the AX200.  The separate `iwlwifi` entry asked for a top-level
directory that does not exist, and that single wrong word cost four releases.

FIRMWARE_ONLY is `amdgpu intel`, and the config now says where the wireless
firmware lives so the next reader does not have to find out:

    intel            EVERYTHING Intel, in one directory:
                       intel/iwlwifi/   wireless (AX200 and the rest)
                       intel/ibt-*      Bluetooth

What actually resolved this was 1.14.133's index search -- one command, run
by the user, printing the real paths.  Everything before it was me reasoning
about a layout I could not see.  When a tool needs a fact about someone
else's data, the first version should go and read it.

## Ask the index, not the working tree  (1.14.133)

Asked where the iwlwifi firmware might be, with a link and a paste that
arrived empty.  The user's own output answered it better: the checkout is
SPARSE, and a sparse checkout REMOVES every path it did not select.  So
`iwlwifi` was reported missing, and the near-match search I added to explain
it searched the same pruned directory -- it could only ever find amdgpu and
intel, the two things already installed.

git's index lists every path the repository has, selected or not.
`git ls-files | grep -i <stem>` is the question that was actually being
asked, and the fixture proves the difference: after
`sparse-checkout set /amdgpu/ /intel/`, `ls` shows two directories and
`ls-files` still shows iwlwifi/iwlwifi-cc-a0-77.ucode.  The find() search
stays as a fallback for a plain directory that is not a repository.

Four releases on this one line, and the mistake was the same every time:
answering from what I believed about linux-firmware's layout instead of
making the tool ask.  The tool can now answer it in one run, which is what
should have been built first.

STILL UNANSWERED, and it needs the machine: whether this linux-firmware calls
the directory `iwlwifi`.  The next run prints the real paths.

## Firmware trouble should not cost you the kernel  (1.14.132)

"are we sure we successfully installed the kernel or is it the step
afterwards?"  No -- and that the question had to be asked is the bug.  The
firmware install runs BEFORE the build (CONFIG_EXTRA_FIRMWARE needs it) and
exited on failure, so three runs in a row built no kernel at all, and nothing
said so.

Now the firmware failure only stops the build when the config actually embeds
firmware.  Otherwise it warns, builds the kernel, and repeats at the end:
"NOTE: firmware was NOT installed".  A missing blob is a run-time problem for
the driver that wants it; it is not a reason to have no kernel.

And `iwlwifi` does not exist in this linux-firmware either -- the near-match
search from 1.14.131 only ran for PATTERNS, so a plain name got the same
useless "does not exist" the pattern had.  Both cases search now, and when
the stem matches nothing at all it lists the top level, because a sparse
checkout that fetched two directories looks identical to a repository that
does not have the file.

Three releases on one line of config.  The pattern in all three: I guessed at
someone else's directory layout instead of making the tool report it.  The
first version of a message like this should print what it found, not what it
expected.

## A pattern that matches nothing should say what is there  (1.14.131)

    # installing firmware: amdgpu
    # installing firmware: intel
    !! nothing matches 'iwlwifi-cc-*' -- check FIRMWARE_ONLY

amdgpu and intel resolved as directories, so linux-firmware keeps the Intel
wireless blobs in an `iwlwifi/` directory too -- the top-level
iwlwifi-cc-a0-*.ucode layout I assumed in 1.14.128 is an older release's.
The shipped default is `amdgpu intel iwlwifi`; the pattern form stays for a
release that puts them at the top level.

The change that matters is the failure: a pattern matching nothing now
searches for its stem two levels deep and prints what it found.  "nothing
matches iwlwifi-cc-*" sends the reader to go and look;
"iwlwifi/iwlwifi-cc-a0-77.ucode" IS the answer.  linux-firmware moves files
between the top level and subdirectories between releases, so this will
happen again to somebody.

Also: the sparse-checkout on the update path was `|| true`.  A failure there
leaves the previous selection in place, and the missing firmware then gets
blamed on the pattern -- which is exactly the wrong place to look.  It is
checked now.

## A config is shell, and a directory has an owner  (1.14.130)

    /etc/pkgusr/kernel.conf: line 74: intel: command not found
    # installing ALL of linux-firmware (FIRMWARE_ONLY is empty)
    cp: cannot create directory '/lib/firmware/3com': Permission denied
    ...two hundred more lines

Two bugs in one release of mine.

kernel.conf is SOURCED BY THE SHELL, and I shipped
`FIRMWARE_ONLY=amdgpu intel iwlwifi-cc-*` unquoted.  The shell ran `intel` as
a command, assigned nothing -- and an empty value meant "install
everything", ten gigabytes of it.  Quoted now, and an empty value is refused
with the likely cause named: FIRMWARE_ALL=yes is required to really mean all
of it.  A default that turns a typo into ten gigabytes is a bad default.

And /lib/firmware already existed, owned by root, so every copy by the
package user failed.  Firmware has exactly one owner, so root hands the
directory over -- the same boundary as the setuid bit (1.14.109) and the ESP
copies: a package user cannot chown, so anything about IDENTITY is root's,
done explicitly, once.

The lesson that generalises: a config file that is `.`-sourced is code.  Any
value with a space, a wildcard or a quote in it must be quoted, and every
shipped example is the thing people copy.

## -j14 by default  (1.14.129)

"(by default we just do -j14)".  kernel.conf shipped -j16; it ships -j14 now,
with the reason beside it -- a core or two left free keeps the machine usable
while a kernel builds, and the link step is memory-hungry.

Note for the next session: the attachment with this message came through
empty, so whatever the kernel build printed was not visible.  The job count
is the only change here.  If `make headers` or another late stage was
failing, that is still open and wants the log.

## Not all firmware lives in a subdirectory  (1.14.128)

"do we get the required iwl driver for wifi and so?"  With
FIRMWARE_ONLY=amdgpu, no.  The lsusb shows an Intel AX200, which needs
`iwlwifi-cc-a0-*.ucode` -- and those sit at the TOP LEVEL of linux-firmware,
not in a directory.  Its Bluetooth half needs intel/ibt-20-1-3.*.

So FIRMWARE_ONLY takes file PATTERNS as well as directory names, and the
shipped default is `amdgpu intel iwlwifi-cc-*`.  That forced a real change in
the clone: git's sparse-checkout uses CONE mode by default, which matches
directories only, so a pattern would have been silently ignored and the
wireless firmware never fetched.  When any entry contains a wildcard the
checkout switches to --no-cone and bare directory names become /dir/, which
is what that mode requires.  Installing follows the same split: a glob for
patterns, a name for directories, and a pattern matching nothing is an error.

Firmware without a driver is useless, so the config check grew the drivers
that need it: CONFIG_IWLWIFI, CONFIG_IWLMVM, CONFIG_BT_HCIBTUSB,
CONFIG_DRM_AMDGPU -- each reported with what it is for rather than as a bare
symbol.

Where the firmware settings ARE, since the question was asked: in
/etc/pkgusr/kernel.conf.  The user's installed copy predates them, so it has
no FIRMWARE_* lines at all -- kernel.conf.new beside it has.

## Firmware is part of the job  (1.14.127)

"we shouldnt jsut scip the firmware part,- its relevant."  Right, and
1.14.126's advice -- clear EXTRA_FIRMWARE and move on -- was the lazy half of
the answer.  amdgpu will not bring up a display without its blobs, whether
they are built in or loaded at run time.

lfs-kernel installs firmware now, before the check that needs it, as ITS OWN
PACKAGE (p_linux-firmware): a separate upstream project with its own release
pace should be one row in `verify`, updatable without touching the kernel.

    FIRMWARE_FROM=git             # kernel.org's linux-firmware
    FIRMWARE_FROM=copy:/lib/firmware   # a tree you already have
    FIRMWARE_FROM=none            # leave it alone
    FIRMWARE_ONLY=amdgpu          # which subdirectories; empty = all

The size problem is why FIRMWARE_ONLY exists: linux-firmware is over ten
gigabytes.  With a subset named, the clone is `--filter=blob:none --sparse`
plus `sparse-checkout set`, which fetches those directories and nothing else.
Without it, the tool says how large the download is before starting.

And the message for a missing built-in blob now names the fix that exists
rather than telling the user to go and install something: the subdirectory of
the missing file is what to add to FIRMWARE_ONLY.

## Firmware built into the kernel must be on disk  (1.14.126)

    make[6]: *** No rule to make target '/lib/firmware/amdgpu/renoir_asd.bin',
             needed by '.../builtin/amdgpu/renoir_asd.bin.gen.o'.  Stop.

Not the cancelled build -- a real missing file.  CONFIG_EXTRA_FIRMWARE embeds
blobs IN the image, read at build time from CONFIG_EXTRA_FIRMWARE_DIR
(/lib/firmware).  The config came from the running distribution kernel
(CONFIG_FROM=running), which lists a dozen; an LFS tree has no
linux-firmware.  So the build compiled amdgpu for ten minutes and then died
in drivers/base, naming ONE file and no reason.

lfs-kernel now reads CONFIG_EXTRA_FIRMWARE straight after olddefconfig,
checks every blob against the configured directory, and lists all of the
missing ones with both ways out: install linux-firmware, or

    ./scripts/config --set-str EXTRA_FIRMWARE ''

...after which the drivers load the same firmware at RUN time instead, which
is what a normal kernel does anyway.

The pattern, and it is the one this whole session keeps returning to: the
check belongs where the DECISION is made, not where the consequence appears.
The decision is in the config; the consequence is a link error in a
subdirectory of drivers ten minutes later.

## Input devices come from udev  (1.14.125)

    [wlr] libinput initialization failed, no input devices
    [sway] Failed to start backend

The DRM error is GONE -- wlroots opens the card now, so 1.14.115 was the
right fix -- and libinput found nothing to listen to.  "maybe sway would
start if i wouldnt be in a chroot": yes.  libinput enumerates through
libudev, which reads /run/udev; a chroot without the host's /run has no
device database at all, and the message names libinput rather than the
chroot.

sway-session checks /run/udev first and says which of the two causes it is (a
chroot, or udev not running), how to make a chroot work (bind-mount /run and
/dev), and how to prove the rest of the stack works without any input
devices at all (WLR_LIBINPUT_NO_DEVICES=1).  It also refuses when started
from a tty that is not the active console, which opens nothing.

Two things found while writing it.  The seat check looked for
/bin/seatd-<user> while mytools installs to /usr/bin -- correct only where
/bin is a symlink, and reporting a missing file that exists where it is not.
It uses `command -v` now.  And the sway-session assertions from 1.14.100 had
been LOST when 1.14.106 rewrote that test block: the file had one line of
coverage left.  Rewriting a test block is not the same as updating it, and
the difference is invisible until something breaks unnoticed.

## A config from an older release  (1.14.124)

"i still see that in the config: ... SRC=/usr/src/linux -- maybe with a
reason, idk."  No reason: SRC was removed in 1.14.123, and what the user was
reading is the INSTALLED copy from before it, kept because kernel.conf is
never overwritten once edited.  The protection is right; the gap was that
nothing noticed a config describing settings that no longer exist.

lfs-kernel checks now: a leftover SRC is named and ignored, and a config with
no PKG is refused with the two ways out (take the .new, or add PKG=linux).
A file whose MEANING has changed is not the same problem as a file that is
out of date, and the tool has to say which.

Shipped values are the author's: ESP=/boot/efi/EFI/NimGnu,
KERNEL_NAME=vmlinuz_new -- a new kernel lands beside the working one and
rEFInd still boots vmlinuz until they swap it.

Note on the shipped config as documentation: the example above the setting
used to read "ESP=/boot/efi/EFI/NimGnu ... # the real one", which is now the
line below it as well -- an example that duplicates the actual value teaches
nothing.  It shows the two KERNEL_NAMEs instead, which is the choice being
made.

## The kernel is a package  (1.14.123)

"in the config i dont realy get the 'source' part. the linux will get
installed like a normal package, so over the pkguser and in its
corresponding home."  Correct, and SRC was a location I invented outside the
model -- exactly what the model exists to avoid.

PKG=linux names the account.  Its sources live in
/usr/src/pkgusr/p_linux/src, like every other package's; there is nothing to
configure.  The account is created if missing, fix-home runs first (1.14.111),
and reload-pkg-list records the manifest at the end, so `verify`, pkg.lst and
`remove` all work on the kernel.

The division of labour, which is the interesting part:
  * AS THE PACKAGE USER: olddefconfig, make, modules_prepare,
    modules_install, headers, the doc copy, v4l2loopback.  So
    /lib/modules/<version>, /usr/include and /usr/share/doc/linux-<version>
    are owned and recorded like any package's files.
  * AS ROOT: the tarball fetch, and the copies onto the EFI partition.  vfat
    carries no ownership and the mount is root's -- the same boundary as the
    setuid bit in 1.14.109.

A detail worth stating because it bit twice: EVERY command that touches the
tree must run as the package user.  The first version left the .config write
and olddefconfig as root, which puts root-owned files in the account's home
and breaks the next build -- a test now asserts that no build stage runs at
top level.

## The refresh list came from a literal  (1.14.122)

"lfs run commmand is not copying that new script i think"  It was not.
TOOLCHAIN_SCRIPTS was a hardcoded tuple of five names, lfs-kernel went into
the Makefile and not into it, and `lfs run` refreshed five of six tools --
the missing one being the tool written minutes earlier.

Two lists of the same thing is the fault.  The Makefile's TOOLS line decides
what `make install` places, so it now decides what the refresh carries; the
literal survives only as a fallback for a tree with no Makefile beside the
tools, and a test asserts the two agree.

kernel.conf travels with it, from beside the tool or /etc/pkgusr, keeping an
edited copy in the chroot -- refreshing lfs-kernel without its config would
put a command in the chroot that refuses to start.

Fourth time this session that adding something meant editing a second place
that nobody remembered (the Makefile's stacks loop, the chroot stack refresh,
the .shipped record, this).  Anything enumerating the tools or the files
should DERIVE the list.  HANDOFF's standing note now reads: when adding a
file to the project, grep for the name of a sibling file first -- every place
it appears is a place the new one belongs.

## lfs-kernel: its own tool, its own config  (1.14.121)

"it should not get provide by the packagemanager command,- its an extra file
we install id say, so we can easily configure it beforehand."  Right: a
config written as a side effect of trying to build is a config you cannot
edit first.

  * **stacks/kernel.sh is now /usr/bin/lfs-kernel**, installed with the other
    tools, out of services.stack entirely.  `lfs-kernel`, `lfs-kernel list`,
    `lfs-kernel 6.12.40`, `lfs-kernel latest`, `lfs-kernel detect-esp`.
    Arguments are handled BEFORE the config is read, so --help and
    detect-esp work on a system that has no config yet.
  * **kernel.conf ships** and `make install` places it, keeping an edited one
    and leaving the new one as .new -- the same rule as the stack files.  A
    missing config is reported, never written silently.
  * **ESP + KERNEL_NAME** are the pair that decides which kernel this is,
    with the test/real example spelled out in the config:
        ESP=/boot/efi/EFI/NimGnu  KERNEL_NAME=vmlinuz       # the real one
        ESP=/boot/efi/EFI/test    KERNEL_NAME=vmlinuz-test  # a trial
    The old file is kept as ${KERNEL_NAME}_old and a copy as
    ${KERNEL_NAME}-${VERSION}, so versions sit side by side.
  * **THE LAST WORKING SOURCE IS NEVER DELETED.**  A kernel that boots is the
    only way back from one that does not, and its TREE is what you need to
    rebuild or bisect -- not just the bzImage.  The running version is
    recorded in /etc/pkgusr/kernel.last-good before the new one is installed,
    and nothing removes that tree.

## A kernel step you can read  (1.14.120)

"the kernel.sh script is a bit to trashy to simply configure it,... also id
like to be able to easily get the newest release of kernel.org ... also the
ESP var is not set, idk what it is and how to set it."  All three fair.

Rewritten around them:

  * **The commands are one block**, after a line saying THE COMMANDS.
    Everything above it picks a version and checks paths; everything below is
    the build, and is meant to be read and edited.
  * **VERSION=latest** asks kernel.org's releases.json for the newest
    stable.  KERNEL_VERSION=7.3 overrides it for one run, KERNEL_LIST=1
    prints what is on offer (mainline/stable/longterm), and the tarball is
    fetched from cdn.kernel.org if it is not already in $SRC.  Picking a
    different kernel when one fails is now one variable.
  * **ESP detects itself**: the vfat mount that already contains a vmlinuz,
    written into the config with a comment saying what it is and how to check
    it (findmnt -t vfat).  It was previously an unexplained variable with no
    default, which is why it was empty.

A parsing note worth keeping: releases.json lists "version" BEFORE "moniker",
and pairing the two by POSITION -- `grep | paste - -` -- silently swapped the
columns, so `$1=="stable"` matched nothing and "latest" resolved to the empty
string.  The keys are paired by NAME now.  Key order in someone else's JSON
is not a thing to depend on.

## Check the paths, not the chroot  (1.14.119)

"i dont think its a problem to run the commands in chroot,- we still should
be able to get running config and to install modules and kernel file at its
places".  Correct, and 1.14.118's refusal was wrong.  The chroot usually IS
the tree that boots: /proc is shared so /proc/config.gz is the running
config, /lib/modules is the right tree, and the ESP is right if the EFI
partition is mounted inside.

So the step no longer judges WHERE it runs; it checks the things that can
actually be wrong.  In a chroot it lists the three paths to verify -- $ESP,
/lib/modules, /proc/config.gz -- and continues.

The real check, which 1.14.118 half-had: the ESP must be ON the EFI
partition.  `stat -f` must report vfat/msdos/exfat; a directory of the right
name on the root filesystem is refused, and an unidentifiable filesystem is a
warning.  That is the failure worth catching, because every copy SUCCEEDS and
the firmware finds nothing at the next boot -- an error separated from its
cause by a reboot.

Two releases to arrive at: do not police the environment, verify the specific
thing that would break.  The first version confused "unusual" with "wrong".

## The kernel is built on the booted system  (1.14.118)

Asked how to run the kernel step.  The answer needed a guard first, because
the obvious thing -- running it in the chroot like everything else -- is
wrong in a way that looks right: a chroot SHARES /proc, so /proc/config.gz
reads the host's config and the step would happily proceed, while
modules_install writes the chroot's /lib/modules, depmod indexes the wrong
tree, and /boot/efi is not the real ESP.  A kernel built for a system that is
not running it.

kernel.sh compares / with /proc/1/root and refuses in a chroot, naming the
command to run outside.  It refuses only on POSITIVE evidence: where
/proc/1/root cannot be read the comparison says nothing, and refusing on "I
could not tell" would block the step on ordinary systems.  Both directions
are asserted.

Second guard: an absent ESP is refused rather than created.  `install -d` on
an unmounted mount point makes a directory on the root filesystem, the copy
succeeds, and the firmware never sees the kernel -- a failure that appears
only at the next boot.

    # on the BOOTED system, not in the chroot
    packagemanager stack services --run --only kernel     # writes the conf, stops
    $EDITOR /etc/pkgusr/kernel.conf
    packagemanager stack services --run --only kernel     # builds

## Giving the files back  (1.14.117)

The 1.14.116 diagnosis fired exactly as written -- "rounds run: 3", naming
wrap_mode=nodownload -- and the wrap_mode itself never took effect, because
the section lives in the SHIPPED machine.conf and the user's own copy is
protected.  meson's summary still said `wrap_mode: nofallback`.  Same .new
mechanism as ever; the fix is one section pasted in, or machine.conf.new
taken.

The question worth answering properly was the user's: "we will sometimes get
that problem that we have to overwrite files,... idk how to handle that".
THE POLICY, in three cases:

  1. LEGITIMATE OVERLAP -- two packages genuinely install the same path
     (icon caches, .desktop dirs).  Ownership follows the installer; the
     handover is right and automatic.
  2. A BUNDLED COPY -- the package builds another package inside itself.
     Stop the bundling (wrap_mode, --force-fallback-for, a configure flag).
     Never let the handover "win" here: it silently transfers a whole
     package to the wrong account.
  3. A DELIBERATE REPLACEMENT -- the new package is meant to supersede the
     old.  Remove the old one; two owners for one file is the thing the
     model exists to prevent.

And case 2 needs a way back, which did not exist: `packagemanager reclaim
<package>` reads the victim's manifest, finds every recorded path now owned
by someone else, and returns it.  Dry run by default, root required, symlinks
not followed.  After it, the aggressor's own manifest still lists those paths
-- `reload-pkg-list <aggressor>` cleans that up.

## One file per round is a loop, not progress  (1.14.116)

libdisplay-info -- added one release earlier to fix the DRM backend -- went
TWELVE rounds, each re-cloning a subproject and handing over one more file:

    .../locale/fr/.../v4l-utils.mo belongs to p_v4l-utils -- handing it over
    ... round 7 ... pt_BR/v4l-utils.mo ... round 8 ... libv4lconvert.so ...

It builds **v4l-utils as a meson subproject** for its edid-decode comparison
tests, and installs that package's real files over p_v4l-utils's.  meson
stops at the FIRST file it may not replace, so its log names only that one,
and each round learns exactly one more: the handover can never catch up.

Two fixes.  The book passes --wrap-mode=nofallback, which blocks fallbacks
for dependency() lookups only -- an explicit subproject() still downloads --
so machine.conf ships `[libdisplay-info] wrap_mode = nodownload`.  And the
retry loop counts single-file handovers from the same package: three in a row
means a bundled copy, it says so, names wrap_mode=nodownload, and stops.

The general rule, which the ownership machinery had been missing: HANDING
OVER FILES IS FOR PACKAGES THAT LEGITIMATELY OVERLAP.  A package installing
another's entire output is not overlapping, it is duplicating, and no amount
of correct ownership transfer makes that right.

## The DRM backend was never built  (1.14.115)

    [wlr] Cannot create DRM backend: disabled at compile-time
    [sway] Unable to create backend

Not the kernel, and not seatd: the log shows seatd opening seat0 and the
client attaching cleanly.  wlroots 0.19's DRM backend requires
**libdisplay-info**, which is in the BOOK and was not in the stack.  meson
disables drm when it is missing, notes it in a summary line, and builds
happily -- so a complete desktop was installed that cannot open a screen.
libdisplay-info is in the stack now, ahead of wlroots, and the backend list
is EXPLICIT (-Dbackends=drm,libinput,x11): an auto-detected list is a silent
dependency, and this was the silently missing one.

Also from the user's own commands:
  * sway   -Dman-pages=enabled -Dswaybar=true -Dswaynag=true
           -Dbash-completions=true
  * seatd  -Dserver=enabled -Dlibseat-seatd=enabled.  Which of the two option
    sets to use was the user's open question: seatd-user execs
    /usr/bin/seatd, so the SERVER must be built even though no daemon runs at
    boot, and libseat needs its seatd backend because LIBSEAT_BACKEND=seatd.
  * the seatd boot service is confirmed gone from the stack (1.14.100).

stacks/kernel.sh: the author's kernel procedure as a step, configured by
/etc/pkgusr/kernel.conf (version, ESP, jobs, boot logo URL, v4l2loopback
on/off, where .config comes from).  It writes the config and stops on the
first run.  It also WARNS about CONFIG_DRM, DRM_FBDEV_EMULATION, INPUT_EVDEV
and SYSVIPC, because a monolithic kernel missing those produces exactly the
error above, one layer further away.

And add-user's report: `add-user n76310` created p_n76310 and then described
"n76310" -- the human login of the same name, its uid, its /home, its
groups.  Every line true of the wrong account.

STILL OPEN, needs the machine: root cannot log in after boot ("no password
entry"?), and `su` in the chroot says "must be run from a terminal".  The
second is normal in a chroot without a controlling tty.  The first wants
`ls -l /etc/shadow` (0600 root:root), the root line from `getent shadow root`,
and whether /bin/bash is in /etc/shells.

## One base, two readings  (1.14.114)

1.14.113 made the symptom legible: after fix-home the passwd entry was right,
and running the step put it straight back.  Both were working correctly on
different answers to the same question.

`lfs` exports LFS_PKGUSR_ROOT from the config key `pkgusr_home`.  Its default
is /usr/src/pkgusr; its help text said "the base the homes hang under
(/usr/src)"; and a SECOND key, `pkgusr_subdir`, is "folder under the base for
package homes (pkgusr)".  Read one way the base already contains the folder,
read the other it does not -- and packagemanager appends the subdir while
`lfs` exported the bare base.  So on a tree configured the second way, every
account's home is /usr/src/p_<name> to `lfs` and /usr/src/pkgusr/p_<name> to
everything else.  add_package_user made the husk there; fix-home moved it;
the step moved it back.

`lfs` composes the value now, appending the subdir unless the base already
ends in it -- the same rule packagemanager has had all along -- and the help
text no longer invites the other reading.

The root cause is not the code, it is TWO CONFIG KEYS THAT CAN BOTH ANSWER
ONE QUESTION.  Any setting whose meaning depends on how another setting was
read will eventually be read both ways by two different programs.  Worth a
sweep: pkgusr_home/pkgusr_subdir and cfguser_home/cfguser_subdir are the pair
here, and one of each ought to go.

## Check that it took  (1.14.113)

    lfs-helper fix-home p_n76310 --run
    # p_n76310: home -> /usr/src/pkgusr/p_n76310
    ...and the next command: "p_n76310's home is /usr/src/p_n76310"

Three runs, three reports of success, no change.  `usermod -d` returned 0
while /etc/passwd kept the old home, and the message was printed on the
strength of an exit code that meant nothing.  (Why usermod does that here is
still unknown -- a chroot without a working shadow database is the likely
answer -- and it no longer matters: the tool stops believing it.)

_set_recorded_home reads the home back after writing.  If usermod's claim is
false it falls through to the file rewrite, and the file rewrite is verified
too -- `cat` exiting 0 says nothing about whether the line was matched.  An
account that is not in passwd now fails instead of succeeding.

Fifth instance this session of the same rule, and the clearest: 1.14.64 (a
zero exit over a failed log), .87 (validate against what was declared), .101
(a step that installed nothing), .111 (a manifest in the wrong place), and
now a write nobody read back.  THE TOOLS SHOULD CONFIRM THEIR OWN EFFECTS,
always, because every layer below them will report success it has not earned.

## The skeleton is not data  (1.14.112)

    /usr/src/p_n76310 kept: these files differ ... compare and remove by hand
      differs: .project, build.conf, .bash_profile, .bashrc, build
    # p_n76310: home -> /usr/src/pkgusr/p_n76310
    ...and the next run: "p_n76310's home is /usr/src/p_n76310"

Those five files are the SKELETON, written by whoever creates an account.  A
husk and a real home therefore differ in exactly them, every time, so the
merge always refused, the husk never went away, and fix-home reported "home
-> ..." while the thing that mattered stayed put.  The repair could not
succeed on any system, ever; it just took a package user with two homes to
notice.

_merge_dir_into treats .bashrc, .bash_profile, .project, build, build.conf,
.wget-hsts and .bash_history as disposable in the SOURCE: the destination's
copies are the ones in use.  A file that is neither identical nor skeleton is
still kept, and the real home's copy is never overwritten -- both asserted.

The tell, in hindsight: an error message that lists the same five filenames
every time is not reporting a conflict, it is reporting a rule.

## Installed, and invisible  (1.14.111)

add-user now creates p_n76310 at /usr/src/pkgusr/p_n76310 -- and pm-install
still worked in /usr/src/p_n76310, the husk add_package_user leaves behind.
Three files installed, "n76310: done", and verify said "not installed": the
manifest was written to a directory nothing reads.

`lfs-helper fix-home` is the existing repair (1.14.27's helper knows this
exact case, calling it "the husk").  The mytools step runs it BEFORE anything
touches the account, and refuses if the recorded home still is not canonical.
And it checks the outcome: if pkg.lst is missing or empty after a successful
install, it says so and offers reload-pkg-list rather than reporting done.

Three consecutive releases on the same package (109, 110, 111), each a
different way for "the account" and "where its files live" to disagree.  The
package-user model has three separate notions of a home -- the passwd entry,
the canonical path the tools compute, and the husk the hint's helper makes --
and every command that touches an account has to reconcile them.  ONE function
should own that; there are at least four call sites doing it differently.

## A package name is not an account name (again)  (1.14.110)

The wrapper installed and got its 4750 root:n76310 -- and then:

    cat: /usr/src/pkgusr/p_n76310/pkg.lst: No such file or directory

The account's home is /usr/src/**p_n76310**, without the pkgusr/ component,
so verify -- which scans /usr/src/pkgusr -- never saw the package at all.

`packagemanager add-user n76310` asked whether "n76310" exists.  It does: it
is the human's LOGIN account.  So add-user said "already exists", created
nothing, and the install runner then made p_n76310 itself with the package-
users hint's default home.  Exactly 1.14.85's fault in a different command:
there, reload-pkg-list passed a package name where an account name was
wanted; here, add-user tested one.  Both now go through pkgusr_name().

Second bug in the same run: the seatd wrapper was still installed three
times, because pm-install prefers the script already in the package home
(1.14.21) and that copy was the old one.  That preference is right for a book
page someone tweaked and wrong for a script shipped by releases, so the
mytools step refreshes the home copy when it differs.

TO REPAIR AN EXISTING MISPLACED ACCOUNT:
    packagemanager remove n76310 --purge --run
    usermod -d /usr/src/pkgusr/p_n76310 p_n76310   # or purge and re-create
then run the step again.

## A setuid file cannot be replaced by the user who made it  (1.14.109)

wifi and sway_start installed; then

    install: cannot remove '/usr/bin/seatd-n76310': Operation not permitted
    /usr/bin/seatd-n76310   -rwsr-x--- root:n76310

The wrapper from the previous run is root-owned and setuid -- step 4 makes it
so on purpose -- and /usr/bin is sticky, so only its owner may replace it.
The package user built a new one and could not put it down.  A package that
hands a file to root can never update that file again.

Root is running the step, so root clears the way: if seatd-<user> exists and
is not owned by the package account, remove it before the build, and put the
setuid bit back after.  The test asserts the ORDER -- remove, build, chmod --
because any other arrangement fails on the second run rather than the first.

Also fixed there: install_pkg installed both the entry's artifact AND the
seatd wrapper on every pass, so the wrapper was written once per source line.
Three writes, and the third is the one that hit the file it no longer owned.
Each entry installs its own artifact now, and a missing build product is an
error rather than a silent skip.

## It may be in the file waiting beside this one  (1.14.108)

    not in this stack: mytools
      entries: acpid, blfs-bootscripts, fcron

True, and useless: `cfg mytools` was in services.stack.new, three lines
above in the same output, and the message did not connect the two.  --only
now looks in the .new file for any name it cannot find and prints the exact
command, with the flags the user already typed:

    mytools IS in the newer file beside this one:
        /etc/pkgusr/stacks/services.stack.new
      Take it and run the same command:
        packagemanager stack services --take-new --only mytools

A name in neither file is still just an error.

Seven releases now on the same protection, and the shape of every one has
been identical: the tools knew the answer and made the person work it out.
The .new mechanism should be reconsidered wholesale next session -- probably
by having `make install` and the chroot refresh agree on a single source of
truth, so a second copy never appears.

## A .new with fewer entries is a downgrade  (1.14.107)

    took the shipped stack file; yours is .../services.stack.bak
      3 entries now.
    NameError: name 'only' is not defined

Two faults, and the first is worse than it looks.

`--take-new` took a .new that was SMALLER: 6 entries replaced by 3.  The
chroot refresh writes <stack>.new from the HOST's copy when the chroot's
differs (1.14.105), and the host is the stale one here -- `make install` kept
its file because it looked edited.  So the loop was: take the good file in
the chroot, refresh brings the host's old one in as .new, take it again, and
the stack shrinks back.  --take-new now refuses a shrink, says the host is
probably the stale side, and gives the one-line fix; --force overrides.

The NameError was mine, from consolidating the two --only implementations in
1.14.106: I removed the `only` variable and left a reference to it, and every
stack run crashed.  A duplicate implementation is bad; removing half of one
without reading the rest is worse.  The suite could not catch it because it
greps sources rather than running `stack` -- a test that RUNS the command,
even against a two-line fixture, is now in the block beside it.

## Their name, their macro, one entry at a time  (1.14.106)

Four things from one run of `cfg mytools`.

**The account is theirs.**  "the user should be called p_n76310 (thats a fixed
name for thoose packages as they come from me)".  The package is named after
the person, so verify, pkg.lst and `packagemanager remove` all say their name.
MYTOOLS_NAME carries it from the step into the script, so install_last and the
account agree.

**The macro.**  `gcc seatd-user.c -DSEATD_USER="$u"` reaches gcc as
-DSEATD_USER=n76310 -- the rewritten program stringifies it itself.  The
script had passed \"n76310\", a different macro, which is what produced
"error: 'n76310' undeclared".  The SOURCES entries are single-quoted now:
inside a double-quoted array element the escapes collapse before eval sees
them, which is how the wrong form got there.

**--yes must reach what a cfg step calls.**  `lfs-helper pm-install` asks
"Press enter to continue" unless PM_YES is set, so an unattended stack run
stopped at a prompt with nobody there.  cmd_stack exports PM_YES and
LFS_ASSUME_YES when --yes is given.

**--only.**  It had been DECLARED long ago and never implemented -- the help
promised "repeatable or comma-separated" and the flag did nothing.  Now it
exempts the named entries from the done-cache AND skips the rest, so
`--only mytools` re-runs one line of a 56-entry stack.  I added a second
declaration before noticing the first; argparse refused the duplicate, which
is the only reason I looked.

## Not everything in that directory is a stack  (1.14.105)

    # refreshed in the chroot: .shipped/desktop-user.sh, .shipped/kernel-
    sway.sh, ..., services.stack, services.stack.new

Two faults, both introduced by 1.14.104's directory copy.

.shipped/ is make install's record of what it last shipped (1.14.98); .new
and .bak are merge leftovers.  Bookkeeping does not travel: the refresh now
skips dot-names and those suffixes.

Worse, services.stack itself was copied over the chroot's.  The "never go
backwards" guard compares VERSIONS, and stack files carry none, so the host's
copy always won -- and the user had just taken the 6-entry file inside the
chroot with --take-new.  The refresh put the 3-entry host copy back over it,
undoing the previous release from the outside.  A stack file that exists and
differs is now the chroot's own, and the incoming one waits as .new, the same
rule `make install` follows.

Three releases in a row where a fix in one copy of a walk was undone by
another copy elsewhere (Makefile -> lfs refresh -> this).  Everything that
moves stack files should share one function; there are currently three, and
the next session should make it one.

## The same walk, twice  (1.14.104)

    ### stack (1/6): cfg mytools
    !! missing /etc/pkgusr/stacks/mytools/install_mytools

1.14.102 fixed exactly this in the Makefile: the loop over stacks/* took
FILES only, so the mytools directory never installed.  The chroot refresh in
`lfs` is a second copy of that walk, and it had the same fault -- so the
directory reached the host and stopped there.

Both handle directories now, and the test asserts both, because the fault was
never in the logic; it was in there being two of it.  When a fix is written,
the next question is where else the same walk lives.

(A test note: the assertion's sed range ended at /continue/, which matched
the first `continue` INSIDE the inner loop, before the chmod it meant to
check -- so a correct implementation failed.  A range delimiter has to be a
line that can only mean the end.)

## Take it, rather than describe it again  (1.14.103)

    a newer version of this stack ships beside it:
        services.stack.new   (6 entries, this file has 3)
    ### stack: services.stack  (3 entries)

1.14.99's note worked perfectly and changed nothing: three runs in a row the
user read it, ran the stack, and got the old three entries -- because the
note asked THEM to do work that was mine to do.  `--take-new` takes the
shipped file, keeps theirs as .bak, removes the .new, and runs the result:

    took the shipped stack file; yours is .../services.stack.bak
      6 entries now.

Five releases around one protection (1.14.58, .92, .98, .99, .103).  The
sequence is worth remembering as a whole: protect the file, teach verify past
it, teach install to retire it, tell the user it exists, and finally DO the
thing the telling was asking for.  Only the last one actually moved the
system forward.  A message that asks the reader to run a command they did not
choose to look up is a design that has not finished.

## One package user for everything of your own  (1.14.102)

"make a setup script for such things so i can bundle them cleanly ... maybe
even under one packageuser so i can easily find all additional
scripts/programs from my side -- we could also add swas, swov, swbr,
browser."

The right shape is not a shell script that scatters files, which is what
1.14.100's desktop-user step was: it is an ORDINARY PACKAGE-USER INSTALL
SCRIPT.  stacks/mytools/install_mytools declares a SOURCES list -- kind, name,
url, destination, build command -- and everything in it becomes files owned
by p_mytools, recorded in its pkg.lst, listed by `verify`, and removable with
`packagemanager remove mytools`.  Adding a program is one line.  The four sway
helpers are there, commented, ready to move off their own accounts.

stacks/mytools.sh does only the two things a package user may not: create the
account, and set the setuid bit on the seatd wrapper afterwards.  The build
itself goes through `lfs-helper pm-install`, the same runner as every other
package, so tracking, grants and the failure box all apply unchanged.

The lesson worth carrying: when a user asks for "a setup script", the answer
in a package-user system is usually a PACKAGE, not a script.  The machinery
for owning, listing and removing files already exists; a script that installs
things outside it gives up all of that and gains nothing.

## A step that installed nothing is not done  (1.14.101)

"which step exactly is compiling the seatd-n76310 program"  `cfg
desktop-user` -- and it had already run, reported "done (stack cache)", and
installed nothing.

If the chroot has no network its three fetches all fail; the script printed
"could not fetch" and exited 0; the stack recorded it done; and the cache
makes a recorded entry disappear from every later run.  A false "done" is
therefore permanent.  Exactly 1.14.64's fault -- a zero exit over a log that
says otherwise -- one layer up, in a config step rather than a build.

Two fixes.  The step checks its own work: /bin/seatd-<user>, ~/bin/sway_start
and /bin/wifi must exist, and the wrapper must be mode 4750 root:<user>, or
it exits 1 naming what is missing and how to install from local copies
(SEATD_USER_URL=file:///...).  And the stack runner refuses to record a
git/tar entry whose prog=/have= is still absent after a build that claimed
success -- it says so and leaves the entry to be retried.

The rule this is the third instance of: a step's exit status is a claim, and
a claim is worth recording only when the artifact it claims is on disk.  The
tools already knew how to check -- prog=, have=, the manifest -- and simply
were not asking at the moment the result was written down.

## The seat comes from a per-user wrapper  (1.14.100)

1.14.94 built a seatd boot service and a `seat` group, reasoning from what the
system had.  The user has something better: seatd-user, a setuid program
compiled for ONE username (-DSEATD_USER=\"$u\"), installed -rwsr-x--- root:$u
as /bin/seatd-<user>.  No daemon at boot, no group to join, and the seat
exists only while that user asks for it.  The boot script is deleted, not
kept "just in case" -- two ways to get a seat is worse than one.

`cfg desktop-user` compiles and installs the wrapper, puts their sway_start
in ~/bin with the `sway` alias and $HOME/bin on PATH, and installs their wifi
script in /bin.  It refuses rather than guesses: LFS_DESKTOP_USER names the
user, /etc/pkgusr/desktop-user remembers it, and an ambiguous /home is an
error listing the candidates.  Anything already installed is left alone, and
a failed download says so instead of installing nothing quietly.

NOT VERIFIED FROM HERE: the three URLs are on git.christianimmanuel.de, which
this sandbox cannot reach.  The commands are the user's own, verbatim; the
fetch either works on their machine or says which URL failed.

sway-session's checks changed with it -- it looked for the `seat` group and
/run/seatd.sock, both of which are now wrong; it looks for
/bin/seatd-$(id -un).

## A newer version is sitting beside it  (1.14.99)

Twice in a row, after two separate fixes:

    ### stack: services.stack  (3 entries)

while the shipped file had six.  1.14.98 was right and still did not help on
this run: the .shipped record did not exist yet, so the very first install
under the new scheme had to take the KEPT path and leave services.stack.new
-- correct, and completely invisible.  The user's "not sure if it did
anything" was, again, exactly right.

The moment to mention a pending merge is the moment someone RUNS the file.
`packagemanager stack` now says so, with the counts that make it obvious:

    a newer version of this stack ships beside it:
        /etc/pkgusr/stacks/services.stack.new   (6 entries, this file has 3)
      diff /etc/pkgusr/stacks/services.stack /etc/pkgusr/stacks/services.stack.new
      ...and take what you want; this run uses YOUR file.

A note, not a refusal.  Fourth repair around one protection, and the last one
needed: 1.14.58 created the .new file, 1.14.92 taught verify to look past it,
1.14.98 taught install to retire it, and this tells the person it exists.
Three of those four were needed only because the first shipped without a way
for anyone to LEARN that the .new file was there.

## Keep only what the user really edited  (1.14.98)

    packagemanager stack services --yes --run
    ### stack: services.stack  (3 entries)

Three, while the shipped file had six: seatd-init, bash-completion and
shell-env sat in services.stack.new waiting for a manual merge that nothing
announced.  "not sure if it did anything" is the correct reaction.

1.14.58 was right that a user's edits must survive `make install`, and
1.14.92 taught verify to see past the same protection -- but the INSTALL kept
every file forever, edited or not, so a shipped fix could never arrive on its
own.  make install now records what it shipped, in
/etc/pkgusr/stacks/.shipped/: if the installed copy still matches that
record, the user never touched it and it is ours to update; if it differs, it
is theirs and the new one lands as .new, as before.

    services.stack (updated -- you had not edited it)
    sway.stack -> KEPT YOURS; new version saved as ...

That is the third repair to the same protection (1.14.58 made it, 1.14.92
made verify see past it, this makes install see past it).  A rule of the form
"never touch X" needs, from the start, an answer to "then how does a fix to X
ever reach anyone?"

## The interactive shell is a config step  (1.14.97)

"we missed ls colors and bash autocompletion, and tab-completing a user after
su -- at which step do we integrate that?"

At a `cfg` step, and the reason is the same one that hid seatd: BLFS's "The
Bash Shell Startup Files" page is CONFIG, not a package.  It writes
/etc/profile and /etc/bashrc, and /etc/bashrc is what evals dircolors and
aliases ls --color=auto.  No package stack ever runs a config page, so on a
system built entirely from package stacks, ls is never coloured.
bash-completion is not a BLFS package at all -- it comes from upstream, so it
is a git entry (2.18.0, confirmed with git ls-remote and by --check-refs).

stacks/shell-env.sh writes /etc/dircolors and a BLFS-shaped /etc/bashrc:
coloured ls and grep, the red/green prompt, the bash-completion loader, and

    complete -A user su sudo passwd chage groups id

which is what makes `su p_<tab>` cycle the package users -- a daily action on
this kind of system, and worth having even without bash-completion installed.
An existing /etc/bashrc is never overwritten (it lands as .new), and
/etc/pkgusr/bashrc gets a line so package users source it too.

SUITE RUNTIME: the regression suite now exceeds a single execution slot here;
the last full runs reached the final checks with only the known rc.site
environment failure but were killed before printing totals.  The three blocks
added in 1.14.94--97 were run in isolation and pass.  The suite should be made
splittable (--from N, or per-tool) before it grows further.

## Snapshots are not the system  (1.14.96)

The find-based scan walked into /snapshots -- btrfs or rsync copies of the
whole tree, every install directory again, once per snapshot.  Fixing those
is pointless (a snapshot is read-only, or a record of the past) and
multiplies the scan by the snapshot count.  /snapshots and /.snapshots are
pruned by default; `--exclude DIR` (repeatable) prunes anything else;
`--no-default-excludes` puts them back for whoever really wants that.

## Every directory with group install  (1.14.95)

The user, now on the MAIN system -- older, in daily use, no manifests -- found
the sticky bits stripped from the install directories.  `fix-install
--sticky` fixed twenty-two, and the user rightly did not believe that was all:
"wherever the install group is set the dir needs the +w +t".

The scan asked forall_direntries_from, the C helper from the package-users
hint.  On a system that has been running for years that is an older build,
and an older build may stop at mount points or list by user rather than by
group.  The question is one find(1) invocation, so fix-install asks find --
`-type d -group install`, with /proc, /sys, /dev, /run and /tmp pruned -- and
says how many directories carry the group before saying how many are wrong.
Roots can be given to limit the scan.

Worth noting for the next session: the main system and the new system are
different generations of the same scheme, and the tools must work on both.
Anything that depends on a helper binary from the hint should fall back to
coreutils, because the helper's version is not under our control.

## The seat has to come from somewhere  (1.14.94)

Asked what to add or change for "a user in the right groups", I read what the
session script actually assumed: "elogind provides the seat".  Against the
stack's avoid list that assumption is false.  elogind registers a login
session only through pam_elogind, and Linux-PAM is avoided -- so a tty login
creates no logind session, libseat's logind backend finds no seat, and sway
exits before drawing anything.  seatd was installed, but blfs-bootscripts has
no script for it and no group existed for its socket.  The first launch would
have failed on the first line.

stacks/seatd-init.sh (a `cfg` step in services.stack) creates group `seat`
and installs an LFS-shaped boot script for seatd at S31, after dbus.
sway-session exports LIBSEAT_BACKEND=seatd so libseat does not try logind
first and fail with a puzzling message, and it refuses early -- naming the
usermod or the init script to run -- if the user is not in `seat` or seatd is
not up.  A launcher that dies on "Unable to create backend" tells the user
nothing; one that says "you are not in group seat" tells them everything.

The general point, and it is the same one as 1.14.75's four shapes of the
systemd mismatch: a comment that says how something works is a claim, and a
claim written before the avoid list was finalised can be quietly false.  The
session script's one-line assumption was never tested because nothing had
ever run it.

## Read every copy; prefer the one whose proof exists  (1.14.92)

"what am i doing wrong?"  Nothing.

The user's stack file is never overwritten (1.14.58), so a corrected
prog=/have= shipped in a newer release sits in sway.stack.new beside it -- and
verify's first-found rule meant the stale copy always won.  For three releases
I asked the user to hand-merge a metadata fix so that a REPORT would come out
right.  That is friction the tools created, and 1.14.91's "declared by ..."
suffix only described it better.

verify now reads every copy -- the user's, the shipped one, and any .new
beside them -- and takes the declaration whose proof is actually on disk.
Only when none is satisfied does it report the first, naming its file.  The
user's file is still never touched; it simply no longer has to be edited for
the tools to know what a package installed.

The lesson is about protections: "never overwrite the user's file" was right,
and it had a cost nobody paid attention to -- every fix to that file now
needs a human.  A protection that adds a manual step must come with a way for
the tools to see past it, or the step lands on the user every time.

## Say where the expectation came from  (1.14.91)

"are we caching something?  isnt it strange that we're missing that wlroots
dir?"  Neither.  verify reads /etc/pkgusr/stacks FIRST, and the user's
sway.stack still said have=/usr/include/wlr; the 1.14.90 fix was sitting in
sway.stack.new beside it, because a user's stack file is never overwritten
(1.14.58) -- a protection that, by design, makes a shipped fix wait for a
human to take it.

"missing: dir /usr/include/wlr" sent the user to look for a directory.  The
useful fact was WHICH FILE said to expect one.  The line now ends
"(declared by /etc/pkgusr/stacks/sway.stack)", which points at the thing to
edit rather than the thing to search for.

Two protections interacted here -- never overwrite the user's stack, and read
the user's stack first -- and the combination is right; it only needed the
report to name its source.  When a check reads configuration from more than
one place, its complaint should say which place it believed.

## The two that were left were real  (1.14.90)

After 1.14.89: 317 installed, 2 unvalidated -- and both were findings, which
is what the previous release promised.

    wlroots      missing: dir /usr/include/wlr
    minibrowser  its script names no verifiable target

wlroots 0.19 puts its headers under /usr/include/wlroots-0.19/, so the stack's
have= had been wrong for the version it pins since the day it was written; the
.pc file is the stable proof.  And from the user: "minibrowser is not called
like that -- the git is called Browser, the projects are browser-mini and
browser-big".  prog= now names browser-mini.  The ENTRY keeps its old name on
purpose: p_minibrowser is the account already on disk, and renaming the entry
would orphan it.

So the session's last verify is the first one whose two remaining lines were
both true, both specific, and both fixable in one line each.  That is what a
verification report is for.

STATE AT SESSION END: 319 packages, all validated once the user takes the two
stack lines.  sway, foot, seatd, elogind, dbus, fcron, acpid, iptables-nft,
wpa_supplicant all built and their boot scripts in rc3.d.  What remains is
not software: a kernel, fstab, a bootloader entry, a root password, and the
first login.

## A stack entry's own declaration wins over a stale record  (1.14.89)

The user asked, fairly, why verify had taken four rounds.  Three stacked bugs
in one column, fixed one at a time as the output revealed each -- and the
last residue was twelve packages whose install_last predates the fix that
carries have= into the script.  That file is not rewritten, so they would have
stayed "unvalidated" until each was next rebuilt.

The stack file itself still says what proves each entry installed.  verify
now reads every stack (installed and shipped, once per run) and, for an entry
it recognises, uses the stack's prog=/have= in place of whatever the old
record said.  A self-named program in a stale record is dropped in favour of
it; a package no stack knows is untouched.  No history rewritten, and git-entry
validation is permanently stronger: libsrtp is checked against its .pc file,
wlroots against /usr/include/wlr, dejavu-fonts against its font directory.

The 1.14.88 test used `libsrtp` as its fixture name and immediately failed,
because the real stack now knows libsrtp and correctly asked for a .pc file
the sandbox does not have.  Fixture names must not collide with real entries
when the code under test reads real configuration -- renamed to
`libstaledemo`.

VERIFY'S METHOD, stated once for the record, since it was questioned:
    1. account and home exist
    2. every path in pkg.lst is on disk          <- the strong check
    3. installed_* targets, from the book page, the script, or the stack
    4. validate_cmd, if the page has one
"installed" means 2 passed and 3/4 either passed or had nothing to say;
"unvalidated" means 2 passed and 3 named something absent -- which after this
release should be rare and real.

## A target that was never a real target  (1.14.88)

"may it be that its just cached?"  No, and the question was a fair one: the
count did not move after 1.14.87.

install_last is the record of the script AS IT LAST RAN.  Those twelve entries
were built before the fix, so their records still say
installed_program=<the entry's own name>, and they will until each is next
built.  Rewriting that file would be a lie about history -- it is the one file
that states what actually ran -- so verify has to cope instead: when the ONLY
thing missing is a program named exactly like the package, the script named no
real check, and it says so rather than claiming a perfectly installed library
is missing a binary that never existed.

A different absent program is still reported.  Two missing things are still
listed.  Both counter-cases are in the suite.

Also, for the record: the command I suggested for regenerating those scripts
-- `packagemanager install --regenerate-scripts` -- is not an option, and the
`2>/dev/null` I put after it hid argparse saying so.  1.14.80 added a test for
exactly this class one release earlier; it covers what the TOOLS print, not
what I type in a message, and there is no test for the latter.  The only
defence is to run a command before recommending it.

## Validate against what the entry says it installs  (1.14.87)

1.14.86 took the count from 299 to 307 installed, and twelve stayed
unvalidated: the libraries and the data packages.  `_stack_git_script`
defaulted `prog=` to the ENTRY'S OWN NAME, so verify hunted for programs
called `libsrtp`, `tllist`, `dejavu-fonts`.  None of those is a binary.

But every one of them carries `have=` -- the path the stack already uses to
decide whether the entry is done.  That is precisely the proof verify wants,
and it was being thrown away when the script was generated.  `prog=` no longer
defaults to the name, `have=` becomes the validation target, and the directory
check uses os.path.exists rather than isdir because a .pc file or a header is
the usual proof.

A test asserts that every git and tar entry in every shipped stack declares
one or the other: an entry that declares neither can never be confirmed, and
would sit in the unvalidated column forever without anyone knowing why.

Three releases (86, 87, and 85 before them) to make `verify` tell the truth
about twenty packages.  Each was small; what they had in common is that the
wrong output was ALREADY THERE, in every run, and had been read past for
weeks.

## Greedy, and the line has a comment on it  (1.14.86)

Every git and tar package, in every `verify` run, all session:

    sway   unvalidated   missing: program ), program #, program e.g.,
                         program ('gst-launch-1.0 ...

The stack's generated scripts document their own metadata:

    installed_programs=()      # e.g. ('gst-launch-1.0' 'gst-inspect-1.0')
    installed_program="sway"   # e.g. "ffmpeg"  (checked on PATH)

and `_parse_bash_vars` matched `\((.*)\)` -- greedy, from the first "(" to
the LAST ")", which is inside the comment.  The quoted scalars did the same.
Twenty packages could not be validated because of two greedy regexes, and the
nonsense they produced was visible in every run I read this session without my
chasing it.

Non-greedy, with a trailing comment allowed and ignored.  sway now validates
by checking `sway` on PATH, which is what its metadata said all along.

Worth naming: this was in plain sight for eighty releases.  It looked like
noise -- an odd line in a column of odd lines -- and noise gets read past.  A
report with a persistently ugly corner trains its reader to skip that corner.

## The account name, not the package name  (1.14.85)

    $ packagemanager reload-pkg-list mpv
    mpv: pkg.lst regeneration started (disowned background task).
    $ pgrep packagemanager          # nothing
    -rw-r--r-- 1 root root 0 pkg.lst.new

"mpv" went straight through.  `pkgusr_home()` accepts either name so the home
resolved -- but `_can_su("mpv")` did not, because the account is p_mpv, so it
took the ROOT branch and ran `list_package mpv`, which found no such user,
produced nothing, and left an empty root-owned pkg.lst.new.  `write_pkg_list`
normalises with pkgusr_name() now, as every other entry point does.

The second half is worse than the first: the command printed "regeneration
started" for a task that had already died.  It is asked for by a person, so it
runs in the FOREGROUND by default and reports the result -- "1234 file(s)
recorded", or "no files found -- it owns nothing on disk", which is the answer
the user was actually looking for.  --background keeps the old behaviour.

A message that reports an INTENTION rather than an OUTCOME cannot be wrong,
which is exactly what makes it useless.  This is the same shape as 1.14.64's
zero exit over a failed log: both said the encouraging thing without checking.

## Highlight the words the answer depends on  (1.14.84)

The collector-group prompt is eight lines of prose containing two names, and
the names are the only thing the reader chooses between.  C_B -- bold, added
long ago with the comment "for the words in a question that the ANSWER depends
on" -- was never applied to them.  It is now, and C_B is cleared for a
non-terminal like every other colour, which it had also been missing.

Small, and worth doing because this prompt appears many times in one stack
run: services.stack alone asked it for /lib/services, and every package that
installs beside another asks it again.

## Fix them together, not one round each  (1.14.83)

fcron reports ONE file at a time.  /etc/fcron.conf must be owned by
root:fcron; fixed, re-run, and it said /etc/fcron.allow: Permission denied;
/etc/fcron.deny would have been the third round.  Each round is a full
configure phase and a fresh reading of the same failure.

The package creates a system group for itself -- it says so in its own script
-- and every config file it installed under /etc wants root:<that group>.  The
box takes the file list from the MANIFEST rather than from the log, skips the
ones already correct, and prints one command covering the rest:

    chown root:fcron /etc/fcron.allow /etc/fcron.conf /etc/fcron.deny
    chmod 640 ...
    It reports ONE file at a time, so fix them together or you will be back
    here for the next one.

The general lesson, and it applies well beyond fcron: when a program validates
its environment one item at a time, a diagnosis that only repeats what the
program said inherits its pace.  The tools know the whole set -- that is what
the manifest is for -- and should say all of it at once.

Also visible in this run: 1.14.64's swallowed-failure check fired for real.
The phase exited 0 while its log carried "Permission denied", and the run was
correctly turned into a failure instead of reporting fcron as configured.

## Write down what was refused  (1.14.82)

fcron's configure, running as root, failed with

    ERROR could not change egid to 22: Operation not permitted

As ROOT.  That makes no sense until you know `fcrontab` is installed setgid
`fcron`, and the chmod wrapper refused that bit at install time -- correctly,
a package user must not set setuid/setgid -- and then never mentioned it
again.

The refusal is recorded now, in the package's home, and reported after the
phase by root, who is the only one who can act on it:

    This package asked for setuid/setgid bits, which a package user cannot
    set... Apply as root, if you want the package to work as upstream intends:
        chmod 2755 /usr/bin/fcrontab

The file is cleared once reported, so later builds do not repeat requests that
have been dealt with.

The principle, which is the third form of the same thing this evening
(1.14.78 accounts, 1.14.81 ownership, now set-id bits): a package-user system
refuses certain operations by design, and every refusal it makes silently
becomes a mystery hours later in a different phase.  Refusing is right;
refusing WITHOUT A RECORD is what cost the time.

## A package that checks its own file ownership  (1.14.81)

fcron's configure, now running as root, got further and stopped on

    ERROR Conf file (/etc/fcron.conf) must be owned by root:fcron
    ERROR Could not chdir to /var/spool/fcron: Permission denied

A package-user install cannot satisfy that.  Everything it writes belongs to
p_fcron, and the chown wrapper skips the package's own chown deliberately --
that skipping IS the model.  For a daemon that validates ownership before it
will start, the last step belongs to root.

Not a bug in the model, and not something to work around: replaying the
skipped chowns wholesale would hand half of /usr/share/doc to root and break
the per-user tracking that the whole design rests on.  What was missing is the
telling.  The box reads the package's own words and prints the two commands
they imply:

    chown root:fcron /etc/fcron.conf
    chown -R fcron:fcron /var/spool/fcron

A worthwhile distinction for the next session: a package-user system can own
FILES but not IDENTITY.  Anything a daemon checks about itself -- who owns its
config, which account its spool belongs to -- is outside what the model can
provide, and the honest answer is a named root command, not a cleverer
wrapper.

## The commands we print must be commands  (1.14.80)

    $ lfs-helper build fcron --phase configure --force --as-root
    !! unknown option: --as-root

1.14.79 printed that advice one release earlier, confidently, having checked
that `--as-root` existed -- on cmd_run_script, one function away.  cmd_build
never took it.  And once it did, `local as_root=0` further down cmd_build
shadowed the flag, so it parsed cleanly and did nothing: two ways to be wrong
about a single word.

Both fixed.  But the fix that matters is the test: every long option the
failure report prints after "lfs-helper build" must appear in cmd_build's
option parser.  It reads both out of the source and compares them, so the next
suggested flag that does not exist fails the suite instead of the user's
evening.

This is the sixth time this session that a message named something that was
not there -- a path, a package, a directory, a command, a flag.  The pattern
is always the same: the message was written from what the author believed, and
nothing checked it against the code.  Where the thing named is machine-
checkable -- and a flag, a path and a package name all are -- the check is
cheap and belongs in the suite.

## A configuration step that needs root  (1.14.79)

1.14.78 worked: fcron's system account was created, the build finished, 74
files installed.  Then the configure phase:

    must be privileged to use -u

from `fcrontab -u systab`.  BLFS's "Configuring" sections are written for the
root user -- they are system configuration, not part of installing a package
-- and no directory grant can help, because the command refuses to run
unprivileged whatever it can write.

`--as-root` has existed all along for exactly this.  The box now recognises a
privilege error IN THE CONFIGURE PHASE and prints

    lfs-helper build fcron --phase configure --force --as-root

It does not fire for a build failure with the same words; that counter-case is
in the suite.

Left open deliberately: whether the configure phase should simply RUN as root.
The book says root for every "Configuring" section, so it is arguably correct
-- but files it creates would then be root-owned rather than the package's,
and the tracking assumes otherwise.  That is a design change to make
deliberately at the start of a session, not at the end of one.

## A service account is root's job  (1.14.78)

fcron compiled completely and then died in its install:

    groupadd: cannot lock /etc/group; try again later
    Group "fcron" does not exist : please create it

Its page's own commands are `groupadd -g 22 fcron && useradd ... fcron`, and
the install phase runs as p_fcron, which cannot write /etc/group.  Every page
needing a system account -- fcron, avahi, sshd, postfix -- is in this
position, and the package-user model has no answer to it: the account is
system state, not a file the package owns.

cmd_build now reads those lines out of the script and runs them as ROOT before
the phase, skipping any account that already exists.  The book's commands stay
in the script, where a reader expects them, and `groupadd`/`useradd` wrappers
turn the package user's own attempt into a no-op when the account is there --
and, when it is not, say plainly that a package user cannot create one.

Parsing note: the account NAME is the LAST argument.  Stripping "-x value"
pairs by hand tripped over the quoted comment in
`useradd -c "Fcron User"` and produced the name `User" fcron`.

## Boot scripts are a package too  (1.14.77)

"why dont i have an fcron startup script -- did we miss it during the lfs
install?"  No: /etc/init.d holds LFS's own scripts and nothing else, and every
BLFS service script lives in blfs-bootscripts, a separate tarball that is not
a BLFS package.  That is precisely why a package page's `make
install-<service>` is commented out by the generator (1.14.20) -- the target
is in that tarball, not in the package being built.

stacks/services.stack: acpid and fcron (the cron daemon make-ca's weekly
update needs), then blfs-bootscripts 20250225 -- the FINAL SysV release --
installing only the scripts for services this system has: dbus, alsa,
bluetooth, acpid, fcron, iptables, random, service-wpa.  The packages come
first; `have=/etc/rc.d/init.d/dbus` keeps it idempotent.

And the parser change that made it readable: a stack entry may now CONTINUE
across lines with a trailing backslash.  Every entry had to be one line, which
is why sway.stack's are 300 characters wide and nobody can see the build=
command inside them.  A dangling backslash at end of file is an error, not a
silent drop, and the line number reported for a bad entry is still the line it
started on.

Note what the user found by reading `ls /etc/init.d`: dbus has no boot script
either.  On a system whose desktop, seat manager and half its packages talk
over dbus, that would have been a puzzling first boot.

## The pattern has to be a real path  (1.14.76)

The network stack finished -- six of six -- and signed off with

    results: packagemanager errors     logs: /usr/src/p_<pkg>/log

The hint was assembled by hand, `os.path.join(BASE_DIR,
pkgusr_name('<pkg>'), 'log')`, and was wrong twice over: the placeholder is
never filled in, and the path omits the `pkgusr/` component every package home
has.  Anyone following it found nothing -- and until 1.14.71 the logs were not
in the right directory either, so the message was doubly useless.

`_pkg_log_dir` is the function that knows.  Both summary lines use it now, and
a test asserts the placeholder form differs from a real package's path only in
the name.

Third message this session that named a location which did not exist (1.14.71
the logs, 1.14.43 the package, here the directory).  When a message contains a
path, it should come from the code that builds that path, never from a format
string that happens to look like it.

## A systemd unit on a system with no systemd  (1.14.75)

wpa_supplicant installed its binaries and its man pages and then died on

    install: target '/usr/lib/systemd/system/': No such file or directory

The systemd book's page ends by installing a unit file, and on a SysV system
that directory does not exist.  Exactly the situation the systemctl shim was
written for -- the book assumes an init this machine does not run -- but a
unit file arrives as a file copy, not a systemctl call, so the shim never saw
it.

The install WRAPPER is the right place: a destination under /usr/lib/systemd
or /lib/systemd, on a machine with neither the directory nor systemctl, is a
visible skip and a success.  Creating the directory instead would have worked
and left a unit nothing will ever read.

A host that does run systemd still installs its units -- that counter-case is
in the suite beside the SysV one.

The pattern to remember for the next session: the systemd/SysV mismatch shows
up in four different shapes now -- systemctl calls (shimmed), configure flags
(1.14.51's survey), unit-directory installs (here), and journald headers
(1.14.60).  Each needed its own catch, in the layer where it appears.

## An --enable must beat the book's --disable  (1.14.74)

The user pasted netfilter.org's own project page, whose news column lists
**libnftnl 1.3.2** (2026-08-31) as current.  That is the project stating its
version, not a guess, so network.stack now carries the tar entry -- placed
above iptables, with a line saying where the version came from and to check
the .sha256 before trusting it.

Then the flag that makes it matter did nothing.  The book configures
`--disable-nftables`; `configure_args` PREPENDED `--enable-nftables`:

    ./configure --enable-nftables --prefix=/usr \
                --disable-nftables ...

and autoconf takes the LAST occurrence.  Same class as 1.14.60 -- an option
that reaches the command and is then ignored is worse than one that never
arrives, because the file says it is set.

configure_args now removes the opposite form of each flag it adds
(enable/disable, with/without).  Line by line: deleting just the token left

    ./configure --enable-nftables --prefix=/usr      \ \

a backslash-escaped space, which is an argument.  An unrelated
`--disable-static` is untouched, and the result is checked with `bash -n`.

The shipped stacks/machine.conf carries the [iptables] section; a user's own
copy is never overwritten (1.14.58), so it arrives as machine.conf.new.

## The nft path, written down but not guessed  (1.14.73)

The user wants iptables-nft (legacy is on its way out) and does not want iw.
iw is gone from network.stack; the nft path is documented rather than shipped,
because libnftnl is not a BLFS package and no mirror of it is reachable from
here to check a version against.

The template in the stack file gives the exact `tar` entry shape, says it must
go ABOVE iptables (order in the file is build order), gives the machine.conf
flag, and says plainly what `--check-refs` does NOT cover: it asks git
remotes, so a wrong tarball version fails at fetch time rather than before the
build.

Writing down what cannot be verified, marked as unverified, is the honest
middle between guessing a version and leaving the user with nothing.  Three
bad pins this session (usrsctp, foot, needs=pcre2) all came from filling in a
value that looked right.

Still missing for a bootable system, for the next session: a kernel with the
right DRM driver and evdev, a bootloader entry, /etc/fstab, a root password,
and the make-ca cron job that 1.14.51's survey turned up.

## A network stack, and every entry checked  (1.14.72)

"is it possible that we miss wpa_supplicant?"  Yes.  The sway stack builds a
desktop; nothing in it brings up a network, and the user's own wifi script
needs wpa_cli, wpa_supplicant and ifup -- none of which existed.

stacks/network.stack: libnl, wpa_supplicant, iw, wireless_tools, libmnl,
iptables, net-tools.  Every one verified against the book before shipping.

What it deliberately does NOT ship: an iptables-nft path.  The book's iptables
page configures `--disable-nftables`, and the nft backend needs libnftnl,
which BLFS does not carry.  No mirror of it was reachable from here, so
rather than guess a version -- the exact mistake of `needs=pcre2` (1.14.66)
and the two rotted refs -- the stack carries a comment saying what to add and
warning not to take a version on trust.

And the check that generalises it: EVERY book entry in EVERY shipped stack
must name a package the book has, `needs=` included.  That test immediately
found `elogind` in sway.stack -- which turned out to be legitimate, a `book`
entry carrying url= as a git fallback, because the systemd book has no
elogind page.  So the rule is: an entry with no fallback must resolve.  A new
check earning its keep by finding something, and then being narrowed by what
it found, is the good case.

## The log belongs beside the package  (1.14.71)

"shouldnt we log everything within the pkgusers home log dir?"

Every failure box already claims we do -- it ends with "logs:
/usr/src/pkgusr/p_<name>/log" -- and for a modern script that directory held
one empty .diff.  The phase log went to the central $LOGS/<name>-<phase>.log
and nowhere else, and that copy is overwritten by the next run of the same
package.  The history someone wants three days later was never kept where they
were told to look.  (The OLD-style path did write into the home; the
dispatcher path, which is everything now, did not.)

run_phase_as copies the log into the owner's home, timestamped so runs
accumulate, owned by the package user, keeping the last ten -- a webkitgtk log
is megabytes and a package that fails twenty times should not fill the disk.

A message that names a location is a promise about that location.  This one
had been wrong since the 1.14.0 refactor moved every install onto the
dispatcher path.

## Retry the phase that failed, not the whole build  (1.14.70)

"is it possible that if we fail the install part we recompile everything?"
Yes, and it had been doing so all along.

foot needed seven rounds to collect its directory grants -- /etc/xdg, then
/usr/share/zsh/site-functions, then /usr/share/fish/vendor_completions.d,
because meson reports one unwritable path at a time -- and EVERY round
re-cloned the repository, re-ran meson and recompiled all 150 targets, to redo
an install that had failed on one completion file.  The grant-and-retry loop
passed `$phase`, which was `all`.

Granting a directory cannot invalidate a compile.  When an `all` run fails in
install or configure, the retry runs THAT phase; the sources and build tree
are untouched, which is precisely why a grant was all that was missing.  An
early-phase failure still retries everything, and a retried install is still
followed by the configure step that `all` owes.

The first version grepped the log inside cmd_build for the failed phase --
and an existing test refused it: "cmd_build still infers finished phases from
the log itself", from the release that moved phase bookkeeping into
run_phase_as.  The rule was right and the fix was better for obeying it:
run_phase_as already computes that value, and now publishes it as
LAST_FAILED_PHASE.  A test that pushes back on a new change for an old reason
is doing its job.

## An entry with no ref still has a url  (1.14.69)

The stack came back clean -- every pinned ref verified.  And four entries had
not been contacted at all: the ones tracking a default branch, reported as
"no ref= (tracks the default branch)" and skipped.

"No ref to check" is not "nothing to check".  A repository that has been
renamed, made private or moved fails exactly like a bad ref -- at clone time,
after everything before it has built.  Those entries are asked for their
branches now: reachable, unreachable (counted, so the summary cannot claim an
all-clear), or present-but-empty, which is what a moved repository looks like.

Also: the four local sway tools in sway.stack pointed at
github.com/nimbin2/..., which is not where they live.  They now point at
git.christianimmanuel.de, the URLs their author gave.  A stack that ships with
someone else's URL for your own software is a pin that was never right, not
one that rotted.

## Sort tags as versions  (1.14.68)

--check-refs did its job on the real stack: twelve pins verified, one bad.
And then suggested the wrong replacement:

    foot   1.24.1 DOES NOT EXIST
           remote has: 1.9.2, 1.9.1, 1.9.0, 1.9, 1.8.2

foot's newest tag is 1.28.0.  Those five are what a reverse STRING sort
produces, because "9" > "2" one character at a time.  A suggestion that names
an ancient release as the newest is worse than no suggestion: it invites a
downgrade, and the person has no reason to doubt it.

Tags are compared component by component now, numbers as numbers, with a
leading "v" ignored and non-numeric parts (release-3.2.4) sorted after.  The
summary also reads "1 entry pins" rather than "1 entry pin".

Both faults were in output I had just written and read twice.  The test that
catches it uses foot's actual tag list -- a fixture taken from the failure is
worth more than an invented one, because it encodes what really happened.

## Check every pinned ref at once  (1.14.67)

Second rotted pin in the same stack.  usrsctp was 1.14.44; now foot:

    error: pathspec '1.24.1' did not match any file(s) known to git

whose tags are 1.24.0 and 1.28.0 -- 1.24.1 never existed.  The 1.14.44
diagnosis worked perfectly and listed the real tags, which is the right answer
to the wrong question: each rotted pin still costs a clone, a build attempt
and a round trip to discover.

1.14.44's note said `--check-refs` would turn this into a five-second report.
`packagemanager stack <name> --check-refs` asks every git remote whether its
ref still exists and builds nothing.  Commit ids are reported as unchecked
(cheap verification is not possible), an entry with no ref= as tracking the
default branch.

The detail that took a second pass: an unreachable remote must not be counted
as verified.  "every pinned ref exists" over seven unreachable remotes is a
false all-clear, and the ones that could not be asked are exactly the ones
that might be wrong.  It now says "every ref that COULD be checked exists" and
counts the rest.

sway.stack's foot pin is corrected to 1.28.0.

## A git entry can name its dependencies  (1.14.66)

sway is built from git, so nothing in the book orders anything before it:

    ERROR: Dependency "json-c" not found, tried pkgconfig and cmake

json-c IS a BLFS package (JSON-C-0.18).  It had simply never been built,
because a git stack entry had no way to say it needed one: book entries get
their dependencies from the book, git entries got nothing at all.  Every git
package in the stack is in this position, and the failures arrive one
dependency at a time, at configure, after the clone.

`needs=` on a git or tar entry names book packages to install first -- through
the same door as everything else (1.14.13), skipped when already installed,
and stopping the stack if one cannot be built.  sway.stack now declares
`needs=json-c,cairo,pango`.

A test asserts that every name in every `needs=` in the shipped stack is a
package the book actually has.  The first draft said `pcre2`, which is LFS and
not BLFS, so the install it triggered could never have worked -- a declaration
that names something unbuildable is worse than none, because it fails later
and further from the cause.

Remaining for a future session: the other git entries (swaybg, wlroots,
libnice, ...) have no needs= yet, and their dependencies are only discoverable
by building them.  Each failure of this kind should end with a line added to
the stack, not just a package installed by hand.

## A warning that is only fatal because of -Werror  (1.14.65)

wlroots 0.19 against libinput 1.31:

    error: enumeration value 'LIBINPUT_SWITCH_KEYPAD_SLIDE' not handled in
           switch [-Werror=switch]
    cc1: all warnings being treated as errors

Nothing is wrong with wlroots.  A dependency grew a new enum value since that
version was written, and -Werror makes the warning fatal.  The box called it
"a COMPILE error in the package's own source ... the tools cannot repair it"
and offered `c_args = -DSOMETHING`, which is no help.

Version skew like this is the NORMAL state of a rolling book against pinned
git sources, and the cure is always the same flag.  The box names it, and
carries the warning class through so the narrow flag is possible too:

    [wlroots]
    werror = false                 # meson
    c_args = -Wno-switch           # cmake or autotools

An ordinary compile error keeps the old advice and nothing more; that
counter-case is in the suite.

Flaky test noted: "a busy tree hangs the build instead of warning" spawns a
`sleep` and greps for it, and fails perhaps one run in four.  It should use a
marker only it can see rather than racing the process table.

## A zero exit is not proof that nothing failed  (1.14.64)

Rebuilding alsa-lib to fix the missing libasound, the install ended with

    install: cannot create regular file '/usr/include/sys/asoundlib.h':
             Permission denied
    make[4]: *** [Makefile:786: install-data-hook] Error 1
    make: *** [Makefile:408: install-recursive] Error 1

and the run reported "# alsa-lib: done.  1 package(s) installed."

THIS IS THE ORIGIN OF THE WHOLE CLASS.  Every "recorded installed but is not"
in this session -- pathspec, cargo-c, Whois, the pip modules, alsa-lib's own
missing library -- is a package whose install did not finish while something
said it had.  The runner itself is correct (a phase stops at the first failing
command; asserted), so the status was swallowed somewhere else: an older
script format, a trailing command that succeeded, a wrapper that returned 0.

Rather than chase which, the LOG is now checked whenever a phase exits 0.  A
line matching `make: *** ... Error N`, `ninja: *** build stopped`, `install:
cannot create`, or a trailing `Permission denied` turns the phase into a
failure, with the offending line quoted.  A package that could not write its
files is not installed, whatever the exit status said.

The false-positive cases are in the suite too ("checking for Permission denied
handling... yes", "Error handling tests: 12 passed"), because a check this
blunt earns its place only by not firing on prose.

Note the shape: the permission failure would have been REPAIRED by the
grant-and-retry if the phase had failed properly.  A swallowed status does not
just mislead, it disables the machinery built to fix exactly that fault.

## Ask the manifests about a library too  (1.14.63)

The three-way diagnosis landed on the user's real case -- "Nothing here
provides libasound at all" -- and stopped one step short.  p_alsa-lib had a
1711-byte pkg.lst while /usr/lib had no libasound of any kind: SOMEBODY
recorded installing it, and that package is the one to rebuild.

The library branch now does what 1.14.33 does for a missing program: greps the
manifests, names the package whose record claims the file, and offers

    packagemanager install alsa-lib --run --reinstall

Two diagnoses written a fortnight of versions apart, for the same underlying
fault -- a record that outlived the files.  The manifests are the one place
that knows, and every "X is missing" message should ask them.

Also worth recording, because it cost ten minutes of hunting: three suite
checks failed with no visible FAIL line, and the cause was the packaging step
(`rm -f *.html`) having removed the book symlinks before the run.  The checks
that need a book should say so rather than failing silently -- the same "an
environment failure must look like one" problem as the rc.site check that has
sat at the bottom of every run this session.

## A library that will not link  (1.14.62)

alsa-utils found alsa-lib's headers and then:

    checking for snd_ctl_open in -lasound... no
    configure: error: No linkable libasound was found.

Headers present but the library unlinkable is a different fault from a
missing package, and none of the existing diagnoses covered it -- the box said
nothing at all.  Three ways it happens, told apart by what is on disk:

    libfoo.so AND libfoo.so.N   -> it should link; stale ldconfig cache, or
                                   the real error is further up in config.log
    libfoo.so.N only            -> the DEVELOPMENT symlink is missing: the
                                   library exists at run time and not at build
                                   time, so its owner installed incompletely
    neither                     -> nothing provides it

The middle case is the one worth naming: a package-user install that missed
the .so symlink leaves a system where everything RUNS and nothing BUILDS, and
the error blames the package that is merely the first to notice.

Both wordings are read -- configure's "No linkable libX was found" and the
linker's own "cannot find -lX".

## A skipped variant does not keep its install step  (1.14.61)

"is it possible that the install of webkitgtk is repeating itself at the end?
i think im building it the second time!"  Its install phase held

    ninja -j8 install
    ## OPTIONAL, skipped -- ... the GTK-4 version ...
    # <the whole GTK-4 build, commented>
    ninja -j8 install          <- the GTK-4 variant's install, still live

1.14.53 enables one of a page's alternative BUILD blocks; each variant also
has its own install step, and the skipped one's stayed.  The repeat is a no-op
rather than a second build -- but on a package that takes hours, nobody
watching can tell that, and the question is the right one to ask.

The first attempt at the rule commented ANY repeat after a skipped block, and
dropped GLib's last `ninja install` -- the one that installs the reconfigured
build with introspection enabled, several live commands later.  The rule is
now exactly "X ; <skipped variant> ; X": a repeat is only redundant when
nothing happened in between.  One page in the book matches (WebKitGTK), and
GLib's counter-case is in the suite beside it.

Whole-book invariants held throughout: 954 scripts, 0 syntax problems, 0 empty
install phases.  Those two numbers have caught or confirmed every filter
change in this session; keeping them cheap has been worth more than any
individual fix.

## Put the option on the command, not in the prose  (1.14.60)

WebKitGTK died on

    fatal error: systemd/sd-journal.h: No such file or directory

with `ENABLE_JOURNALD_LOG = OFF` sitting in machine.conf.  The generated
script showed why:

    ## NOTE: ... add the -D CMAKE_CXX_FLAGS_RELEASE=... option to the cmake
    -Denable_journald_log=OFF -Duse_gstreamer_webrtc=ON to disable some ...

Two bugs in that one line.

The options were inserted at the first line CONTAINING the word "cmake" --
which on that page is a NOTE, prose, three paragraphs before the command --
so nothing reached the build.  Insertion now skips comment lines.

And they were lower-cased: configparser folds keys, and CMAKE VARIABLES ARE
CASE-SENSITIVE.  Even correctly placed, `-Denable_journald_log=OFF` sets a
variable nothing reads, and cmake accepts unknown -D silently.  `optionxform
= str` keeps the case.  meson's options are lower-case anyway, which is why
[mesa] worked for months and hid both.

Same shape as 1.14.23, 1.14.41, 1.14.51, 1.14.56: text that mentions a command
is not that command.  Four filters and now an INJECTOR have made it.  Anything
in these tools that scans generated script text should skip comments unless it
has a specific reason not to -- that rule is cheap and would have prevented
all five.

## ninja does not read MAKEFLAGS  (1.14.59)

WebKitGTK's page says it outright: some of its source files need more than
4 GiB of RAM each, so pass `-j<N>` to ninja with N = RAM / 4 GiB, or the OOM
killer takes the build.

MAKEFLAGS cannot express that -- ninja ignores it and uses nproc+2 -- so
following the book meant editing the generated script by hand, and the failure
it prevents arrives hours in as a killed compiler.  machine.conf takes a
`jobs` key now, which rewrites bare `ninja` invocations to `ninja -jN` (a line
that already has -j is left alone, and re-applying does not stack flags).

Also confirmed while answering the user's question about GTK-3 vs GTK-4: the
page's two build variants "differ only in the setting of -D USE_GTK4" (its
own words), and `apply_machine_opts` REPLACES an option the book sets rather
than appending -- so `USE_GTK4 = ON` in machine.conf turns the enabled GTK-3
block into the GTK-4 build, without touching which block 1.14.53 enabled.
That is the mechanism working as intended across three separate features.

## A stack file is the user's  (1.14.58)

Found while answering a question about WebKitGTK's feature list: `make
install` copies stacks/* over /etc/pkgusr/stacks/* UNCONDITIONALLY.

The user had just removed `avoid ruby` from sway.stack to get webkitgtk to
build.  Every fix in this session begins with `make install`.  The next one
would have put `avoid ruby` back, the build would have failed the same way,
and nothing would have said why.  machine.conf lives in the same directory --
that is where the per-package build options go, and it was equally at risk.

Missing file: installed.  Identical: reported as unchanged.  Different: the
user's is KEPT and the shipped one saved as `.new` beside it.  The skel
handling a few lines further down has done this since it was written; the
stacks loop simply never did.

A file the tool tells people to edit cannot be a file the tool overwrites.
Worth a sweep for others: anything under /etc that `make install` writes.

## One place to set the job count  (1.14.57)

Asked where -j is set.  Four places:

    lfs config makeflags        -> <tree>/usr/src/lfs-pkgusr/config/env,
                                   exported by every chroot shell
    /etc/pkgusr/build.env       -> the per-machine file, via build_env_pairs
    lfs-helper build --jobs N   -> one build
    lfs-phases                  -> -j$(nproc), only if nothing else set it

And they did not agree.  build.env is added to the command FIRST and the
caller's MAKEFLAGS after it; the last assignment on an `env` line wins.  So an
ambient -j16, inherited from the chroot's config env, silently beat a -j13 put
in the file that exists for exactly this.

Precedence is now --jobs, then build.env, then the ambient value: the caller's
MAKEFLAGS is only passed when nothing has already set one.

For the record, the fix a user wants is one line in /etc/pkgusr/build.env
(`packagemanager env --set MAKEFLAGS=-j13`), which now actually takes effect;
`lfs config makeflags` remains the setting for the chapters 5-8 build, where
there are no package users and no build.env yet.

## A demonstration is not an installation step  (1.14.56)

enchant installed perfectly -- 17 files tracked, enchant-2.pc in place -- and
then the configure phase failed:

    No dictionary available for 'en_GB'

Its page ends with "You can test your installation and configuration by
creating a test file and running the following commands", and the generator
turned that demonstration into a step.  It needs an aspell dictionary the
system may not have, and running it is nobody's idea of installing enchant.
Blocks introduced by "you can test / verify / try" are commented, with the
book's text kept.  Two pages in the book: enchant and autofs.

The failure box got it wrong twice over.  It reported

    'not' is not installed -- the build needs it
      find what provides it:  packagemanager search not

from a line in enchant's own configure:

    ./configure: line 26491: not: command not found

which is a broken autoconf probe, harmless, and fifty lines above the real
failure.  Shell keywords and a few English words are skipped now, and the next
candidate is taken -- so a log with both `not` and `cmake` reports cmake, and
a log with only noise reports nothing.

Both halves of this are the same mistake in different places: text that LOOKS
like a command (a book's example, a shell diagnostic) treated as one.  The
tools read prose all day; every reader of it needs to know what it is reading.

## cmake takes -D options too  (1.14.55)

WebKitGTK, next configure error: "Enchant is needed for ENABLE_SPELLCHECK".
enchant is in the user's avoid list and webkitgtk only RECOMMENDS it, so
1.14.54's check correctly stayed quiet -- a recommended package being absent
is what an avoid list is FOR.  The natural fix is to turn the feature off, and
that had nowhere to live:

    machine.conf has [webkitgtk] but the script has no `meson setup` line
    -- options NOT applied

webkitgtk is a cmake package.  `apply_machine_opts` only knew `meson setup`,
so for every cmake page in the book the file was inert -- which also explains
the [vulkan-loader] and [libass] warnings the user had been seeing for days
and reasonably ignoring.

Both build systems take -Dkey=value; only the command word differs, and
autotools already had configure_args.  An option the BOOK sets is replaced
rather than duplicated (cmake takes the last, so a duplicate would have been a
silent no-op), and re-applying changes nothing.

The diagnosis chain that got here is worth noting as a whole: the box named
the module (enchant-2), traced it to the package (enchant), said it was not
installed, and offered the install -- 1.14.43's work, doing exactly its job on
a failure nobody had in mind when it was written.

## An ignored package that something REQUIRES  (1.14.54)

WebKitGTK configured for an hour and stopped at

    CMake Error: Ruby 2.5 or higher is required.

webkitgtk REQUIRES Ruby-4.0.1.  The stack's avoid list contains `ruby`.  So
the plan omitted a hard requirement of a package the user had asked for, and
said nothing about it.

Not walking into an avoided branch is right and stays.  What was missing is
the report: `walk_deps` records (parent, ignored) whenever the edge it skips
is REQUIRED, `blfs order --anchors` emits `#ignored-required`, and the plan
warns before building:

    1 package(s) in this plan REQUIRE something the ignore list excludes:
      webkitgtk            requires ruby, which is ignored
      Either drop it from the ignore list, or install it:
        packagemanager install ruby --run --recursive

Only REQUIRED edges are reported; ignoring a merely recommended package is the
normal use of an avoid list.

A note on the test for this: the first version asserted that ignoring
bubblewrap (which webkitgtk only recommends) reports nothing -- and it failed,
because glycin in the same tree REQUIRES bubblewrap.  The code was right and
the test's premise was wrong.  When a new test fails, the first question is
which of the two is mistaken.

## A page that offers a choice must still build  (1.14.53)

WebKitGTK unpacked, and then

    ninja: error: loading 'build.ninja': No such file or directory

Its page gives TWO complete builds -- "If you want to install the GTK-3
version of WebKitGTK, run the following commands", and the same for GTK-4.
Each is introduced by a conditional, so `_conditional_guard` commented BOTH,
the build phase came out as `:`, and the install phase ran `ninja install`
against a directory with nothing in it.

Guarding a conditional block is right; guarding EVERY block is a package that
cannot be built.  When a build phase has no live command left but a skipped
block exists, the first is restored, with a line saying which variant was
chosen and that the others are still there to switch to.  Five pages in the
book are in this shape: WebKitGTK, okular, Vim, docbook-dsssl, Py3c -- all of
which previously built nothing.  954 scripts still parse.

Third failure this session from the same root (gegl 1.14.39, Whois 1.14.41):
a filter that comments commands was right about the line and wrong about the
phase.  The invariant that catches all of them is already in the suite -- no
generated script may have an empty install phase -- and it should be extended
to the BUILD phase too, with the handful of legitimately-empty pages listed
by name rather than counted.

## A fallback must not take you back a release  (1.14.52)

The user is building 13.0.  They fetched the 12.4 book as a REFERENCE for
SysV commands -- and the next build produced **BlueZ-5.83**, which is 12.4's
version.  Fetching a book to read from silently changed the book they build
from.

The configured default is `stable-sysv`, which no longer exists, so
`_best_cached_for` scored the cached books: init flavour is worth 4, an exact
selector match 8, version nothing at all.  The 12.4 sysv book matched the
flavour and won, and the 13.0 book it passed over was never mentioned.

Flavour still decides -- that is what the selector asks for -- but among books
of the same flavour the newest now wins, and the note names what it passed
over:

    note: no book matched 'stable-sysv'; using the cached BLFS-BOOK-12.4...
          a NEWER book is also cached: BLFS-BOOK-13.0-systemd... (13.0)
          building from 12.4.  To pin the other one:
              blfs set-default 13.0-systemd

Also here: `make install-<name>` in a CONFIGURATION section is the SysV books'
boot-script idiom, and the target lives in blfs-bootscripts, not in the
package.  BlueZ installed everything correctly and then died on

    make: *** No rule to make target 'install-bluetooth'.  Stop.

It is commented with the real instructions now.  automake's own
install-strip/-data/-exec/-man are left alone.

The lesson for the session: on 13.x the SysV book is a REFERENCE, never the
build source.  Build from 13.0-systemd and carry the init differences as
per-package overrides -- which is what diff-init exists to find.

## Judge the difference on lines that run  (1.14.51)

The narrowed survey named eight pages on the user's system.  Four were
nothing: gcc differed only in a NOTE whose URL contains "13.0-systemd",
libxml2 in a NOTE saying "systemctl stop httpd.service", rust in a NOTE about
the "systemd journal".  Prose, all of it -- 1.14.23's lesson in a different
filter.  Comments are stripped before the difference is judged now, and the
three real ones (bluez, dbus, make-ca) still come through.

What the eight actually were, for the record -- this is the SysV work a 13.x
system needs, and it is small:

    bluez         --disable-systemd is gone from 13.0's configure     REAL
    dbus          -D systemd=disabled is gone from 13.0's meson       REAL
    make-ca       12.4 writes /etc/cron.weekly/update-pki.sh;
                  13.0 does `systemctl enable update-pki.timer`       REAL
    at-spi2-core  12.4 redirects systemd_user_dir to /tmp and
                  deletes the .service afterwards                     cosmetic
    gcc, libxml2, rust                                                prose
    llvm          13.0 runs its TESTS via systemd-run --user; the
                  systemd shims turned that into a visible skip       handled

That last one is worth noting: the shims added for exactly this (a systemd
book on a SysV system) did their job silently and the build succeeded without
its test suite.  The design held.

## What differs AND concerns you  (1.14.50)

The survey worked: 47 of 929 shared pages differ in their init handling.  And
that is still the wrong list to hand someone -- most of the 47 are GNOME,
samba, qemu, postgresql, software this machine does not have and never will.

`--installed` intersects the survey with the package users on disk: a package
with an account has been built or is about to be.  On the user's tree that
turns 47 into the handful they are actually going to build.  An empty
package-user root says so rather than comparing nothing.

The general shape: a report is only as useful as it is short, and the filter
that shortens it is usually already on the machine.  Same move as verify's
"16 need attention" out of 242 (1.14.34), and the plan's "127 of 233 already
installed" (1.14.15).

## There is no 13.0 SysV book  (1.14.49)

The fact this whole thread has been working around, established by the user's
own `blfs books`: BLFS stopped publishing the SysV edition after **12.4**.
The 13.x books are systemd-only.  So "just fetch the sysv book" -- advice
given repeatedly in this session, including by me -- was never possible for a
13.0 system.

Three things hid it.

`blfs fetch stable-sysv` printed the routine "no book matched" note and then
"cached."  A fetch that fetched nothing reported success.  It now checks the
published list, fails, and names the newest SysV edition that does exist.

`blfs diff-init 12.4` answered "0 of 947 shared pages differ" -- true and
useless: the default selector has no book, so the fallback picked the newest
cached one, which was 12.4, and it compared that book with itself.  Both sides
are printed now, and comparing a file with itself is refused.

And comparing ACROSS versions (12.4-sysv against 13.0-systemd) is the only
comparison available, where most pages differ for reasons that have nothing to
do with init.  The survey filters to differences that MENTION init
(systemd, systemctl, bootscript, init.d, tmpfiles, unit-dir, service), with
--all for everything.

What this leaves, for the next session: on 13.x, SysV pages must come from
12.4 plus judgement, or from per-package `configure_args`.  lfs-sysvbook
already grafts SysV onto a systemd LFS book; the same treatment for BLFS --
take 12.4's init-related command differences and apply them to the 13.x pages
-- is the obvious next tool, and `diff-init` is the survey it would be built
on.

## See the difference, do not guess it  (1.14.48)

BlueZ stopped with

    configure: error: systemd system unit directory is required

on a SysV system.  Nothing was broken: the SYSTEMD book's page was used, and
its configure line carries no --disable-systemd because on a systemd machine
there is nothing to disable.  Every run had already printed "no book matched
'stable-sysv'"; this is what that note costs when it is ignored.

Two additions.

The failure box now recognises a systemd-only configure failure on a machine
with no systemctl, and points at the BOOK -- `blfs fetch stable-sysv`, which
fixes every later page too -- with the per-package `configure_args =
--disable-systemd` as the offline fallback.

And `blfs diff-init <book> [package]` answers the question the user actually
asked ("let me hold the sysv in a vimdiff"): with no package it lists every
page whose commands differ between the two books; with one it prints the
unified diff of that page's commands.  Measured against a doctored copy: 1 of
954 shared pages, and the diff shows exactly the --disable-systemd line.

That is the shape worth keeping.  A whole-book survey turns "which of my 954
pages will bite me on SysV?" from a question answered one failed build at a
time into a list printed in a minute, before anything is built.  When the two
sources of truth disagree, show the disagreement -- do not wait for a package
to discover it.

## One typo must not disable a whole file  (1.14.47)

The recipe was followed twice, so machine.conf held

    [webrtc-audio-processing]
    cpp_args = -include cstdint
    [webrtc-audio-processing]
    cpp_args = -include cstdint

configparser raises on a repeated section, and `_read_conf_section` discarded
the ENTIRE file on any error.  So the new section did nothing -- and neither
did [mesa]: its driver selection quietly reverted to "build everything"
because of a duplicate heading further down.  That is how you get a mesa build
that wants libdrm_intel on an AMD machine, from an edit made somewhere else
entirely.

`strict=False` merges repeated sections, later keys winning, which is what
someone appending a correction means.  A file that is genuinely malformed
still reports -- and now says how far the damage reaches: "NO options from
that file were applied, not for this package and not for any other."

`cat >>` is how every recipe in this session told the user to edit that file,
so a repeated section was not an edge case, it was the expected outcome of
following instructions twice.  A config parser that fails closed on the whole
file, over a duplicate heading, punishes the ordinary way of using it.

## Advice that nothing reads  (1.14.46)

1.14.45's box told the user to put

    [webrtc-audio-processing]
    cpp_args = -include cstdint

in machine.conf.  webrtc-audio-processing is a GIT STACK ENTRY, and
`apply_machine_opts` was called only from `resolve_script` -- the book path.
Nothing would have read that section.

Correct and inert is worse than wrong: it looks like it worked, the build is
retried, the same error comes back, and the person has no way to tell whether
the advice was bad or their edit was.  The stack's git/tar branch applies the
options now; a script is a script, and the options belong to the PACKAGE, not
to where its commands came from.

Three consecutive releases (1.14.44, .45, .46) have been "the message was
right, the machinery behind it was not".  Whenever a diagnostic prints a
recipe, the next question is which code path consumes it -- and whether the
path that just failed is one of them.

## One flag, and the same one every time  (1.14.45)

webrtc-audio-processing stopped with

    trace_event.h:202:18: error: 'uint8_t' does not name a type

That is not a broken package: GCC 13 stopped pulling <cstdint> in through
other headers, so anything written before that no longer compiles.  Half the
older C++ in BLFS hits it.  The box said "if it needs a build flag, put it in
machine.conf" -- true, and no help at all when the flag is always the same
one.

It now names the cause and the cure, in the right language for the file that
failed:

    cpp_args = -include cstdint       (C++)
    c_args   = -include stdint.h      (C)

...and an ordinary compile error still gets the generic advice, so this does
not become "every failure is cstdint".

While writing that: the flag would NOT have worked.  `apply_machine_opts`
pasted values into the shell line unquoted, so `cpp_args = -include cstdint`
became `-Dcpp_args=-include cstdint` -- two shell words, one of them a stray
`cstdint`.  Every option that takes a flag LIST has this shape; the
single-word examples in the help text (`c_args = -DSOMETHING`) hid it for as
long as the feature has existed.  Values with whitespace are quoted now, and
re-applying does not nest the quotes.

Recommending a fix and then mangling it is the worst of both: the person
follows the advice, it fails differently, and the advice is what they stop
trusting.

## A ref that does not exist is a typo, not a build error  (1.14.44)

sway.stack pinned usrsctp to `ref=1.0.0`.  That tag does not exist upstream --
the repository has 0.9.3.0, 0.9.4.0, 0.9.5.0 -- and all the person saw was
git's own

    error: pathspec '1.0.0' did not match any file(s) known to git
    !! phase 'unpack' FAILED (exit 1)

which reads like a build failure and sends them to a log.  The repository is
cloned and standing right there, and it knows exactly what it does have.

The runner now names the ref, lists the recent tags and the branches, and says
where the wrong value came from ("Fix ref= in the stack entry for X").  The
phase still fails -- explaining is not excusing.

The stack's pin is corrected to 0.9.5.0, checked to have meson.build so the
entry's build line still applies.  libsrtp's v2.6.0 verified too; libnice and
webrtc-audio-processing are on gitlab.freedesktop.org, which this environment
cannot reach, so those two are unverified and may hold the same kind of typo.

Worth noting for stack entries generally: a pinned ref is data that rots, and
the only thing that can check it is the remote.  `git ls-remote --tags` is
cheap; a `packagemanager stack --check-refs` that runs it over every git entry
would turn this class of failure into a five-second report.  Not built.

## Not installed is not the same as not a package  (1.14.43)

The user asked: "is something broken in our install cycles?"  No -- and the
evidence they gathered settled it in one line:

    ls -al /usr/src/pkgusr/ | grep tiff     ->  (nothing)

There is no p_libtiff account: libtiff was never installed here.  gtk4
requires it, and NO page in that chain lists it -- not gtk4's, not
gdk-pixbuf's, not librsvg's (all three checked).  Same family as libaom
needing cmake: the book does not say, so the planner cannot know.

But the box handled it badly.  1.14.42 resolved a module name to its package
by asking whether the ACCOUNT exists, so with libtiff absent it fell through
to "nothing provides 'libtiff-4' -- packagemanager install libtiff-4", naming
a package the book does not have, and then offered to vendor a copy.  Two
wrong answers where the right one was one string operation away.

A trailing API version that strips to a DIFFERENT name is the signature of a
pkg-config module belonging to a real package (libtiff-4 -> libtiff,
libxml-2.0 -> libxml).  The box now names that package, offers to install it,
and says how to check the guess.  libnsgif strips to itself, so it keeps the
fallback advice -- the distinction that matters is preserved.

Three releases on this one message (1.14.39, .42, .43), each fixing what the
previous one got right for one case and wrong for the next.  A diagnostic that
prescribes should be tested against every shape it can meet, not the one that
prompted it.

## One answer per failure  (1.14.42)

gtk4 stopped on `Dependency 'libtiff-4' is required but not found`, and the
box told the user to allow a vendored copy:

    [gtk4]
    wrap_mode = default

libtiff-4 is the pkg-config MODULE of libtiff -- a BLFS package, installed on
that system.  Following that advice would have built a second libtiff inside
gtk4 and buried a pkg-config problem under it.  The advice added in 1.14.39
was right for gegl and wrong here, and nothing distinguished the two.

Two faults.  meson has a SECOND wording -- "Dependency 'x' is required but not
found", single quotes -- which matched none of the four extraction patterns,
so the whole .pc diagnosis was skipped and only the fallback note survived.
And the fallback note ran BEFORE that diagnosis, so it could not have known
better even with the name in hand.

Now the diagnosis runs first and resolves the module name to the package that
owns it (`libtiff-4` -> `libtiff`, trying the name and then with a trailing
API version dropped -- libxml-2.0, ncursesw6 are the same shape).  When there
is an owner the box says so and offers the rebuild; the fallback note stays
quiet.  When there is none, the fallback note is the answer and the generic
"nothing provides it" line stays quiet instead.

Saying two contradictory things in one box is worse than saying neither: the
person has to decide which half to believe, and the wrong half was the one
with a command under it.

## A test runner is a command, not a substring  (1.14.41)

librsvg died on `Program 'cargo-cbuild' not found`, and cargo-c -- which
provides it -- had installed nothing.  Its one install line:

    install -vm755 target/release/cargo-{capi,cbuild,cinstall,ctest} /usr/bin/

`\bctest\b` matched inside the brace list, because a comma is a word
boundary.  The line that installs four binaries was commented as "runs the
test suite"; verify was RIGHT to call cargo-c not installed; and the failure
surfaced two packages later in something that needed one of those binaries.

`ctest` and `pytest` now need a lookbehind rejecting a name that is part of a
word, a path or a list.  Being a test runner is about being the COMMAND.

Found while checking the whole book for the same shape: Whois installed
nothing either.  It builds with a bare `make` and installs with `make
prefix=/usr install-whois`, and `_comment_orphan_doc_installs` skips
`make install-X` unless something ran `make X` -- there is no `make whois`
target.  A bare make builds the package; the exception is the DOCUMENTATION
targets (man, html, info, pdf...), which is the case that filter exists for --
git has a bare make too, and its manuals still need the conditional
`make man`.  Both verified.

The whole book now: 954 scripts, 0 syntax problems, 0 install phases that do
nothing.  That last number is the one to keep in the suite -- it is the
cheapest possible check for this entire family of filters, and it would have
caught the pip wheels (1.14.16), cargo-c and Whois on the day each was
introduced.

CACHE_VERSION 52.

## Protect against what the book has  (1.14.40)

1.14.39 told the user how to allow gegl's fallback by hand.  They should not
have had to: gegl is a book package that BLFS builds with a plain `meson
setup`, and our flag is what stopped it.

The rule the protection was reaching for is narrower than "no fallbacks ever":

    libnsgif, poly2tri-c   no BLFS page   -> nothing can supply them; allow
    freetype2, fontconfig  in the book    -> a fallback would shadow a package
                                             we manage; refuse

`--force-fallback-for` overrides the wrap mode for exactly the named
subprojects, so gegl now generates

    meson setup --force-fallback-for=libnsgif,poly2tri-c --wrap-mode=nofallback ...

and cairo is untouched.  `_FALLBACK_ALLOWED` carries the list, with a test
asserting every name in it really has NO page -- so if the book gains one, the
suite says so rather than a vendored copy appearing quietly.  CACHE_VERSION 50.

The machine.conf `wrap_mode` override from 1.14.39 stays for the cases the
list has not caught yet, and the failure box still explains itself.  A default
should fit the common case; an escape hatch is for the rest, not for a
package the book supports.

## A commented block does not move the stream  (1.14.39)

gegl failed with

    ninja: error: loading 'build.ninja': No such file or directory

Its generated script had an EMPTY build phase and did the whole build inside
install_pkg -- so when `meson setup` failed, the `ninja install` on the next
line ran regardless and produced that message instead of the real one.

`extract_commands_phased` latches: once a ROOT block has appeared, everything
after it joins the install stream.  That is right, and GLib needs it (build,
install gobject-introspection as root, then reconfigure).  But gegl's first
root block is conditional -- "If you are installing over a previous version
... remove it" -- so it is emitted COMMENTED and nothing has happened, and it
flipped the latch anyway.  A block that does not run cannot mark a boundary.
CACHE_VERSION 49.  Across the book: 954 scripts, 0 syntax problems, GLib's
interleaving intact.

The real dependency error underneath was ours too.  blfs adds
`--wrap-mode=nofallback` to every `meson setup` so a package cannot silently
vendor a dependency (cairo once installed its own freetype, and the planner
then believed freetype2 was done).  gegl needs libnsgif and poly2tri-c, which
have NO BLFS page -- the fallback is the only way to get them, and meson's
message ("Use of fallback dependencies is disabled") never says who disabled
it.  So: `wrap_mode` is settable per package in machine.conf, and the failure
box says the flag is ours and prints the three lines that override it.

A protection that cannot be turned off for the case it does not fit is a bug
with a good reason.

## A report names the thing it is about  (1.14.38)

After 1.14.37 the tree came to 232 installed and six lines needing attention.
Two of those six were the report's own fault.

    root   broken   has a home dir but no user

That sent the user looking for /usr/src/root, which is not where it is.  The
path was in hand when the line was printed and thrown away; it now reads "no
account for the directory <path>", which is the whole of what anyone needs to
act.

And the advice under the list said "remove with: packagemanager remove
<name>".  For a directory with no account the fix is to delete the DIRECTORY,
and suggesting a remove command against a name like `root` is an invitation to
an accident.  It names the line above instead.

Two process notes from this release.  The version bump was done with a blanket
`sed s/1.14.37/1.14.38/` over the tools, which rewrote HISTORICAL references
inside comments -- "fixed in 1.14.35" became "fixed in 1.14.38", and a test
whose sed range quoted one of those comments stopped matching.  Bump the
version CONSTANTS only; a comment naming a version is a fact about the past.

Small, but this is the fourth report in the session whose remedy was "print
what you already know" (1.14.6 the file paths, 1.14.32 the cycle, 1.14.33 the
manifest owner).  The information is almost always in hand at the moment of
the message.

## An install that leaves no record is invisible  (1.14.37)

verify reported beautifulsoup4, certifi, charset_normalizer, idna, requests,
soupsieve and urllib3 as "not installed -- nothing installed yet", while blfs
was using bs4 to parse the book on that same machine.  Their homes held
build.conf and .project and nothing else.

`packagemanager pip` installed the module and wrote NO record: no pkg.lst, no
install_last.  Every downstream reader -- verify, the planner, gather_user --
looks at those two files, so the bootstrap set the tools depend on was
invisible to the tools.  And then verify offered to rebuild them with a
command that could not work, because they are not BLFS packages either.

The user's question was the right one: "if we use pip to install something, it
should somehow be unified".  It is now.  `pip_install_module` writes the
manifest (write_pkg_list), an install_last carrying name_version -- with the
version asked of the MODULE via importlib.metadata, not of the request -- and
a validate_cmd that can confirm it later.  So a pip module is a package like
any other from the moment it lands.

For the ones already installed without records, `packagemanager pip record
[names]` writes the paperwork without reinstalling; with no names it finds
every account whose module imports but has no record.  It REFUSES to record a
module python cannot import, which is what keeps it from stamping a lie onto
the exact state it was written to fix.  verify names that state and prints
that command instead of "nothing installed yet".

The pattern, for a future session: state lives in pkg.lst + install_last, and
anything that installs must write both.  Three install paths existed
(pm-install, the runner, pip) and only two of them did.

## Silence is the one answer a command must never give  (1.14.36)

Pasting verify's own suggested command:

    packagemanager install beautifulsoup4 cargo-c ... --run --recursive
    note: no book matched 'stable-sysv'; using the cached BLFS-BOOK...
    (nothing else, prompt returns)

`blfs order` exits 1 for a name the book does not have, and
`blfs_order_anchors` turned that into `sys.exit(1)` for the WHOLE run --
before any plan was printed.  One name that is not a BLFS package (soupsieve,
pkgusr, linux-headers) killed a twelve-package command, and the person could
not tell whether it had worked, refused, or crashed.

It reports the name and returns an empty order now; the caller records it in
`not_found` and carries on with the rest.  The recursive branch also never
recorded such a name at all -- the non-recursive one always had.

And verify no longer suggests a command that cannot work.  Its list is split:
BLFS packages get the install command; LFS steps (linux-headers, pkgusr) are
named as chroot-build work; anything else is an account with no package.
Offering a command that fails is worse than offering none -- 1.14.10 again,
and this time the wrong command came from our own health check.

## One shared value, two defaults  (1.14.35)

1.14.34 fixed the collector-group filter and the groups were STILL reported as
broken packages.  The filter was right; the prefix was not.

`lfs` and `packagemanager` fall back to "sysgroup"; lfs-helper had one line
saying `${COLLECTOR_PREFIX:-nimgnu}`.  On a system whose config never set the
key, groups were CREATED as nimgnu_* by lfs-helper and filtered for as
sysgroup_* by packagemanager.  A value read from a shared file, with a
different default in each reader, is not shared.

Three changes: lfs-helper falls back to "sysgroup" like the others; the
account list recognises BOTH spellings, because real systems already carry
groups under either name and the config still decides what new ones are
called; and `_looks_like_an_account` no longer accepts "a user of this name
exists" -- /usr/src/root passed that test because root exists, which is how a
directory became a broken package.

Also: 1.14.34's summary block was inserted by a string replace that matched in
TWO functions, so verify printed it twice and cmd_script_status got a copy
referring to a variable it did not have.  Broad textual edits need the same
care as the code they edit.

## A health check nobody reads is not a check  (1.14.34)

A real `packagemanager verify` on a working tree:

    broken: 4   not installed: 12   unvalidated: 226

Three problems in one line.

**226 "unvalidated" were normal.**  Most pages name no installed_programs or
-libraries, so there was nothing to check against -- and the answer to
"nothing to check" was a word that reads like a fault.  The manifest HAS been
checked by then (its files exist, or the state would already be "not
installed"), so the honest answer is `installed`, with the limit stated.
Anything genuinely wrong still comes out as not installed, broken, or a
missing target.

**Three of the four "broken" were collector groups.**  `nimgnu_*` are groups,
not packages.  The filter for them read `d.startswith(_cp + "_")` while
`collector_prefix()` already ends in "_", so it tested for `sysgroup__` and
has never matched anything since it was written.  One underscore.

**The fourth was a stray directory.**  BASE_DIR is /usr/src, which holds more
than accounts; every directory in it was treated as a package, so `root` was
reported as broken.  An account has one of the account prefixes, exists in the
user database, or carries the skeleton -- a bare directory is none of those.

And verify now ends with the work rather than the evidence: the packages that
need action, with the command to rebuild them, or "nothing needs attention".
The twelve that mattered were in the middle of 242 lines.

Also worth recording: the grep suggested to the user in chat --
`verify | grep -vE "installed "` -- hid the "not installed" lines it was meant
to surface.  A filter written against the wrong end of a word.

## The manifests know who claimed it  (1.14.33)

librsvg stopped on `Program 'cargo-cbuild' not found`.  The box had the shape
of it right -- a package recorded as installed whose build did not finish --
and then said "find the package, purge its record, rebuild it", leaving the
person to find it.

Every installed package has a pkg.lst naming what it installed.  One grep
answers, and the answer says WHICH of two situations this is:

- a record CLAIMS the file -> that record is wrong;
  `packagemanager install cargo-c --run --reinstall`
- nobody claims it -> whatever provides it was never installed;
  `packagemanager search`, then install.

Also hardened: the report reads $SRCROOT and now tolerates it being unset.  A
failure report runs under `set -u` in whatever state the failure left, and
must not add a second failure to the one it is describing.  Same lesson as
1.14.4 (`_retry: unbound variable`), which is why the test for that one
deliberately does not set SRCROOT either.

## Say what the cycle cost  (1.14.32)

vala stopped at

    configure: error: Package requirements (libgvc >= 2.16) were not met

libgvc is Graphviz, which vala RECOMMENDS, and graphviz was in the plan --
twenty packages later.  The cause is a real cycle:

    vala -> graphviz -> gegl -> babl -> librsvg -> vala

every edge recommended, so one has to give and vala loses.  The breaker has
done this correctly since 1.13, and silently, so the consequence arrived as a
configure error with no connection to the decision that caused it.

`_CYCLE_DROPS` records each dropped edge; `blfs order --anchors` emits it as
`#cycle<TAB>dependant<TAB>dependency`; the plan reports the ones that are real
in the FINAL order (a two-package cycle drops both edges, so reporting both
directions makes one line false every time) and offers the rebuild:

    10 package(s) are built before something they recommend (a dependency cycle):
      vala             is built before graphviz
      freetype2        is built before harfbuzz
      ...
      rebuild afterwards if you want it:
        packagemanager install babl gdk-pixbuf glib2 vala ... --run --reinstall

Also: 1.14.26 knew meson's wording for a missing dependency and pkg-config's,
but not autoconf's -- "Package requirements (libgvc >= 2.16) were not met" --
so every autotools package in the book missed the .pc diagnosis entirely.
Three spellings of one event, and a pattern that matched two of them looked
like it worked.

## A link in an aside is not a dependency  (1.14.31)

Asked whether the plan could be trimmed: installing Xwayland -- an X server
for Wayland -- planned 235 packages, among them LibreOffice, OpenJDK,
PostgreSQL, TeX Live and a print stack.

One sentence on the harfbuzz page:

    Graphite2-1.3.14 (required for building texlive-20250308 or
    LibreOffice-26.2.1.2 with system harfbuzz)

Those name what NEEDS graphite2.  `_dep_xrefs` took every `<a class="xref">`
in the paragraph, so harfbuzz "recommended" LibreOffice and TeX Live -- and
from them came Qt6, Cups, Java, OpenJDK, Postgres, the lot.  poppler
"recommended" okular the same way, from "Qt-6.10.2 (required for PDF support
in okular)".

The qualified package is always the link BEFORE the parenthesis, so links
inside one can be dropped without losing anything real.  `_in_parenthetical`
counts unclosed brackets in the text preceding a link.  CACHE_VERSION 48.

    xwayland   235 -> 53      mesa 41   dbus 35   pipewire 110   gtk4 125
    required-only: 25, unchanged -- nothing real was lost

Checked by hand against the book: harfbuzz keeps GLib, Graphite2, ICU and
FreeType (exactly what its Recommended line says), poppler keeps Qt6 and loses
only okular.

This also retired the 1.14.24 test, which used harfbuzz/libreoffice as its
example of a prunable branch -- an edge that was never real.  It uses
poppler/qt6 now (185 -> 61).  A test written against a bug reads as a
specification for it.

The user's avoid list, and the ignore machinery of 1.14.24, were both
compensating for this.  Worth asking, when a workaround gets long, whether it
is working around a mistake.

## Ask the way the build will ask  (1.14.30)

A plan printed itself twice and refused twice:

    cargo    needed by 2 package(s), first: cargo-c
    adding to the plan: rust -- its commands call `cargo`
    ... the same plan again, the same refusal ...

Rust was installed.  BLFS puts it in /opt/rustc and adds /opt/rustc/bin from
/etc/profile.d/rustc.sh; a build runs through `su -`, a LOGIN shell, which
reads that.  `shutil.which` reads OUR path, which does not.  So a tool the
build could see perfectly well was reported missing.

And the 1.14.14 repair could not help: adding an already-installed package to
the plan changes nothing, so the second pass produced an identical stop.  A
repair that cannot change the state it is repairing has to notice, or it
loops.

`_tool_available` asks the way the build asks -- PATH, then `bash -lc
'command -v'` (bounded, memoised), then /opt/*/bin.  A provider that is
already installed is never "added" again.  And when the package IS installed
while the tool is not on our PATH, the stop says so and names the cause:

    NOTE: rust is installed, so `cargo` exists but is not on PATH here.
          BLFS puts it outside /usr (e.g. /opt/rust/bin) and adds it in
          /etc/profile.d -- which a login shell reads and this one did not.

The general lesson: a check must run in the environment of the thing it is
checking.  This is 1.14.7 again from the other side -- there the build could
not see what we had set, here we could not see what the build had.

## The setup for a test is part of the test  (1.14.29)

An ordinary Xwayland build cloned piglit, cloned the X Test Suite, started an
Xvfb server and tried to build xts:

    install_Xwayland-24.1.9: line 54: cd: xts: No such file or directory
    Fatal server error

The page puts all of it in the BUILD block, and only the last line
(`ninja test`) looks like a test run, so the 1.13 filter commented that one
line and left everything it depends on running.  Commenting a test but not its
setup is worse than commenting neither: the whole cost is still paid and the
result is thrown away.

The setup is bracketed by pushd/popd, so the group can be taken as a unit --
but only when it is recognisably a test suite (`_TEST_SETUP_RE`: piglit, xts,
fate-suite, jtreg, XTEST_DIR...), never a plain pushd group that happens to
sit before a test.  A `mkdir` on its own line above the pushd goes with it,
since the directory exists only for the suite.  The book's text is commented,
not deleted, so it can be read and re-enabled.

Across the whole book this changes exactly one page, and all 954 still parse.
That narrowness is the point: the rule fires on evidence, not on shape.

## Build it, do not just name it  (1.14.28)

The 1.14.27 check worked -- and then asked the person to type the thing the
stack exists to do:

    stack stopped at git 'elogind': it needs a tool that is not installed
        packagemanager install git --run --recursive

A PLAN already handles this itself: 1.14.14 adds a missing provider to what
was asked for and rebuilds.  A git entry is not a plan, so it stopped.  git is
a book package and the stack installs book packages all day.

A git or tar entry now installs any missing tool the BOOK provides
(`--recursive`) and carries on.  A tool with no BLFS page -- meson, ninja,
gperf, which come from LFS -- still stops the run, because nothing here can
install those and pretending otherwise would loop.

The distinction that matters, and it has now come up three times (1.14.10,
1.14.14, here): a message telling someone to run a command is only right when
they know something the tool does not.  When the tool has everything it needs
to do the thing, printing the command instead of doing it is not caution, it
is an unfinished feature.

## An old account can point at the wrong home  (1.14.27)

elogind ended up with two half-populated homes:

    /usr/src/p_elogind/         install_elogind, install_last, log
    /usr/src/pkgusr/p_elogind/  build, build.conf, src

Its .bash_profile was dated November 2023 -- an account carried over from an
earlier system.  Every tool resolves the home through `pkgusr_home_for` (the
canonical path), but `su -` starts in the PASSWD home, so the build ran in one
directory while its sources were staged in the other, and the failure box
printed two different paths for the same script without either being wrong.

`_repair_misplaced_home` has existed since 1.11.x and ran only when an account
was CREATED.  An account made by an older version was never re-examined.
cmd_pm_install now repairs an existing account's home before staging, in the
LOUD form -- a home wrong since 2023 is not the routine just-created case
1.14.4 quieted.

Second fix from the same report: `git: command not found`, after the account
was made and the phase started.  A stack entry of kind=git sets `is_git="1"`
and the RUNNER does the clone, so `git` appears in no command text and the
1.14.9 scan could not see it.  It is read from `is_git` now, git is in the
tool map (`Git-2.53.0` -- checked against the book, per 1.14.14), and a git
entry runs the same prerequisite check as a book package before it creates
anything.

## Three reasons a dependency is "not found"  (1.14.26)

mesa stopped with meson's entire account of the problem:

    ERROR: Dependency "libdrm_intel" not found, tried pkgconfig and cmake

libdrm was installed -- 2.4.131, found two lines earlier in the same log.  It
had been built before libpciaccess existed, so it has no libdrm_intel.pc and
never will until it is rebuilt.  The book only RECOMMENDS Xorg-Libraries for
libdrm, so nothing put them in that order.

The .pc files on disk tell the three cases apart:

- the .pc EXISTS and was not found -> a path problem (PKG_CONFIG_PATH,
  pc_path), not a missing package;
- the .pc is absent but its PROVIDER's is present (libdrm_intel -> libdrm)
  -> the provider was built without that component, almost always because one
  of its own dependencies was missing at the time; rebuild it;
- neither -> nothing provides it, and which-package/install is the way.

Same shape as 1.14.22's undeclared symbol, and the same principle: the tools
cannot fix a build error, but they can nearly always say which KIND it is,
and that is most of the work.

Note for a future session: libdrm-before-Xorg-Libraries is an ordering the
book's own dependency lists do not express, exactly like libaom needing cmake
(1.14.12).  The command-scanning fix cannot see this one -- there is no
`libdrm_intel` in the commands -- so it stays a diagnosis rather than a
prevention.

## Where the page's own commands left off  (1.14.25)

Xorg Libraries downloaded all thirty-two tarballs, verified every checksum,
and then:

    the list this build loops over is missing or empty: ../lib-7.md5

Its prepare step writes lib-7.md5 in the build root, then `mkdir lib && cd
lib` and downloads into it; the build loop reads `../lib-7.md5`, which only
resolves from INSIDE lib.  `_pp_unpack` ran prepare_pkg and then `cd
"$BUILD_ROOT"` -- correct for a package with a tarball, which must be looked
for from the build root, and fatal for a page whose own commands ARE the
unpack.

The directory prepare_pkg ends in is now remembered (`_pp_prepared_in`) and
recorded as the resume point for a page with no tarball of its own, so build,
install and configure all continue where the page left off.  A package with a
real tarball still enters its unpacked source, as before; both are asserted.

The runner's own guard was what caught this, and it named the file it could
not find -- which is the only reason the cause was findable at all.  A test
that fails with the path it looked for is worth writing.

## An avoided package is not walked into  (1.14.24)

The JT_JAVA plan had cups, Java, OpenJDK and apache-ant in it, every one
labelled "required by libreoffice" -- with libreoffice in --ignore.  Ignoring
dropped the NAMED package and kept everything it alone wanted, so a sway
desktop was about to build a JDK.

1.12.82 tried this and was reverted, for a real reason: it pruned the FINISHED
list, `blfs order` reports one parent per package, and graphite2 -- recorded
under an ignored parent but genuinely needed by harfbuzz -- was dropped:

    Dependency 'graphite2' is required but not found

That note ended "pruning needs every edge, which this output does not carry".
So it moved to where the edges are.  `walk_deps` does not descend into an
ignored anchor; anything another package needs is still reached through that
package.  Measured on harfbuzz with libreoffice ignored:

    before   230 packages   (planner: 463)
    after     46 packages   (planner: 101)
    kept     graphite2, icu, libxml2, fontconfig, curl
    gone     PostgreSQL, unixODBC, CLucene, Redland, OpenJDK, apache-ant, Cups

A package named as the TARGET is still built, ignore list or not -- otherwise
`install libreoffice --ignore libreoffice` would silently do nothing.

sway.stack's avoid list is eighty names long because that is what it took to
say this by hand; its own comment says what was meant -- "everything they
alone pull in goes with them".  The list can shrink to the branches
themselves now, though it costs nothing to leave.

The wider point: a revert with a reason attached is a bug report.  1.12.82
recorded exactly why its approach could not work, and that sentence was the
design for the fix two years of versions later.

## A commented line is not a command  (1.14.23)

A plan refused to start:

    JT_JAVA        needed by 1 package(s), first: openjdk
    packagemanager env --set JT_JAVA=...

JT_JAVA appears on OpenJDK's page only inside the TEST block -- which the
generated script comments out -- and the page exports it there itself:

    # export JT_JAVA=$(echo $PWD/build/*/jdk) &&
    # jtreg/bin/jtreg -jdk:$JT_JAVA ...

So `_required_env_guard` demanded a value for a variable nothing live would
ever read, and the person was asked to invent one for a test suite that does
not run.  The stop added in 1.14.12 turned that into a refusal to build
anything at all -- a correct mechanism amplifying a wrong input.

Two rules, both obvious in hindsight:

- Scan only lines that will RUN.  Everything commented is the book's prose,
  kept for the reader, and not the shell's business.
- A variable the commands ASSIGN is not one to ask about, live or commented:
  the page is telling us the value, not asking for it.  (TeX Live sets
  TEXLIVE_PREFIX="/opt/texlive/2025" itself.)

Across the whole book the guards now come to exactly XORG_PREFIX (14 pages)
and XORG_CONFIG (23) -- the two the Xorg build environment page genuinely
asks the reader to export, and nothing else.  Before this, every page whose
commented-out test block mentioned a capitalised name could stop a build.

## An undeclared symbol usually belongs to someone else  (1.14.22)

cairo stopped with twelve errors, all like

    error: 'FC_HINT_NONE' undeclared (first use in this function)
    error: 'FC_RGBA_RGB' undeclared ...

Every one of them is fontconfig's.  This is not a bug in cairo: it is a
DEPENDENCY whose headers are missing or too old.  The box said "this is a
COMPILE error in the package's own source ... the tools cannot repair it" --
true about repairing, wrong about the diagnosis, and it left the person to
work out whose symbols those were.

The tools can look.  The first undeclared symbol is grepped for under
/usr/include (bounded: `timeout 20`, `grep -rlm1`, first hit only):

- FOUND -- the header is installed and the build did not see it, so the
  problem is an include path or a missing .pc file; the header's directory
  usually names the package, so `pkg-config --cflags fontconfig` and
  `packagemanager info fontconfig` are offered.
- NOT FOUND -- nothing on this system declares it, so the package that
  provides it is missing or out of date, and `packagemanager which-package`
  is the way to it.

The machine.conf advice stays for what it was written for: a real compile
error needing a build flag.

Also fixed in the suite: the harness that tests the failure report sliced it
from a marker HALFWAY DOWN, so every branch above that marker -- including
this one and the compile-error branch it sits in -- was untested.  It now
builds the whole report.  A test that covers half of what it names is worse
than none, because it reads as coverage.

## One door for every build  (1.14.21)

glib2's install stopped on

    PermissionError: [Errno 13] '/usr/share/gettext/its'

Through lfs-helper that failure is REPAIRED -- grant-and-retry offers a
collector group for the directory and runs the phase again, which is exactly
what happened the first time.  Through `packagemanager script install glib2`
the identical traceback repeated forever: that path built its own `su` and had
none of the wrappers, the file tracking, the failure box or the repair around
it.  And `packagemanager script install <pkg>` is the command the failure box
itself prints.

It now calls `lfs-helper build <user> --script <file> --phase <phase> --force`
when lfs-helper is present, falling back to the old direct run when it is not.

This is the SECOND bug from that same split -- 1.14.7 was the build
environment not reaching the build, from the same reimplemented `su`.  The
note then said "packagemanager script should call lfs-helper run_phase_as
rather than reimplement it"; it took a wasted evening to make that concrete.
When a note says two implementations will drift, believe it.

Also here: this path still used install_<user>, the redundant copy 1.14.16
removed everywhere else, so a failure said "ran: install_p_glib2" while
telling the person to edit install_GLib-2.86.4 -- and an edit to the file they
were pointed at did not affect the file that ran.  It uses the canonical
versioned script now, and the regeneration message says what actually happened
instead of claiming that file "is never regenerated" while regenerating it.

## Not every name is an LFS step  (1.14.20)

    lfs-helper build glib2 --phase install --force
    !! no script for 'glib2' at /usr/src/lfs-pkgusr/scripts/glib2.sh
       From outside the chroot:
           lfs build-system gen-chroot-scripts --run --overwrite
    (then, running exactly that)
    You are inside the LFS chroot, where it does not apply.

"that hint was dumb", and it was.  glib2 is a BLFS package: there is no
$SCRIPTS/glib2.sh and there never will be.  cmd_build looked only at the step
scripts, assumed a missing name meant a missing STEP script, and prescribed
the cure for that -- a command that refuses to run in the chroot the person is
standing in.  Meanwhile glib2's script was in /usr/src/pkgusr/p_glib2/, which
the failure box's own retry hint had printed a screen earlier.

Two changes:

- Before giving up, cmd_build looks for the package user's own script
  (install_<Name-Version>, newest first, .edited and .bak excluded, then
  install_last).  A BLFS package now builds through `lfs-helper build <name>`
  as well as through packagemanager.
- The message that remains asks WHAT THE NAME IS.  `in_step_order` decides:
  a real step with no script keeps the regenerate advice; anything else is
  told to use packagemanager, or to check `lfs-helper list` for the step it
  might have meant.

1.12.30 fixed the same class of thing from the other end (the retry hint
printed the anchor, and `lfs-helper build` wanted the account).  The lesson
both times: a tool that accepts a name from three different namespaces owes
the user an answer that says which one it looked in.

## A typo in a group name is permanent  (1.14.19)

The collector-group prompt offered `nimgnu_gcc` or `nimgnu_lib`, the user
typed a name of their own and wrote `nimnu_gdb` -- one letter short of the
prefix.  Perfectly valid as a group name, so it was created and the directory
handed to it; and nothing that looks for `${COLLECTOR_PREFIX}_*` will ever see
it again.

The prompt sanitised CHARACTERS (1.13.x, after a leading space produced
`--nimgnu_gcc`) but never asked whether the name meant what it said.  It now
compares the part before the first underscore with the configured prefix and,
when it is one edit away, offers the correction:

    'nimnu' is not 'nimgnu' -- collector groups start with 'nimgnu_'.
    use 'nimgnu_gdb' instead? [Y/n]:

One edit exactly: a name that is nothing like the prefix is a deliberate
choice and is left alone.

For the ones already made, `lfs-helper rename-group <old> <new> [--run]`.
Renaming is the whole repair because the GID does not change -- every
directory already handed to the group and every member still apply.  It lists
what it will affect, refuses a name that exists, and has a dry run.

The general point: a prompt that accepts free text is a place where a typo
becomes permanent state.  Validating the SHAPE of an answer is not
second-guessing the user; it is the difference between a question and a trap.

## Ask the book once, not once per package  (1.14.18)

"why is the lookup for the script taking that long? arent we somehow indexing
all the package names?"

There is an index.  `book_versions_all()` reads the whole book in one call and
returns anchor -> name_version -- and only `update` used it.  `book_version()`,
which everything else calls, ran `blfs debug <anchor>`: a subprocess that opens
and reads the book cache to answer ONE lookup.  The sway stack preview asks it
56 times; the planner asks it for every package it considers.  Hence the
minutes of

    looking up pipewire in the book

Measured on 26 names: 7.07s of subprocesses against 0.79s for the map, and
every lookup after the first free.  The map is loaded on first use; a name it
does not have (an alias, a URL) still falls back to the old call and is
remembered afterwards.

Worth noticing WHY this survived: the fast path existed and was used in one
place.  A helper written for one caller does not advertise itself to the next
one, so the slow obvious thing stays.  When something is slow, look for the
bulk version before writing one.

## A fix that only applies to new records is half a fix  (1.14.17)

1.14.16 excluded /var/mail from the manifest SCAN, and the next run failed the
same way: Hatchling, `No module named 'pathspec'`, pathspec skipped again.
Every pkg.lst already on disk still had that one line in it, and the reader
still counted it -- one path, one alive, "installed".

The exclusion belongs on both sides.  `_manifest_has_real_paths` skips account
furniture (/var/mail, /var/spool/mail) as it reads, so a record written by any
earlier version is judged on what it actually claims about the install.  A
mail-spool-only manifest now reads as not installed, and the planner rebuilds.

The lesson, and it is the same shape as the "advice must work where the person
is standing" one: a fix that only applies going forward leaves every existing
system broken, and those are the systems people are running.  When a rule
changes, ask what the data already on disk says under the new rule.

## Build a wheel, install nothing  (1.14.16)

The user pasted an `ls` of p_pathspec and its manifest:

    /usr/src/pkgusr/p_pathspec/pkg.lst  ->  /var/mail/p_pathspec

One path, created by useradd.  Two independent faults had met.

**The install step was commented out.**  `_comment_orphan_pip_installs`
comments a pip install whose `--find-links` directory nothing builds -- right
for brotli, whose wheel step is optional and commented.  But it judged each
command block ALONE, and for a Python module the wheel is built in the BUILD
phase and installed in the INSTALL phase.  It never saw the producer, so it
commented the only line that installs anything.  ALL 76 python-module pages
in the book: build a wheel, install nothing.  Each block is now filtered with
the other in view.

**The mail spool passed for evidence.**  useradd creates /var/mail/<user>
owned by the package user, the manifest scan picked it up, and `state`
accepts one existing path as proof of an install.  So a package that installed
nothing looked installed, the planner skipped it, and Hatchling died on
`No module named 'pathspec'` twenty-two packages later.  /var/mail is excluded
from the scan: an empty record is honest, a record of the account's own
furniture is not.

**A second opinion, from data already on disk.**  Every generated script
carries the page's own Installed-programs/-libraries/-directories:

    installed_directories='/usr/lib/python3.14/site-packages/pathspec ...'

`_declares_content_that_is_missing` checks them, and when a script names paths
and none exist the package is not installed, whatever install_last says.  Only
when the page names paths -- otherwise the old rule stands.

Note for the next session: every python module "installed" before 1.14.16 is
suspect.  `packagemanager verify` or a rebuild of the module packages is the
way back.

## Progress that is real should be visible  (1.14.15)

After three runs of the same stack: "its like always starting from fresh".

It was not.  The plan had gone 181 -> 151 -> 135 across those runs: forty-six
packages built and kept.  But a re-run recomputes the whole tree and prints
only what is LEFT, so three real advances read as three identical fresh
starts.  Nothing was wrong except that the tool never said what it had
already done.

`build_install_plan` counts what it skipped as up to date, and the plan header
says so:

    ### Install plan (15 to build) ###
      4 of the 19 packages in this tree are already installed -- they are skipped.

Worth stating as a rule, because this is the third report in this session of
the same shape (1.14.2 silence during the claim, 1.14.8 silence during
regeneration, this one): a long-running tool must account for the time it
takes AND for the work it is not doing.  Silence reads as failure, and an
unchanged-looking plan reads as no progress.

## One file to edit, one to run  (1.14.16)

"im also irritated cause of the different files in script and staged, is it
wanted that we have the p prefix?"  No.  One script had four names in one
home: install_Hatchling-1.28.0 (the one the user is told to edit),
install_p_hatchling (the one that actually RAN), install_hatchling (a staged
copy) and install_last (the record).  Every failure box spent three lines
explaining which was which, and the file that ran was the one the user was
told not to edit.

The canonical versioned script is runnable, so it is what runs.
install_p_<user> is removed when it is a copy and kept with a warning when
someone has edited it; a script already living in the owner's home is not
staged to a second name; and the failure box prints a `staged:` line only when
there really is a second file.  What is left: install_<Name-Version> to edit
and run, install_last as the read-only record of what last ran.

Also: a `ModuleNotFoundError` in a build log now names the module and the
command that installs it.  pip prints a full traceback and ends with
"metadata-generation-failed", and the log scanner picked exactly the two lines
that say nothing.

## Name a package the book actually has  (1.14.14)

The 1.14.12 stop worked, and then said:

    cargo    needed by 3 package(s), first: rust-bindgen
    packagemanager install rustc --run --recursive

`rustc` is not an anchor in this book -- `rust` is (`Rustc-1.93.1`), and
`book_version("rustc")` returns None, so that command would have answered
"not in the BLFS book".  Exactly 1.14.10 again, one layer down: the
tool -> package map was written from memory rather than checked against the
book.  `ninja`, `meson`, `gperf` and `libtoolize` were wrong in a second way
-- they have no BLFS page at all, they come from LFS, so no command should be
offered for them.

`_provider_of` resolves a tool through `book_version` and returns nothing when
the book has no such page; `_install_cmd_for` builds a command only when there
is one, and the report says plainly that meson and ninja come from LFS instead
of inventing an install for them.  The test asserts EVERY named provider
resolves in the book, so the next entry added is checked by the suite rather
than by a user's failed build.

The deeper fix: a tool whose provider is not in the plan AT ALL is now ADDED
to it.  Reordering (1.14.12) can only help when both are present, and
rust-bindgen's page does not list Rust, so no ordering would have saved it.
The provider is a book package like any other -- it joins what was asked for
and the plan is rebuilt, once, so a provider that is itself missing something
cannot loop.  Only with --recursive: a plain `install X` means that package
and nothing else.

## The stack is the same door  (1.14.13)

Asked whether `packagemanager stack ... --run` gets the 1.14.12 ordering fix
too.  It does, and the reason is worth recording: a stack's `book` entry runs
`_install_via_self`, which re-executes THIS tool as

    packagemanager install <target> --run --recursive [--ignore ...]

so the plan, the ordering, the prerequisite checks and the stop all come from
the same code.  One door, as HANDOFF has it elsewhere -- and a test now
asserts it, because the day someone reimplements the install inside cmd_stack
is the day the ordering fix silently stops applying to the only command
anyone actually runs.

`--ignore-prereqs` is forwarded through it: a stack is a long unattended run,
and a decision to push past a missing tool has to reach the install it
delegates to.

Also corrected in the advice given to the user: with 1.14.12 there is no
longer any reason to install cmake by hand first.  The plan contains it and
now orders it correctly, which is the whole point of the fix.

## Build the tool before the package that calls it  (1.14.12)

The user asked the right question: "are we even sure we recursively install
programs?"  Yes -- and that was never the problem.  Measured on their plan:

    libaom-3.13.1     position  89
    CMake-4.2.3       position 151

--recursive worked; CMake WAS in the plan.  It was ordered 62 packages too
late, because the order comes from the book's dependency lists and libaom's
page lists no Required at all.  Right answer, wrong facts -- 1.14.9 read the
scripts' commands but only to WARN, when the same reading should have fed the
ordering.

`_order_by_build_tools` moves a package down to just after the one providing
the tool its commands call.  The CONSUMER moves, never the provider: moving a
package later keeps every dependency it already has in front of it, while
moving one earlier could jump it over its own (CMake needs cURL).  Only when
the tool is not already on the system, and the plan is now ORDERED BEFORE IT
IS PRINTED -- the list is a promise about what happens next.

A tool the plan itself builds is no longer reported missing; it was only late.

Two more from the same report:

- `resolve_script` has three exits and only two checked prerequisites.  The
  third -- a script already in the package user's home -- is every package
  that has been attempted once, which is why libaom's missing cmake was never
  announced at plan time.
- A plan that cannot finish no longer starts.  Warning and building anyway is
  how a missing cmake was found twenty-two packages deep, long after the
  warning had scrolled away.  `--ignore-prereqs` overrides.

Also answered: the p_cmake home with scripts and a src/ but nothing installed
is a HUSK, and expected.  The account and its script are created before the
build; that build failed (cURL missing), so the home is what the attempt left.
It is not a sign that cmake is half-installed.

## The book sets them together  (1.14.11)

Reported seventeen packages into a plan:

    this package needs XORG_PREFIX to be set

The person had set XORG_CONFIG hours earlier, from the same BLFS page that
sets both:

    export XORG_PREFIX="/usr"
    export XORG_CONFIG="--prefix=$XORG_PREFIX --sysconfdir=/etc ..."

Nothing mentioned the other half, for a reason worth remembering: `env --set`
asks the CACHED SCRIPTS which variables matter, and at that moment every one
of them was from an older blfs, so `_env_wanted_by_scripts` returned nothing
and the "ignored 183 script(s)" line was the only trace.  A check whose input
was empty reported nothing and looked like a pass.

Three changes:

- `_ENV_COMPANIONS`: XORG_CONFIG and XORG_PREFIX are each other's other half,
  so setting one names the other, with the book's own value.
- When EVERY cached script is stale, say that nothing could be determined and
  list the common variables, instead of a note about ignored files.
- The plan warns once per VARIABLE (it was once per package -- the same
  XORG_PREFIX notice dozens of times, scrolled past) and prints a summary
  beside the missing-tools one: which variables, how many packages want each,
  and the exact command.

Same shape as 1.14.9's missing build tools, and the fix belongs beside it:
everything knowable before the first package is built should be said before
the first package is built.

## A suggested command has to work  (1.14.10)

Straight out of 1.14.9.  The new hint said

    packagemanager install cmake --run

which builds cmake ALONE, and cmake then fails with

    CMAKE_USE_SYSTEM_CURL is ON but a curl is not found!

because cURL is one of its four RECOMMENDED dependencies and BLFS builds
CMake with --system-libs.  packagemanager had already said this itself, above
the plan -- "12 dependencies of CMake-4.2.3 are NOT installed ... to build
them too: packagemanager install cmake --run --recursive" -- and the hint sent
the person past its own correct advice.

Every suggested install now carries `--recursive`, here and in the
"these are NOT INSTALLED, to build them" hint.  The test greps for a bare
`install %s --run` anywhere in the tool, so the next one added is caught.

The pattern across 1.14.3, 1.14.7 and this one: a suggestion is code that
runs on someone else's machine, and it has to be correct there, not just
plausible here.

## The commands are the fact; the dependency list is an opinion  (1.14.9)

Reported from a real chroot, three packages into a 151-package plan:

    install_libheif: line 33: cmake: command not found

libheif's BLFS page has NO Required section -- only Recommended (libaom,
libde265, x265).  CMake reaches libheif only THROUGH x265, and x265 was
already installed on that system, so nothing pulled cmake into the plan.  The
resolver was right about the book; the book does not say what the commands do.

The script is right there and its commands are the truth.
`_warn_missing_build_tools` reads the command word of each line, keeps the
build-system drivers (cmake, meson, ninja, cargo, autoreconf, qmake, ...) and
reports the ones `shutil.which` cannot find, with the BLFS package that
provides each.  Scanned across 200 generated scripts it flagged only real
absences -- no parse noise.

Warned once per TOOL, not per package (37 packages calling cmake would print
the same three lines 37 times), with a block under the plan naming every
missing driver, how many packages want it, and one command to install them
all.

Fixes a hole 1.14.8 opened as well: `_warn_unset_env` lived only on the
freshly-generated path in resolve_script, so pre-generating a plan in one pass
skipped it.  Both checks are now `_check_script_prereqs`, called for a script
whether it was just written or came from the cache -- they belong to USING a
script, not to writing one.

## One book load, not one per package  (1.14.8)

Reported from a real chroot: a 151-package plan printed

    cached script is from blfs 1.14.3, this is 1.14.7 -- regenerating

twice, then sat silent for five minutes and was killed.

`resolve_script` generates ONE SCRIPT PER PACKAGE, each a `blfs script`
subprocess that loads and indexes the whole book again.  With a warm cache
that is ~0.2s each; on a fresh system, where the first call indexes a 25MB
book, it is the difference between a wait and a hang -- and it presented as a
hang, because the output was one line per package with all the work between
the lines.

`blfs script` has ALWAYS taken `nargs="+"` and used only `_t[0]`.  It now
writes every target from one book load (5 packages: 1.14s as separate calls,
0.27s in one), and `_prewarm_scripts` generates everything a plan needs in a
single pass before the plan is printed, announcing the count first.  A local
script in a package user's home still wins and is never touched.

Also fixed, same family as 1.14.7: `_warn_unset_env` asked `os.environ` only.
After `packagemanager env --set XORG_CONFIG=...` every Xorg package in the
plan was still announced as missing it -- and the cure it printed, `export`,
is exactly the one that cannot work, since `su -` drops the caller's
environment.  It now reads /etc/pkgusr/build.env, the file the build actually
reads, and prints the command that writes there.

That is three bugs in two releases from the same root: a value has one home
(/etc/pkgusr/build.env) and several readers, and each reader had its own idea
of where to look.

## The build environment has to reach the build  (1.14.7)

The end of the util-macros report, and the actual cause of all of it.  The
person ran

    packagemanager env --set XORG_CONFIG=...

was shown it written to /etc/pkgusr/build.env and echoed back in the table,
and the very next command still stopped with "this package needs XORG_CONFIG
to be set".

lfs-helper's `run_phase_as` pastes `build_env_pairs` in front of the command
it runs, so the pm-install path had this right.  packagemanager's
`script <phase>` path builds its OWN `su` and passed nothing -- it set
variables in subprocess's `env`, and `su -` starts a login shell that drops
them.  So a file written by one command was honoured by one of the two paths
that run builds.

Now the same pairs go INSIDE the command (`env K='v' ... bash install_x
build`), single-quoted, which is the trap `build_env_pairs` already documents:
XORG_CONFIG is a flag list, and unquoted it split into words with the second
run as a command.  The header line also names what was applied and where it
came from, so a missing variable is visible before the build starts rather
than after it fails.

Two tools, two implementations of "run a phase as the package user", is what
allowed this.  Worth collapsing: `packagemanager script` should call
`lfs-helper run_phase_as` rather than reimplement it.  Not done here -- it
touches the phase records and the log plumbing too -- but this is the second
bug from that split (the first: phase records, 1.11.55).

## A failure has to say where  (1.14.6)

Continuing the util-macros report.  Its build had stopped for a missing
XORG_CONFIG, so the source was unpacked and unconfigured.  Running the install
phase then gave, in full:

    make: *** No rule to make target 'install'.  Stop.
    !! phase 'install' FAILED (exit 2)
    phase 'install' failed for p_util-macros (exit 2).
      logs: /usr/src/pkgusr/p_util-macros/log

The package's own words for "there is no Makefile", and nothing else: not
which of the three copies of the script had run, not the file the person is
told to edit, not the source directory, not the actual reason.  The user's
words: "we do not even tell the user the file path".

Two halves.

The RUNNER now records that a build FINISHED (`.pkgusr-<nv>.built`, written
only on a zero exit) separately from where it finished (`.cwd`, written even
on failure so a retry can resume).  A later phase with no such record says so
before the package's tools fail in their own vocabulary -- a warning, not a
refusal, because a tree built by an older runner has no record either and
refusing there would be wrong.

packagemanager's report names `ran`, `edit`, `source`, `logs` and `retry`,
and for install/configure/test adds that no later phase can stand in for a
build that never finished.  `_versioned_script_in` finds the editable
install_<name>-<version> (not the copy, not a .edited backup) and
`_unpacked_source_dir` the tree, so the three files a person has to tell
apart are named for them.

## One package, several filenames  (1.14.5)

Reported from a real chroot.  util-macros had unpacked and built; the retry
of just the install phase said

    !! no unpacked source in /usr/src/pkgusr/p_util-macros/src

with the unpacked source sitting right there.

1.14.0 named the build markers from `$0`.  This project runs ONE script under
three filenames by design -- the book copy (install_util-macros-1.20.2), the
staged copy (install_util-macros) and the account's copy
(install_p_util-macros), and the failure box says so itself.  Unpack recorded
`.pkgusr-install_util-macros.dir`; install looked for
`.pkgusr-install_p_util-macros.dir`.  The old scaffolding keyed markers to the
PACKAGE (`.cc-dir-<name>`, `.pm_build_cwd`), which is why this never happened
before -- a regression introduced by taking an identity from the wrong place.

Markers are now `.pkgusr-<name_version>.{dir,cwd}`: name_version is in every
copy of the script and is the same in all of them.

And `_pp_enter_source` no longer gives up when the marker is missing.  It
looks for `$BUILD_ROOT/$name_version`, and failing that for a single unpacked
directory, before saying "run unpack" -- which is the wrong answer when the
tree is in front of it, and for a big package throws away a compile that
succeeded.  Markers written by 1.14.0-1.14.4 are recovered this way rather
than being re-unpacked.

`clean_stale_source` clears `.pkgusr-*` by glob now: the build root belongs to
one package, so whatever is in it is that package's, under whichever naming.

## The last thing you see cannot be the thing that breaks  (1.14.4)

Reported from a real build.  util-macros stopped because XORG_CONFIG was not
set, the box diagnosed it correctly, printed the one command that fixes it,
and then:

    ! Edit the script, then retry just this phase:
    /usr/bin/lfs-helper: line 5596: _retry: unbound variable

`$_retry` -- the account name a retry command has to use -- was computed
INSIDE the permission-failure branch and used by three hints outside it.
Under `set -u` every failure that was NOT a permission problem crashed the
reporter on the line telling you how to retry.  It has been there since
1.12.30, hidden because the branch that sets it is the common case.

Now resolved once, before any hint runs.  The regression test builds the
reporter into a standalone function and runs it under `set -u` against six
kinds of log -- env-var, permission, compile error, missing program, missing
library, and one it does not recognise -- asserting no crash and a retry
command in each.  That is the shape to keep: a diagnostic path is code, and
the only code guaranteed to run on a bad day.

Also quieted: `add_package_user` takes no home argument, so every account it
creates lands in /usr/src/<name> and is moved to /usr/src/pkgusr/<name> a
line later.  That is expected and instantly repaired, but it was reported as

    misplaced home: p_util-macros is recorded at /usr/src/p_util-macros
       every tool looks at /usr/src/pkgusr/p_util-macros

opening every single install with two lines of alarm about a non-problem.
`_repair_misplaced_home` now takes a third argument for "this account was
just created": in that case, and only when the recorded home is exactly
add_package_user's own, it is one dim line.  A misplaced home found any other
way is still a warning -- there it means a real account has been pointing at
the wrong directory for who knows how long.

## The bootstrap circle, explained from where you stand  (1.14.3)

Reported from a real chroot, at `packagemanager bootstrap --run` stage 2:

    wget: there is no BLFS book on this system to look it up in.
      Download it (needs working networking):
          blfs fetch

Told to a system whose entire problem is that it has no download tool.  That
is the circle itself -- fetching needs wget, wget is looked up in the book,
the book is what is missing -- and the advice was to go round it once more.

The cause is one step earlier and on the other side.  lfs's
`bootstrap_sources()` asks `packagemanager bootstrap --sources`, which
resolves wget's URL FROM THE BOOK (`blfs sources wget`).  A host with no
cached BLFS book therefore staged no wget tarball into $LFS/sources either.
Both halves go missing together, from one cause, and the tree cannot supply
either from inside.

Two changes:

- `install-tools` said "BLFS book: (none cached here)" as a dim aside in a
  list of successes.  It is now a `warn` that names the consequence, because
  it IS the later failure, announced early enough to fix while there is still
  a network.
- The no-book message asks what this system can actually do.  With a download
  tool: fetch or import, as before.  Without one: the recovery is on the
  HOST, both halves in one trip, and it says which of them is really absent
  rather than letting them be discovered one at a time.

The general shape, and it has come up before: advice has to be answerable
from where the person is standing.  A remedy that requires the thing that is
broken is not a remedy.

## Silence is not progress  (1.14.2)

Reported mid-build, at chapter 8 GCC:

    ===== [37/106] gcc =====
    # user   : p_gcc (package user)   phase: all

...then ten minutes of nothing, one bash process holding a core, and no child
process at all.  Between those two lines sits exactly one thing:
`_claim_earlier_stages`, which takes over the files an earlier stage of the
same package left behind.  It forked three or four times PER PATH -- a
command substitution for `strip_host_prefix`, a `stat`, a `chown` -- across
every earlier stage's manifest.  For GCC that is gcc-pass1 + gcc-pass2 +
libstdcpp, and it prints nothing until it is finished.

Measured: 3,000 paths took 9.3s the old way and 0.08s now -- one `stat` and
one `chown` for the whole manifest, batched through `xargs`, with the
owner filter moved into an `awk` that reads the batch.  Semantics are
unchanged: a path another package owns is still left alone, and a path
already owned by the account is still not counted.

Two things this also fixed: `libstdcpp` was never in the list of earlier
stages (chapter 5 builds "Libstdc++ from GCC", and `pkg_owner_name` maps it
to the gcc account), so those files stayed root-owned; and the step now says
what it did.

The lesson is the one in the title.  A step that can run for minutes has to
say it started, not only that it finished -- `detail` before the work, not
`say` after it.

## A fresh build on a host we built  (1.14.1)

Reported from a real fresh build, on the user's own LFS machine:

    root ~ # lfs run
    You are inside the LFS chroot, where `lfs build-system run` does not apply.

It was not.  `inside_chroot()` fell through to its last-resort inference --
"/usr/src/lfs-pkgusr exists AND /mnt/lfs/usr/src does not" -- and both halves
were true on the host: the machine was BUILT by these tools, and the freshly
mounted partition was still empty.

1.11.x had already fixed the first half of this ("an inference that is true of
the destination cannot identify the journey") and added `LFS_IN_CHROOT`.  The
guard bolted onto the old inference was the part that stayed wrong, and it
failed at the one moment the inference is consulted at all: before a build has
put anything in the tree.

The kernel knows.  A chroot IS a root that is not PID 1's, so
`_root_differs_from_pid1()` compares `/` with `/proc/1/root` and answers
outright.  Order: `LFS_IN_CHROOT`, then the kernel, then (only when the kernel
cannot be asked -- no /proc, or not root) `$LFS`, then the inference, now
against the CONFIGURED mount point rather than a hardcoded `/mnt/lfs`.

Being wrong toward "inside" blocks a host; being wrong toward "outside" fails
later with a message about the real problem.  So the fallbacks all lean
outside, and only `LFS_IN_CHROOT` or the kernel can say "inside".

## The runner moved out of every script  (1.14.0)

A generated install script was ~230 lines for five lines of book commands:
source lookup, the symlink farm, the unpack, a heredoc-per-phase trick, build
markers, the dispatcher and its usage text -- emitted by FOUR generators
(`_crosschain_script_body`, `_plain_root_script`, blfs `render_script`,
packagemanager `_TEMPLATE`) in three dialects, and text-patched by
`_chrootify` for the chroot.  Every consumer then grepped for a piece of that
scaffolding (`#### CONFIGURE ####`, `.cc-build-*`, `.pm_build_cwd`).

Now a script is its variables at the top, one function per phase
(`prepare_pkg`, `build_pkg`, `install_pkg`, `configure_pkg`, `test_pkg`), and
one last line:

    . "${PKGUSR_LIB:-lfs-phases}" && pkgusr_run "$@"

`lfs-phases` is the shared runner.  It ships with the tools (Makefile,
`TOOLCHAIN_SCRIPTS`, `PKGUSR_TOOLS`), is copied into the store for the host
`lfs` user, and is found on PATH or through `PKGUSR_LIB`.  What it keeps from
the old scaffolding, and why:

- **Each phase is its own process.**  bash disables `set -e` inside any
  function reached from a tested context and subshells inherit that, so a
  failing make was silently ignored (the day-long bug).  The runner re-executes
  the script itself as `PKGUSR_PHASE=build bash script </dev/null`; the phase
  then runs at top level under `set -e`, and stdin is closed so a book command
  that reads it (Expect's PTY check) swallows nothing.  This is why a script
  must be run BY PATH: `cmd_bs_crosschain` no longer pipes it through
  `bash -s`, and the runner refuses stdin with a message.
- **`pkgusr_stage`** (`cross` | `chroot` | unset) replaces `_chrootify`'s text
  patching: it decides `$LFS`, `$LFS_TGT`, `/tools/bin` on PATH, and the
  defaults for `SOURCES_DIR` / `BUILD_ROOT`.
- **One marker pair**, `.pkgusr-<step>.dir` and `.pkgusr-<step>.cwd` in
  BUILD_ROOT; `clean_stale_source` and `clean-sources` sweep both the new and
  the old names.
- **Function bodies are not indented.**  The books are full of heredocs and
  an indented terminator is no terminator.  A body of comments alone gets a
  `:` -- bash rejects an empty function.
- **The phase names keep their `_pkg` suffix.**  `install` is coreutils and is
  called inside install phases; `test` is a builtin.
- **Sourcing a script does nothing.**  pm-install sources scripts for their
  metadata; `pkgusr_run` returns when `BASH_SOURCE[1]` is not `$0`.  Every
  name in the runner carries a `pkgusr_`/`_pp_` prefix because it comes along
  into the sourcing shell.

Consumers that changed: `script_phases_of_file` and `lfs install --reinstall`
look for `^configure_pkg()` (the marker still recognised for old scripts);
`_version_from_script` now reads `name_version=` -- it read a `# package:`
comment no generator ever wrote, so every pkgusr.info `version=` was empty;
`run_phase_as` names a missing runner in one message instead of letting `su`
report it; the test switch is `PKGUSR_TESTS=1` (`LFS_RUN_TESTS`/`PM_TEST` still
accepted); packagemanager's stack generator fills function bodies and
`extract_phase_cmds` reads them.

Two bugs the old scaffolding hid, fixed here because they surfaced the moment
it was gone: blfs's `_repair_dangling_operators` ran before five later
commenting filters, so a body ending `cmd &&` + commented line was a syntax
error in install_pkg (cachecontrol and 145 others failed `bash -n` under the
OLD generator too -- in build_pkg the trailing `&&` chained into the
scaffolding's `pwd > .pm_build_cwd` line and passed by accident); and the
BLFS mirror of last resort was the literal `13.0`, now `pkgusr_book_mirror`
from the book file's name.

Formats: lfs v18, blfs v17.  Old scripts are self-contained and keep working;
`--regenerate` writes the new shape.  Every LFS package (81) and every BLFS
page (954) in the 13.0 books renders, parses and sources.

## stdout is the return value  (1.13.69)

1.13.68's new messages made the real cause readable at last:

    chgrp # /usr/share/gstreamer-1.0/presets is inside /usr/share/gstreamer-1.0,
    which is shared through nimgnu_gst\n#   -- using that group\nnimgnu_gst
    /usr/share/gstreamer-1.0/presets FAILED

choose_collector_group ANSWERS on stdout.  1.13.46 added two explanation
lines with plain `say`, so the caller captured the whole paragraph as the
group name and chgrp failed on it -- silently, which is why it read as
"nothing to grant" for six rounds.  The prompt body was always safe: it lives
inside a `{ ... } > /dev/tty` group, for exactly this reason.

Both lines now go to stderr, and the suite captures the function's output and
requires it to be a bare group name.

THE LESSON, and it is mine to keep: the bug was introduced by a FIX (1.13.46,
inheriting the ancestor's group -- which was correct and the user's idea) and
then hidden by the silence of the code around it.  Every one of the six
rounds added a message; the round that added the RIGHT message solved it.
When a repair is silent, make it speak before changing what it does.

## The prompt could not run, so nothing was chosen  (1.13.68)

FOUND IT.  The same failure appeared on a new directory
(/usr/share/gstreamer-1.0/presets, owned by p_gst10-plugins-good) after the
user fixed the first one by hand -- same shape, same "nothing to grant".

choose_collector_group PROMPTS when the group does not exist yet.  During a
build stdin is not a terminal, so the prompt cannot run and the function
returned NOTHING.  Then:

    chgrp "" /usr/share/gstreamer-1.0/presets     -> fails
    grant_dir_access                              -> return 1, no message
    the loop                                      -> "nothing to grant"

Two fixes, both about not being quiet:
  * an empty name falls back to the OWNER-NAMED group (the recommended answer
    anyway) and says why: "could not ask ... (no terminal here) -- using
    nimgnu_gst10-plugins-good, named after its owner";
  * a failed chgrp reports itself, with `getent group` to check.

Six rounds on this one package, and the cause was a prompt in a place that
cannot prompt.  1.13.33 made --yes stop answering name questions -- correct
for a person at a terminal, and it left the BUILD with no way to answer at
all.  Worth re-reading every prompt for "what happens when nobody can
answer": the answer must never be "nothing".

## Extras last, except when they are dependencies  (1.13.67, cont.)

Adding the WebRTC chain broke a rule this session had made: 1.12.75 put all
git entries LAST so --no-git could skip the extras.  libnice and friends are
git entries that must come FIRST, because gst-plugins-bad compiles webrtcbin
only if libnice is present.

Two corrections:
  * the invariant is that nothing after the extras MARKER is a book entry --
    not that no git entry may precede a book one;
  * `--no-git` now says what it costs when it skips them:
        NOTE: libnice, libsrtp, usrsctp, webrtc-audio-processing are skipped,
        and gst-plugins-bad / webkitgtk link them.  Built without them there
        is no WebRTC ... adding them later means recompiling both.

Which matters immediately: the user has been running --no-git all session.

## WebRTC has to be decided before the build  (1.13.67)

The user asked whether streaming support can come later.  It cannot, cheaply:
webrtcbin -- the element a browser uses for WebRTC -- is compiled into
gst-plugins-bad ONLY if libnice is present, and webkitgtk links the result.
Adding it afterwards means recompiling both.

BLFS 13.0 carries NONE of the pieces, so they are git entries, placed before
gst10-plugins-bad and webkitgtk:

    libnice                  ICE / NAT traversal -- WebRTC cannot work without it
    libsrtp                  encrypted media transport
    usrsctp                  data channels
    webrtc-audio-processing  echo cancellation (the log's "found: NO")

The camera side was already there: v4l-utils for the device, pipewire for
routing.

UNTESTED: the build lines follow each project's README and none has been
built here.  Two things learned writing them:
  * `git` entries must be ONE line -- the parser has no continuations
    ("No escaped character" at the first backslash);
  * `prog=false` as a placeholder made all four report themselves INSTALLED,
    because `false` is a real program.  The suite now rejects it, and checks
    that libnice precedes the two packages that link it.

STILL OPEN, and worth saying plainly: BROWSER SCREEN SHARING on Wayland goes
through xdg-desktop-portal, which this desktop avoids.  Camera capture and
playback do not need it.  If screen sharing is wanted later, the portal and
its wlr backend are the addition -- and that one CAN be added afterwards
without recompiling anything.

## Interactive, like the others  (1.13.66)

Per the user: every config command should have an interactive mode.  Two
already did -- `packagemanager config` asks for what is missing, and
`packagemanager env --ask` walks the build variables.  The one that did not
was the one a person most needs to set deliberately: the NEW SYSTEM'S.

    lfs config --target --ask
      prefix for package users in the new system (p -> p_mesa; empty -> mesa)
        pkgusr_prefix    [this host's value]: p
      folder under the base for package homes (pkgusr)
        pkgusr_subdir    [this host's value]: packages

Enter keeps the current value, '-' clears it (which MEANS none, and is shown
as "(none)" afterwards -- the absent/empty distinction from 1.13.64).  Each
key is explained where it is asked, rather than in documentation nobody has
open at that moment.

REMAINING for the unification: `lfs config` itself (the session keys) is
interactive only through `lfs build-system session --run`.  Once the storage
is unified (1.13.56), all four should offer the same three modes -- show, set
one key, walk them all -- with the same layout.

## A config for the build system, written before it exists  (1.13.65)

The user's request, and it was the missing piece: a file on the HOST that IS
the new system's config, so it can be configured before there is a tree to
configure -- and `lfs run` copies THAT in rather than the host's own
settings.

    /usr/share/lfs/target-config.json

    lfs config --target                      # show it
    lfs config --target pkgusr_prefix p      # set a key

Precedence, printed where it is applied: the host's session config is the
floor, target-config.json overrides it, and a config the TREE already has
wins over both -- it is the system's own choice, made after that file was
written.  `lfs run` lists what it took from the target config as it copies.

Laid out like `packagemanager config --show`: the file, then value and
source.  That is the first step of the user's second request -- ONE LAYOUT
AND ONE VOCABULARY for the config commands across all four tools.  The rest
belongs with the unification proposed under 1.13.56: while the shared keys
still live in two files with precedence rules, the commands cannot be made to
look alike without lying about which file wins.  Do that first, then align
`lfs config`, `lfs config --target`, `packagemanager config --show` and
`packagemanager env` on the same shape.

## Which config is which, and an empty prefix  (1.13.64)

The user asked whether /usr/share/lfs/config.json is the build system's
config.  It is not, and the distinction matters:

    /usr/share/lfs/config.json            the HOST's -- drives the build
    /mnt/lfs/usr/share/lfs/config.json    the BUILT system's -- decides for it
                                          once it exists (1.13.51/63)

The session shows the host's, correctly (it holds the device, the mount, the
makeflags).  What it also holds is the prefix the build will CREATE ACCOUNTS
with -- and on this machine that is now empty, because the user emptied it
on the host.  With no tree config yet, nothing overrides it.

"(unset)" read as "nothing chosen yet" when it was an empty value on
purpose.  The two are now distinguished:

    pkgusr_prefix    = (none -- accounts will be named without a prefix)
    pkgusr_prefix    = (unset -- will ask)

Third time this exact ambiguity has cost a round (1.13.26 the reader,
1.13.63 the source, this the display).  Anywhere a setting may legitimately
be empty, ABSENT AND EMPTY MUST LOOK DIFFERENT.

## The session config took the host's prefixes  (1.13.63)

    Session config:
      pkgusr_prefix    = (unset)

That is the empty prefix the user had just set on their HOST, in the session
that creates the accounts of the NEW system.  1.13.51 stopped the host's
prefixes reaching the chroot's environment; this is the same leak one step
earlier, in the session config itself -- and it would have named every
account of the build system after a decision made on a different machine.

A tree that already has a config now decides its own prefixes there, and
says so:
      pkgusr_prefix    = p   <- from the tree's own config

And the header names the file, because "which config is this?" was exactly
the question that could not be answered:
    Session config:  (/usr/share/lfs/config.json)

Two leaks found by the user asking the same question three ways.  Worth
asking it of every place that reads a shared key: WHOSE value is this, the
machine I am on or the machine I am building?

## A retry hint that cannot work  (1.13.62)

The user asked whether the script-version warning had been the cause all
along.  No -- and the question was fair, because our own failure box sent
them there:

    !   lfs-helper build gst10-plugins-bad --phase all --force
    !! no script for 'gst10-plugins-bad' at .../scripts/gst10-plugins-bad.sh
    !! These build scripts were generated by 1.12.30 ...

`lfs-helper build` takes the ACCOUNT (p_gst10-plugins-bad).  The box printed
whatever name it was called with, and for a BLFS package that is the anchor,
so the command fell through to the LFS BASE-STEP path and blamed chroot step
scripts that have nothing to do with BLFS packages at all.

The box now resolves the name to a real account before printing it.

THE ACTUAL CAUSE of that package, for the record: /usr/include/gstreamer-1.0/
gst/audio was group p_gst10-plugins-base (mode 775) and the installing
package is in install, nimgnu_gir and nimgnu_gst -- not in that group.  The
user fixed it directly:
    chgrp nimgnu_gst .../gst/audio && chmod g+w .../gst/audio
which is exactly what grant_dir_access should have done: its parent gst/ is
already nimgnu_gst.  It reported "nothing to grant" instead, so ONE of its
six early returns fires wrongly.  NEXT SESSION, FIRST TASK: run it under
`bash -x` and find which -- five patches to that function were made from log
text and three of them addressed cases that were not happening.

## The directory was never the problem  (1.13.61)

One line of new output ended five rounds of guessing:

    /usr/include/gstreamer-1.0/gst/audio -- nothing to grant (already writable)

The package CAN write there.  What it cannot do is finish installing over a
FILE owned by another package: meson copies the contents (the directory is
writable) and then chmod/chown/utime the destination, which only its owner
may do.  Python raises EPERM; meson prints "Unhandled python OSError" with no
path; and for five rounds that looked like a directory-permission problem
because that is the only class the repair knew.

It is the same shape as tar's "Cannot change mode" (1.13.35) -- and the same
answer as the rest of this system: OWNERSHIP FOLLOWS THE INSTALLER.
meson_takeover_from_log hands the files a package is installing over to that
package, using meson's own "Installing SRC to DIR" lines to know which.
root's files are never taken.

The lesson worth keeping: the repair had ONE explanation for a failure and
kept applying it.  The fix that mattered was 1.13.60's -- making it say what
it decided -- because that is what turned a guess into a diagnosis.

## A group on a leaf is no use if the chain is closed  (1.13.60)

The user's own `ls` chain, and their conclusion, were the fix:

    /usr/include/gstreamer-1.0/gst/        p_gstreamer10:nimgnu_gst    drwxrwxr-x
    /usr/include/gstreamer-1.0/gst/audio   p_gst10-plugins-base:...    drwxrwxr-x

"isn't it normal that a collector group will not work without its parent?  so
why not directly set it until we get to an accessible parent" -- yes.
grant_dir_access now walks UP from the directory it is granting and makes
each ancestor searchable, stopping at the first one that already is.  Search
happened to be open in this tree, but a package that tightens its own
directory would break everything installing below it.

AND, the reason four fixes were made by guessing: the grant loop printed a
header and then NOTHING when every candidate was skipped, so a failing
package looked like a repair that had never run.  Every candidate now reports
its outcome, including "nothing to grant (already writable, or not a
directory)".

If gst-plugins-bad still fails after this, the output will finally say which
directory was considered and what was decided about it -- which is what the
last four rounds were missing.

## Grant every destination meson announced  (1.13.59)

The plan was "the wrapper that fails records the directory".  It cannot:
MESON INSTALLS THROUGH PYTHON, not through install/cp/mkdir, so nothing on
our side ever sees the EACCES.  That is why four rounds of log-parsing were
needed and why the fifth would have been too.

What meson does give us is every destination it ANNOUNCED before dying.
Granting all of them settles the package in one round instead of one round
per header directory, and costs nothing: grant_dir_access now returns
immediately for a directory the package can already write (`su -c "test -w"`),
so the package's own directories and shared ones it already belongs to are
skipped rather than growing new groups.

    Installing ... to /usr/include/gstreamer-1.0/gst/uridownloader
    Installing ... to /usr/include/gstreamer-1.0/gst/audio
    ERROR: Unhandled python OSError
      -> both granted, one round

STILL TRUE for the wrapper-based builders (make/install/cp): recording the
directory at the point of failure would beat parsing, and those DO go through
our wrappers.  Worth doing for them -- but meson needed the other answer, and
meson is most of BLFS now.

## One grant per directory, not per tree  (1.13.58)

    auto-repair: rounds run: 2
    /usr/include/gstreamer-1.0/gst/audio  drwxrwxr-x p_gst10-plugins-base

The repair ran twice, granted something each time, and the build failed on
the same directory.  The dedup was the bug: it collapsed every failing path
to the top of its tree, so once ONE directory under
/usr/include/gstreamer-1.0 had been granted, every other directory under it
was skipped -- including the one that failed.

A collector group applies to the directories it is put on -- the prompt says
exactly that -- so each distinct directory needs its own grant.  The problem
the tree-top dedup was written for (the same directory named by nine
different paths) is solved by deduping on the directory itself.

FOURTH fix to this one repair path tonight: relative paths (1.13.36),
meson's wording (1.13.49), the ancestor's group (1.13.46), and now the dedup.
Every one was a patch to reconstructing information the BUILD already had.
The design note stands: the wrapper that fails should record the directory it
failed on, and the repair should read that instead of parsing prose.

## Flags for the layout  (1.13.57)

The directories became configurable in 1.13.52/53 and could still only be
changed by editing a file:

    packagemanager config --base-dir /usr/src
    packagemanager config --pkgusr-subdir packages
    packagemanager config --cfguser-subdir config

with the prefix guard's twin -- moving the layout does not move the homes:

    account homes already exist under the current layout:
        /usr/src/pkgusr  (37 entries)
      Changing the layout does NOT move them.  Every tool would look in the
      new place and find nothing.

Also: the report named /usr/share/lfs/config.json whatever it had actually
read.  It names the real file now, which matters as soon as LFS_STORE points
elsewhere -- and pointed at the wrong file while explaining where settings
come from.

## Saved where nobody reads  (1.13.56), and the config question

    packagemanager config --pkgusr-prefix ""
      pkgusr_prefix -> '(no prefix)'
      Saved /etc/pkgusr/packagemanager.conf
    packagemanager config --show
      package-user prefix  p_   the lfs config (/usr/share/lfs/config.json)

The setter wrote one file; the reader reads the other.  Nothing changed and
it said Saved.  _save_shared_key() now writes the AUTHORITATIVE file (the lfs
config, when it exists) and says which file it wrote.

### THE DESIGN QUESTION THE USER ASKED -- worth doing properly

"Is there even a good reason for those different config paths?"  No.  It is
history: `lfs` has its store (config.json, travels with the tree) and
packagemanager has its own file, and the SHARED keys ended up in both with
precedence rules.  Every config bug this session came from that:

  * an empty prefix from the environment beating the config (1.13.26)
  * the host's prefix baked into the chroot's exports (1.13.51)
  * the layout readable from one file only (1.13.52/53)
  * a setting saved where nobody reads it (this)
  * and `--show` needing a "source" column at all, to explain the mess

PROPOSED, for a fresh session:
  * /usr/share/lfs/config.json is the ONLY home for system-level settings:
    the prefixes, the layout, the books, the device/mount.  It travels with
    the tree, which is what makes a build system's config its own.
  * /etc/pkgusr/packagemanager.conf keeps only what belongs to the person
    using the tool on this machine: editor, difftool, main_user.
  * packagemanager reads the lfs config directly (it already can) and stops
    duplicating those keys; the precedence rules disappear with them.
  * the environment stays as an override for one-off runs, and `--show`
    keeps the source column for exactly that reason.

That is a contained change -- one reader, one writer, one file -- and it
removes a whole class rather than the five instances above.

## purge deleted the wrong name and said it worked  (1.13.55)

    $ userdel mako
    mako purged.
    $ grep p_mako /etc/passwd
    p_mako:x:10764:10767:p_mako:/usr/src/pkgusr/p_mako:/bin/bash

`remove --purge mako` uninstalled 85 files, removed the home, ran `userdel
mako` -- an account that does not exist -- and reported success.  The system
was left with an account owning nothing and a report saying otherwise.  (The
1.13.19 fix corrected the passwd LOOKUP in the same function and missed the
delete.)

Now: the account name is used, a failed userdel is reported, and the final
message checks what actually remains:
    mako: files removed, but the account p_mako, /usr/src/pkgusr/p_mako
    remain -- NOT fully purged

For the user's host right now: p_mako is still there and can be removed with
`userdel p_mako`.  After that the tree has no package users and
`config --pkgusr-prefix ""` will be accepted.

## A flag for the prefix, and a refusal  (1.13.54)

`config` could set the collector and user prefixes but NOT the package-user
one -- the only way was editing config.json by hand, and it is the one
prefix whose change orphans every account on the system.

    packagemanager config --pkgusr-prefix ""
    packagemanager config --cfguser-prefix cfg

and, when accounts already use the current prefix, a refusal that says why:

    2 account(s) already use the 'p_' prefix: p_gcc, p_wget
      Changing it now does NOT rename them.  Every tool would look for
      accounts named '<none>' and find nothing: the packages would read as
      not installed, their manifests would orphan, and a rebuild would make
      a second set.
      If you are certain (a fresh tree, or you will rename them yourself):
        packagemanager config --pkgusr-prefix '' --force

The user asked for exactly this safety before making the change, which was
the right instinct: on their HOST the accounts are p_*, so the answer is
that the change belongs on a fresh tree, not that one.

## Say what the keys are, and mean it  (1.13.53)

The user ran `config --show` after 1.13.52 and saw no difference -- correctly.
The values were unchanged (nothing had been set), and the FOOTER still said

    set a directory: export PKGUSR_BASE / PKGUSR_SUBDIR / CFGUSR_SUBDIR

which was true before the keys existed and stale afterwards.  A report that
does not mention the thing that changed looks like nothing changed.

It now lists the actual keys in both files.  Writing that text also caught
that the claim was not yet TRUE: _early_conf read only packagemanager.conf,
so the layout could not travel with the tree.  It reads the lfs config first
now, as the prefixes do -- verified from both files, with the environment
still winning over both.

The lesson, again: when adding a setting, the place that TELLS people about
settings has to change with it -- and writing the sentence is a good way to
discover the code does not do what the sentence says.

## The directories are configurable too  (1.13.52)

The last leak from 1.13.50/51: BASE_DIR has read `pkgusr_home` from
packagemanager.conf for a long time, but the two SUBDIRECTORIES were
environment-only.  A tree with a different layout therefore depended on the
environment being right on every invocation, and could not be made
tree-specific the way the prefixes now are.

    pkgusr_subdir=packages
    cfguser_subdir=config

are read from packagemanager.conf now (environment first, then the file, then
the default -- as everywhere else), reported by `config --show` with their
source, and added to the keys that travel with the tree.

So the whole answer to the user's question is now: the build system has its
own prefixes AND its own layout, set once, and the host cannot overwrite
either.

## The build system's config is its own  (1.13.51)

The user asked whether the host's config gets copied into the build system.
Half of it did not (config.json has been MERGED since an earlier fix -- host
values only where the tree is silent).  The other half did:

    export LFS_PKGUSR_PREFIX="{pkgusr_prefix()}"

written into the chroot scripts, evaluated in the HOST process.  So a prefix
changed on the user's own machine was baked into the build system's
environment -- and that is exactly how an empty LFS_PKGUSR_PREFIX reached a
chroot whose config says "p" (see 1.13.26, which treated the symptom).

_tree_prefix() reads the TREE's config for those exports; the host's value is
only a fallback for a tree that has not been configured yet.  Verified all
three cases.

So the answer to the question: yes, the build system can have its own
prefixes and directories, and after this they stay its own.  The one
remaining leak is the DIRECTORIES, which have no config keys at all and are
environment-only -- the open item from 1.13.50.

## Where the prefixes and directories actually live  (1.13.50)

The user tried to check their prefixes and the package directories and could
not find them.  Fairly: prefixes came from /usr/share/lfs/config.json, then
packagemanager.conf, then the environment, then a default -- and the
DIRECTORIES were environment-only (PKGUSR_BASE, PKGUSR_SUBDIR,
CFGUSR_SUBDIR), documented nowhere.  `packagemanager config` existed but
PROMPTED for the main user before printing anything, and showed neither the
package prefix nor any directory.

`packagemanager config --show` prints the lot, with the source of each:

    package-user prefix  p_               the lfs config (/usr/share/lfs/config.json)
    config-user prefix   cfg_             the built-in default
    collector prefix     nimgnu_          packagemanager.conf
    shared-user prefix   u_               the built-in default
    base directory       /usr/src         the built-in default
    package homes        /usr/src/pkgusr  $PKGUSR_BASE/$PKGUSR_SUBDIR
    config-user homes    /usr/src/cfg     $PKGUSR_BASE/$CFGUSR_SUBDIR

...and how to change each, with the warning that a prefix is a decision taken
before the first account.

STILL WORTH DOING: the directories have no config-file keys at all -- they
can only be set by exporting variables, which means a tree built with a
non-default layout depends on the environment being right every time.  They
belong in the same config as the prefixes.

## meson says "OSError" and names nothing  (1.13.49)

    Installing .../gstnonstreamaudiodecoder.h to /usr/include/gstreamer-1.0/gst/audio
    ERROR: Unhandled python OSError.  This is probably not a Meson bug

A permission failure in another package's directory -- the class the
collector-group repair exists for -- and it ran TWO rounds with nothing to
grant, because meson's error names no path.  The directory is on the line
BEFORE it, which is the only place meson puts it.  (The failure box already
worked it out for the human: "what those paths actually are" named
/usr/include/gstreamer-1.0/gst/audio, owned by p_gst10-plugins-base.)

unwritable_dirs_from_log now takes the destination of the last `Installing
... to <dir>` line when an OSError / Errno 13 / Permission denied follows.

Third extractor added for this one repair (absolute paths, a relative path
plus its `cd`, and now meson's).  Each build system reports the same failure
differently, and the repair is only as good as the parsing.

## glycin needs librsvg  (1.13.48)

    ERROR: Dependency "librsvg-2.0" not found

Third instance of one shape: the book RECOMMENDS it, the build REQUIRES it,
and both packages sit inside one strongly-connected component -- so the
cycle-breaking is free to drop exactly that edge (glycin 197, librsvg 206).

    [glycin]
    needs = librsvg
librsvg 205 -> glycin 211, with libass/ffmpeg unchanged.

The three are ffmpeg->libass, mesa->{glslang,rust-bindgen,libclc} and now
glycin->librsvg.  Each was one line, and each was found by a build failing.
The real fix remains the one noted in 1.13.43: inside an SCC, drop the edge
that CLOSES the cycle rather than any recommended edge in it.  Tarjan already
identifies the back-edges; using them would remove this whole class rather
than treating it one package at a time.

## A feature missing from an installed package  (1.13.47)

    Run-time dependency cairo found: YES 1.18.4
    Run-time dependency cairo-ft found: NO
    ERROR: Problem encountered: No Cairo font backends found

cairo is installed and working; it simply has no FreeType backend, because
it was built BEFORE freetype2 existed under an older ordering.  The ordering
is right now (freetype2 112 -> fontconfig 116 -> cairo 117), but a package
already on disk does not rebuild itself.

Nothing detects this class -- a package that is present and less capable
than it should be -- so the failure box now recognises the shape (a
`<pkg>-<feature> found: NO` beside a `<pkg> found: YES`) and says:

    ! 'cairo' is installed, but the feature this package needs is missing
    ! from it -- it was probably built before its own optional dependency
    ! existed.  Rebuild it, then retry:
    !   packagemanager install cairo --run --yes --reinstall

WORTH CONSIDERING: every package built before tonight's ordering fixes may
be missing optional features the same way.  A sweep -- rebuild anything
installed before a dependency it recommends -- would find them, and would be
cheap to compute from the install timestamps we already keep.

## An ancestor's group already answered  (1.13.46)

    /usr/lib/python3.14/site-packages   drwxrwxr-x p_python nimgnu_python
    ...
    Which group should share /usr/lib/python3.14/site-packages/gi/overrides?

The user's point: the enclosing tree is already shared through
nimgnu_python, so a nested directory inside it needs no new decision.
share_new_dir_with_tree_owner has inherited a parent's group since 1.12.44;
choose_collector_group -- the path the auto-repair uses -- never learned it.

It walks up to the nearest ancestor carrying a COLLECTOR group now and uses
that, saying so.  Only collector groups count: root or install on a parent
says nothing about sharing.  With no such ancestor it still asks.

Also visible in that output and NOT chased: "retrying at-spi2-core (phase
all), round 6" -- the auto-repair re-ran the whole phase six times, unpacking
the source afresh each round.  Each round granted one directory.  Granting
all the directories the log names in ONE round would turn six unpacks into
one; worth doing.

## polkit was an orphan  (1.13.45)

    ERROR: Dependency "libsystemd" not found

polkit wanted libsystemd because this is the systemd flavour of the book and
its meson defaults to logind session tracking.  But the user asked the better
question -- do we need it at all? -- and the parent check answered: polkit's
only parents are colord and systemd, both avoided.  A pure orphan, like
colord and linux-pam before it.  Avoided, with libgusb (colord's too).

205 packages.  bluez/pipewire/wireplumber stay: bluez has a live parent
(pipewire).

For the record, had it been wanted: polkit on a SysV system needs
    -Dsession_tracking=libelogind
which is one line in package-fixes.conf.  Not added, because nothing wants
polkit.

The parent check is now the standard move for "do I need this?" and it has
found five orphans (colord, linux-pam, xdg-utils, freeglut, polkit+libgusb).
Automating it needs every edge, which is still the open item from 1.12.83.

## vala wanted Graphviz, not graphite2  (1.13.44)

    configure: error: Package requirements (libgvc >= 2.16) were not met

libgvc is GRAPHVIZ (the user read it as graphite2, which is installed and
fine).  Vala needs it only for valadoc, its documentation generator, and the
book says so: "--disable-valadoc: This option is required if Graphviz is not
installed."  That flag was already in package-fixes.conf -- and I added a
SECOND [vala] section for it, which made configparser raise and the WHOLE
FILE be ignored, silently disabling every fix in it.

Duplicate removed, and the suite now parses package-fixes.conf on every run:
one bad section would otherwise turn off ffmpeg's libass edge, mesa's three
`needs`, cairo's ctime_r and the rest at once, with no message beyond a
single warning line.

(Check the file before adding to it -- the sections have grown past the
point where they fit on one screen.)

## Break inside the cycle, release only the knot  (1.13.43)

libass really was not installed, and the recursive plan put ffmpeg FIRST
(0/32) -- so the sort had dropped ffmpeg's edge to libass.  Two faults, both
in the cycle handling:

  * "fewest blocking dependencies" is not "in the cycle".  It picked ffmpeg
    and dropped its recommended libass edge, while the actual cycle was
    harfbuzz <-> freetype2.  Cycle membership is computed properly now
    (Tarjan's SCC), and only edges with BOTH ends in one component are
    dropped.
  * the required-cycle fallback emitted EVERY remaining node in its original
    order -- one unbreakable knot threw away the ordering of everything
    after it.  It releases just the smallest component now and keeps sorting.

The isolated case sorts correctly (harfbuzz, freetype2, libass, ffmpeg).  In
the FULL book graph ffmpeg and libass still land in one huge component, so
the recommended edge between them remains fair game -- and ffmpeg's configure
hard-requires libass.  So:
    [ffmpeg]
    needs = libass
Order: libass 204 -> ffmpeg 209, with every earlier case intact.

NOTE for next session: a big SCC means the "drop recommended edges inside
it" rule can still drop something a build needs.  The mechanism to declare
the edge required is the safety valve, but a better rule (drop the edge that
closes the cycle, not any edge inside it) would need the cycle's back-edges,
which Tarjan gives -- worth doing properly.

## A one-package plan with missing dependencies  (1.13.42)

    packagemanager install ffmpeg --run --regenerate
    ### Install plan (1 to build)
    ...
    ERROR: libass >= 0.11.0 not found using pkg-config

libass really was not installed (search, pkg-config and the missing .pc all
agreed).  Without --recursive the plan is exactly one package -- correct
behaviour, and the command came from me without the flag.

But the plan KNOWS its dependencies are missing and said nothing.  It now
does:

    2 dependencies of FFmpeg-8.0.1 are NOT installed:
      libass-0.17.4, ...
    this plan builds ONLY FFmpeg-8.0.1 and will fail on them.
    to build them too:  packagemanager install ffmpeg --run --recursive

Worth remembering when suggesting commands: `install <pkg> --run` is only
right for a package whose dependencies are already in place.  For anything
mid-build, the stack run or --recursive is the honest suggestion.

## Half a command is worse than none  (1.13.41)

    install_ffmpeg: line 242: rsync: command not found

`make fate-rsync` was commented (1.13.39) and the standalone fetch beside it
was not -- and worse, the fetch is split over two lines:

    rsync -vrltLW --delete ... \
          rsync://fate-suite.ffmpeg.org/fate-suite/ fate-suite/

Only the SECOND line matched the pattern, so the first stayed active and ran
on its own.  A match on a continuation line now walks BACK and comments the
command it belongs to, and rsync:// fetches count as test-suite work.

STILL OPEN, and the actual build failure: `libass >= 0.11.0 not found using
pkg-config`, with libass recorded as installed.  That is the xorg7-lib shape
again -- a record without the files -- and the user is checking.

## A stale script refreshes itself  (1.13.40)

ffmpeg failed on the identical error one release after it was fixed, and the
box said why: "generated by blfs 1.13.38; the generator is now 1.13.39".

That warning was added in 1.13.4 and has now cost several rounds EACH on
brotli, rust, xcb-utilities and ffmpeg.  The fix existed, the message
printed, and the build ran the old script anyway -- because noticing one
warning in a 200-package plan and acting on it per package is not a
reasonable thing to ask of anyone.

A script older than the generator is now REGENERATED, unless the user has
claimed it: a `# EDITED` line in the file, or an existing .edited sibling,
means hands off (and then the old message appears, with the command).

The 1.13.4 reasoning -- "not automatic, because regenerating discards edits"
-- was right about the risk and wrong about the remedy.  The answer was a way
to say "this one is mine", not making every user do it for every package.

## A typesetting loop, and ffmpeg's fate  (1.13.39)

    You don't have a working TeX binary (tex) installed anywhere in your PATH
    make: *** No rule to make target 'fate-rsync'.  Stop.

Two more in one page:

  * ffmpeg wraps texi2pdf/texi2dvi/dvips in `pushd doc && for ... done &&`.
    The 1.12.87 filter only knew `make ... pdf|ps|dvi`, and commenting just
    the texi2* lines would have left an EMPTY LOOP BODY -- so the block is
    commented as a unit, from the pushd/for that opens it to the done/popd
    that closes it.
  * `make fate` is ffmpeg's test suite, and `make fate-rsync` fetches its
    samples -- tens of gigabytes over rsync -- during an ordinary install.
    Added to the test drivers.

ffmpeg's build is now: configure, make, install.  A loop that does NOT
typeset is untouched.

## Rearranging a directory nothing filled  (1.13.38)

    mv: cannot stat '/usr/share/doc/git-2.53.0/git*.adoc'   -- with 346 files installed

FIFTH in the same family, and the last shape of it in git: after the
optional "untar the html docs" block is commented, the page still
reorganises what it would have extracted, with mkdir/mv chains.

A `mv` (or find/sed) whose directory appears ONLY in commented commands is
moving something nobody produced -- so it is commented, with its chain and
the `mkdir` that led into it.  Two things had to be right for this to work:
a trailing slash must not defeat the match, and mv/find/sed must NOT count as
"filling" a directory (they rearrange it; only tar/cp/install/make fill).

Git's install block is now: `make ... install` and nothing else.  Everything
optional is commented, and 346 files were already installing correctly
before this.

THE FAMILY, for whoever adds the next filter:
    libuv's man page, the orphan log reader, brotli's wheel,
    install-man/install-html, and this.
Ask, every time: WHAT CONSUMES WHAT THIS BLOCK MADE?

## Installing docs nothing built  (1.13.37)

    /bin/sh: line 1: asciidoc: command not found
    make: *** [Makefile:3725: install-man] Error 2

Git's page generates its man pages and html docs under "If you have installed
asciidoc and xmlto you can create ..." -- correctly skipped -- and then
installs them unconditionally.  `make install-man` therefore tried to BUILD
them, after everything else had installed.

An `install-<x>` whose `<x>` nothing active builds is now commented, along
with the rest of its && chain (git follows install-html with mkdir/mv of
files only install-html would have created).  A package that really does
build its docs keeps both lines.

Fourth in this family: libuv's man page, the orphan log reader, brotli's
wheel, this.  The rule to apply when adding any filter: WHAT CONSUMES WHAT
THIS BLOCK MADE?

Also note: `make htmldir=... install-html` needed the pattern to allow
variable assignments between make and the target.  And I broke the edit
twice by patching in place before rewriting the function whole -- the
1.13.31 note about that stands.

## A relative complaint needs the cd above it  (1.13.36)

The log settled it in two lines:

    (cd '/usr/lib/perl5/5.42/site_perl' && umask 022 && tar xof -)
    /usr/bin/tar: ./Git: Cannot mkdir: Permission denied

A permission problem in another package's directory -- the class the
collector-group repair exists for -- and it found NOTHING to grant, because
tar reports "./Git" and every extractor looks for absolute paths.  The
directory that needs granting is named one line earlier, in the subshell's
own cd.

unwritable_dirs_from_log now scans the tail in order, remembers the last
absolute `cd`, and emits it whenever a relative complaint follows.  Verified
on the real two lines: it yields /usr/lib/perl5/5.42/site_perl.

(The 1.13.35 tar wrapper was right and not enough: it correctly tolerated the
utime/mode noise, which then let the REAL error -- three lines later and
about a different directory -- become visible.)

## tar is a wrapped tool too  (1.13.35)

    tar: ./zh_TW: Cannot change mode to rwxr-xr-t: Operation not permitted
    tar: Exiting with failure status due to previous errors
    make: *** [Makefile:3636: install] Error 2   -- with 104 files installed

Git installs its translations by piping through tar, which then stamps the
destination DIRECTORIES: they belong to other packages and are sticky
because we sealed them.  The FILES extracted correctly.

cp has had this exact wrapper for a long time ("preserving times for
/usr/bin: Operation not permitted"); tar was never wrapped.  It is now, with
the same rule: if every complaint is about utime/mode/ownership on something
we do not own, the extraction succeeded; anything else still fails.  Verified
both ways.

Wrapped tools are now: install, chown, chgrp, chmod, mkdir, cp, ldconfig,
tar.  Worth asking what else writes metadata -- rsync, cpio, and `install -p`
are the obvious candidates, and none has appeared yet.

## vulkan-loader needs git  (1.13.34)

    FileNotFoundError: [Errno 2] No such file or directory: 'git'

Its CMake scripts shell out to git to stamp a version.  git IS a stack entry
but sits at the end, and vulkan-loader is built inside another entry's plan,
so it was not there yet.  One line in package-fixes.conf:

    [vulkan-loader]
    needs = git

Order: git 111 -> vulkan-loader 159.

Checked the other fifteen packages in the plan for the same shape -- none of
their SCRIPTS call git; vulkan-loader's call is inside its CMake, which no
scan of the book would ever find.  That is the limit of this class: a
dependency invisible in both the book AND the generated script, findable only
by building.

## --yes answers a question; it does not name things  (1.13.33)

    # granting access via collector groups and retrying:
    #   /usr/include/X11 -> group nimgnu_xorgproto

The user asked why nothing was asked any more.  The prompt was there; --yes
skipped it -- and --yes was in the command this session kept recommending.

The distinction that was missing: reusing an EXISTING group is a yes/no, and
--yes may answer it.  Creating a NEW one is a choice of NAME that stays on
the system, and the user wants to keep making it.  So a run with --yes now
still stops for a group that does not exist yet, whenever a terminal is
available.  With no terminal, the owner-named choice stands and says so --
including "(this CREATES the group X)".

Worth applying the same test elsewhere: --yes should carry decisions whose
answer is obvious afterwards, not decisions that leave a name behind.

## ...and the build must resume where they left off  (1.13.32)

1.13.31 got the downloads running -- 32 tarballs, all md5-verified -- and the
build loop still said

    grep: ../lib-7.md5: No such file or directory

The page does `mkdir lib && cd lib`; the build phase is a separate function
that starts at the build root, so `../lib-7.md5` pointed nowhere.  unpack now
records that directory in .pm_build_cwd (the mechanism already existed for
resuming a build) and _enter_build returns there for a meta page.

AND THE SECOND HALF, which is the one that mattered: a loop over a missing
list runs zero times and exits 0, so the package was RECORDED as installed
having built nothing.  Every `for x in $(... ../file ...)` now gets

    [ -s "../lib-7.md5" ] || { echo "the list this build loops over is
      missing or empty: ../lib-7.md5" >&2; exit 1; }

That was the "loop that runs zero times is not a success" item from 1.13.31's
notes; it took one release rather than a session because the shape was
already written down.

## A meta page's own commands must run  (1.13.31)

    grep: ../lib-7.md5: No such file or directory
    # xorg7-lib installed no NEW files ...
    # xorg7-lib: done          <- RECORDED AS INSTALLED

The meta-page early return (1.12.61) sat ABOVE the page's own Downloading
section, so Xorg Libraries never wrote lib-7.md5 nor fetched its list.  The
build loop read a file nobody had created, iterated zero times, and exited 0
-- which is how a package that installed nothing got recorded, twice.

The page's own commands are emitted BEFORE the early return now.  A normal
package is untouched (one tar -xf, as before), and nine pages including the
three meta ones generate valid bash.

TWO THINGS FOR NEXT SESSION, both exposed here:

1. A LOOP THAT RUNS ZERO TIMES IS NOT A SUCCESS.  `for x in $(grep ... file)`
   exits 0 when the file is missing.  The recorder trusts rc==0 (1.12.7), so
   an empty meta build looks identical to a complete one.  A meta page should
   assert it built something.

2. I broke the generator three times editing it in place during this fix and
   restored it from the shipped zip.  When an edit needs more than one
   substitution, write the new function whole rather than patching around it.

## verify checks the package you name  (1.13.30)

    lfs-helper verify xorg7-lib --fix
    ...
    [1/533] binutils-pass1    ^C

It read only $1 for the flag and ignored the name, so a question about ONE
package started a walk of all 533.  (The command came from me, which is how
it surfaced.)

Arguments are parsed properly now: --fix/--run anywhere, the first non-flag
is the package, and the ownership pass is narrowed to its manifest.  An
unknown name fails immediately rather than scanning everything.

## A function definition is not a command to skip  (1.13.29)

    packagemanager search xorg7-lib  ->  installed
    pkg-config --exists x11          ->  1

xorg7-lib recorded as installed with no libX11 on disk.  The cause was mine:
the Xorg loop defines

    do_build()   { make; }
    do_test()    { make check; }
    do_install() { as_root make install; }

and calls them per package.  The 1.13.2 test filter commented the DEFINITION
of do_test, so the loop called a function that no longer existed.

_is_definition() now guards every filter -- the doc and pip filters had the
same flaw waiting for a page that wraps those commands in a function.  A real
`make check` is still skipped.

The record is a separate problem the user must clear:
    lfs-helper verify xorg7-lib --fix        (purges the lying record)
    packagemanager install xorg7-lib --run --yes --regenerate

And the lesson: a filter that edits the book's commands can break a script
in ways `bash -n` cannot see -- this one parsed perfectly and did the wrong
thing.  Every filter added since 1.13.2 should be re-read with "what if this
line is inside a function definition, or defines one?" in mind.

## The book writes -D key=value with a space  (1.13.28)

    ERROR: Dependency "libdrm_intel" not found

An INTEL dependency, on a machine.conf that says radeonsi.  The merged line
explained it:

    meson setup -Dgallium-drivers=radeonsi ... \
          -D gallium-drivers=auto  \        <- the book's own, still there
          -D vulkan-drivers=auto   \

apply_machine_opts matched only `-Dkey=`, and the book writes `-D key=value`
with a space -- so ours was PREPENDED and meson took the last occurrence.
mesa was building every driver, and the three "undeclared dependencies"
found in 1.13.23-27 (glslang, rust-bindgen, libclc) were at least partly
this: an auto build wants far more than a radeonsi one.

The pattern accepts the space now, so the book's own option carries the
machine's value.  Worth re-testing whether mesa still needs all three of
those `needs =` entries once it builds for radeonsi alone -- if not, they are
harmless but no longer necessary.

## mesa's third undeclared dependency  (1.13.27)

    ERROR: Dependency "libclc" not found, tried pkgconfig and cmake

libclc IS in the book; mesa's page does not list it.  radeonsi (from the
user's machine.conf) builds the OpenCL bits and needs it.  One line:

    [mesa]
    needs = glslang rust-bindgen libclc

Order: llvm 120 -> glslang 139 -> rust-bindgen 140 -> libclc 143 -> mesa 159.

Three undeclared dependencies for ONE package, each found by a build
failing.  The pattern is now cheap to fix but still expensive to find --
worth considering whether a failed `Dependency "X" not found` could search
the book for X and suggest the `needs =` line itself.  The failure box
already does something similar for a missing PROGRAM (1.12.x); this is the
same idea for a missing pkg-config module.

## An empty export is not an answer  (1.13.26)

The user checked, and both config files said "p".  The note added in 1.13.25
was therefore a FALSE POSITIVE, and a useful one: lfs-helper really did read
an empty prefix.

    PKGUSR_PREFIX="${LFS_PKGUSR_PREFIX-...}"

`-` means "set but empty wins".  A chroot script exports
LFS_PKGUSR_PREFIX="" when the value was unknown when it was written, and
that beat a config file that says "p".  Now `:-` for the ENVIRONMENT, while
the FILE keeps its present-and-empty meaning (1.12.95) -- the two are not the
same statement, and only one of them is deliberate.

Also: mesa needs `bindgen` as soon as it FINDS a rust compiler, and rust is
built here for librsvg.  The book's mesa page lists neither it nor glslang,
so both are declared in package-fixes.conf now:
    [mesa]
    needs = glslang rust-bindgen
Order: rust 128 -> glslang 139 -> rust-bindgen 140 -> mesa 157.  Second use
of the 1.13.23 mechanism, and this time it took one line rather than a
release.

## Strip what an older version wrote  (1.13.25)

mesa failed on -Dneeds= AGAIN after 1.13.24 stopped adding it: the flag was
already in the script on disk, and the merge is idempotent, so nothing took
it out.  Stopping a bad write does not undo the writes already made.
apply_machine_opts removes a stale -Dneeds= when it sees one, and says so.

Also, the stale-script box suggested `packagemanager install p_mesa` -- the
ACCOUNT, where the command wants the ANCHOR.  The user pointed out that
p_mesa is correct for their tree (prefix "p"), which is the useful part:
unprefix_pkg_user should therefore have produced "mesa" and did not, meaning
lfs-helper read an EMPTY prefix while packagemanager had "p".

That is a config disagreement (config.json vs packagemanager.conf inside the
chroot), so the box now prints the anchor AND names the disagreement rather
than hiding it behind a literal strip.  Asked the user to check both files.

## One file, two readers  (1.13.24)

    mesa: ../meson.build:4:0: ERROR: Unknown option: "needs".

1.13.23 put `needs = glslang` in package-fixes.conf for blfs to read as a
dependency edge -- and apply_machine_opts turns EVERY key in a section into
a meson -Dkey=value, so mesa was configured with -Dneeds=glslang.

The file has two readers and each must ignore the other's keys.
apply_machine_opts drops `needs`; blfs already looks only at `needs`.

Worth watching if the file grows: a third key type would need the same
treatment, and the failure appears in a package's configure output rather
than anywhere near the config file.

## A dependency the book does not record  (1.13.23)

    libass: configure: error: Package requirements (harfbuzz >= 1.2.3) were not met

libass's page lists FreeType, FriBidi, Fontconfig and NASM.  Its configure
hard-requires harfbuzz.  So no ordering could place it -- libass 143,
harfbuzz 199 -- and moving stack entries could not either, because both sit
inside ONE plan.

package-fixes.conf can now add the edge, and blfs treats it as required:

    [libass]
    needs = harfbuzz
    [mesa]
    needs = glslang      # the same class, patched by hand in 1.12.96

Result: harfbuzz 198 -> libass 199.

This is the general answer to a class that has cost several sessions
(glslang/mesa, and every "X not found" where the book never said X).  When
the next one appears, it is two lines in package-fixes.conf, which the sync
refreshes -- no code change.

## Commenting a command stranded the one before it  (1.13.22)

    install_p_libpwquality: line 190: syntax error near unexpected token `}'

The generated script ended:
    make install &&
    # pip3 install ... --find-links dist pwquality
The pip filter (1.13.3) commented the last command of an && chain and left
`make install &&` dangling, so bash refused the entire file.

Every filter that comments a line can do this -- the test-run filter already
had a local version of the fix (1.13.6, for pipelines).  The repair belongs
at the END, once, over the whole block: an ACTIVE line ending in && || or |
with no active line after it loses the operator.  Real chains are untouched.

Swept all 30 packages in the current plan afterwards: no syntax errors.
Worth keeping that sweep in mind whenever a filter is added -- the generator
runs `bash -n` and PRINTS the error, but still writes the file, which is how
this reached a build.

## Say "regenerate" where the failure is  (1.13.21)

XCB-Utilities failed again with the message 1.13.20 had just fixed, because
the script it ran came from the package's home and was written by an older
generator:
    install file: /usr/src/pkgusr/p_xcb-utilities/install_XCB-Utilities

packagemanager warns about that when it RESOLVES a script -- at the top of a
59-package plan, hundreds of lines before the failure.  The failure box now
carries the same news, with the command:

    ! This script was generated by blfs 1.13.6; the generator is now 1.13.21.
    ! Fixes made since then are NOT in it -- including any for this very
    ! failure.  Rebuild it from the book first:
    !   packagemanager install xcb-utilities --run --yes --regenerate

Third time this has bitten in the same session (brotli, rust, this).  The
information existed each time; it was just nowhere near the failure.

## A meta page has nothing to enter either  (1.13.20)

    no single tarball -- this page builds a list of packages
    no unpacked source in .../src -- run: ... unpack

Both lines in the same run: unpack_pkg correctly did nothing (1.12.61) and
_enter_build then demanded the directory unpack had not created, so
XCB-Utilities failed in the BUILD phase.  Half a fix -- the same shape as
1.12.20/21 (the shared index) and 1.13.11/13 (the profile helpers): the first
half was right and the second path had not been told.

_enter_build returns at the build root when the page has no tarball of its
own; the page's commands download and cd where they need.  A normal package
still fails loudly if its source is missing.

## A fixed PATH loses everything in /opt  (1.13.19)

The user's own test settled it:

    su - p_cargo-c -c 'command -v cargo'   ->  /opt/rustc/bin/cargo
    (the build)                            ->  cargo: command not found

The login shell had it; the BUILD did not, because cmd_build replaced PATH
with a hard-coded list that has no /opt in it.  So the profile work of
1.13.11-18 was correct and still could not reach a build.

cmd_build now appends the /opt directories that the packages' own profile.d
snippets name (grep for pathprepend/pathappend, keep the ones under /opt
that exist) after the fixed base -- wrappers and system tools still first.
Read from the files rather than by starting another login shell: cheaper, and
it does not inherit whatever else a profile does.

Also fixed: `packagemanager remove cargo-c --purge` crashed with
KeyError: getpwnam(): name not found: 'cargo-c' -- it looked the ANCHOR up in
passwd instead of the account, and a missing account is a normal answer here.

Both suite failures on the way were real: root must not get the wrappers, and
my first version shelled out to `su` to compute the PATH.

## The profile loop is not cosmetic  (1.13.18)

    install_p_cargo-c: line 161: cargo: command not found

cargo lives in /opt/rustc-1.93.1/bin and gets onto PATH through
/etc/profile.d/rustc.sh -- which never runs, because this system's
/etc/profile does not source /etc/profile.d.  1.13.13 offers to add the
loop, and the offer could only be accepted by exporting LFS_ASSUME_YES,
so it was (reasonably) skipped.

`lfs-helper install-profile --yes` now accepts the answer on the command
line.  The build runs through `su -`, a login shell, so once /etc/profile
reads profile.d every package that installs under /opt is on PATH for every
later build.

Worth seeing the chain: rust installs to /opt -> writes a profile.d snippet
-> the snippet needs pathprepend (1.13.11) -> and the snippet needs to be
READ (1.13.13/18).  Three separate fixes for one package to be usable, and
the last of them was a prompt nobody could answer.

## An install nobody recorded did not happen  (1.13.17)

Rust installed cleanly (the ~/src fix worked -- x.py ran, every component
installed).  The very next stack run then planned it as

    Rustc-1.93.1   new   required by cargo-c

and started compiling it again.  `packagemanager script` runs the phase
directly and only pm-install writes the manifest, so nothing recorded the
install and every other command still read rust as absent.

cmd_script now calls `lfs-helper record-install` after a phase that installs
(install / all / update), and says so.

This is the fourth bug in cmd_script.  The handoff item stands and is getting
more expensive to ignore: that function reimplements what _install_via_self
does properly, and should call it instead.

## The plan's "recommended by" names one parent, not the reason  (1.13.16)

The user asked why recommendations are still being pulled in, pointing at
lines like "GTK-3.24.51  new  recommended by libreoffice" -- with libreoffice
avoided.

Two different things, and the display hid the difference.  `blfs order`
reports the FIRST parent that pulled a package in, so:

    gtk3       labelled libreoffice, really wanted by adwaita-icon-theme
    ffmpeg     labelled qt6,          really wanted by mpv
    polkit     labelled systemd,      really wanted by colord
    pulseaudio labelled sdl3,         wanted by pipewire and gst too

Those belong in the plan.  But checking every parent (not the printed one)
found four with NO live parent at all -- colord, linux-pam, xdg-utils,
freeglut -- pure tails of cups/systemd/mupdf.  Avoided.  204 packages now.

And to answer the question itself: recommendations stay because required-only
was tried twice (1.12.47, 1.12.70) and broke the build both times -- BLFS
"recommended" often means the build command uses it (cmake has NO required
deps and hard-fails without curl; libxml2 without icu).  The rule is: build
the book's graph, name what you do not want.

WORTH FIXING: the plan should print a parent that is actually IN the plan.
Doing that by hand is what this note is; the tool has the data.

## Where the sources are, not where the shell started  (1.13.15)

    $ su - p_rust -c 'bash ~/install_p_rust install'
    install_p_rust: line 237: ./x.py: No such file or directory

BUILD_ROOT fell back to $PWD, and a login shell starts in the HOME -- so
_enter_build hunted for the unpacked tree beside the script, took the first
directory it found (log/, probably) and rust's x.py was not there.  It only
worked during a full `all` run because the build phase had already left the
shell inside the source directory.

Sources are unpacked into ~/src, so that is the fallback now:
    LFS_BUILD_ROOT (the runner) -> BUILD_ROOT (explicit) -> ~/src -> $PWD

This is the other half of 1.12.90: that fix stopped exporting BUILD_ROOT into
package builds, and this one gives the script a sensible answer when nobody
exports it at all.

## The whole startup-files chapter  (1.13.14)

The user asked why only the path helpers.  Reading the chapter answered it:
"The Bash Shell Startup Files" creates NINE files, and we installed one.
Without the rest a package user's shell has no umask policy, no INPUTRC, no
locale setting and no ~/.bashrc.

install_shell_startup_files now writes, when absent:
    /etc/profile.d/umask.sh readline.sh i18n.sh extrapaths.sh
    /etc/bashrc
    /etc/skel/.bash_profile .bashrc .bash_logout .profile
plus /etc/profile and the path helpers from 1.13.11.

They are OUR versions -- shorter, commented for this system -- not copies of
the book's text.  Nothing that already exists is touched: each file reports
"kept existing" instead, verified by putting a file in place and re-running.

## Report what you did, not only what you refused  (1.13.13)

    $ lfs-helper install-profile
    /etc/profile exists but does not source /etc/profile.d -- left alone.
    ...
    "it did not installed the files"

It HAD written /etc/profile.d/00-path-functions.sh -- that happens before the
profile check -- and said nothing about it.  A command whose only output is
what it declined to do reads as a command that did nothing.

  * it now reports the helpers it wrote, in every branch;
  * an /etc/profile that lacks the profile.d loop is OFFERED the line through
    confirm_change (--yes accepts), with a backup at
    /etc/profile.before-lfs-helper, instead of a paste-this message.

Both paths verified: with consent the loop is appended and the backup taken;
without it the profile is untouched and the helpers are still installed.

## Wired into the command nobody runs  (1.13.12)

1.13.11 put install_profile_helpers in cmd_init_pkgusr -- and the command
people run on a fresh system is `packagemanager setup`, the BOOTSTRAP, which
is a different entry point.  The user ran setup, saw the five stages pass,
and got no helpers.

Two ways in now: `lfs-helper install-profile` on its own, and the bootstrap
calls it and prints what it did.

The pattern is familiar enough to name: a fix wired into a code path the user
does not travel is not delivered (1.12.85 the file that was never
overwritten, 1.12.86 the script that was never re-read, this).  Ask which
command the user will actually type.

## The startup files BLFS assumes  (1.13.11)

The user's diagnosis, and it is right: BLFS pages drop snippets into
/etc/profile.d that call pathprepend/pathappend, the book defines those in
postlfs/profile ("The Bash Shell Startup Files"), and LFS does not install
them.  So rust's rustc.sh said

    pathprepend: command not found

on every package-user login -- noise at best, a failed configure at worst,
and it will happen for every package that ships a profile snippet.

install_profile_helpers, run by `packagemanager setup` (cmd_init_pkgusr),
writes /etc/profile.d/00-path-functions.sh with pathremove, pathprepend and
pathappend -- our own implementation, not a copy of the book's files.

/etc/profile is the administrator's:
  * already sources profile.d -> nothing to do
  * exists but does not      -> LEFT ALONE, with the line to add printed
  * does not exist           -> a small one is written that sources profile.d
Verified: the helpers actually prepend and append, and an existing profile
survives untouched.

## A local import that shadowed the module  (1.13.10)

    UnboundLocalError: cannot access local variable 'pwd'

cmd_script imports pwd inside a try in one branch, which makes `pwd` LOCAL
to the whole function -- so the module-level `pwd` (imported at the top, with
a `pwd = grp = None` fallback for non-unix) was invisible, and the later
`if pwd is not None` crashed.  The import now lives where it is used, and a
missing account leaves the file owned by root rather than raising.

The suite gained an AST check for the pattern: any function that imports pwd
locally must not also use a bare `pwd`.

This is the third bug in cmd_script in three releases (anchor-vs-account
twice, now this).  That function is the one place doing by hand what
_install_via_self does properly, and it should probably just call it.

## Two names, and they are not interchangeable  (1.13.9)

1.13.8 fixed `packagemanager script` by replacing the anchor with the
account everywhere in that function -- and broke the other half:

    Generating install script for p_rust...
    blfs script failed for p_rust

cmd_script needs BOTH:
    anchor  -- what the book calls it (rust); blfs generates from this
    name    -- the account (p_rust); su and the script path use this
It used the anchor for both, then the account for both.  They are separate
variables now.

STILL OPEN on the user's chroot: `lfs-helper build rust --phase configure`
did not recognise rust as a package and fell through to the LFS build-step
path ("no script for 'rust' at .../scripts/rust.sh").  That is the account
prefix again -- if the chroot's config carries pkgusr_prefix "" while its
accounts are p_*, lfs-helper (which honours empty since 1.12.95) looks for an
account called "rust".  Asked the user for:
    grep pkgusr_prefix /usr/share/lfs/config.json /etc/pkgusr/packagemanager.conf
If that is it, the answer is to put "p" back in the CHROOT's config -- and
the deeper question is whether an empty prefix should be allowed at all once
a tree exists with prefixed accounts.

## script ran as the anchor, not the account  (1.13.8)

    packagemanager script install rust
    $ su - rust -c 'bash ~/install_rust install'
    bash: install_rust: No such file or directory

cmd_script took args.package verbatim -- so it used the ANCHOR as both the
account name and the script name, neither of which exists.  Everything else
in the tool goes through pkgusr_name(); this one path did not.  (Found
because a command I recommended to the user was itself wrong.)

## Writing a login profile is not running it  (1.13.7)

Rust built, installed 2390 files, and failed on the last line:

    /etc/profile.d/rustc.sh: line 3: pathprepend: command not found

The page writes that snippet and then sources it.  The snippet calls
pathprepend/pathappend -- helpers from the BLFS bash startup files, absent
from a build shell -- so sourcing it tests the login shell, not the package.
The file is written and applies at the next login, which is its purpose.

`source /etc/profile[.d/x]` and a bare `/etc/profile.d/x.sh` are now
commented, in the configuration section as well as build and install.

Note this was the CONFIG section again (1.12.89 was the first): a part of the
book that runs after a successful install and can fail a package that is
already on disk.

## x.py test, and a guard that ate the install  (1.13.6)

Rust ran 41425 tests during an ordinary build: `./x.py test` is its test
driver and the 1.13.2 list did not know it (nor `cargo test`, `go test`).
Added -- with `./x.py build` and `./x.py install` carefully NOT matching.

Two more, found by reading the regenerated script instead of shipping:

  * the test run pipes into rustc-testlog and the next lines grep and awk it.
    Commenting only the run left `awk` reading a file nobody wrote, so a
    commented line now takes its continuation lines (trailing |, && or \)
    with it.
  * the book prefaces `./x.py install` with "If sudo or su is invoked for
    switching to the root user, ensure ..." -- and the conditional guard
    commented THE INSTALL.  A sentence about privilege mechanics guards
    nothing; sentences starting "if sudo" or "if su" are no longer treated
    as conditions.

That second one is the guard's first FALSE POSITIVE on something essential,
and it was one regenerate away from silently installing nothing.  Worth
remembering that the guard's failure mode is not only "runs too much".

## A question with one answer is not a question  (1.13.5)

    'p_rust' created /opt/rustc-1.93.1/share inside 'p_rust''s tree.
    Which collector group should own it?
       1) nimgnu_p_rust   (named after the tree ...)
       2) nimgnu_p_rust   (named after the package that made it)

Two bugs in four lines:

  * p_rust created a directory in ITS OWN tree, so there is nothing to share
    and both options were the same name.  When the tree owner IS the
    installing package, no group is created and no question is asked.
  * the group kept the ACCOUNT prefix.  collector_group_for unprefixes with
    PKGUSR_PREFIX, which is empty on that system, so "p_rust" survived whole.
    The tools' own default prefix is stripped as well now: nimgnu_rust.

And, at the user's request, the three things the answer depends on are
highlighted -- the package doing the installing, the directory, and the
recommended name:

    package  : p_cmake   (it is doing the installing)
    directory: /usr/share/vim/vimfiles
    in the tree of: p_vim
       1) nimgnu_vim   <- recommended: named after the tree ...

## A fixed generator does not fix the scripts on disk  (1.13.4)

brotli failed on the identical pip line after 1.13.3 fixed it: the script in
the package home was written by the PREVIOUS blfs, resolve_script prefers a
local script (correctly -- it may hold the user's edits), and the only notice
was a one-line "pass --regenerate" hint that vanishes in a 200-package run.

The mismatch is now stated plainly:
    ^ this script was generated by blfs 1.13.2; the current generator is 1.13.4
      fixes made since then are NOT in it.  To take them (your edits, if any,
      are saved as install_<pkg>.edited):
        packagemanager install brotli --run --regenerate

Deliberately NOT automatic: regenerating would silently discard edits, and
1.12.92 showed how long a silently-ignored edit can go unnoticed.  The user
decides; the tool makes sure they know there is a decision.

This is the same shape as the /tmp cached-script check (1.12.57) and the
stale env questions -- a version stamp exists on these files, and every
consumer of them has had to learn to read it.

## A pip install whose wheel nothing built  (1.13.3)

brotli installed its C library perfectly and then failed on

    WARNING: Location 'dist' is ignored: ... non-existing path
    ERROR: No matching distribution found for Brotli

Its optional Python bindings are two steps: `pip3 wheel -w dist ...` (which
the conditional guard correctly commented) and `pip3 install --find-links
dist Brotli` (which it did not).  Producer skipped, consumer live -- the
same shape as the orphan log reader (1.12.62) and libuv's man page.

A pip install reading from a --find-links directory that no ACTIVE command
fills is now commented with its producer.  A package that really does build
the wheel keeps both lines.

Third instance of this family, so it is worth naming: whenever the guard
comments a block, ask what CONSUMES what that block made.  The generator has
no dataflow model -- each case has been found by a build failing on the
consumer.

## Running the tests is not building the package  (1.13.2)

    Tests summary:  Passed: 77549   Failed: 12
    ! p_nss FAILED (phase 'all')

An ordinary install ran NSS's entire test suite -- hours of it -- and then
failed the package on a leftover test artifact.  The book puts the run in
the BUILD block:
    cd tests &&
    HOST=localhost DOMSUF=localdomain ./all.sh
    cd ../
and the generated script already HAS a test phase, gated on PM_TEST=1.

Test drivers (make check/test, ctest, meson/ninja test, pytest, ./all.sh,
./runtests, make -C tests) are commented out of build and install now, along
with the `cd tests &&` that leads in and the `cd ..` that leads back out --
or the && chain would break.

A bug worth remembering from writing it: the regex began with `\b(`, and
there is no word boundary before "./all.sh", so that alternative could never
match.  It compiled, it caught the make-based drivers, and it let the one
that mattered through -- a filter that half works looks like a filter that
works.

## Tails of avoided packages, named by hand  (1.13.1)

The plan still held 255 packages after the named exclusions, and the parent
column said why: most of the remainder existed ONLY to serve something
already avoided.

    poppler, mupdf, gs, qpdf, pdfio   <- libcupsfilters  <- cups (avoided)
    clucene, redland, rasqal, raptor  <- libreoffice (avoided)
    jasper, libmng, double-conversion <- qt6 (avoided)
    exiv2                             <- libkexiv2 <- okular (avoided)
    the whole xfce/lxqt/gnome stack   <- xdg-desktop-portal's four backends

Each was checked against its parents before being added -- rust and llvm
STAYED, because glycin genuinely requires rust and llvm is a stack entry for
mesa.  273 -> 208, with webkitgtk, gtk4, mpv, pipewire, mesa, cairo,
harfbuzz, graphite2, librsvg and gdk-pixbuf all still in.

This is the manual version of the prune reverted in 1.12.83.  The real fix
remains: `blfs order --anchors` reports ONE parent per package, so "reachable
only through an avoided package" cannot be computed from it.  Emitting every
edge would make this list unnecessary -- and is the next session's first
task, tested against the five ordering cases already in the suite.

## The status counted what the run skips  (1.13.0)

    packages: 108 of 273 installed
    ... qt6, okular, libreoffice, cups, openjdk, postgresql, xfce4-panel ...

all of which the stack AVOIDS.  The avoid list reaches the installer
(1.12.78) and never reached the status display, so the user was shown the
unfiltered graph and reasonably asked whether the exclusions had come undone.
They had not; the report was wrong.

--status now drops avoided packages from the count and says how many:
    packages: 108 of 214 installed
    avoided : 24 named in the stack (apache-ant, cups, gegl, ...)

Third time a status has reported something other than what the run does
(1.12.71 the graph, 1.12.72 the stale file, this).  A display that disagrees
with the action is worse than no display -- worth a look at whether any other
report is computed differently from the thing it describes.

## Staging a file onto itself  (1.12.99)

    install: '/usr/src/pkgusr/p_nss/install_p_nss' and
             '/usr/src/pkgusr/p_nss/install_p_nss' are the same file
    !! could not stage the install script

The script is staged TWICE -- pm-install copies it into the account's home,
and cmd_build stages it again to the same name.  That was invisible while the
account's home was MISPLACED (/usr/src/p_nss vs /usr/src/pkgusr/p_nss, two
different paths); the moment fix-home repointed the home mid-run they became
one file and install(1) refused.

Both staging sites now skip the copy when source and destination are the same
file (and the package-user branch still confirms ownership).  A latent bug
that only surfaced because another fix worked.

STILL WORTH DOING: the double staging itself.  One copy, in one place, would
be better than two that happen to agree -- see the note under 1.12.75 about
account creation ignoring PKGUSR_SUBDIR, which is the same story one layer
down.

## Break the least  (1.12.98)

ghostscript failed on a missing FreeType, and the order explained it:
gs 112, freetype2 130 -- with gs RECOMMENDING FreeType.

The topological sort (1.12.69) breaks cycles by dropping recommended edges,
and it dropped ALL of them among the remaining nodes at once.  gs sits in a
genuine cycle (gs -> cups -> cups-filters -> gs), so when that stalled the
sort, gs's unrelated FreeType edge went with it.

Now it breaks the LEAST that frees a node: pick the node closest to ready
(fewest blocking required dependencies, then fewest recommended), drop only
ITS recommended edges, sort again.  Every other edge survives, and each pass
either frees a node or gives up.

Verified on the real book, all five cases that have cost a session each:
    freetype2 150 -> fontconfig 151 -> gs 153
    libxcb 143 -> xorg7-lib 155
    glib2 173 -> shared-mime-info 174

## A finished host is not the chroot  (1.12.97)

On the user's own machine:

    root ~ # lfs run
    You are inside the LFS chroot, where `lfs build-system run` does not apply.

inside_chroot() asked "does /usr/src/lfs-pkgusr exist" -- which is true of
ANY system these tools built, so a finished host was refused every build
command it has.  An inference that is true of the DESTINATION cannot identify
the journey.

The chroot says so itself now: `chroot enter` sets LFS_IN_CHROOT=1 in the
environment it starts.  A set $LFS means we are outside (there is a build
target to work on).  The old directory test survives only as a fallback for a
chroot entered by hand, and only when there is no $LFS and no /mnt/lfs.

Worth checking next session: this probably explains other odd behaviour on
the host, since every command that guards on inside_chroot() was refusing
there -- possibly including the `packagemanager install Mako` hang, which
has never been diagnosed.

## An entry's position does not move a dependency  (1.12.96)

texlive built at 3/102 despite `book texlive` being the LAST entry: it is
harfbuzz's RECOMMENDATION, so it arrives inside an earlier entry's plan, and
where the entry sits in the file has nothing to do with it.  (1.12.88 said
"TeX last" and was wrong about the mechanism.)

Its own failure is upstream anyway -- texlive-source's configure looks for
`freetype-config`, which FreeType removed years ago.

So texlive is now `avoid`ed: nothing in this stack needs it (the book's
`make ... pdf ps` manual builds are commented out, asymptote and biber are
avoided), and it can be built on its own later:
    packagemanager install texlive --run

STILL UNRESOLVED: the `packagemanager install Mako` hang on the HOST.  It
stops after "# user 'p_mako' already exists" with both tools now agreeing on
the name.  Asked twice for `ps -ef --forest` / `/proc/<pid>/wchan` and not
yet received; my hypothesis is the pre-build tree snapshot, which on a full
host system (millions of files, unlike a chroot) may simply be slow and
silent -- but that is a guess and the process tree would settle it in
seconds, as it did for the `bash -e` hang.

## Present-and-empty is an answer  (1.12.95)

The user set `"pkgusr_prefix": ""` and the two tools disagreed in the same
line of output:

    $ /usr/bin/lfs-helper pm-install mako ...     <- packagemanager: no prefix
    Install p_mako                                 <- lfs-helper: prefix "p"

packagemanager honours an empty value ("no prefix", documented since
prefixes were introduced).  lfs-helper's reader tested `[ -n "$v" ]`, so an
empty value looked like a MISSING key and fell through to the default `p`.
It now checks whether the KEY EXISTS and takes its value, empty or not.

WARNING recorded for the user: their tree was built with `p_`, so setting
the prefix empty now makes every tool look for accounts that do not exist.
The prefix is a decision taken before the first account, not a runtime
switch.  For that machine the answer is to put "p" back.

Not changed: the collector-prefix reader has the same shape, but an empty
collector prefix would produce group names like "_vim", so "present and
empty" is not obviously meaningful there.  Left alone deliberately.

## "Cannot judge" is not an answer  (1.12.94)

    packagemanager update --reinstall --yes --recursive mako
    ... 1 it cannot judge:  Mako

True, and useless: Mako has no install record because it is NOT INSTALLED,
and the user was asking to build it.  When packages are NAMED on the command
line, the report now says so and gives the command:

    These have no record here because they are NOT INSTALLED.  To build them:
      packagemanager install Mako --run

(The first attempt read `args` inside a helper that never had it -- a
NameError the suite caught on the same run.  The package names are passed in
as an argument now.)

## Type what you were shown  (1.12.93)

    blfs search mako                      ->  Mako   Mako-1.4.1
    packagemanager update mako            ->  ERROR: 'mako' not found

BLFS anchors are not all lower case: the Python module pages keep their
project capitalisation (Mako, PyYAML, Cython).  `search` matched
case-insensitively and every other command looked the anchor up exactly, so
a user who had just been shown a name could not use it.

resolve_anchor() returns the book's own spelling for whatever case was
typed, and is applied at every command that takes an anchor from the user
(debug, order, script, deps, install...).  A name that really is absent comes
back unchanged, so the error message still says what was asked for.

(Two mistakes of mine while doing it, both caught immediately: a blind
string replacement rewrote a loop body, and the resolver assumed `book` was
a dict when it is a Book object with a .packages map.)

## The edited script was never even looked at  (1.12.92)

The user edited install_xmlto-0.0.29 -- the file the tools tell them to edit
-- and the run still used the generated one, without the "using LOCAL
script" line.

_script_name_version matched only

    name_version="..."

and since 1.12.18 the generator emits book strings SINGLE-quoted (a dollar
sign in prose is not a variable).  So it returned None, the local-script
condition never held, and EVERY user edit has been silently ignored since
that release -- including the ones this session told people to make.  It
accepts either quote now.

The 1.12.91 backup message was treating a symptom of this: edits were not
being overwritten so much as never read.  Both fixes stand.

Checked for the same assumption elsewhere: the only other double-quote-only
reader (the book-set variables in _env_wanted_by_scripts) matches what the
generator actually emits there, so it is correct.

## An edit must not vanish in silence  (1.12.91)

xmlto's download 404s at pagure.io AND at the LFS mirror -- the book's URL is
simply dead.  The user fixed the link in a script and found it broken again,
and asked the right question: do we overwrite the install files?

Three files, and only one is safe to edit:
    install_<name>-<version>   the canonical one -- resolve_script prefers it
                               and never rewrites it.  EDIT THIS.
    install_<name>             regenerated whenever the tools move on
    install_p_<name>           the runner's copy, rewritten every run
The failure box has always named the first one, but the other two look just
as editable, and losing an edit to them was silent.  Now a differing file is
saved as install_<name>.edited with a message saying where edits belong.

STILL OPEN for the user: xmlto's tarball has to come from somewhere.  Options
are dropping it into /sources by hand (the fetch checks there first), or
correcting the url= in install_xmlto-0.0.29.  Nothing in this desktop needs
xmlto directly -- it arrives via xdg-utils -- so `avoid xmlto` is also
reasonable.

## Our variable name broke someone else's build  (1.12.90)

libvpx configured correctly, created its headers, and then every compile
said `vpx_config.h: No such file or directory` -- with the file sitting in
the build directory, readable.

Its build/make/Makefile:
    BUILD_ROOT?=.
    CFLAGS+=-I$(BUILD_PFX)$(BUILD_ROOT) -I$(SRC_PATH)
`?=` yields to the ENVIRONMENT, and run_phase_as exported BUILD_ROOT (the
package's source directory) into every build -- so libvpx compiled with
-I<source root> instead of -I. and never saw its own config header.

Ours is now LFS_BUILD_ROOT; the generated script still calls it BUILD_ROOT
internally (`BUILD_ROOT="${LFS_BUILD_ROOT:-${BUILD_ROOT:-$PWD}}"`) but as a
plain shell variable that is not exported to make.

The general lesson: a name in the environment belongs to whoever else might
use it.  Every variable this project injects should be prefixed --
LFS_CC_PHASE and PM_* already are; BUILD_ROOT was the exception, and it took
a package whose Makefile happened to share the name to find it.  Worth a
sweep of what else run_phase_as passes.

(Found by reading libvpx's actual Makefile from the tarball's repository
rather than guessing -- three commands, one cause.)

## A conditional block is conditional wherever it appears  (1.12.89)

    make: *** No rule to make target 'install-saslauthd'.  Stop.

The book introduces that command with "If you need to run the saslauthd
daemon at system startup, install the saslauthd.service unit included in the
blfs-systemd-units package" -- a conditional block, and one that needs a
package this system does not have.

extract_commands_phased has guarded conditional blocks since 1.12.6, but
extract_commands -- used for the CONFIGURATION section -- did not, so every
"If you want..." command in a Configuration section has been running all
along.  The guard is applied there too now; cyrus-sasl's line is emitted
commented, with the book's sentence above it.

(Read the script first: it named the failing line and where it came from in
one look.  Same as libassuan.)

## TeX last, because nothing needs it  (1.12.88)

The user asked whether TeX is needed by other packages or can wait.  With
1.12.87 the answer is clear: NOTHING in this stack needs it.  The only
commands that wanted TeX were the book's `make -C doc pdf ps` manual builds,
now commented out, and the packages that genuinely require it (asymptote,
biber) are avoided.  TeX is useful to the USER, not to the build.

So `book texlive` is the LAST book entry -- after everything the desktop
needs, before the git block (the suite enforces that the cloned entries stay
last, and caught the first attempt at putting texlive after them).

## Read the script before fixing it  (1.12.87)

The user pasted the generated script and it settled four releases of
guessing in one line:

    153: ./configure --disable-doc --prefix=/usr      <- the fix HAD applied
    159: make -C doc pdf ps                           <- this is the failure

--disable-doc does not exist in libassuan (autotools accepts unknown
--disable-* silently), so the fix was WRONG, not undelivered -- and three
releases went into delivering it better.  Reading the script on the first
failure would have shown the cause immediately.

Two changes:
  * `make ... pdf/ps/dvi` lines are emitted COMMENTED -- typesetting a
    manual is not installing a package, and those targets need TeX.  html
    and info builds are untouched (texinfo is in LFS).
  * texlive is BUILT now, at the user's call: it is generally useful and it
    removes the whole "needs TeX" class.  It goes to /opt/texlive/2025, a
    value the generator lifts from the book's own PATH page (1.12.49), so
    nothing has to be set by hand.
  * the useless --disable-doc entries are gone from package-fixes.conf, with
    a note saying why.

## And it must reach a script that already exists  (1.12.86)

package-fixes.conf arrived on the system (the user checked) and libassuan
failed identically for the THIRD release.  apply_machine_opts ran only where
a script was GENERATED -- and libassuan's script was already in its home
from the first failure, so resolve_script returned it untouched.  Every
package that has failed once was in that state.

The merge now runs on the local path too, and is idempotent (an option
already present is not added again, verified over three applications).

Also: TOOL_VERSION still read 1.12.82 while the build id moved -- the
version bumps had been editing a string that no longer matched.  The user
spotted it in --version output.

Three releases for one fix, each blocked by a different link in the chain:
the file was not shipped, then not overwritten, then not applied.  A fix is
not delivered until it reaches the code path that runs.

## A fix must be able to arrive  (1.12.85)

1.12.84 shipped libassuan's --disable-doc in machine.conf, and libassuan
failed again with the identical error.  machine.conf is NEVER OVERWRITTEN by
the sync -- correctly, it holds the machine's mesa options -- so a workaround
shipped in it can never reach an existing system.  The fix was in the
release and not on the machine.

Two files now, and the difference is the point:
  package-fixes.conf -- workarounds the TOOLS ship (cairo's ctime_r,
                        libassuan/libgpg-error --disable-doc, gpgme).
                        Refreshed with every release.
  machine.conf       -- the MACHINE'S choices (mesa's drivers).  Never
                        overwritten, and it WINS where both name a key.

The general lesson, which cost two releases: a file the user owns cannot
also be a delivery channel.

## machine.conf reaches autotools  (1.12.84)

libassuan's `make` builds assuan.pdf, which needs TeX -- and TeX is on the
avoid list on purpose.  The package has a switch for it (--disable-doc), but
machine.conf could only inject into `meson setup` lines, so an autotools
package had no way to take a machine option at all.

`configure_args` is appended to the ./configure line now; every other key is
still a meson -Dkey=value.  Shipped for the three packages in this plan that
build TeX manuals: libassuan, libgpg-error (--disable-doc) and gpgme
(--disable-gpg-test).

This is the same shape as the cairo ctime_r workaround (1.12.16): the cure
lives in machine.conf so it survives a regenerated script, and it is per
package rather than a rule about all of them.

## The prune was wrong, reverted  (1.12.83)

1.12.82's reachability prune broke harfbuzz:
    Dependency 'graphite2' is required but not found
graphite2 IS a stack entry, and it was dropped because `blfs order
--anchors` reports ONE parent per package -- the first that pulled it in.
When that recorded parent is an ignored package, a dependency several
packages share is pruned with it.  Pruning needs every edge; that output
carries one.

Reverted.  The KDE leaves that okular alone pulls in are named in the stack
instead (plasma-activities, libkexiv2, kwindowsystem, libfm-qt, the lxqt and
gnome portals, gnome-desktop) -- more lines, but each one true.

Two attempts at automatic exclusion (deps=required in 1.12.47/70, this
prune) have both been reverted after breaking a build, and both times the
naming approach the user asked for turned out to be the correct one.  Worth
remembering before a third attempt: the book's graph does not carry enough
information to prune it safely from one walk.

## Prune the graph, not the list  (1.12.82)

plasma-activities failed on a missing ECM -- a KDE package, in a plan where
okular is avoided.  This was the limit written down in 1.12.78: --ignore
removed the named packages and left the tails only they pulled in.  okular
was skipped; plasma-activities, which nothing else wants, was built anyway,
straight into the KDE Frameworks page that this book edition does not carry.

The plan now prunes by REACHABILITY: `blfs order --anchors` reports each
package's parent, so a package whose only path to the target runs through an
ignored one is dropped with it.  Verified on the shape that failed --
ignoring okular drops plasma-activities and qtbase, keeps poppler and
webkitgtk.

That closes the honest gap left in 1.12.78, and with it the KDE branch.

## Say what to do about it  (1.12.81)

util-macros stopped with "this package needs XORG_CONFIG to be set" -- the
guard doing its job (1.12.47), but saying WHAT and not HOW.  The value had
been set before the snapshot restore and went with /etc/pkgusr/build.env.

The failure box now prints the command:
    ! XORG_CONFIG is not set for builds.  Set it once and it applies to
    ! every package (builds run as a package user, so exporting it in your
    ! shell does not reach them):
    !   packagemanager env --set XORG_CONFIG=...   # or: packagemanager env --ask

NOTE for a fresh tree: build.env is not part of the snapshot, so the Xorg
variables have to be set again after a restore.  Worth considering whether
`packagemanager setup` should ask for them.

## Do not throw away a build that succeeded  (1.12.80)

Two bugs, one of them expensive:

**--ignore twice, the second by letter.**  The command line read
    --ignore texlive,libreoffice,...  --ignore t,e,x,l,i,v,e,,,l,i,b,...
A leftover second block re-joined the already-joined STRING, one comma per
character.  Removed; there is one list and one flag.

**LLVM recompiled from scratch.**  It had built all 4343 targets and failed
on the systemd-run line at the very end -- and the retry wiped the source
tree and did it again, because `--phase all` always called
clean_stale_source.  That is right for a fresh build and wrong for a retry.
The phase records already know what finished (1.11.55), so a retry with
'build' on record keeps the tree and says so:
    # keeping the source tree: 'build' already finished here
    #   (rebuild from scratch with: lfs-helper build llvm --phase unpack --force)
A package with only 'unpack' recorded, or nothing, is still cleaned.

## The whole systemd family  (1.12.79)

    [4343/4343] Linking CXX executable bin/obj2yaml
    # skipped (no systemctl on this system): systemctl --user start dbus
    install_llvm: line 166: systemd-run: command not found

LLVM built every one of its 4343 targets and then died on the last line but
one.  systemctl was shimmed (and did its job, visibly); systemd-run was not,
and on a SysV system a missing command aborts the phase.

The shim now covers the family the systemd book actually uses: systemctl,
systemd-run, systemd-tmpfiles, systemd-sysusers, systemd-machine-id-setup,
systemd-hwdb, loginctl, busctl, journalctl, timedatectl, hostnamectl,
localectl, udevadm.  Each is defined ONLY when the real binary is absent, so
nothing changes on a systemd host.  Verified in an isolated shell where the
binary genuinely does not exist:
    # skipped (no systemd-run on this system): systemd-run --user foo

(The user is building with the systemd-flavour book on a SysV system -- see
1.12.4, where the default was made init-aware.  Switching the book would
avoid this class entirely; shimming keeps the current build going.)

## Follow the book, name what you do not want  (1.12.78)

    CMAKE_USE_SYSTEM_CURL is ON but a curl is not found!
    Dependency "icu-uc" not found, tried pkgconfig

Two packages in a row, same shape: the book calls a dependency
"recommended", and the package's own build command hard-requires it.
--ignore-recommended is global, so it strips those too -- and naming them one
failure at a time is a treadmill.  The user asked the right question ("are we
still installing required deps?"): yes, and that was never the problem.

So deps=required is off the shipped stack.  The book's graph is followed as
written, and the branches this desktop does not want are NAMED -- which is
the rule the user set for texlive and which the stack format already had:

    avoid  qt6 / okular / phonon / vlc / cups / openjdk / java / apache-ant
    avoid  postgresql / openldap / unixodbc / graphviz / gegl
    avoid  texlive / libreoffice / asymptote / biber

And a real bug found while doing it: `avoid` was ONLY A MESSAGE.  It printed
"never built by this stack" and passed nothing to the installer, so those
packages were built anyway.  It is now handed to every entry's resolve.

Honest limit: --ignore removes the named packages, not the dependencies they
alone pull in, so some of qt6's tail may still build.  If that shows up as
wasted hours, the fix is to prune the graph rather than the list -- worth
doing properly, not at the end of a session.  deps=required remains
available per entry for anyone who wants it.

## The deps=required trade-off, paid  (1.12.77)

    CMAKE_USE_SYSTEM_CURL is ON but a curl is not found!

cmake declares NO required dependencies and four recommended ones (cURL,
libarchive, libuv, nghttp2) -- and its own build turns the system libraries
ON, so a recommendation is a hard requirement in practice.  This is exactly
the cost of deps=required that was flagged when it went in, and the answer
is the one that was agreed: NAME what the build needs.  Those four are stack
entries now; the plan goes 99 -> 102.

Expect a few more of these as the build climbs -- each arrives as a clean
configure error naming the package, and costs one line.  That is the deal
deps=required makes: 170 packages not built, in exchange for naming the
handful the book calls optional and the code does not.

## A book entry can become a clone  (1.12.76)

--no-git skipped the 14 declared git/tar entries and then cloned elogind
anyway.  elogind is `book elogind url=...` (1.12.5): a BOOK entry that falls
back to git when the book does not carry it -- and that rewrite happens
during the judging, after the early filter has run, so its kind was still
"book" when the filter looked.

The decision is taken in the run loop as well, where the kind is final:
    elogind: skipped (--no-git)
Same lesson as the ordering passes: a filter that runs before the data is
final only filters what it happened to see.

## The extras come last  (1.12.75)

    install_elogind: line 54: git: command not found

git is itself a BLFS package, and the stack was cloning things before it
existed.  The git and tar entries -- elogind, seatd, wlroots, sway, foot,
the Sw* tools, dejavu -- are now grouped at the END of sway.stack, after a
`book git` entry, so the book part of the desktop finishes first and the
extras follow.  `packagemanager stack sway --no-git` skips them entirely,
which is what the user wanted for now.

Noted while reading that output, not chased: the failure box shows
    script: /usr/src/p_elogind/install_p_elogind
    staged: /usr/src/pkgusr/p_elogind/install_elogind
-- p_elogind's home is /usr/src/p_elogind, the hint's default, which
fix-home is supposed to repair at account creation (1.11.55).  It was
created by the git-entry path, which may not go through _pm_add_account.
Worth a look next session.

## Where the stacks actually are  (1.12.74)

1.12.73 refreshed the stacks -- from `os.path.dirname(__file__)/stacks`.  The
running tool is /usr/bin/lfs, so that is /usr/bin/stacks: nothing, in
silence.  The host had 31 book entries and the chroot kept 23, and the only
clue was the ABSENCE of a line.

It looks in both places now, nearest first: beside the tool (a checkout) and
/etc/pkgusr/stacks (an installed system), never at the chroot's own copy.
And finding none is no longer silent:
    # no stack files found to refresh (looked beside the tool and in
    #   /etc/pkgusr/stacks)

Three fixes for one sync (1.12.72 stacks at all, .73 one path + no
downgrade, .74 the right source).  Each was found only because the user
checked a number rather than trusting the tool's own report -- worth doing
again the next time something claims to have refreshed itself.

## One sync path, and never backwards  (1.12.73)

Per the user: `lfs build-system run`, `lfs run` and `lfs chroot enter` must
all keep the chroot current.  Two of them did (both call
_refresh_chroot_tools); `sync-tools` installed the helper and the skeletons
and left the other three tools and the stack files to whatever was already
there -- so WHICH COMMAND YOU USED decided what got updated.  sync-tools
calls the same function now: one sync path, every entry point.

And it never goes backwards.  Stack files carry `# stack-version:` and are
skipped when identical, kept when the copy in the chroot is NEWER (a file
edited in there, or a newer release), replaced only when the host's is
newer.  machine.conf is still placed only when absent -- it is the machine's
own options.

    # kept the newer sway.stack already in the chroot (9.9.9 > 1.12.73)
    # refreshed in the chroot: kernel-sway.sh, sway-session.sh

## The stacks travel with the tools  (1.12.72)

--status still said 272 after 1.12.71, and the entry list gave it away: 39
entries, none of the ones added in 1.12.70.  The chroot was reading a
sway.stack from days ago.

_refresh_chroot_tools copied the four BINARIES and nothing else, so a chroot
kept whichever stack file it was first given -- the user updated the tools
four times and kept reading the same stale file, checking a number that
could never move.  The stack files are refreshed with the tools now.
machine.conf is the exception: it is the machine's own build options, so it
is placed only when absent, never overwritten.

(Both --status bugs in a row were the same mistake in different clothes:
reporting something other than what the run would do.)

## The status must count what the build will build  (1.12.71)

The user ran --status after 1.12.70 and saw "4 of 272 installed" -- the old
number.  The build would have used the required graph; the STATUS asked
blfs_order_anchors without the entry's deps=, so it counted a plan nobody
was going to build.  It passes no_recommended now and reports 99, the same
graph the run uses.  (Also: the entry-table header still printed in status
mode; gated.)

A status that does not match the run is worse than no status -- it was the
number the user was asked to check before committing hours of build.

## The graph you asked for  (1.12.70)

`--status --full` showed 272 packages for a sway desktop: LibreOffice,
OpenJDK, CUPS, Qt6, okular, VLC, texlive, PostgreSQL, the xfce and lxqt
portals -- every one of them arriving as a RECOMMENDATION, and one branch
(KDE) unbuildable because its dependency page is out of book.

So the book entries now carry `deps=required`, and the recommendations this
desktop actually needs are NAMED as entries instead of inherited: harfbuzz,
graphite2, pango, gdk-pixbuf, hicolor-icon-theme, adwaita-icon-theme,
glib-networking, and the gstreamer family that was already there.

    272 packages  ->  99

The first attempt at this (1.12.47) was reverted for a good reason and is
worth remembering: texlive's own dependencies are all recommended, so
dropping the class left it with none and the ORDER put it first.  That was
an ordering bug, fixed in 1.12.69 by the topological sort -- not an argument
against choosing a graph.  The mechanism is per-entry, so anything that
turns out to be needed is one named line, and the failure it causes first
("X not found" at configure) says exactly which.

The user wants LibreOffice eventually: `book libreoffice` as its own entry,
placed last, once the desktop runs.  Deliberately not now.

## A sort, not a repair pass  (1.12.69)

The user asked the right question after the third ordering fix: is this a
general ordering problem?  Yes -- and the approach was wrong in kind.
_dependencies_come_first was a REPAIR PASS: walk the list, notice a
dependency that landed too late, move it earlier.  That can only fix the
cases it happens to look at, and the next pass undoes them -- which is
exactly what happened three times (texlive, GLib, libxcb).

It is Kahn's algorithm now: a node is emitted only when everything it
depends on has been emitted, ties keep the walk's order so the result stays
stable.  Cycles are broken by STRENGTH -- recommended edges inside a cycle
go first; a cycle of required edges is the book's own knot and those nodes
are emitted in their original order rather than pretending it was solved.

Verified on the real book, all four cases that cost a session each:
    libxcb 117 -> xorg7-lib 189      glib2 103 -> shared-mime-info 132
    freetype2 130 -> fontconfig 170  cairo 107 -> texlive 108

### mesa/glslangValidator is NOT an ordering bug

The book's mesa page lists required: Xorg-Libraries, Libdrm, Mako, PyYAML --
glslang is not there.  mesa needs glslangValidator only because
machine.conf sets -Dvulkan-drivers=amd: the USER'S OPTION creates a
dependency the book does not declare, and no dependency order can place
what nothing declares.  sway.stack now names `book glslang` before mesa,
with the reason in a comment.  Any future machine option that pulls in a
tool needs the same treatment.

## Required has the last word  (1.12.68)

libX11 could not find xcb, and the user's three commands settled it in one
go: `pkg-config --exists xcb` -> 1, `search libxcb` -> NOT INSTALLED, no
xcb.pc on disk.  Not a ghost record, not a PKG_CONFIG_PATH problem: libxcb
was never built, because the plan had

    32: xorg7-lib
    37: libxcb

and xorg7-lib REQUIRES libxcb, with no edge back at all.

_dependencies_come_first (1.12.52) ran the required pass FIRST and the
recommended pass second -- and the second pass could move things the first
had just fixed.  Reversed: recommended first, required LAST, so nothing
weaker can put a required dependency after its dependant again.  Verified on
the real book: libxcb 32 -> xorg7-lib 33, and the earlier cases still hold
(freetype 25 -> fontconfig 26 -> texlive 42; GLib before shared-mime-info in
three different plans).

Third ordering fix in this session (1.12.33, 1.12.52, this one).  The
lesson each time: a pass that reorders must be the LAST word on the
strongest constraint, or a weaker pass silently undoes it.

## An absolute path walks past every wrapper  (1.12.67)

The ldconfig wrapper (1.12.66) sat unused: the book's loop says

    as_root /sbin/ldconfig

and the wrappers live in a directory on the package user's PATH, so an
absolute path never reaches them.  This is not about ldconfig -- ANY of the
wrapped tools (install, chown, chgrp, chmod, mkdir, cp) written as /sbin/x
or /usr/bin/x bypasses the entire package-user mechanism, silently.

Generated commands now call the wrapped tools by NAME: /sbin/ldconfig ->
ldconfig, /usr/bin/install -> install, and so on.  Comments are left alone
and a longer name (/sbin/ldconfigXYZ) is not a match.

The wrapper mechanism has been in this project since the beginning; a book
command with an absolute path defeated it the whole time, and only a
sticky-directory failure made that visible.  Worth remembering when a
wrapper "does not fire": check how the command was spelled.

## The library cache, and what ldconfig also does  (1.12.66)

    /sbin/ldconfig: Renaming of /etc/ld.so.cache~ to /etc/ld.so.cache failed:
        Operation not permitted

/etc/ld.so.cache is rewritten by every package that installs a library, and
ldconfig writes a temp file and RENAMES it over -- which a sticky /etc allows
only to the file's owner (here p_e2fsprogs).  Unsealing /etc to fix that
would let every package delete every other package's configuration, so
instead package users get a wrapper that skips ldconfig, and the tools
refresh the cache as root when the install finishes -- the mandb treatment.

THE USER CAUGHT THE DANGER IN THAT: ldconfig does two jobs.  Besides the
cache it creates and updates SONAME symlinks (libfoo.so.6 ->
libfoo.so.6.2.1) in the library directories -- and run as ROOT those land
root-owned inside package-owned trees.  That is exactly how
libfreetype.so.6 came to be owned by p_libpaper earlier in this build.  So
the refresh is `ldconfig -X`: rebuild the cache, touch no links.  The
symlinks belong to the package that installs the library, and its own `make
install` creates them.

## as_root, in a model with no root  (1.12.65)

The loop finally ran, and reached
    install_xorg7-lib: line 198: as_root: command not found
The book defines as_root() in a NOTE -- prose, kept as a comment -- and the
loop calls it.

In the package-user model there is nothing to elevate: the package user owns
the directories it installs into, and the wrappers cover what it may not do.
So when the commands call as_root, the script defines it as
    as_root() { "$@"; }
placed before the commands that use it.  A package that never calls it gains
nothing, and a mention inside a comment does not count as a call.

## The book says "type this into a subshell"  (1.12.64)

The user's process tree found it in one look:

    bash install_xorg7-lib all
      \_ bash -e            <- idle, no children, holding the build

Not a prompt after all.  The Xorg pages use an interactive idiom: type
`bash -e`, paste the loop, type `exit`.  A SCRIPT that runs `bash -e` gets a
shell reading its own stdin -- the terminal -- and waits there forever.

The wrapper line and its matching `exit` are now removed: the phase IS that
shell and already runs under set -e.  (Leaving the `exit` would have ended
the phase silently at that point, which is worse than hanging.)  A package
without the idiom is untouched.

Worth noting for the next session: the 1.12.63 "WAITING FOR AN ANSWER"
lines were written on a hypothesis that turned out wrong.  They are still
right -- a prompt behind a pipe would have been invisible -- but the lesson
is the one this file keeps repeating: ps and /proc answered in seconds what
two rounds of reasoning did not.

## A prompt behind a pipe looks like a hang  (1.12.63)

xorg7-lib printed "its own commands fetch them" and then nothing for twenty
minutes.  `ps` showed lfs-helper alive with NO child compiler -- so it was
not building, it was waiting.

Every prompt writes its question to /dev/tty (so it survives the pipes) and
reads the answer there, but the build's OUTPUT goes through tee -- so a
waiting prompt is invisible in the place the user is watching.  All three
prompts now also announce themselves on the ordinary output:

    !! WAITING FOR AN ANSWER: which group should share /usr/share/X11/...?

DIAGNOSIS STILL OPEN for the user's current hang -- asked for:
    cat /proc/<pid>/wchan      # what it is blocked on
    ls -l /proc/<pid>/fd/0     # a terminal read?
    ps -ef --forest            # any child at all
If it is a prompt, pressing Enter releases it and 1.12.63 makes the next one
visible.  If wchan says something else (a stuck wget, an NFS read), that is a
different bug and the evidence will say so.

## A command whose input nothing produces  (1.12.62)

Xorg Libraries got past the tarball problem and died on
    grep: *make_check.log: No such file or directory
The line that WRITES those logs is the optional test step, correctly
commented out; the line that READS them stayed active, and set -e failed the
page.

Same shape as libuv's man page (1.12.19), one layer earlier -- at generation
instead of at run time.  A reader (grep/cat/tail/...) of a .log that no
active command writes is commented out with a note.  Deliberately limited to
.log files: a build artifact with a real name might be produced by make
itself, and guessing there would do harm.  A page that does write a log
keeps its reader.

## A meta page has no tarball  (1.12.61)

    2026-08-31 (313 KB/s) - 'index.html' saved [328504]
    tar: ../: Cannot read: Is a directory

"Xorg Libraries" is not a package: no pkg=, a DIRECTORY for link=, and its
own commands fetch the list (wget -i from an embedded md5 file, then a
for-loop over every tarball).  The generator treated it like any package,
downloaded the directory index and tarred "..".

unpack_pkg now returns early when there is no pkg -- there is nothing to
fetch or unpack, and the page's own commands do all of it.  Xorg
Applications, XCB-Utilities and KF6 Frameworks are the same shape and get
the same treatment.  Normal packages are unchanged (nettle still fetches and
extracts).

## Another language's variables, and a prompt that says who wants it  (1.12.60)

The user, asked for PACKAGE_PREFIX_DIR: "i totally dont know what to set
there".  Neither would anyone -- it is a CMAKE variable, written by a sed
expression into a .cmake file:

    sed -e '/PACKAGE_INIT/i set(SAVE_PACKAGE_PREFIX_DIR "${PACKAGE_PREFIX_DIR}"...

Inside single quotes the shell never expands it, which is a provable rule
rather than a heuristic: single-quoted spans are stripped before looking for
variable names.  Both false positives are gone; KF6_PREFIX (a real shell
variable in the same command) is still asked.

And the prompt now says WHERE the question comes from, because "a script
needs it" is not information:
    KF6_PREFIX is needed by: kf6-frameworks-6.19.0
      the book's page for that package explains it:  blfs debug kf6-frameworks
      press Enter to skip -- the build stops at that package rather than
      using an empty value
Book values are offered for KF6_PREFIX (/usr), QT6PREFIX (/opt/qt6),
TEXLIVE_PREFIX (/opt/texlive/2025) and XORG_PREFIX (/usr).

## A value with spaces is one value  (1.12.59)

The first package built after setting XORG_CONFIG died at line 1:

    env: '--disable-static': No such file or directory

build_env_pairs (1.12.54) printed NAME=value pairs straight into
`env $envpass bash ...`, and the shell split the flag list on whitespace, so
its second word was run as a command.  Every package would have failed this
way -- the variable was set correctly, the plumbing lost it.

Each pair is single-quoted now, with the one escape single quoting needs, so
values containing spaces AND apostrophes survive.  Pinned in the suite with
exactly such a value.

## An empty list is not a promise  (1.12.58)

With 219 stale scripts ignored, `env` said "nothing set, and no generated
script asks for anything" -- true, and useless: the user still could not set
anything BEFORE the run, because a guard only exists once the package's
script has been generated, which happens during the build.

Two changes, neither of them a claim that the list is complete:
  * `--refresh` drops scripts from an older blfs (they regenerate on demand),
    so the current generator's questions can be seen;
  * an EMPTY list now says what will actually happen -- a variable becomes
    visible when its package's script is generated, the build warns before
    that package starts (1.12.48) and stops rather than passing an empty
    value -- and offers the one value we already know (XORG_CONFIG).

The honest shape of the real fix, for a later session: ask blfs for the
variables of every package IN THE PLAN before the run starts, rather than
reading whatever scripts happen to be in /tmp.  `blfs env <anchor>` using
_required_env_guard's detector is the missing piece; packagemanager then
walks the plan once and asks everything up front.

## Old scripts ask old questions  (1.12.57)

The user reran `packagemanager env` after 1.12.56 and saw the SAME eleven
variables.  The fix was fine; `env` was reading the scripts in
/tmp/packagemanager/install_files, which the previous blfs had written.  It
now skips any script whose "### generated by blfs X" header does not match
the current generator (falling back to packagemanager's own version when
blfs cannot be asked) and says how many it ignored.

### The user's second question: should those prefix directories exist?

Yes -- /opt/texlive/2025 and /opt/qt6 are the packages' own prefixes, and an
install into a missing directory fails (`tar: /opt/texlive/2025: Cannot
open`).  cmd_build's repair creates them today, but under the SHARED rule
(root:install), because /opt is an install directory -- while the user is
right that a package's own prefix belongs to that package.

NOT changed here, deliberately: the directory-ownership rules were rewritten
three times this session (1.12.41/42/44) and each attempt broke something.
The shape of the fix is clear -- a directory created as a package's own
PREFIX (the build's --prefix, not a shared tree) should be owned by that
package, with the shared rule reserved for directories more than one package
writes -- and it wants a fresh session and its own tests.

## Ten of eleven questions were mine to answer  (1.12.56)

`packagemanager env` on the real system listed eleven variables, and the
user asked the right question: how am I supposed to know what to set for the
ones with no default?  Answer: they should never have been asked.

    EUID                 -- the shell's own
    DOCNAME              -- a for-loop variable in the script's install text
    PACKAGE_PREFIX_DIR   -- set by the script itself
    SAVE_PACKAGE_PREFIX_DIR, JT_JAVA  -- likewise
    XORG_PREFIX          -- "the book says <PREFIX>", which is a placeholder

Three causes, all in the guard: shell built-ins were not excluded; the
"what does the script set itself" scan only read the BUILD text, so loop
variables and assignments in the install section looked like the user's job;
and a prose placeholder (<PREFIX>) was accepted as a value.  Now: a list of
shell variables is excluded, assignments/`for`/`read` are collected from the
whole script, and any value containing <> is refused.

Across util-macros, texlive, qt6, kf6-frameworks and poppler exactly ONE
question remains -- XORG_CONFIG -- and --ask offers the book's value for it.
A prompt the user cannot answer is worse than no prompt: it teaches them to
ignore the ones that matter.

## A value in two halves is not a value  (1.12.55)

util-macros wanted XORG_CONFIG.  The book does define it, in "Introduction
to Xorg-7":
    export XORG_PREFIX="/usr"
    export XORG_CONFIG="--prefix=$XORG_PREFIX --sysconfdir=/etc \\
                        --localstatedir=/var --disable-static"
1.12.49 rejected it because the value names another variable.  That rule was
too blunt -- the other variable is defined on the same page -- so definitions
now FOLLOW THE CHAIN (up to four links) and are emitted dependency-first,
XORG_PREFIX before XORG_CONFIG.

The first attempt then produced broken bash: the value continues over lines
with backslashes and a single-line regex captured half of it.  Continuations
are joined now, and anything still ending in "\\" or carrying an unbalanced
quote is DROPPED rather than emitted -- a fragment in a build script is
worse than a question.

XORG_CONFIG is exactly such a case (quoted, multi-line), so it stays a
question -- but `packagemanager env --ask` now offers the book's standard
value, so the answer is one Enter:
    XORG_CONFIG [--prefix=/usr --sysconfdir=/etc --localstatedir=/var --disable-static]:

## One place for the book's build variables  (1.12.54)

Exporting TEXLIVE_PREFIX or XORG_CONFIG in a shell never reached the build:
package builds run through `su -`, which drops the caller's environment.
So they live in one file, /etc/pkgusr/build.env (LFS_BUILD_ENV overrides),
and run_phase_as prepends it to every phase -- one place, every package,
every tool.

    packagemanager env                      # what is set, what is still needed
    packagemanager env --ask                # asks for each one a script needs,
                                            #   offering the book's own value
    packagemanager env --set NAME=VALUE     # one at a time

--ask reads the guards out of the generated scripts (the same
"needs NAME to be set" lines the build would fail on) and pre-fills what the
generator already found in the book (1.12.49), so most answers are a press
of Enter.

STILL WANTED, and not built (the user's second ask): a way to define a GIT
package interactively -- name, ref/branch, build and install commands --
without editing a generated script full of template.  The stack file already
carries exactly those fields
    git foo url=... ref=... prog=... build="..." install="..."
so the command is a small one: ask four questions, write or update that
line.  `packagemanager recipe <name>` is the obvious shape.  Doing it half
now would be worse than not doing it; it is the next session's first task.

## Status about the tree, not the file  (1.12.53)

`--status` reported "1 of 39 entries done" and reprinted the entry table --
which says nothing about the hundreds of packages those entries pull in, and
was the wrong question.  It now resolves each book entry's dependency order
and reports PACKAGES:

    ### stack sway ###
      entries : 3 of 39 done
      packages: 41 of 196 installed
      next    : llvm
      building next: libpng, pixman, docutils, icu, libxml2, ... 
      (full tree: --status --full)
      state   : /usr/src/lfs-pkgusr/progress/stacks/sway.done

Short by default, `--status --full` lists every package with its state, and
the entry table is suppressed in status mode.  The installed judgement is
install_tag -- the same one `search` and the install plan use, so all three
agree rather than inventing a third answer.

## A recommendation is a dependency  (1.12.52)

The user's upload settled it: the install plan had
    texlive-20250308-source   new   recommended by harfbuzz     <- #1
    FreeType-2.14.1           new   required by fontconfig      <- #20
and `blfs order dbus` agreed (texlive 26, FreeType 46).  So the ORDER was
wrong, not the plan's use of it -- packagemanager does use `blfs order`.

_required_edges_win (1.12.33) moved only REQUIRED edges.  texlive's
dependencies are ALL recommended (Cairo, libpaper), so nothing pulled it
after them.  Third time this project has treated a recommendation as
optional and been wrong: _dependencies_come_first now applies both kinds --
required first (it wins any disagreement), then recommended, skipping only
genuine mutual pairs, which the required pass has already settled.

Verified on the real book: freetype2 25 -> fontconfig 26 -> cairo 40 ->
texlive 42, and GLib still precedes shared-mime-info (the 1.12.33 cycle).

Also added, as the user asked: `packagemanager stack <n> --status` --
how many entries are done, what is next, and where the state file lives,
without reading the scrollback.

## No exclusions at all  (1.12.51)

Per the user, after 1.12.50 named texlive and LibreOffice as ignored:
"dont ignore thoose packages! just install them with their deps as we do
with the other ones."

The shipped sway.stack carries no ignore= and no required-only.  The book's
graph is built as the book states it, recommendations included.  It costs
hours (texlive, LibreOffice, OpenJDK, Qt and their tails) and buys a system
that matches the book -- and it removes the class of failure that both
attempts produced, where a package arrived before something it needed
because the graph had been pruned.

`ignore=` remains available as a per-entry option for anyone who wants it;
nothing ships using it.

## Never drop a class of dependencies  (1.12.50)

texlive built before FreeType and died on
    did not find freetype-config required for system freetype2 library
The user's `packagemanager deps texlive` showed FreeType in the plan,
required by Fontconfig, long before texlive -- so why?

Because of MY OWN 1.12.47 change.  `required-only=1`
(--ignore-recommended) was meant to keep texlive and LibreOffice out of a
sway build; it also removed texlive's OWN dependencies, which are ALL
recommended (Cairo, libpaper, the PATH page).  Left with no dependencies,
texlive was scheduled FIRST and built against a freetype that did not exist.
I traded a long build for a broken one.

A recommendation is still a dependency; the book knows why it is there.
Unwanted packages are NAMED instead: `ignore=texlive,libreoffice` on the
entry (--ignore), one explicit decision per package, with the rest of the
graph built in full.  required-only is gone, and the suite fails if it
returns.

## The book already answered it  (1.12.49)

The user pointed at the page: TeX Live's PATH section writes
/etc/profile.d/texlive.sh and sets
    TEXLIVE_PREFIX=/opt/texlive/2025
So asking the user to export it was asking them to repeat the book.

_page_env_definitions collects, for every variable the build commands use
and the script does not set, a simple assignment from the book -- searching
the package's own section first and then the WHOLE BOOK, because this one
lives in a different section ("Setting the PATH for TeX Live", anchor
tex-path, which our parse lists as its own page).  Definitions that
themselves depend on another unknown variable are ignored: that is the same
question moved, not an answer.  Only what remains unanswered is asked of the
user (1.12.47/48).

Verified on the real book: texlive's script now opens with
    TEXLIVE_PREFIX="/opt/texlive/2025"   # set by this package's own page
and the guard no longer fires; nettle and other ordinary packages gain
nothing.

## The warning belongs before the build  (1.12.48)

The user asked for the general safety: not just TeX Live, and not only in
the log afterwards.  Two layers now, and both are general -- they act on
whatever the BOOK's commands reference, package by package:

  * the generated build phase refuses at the top, naming the variable
    (1.12.47), instead of handing configure an empty string;
  * packagemanager warns THE MOMENT THE SCRIPT IS GENERATED -- which is
    before unpacking, patching and configuring -- if such a variable is
    unset in the environment:
        texlive needs TEXLIVE_PREFIX set before it can build:
            export TEXLIVE_PREFIX=...
    and says nothing when it is set.

resolve_script is the one place every script is born, so every package gets
this, including local and git ones.

Still worth doing (not done): collect these across a whole PLAN and print
them once before the run starts, so a 200-package stack asks for everything
it will need up front rather than at package 47.  The pieces are in place --
_warn_unset_env's regex reads the guards out of any generated script.

## An empty expansion is not a value  (1.12.47)

    configure: error: expected an absolute directory name for --datarootdir:
    tar: --strip-components=1: Cannot open: No such file or directory

TeX Live's page tells the USER to `export TEXLIVE_PREFIX=...` first.  Unset,
the shell expanded it to nothing, configure got an empty flag and tar read
an option as a filename -- nonsense far from its cause.  Generated build
phases now refuse at the top and name the variable: every $NAME the commands
use that the script does not set itself and that is not part of its own
vocabulary.  A normal package gains nothing (nettle: 0 guards).

And the deeper question the failure raised: WHY is texlive in a sway build
at all?  harfbuzz RECOMMENDS texlive -- and LibreOffice.  Both are
enormous, neither belongs in this desktop, and a recommendation is a
preference.  Stack entries can now say `required-only=1`
(--ignore-recommended); webkitgtk, gtk4 and mpv carry it in the shipped
sway.stack.

Watch for the trade-off: required-only also drops recommendations that
matter (harfbuzz's Graphite2, icu).  If something later fails for a missing
recommended dep, name it explicitly as its own `book` entry rather than
dropping the flag.

## cairo built its own freetype  (1.12.46)

The four diagnostics answered it in one line:

    ls -l /usr/lib/libfreetype*
    -rwxr-xr-x 1 p_cairo p_cairo 964504 /usr/lib/libfreetype.so.6.20.1
    grep: /usr/src/pkgusr/p_freetype2/pkg.lst: No such file or directory

There is no p_freetype2 AT ALL -- freetype2 was never built.  cairo's meson
fell back to its BUNDLED SUBPROJECTS and installed its own freetype and
fontconfig: owned by p_cairo, with no development symlinks.  The planner
then saw a libfreetype on disk and never scheduled the real package.  Every
"cannot find -lfreetype" in the last four sessions -- ghostscript, cairo,
the "missing dev symlink" diagnosis, the ghost-record hunt -- traces to that
one silent fallback.

Generated meson lines now carry --wrap-mode=nofallback, so a package FAILS
and names the dependency instead of vendoring it.  Added only where not
already specified, never to a commented line.  SCRIPT_VERSION 8.

USER ACTION on the tree: remove cairo's vendored copies and let the real
packages build --
    rm -f /usr/lib/libfreetype.so* /usr/lib/libfontconfig.so*
    lfs-helper build cairo --phase all --force   # after freetype2/fontconfig
then resume the stack (it will schedule freetype2 and fontconfig properly).

STILL OPEN: the planner accepted "a library exists on disk" as proof a
package is installed, with no account, no manifest and no VERSION.  That
check should require a RECORD, not a file someone else installed -- the
wrap-mode fix removes the cause, this would remove the class.

## Ownership is a fact, a manifest entry is a claim  (1.12.45)

cairo failed on -lfontconfig / -lfreetype and the box told the user to
"rebuild cairo" for a FONTCONFIG library.  1.12.30 had made the manifests
the primary source of ownership, and a failed cairo round had swept those
files into cairo's manifest (the over-claiming species of 1.12.13).  The
file's OWNER is a fact; a manifest entry is a claim, and claims have been
wrong before -- so stat comes first now, manifests only when the owner is
root.

STILL OPEN, and the important one: on a REBUILT tree, freetype2 and
fontconfig are installed yet libfreetype.so / libfontconfig.so (the
development symlinks) are missing, exactly as on the old tree.  That is no
longer explicable as old damage.  Next session starts here:
    ls -l /usr/lib/libfreetype*
    grep -c . /usr/src/pkgusr/p_freetype2/pkg.lst
    grep libfreetype /usr/src/pkgusr/p_freetype2/pkg.lst
    tail -40 /usr/src/lfs-pkgusr/logs/freetype2-all.log
The suspects, in order: (1) the install wrapper of 1.12.19 skipping a real
install, (2) something in the phase split dropping the symlink step, (3) the
package genuinely not creating it under meson.  Do not guess -- read the
freetype log first.

## The parent directory decides the group  (1.12.43/44)

The directory came out right and the GROUP was wrong:

    /usr/share/vim/vimfiles  p_cmake  nimgnu_cmake

named after the package that created it, because grant_dir_access names the
group after the DIRECTORY'S owner -- which by then was cmake.  The group
belongs to the tree, not to whoever installed first.

The user then stated the rule exactly, and it is simpler than what I built:
when a package creates a directory inside another package user's directory,
**if the parent already carries a collector group, use the parent's; if not,
ASK** -- the ordinary question, not a silent default.  My first attempt
asked "does a group named after the tree owner exist anywhere", which is not
the same thing and would reuse an unrelated group.

share_new_dir_with_tree_owner now:
  * parent carries <prefix>_* -> inherit it, no question (the decision was
    made when it was put there; a subdirectory of a shared directory is
    shared the same way)
  * otherwise -> ask, offering the tree's name or the creator's or a typed
    one.  Asked even under --yes, because naming a group is a decision, not
    a confirmation; with no terminal it falls back to the TREE's name, never
    the creator's.

Also fixed in passing (1.12.42): mkdir -p left intermediates root:root, and
the next round read that artifact as "root's tree" -- the ancestor walk now
skips past root:root directories that are not real install directories, and
every created component gets the rule.

## A directory we made is not evidence  (1.12.42)

1.12.41 chose the rule by asking the nearest EXISTING ancestor, and the
user's ls showed why that is not enough:

    /usr/share/vim/vimfiles/         root:root      <- made by mkdir -p
    /usr/share/vim/vimfiles/syntax   root:install   <- wrong rule, round 2

`mkdir -p` creates intermediates as root:root.  Round 1 made vimfiles that
way; round 2 read that artifact OF OUR OWN MAKING as "root's tree" and
applied the system rule inside p_vim's tree.  cmake then could not chmod it,
which is the same failure as 1.12.41 one directory deeper.

Two fixes: the ancestor walk continues past a root:root directory that is
not a real install directory (it decides only on an install directory or a
package-owned one), and EVERY component created gets the rule -- not just
the last one -- so no root:root intermediates are left behind to mislead the
next round or to block the package that must install into them.

The suite now replays the user's exact three-round sequence (indent, then
syntax, then a real install dir) and checks all three outcomes.

## Two rules, and I applied the wrong one  (1.12.41)

The created directory failed cmake a second way:
    cannot set permissions on "/usr/share/vim/vimfiles/indent":
        Operation not permitted
and the user named the design error exactly: "the base dir belongs to p_vim,
so the dir created within it should belong to nimgnu_vim ... as we do for
all other dirs".

root:install is the rule for the SYSTEM'S OWN install directories -- the
ones in installdirs.lst, which no package owns.  /usr/share/vim/vimfiles is
not one of those: it is a new directory inside ANOTHER PACKAGE'S tree, and
the model has always answered that case with collector groups.  Applying the
system rule there was wrong twice over: chmod requires OWNERSHIP, so an
installer cannot set modes on a root-owned directory; and it invented a
second rule where one already existed, which is what made vimfiles behave
unlike everything else on the system.

create_missing_dirs_from_log now looks at the nearest existing ancestor:
  * an install directory, or root-owned -> root:install, group-writable
  * another package's tree -> owned by the package INSTALLING into it, then
    grant_dir_access() shares it with the tree's owner through the ordinary
    nimgnu_* group question
Verified both branches side by side in one run.

USER ACTION: they are removing /usr/share/vim/vimfiles by hand, so the next
run recreates it under the right rule.  If any other directory from the
1.12.39/40 runs is root:install inside a package's tree, the same applies --
`lfs-helper verify` will not flag these, which is worth a rule of its own if
it recurs.

## Ask before changing the system  (1.12.40)

The repair worked at last -- /usr/share/vim/vimfiles/indent exists,
root:install, group-writable -- and the user's objection was right anyway:
"that should never happen in any way if not 100%% required and I confirmed."

The OWNERSHIP is deliberate and stays: giving the directory to p_cmake would
make cmake the owner of a subtree inside vim's tree, and block the next
package that installs vim runtime files.  A directory two packages share
belongs to root:install; that is the model.

The SILENCE was wrong.  Creating a directory the book never mentions is a
change to someone else's tree, so confirm_change() now asks, and
create_missing_dirs_from_log goes through it.  assume_yes (--yes / PM_YES /
LFS_ASSUME_YES) is that permission given in advance and the action is still
ANNOUNCED; with no terminal the answer is NO, because silence is not
consent.

Worth applying the same rule to the other automatic repairs (takeover,
share_shared_files, collector grants) in the next session -- they change the
system too, and only the group grant currently asks.

## An empty variable is not a prefix, it is a wildcard  (1.12.39)

The box from 1.12.38 answered it in one line:
    auto-repair: enabled, gate: recognised, rounds run: 0
and no "directories it could create" line at all -- so the detector returned
NOTHING on the real system while finding the path in every sandbox.  The
difference was the root:

    case "$d" in "${SNAP_ROOT%/}"/*)     # in a chroot SNAP_ROOT is "/",
                                         # so this is ""/* and matches nothing
    case "$d" in "$SRCROOT"/*) continue  # with SRCROOT unset this is /*
                                         # and excludes EVERYTHING

Every sandbox used a root like /tmp/xx, where both patterns behave; every
real chroot uses /, where neither does.  Three sessions of "the repair does
not run" came from those two lines.

under_dir() is now the one implementation of "is this path under that
directory", with an empty directory meaning "/" rather than a wildcard, and
missing_dirs_from_log, takeover_files_from_log and the failure-box path
scanner all use it -- so the file takeover was equally broken in the real
chroot and is fixed by the same change.  The suite now runs the detector
with SNAP_ROOT=/ and with SRCROOT unset, which is what would have caught
this on day one.

## Put the evidence in the box  (1.12.38)

cmake failed a third time on the same missing directory, and the 1.12.37
explanation line did not appear either -- so the question "did the repair
run?" was STILL unanswerable from the user's paste.  Three sessions of
guessing from outside is the actual failure here; the repair may well be
fine.

The failure box now states its own reasoning:
    !   auto-repair: enabled, gate: recognised, rounds run: 2
    !   directories it could create: /usr/share/vim/vimfiles/indent
    !   (they are still missing, so creating them did not work ...)
Whatever the next paste shows, it distinguishes the three possibilities that
have been indistinguishable: an old binary on the tree, a gate that refused,
or a creation that failed.  If it says "gate: recognised, rounds run: 0",
the loop's own conditions are the bug; if "created ... " appears and the
directory is still missing, mkdir is failing and the reason must be shown.

## The gate, not the repair  (1.12.37)

cmake failed on /usr/share/vim/vimfiles/indent AGAIN -- the exact case
1.12.15/17 exists to repair -- with no attempt and no explanation in the
failure box.  The repair was fine (verified: the detector finds cmake's
path, the creator makes it).  The GATE was wrong: _perm_ish is set by a
regex listing "cannot (create|remove|change|touch)", and cmake says "cannot
MAKE directory".  The second condition
(`[ -n "$(missing_dirs_from_log ...)" ]`) should also have caught it, so
this needs confirming on the real tree -- see below.

Two changes: "make" joins the regex, and a refusal now SAYS SO --
    # no automatic repair attempted: the failure does not look like
    #   a permission or missing-directory problem
A decision not to act is a decision, and it was invisible; two sessions were
spent guessing whether the loop had run.

STILL OPEN: if cmake fails a third time WITH the new gate, the missing-dirs
detector is not seeing $log at that moment (wrong path? log not yet
flushed?) and the next step is to print what missing_dirs_from_log returns
right there, rather than reason about it from outside.

## Retrying a dead mirror is not a retry  (1.12.36)

    HTTP request sent, awaiting response... 502 Bad Gateway
    download failed (try 1/3) -- retrying in 5s: https://ftpmirror.gnu.org/...
    ... 502 ... 502 ... and libunistring failed

Not a tool bug in the strict sense -- ftpmirror.gnu.org was down -- but
asking the same broken host three times, five seconds apart, is not a retry,
and the file was sitting on every other GNU mirror.  _fetch now walks a
mirror list: the book's own URL first (always), then for GNU hosts
ftp.gnu.org, mirrors.kernel.org and mirror.csclub.uwaterloo.ca with the path
rewritten properly, and for ANY host the LFS downloads mirror by filename as
a last resort.  Backoff grows (15s, 30s) instead of a flat 5.

A guessed GNOME rewrite was written and then deleted rather than shipped:
its path shape was not verified, and an invented mirror that 404s is worse
than none.  Verified: a GNU url yields 5 candidates, an unknown host yields
exactly 2 (itself and the LFS mirror), and the book's url is always tried
first.

## One meaning for "yes", and the whole cache family  (1.12.35)

**`--yes` did not answer the group prompt.**  `stack sway --run --yes` still
stopped at "Which group should share THIS DIRECTORY?".  The prompt honoured
LFS_ASSUME_YES; packagemanager --yes sets PM_YES; pm-install read PM_YES.
Three spellings of one decision -- so `assume_yes()` is now the single
predicate (either variable), used by every prompt in the file, and the
automatic choice is ANNOUNCED ("granting <dir> to group <g> (--yes)")
because an answer taken on someone's behalf must still be visible.

**desktop-file-utils:** "The databases in [/usr/share/applications] could
not be updated" -- update-desktop-database rewriting mimeinfo.cache.  The
info index (1.12.20), the XML catalogs (1.12.31) and this are one question
asked three times, so the whole family goes in at once rather than one
session each: applications/mimeinfo.cache, mime/mime.cache,
glib-2.0/schemas/gschemas.compiled, icons/hicolor/icon-theme.cache.  Each is
REGENERATED from what other packages installed, by whichever package runs
the tool last; none is installed by one package, so none may be owned by
one.  Proven with two real package users on the desktop cache.

## The book's order survives the split into phases  (1.12.34)

The ordering fix worked -- GLib now builds before shared-mime-info -- and
GLib itself then failed:
    ERROR: Program 'g-ir-scanner' not found or not executable

Not a dependency cycle in the plan.  The BOOK resolves the GLib /
gobject-introspection cycle inside GLib's own page, and it does so by going
user -> root -> user:
    build glib with -D introspection=disabled          (user)
    ninja -C gi-build install                          (root)
    meson configure -D introspection=enabled && ninja  (user)
extract_commands_phased sorted blocks into two streams, keeping each
stream's order and LOSING THE INTERLEAVING, so the reconfigure landed in the
build phase -- before gobject-introspection was installed.

Now: once a root block has appeared, every later block joins the install
stream, in the book's own order.  Nothing is lost by moving a command
across, because both streams run as the same package user here (a package
user installs its own files).  Verified on the real book: glib's install
phase reads ninja install / tar / meson setup gi-build / ninja -C gi-build /
ninja -C gi-build install / meson configure -D introspection=enabled /
ninja / ninja install -- exactly the page.  nettle, cmake and libxml2 are
unchanged.  The suite generates glib2 from the shipped book and asserts the
gi install precedes the reconfigure.

## A required edge beats a recommended one  (1.12.33)

docbook-xsl passed (1.12.31 works).  shared-mime-info then died on
    Dependency "glib-2.0" not found, tried pkgconfig
on a FRESH tree, so not damage -- a real ordering bug, and the same one that
was blamed on a "glib ghost" two sessions ago.

shared-mime-info REQUIRES GLib; GLib merely RECOMMENDS shared-mime-info.
walk_deps marks a node visited on entry, so a cycle is broken by whoever was
entered first: exploring GLib's recommended list reached shared-mime-info
while GLib was still in progress, its required GLib edge was skipped as
"already visited", and it was emitted first --
    ... libxslt, shared-mime-info, GLib, desktop-file-utils

A recommendation is a preference; a requirement is a fact.
_required_edges_win moves a required dependency in front of its dependant
after the walk, bounded, leaving all-required cycles alone (those the book
must resolve, and reordering forever would hide them).  Verified on the real
book: GLib precedes shared-mime-info in the orders for desktop-file-utils,
shared-mime-info and glib2 itself.

NOTE for the next session: this bug means ANY package caught in a
required/recommended cycle was mis-ordered, not just these three.  Worth a
sweep of the stack's book targets with `blfs deps <t>` once the build
settles.

## `make install` was breaking the system  (1.12.32)

    (lfs chroot) ls -ald /usr/bin/
    drwxr-xr-x 1 root install 9886 /usr/bin/

775 -> 755: group-write gone, and with it every package user's ability to
install anything.  The user suspected the stack cycle; it was OUR MAKEFILE.
`install -d DIR` applies its mode to a directory that ALREADY EXISTS, so
`$(INSTALL) -d $(BINDIR)` re-moded /usr/bin on every `make install` -- five
such lines (bin, stacks, completions, skel, share).  Every failure in the
build that followed was a symptom of installing the tools.

`mkdir -p` leaves an existing directory exactly as it is; all five now use
it.  Reproduced (775 -> 755 with install -d, unchanged with mkdir -p) and
pinned in the suite, which runs a real `make install DESTDIR=...` over a
775 directory and checks the mode survived.

Repair for a tree already hit: `lfs-helper verify --fix` restores the
install directories.  This also explains the docbook-xsl catalog failure
repeating at 1.12.30 -- the run was made with the tools that had just
re-moded /usr/bin.

## The XML catalog is an index too  (1.12.31)

    could not open /etc/xml/catalog for saving

docbook-xsl, on the REBUILT tree -- so not old damage, a gap.  Exactly the
info-index failure one directory over: docbook-xml creates /etc/xml/catalog
as its own package user, and every later docbook package rewrites it with
xmlcatalog.  1.12.20 said the membership test for shared_files_list is "is
this file REWRITTEN by many packages rather than installed by one" -- the
catalogs qualify, so /etc/xml/catalog and /etc/xml/docbook join the list.

And a real hole in that rule, found while testing it: share_shared_files
fixed the shared DIRECTORY's mode but not its group, so /etc/xml came out
root:root 775 -- group-writable for group ROOT, which helps no package user.
/etc/xml is not in install_dirs_list, so nothing else was going to give it
the group.  It is chowned root:install now, like every other shared
directory.  Proven end to end with two real package users: a catalog created
by one, in a sticky root-owned directory, is rewritable by the next.

## Blame the owner, not whoever ran ldconfig  (1.12.30)

freetype is fixed on the user's tree; fontconfig showed the same missing
development symlink, and the box named the wrong package:

    lfs-helper build libpaper --phase all --force
    (the file is owned by p_libpaper ...)

libfontconfig.so.1 is the SONAME link, made by LDCONFIG under whatever
account happened to run it -- p_libpaper's install, in this case.  The hint
now follows the link to the real library and asks the MANIFESTS who owns
that file, falling back to file ownership; it names fontconfig.

### Recommendation recorded for the user: rebuild rather than repair

The tree carries pre-1.12.x damage: mis-owned files, installs that never
finished (freetype, fontconfig), records that lied.  The tools now prevent
each of those, but every package installed during the broken era may carry
some of it, and each one costs a round trip to find.  A rebuild from the
LFS-base snapshot costs CPU time and no human attention, and everything
after it runs on tooling where these bugs cannot arise.  Advised: restore the
snapshot, `make install` the current tools INTO it first, then
`packagemanager setup --run` and `packagemanager stack sway --run --yes`.
Only valid if the snapshot predates the BLFS installs.

## The ordinary path must not need the sweep  (1.12.29)

The user asked the right question about 1.12.27/28: does a plain
`packagemanager stack sway --run` handle both problems without a manual
`verify --fix`?

  * mis-owned files: YES -- takeover_files_from_log is in cmd_build's retry
    loop, which fires on "Operation not permitted".
  * lying records: NO, and that was the real gap.  `verify` had the majority
    rule since 1.12.10, but the PLANNER used a different one:
    _manifest_has_real_paths returned True on ONE surviving path.  binutils
    (140 of 330 alive) therefore read "installed" to every ordinary install,
    and only the manual sweep disagreed.  Two rules for one question, which
    is this project's oldest disease.

The planner now applies verify's rule: more than half the manifest must
still exist.  Counted over the whole manifest (capped at 5000 paths) --
sampling the first N is wrong, because pkg.lst is path-sorted and a package
whose /usr/bin survived while /usr/share died would look healthy from the
top.  And when a pkg.lst exists it decides: install_last naming a version no
longer overrides a manifest that is mostly gone.

So `packagemanager stack sway --run` alone now rebuilds a package with a
dead record instead of skipping it; `verify --fix` remains the way to clean
the record itself.

## Deleting a lie is a repair  (1.12.28)

The lying-record sweep (1.12.10) was report-only, on the reasoning that
"rebuilding is a build decision, not a repair".  Half right: rebuilding is
the user's call, but the false RECORD is not a build decision at all -- it is
wrong data, and while it stands the planner skips the package and every
dependent fails somewhere else entirely (xmllint, glib, -lfreetype: three
sessions of chasing symptoms of one lie).

`verify --fix` now removes pkg.lst and VERSION for a record whose files are
mostly gone, says so, and names the reinstall for when the user wants it.  A
bare `verify` still only reports.  Pinned in the suite: bare verify deletes
nothing, --fix deletes the liar's record and keeps the honest one.

## Ownership follows the installer  (1.12.27)

The bottom of the whole ghostscript chain, in one line:

    install: cannot remove '/usr/lib/pkgconfig/freetype2.pc': Operation not permitted
    /usr/lib/pkgconfig/freetype2.pc  -rw-r--r--  p_cairo:p_cairo
    in /usr/lib/pkgconfig            drwxrwxr-t  root:install

freetype2's OWN file, owned by cairo -- the over-claiming manifests of
1.12.11 and earlier, made real by a `verify --fix` -- in a sticky (sealed)
directory, where only the owner may replace a file.  EPERM is not something
a collector group can grant away, so the retry loop had nothing to try.  One
cause, four symptoms: freetype's install never finished -> libfreetype.so
missing -> ghostscript could not link -> four sessions of chasing.

In this model the package that installs a file OWNS it (that is verify's
ownership rule), and the installer is by definition installing it now.  So
takeover_files_from_log hands such files over -- loudly, naming the previous
owner -- and the retry proceeds.  Bounded deliberately: only files owned by
another PACKAGE USER, never root's (root's files are not a package's
mistake), and never inside a build tree, /tmp or /sources.

Tested with real package users: the mis-owned file is taken over, a
root-owned one is not, a build-tree file is not.  (Fixture note: package
users need their OWN group -- useradd -U -- or chown p_x:p_x fails and the
test lies.)

## libfoo.so.N is not libfoo.so  (1.12.26)

The user's tree answered the ghostscript question:

    libfreetype.so.6 -> libfreetype.so.6.20.1     exists (p_libpaper, 00:51)
    libfreetype.so.6.20.1                          exists (p_cairo,    00:39)
    libfreetype.so                                 MISSING
    /usr/src/pkgusr/p_freetype/VERSION             does not exist

NOT a lying record: `-lfreetype` needs the DEVELOPMENT symlink libfreetype.so,
which only the package's own `make install` creates.  libfreetype.so.6 is the
SONAME link, which ldconfig makes from any library it finds -- that is why it
carries a later timestamp and an unrelated owner.  So freetype's install
never finished, and the odd ownership is the old over-claiming bug that
`verify --fix` then acted on.

Two illnesses, two cures, and 1.12.25 could not tell them apart -- worse, its
presence check globbed libfoo.so* and so declared libfoo.so.6.20.1 "present",
filtering out exactly the failing case.  Now it checks for libfoo.so (or .a)
EXACTLY, and the box distinguishes:
  * libfoo.so.N present, libfoo.so absent -> the owner's install did not
    finish; rebuild it (the owner is named from the file's ownership).
  * nothing at all -> a dependency recorded as installed that is not.

User's cure for this tree: rebuild freetype and fontconfig
(lfs-helper build freetype2 --phase all --force, likewise fontconfig), then
resume.  Their records were never written, so the planner will not skip them.

## The linker's version of the same sentence  (1.12.25)

ghostscript got past configure (1.12.24 worked) and died linking:
    /usr/bin/ld: cannot find -lfontconfig
    /usr/bin/ld: cannot find -lfreetype
Same species as "Program 'xmllint' not found": a dependency the planner
believes is installed did not leave its library behind.  The failure box now
says so -- it extracts the -lNAME list, keeps only the ones genuinely absent
from /usr/lib, /usr/lib64, /lib, /lib64, /usr/local/lib, and prints the cure
(packagemanager search libNAME; lfs-helper verify; purge pkg.lst+VERSION;
reinstall).

A bug found while testing the check, worth recording because it is a
classic: `ls a* b* c*` returns non-zero when ANY pattern misses, so a
library present in the first directory was reported missing because the
other two lacked it.  One glob per directory now, and the suite pins both
halves (a missing library IS named, an installed one is NOT).

Open on the user's system: freetype and fontconfig are recorded as installed
but their libraries are absent -- ghosts of the same family as glib.  The
sweep (verify) plus the printed cure is the path; if freetype turns out to
be installed and only its .so symlink missing, that is a different bug and
worth its own look.

## Four causes behind one ghostscript failure  (1.12.24)

    configure: error: Mixing local libtiff with shared libjpeg not supported
    make: *** No rule to make target 'so'.  Stop.
    install_gs: line 118: gs: command not found
    mv: cannot stat '/usr/share/doc/ghostscript/10.06.0'

**Why configure failed.**  The block that prevents it --
"If you have installed the recommended dependencies on your system, remove
the copies of freetype, lcms2, libjpeg, libpng, and openjpeg:
 rm -rf freetype lcms2mt jpeg libpng openjpeg" -- was COMMENTED as
conditional.  But these tools install required AND recommended dependencies
by default; that is the contract.  A condition predicated on what we
guarantee is satisfied by construction, so _conditional_guard now keeps such
blocks active ("optional" still wins over both).

**Why everything after it ran anyway.**  `unpack_pkg && build_pkg || exit 1`
reads like it stops on failure and does the opposite: POSIX disables set -e
inside a function whose status is being TESTED.  The phase bodies' own set -e
(1.12.8) was switched off by the CALL.  The dispatcher now runs `set -e` with
sequential calls, and the PM_TEST condition is an if, not an and-list (which
would abort the run when false).

**Two things that only became dangerous once failures stop the run.**  The
book demonstrates results with the package's own not-yet-installed program
("gs -q -dBATCH .../tiger.eps"); and it offers test commands in the build
section.  Chasing the wording ("To do this...") is the mistake this file
keeps making, so the rule is structural: a build line whose first word is a
program THIS package installs is commented out.  Test blocks are matched by
_TEST_BLOCK_RE as a smaller, separate rule.

Known cosmetic gap: `make so` stays active in the build while its install
("If you built the shared library...") is skipped -- harmless (libgs.so is
only wanted by asymptote/ImageMagick) but inconsistent.

## The tool died on its own source  (1.12.23)

    # libjpeg: done
    Installed. Refreshing mandb in the background...
    /usr/bin/lfs-helper: line 8312: mmand: command not found
    /usr/bin/lfs-helper: line 8314: syntax error near unexpected token `)'

Line 8312 is a COMMENT containing the words "a command", and bash read
"mmand".  Nothing was wrong with libjpeg -- it had built and installed.  The
shipped file parses cleanly; the one on disk was REPLACED while bash was
executing it, and bash reads scripts incrementally by byte offset, so
execution resumed mid-word in the new content.  (A `make install` of a new
build in another terminal will do it; so would any tool refresh.)

Everything in lfs-helper is now one group command -- `{` after the header,
`}` at the end -- so bash parses the WHOLE file before executing any of it;
after that the file on disk may change freely.  Functions and variables in a
group are global, exit still exits, the status is the last command's.
Verified working wrapped, and the suite pins the shape (first non-comment
line is `{`, last line closes it, and the tool still runs).

blfs/packagemanager/lfs are Python, which reads the file whole -- immune by
construction.  lfs-sanity.sh is bash but short-running; worth the same
treatment if it ever grows.

## The same failure, one layer earlier  (1.12.22)

The user asked whether the LFS BASE build hits this too.  It does, and
1.12.21 left the gap: /usr/share/info/dir usually does not exist when
init-pkgusr runs -- it is created mid-build by the first package that ships
an info page, owned by THAT package user -- so the second such package
fails, is repaired by the retry loop, and the user watches a failure that
never needed to happen.  Chapter 8 hits this on every fresh system.

cmd_build now shares the indexes BEFORE the build (pkgusr_ready &&
share_shared_files, idempotent and cheap), so the file is root:install 664
before anyone needs to replace it.  The auto-fix path stays as the net for a
tree that predates this.

Proven with real accounts: package A creates the index (p_a:install 644),
package B cannot replace it, sharing takes it into root:install 664, package
B can.  That is the LFS chapter-8 sequence exactly.

## Sealing and sharing were contradictory rules  (1.12.21)

1.12.20 made /usr/share/info/dir root:install 664 and nettle failed at the
same line.  The message said which half was missing all along: **Operation
not permitted**, EPERM, not EACCES.  install-info does not write the index
in place -- it writes dir.new and RENAMES it over the old file, and in a
STICKY directory only a file's owner may replace it.  /usr/share/info is an
install directory, the tree is sealed, so no mode on the file could ever
have helped.

Two of this project's own rules were in direct contradiction: sealing
(sticky, so package users cannot delete each other's files) and sharing
(every package must replace this file).  A directory that holds a shared
index is now excluded from sealing -- in share_shared_files (which clears
the bit: g+w,o-t), in cmd_seal_install_dirs (which skips it and says so),
and in _vfy_install_dirs (which wants 775 there even on a sealed tree, so
the next verify does not put it back).

Reproduced in the suite before fixing: a real package-user account, a
sticky root-owned index, the rename fails with exactly EPERM; after the
rule it succeeds.  That test is the one that would have caught 1.12.20
being half a fix.

## A shared index is shared, not owned  (1.12.20)

    install-info: Operation not permitted for /usr/share/info/dir

nettle died there AFTER installing its libraries.  /usr/share/info/dir is
the info INDEX: every package that ships an info page rewrites it.  It has
been in never_claim_list since early on -- nobody OWNS it, correctly -- but
nothing ever made it WRITABLE by the package users who must update it.  Half
a rule: we knew whose it wasn't, and never said whose it was.

A shared DIRECTORY is root:install and group-writable.  A shared FILE is the
same rule one level down: shared_files_list + share_shared_files (root:install
664, idempotent), applied in the three places that matter -- init-pkgusr when
the system is set up, verify --fix on an existing tree, and cmd_build's
auto-fix loop, so a build that hits it repairs and retries instead of dying.

The list is deliberately short (just the info index today).  Anything else
that turns out to be a shared, rewritten-by-everyone file belongs there too
-- and that is the test to apply, not "which package installed it".

## What runs decides, twice over  (1.12.19)

alsa-lib failed two ways at once, and both were label-reading:

    tar: ../alsa-ucm-conf-1.2.15.3.tar.bz2: Cannot open
    install: cannot stat 'doc/doxygen/html/*.*'

**Downloads follow the commands.**  1.12.8 kept additional downloads whose
label said "required", plus every .patch.  alsa-ucm-conf is labelled
"Recommended file:" and is used by a command that is NOT conditional:
    make install && tar -C /usr/share/alsa ... -xf ../alsa-ucm-conf-...
Reading the label is guessing; reading the commands is knowing.  The
extractor now collects every listed download, and _needed_additional_links
keeps the ones an ACTIVE (uncommented) phased command names -- patches
always.  Verified: alsa-lib keeps its tarball, docbook-xsl only its patch,
libxml2 and libuv keep nothing (their extras are commented).  Note the trap
found on the way: data["install_cmds"] is the RAW page, where conditional
blocks are still live and vote for their own downloads -- only the phased
text may be consulted.

**An artifact that was never built is not a failed install.**  The book
installs optional extras the package's own `make install` does not produce
(alsa's doxygen html, libuv's sphinx man page).  Without the optional tool
the sources do not exist, and install killed a package that had built and
installed correctly.  The install WRAPPER now skips when EVERY source
argument is missing, loudly ("an optional artifact that was never built --
not a failure"); a partial set still goes to the real install, so a
genuinely half-built package is not hidden.  One place, every package --
and it retro-fixes the libuv class too.

## Book prose is data; our shell options are ours  (1.12.18)

    install_texlive-20250308-source: line 25: TEXLIVE_PREFIX: unbound variable

Line 25 is metadata lifted from the book's Contents section --
"Installed Directories: $TEXLIVE_PREFIX/bin, $TEXLIVE_PREFIX/lib" -- emitted
inside DOUBLE quotes, so the shell expanded it.  Two independent causes, both
fixed:

1. The generator now emits every book string through bash_str(): single
   quoted, with the one escape single quoting needs.  A dollar sign in
   documentation is not a variable, and a backtick in it is not a command.
   (bash_array uses it too.)  SCRIPT_VERSION bumped to 5.
2. pm-install sources the script only to read that metadata, and did so
   under THIS shell's set -u.  Our strictness governing their file is a
   category error, and would keep producing failures that are ours, not
   theirs: it now saves $-, does set +u +e around the source, and restores.

Also answered for the user: the ~195 "regenerating" lines are the
generator-version check (1.12.16 -> 1.12.17) doing its job once, not lost
work; the plan is re-resolved per stack ENTRY, and a book entry with 195
pending dependencies re-plans them until they are installed.  Possible
improvement if it grates: cache the resolved plan per entry and offer to
reuse it (the plan cache exists -- "plan cache v1" in --version -- but the
per-entry resolve still runs).

## The pattern, not the wording  (1.12.17)

libpaper died writing /etc/profile.d/libpaper.sh -- the directory does not
exist, exactly the class 1.12.15 was supposed to have fixed.  It did not
fire because 1.12.15 matched MESSAGE WORDINGS (cmake's `cannot make
directory "X"`, coreutils' `cannot create directory 'X'`) and bash words a
failed redirection differently:
    install_libpaper: line 150: /etc/profile.d/libpaper.sh: No such file or directory
The same mistake as the verb list in the book guard, made by the same
author two releases later.  Every tool words it differently; the pattern is
"No such file or directory" plus an absolute path.

missing_dirs_from_log now works from that pattern, with two classes and one
rule each: a directory the tool tried to CREATE -> make that path; anything
else that could not be written -> make its PARENT.  Both only when the
directory chain really is what is missing (if the parent exists, the error
is about a file, and inventing a directory would turn a clear message into
a mystery), and never inside $SRCROOT, /sources, /tmp or a build tree --
a path that failed there is the build's own problem.

Verified on five real line shapes at once: cmake's directory, bash's
redirection, a missing source file in a build tree, a missing file whose
directory exists, a relative path.  Only the first two are acted on.

## A compile error is not ours, but the cure has a home  (1.12.16)

cairo 1.18.4:
    error: static declaration of 'ctime_r' follows non-static declaration
Cairo's HAVE_CTIME_R check came out false, so cairo-ps-surface.c defined its
own static ctime_r and collided with glibc's.  The book carries no patch --
this is the package's source against a newer toolchain, and the tools cannot
and should not repair a package's C.

What IS ours: making sure the cure survives.  A hand-edit of the generated
script is lost on --regenerate; machine.conf is the place that persists and
is per-package.  Shipped:
    [cairo]
    c_args = -DHAVE_CTIME_R
merged into cairo's `meson setup` line by apply_machine_opts (verified).
And the failure box now says so: on a real compile error
(file:line:col: error:) it states that this is the package's own source,
not a permission or layout problem, and prints the machine.conf shape for a
per-package build flag.

Note the honest boundary here (ALWAYS TREAT THE CAUSE): the cause is
upstream cairo, which we cannot fix; what we fixed is that the workaround
had nowhere durable to live and the failure said nothing about it.

## A directory that is not there cannot be granted  (1.12.15)

cmake installs into /usr/share/vim/vimfiles/indent -- vim's tree, a
subdirectory that has never existed:

    file INSTALL cannot make directory ".../vimfiles/indent":
        No such file or directory

Not a permission problem, so the grant machinery never fired (and could not
have helped): the directory is not unwritable, it is ABSENT, and a package
user may not create it inside another package's tree.  The model has always
had the answer for a directory two packages share -- root:install,
group-writable -- but nothing applied it ON DEMAND, so every package that
installs into a new subdirectory of another package's tree hit this.

cmd_build's auto-fix loop now creates them: missing_dirs_from_log reads
DESTINATION directories out of the log (cmake's `cannot make directory "X"`
and coreutils' `cannot create directory 'X'`), create_missing_dirs_from_log
makes them as root with set_install_dir_owner + g+w, and the loop tries
creating before granting, since a round often needs both.  Deliberately NOT
matched: `install: cannot stat 'X'`, which names a SOURCE the build never
produced (libuv's man page) -- creating a directory there would turn a clear
error into a mystery.

## A condition is a condition  (1.12.14)

libuv died on `install: cannot stat docs/build/man/libuv.1`.  The 1.12.6
guard had caught the block that BUILDS the man page ("If you installed the
optional sphinx-9.1.0 python module, create the man page:") and missed the
one that INSTALLS it ("If you built the man page, install it as the root
user:") -- because the guard enumerated verbs (wish|want|downloaded|have|
installed|...) and "built" was not among them.  So the page was never made
and the install of it ran anyway.

Enumerating verbs is guessing at English; the pattern is the conditional
opening.  _COND_GUARD_RE is now ^(if\b|optionally\b|should you\b) -- any
sentence that opens with a condition guards its block.  Skipping stays safe
either way: the block is emitted commented with the book's own sentence
above it, one uncomment away.  Verified on the user's book: libuv's man
build AND its install are both commented, `make install` stays active, and
libxml2's mandatory root sed on xml2-config is untouched.  CACHE_VERSION
bumped to 6.

(Same lesson as the h3/h4 fix and the settle fix: the list of cases is not
the rule.  See ALWAYS TREAT THE CAUSE at the top.)

## The cause of the over-claiming manifests  (1.12.13)

The user asked what actually caused the 711 wrong-owner claims, and whether
it was one package or a leak.  It is a leak, and it is structural.

cmd_build decides what a package installed BY TIMESTAMP: drop a stamp, run
the build, claim every file newer than the stamp.  That rests on one
assumption -- nothing else writes to the tree during a build -- and the
user's run disproved it.  make-ca (package 98) was still generating
/etc/ssl/certs and /etc/pki/anchors at 19:45, after its own scan had closed,
while libogg (99) was building: libogg's manifest claimed ~400
certificates.  The files themselves were fine (root:root); the MANIFEST was
wrong, which is why --fix was dangerous.  Same mechanism gave p_docutils our
own `make install` files and p_wget /tools.  Any writer active during a
build window is attributed to whoever is building -- and this toolchain
supplies such writers itself, detaching mandb and record-install with setsid
precisely so they outlive the install.

Fix at the cause: the attribution window does not open until the tree is
quiet.  _settle_tree_before_stamp waits (bounded, LFS_SETTLE_SECONDS,
default 60) for a NAMED list of writers -- mandb, make-ca,
update-mime-database, gtk-update-icon-cache, gdk-pixbuf-query-loaders,
glib-compile-schemas, fc-cache, p11-kit, trust, list_package -- then stamps.
Named rather than "any activity", which would hang on whatever the user is
doing on purpose; and bounded, so a stuck mandb warns that the manifest may
over-claim instead of stopping the build.

The 1.12.11 path shields stay: they also cover files written outside any
build window at all.  But they are no longer the fix.

## Sealing is one-way  (1.12.12)

The user asked the right question about the verify log: what CAUSED the
wrong install-dir permissions?  Answer: nothing on the tree -- the ~50
"installdir ... 1775 -> 775" lines were verify proposing to STRIP correct
sticky bits.  _install_dirs_are_sealed demanded that all five probed
directories be sticky; the user's tree is partly sealed (sealing
interrupted, or install dirs created after the seal), so it read as "not
sealed at all", and the unsealed-phase rule (775) was then applied to
directories that had been deliberately sealed.  A `verify --fix` would have
unsealed half the system.

Now: ANY sticky install directory means sealed (probe widened to 12, mixed
state warned about).  Sealing is a deliberate one-way end-of-build act, so
verify COMPLETES it on stragglers and never takes it back.  A never-sealed
mid-build tree has no sticky install dirs and still reads unsealed, which
is what the build needs.

**Still NOT fixed at the root: the 711 wrong-owner claims (1.12.11).**  The
cause is structural -- cmd_build attributes every file newer than its stamp
to the building package, and detached background work (make-ca's cert
regeneration, `make install` of these tools, mandb) runs during someone
else's build.  1.12.11 shielded the paths this actually hit; the general
cure is to stop guessing by timestamp (per-phase DESTDIR staging already
exists for the install phase -- extending it, or ignoring files whose mtime
falls inside a known background task's window, is the next real fix).

## What the sweep found  (1.12.11)

The first real sweep on the user's system answered both open questions.

**glib was never the tool's fault.**  `blfs order desktop-file-utils` puts
GLib-2.86.4 in the plan, correctly (an earlier `head -8` of mine truncated
it, which is how it looked missing).  So glib is judged installed while
pkg-config cannot find it: another ghost, and the planner therefore starts
at desktop-file-utils.  The sweep names p_binutils a liar (330 claimed, 190
missing, 57%) but says nothing about glib -- so glib's "installed" verdict
comes from a validate/library check rather than a pkg.lst, or its record is
just under the 50%% threshold.  Next session: teach the sweep to also judge
a package the PLANNER calls installed whose account/record does not exist,
and consider a `packagemanager why-installed <pkg>` that prints which
signal decided it.

**711 wrong-owner claims, one species.**  p_libogg claiming every
/etc/ssl/certs file, p_make-ca the /etc/pki anchors, p_docutils
/etc/pkgusr/stacks and /usr/share/lfs-pkgusr, p_wget /tools.  None of them
installed those: make-ca's detached background regeneration and `make
install` of these tools ran DURING someone else's build, and the timestamp
scan sweeps whatever is newer than the stamp.  `verify --fix` would have
chowned the system certificate store to libogg.  never_claim_list now
covers /etc/ssl/certs, /etc/pki, /etc/pkgusr, /usr/share/lfs-pkgusr and
/tools -- regenerated-on-demand or ours, same class as
/usr/share/info/dir.  **The user must NOT run `verify --fix` on a
pre-1.12.11 helper.**

## The sweep for every lie at once  (1.12.10)

desktop-file-utils: `Dependency "glib-2.0" not found` -- while
shared-mime-info, which requires the same glib, had just built.  The book's
dep extraction is CORRECT (verified against the uploaded book: both require
GLib-2.86.4, ordered first), so either glib is recorded-but-absent (another
ghost) or something environmental.  Rather than guess one crash at a time,
the deferred detector is built: verify rule 3c, _vfy_lying_records, reads
every pkg.lst under $PKGUSR_ROOT and counts how many claimed paths exist; a
record with >=50%% of its files missing is named a LIAR with the exact cure
(rm pkg.lst VERSION; packagemanager install <pkg> --run).  Report-only --
rebuilding is a build decision, not a repair.  Wired into cmd_verify after
the unclaimed pass.

Diagnostics handed to the user for the glib mystery (their output decides
the next fix):
    lfs-helper verify                      # the sweep names every ghost
    pkg-config --exists glib-2.0; echo $?
    ls -la /usr/lib/pkgconfig/glib-2.0.pc
    cat /usr/src/pkgusr/p_glib2/VERSION 2>/dev/null

## The lie on disk, and the box that names it  (1.12.9)

shared-mime-info: "Program 'xmllint' not found".  xmllint is libxml2's --
and libxml2 was NEVER really rebuilt: the 1.12.7 recorder gate stops new
lying records, but the pre-fix pkg.lst still sits in p_libxml2's home and
the planner believes records.  Worse, docbook "succeeded" under a
pre-set-e script whose xmlcatalog failures were mid-script and ignored, so
its catalog registration is silently missing too.

Tree remedy (given to the user):
    rm -f /usr/src/pkgusr/p_libxml2/pkg.lst /usr/src/pkgusr/p_libxml2/VERSION
    packagemanager install libxml2 --run --yes
    packagemanager script install DocBook     # redo the skipped catalog steps
    packagemanager stack sway --run --yes

Tool side: the failure box now recognises the pattern.  On "Program 'x'
not found" where x really is absent from the system, it says a dependency's
record probably LIES (pre-1.12.7 failed build), and prints the cure:
search for the owning package, purge its pkg.lst/VERSION, reinstall.

Open question for a later session: a one-shot detector for remaining
pre-1.12.7 lying records (a verify pass comparing each record's claimed
programs against the filesystem) -- the failure-box hint covers the
discovery path for now.

## Required patches exist, phases fail loudly, caches notice  (1.12.8)

docbook-xsl, third stack failure, three causes in one crash:

**additional_links was empty for EVERY package in the 13.0 book.**  The
extractor looked for an <h3>Additional Downloads</h3>; this book edition
uses <h4>.  The tag is layout, the title is the contract -- it matches h3 OR
h4 now, by get_text().  And the extractor collects only REQUIRED entries
plus every .patch; optional doc/test tarballs stay uncollected, matching
their commands being emitted commented.  CACHE_VERSION bumped to 5 so the
parsed index rebuilds (the suite's guard now checks >= instead of an exact
number that itself went stale on the bump).

**A failed patch was shrugged off for 1900 lines.**  Command blocks joined
without set -e meant `patch: Can't open ...` at line 2 and a "successful"
unpatched build until the optional cp finally tripped.  Every generated
phase body opens with set -e now -- bodies do not execute on `source`, so
pm-install's sourcing of the script is untouched.

**The /tmp script cache did not notice a moved GENERATOR.**  "version-keyed
= safe" caught a moved book, not a fixed blfs: the user's run reused a
pre-1.12.6 docbook-xsl script whose optional blocks were still active.
resolve_script now compares the cached script's "### generated by blfs X"
header against the live generator's version and regenerates on mismatch.
(Local scripts in package homes stay sacred -- user edits win; a stale
pre-fix HOME copy still needs a manual rm, as with libxml2.)

User remedy for the current failure:
    rm /usr/src/pkgusr/p_docbook-xsl/install_docbook-xsl-nons-1.79.2
    # stage the patch or let _fetch get it, then resume the stack

## A failed build makes no claim  (1.12.7)

Second --run: docbook died on `xmlcatalog: command not found` -- a program
libxml2 installs, in a plan the book orders correctly (libxml2 first).  The
planner had SKIPPED libxml2 as installed, because the previous FAILED
libxml2 run had still called cmd_record_install: pkg.lst with 4 half-built
files, and pkg.lst is what the planner believes.  The very next comment in
cmd_build says "A FAILED build must not take ownership of anything" -- the
recorder now obeys the same rule: gated on rc==0.  The manifest (what a
step TOUCHED) rightly survives failure; the claim of installation does not.
User remedy on the tree: `lfs-helper build libxml2 --phase all --force`
rebuilds it for real (the planner cannot, it still believes the lie until
the record is rewritten by a successful build).

The failure box printed p_docbook and p_DocBook in one breath: python's
pkgusr_name did not lowercase, the helper's pkg_owner_name does.  Python
now lowercases first, same as the helper -- one casing rule for every name.

And the user's ask: `stack --run` now CACHES completed entries per stack
file ($LFS_PKGUSR_DIR/progress/stacks/<n>.done, "kind target" lines).  A
resume skips them as "done (stack cache)" instead of re-planning a
200-package tree for a stage already finished; --force ignores the cache.

## The book's conditionals stay conditional  (1.12.6)

First --run: 217-package plan, died at 2/217 in libxml2 -- `ERROR: Program
'doxygen' not found`, plus a missing xmlts test tarball.  The user called
it: "in the script we include the docs [but] we don't install the
requirements for it."  The book agrees -- both blocks sit under prose
conditionals ("If you wish to build and install the manual pages...", "If
you downloaded the test suite...") that the extractor ignored, taking every
<pre> unconditionally.

extract_commands_phased now reads the paragraph INTRODUCING each command
block (_conditional_guard: "If you wish/want/would like/downloaded/have/
prefer/need/did/are going to/installed", "Optionally", "Should you", "If,
instead").  A conditional block is emitted COMMENTED with the book's own
sentence above it -- visible, one uncomment away.  Proven against the
user's real 13.0-systemd book (uploaded this session): libxml2's meson
setup and the mandatory xml2-config sed stay active; docs=enabled and the
xmlts tar are commented.  Class fix: applies to all 217 pending scripts.

RESUME TRAP: a failed pre-fix run leaves the OLD script in the package's
home, and resolve_script deliberately prefers local copies.  The user must
`rm /usr/src/pkgusr/p_libxml2/install_libxml2-2.15.1` (and likewise for any
other pre-fix leftover) before re-running the stack.

The suite's 4 remaining bare-checkout fails need the LFS book (not BLFS) --
still environment-gated.

## A book entry can carry its own fallback  (1.12.5)

Per the user: elogind must build even where the book lacks it.  Generalised
rather than special-cased: a `book` entry carrying url= (plus the usual git
opts) FALLS BACK to a git entry when the dry run judges it NOT IN BOOK --
it no longer trips the refusal, and shows "not in book -> git fallback".
One stack file now serves a system whose book flavour has the package and
one whose book does not.  elogind carries url=github.com/elogind/elogind
ref=v255.17 prog=loginctl with a meson build (-Dcgroup-controller=elogind).
The 1.12.4 flavour fix still matters -- the BOOK build is the better one
(BLFS's configure choices + dependency resolution); the fallback is the
safety net, not the plan.

## The book flavour follows the system  (1.12.4)

The second judged dry run on the real machine came back with every anchor
green except one: elogind, still NOT IN BOOK.  The root cause was a
constant: `DEFAULT_SELECTOR = "stable-systemd"` -- on a SysV system, blfs
defaulted to the wrong flavour unless told otherwise, which is exactly how
the systemd book got onto the 13.0-sysv chroot in the first place (the old
open item, closed here).  The default is now decided by the running init
(/run/systemd/system exists -> systemd, else sysv); an explicit
`blfs set-default` always wins.

For the user's machine: `blfs fetch stable-sysv && blfs set-default
stable-sysv` (or just delete the stored default and let the new rule
decide), then the dry run judges elogind and --run is unblocked.  Closing
the old open item: "BLFS must not pick a systemd-flavour default on that
system" -- it no longer can.

## The machine's options, and the anchors trued up  (1.12.3)

The first judged dry run on the real system named seven wrong anchors.
Fixed from the machine's own `packagemanager search` output: the gstreamer
family is gstreamer10 / gst10-plugins-{base,good} (bad ADDED -- the user
needs it), mpv joins the stack, dejavu-fonts became a `tar` entry (new stack
kind, tarball through the same template; needs url= and pkg=), and
sdl3-image/-ttf became pinned git entries (SDL_image release-3.2.4,
SDL_ttf release-3.2.2, cmake builds, have=/usr/lib/libSDL3_*.so).

**elogind NOT IN BOOK is a flavour smell, not a missing page**: the system's
default book is BLFS-BOOK-13.0-systemd-nochunks (see the 1.11.56 verify
log), and elogind only exists in the SysV edition.  The user must switch the
default book to the plain 13.0 edition BEFORE --run, or every generated
script leans systemd.  This is the old open item about BLFS flavour defaults
on the SysV system, now with teeth.

**Machine option overrides are wired.**  /etc/pkgusr/stacks/machine.conf
(PM_MACHINE_CONF overrides the path; ships with the user's mesa flags:
radeonsi, amd, x11+wayland, video-codecs=all, glvnd/libunwind disabled,
llvm on).  apply_machine_opts merges each [anchor] key into the generated
script's `meson setup` line as -Dkey=value -- existing keys replaced, new
ones appended -- at the ONE place scripts are born (resolve_script's
generation return).  The change makes the script a local edit, which
resolve_script then deliberately keeps across runs.  meson only; cmake
merging (llvm options) pending if ever wanted.

## The dry run asks the book  (1.12.2)

The user read the first real dry run and said the quiet part: "sway and
wlroots are also git repos" -- BLFS carries neither, and the dry run had
printed "book" for every book entry WITHOUT LOOKING.  A plan half-judged
would have discovered that one llvm build too late.

Now the dry run asks: each book entry is looked up via book_version, with
one availability probe first (book_version cannot tell "anchor absent" from
"no book on disk", so without a book every entry reads "unjudged" instead of
a false NOT IN BOOK).  Unknown targets warn on a dry run and REFUSE a --run.

The stack file grew what the book lacks, as pinned git entries with real
build commands -- which forced the parser onto shlex (build= carries
spaces; values are quoted now) and added have=<path> as the doneness signal
for libraries that put nothing on PATH (prog=- disables the PATH check):
seatd 0.9.1 (libseat-logind=elogind), wlroots 0.19.2, sway 1.11, swaybg
v1.2.1, and a terminal the stack had silently omitted -- foot 1.24.1 with
tllist 1.1.0 and fcft 3.3.2.  37 entries now.  Pins are best-guess release
tags: a wrong one fails the clone, stops the stack, and is a one-line fix.

Still pending: machine option overrides (mesa flags), and the book-anchor
names (sdl3*, dejavu-fonts, xwayland, gtk4...) get trued up by the first
dry run on the real machine now that it judges.

## One command, one environment: `packagemanager stack`  (1.12.1)

The next goal is a working Sway desktop with the user's own WebKitGTK-6.0
browser (github.com/nimbin2/Browser -- GTK4, so the whole stack is GTK4) and
the Sw* family (SwBr: wayland; SWOv/SwAS: SDL3).  Decisions locked with the
user: LLVM yes, Mesa radeonsi+amd (options must become per-machine), Xwayland
yes, ALSA as the floor with pipewire started on demand.

`packagemanager stack <name> [--run]` replays a declarative plan file, top to
bottom, through the machinery the fresh build proved: `book` entries via the
ordinary install planner (BLFS resolves deps, installed is skipped), `git`
entries via an auto-generated template (family convention `make all && make
PREFIX=/usr install`, doneness = prog= on PATH, --force rebuilds), `check`/
`cfg` entries as root scripts beside the stack file, run through run-script
--as-root; a failing check STOPS the stack.  Dry run by default; malformed
plans are refused with a line number.  Stack files are found at the given
path, /etc/pkgusr/stacks/, or stacks/ beside the tool; `make install` ships
stacks/.

Shipped: stacks/sway.stack (33 entries, kernel check -> seat/session ->
llvm/mesa -> wayland/sway -> gtk4/webkitgtk -> alsa+pipewire -> sdl3 -> the
four nimbin2 repos -> session wiring), stacks/kernel-sway.sh (verifies DRM,
evdev, snd, seccomp, user namespaces, tmpfs, a render node -- builds
nothing), stacks/sway-session.sh (writes /usr/bin/sway-session =
dbus-run-session sway, /usr/bin/pipewire-start for on-demand audio, and a
sway config skeleton for $LFS_HOME_USER with the Sw* binds).

**Pending for the stack (next session):**
- Machine option overrides (opts=@mesa -> /etc/pkgusr/stacks/machine.conf
  [mesa] section merged into the generated script's meson line).  The user's
  flags: gallium-drivers=radeonsi vulkan-drivers=amd platforms=x11,wayland
  video-codecs=all glvnd=disabled libunwind=disabled llvm=enabled.
- Book target names in sway.stack are UNVERIFIED against the real 13.0 book
  (sdl3*, dejavu-fonts, xwayland anchors may differ) -- the first dry run +
  install on the machine trues them up.
- sway-session.sh appends Sw* binds only when creating a FRESH config.

## Four tools  (1.12.0) -- plan step 7, the endpoint

packagemanager_install is DELETED.  No shim, no fallback, at the user's
explicit request -- and both `make install` and lfs's chroot tool sync now
SWEEP a previously installed copy off the system, because a stale fifth tool
on any PATH is old code waiting to run.

What survived it lives in `lfs-helper pm-install <account> <script>`: the
front-matter transplanted near-verbatim (the exact bash that carried the
fresh build), behind one command.  Name resolution through pkg_owner_name,
the confirm prompt (PM_YES), account creation via the hint's add_package_user
plus the in-process home repair and user sort, tarball staging from /sources
(_pm_stage_source), collector-group membership (_pm_check_groups), the
install_last/diff/script records, and the two special installers --
_pm_install_collector_dirs for nimgnu_ accounts, _pm_install_app_user for u_
accounts (pam su rule, shared dir, launcher; the desktop user is
LFS_HOME_USER, default n76310, no longer hardcoded).  Then the script goes to
the one loop: cmd_build --script for phased scripts, run_phase_as +
record-install for a rare old-style one.  packagemanager's find_pm_install
returns `lfs-helper pm-install`; PM_YES/PM_MODE/PM_NO_AUTO_FIX still work.

Deliberately dropped: the installBaseScript/vim editing flow, and the
engine's private runner/retry/wrapper/recorder block.

The suite lost 22 counted results and gained the replacements: tests of the
deleted legacy loop are gone; tests of behavior that MOVED (staging order,
home settlement, name resolution, one recorder, one runner) now point at
pm-install; new checks assert the tool STAYS retired (its presence in tree
or chroot is now the bug) and an end-to-end pm-install run installs, records
under the step name, and keeps install_last.

## The script owns the source search  (1.11.58)

First real run of the one loop, on a fresh 13.0-sysv bootstrap: wget's own
install tried to DOWNLOAD wget.

    staged /sources/wget-1.25.0.tar.gz -> /usr/src/pkgusr/p_wget
    ...
    install_wget: line 33: wget: command not found
    md5sum: wget-1.25.0.tar.gz: No such file or directory

Generated scripts open with `BUILD_ROOT="${BUILD_ROOT:-$PWD}"` and looked for
the tarball ONLY in that directory.  Under the old engine nothing set
BUILD_ROOT and `su -` started in $HOME -- so "look in ." found the file
packagemanager had staged there, by accident.  The one loop exports a real
BUILD_ROOT, and the accident stopped happening.

The fix is at the chokepoint: the SCRIPT owns the decision of where a source
might already be, so it no longer depends on who runs it or from where.
Before any download it now searches $HOME/<tarball> then /sources/<tarball>
and copies the file in; additional_links get the same rule, and are no
longer re-fetched when already present.  Scripts are regenerated from the
book on every packagemanager run, so `make install` of the new blfs repairs
the live flow immediately -- rerun the bootstrap, it skips what is done.

## One loop  (1.11.57) -- plan steps 5 and 6

The endpoint item 6 named: `packagemanager_install` no longer runs a build.
Its installPkg keeps the front-matter -- name resolution, confirmation,
account creation, tarball staging, group checks, the script/install_last
records -- and then hands the prepared script to the one loop:

    lfs-helper build <account> --script <home>/install_<account> --phase <P> --force

cmd_build grew three things to take the hand-off.  `--script` builds from a
file that is not in $SCRIPTS.  The name argument is normalised through
unprefix_pkg_user, because build-all passes step names and packagemanager
passes accounts, and recording p_wget's build under "p_wget" while lfs
records "wget" is two keys for one package.  And `--phase update` is a full
run: stale source cleaned, VERSION/pkgusr-info/mark_done written, no false
"earlier phases never completed" hint -- while staging still never fires for
it (_phase_can_stage allows only a lone install phase, which is also why
step 6 is now true by construction).

The engine's wrappers/runner/retry/failure-box/recorder block survives only
for nimgnu_/u_ accounts, old-style scripts and systems without lfs-helper.
Step 7 (retiring the file) waits until a real build has proven this.

Two report fixes from the husk repair's first real run: verify's summary
counted nothing ("repaired 0 path(s)" after merging four husks -- the
`fixed` variable was declared and never fed; _repair_misplaced_home feeds
_vfy_n_fixed now and the summary adds it), and "some files differ ...
compare and remove by hand" now NAMES up to five of them, because a report
that hands work over without saying where sends the user diffing eleven
directory pairs.

## Root's shell history is not sqlite's  (1.11.56)

The first verify on the repaired 13.0-sysv chroot reported, alongside the
expected strays:

    [62/221] sqlite   /root/.bash_history   root -> p_sqlite

The timestamp scan sweeps every new file into the open manifest, and root was
in a shell while sqlite built -- so --fix would have handed root's shell
history to a package user.  Same species as /etc/group- ("ncurses did not
install /etc/group-; useradd did, while ncurses was building").

Three guards: /root joins never_claim_list (which also protects manifests
ALREADY polluted -- no manifest surgery needed), and both snapshot scans now
skip /root and /home so no new manifest picks such files up.

The same run reported six files claimed by nobody.  Five are the tools' own
stores -- /usr/share/lfs and /usr/share/blfs hold downloaded books, parse
caches and stamps, runtime data like $STATE, now never-claimed.  The sixth,
the bash completion file, IS installed by `make install`, so
_adopt_pkgusr_tools claims the completions dir alongside /usr/bin and
/usr/sbin, and `verify --fix` refreshes that manifest before the unclaimed
pass so the report heals in one run.

## A home that never met its files, and the runner owns the phases  (1.11.55)

Two changes, one found on the user's real 13.0-sysv chroot.

**The husk homes.** `ls /usr/src` showed `p_wget`, `p_requests`, `p_make-ca`
and seven more sitting beside the roots.  The hint's add_package_user takes no
home argument and creates `/usr/src/<account>`; every tool computes
`/usr/src/pkgusr/<account>`.  Three tools each held part of the repair, and
the python side's part was `usermod -d` alone -- it repointed the passwd entry
and LEFT THE DIRECTORY BEHIND.  Same species as ever: one decision (where a
home is, and how to move it there) held in several places.

Now there is ONE implementation, `lfs-helper fix-home <name> [--run]`:
repoints the passwd entry (usermod, or the file itself pre-Shadow), then
merges the stray into the real home -- moves what is missing, deletes what is
byte-identical, KEEPS anything that differs and says so.  packagemanager and
packagemanager_install both call it (each keeps a reduced local fallback for a
system without lfs-helper), and `verify` grew rule 6b: every package-prefixed
account is checked for a misplaced passwd home and for a husk at
`$SRCROOT/<account>`, repaired under --fix by the same function.

**Phase tracking moved into the runner (plan step 4).**  It was cmd_build's
private bookkeeping -- clear on "all", record on success, infer finished
phases from a failed log -- so an install driven by packagemanager left no
record and could not be resumed.  run_phase_as now takes the record key and
does all three, for every caller; cmd_build's copies are deleted, and
run-script derives the key from --user through pkg_owner_name +
unprefix_pkg_user, so both drivers record under the same step name.  Gated on
the script defining `install_pkg()`: an old-style script runs everything
whatever argument it gets, so recording a phase for one would claim what did
not happen.

## Merged: the SysV-book session  (1.11.54)

A parallel session branched from **1.11.26** to solve a real problem: LFS
13.0 dropped the SysV edition. It produced a new tool and four fixes. Since
that branch never saw 1.11.27-1.11.53, everything was PORTED, not
overwritten — the branch's `lfs`, `lfs-helper` and `packagemanager_install`
were older than the ones here.

**New tool: `lfs-sysvbook` 1.0.0** (own version line; it converts books, it
is not part of the build engine). It grafts the SysV flavour of the last
SysV book (12.4, donor) onto a systemd-only release (target) and stores the
result as a normal book, with wget-list and md5sums generated offline:

    lfs fetch 12.4 && lfs fetch 13.0-systemd
    lfs-sysvbook make                    # -> 13.0-sysv
    lfs-sysvbook check --book 13.0-sysv  # 12 checks, fails loudly
    lfs --book 13.0-sysv run

Rules are declarative tables at the top of that file, so a later release is
`make --target 13.1-systemd`. Transplanted sections stay pinned at donor
versions; everything else builds at target versions. Verified there: a full
13.0-sysv build reached chapter 8 and BLFS bootstrap. **Booting the finished
13.0-sysv system is still untested.**

Ported into the current tools:

- **`lfs`**: the infix tarball pattern (SQLite-3510200 ships as
  `sqlite-autoconf-3510200.tar.gz`, a new 13.0 package that broke unpack),
  with the unpack doc-filter extended to infix spellings so it cannot grab
  `sqlite-doc-*`; the "download the sources" step is done only when EVERY
  basename of the current book's wget-list is present, not "some tarball
  exists" (leftovers from an older book were skipping the download); and a
  fresh-run confirmation that states the book and the whole session config
  once before touching anything.
- **`lfs-helper`**: `chown 0:0` instead of `chown root:root` for the wrapper
  directory (before 7.6 there is no /etc/passwd in the tree, so names do not
  resolve); `/tmp` created early if missing (sort needs it before init-dirs
  runs); and a line saying the manifest scan is running, which on a fresh
  tree looks like a hang.
- **`packagemanager_install`**: the "could not write to <dir>" box printed a
  wrong remedy — swapped arguments, and the wrong command entirely when the
  directory is ALREADY shared and the user simply is not in its collector
  group. Hit in the wild with p11-kit vs /usr/share/zsh/site-functions.

One test broke on the merge: it asserted `chown root:root "$WRAPPERS"`
literally, and the numeric-id fix is the same property spelled differently.
Fixed to accept either. Fifth time this session that a test matched an
implementation rather than an intent.

## "Up to date" is not "built against this system"  (1.11.53)

After glibc changes, a package whose version did not move is still the old
binary. The version is right; what it was built against is not. So
`--reinstall` now reaches the LFS book's up-to-date packages too, via
`lfs update --porcelain --include-current`, and the plan can be the whole
system in book order rather than only the 29 whose numbers moved. Rows where
installed == book print as "(rebuild, same version)" so the plan does not
claim an upgrade it is not making.

Worth recording honestly: glibc keeps backward ABI compatibility through
symbol versioning, so existing binaries keep working and a full rebuild is
NOT required the way it would be after an ABI break. It is required to know
the system is built against the new toolchain, which is a different
question, and one only the person can decide is worth the time.

Another test asserted a call's exact spelling (`_lfs_stale_list()`) and
broke the moment the call took an argument. Fourth time this session.

## Rebuild in book order  (1.11.52)

The stale list came out **alphabetically** — Python, binutils, coreutils,
... glibc — and that is a genuinely dangerous order to rebuild in: each
package is compiled against the ones before it, so Python rebuilt ahead of
glibc links against the old one and is stale again the moment glibc is
replaced. The list is now sorted by where each package appears in the book,
which is chapter 8's own build sequence; anything the book does not name
goes LAST rather than jumping the queue. packagemanager preserves that order
when it folds the LFS packages into its plan.

Also: the systemctl hint now prints the FILE PATH, not just the package
name. The next thing anyone does with that list is open the file and add the
SysV equivalent, and the script it names is the one the build runs.

## Said once, and said before the build  (1.11.51)

1.11.50 printed every stale package twice: the "the LFS book answers for
these" report ran BEFORE those packages were folded into the plan, so each
appeared as unplanned and then again as planned. The folding now happens
first and the report covers only what the plan does not.

New: **a systemd book on a SysV system says which packages need systemctl.**
The shim (1.11.30) turns each call into a visible skip so the build
succeeds -- but "skipped" means the service was not enabled, and only the
person can judge whether that matters for a given package. The plan now
names them with a line count, before the build, instead of leaving the
notices to scroll past during it. Silent on a system that has systemd.

## One update, both books  (1.11.50)

The plan held two packages -- what the BLFS book carries -- while
twenty-nine LFS-book packages were merely REPORTED, with a command to paste.
That was never the request: "update all, preferring BLFS" is what was asked
for in the first place, and preference means falling back, not stopping.

`lfs update --porcelain` prints `name<TAB>installed<TAB>book` and nothing
else; packagemanager reads it and folds those packages into the SAME plan,
skipping any the BLFS book already covers -- so BLFS stays preferred, and
the LFS book fills in the rest. On `--run` an LFS entry is built by
`lfs install --reinstall <name>`, which already knows how to fetch the
tarball, generate the script and hand over to lfs-helper; reimplementing
that here would have been a second builder for the same book.

Parsing the human report was the alternative and was rejected: it breaks the
first time a word changes, which this tool has already been bitten by.

**Toolchain packages need consent.** glibc, binutils, gcc, libstdcpp and
linux-headers are planned and shown, but skipped by `--run` unless
`--toolchain` is given. Rebuilding those on the running system can leave it
without a working compiler, and that is not the same act as rebuilding
`less`.

For the third time in this session a new test was inserted after the
`if problems: sys.exit(1)` that guards its block, and passed on the old code
until the red check caught it. Worth a rule: when adding to an existing
python test block, put the assertions ABOVE that guard, and never trust a
new test that has not been seen red.

## A run's record must not outlive the run  (1.11.49)

**m4 built end to end** — fetched from the wget-list, unpacked, compiled and
installed as p_m4 through the shared runner. First real proof of step 3b and
of the single-package fetch, on the live system.

It ended with "Collector groups used during this run:" and nine grants for
p_urllib3, make-ca and p11-kit — all real, all made weeks earlier. The
granted-groups file is only cleared by the report, so any build that granted
without reporting (a failure, another path) left its entries for the next
successful build to claim as its own. A build now starts with an empty
record, and the heading says what it means: "Collector groups this build
needed".

Also fixed: a `DeprecationWarning` from 1.11.48's own code —
`re.split(pat, s, 1)` must pass `maxsplit=1` by keyword on Python 3.13. It
printed on every install, from the tool that had just been shipped to stop
noise.

## The book ships the URLs; use them  (1.11.48)

`lfs install --reinstall m4` failed with "no M4-1.4.21.tar.* in /sources --
run: lfs build-system get-sources --run" — while the URL for exactly that
tarball sat in the wget-list this tool already downloads and caches with
every book. Only `get-sources` ever read it, and only in bulk, so updating
one package meant fetching everything or nothing.

`_wget_list_url_for` looks up a single package's URL, `_have_source_for`
answers whether it is already in the tree's /sources (with the same loose
matching the generated script globs with — a stricter test here would fetch
a file the build then refuses to see), and `cmd_install` fetches what is
missing before handing over to the build. The tree root is passed in rather
than guessed: inside the chroot /sources is /sources, outside it is
$LFS/sources, and a fetch into the wrong one would look like it worked.

Matching is on the version token, so `Util-linux-2.41.3` finds
`util-linux-2.41.3.tar.xz` — the hyphenated names are where a naive split
goes wrong — and a package not in the list returns nothing rather than a
confident wrong URL.

The test for this passed on the OLD code at first: it was inserted after the
`if problems: sys.exit(1)` that guards its block, so every failure it found
was collected and never reported. A test that cannot fail, again, and this
time caught by the habit of checking red before green rather than by luck.

## A heading that promises errors must show some  (1.11.47)

The first real build through the shared runner failed for an ordinary reason
-- the 13.0 book wants M4-1.4.21 and only the 12.4 tarballs are in /sources
-- and the failure report printed:

    --- first errors in the log ---
    -------------------------------

Nothing between them. The log said `no M4-1.4.21.tar.* ... in /sources --
run: lfs build-system get-sources --run`, which matched none of the
compiler-shaped patterns (`error:`, `*** [`, `undefined reference`). No
pattern matching is a statement about the PATTERNS, not about the log: it
now says so and shows the tail, which is where a non-compiler failure
usually is. Empty-as-no-findings, fifth appearance.

Also: `lfs-helper run-script` did not answer `--help`, which every other
command does. It does now.

Not a bug, worth knowing: moving to a newer book means the new tarballs are
not in /sources. `lfs build-system get-sources --run` on the host fetches
them before any of the 30 stale packages can be rebuilt.

## One runner  (1.11.46) — item 6, step 3b

The last structural piece of the split. Running the install script existed in
**three** copies, two of which I only found because the test looked:

- `cmd_build`: `su - "$owner" -c "env ... bash SCRIPT PHASE" | tee`
- `cmd_build`'s permission-RETRY loop: the same three-branch block again — so
  a retry could run the build differently from the attempt it was retrying
- `packagemanager_install`: `su - -c "set -o pipefail; PATH=...; bash
  ~/install_<user> | tee" <user>`

The differences were exactly where this project's worst bugs lived: whether
the wrappers are in PATH (without them the book's own `install -vdm755
/usr/sbin` fails as "cannot change permissions"), and whether the status
comes from the script or from `tee` (a failing build reporting success cost a
day).

`run_phase_as` is now the one runner, with the three privilege cases named
and kept distinct: as root (no wrappers — root legitimately chowns), as the
owner (wrappers first), and root-then-hand-over for the packages built before
Shadow exists. It returns the SCRIPT's status via PIPESTATUS, never tee's.
`lfs-helper run-script --user U --script S --phase P` exposes it to callers
that are not this script, and packagemanager_install uses that instead of its
own line (keeping the old one only where lfs-helper is absent).

Proved functionally, not by grep: a script exiting 7 reports 7, a passing one
reports 0, the phase argument arrives, and the su branch really runs as the
target user with the wrapper directory first in PATH.

With step 3 done, what remains of the plan is step 4 (phase tracking into the
shared runner), step 5 (delegate the rest), step 6 (staging follows), and
step 7 (retire the fifth tool).

## A kept script says which version it builds  (1.11.45)

`lfs script fetch m4` printed the book's heading — `m4 (8.14. M4-1.4.21)` —
above a script generated from book 12.4 that builds M4-1.4.20, and said
nothing about the difference. Keeping the script is right (it is the
editable file, and regenerating discards edits), but two versions on screen
with no relation stated invites the wrong conclusion. It now says which
version the kept script builds, what the book has, and that `--regenerate`
rebuilds it at the cost of edits.

## One stamp, read by everyone  (1.11.44) — item 6, step 3a

Step 3 opened better than expected: the two generators are NOT far apart.
Both already emit `unpack_pkg()`, `build_pkg()`, `install_pkg()` and take the
phase as `$1`; the lfs one adds `#### BUILD ####` markers its own driver
greps. What actually differed was the STAMP, and that is what made
packagemanager call every LFS-book script "OLD-format" and offer to migrate
it into a BLFS one.

Both generators now write one shared line:

    ### script format v<N> origin=<tool>

`_script_origin` reads it, with a fallback to each tool's older mark so
existing scripts keep working, and `_package_script_outdated` judges only
what `blfs` generated. The counters stay PER GENERATOR (blfs v4, lfs v17)
and are never compared with each other — comparing them would be a number
against an unrelated number. The 1.11.40 containment (recognising the other
tool's dialect) is gone: recognising was the workaround, asking is the fix.

Verified by generating a real crosschain body and reading its stamp back
with packagemanager's parser, plus all five origin cases (new blfs, new lfs,
legacy blfs, legacy lfs, unstamped).

**Step 3b, the runner, is deliberately NOT in this release.** The `su - …
bash install_<n> <phase>` invocation, the wrappers, `pipefail`/`tee` and the
exit-code capture are one function's worth of work in the live build path,
and the plan's own warning is "doing it as one commit" — so it gets its own
red-tested release.

A test broke on the way and earned its comment: it asserted that
`_package_script_outdated` CALLS `_is_lfs_book_script` — the mechanism — and
failed the moment the check became a better one. Assert intent, not
implementation; third time this exact lesson has appeared.

## A refresh that does not record what it did  (1.11.43)

1.11.42 refreshed all five tools on entry and the chroot still opened with
"These tools differ from the copies on the host", naming all five. The
warning does not compare files: it compares `tool-stamps.json`, written by
install-tools. Refreshing the binaries and leaving the stamps alone made
packagemanager announce that tools were stale seconds after being handed
fresh ones, and advise a sync -- on the path that had just synced them. The
refresh writes the stamps now.

Still open on the real system: the refresh reported all five as updated on
EVERY entry, which cannot happen if the copies landed -- the md5s would
match on the second run. So the refresh now VERIFIES each copy and names any
that did not change on disk. That turns a silent repeat into a stated
failure with a reason. If it still repeats with no failure named, something
outside the refresh is rewriting the tools in the tree between entries, and
the next step is comparing `md5sum /usr/bin/<tool>` on the host against
`$LFS/usr/bin/<tool>` right after an entry.

## Entering refreshes everything, and changes nothing  (1.11.42)

`chroot enter` refreshed **lfs-helper alone**. The four python tools inside
stayed older than the host's, which is why every packagemanager run in the
chroot opened with "These tools differ from the copies on the host" and told
the user to sync -- advice printed by the very path that had just synced one
file of five. `_refresh_chroot_tools` now content-compares all five and
carries the completion with them, silent when nothing changed.

The other half, and the reason this needed care: `install-tools` copied the
host's `config.json` straight over the tree's. So `lfs set-default
13.0-systemd` INSIDE the built system was undone by the next entry, back to
whatever the host had, without a word. The config is MERGED now -- host
values only where the tree has nothing to say, the tree's own book default
kept and reported when it differs. A setting the person changed last must
not be reverted by a command whose job is to copy binaries.

Also: `lfs update` colours the version you would move to, matching
packagemanager's plan, and guarded by `_tty_out()` like every other colour
here -- escape codes in a piped report are noise in a file.

The refresh test caught a `NameError` (shutil is imported per-function in
this file, not at module scope) before it could reach a chroot. Worth
noting: a functional test on a temp tree found in a second what a static
grep would have shipped.

## Ask a question whose answer can be no  (1.11.41)

With the false clean bill gone, the honest report showed two more, both in
`lfs update`:

- **`_blfs_knows` said yes to everything.** It asked `blfs debug <name>` --
  a DIAGNOSTIC, which prints "resolve: NOT FOUND" and exits 0. So every
  string passed to it was "in the BLFS book", and the report ended with
  `blfs update gcc-pass1 cfg_fstab init-dirs libstdcpp ...`: LFS build steps
  offered as BLFS packages. It now asks `blfs versions`, a fact — the set of
  anchors the book actually has, read once per process.
- **The temporary chapter-7 toolchain was offered for reinstall.**
  `util-linux-tmp 2.41.1 -> 2.41.3`, `python-tmp`, `gettext-tmp` in the
  `lfs install --reinstall ...` line — rebuilding the throwaway stage builds
  onto a finished system. Only the STAGE VARIANTS are excluded now
  (`-tmp`, `-passN`), from the step tables.

The first draft of that exclusion took every name in `CHROOT_STEPS_7` and
`CROSSCHAIN_STEPS`, which silently hid `glibc`, `coreutils` and
`linux-headers` — chapter 6 builds those under their own names. Caught by
asserting both directions in the same test (these must be excluded; these
must NOT be), which is worth doing whenever a filter is introduced.

Two testing notes: the new assertion matched the word "debug" and fired on
the comment explaining the old behaviour — "match invocations, not message
text", earned for the second time in five releases. And a 1.11.35 test broke
because `_lfs_update_report`'s contract changed under its stub; a stub is a
copy of an interface and ages like one.

## Silence is not a clean bill of health  (1.11.40)

Step 1 worked -- `reconcile-records --run` wrote 80 pkg.lst files and update
went from 96 unjudged to 9 -- and the first good run exposed three things.

- **A manufactured clean bill.** `packagemanager update` printed "all current
  with the LFS book" while `lfs update` reported thirty stale packages.
  `_lfs_update_report` returned `[]` both for "everything is current" and for
  "the call produced nothing", and the caller printed the same reassuring
  line for both. It now returns ("current"|"lines"|"failed", …) and a failure
  is stated: *these are UNCHECKED*. Empty-as-pass, found for the fourth time
  in this project, this time in the helper written to stop packages
  disappearing quietly.
- **The book was re-parsed per package.** `_find_lfs_package` called
  `load_soup` for every name, so `lfs update` with 77 packages parsed a 10 MB
  HTML file 77 times -- measured at 27s of pure parsing, and long enough for
  a caller with a timeout to give up. `load_soup` now caches per path: 0.35s
  once instead. The consult also asks `lfs update` with no names now, which
  is the same question a person asks by hand.
- **A script from the other book was called OLD-format.** Only blfs stamps
  `script format vN`; `lfs` stamps `### lfs-crosschain-script vN`. So every
  LFS-book script failed the format test, and the advice attached to it was
  worse than the warning: `migrate-scripts` would rewrite an LFS-book script
  into a BLFS one. `_is_lfs_book_script` now recognises the other dialect and
  leaves it alone.

That last one is item 6 talking: two generators, two dialects, and a tool
confidently misreading the other's work. It is a containment, not a cure --
**the cure is plan step 3 (one script format / one runner), which this moves
to the front of the queue**, ahead of step 2.

## One recorder, two strategies  (1.11.39) — item 6, step 1

The first step of the written plan, and the one that removes the class of bug
that prompted it. What a package installed was written down twice, by two
drivers, in two places, and each tool read only its own.

`lfs-helper record-install <pkg>` is now the single writer. It chooses by one
named predicate, `_record_strategy`, which turns on the existing
`ownership_established`:

- **before ownership** (the build stage): the build-stage manifest stands
  alone, because a package's files are not owned by its package user yet and
  an owner scan would return nothing;
- **after**: `_write_pkg_lst` does the owner scan, and pkg.lst is the record
  everything reads.

`lfs-helper reconcile-records --run` gives every package built during the
build stage its pkg.lst once ownership exists — without a rebuild. Both
drivers call the one door: lfs-helper's build path after it writes the
manifest, and packagemanager_install in place of its own inline
`list_package > pkg.lst` (which falls back to the old line only where
lfs-helper is absent).

Two traps met on the way, both caught by testing against a real account
rather than by reading:

- `SCAN_PRUNE` is empty until `scan_prune_set` runs, so the first version of
  the owner scan would have swept /build and /sources into the record — the
  same bug that once put 3348 scratch files into a manifest.
- An owner scan that finds nothing must NOT write an empty pkg.lst over a
  real one. It returns non-zero, says so, and leaves the manifest standing.
  Empty-as-pass has cost this project three separate bugs.

Verified end to end on a real `p_`-prefixed account: no pkg.lst during the
build stage, a correct one after, the home itself excluded, the empty-scan
guard preserving the old record, and reconcile writing what was missing.

**Next: step 2, the version writer** — one function for VERSION and
install_last, and 1.11.37's read-both fallback comes out with it.

## Ask for the account, prefer the installed record  (1.11.38)

1.11.37 taught packagemanager to read `VERSION`, and the next run reported
"0 of 97 current, 97 it cannot judge" — unchanged. The fallback was never
reached. Two bugs, one after the other:

- **`gather_user` looked the PACKAGE name up in the user database.**
  `list_all_users` hands names back unprefixed ('glibc'), the account is
  'p_glibc', so `getpwnam` raised KeyError, `has_user` stayed false, and
  `state` came out 'broken' — landing every LFS-built package in the "cannot
  judge" bucket with its home, VERSION and manifest sitting right there. Now
  through `pkgusr_name()`, which is idempotent, so a name that already
  carries the prefix is safe. `_user_exists` takes either spelling too (raw
  first, so a real account like 'root' is never reinterpreted).
- **Record precedence, found while fixing the first.** The home also holds
  the install script, and that script is regenerated whenever the book moves
  on — its `name_version` is what the BOOK has. Reading it before `VERSION`
  would compare the book with itself and report everything current, forever,
  silently. `lfs update` carries a comment warning about exactly this trap.
  Order is now: `install_last` (what ran) → `VERSION` (what is installed) →
  the script, last resort only.

Both proved against a real `p_`-prefixed account with a real VERSION file,
not by grep. Note for item 6: **neither of these is a build-loop bug** — they
are reader bugs, and unifying the loop would not have removed them. What the
unification does remove is the two-records-of-one-fact split underneath.

## One fact, two files  (1.11.37)

With 1.11.36's accounting switched on, the real number appeared: **0 of 97
current with the BLFS book, 97 it cannot judge** — on a system where `lfs
update` compares all 97 without trouble and finds 30 stale. Not a reporting
bug this time, the underlying split: both build paths record what they
installed, packagemanager into `install_last`, lfs-helper into `VERSION`,
and packagemanager read only its own. Every package the LFS build produced
was therefore version-less to it.

`read_install_last` now falls back to `VERSION` (install_last stays
authoritative where it exists). That required a second change: the books
capitalise differently — BLFS anchors are lowercase (`which-2.23`), the LFS
book titles its packages (`Which-2.23`) — so `_same_version` compares
case-insensitively. An exact compare would have invented an update for every
package both books carry, which is exactly the hazard of reading VERSION at
all.

This is a bridge, not the cure: **open item 6 (one build loop) is what this
keeps arguing for**, and each release that works around the split adds to
the case. Also fixed here: `--run` printed "check them with: lfs update"
where the dry run gave real answers — with no BLFS work to do there is time
to consult, and withholding an answer already in hand helps nobody.

## Two silent exits, and unknown read as current  (1.11.36)

1.11.35 fixed the REPORT and the contradiction survived: 97 checked,
"nothing to update", 1 package named as outside the book — while `lfs
update glibc` said 2.42 -> 2.43. The number gave it away. 1 of 97 in the
not-in-book bucket meant the other 96 were leaving the classification loop
by two paths that said nothing:

- `if u.state != "installed": continue` — silent unless the package had been
  NAMED. Everything lfs-helper built has no `install_last`, so a
  chapter-8 package reads as "not installed" here and simply vanished from
  every update-all.
- `outdated = u.version and bv != u.version` — with an UNKNOWN installed
  version the whole expression is falsy, so the package was filed as up to
  date. Not knowing is not the same as being current; that one predicate
  turned missing evidence into a clean bill of health.

Every package now lands in a named bucket (`no_book`, `no_record`,
`unjudged`) and the report makes the arithmetic visible: "Of 97 checked: N
current with the BLFS book, M it cannot judge" — so a bucket that swallows
things can never again hide behind a total that looks healthy.

Two testing notes worth keeping. The bucket test caught a SECOND copy of the
bad predicate that turned out to be my own comment quoting the old code —
"match invocations, not message text", the handoff's own lesson, earned
again. And the first version of that test failed on old code with a bare
TypeError instead of a reason; a red that does not say why is only half a
test.

## The whole system is answered for  (1.11.35)

`lfs update glibc` said 2.42 -> 2.43 while `packagemanager update` said
"Nothing to update" in the same breath. Both were right: the BLFS-matched
subset WAS current — but 1.11.31's not-in-book report printed only on the
non-empty-plan path, and the early "Nothing to update" return skipped it in
exactly the state that needs it most (a mostly-LFS system whose few BLFS
packages are fine). Now one shared `_report_no_book` runs on both paths, the
verdict says what it actually judged ("Nothing to update from the BLFS book
(...) — every package it carries is current"), and the dry run CONSULTS the
LFS book through `lfs update <names>` — one door, lfs owns that comparison,
packagemanager only relays its answer (including the ready-made
`lfs install --reinstall ...` line).

Also, per request, the script-fetching verb reads the same in every tool:

- `packagemanager script fetch <pkg>` — BLFS script into the package home's
  canonical `install_<name-version>` (the file resolve_script prefers, so
  fetch→edit→install is the 1.11.31 conflict flow by construction), chowned
  to the package user, nothing run. Not-in-BLFS points at the lfs variant.
- `lfs script fetch <pkg>` — same idea for the LFS book; the generation was
  factored out of cmd_install into `_ensure_lfs_script`, the ONE generator
  both go through, so fetch edits exactly what install runs. BLFS-first hint
  mirrors cmd_install; `--lfs-book` forces.
- `blfs script fetch <pkg>` — `blfs script` always WAS fetch; the leading
  verb is accepted so the spelling matches.
- `lfs search <fragment>` — packages and sections of the LFS book, with a
  pointer at `blfs search` for the other book.

## The wrapper asks; the person browses  (1.11.34)

The first run of 1.11.33 on the real system showed three bugs at once, two
of them introduced BY 1.11.33. The book name came from the first [bracketed]
filename of `blfs books` — alphabetical, so 12.4 beat 13.0-systemd and
update reported the wrong book even with the right default set; it was only
ever correct while the default happened to sort first.
`_current_blfs_book` now asks `blfs books --brief` (default + cached list,
no network) and reads the Default line. Second: books' new auto-discovery
ran through `run_blfs`, so every packagemanager invocation probed the site,
twice — --brief is the wrapper's contract, discovery stays with a person at
a terminal. Third (pre-existing, exposed by the forwarded notes):
enumeration probing stale index directories ('oldsvn', 'blfs-book-6.0-html')
fell into the resolve-for-use cached fallback, emitting a note per junk
directory and returning the cached book under a false name —
`discover_dir(listing=True)` raises instead, and the listing skips.
Forwarded notes are also deduplicated per invocation: ninety blfs calls in
one plan must not print the same note ninety times.

A 1.11.33 test broke here for asserting the filename-folding regex — the
implementation — instead of the property; rewritten to assert the name
never comes from a bracket-scraped filename. Assert intent, not
implementation: one more notch on that lesson.

## A chosen book is a decision  (1.11.33)

`blfs set-default 13.0-systemd` answered "Default book set" — and
`packagemanager update` kept reading 12.4. Three holes in one flow, all now
closed: `set-default` validated nothing, so an uncached default sent every
lookup to the closest-cached fallback (it now calls `ensure_book` and
fetches the book while the person who chose it is looking, or says plainly
that it could not and what falls back until `blfs fetch` succeeds); blfs DID
warn ("note: no book matched...") but `run_blfs` captures stderr and threw
the note away (notes are forwarded now — a decision being overridden is
never silent); and the book was displayed by filename
(`BLFS-BOOK-12.4-nochunks.html` reads as `12.4` everywhere now).

Also per request: `blfs books` discovers automatically when a connection
exists — `discover_all` raises when no index was reachable instead of
returning its named-book guesses as a tiny "successful" discovery (the
empty-result-as-pass trap, again), and the offline listing says it is the
cached one. `--discover` remains the explicit refresh that reports failure
loudly. Note `lfs books` always discovered; only blfs hid it behind the
flag.

## Output that reads as one voice  (1.11.32)

Three paper cuts from the first real `packagemanager update` run. `run_blfs`
set a status line ("reading versions from the book") and left it standing,
so the caller's next print landed on the same line — cleared now in a
finally, at the one door, for every status any blfs call sets. The
"Checking N package(s)" line and the "Nothing to update" verdict name the
book they compared against (`_current_blfs_book`, one parser shared with
the init-mismatch check — the two must name the same book). And `lfs
set-default` stopped lecturing about `build_book` on every invocation; it
says what it did and stops.

## Update-all already existed; now it is honest  (1.11.31)

`packagemanager update` with no names has been the whole-system update all
along — every installed package user, versions from the BLFS book in one
call, dry run by default, plan printed in exactly the order --run executes,
cached and resumable. What its plan did not deliver, it now does:

- **Local edits are conflicts, not casualties.** `install_last` is the
  read-only record of the script as it last ran; the canonical
  `install_<version>` beside it is where edits live. When they differ and
  the update would generate a fresh new-version script,
  `_pending_edit_conflict` flags it: collected at the END of the dry run in
  one block, and `--run` STOPS before the first one — the plan is saved, so
  fixing and re-running resumes. Self-clearing: a merged
  `install_<new-version>` in the home resolves it (resolve_script prefers
  it); `--regenerate` declares the discard deliberately. The make-ca
  systemctl edit was this class.
- **Not-in-book packages are named, not dropped.** The `if not bv: continue`
  made LFS-book packages vanish from update-all without a word; the dry run
  now lists them and points at `lfs update` for that side. Driving the LFS
  book through packagemanager's engine is open item 6 (the two build loops),
  deliberately not half-built here.
- **The bash completion travels with the sync** — the third forgotten file
  after skel-package (never forgotten) and skel-u_xdg (1.11.29):
  `_install_completion` runs in install-tools and sync-tools, placing the
  script plus the blfs/packagemanager/lfs-helper symlinks. Overwritten, not
  kept: stale completion is worse than none.

## The other book is a choice, not a mistake  (1.11.30)

The SysV BLFS book is no longer maintained, so running the systemd book on a
SysV system stopped being an error to warn about and became a decision to
support. Three pieces, found by the first real end-to-end install
(`packagemanager install which --run` — which passed, closing the last
verification item):

- **Generated scripts shim a missing systemctl.** `command -v systemctl ||
  systemctl() { echo "# skipped ..."; }` at the top of every blfs-generated
  script: on systemd systems nothing changes, on SysV every book `systemctl`
  becomes a visible skip instead of `command not found` aborting the phase.
  This retires the recurring hand-edits (the make-ca one included, going
  forward).
- **The mismatch warning asks once.** `_warn_init_mismatch` records the
  accepted pair as `init_mismatch_ok=systemd-on-sysv` in the packagemanager
  config; a different mismatch direction asks again. Undo by removing the
  key.
- **Downloads retry.** GNU's ftpmirror 502'd twice and succeeded on the
  third manual run via a mirror redirect — exactly what a retry loop does
  unattended. All generated-script downloads go through `_fetch`: three
  tries, 5s apart, `wget -c` so a retried partial continues instead of
  landing beside itself as pkg.1.

Also closed on the real system this session: the collector-group gid check
came back clean (8 nimgnu_* groups, none below 90000), and p_which reused
the freed uid 10093 — the account allocator working as intended.

## The XDG profile travels with the sync  (1.11.29)

`make install` placed `/etc/pkgusr/skel-u_xdg/.bash_profile`, but no chroot
is populated by `make install` — the tools arrive through `install-tools`
and `sync-tools`, and that path carried `skel-package` verbatim while this
one file was forgotten. So every synced system was missing it, and every
`--shared` user creation warned. `_install_xdg_skel` now runs in both paths:
the host's copy is preferred verbatim (a filled-in `XDG_RUNTIME_DIR` is the
right answer for the machine it syncs to, and `packagemanager` only
substitutes where the placeholder is still present), the placeholder copy
beside the tools is the fallback, and an existing copy in the tree is never
clobbered — same rule as the Makefile. The regression test proves
keep-if-exists functionally and fails on any tool where either sync path
skips the file. This closes the last real-system suite failure at its cause;
the pending-list `make install` entry below remains only as the immediate
fix for the already-built system.

## The suite must be honest on the machine it runs on  (1.11.28)

The first run on the real, built system reported 12 failures. Ten of them
were the suite reading the machine instead of testing the code — and two of
those uncovered real tool bugs the bare checkout could never show:

- **`packagemanager` warned onto stdout.** The config-conflict note ("...is
  'n' here but 'nimgnu' in the lfs config") was printed by `printWarning` to
  stdout, so anything capturing a value captured the note with it. Moved to
  stderr, matching `lfs-helper`'s `warn()`. The values it polluted were
  correct all along.
- **`BLFS_STORE` half-applied.** `_blfs_book_on_host` checked the override
  first but fell through to `/usr/share/blfs` when the overridden store was
  empty — so an empty override reported the system's books as its own. When
  set, the override is now the only place looked. The oldest bug shape in
  this project, in one more place.

The rest were suite fixes: the LFS book is now *found* (beside the tool, then
`$LFS_STORE/books`) instead of a path baked in from whoever ran it last; a
bare tool name resolves off `$PATH` and an unreadable tool stops the run with
one message instead of hundreds of tracebacks; the remove_tools/strip
*default* checks point `LFS_STORE` at an empty directory so the machine's own
interview answers cannot fail them; the XDG-profile test accepts the
installed location `/etc/pkgusr/skel-u_xdg/` as well as beside the tool; and
the empty-sources refusal test SKIPs on a system where bootstrap has nothing
left to install, because exit 0 there is the truth.

The two remaining real-system failures after the first pass were down to two
after 1.11.28, and the second run explained both: the `/tools is deleted by
default` check existed TWICE in the suite — the isolated copy passed while an
unisolated duplicate in the up-front-decisions block still read the machine's
`remove_tools=yes` answer. One decision held in two places, in the suite
itself; the duplicate is gone, the isolated check is the one door. The XDG
failure was the test telling the truth: the profile really is missing at
`/etc/pkgusr/skel-u_xdg/` on the built system — the tools were copied by
hand, and only `make install` places the skel. Strip's dry run on the real
tree behaved: 1098 ELF files, 3135 MB, 70 owners, nothing touched.

## Stripping runs as the file's owner  (1.11.27)

Open item 2, closed. `strip` was asked for in the interview and ignored with a
NOT YET IMPLEMENTED notice at the end of the build. Now `lfs-helper strip`
does it, and the design follows from one fact: **strip does not edit a file,
it writes a stripped copy and renames it into place — and the copy belongs to
whoever ran strip.** Run as root, every binary becomes root's and the
ownership record is gone. So the candidates (the book's 8.85 set: `*.so*`
under /usr/lib and /usr/libexec, every ELF file under /usr/bin, /usr/sbin,
/usr/libexec — real ELF checked by magic, not by name) are grouped by owner
read from the filesystem, and each group is stripped **as that owner** via
`su`. The sealed install directories permit exactly this: group-writable for
`install`, sticky, so an owner may replace its own file and nobody else's.

Libtool `.la` files are removed too (the book's cleanup; `--keep-la` keeps
them) — deleting is a directory operation, not a rewrite, so root does that
part directly. In-use binaries (bash, strip, libc) are safe to strip in place
because a running process keeps its open inode across the rename; the book's
copy-to-/tmp dance guards in-place editing, which GNU strip does not do.

`build-all` now ends with `_strip_if_asked_for` → `cmd_strip --run` when
`LFS_STRIP=1` — one implementation, one caller. A failed run cannot fail the
build (an unstripped system is complete, only larger); it downgrades to the
old end-of-build notice, which now says what to run
(`lfs-helper strip --run`) instead of what is missing. Per-file failures are
printed as marked lines and counted, never swallowed. Files with an owner the
user database does not know are left alone, and that is said.

Untested against a full real tree — a smoke test proved bytes drop and the
owner survives; watch the first `strip --run` on the real system with
`lfs-helper verify` afterwards.

## Toolchain audit: one colour vocabulary  (1.11.26)

Rule, stated by the user and now enforced by a test: **red states a failure,
orange warns, green states success — in every tool.**

What the audit found and fixed:

- `lfs` had `fail()/warn()/ok()` and, beside them, **20 bare uncoloured
  `sys.stderr.write("! ...")` errors**. All routed through `fail()` now,
  rewritten mechanically via the AST (constant and %-format sites) so no
  message text changed.
- `blfs` had green for commands and **no red at all** — its errors were the
  only uncoloured errors in the set, and an error that does not look like the
  other tools' errors reads as less serious. It has the same
  `fail()/warn()/ok()` painters now (tty-guarded), and `-V` like every other
  tool.
- `lfs-sanity.sh` printed `!!` plain. Problems are red, the clean verdict
  green, colour only on a terminal so the saved report stays clean text.
- The engine printed its no-wrappers **warning in red**. Orange now: red is a
  statement of failure, this is a statement that failure is coming. Its
  `echoGreen "Creating:"` header (information, not success) is blue.

**Verified while auditing:** `blfs` contains zero install commands — no
useradd, groupadd, su or chown. Install work flows through one path:
packagemanager → packagemanager_install → lfs-helper (owner-name,
pkgusr-home, grant-dir, wrappers). The unification asked about is real.

**Worklist for the next session** (audit items seen, not yet done):
- lfs-helper's `say`/`warn` sites deserve the same pass lfs got — grep for
  plain `echo` of error-shaped text.
- Help-message structure: lfs and packagemanager group commands with
  headers; blfs's `--help` is flat argparse. Worth aligning.
- `--verbose` exists in lfs and packagemanager only; decide whether the
  bash tools need it or the flag should be documented as python-only.
- Long-running steps mostly announce themselves (`  $ ...` convention,
  `_run_banner`); `blfs fetch` and `make-ca -g` announce, but `write_pkg_list`
  regeneration in the background does not say how to check on it.

## A collector group belongs in its own range, under one prefix  (1.11.25)

A real tree, otherwise clean, ended with:

    !! group nimgnu_p_openssl (gid 10093) is outside every convention

Two faults in one name.

**The gid.** `groupadd <name>` with no `-g` takes the next free system gid, so
the group landed at 10093 -- among the package-user accounts, where nothing
expects a group. `_create_collector_group` allocates from 90000-99000, and
every caller goes through it. A test scans for any remaining bare `groupadd`.

**The name.** `nimgnu_name("p_openssl")` gave `nimgnu_p_openssl`: two prefixes
on one name, which is the thing "one account, one prefix" exists to prevent --
and not even what the prompt offered, which showed `nimgnu_openssl`. The
owner's prefix is stripped before the collector's is added.

**And the summary lied.** That `!!` came from an awk that printed its own line
and never touched `$hits`, so the report ended "no problems found by these
checks". A summary that disagrees with its own body teaches you to skip the
summary. It goes through `hit` now, and a test fails on any awk in
`lfs-sanity.sh` that prints `!!` itself.

## A collector group grants a directory, never a package  (1.11.24)

The prompt said:

    1) nimgnu_openssl   (everything owned by 'p_openssl' -- fewer groups)

which is simply untrue, and dangerous in a scheme whose whole point is that a
package cannot reach another package's files. A collector group grants the
directories it is **applied to**, one at a time. Choosing the owner-named
option only means the name can be reused on the next directory of that owner;
by itself it grants nothing extra.

Reworded, with the guarantee stated outright: "Either way it grants $dir and
nothing else."

## The file to edit is named last, and it is the one that survives  (1.11.24)

A failed install said

    install file: /tmp/packagemanager/install_files/install_make-ca-1.16.1

three messages before the end. Both halves wrong.

**The path.** That is where a script freshly generated from the book lands. The
engine copies it into the package user's home, and the next run regenerates the
/tmp one — so an edit there is silently discarded, which is the exact failure
this message exists to prevent. It names the copy in the home when there is
one, and says explicitly that the other is regenerated each run.

**The position.** It is what you do next, and it was buried above the logs and
the re-run command. It is the last thing printed now, in the error colour. A
test asserts nothing follows it.

## Two registries, one question  (1.11.23)

`packagemanager which-package` is documented in the README and never existed:

    error: argument <command>: invalid choice: 'which-package'

And `lfs-helper which-package` reads the **build** manifests only, so a package
installed ten minutes earlier by these tools answered:

    Nothing recorded means it was installed before file tracking existed,
    or outside these tools entirely.
    On disk now: -rwxr-xr-x p_wget:p_wget

Wrong twice over, with the contradiction printed two lines below it. These
tools installed it, and they did record it — in the package user's own
`pkg.lst`. Chapters 5-9 record into `$STATE/manifests`; everything after
records into `pkg.lst`; neither tool looked at the other's.

`packagemanager which-package` exists now, reads `pkg.lst`, and cross-checks
the recorded package against who owns the file on disk — those can disagree,
and that disagreement is worth seeing. `lfs-helper which-package` searches
`pkg.lst` before claiming nothing recorded it, and points at the other tool
either way.

## The trigger must match what counts as done  (1.11.22)

1.11.19 made "stage 5 finished" mean *a bundle exists AND no store is empty*,
and left the trigger as *no bundle exists*. On a tree with the GnuTLS bundle
written and `/etc/ssl/certs` empty, stage 5 was skipped entirely — and then the
check reported the empty store as a failure. Correctly, and without ever having
attempted it. Reported twice, tried never.

The trigger is `not _have_ca_bundle() or _empty_cert_stores()` now: the same
condition that decides it is done decides whether to run it. A test asserts the
two agree, and fails if the trigger drops the store check.

When it still cannot fix it, the message says so — "even after granting and
generating again" — and prints the two commands to do it by hand, instead of
describing the problem twice in identical words.

## A wrapper that exists can still be the wrong wrapper  (1.11.21)

1.11.18 fixed the install wrapper. 1.11.20 hit the identical failure on the
identical line:

    install -vdm755 /usr/sbin
    install: cannot change permissions of ‘/usr/sbin’: Operation not permitted

A snapshot had restored the **old** wrapper. It existed and was executable, and
`_wrapper_dir_from_lfs_helper` checked exactly that — "missing or incomplete".
Its comment claimed this "repairs a tree whose wrappers predate a fix"; the
code could not see "predates". The fixed wrapper on the tools side never
reached the tree.

`make_wrappers` now stamps `$WRAPPERS/.written-by` with the same fingerprint
`--version` prints — same species, same cure as the stale chroot tools. The
engine compares the stamp against the live `lfs-helper --version` and rewrites
on any difference. The test corrupts the stamp and proves the rewrite happens.

One trap inside the fix: the test suite lifts `make_wrappers` out with sed and
runs it under `set -u` where neither the version variable nor `_build_id`
exists, so the stamp uses `${VAR:-}` and a `command -v` guard — a stamp that
kills the function it stamps is worse than no stamp. Six tests caught the first
draft.

**For the user's tree:** their snapshot restores old wrappers every time; with
this, the first `packagemanager` run after `install-tools` rewrites them
without being asked. The manual `lfs-helper make-wrappers --run` advice from
1.11.18 is obsolete.

## The staging guard made the fix a no-op  (1.11.20)

1.11.14 staged the downloaded tarball into the package user's home before the
engine ran, guarded by "only if the home exists". For a **new** package it
never does -- the engine creates it -- so the guard turned the fix off in
exactly the case it was written for, and the identical error came back:

    install_p_wget: line 44: wget: command not found
    md5sum: wget-1.25.0.tar.gz: No such file or directory

It belongs in `packagemanager_install`, after `addUser`, where the account and
its home exist. The Python copy is gone: one door, and the one that could
never work is not the door. A test asserts the ordering, not just the presence
-- reintroducing the old placement fails it.

**And the message was wrong about itself.** "ERROR: md5sum check failed" was
printed for two different things: contents that differ from the book, and a
file that is not there at all. The second is what a fresh system hits, and it
is not a checksum problem -- it is a download that never happened. It now
prints expected, got (or `<no file>`), and says which.

`PM_SKIP_MD5=1` accepts a mismatch on purpose, for when the book's checksum
disagrees with a mirror's tarball. Not a default: a checksum skipped by
accident is worse than none, so it has to be asked for by name.

## A zero exit is not a finished job  (1.11.19)

Bootstrap reported all five stages complete on a system whose OpenSSL trust
store was empty:

    install: cannot create regular file '/etc/ssl/certdata.txt': Permission denied
    p11-kit: couldn't create file: /etc/ssl/certs/...pem: Unknown error 13
    Failed!!!
    Extracting GNUTLS server auth certificates to: ...Done!
    CA certificates found (/etc/pki/tls/certs/ca-bundle.crt) -- re-enabled

`/etc/ssl/certs` is `p_openssl:p_openssl`, so `p_make-ca` could not write it.
make-ca wrote the stores it could, **exited 0**, and `_have_ca_bundle` found
the GnuTLS bundle and said yes. Certificate checking was then turned back on
against a store that is empty — and `/etc/ssl/certs` is OpenSSL's default
CApath, which is what `wget` itself reads.

Three separate failures of the same kind: a success signal that was not
checked against the actual result.

- **The errno is a number.** p11-kit prints "Unknown error 13", so `_PERM_HINT`
  — looking for the word "denied" — skipped the line and no directory was
  extracted. 13 is EACCES. Both its wording and `couldn't create file:` are
  matched now.
- **Nothing granted or retried.** Stage 5 ran make-ca once, outside the
  recovery every install goes through. `_run_make_ca` captures the output,
  grants what the errors name, and runs it again once.
- **Existence is not population.** `_empty_cert_stores` checks that
  `/etc/ssl/certs` actually holds certificates, and verification is only
  restored when it does. An empty store is now a stage-5 failure.

## The install wrapper must see bundled short options  (1.11.18)

**This was the actual cause of the make-ca failure**, under three rounds of
wrong diagnosis. The wrapper detected directory mode with

    for a in "$@"; do case "$a" in -d|--directory) want_dirs=1 ;; esac; done

which matches `-d` only as a whole argument. make-ca's Makefile writes it
bundled:

    install -vdm755 /usr/sbin

one token. The rule never fired, the real `install(1)` ran, and it died on the
exact message this wrapper's own comment quotes. The comment was written for
the unbundled spelling and the code only ever handled that one.

Why no amount of granting helped: `install -d` on an **existing** directory
still applies the mode, and chmod requires ownership, not write permission.
`/usr/sbin` is `root:install`, `p_make-ca` was already in `install`, and
`_user_can_write` correctly said yes. Writing was never the problem.

The wrapper now expands a short cluster into canonical form before any rule
looks at it — `-vdm755` becomes `-v -d -m 755` — so one spelling reaches all of
them. `m o g t S` take a value: the rest of the token if there is one, else the
next argument.

**A second bug fell out of it.** The setuid guard matches `-m` followed by a
four-digit mode, so `install -vm4755` slipped past it entirely and set the bit.
It is refused in both spellings now.

The test lifts the wrapper out of `lfs-helper` exactly as it is written and
runs it: bundled and unbundled `-d`, `--directory`, a directory that does not
exist yet, an ordinary file install, ownership stripping, and setuid in both
spellings.

**Diagnostic note for next time.** Three sessions chased permissions because
the error said "Operation not permitted". The absence of the new "no
package-user wrappers" warning was the evidence that the wrappers were present
and running — an absent warning is evidence, and it was not read as any.

## Granting cannot fix what is not a group problem  (1.11.17)

With 1.11.16 the grant fired, found the right directory, and then:

    /usr/sbin is already group install -- adding 'make-ca' to it
    usermod: user 'make-ca' does not exist

Two faults in three lines.

**The name.** `auto_grant_from_log` was called with the package name. Third
appearance of that species in this file, after `_run_pm_install_once` and
`cmd_pip`. It takes `pkgusr_name(name)` now.

**The diagnosis.** `/usr/sbin` is `root:install` and `p_make-ca` is in
`install` — the grant was for a group it already had. The actual failure is
`install -vdm755 /usr/sbin` CHMODing a directory root owns, which no package
user may do. That is what the **wrappers** are for, not the group. Granting a
group someone already holds looks like progress and is not, so it now says so
and points at `lfs-helper make-wrappers --run`.

**And the underlying cause.** `packagemanager_install` falls back to
`_wrapdir=""` when it can establish no wrappers, then builds without them
silently — so a book command the wrapper is designed to absorb fails as a
permission error, and every diagnosis chases the permission. It says so loudly
now. Whether the wrappers were actually missing on the real system is still
unconfirmed; that message is what will answer it.

## The auto-grant must recognise the message it is given  (1.11.16)

The recovery lfs-helper does during the base build exists in packagemanager
too: a package that must write into another package's directory joins that
directory's collector group, and the install is retried. It never fired on the
real failure.

    install: cannot change permissions of ‘/usr/sbin’: Operation not permitted

Two reasons, both in `_PERM_PATTERNS`. coreutils quotes paths in the locale's
style — U+2018/U+2019 under UTF-8 — and every pattern matched ASCII
apostrophes only. And `change permissions` was not among the verbs, though it
is the one `install(1)` uses when the directory exists and only its mode cannot
be set, which is the commonest way a package meets a directory another package
owns.

So no path was extracted, `auto_grant_from_log` returned nothing, the retry
loop stopped on the first round, and packagemanager printed the manual command
as though it had no opinion — while the engine's own diagnostic, which uses
different code, had already named the directory correctly.

**The advice named the wrong file.** A package user's home holds
`install_<name>-<version>` (edit this) and `install_<user>` (a copy the engine
executes, overwritten every run). The error lines name the copy —
`install_p_make-ca: line 96` — while the advice named the original. Correct,
and it reads as a mistake because it contradicts the output above it. The
advice now says which is which.

## --run means run, not print  (1.11.15)

Stages 3-5 were printed as commands to type. The reasoning was that each has to
be seen to work before the next is worth trying — but `bootstrap --run` is
someone saying "get this system ready", and answering with three commands to
type refuses the request while looking like an answer.

`_bootstrap_finish` does them: `blfs fetch` for the book, `install make-ca
--recursive` so BLFS resolves its dependencies, and `make-ca -g --force` for
the bundle. Then `restore_wget_verification`, the moment there is something to
verify with.

The part that actually mattered is kept: a stage whose dependency failed is
**skipped and said so**, never attempted and blamed for a failure that belongs
to something else. Without a book there is nothing to look make-ca up in;
without make-ca there is no bundle to generate.

The dry run still prints the same list, as what `--run` would do.

## The tarball is staged before the build, not only in new scripts  (1.11.14)

The `/sources` lookup added to the generated script in 1.11.11 only reaches
scripts generated after it. A **local** script is preferred over the book --
it holds your edits -- so the one written by the previous run won, had no
lookup, and did:

    install_p_wget: line 44: wget: command not found
    md5sum: wget-1.25.0.tar.gz: No such file or directory

reaching for a download tool in order to install that download tool.

`_stage_source_from_sources` reads `pkg=` out of whatever script is about to
run and copies the file from `/sources` into the package user's home first. It
sits in `_run_pm_install_once`, so every caller gets it, and it works for
scripts that already exist -- which the in-script version cannot. Copied, never
moved.

Both remain: the script keeps its own lookup for when it is run by hand.

## The account's home is settled where the account is made  (1.11.13)

`add_package_user` takes no home argument: it uses `/usr/src/<name>`, while
every other tool here puts package users in `/usr/src/pkgusr/<name>`. So the
account was created, a home was created, and the install ran in a third place
that existed in neither:

    tee:  /usr/src/p_wget/log/...: No such file or directory
    bash: /usr/src/p_wget/install_p_wget: No such file or directory
    logs: /usr/src/pkgusr/p_wget/log

The last line is packagemanager reporting the correct path in the same breath.
Two halves of one toolchain disagreeing, not a missing directory.

`addUser` now reconciles it at the one point where the account comes into
existence: `usermod -d` to the computed home, and the half-populated directory
the hint made is **moved**, not abandoned — `.bash_profile`, `.bashrc` and
`.project` are already in it, and a passwd entry pointing at an empty directory
is the same bug wearing a different path.

`installPkg` also re-reads the home after creating the user. It computed
`install_user_dir` at the top of the function, describing an account that did
not exist yet.

**1.11.9 fixed the same fault in packagemanager's own `create_package_user`.**
It was never fixed in the engine, which is the path an actual BLFS install
takes. One rule, two implementations — item 6 again.

## The parsers come before the thing that needs them  (1.11.12)

Installing the download tool means looking it up in the BLFS book, and reading
the book needs requests and beautifulsoup4. Stage 1 installed the tool and
stage 2 the parsers, so on a fresh system the first run could not read the book
it was holding:

    $ install wget --run
    wget: not in the BLFS book.
    searching the book for wget  Nothing similar found either.

It succeeded only on a **second** run, once stage 2 had put the parsers in
place — which reads as flakiness rather than as an order. Both earlier logs in
this project show it: the run that found `Wget-1.25.0` was a run where the
modules were already installed.

The wheels need neither the book nor a network, so they are stage 1 now and
nothing is lost. When they fail, stage 2 says the lookup cannot work and does
not attempt it — a missing parser reported as a missing package is how this
hid in the first place.

## The install engine is handed an account, not a package  (1.11.11)

Argument 1 of `packagemanager_install` is used for exactly one thing: the user
to create, own the files and build as. The bare package name was passed:

    $ /usr/bin/packagemanager_install wget /tmp/.../install_Wget-1.25.0
    id wget || addUser wget
    uid=10089(wget) ... bash: /usr/src/wget/install_wget: No such file

An account literally called `wget`, living in `/usr/src/wget` — no prefix, no
subdirectory, colliding with any real account of that name. A fresh snapshot
proved the install created it: `id wget` said no such user beforehand.

Fixed at both ends. `_run_pm_install_once` passes `pkgusr_name(name)`, and
`installPkg` resolves through `lfs-helper owner-name` regardless of what it is
handed, because the script is also run by hand and by older callers. Both are
idempotent, so an already-resolved name passes through unchanged.

## An already-downloaded tarball is used, not re-fetched  (1.11.11)

`unpack_pkg` looked for `$pkg` only in the build directory, so the first
install on a fresh system reached for the network — to download the very
package it was installing, over a connection it cannot verify, because make-ca
needs that same download tool. `get-sources` had already put the tarball in
`/sources` before the reboot.

It now looks in `$LFS_SOURCES_DIR` and `/sources` first and **copies**, never
moves: `/sources` is the record of what was downloaded and no build may consume
it. The download still happens when nothing is staged.

This is the circle the last session hit. With the tarball staged, the first
install needs no network at all.

## One key, one meaning: pkgusr_home  (1.11.10)

A real install put its logs here:

    logs: /usr/src/pkgusr/pkgusr/p_wget/log

`lfs` writes `pkgusr_home` as the FULL package-user root -- `LAYOUT_DEFAULTS`
says `/usr/src/pkgusr` -- and `_base_dir_default` read the same key as the BASE
and appended `PKGUSR_SUBDIR` itself. One key, two readings, and the tools only
disagreed on a tree that lfs had configured, which is every real one.

Fixed on the READING side: a value already ending in the subdirectory yields
its parent, so both tools agree without either changing what it writes. A base
that does not end in it is still taken literally, which is what a hand-written
config means.

**Still open from the same log**, not yet diagnosed: the account was created as
`wget`, not `p_wget` (`uid=10089(wget)`), and `packagemanager_install` used
`/usr/src/wget` for its home. The doubled path above is a separate fault from
the missing prefix; fixing the first does not explain the second. Needs
`/etc/pkgusr/packagemanager.conf` from the tree to go further.

## The BLFS book has to be fetched where there is a network  (1.11.9)

A real bootstrap run walked into the circle:

    wget: there is no BLFS book on this system to look it up in.
    Could not install: wget

The built system installs a download tool by looking it up in the BLFS book,
and fetches the book with the download tool it cannot install. The host has a
network and `install-tools` already copies a cached BLFS book into the tree --
what was missing was **asking**, at a moment when the answer can still be acted
on.

`fetch the BLFS book (for the built system)` is a checklist step now, walked
through by `lfs run` like the LFS book choice. Declining is recorded in
`blfs_book`, so a resume does not ask again. It sits **before** `download the
sources` on purpose: `get-sources` asks `packagemanager bootstrap --sources`,
which asks the book where the download tool's tarball is, so with no book that
URL is silently absent from the download list and the gap only shows up after
the reboot. `get-sources` also says so when it finds nothing.

The warning in `bootstrap_sources` names no package, deliberately: which
packages the built system needs is packagemanager's list, and a test forbids a
copy of it in `lfs`. It caught the first draft of that message.

## A home that is recorded must be the home that exists  (1.11.9)

The same run reported both of these about one account:

    $ chown -R -h p_urllib3:p_urllib3 /usr/src/pkgusr/p_urllib3
      home directory created: /usr/src/p_urllib3

`add_package_user` takes no home argument, so the hint's script used its own
default while `init_package_user_home` created and chowned the one this tool
computes. The `useradd` fallback had always passed `-d`; the preferred path
never did. `su - p_urllib3` lands in a directory that does not exist.

`_fix_recorded_home` compares the passwd entry against the computed home after
creation and corrects it with `usermod -d`, saying so.

## Do not ask for what the system already knows  (1.11.8)

`packagemanager setup` in a fresh chroot opened with a wizard:

    Collector-group prefix [sysgroup]:

on a system built by these tools, where `lfs build-system session` had asked
for that exact value, written it into config.json, and copied it into the
chroot. Being asked for a setting the machine is holding teaches you the
answer does not matter. It matters a great deal: a collector prefix that
disagrees with the built system gives two parallel sets of groups over the
same directories, and nothing reports it.

`_adopt_existing_settings` answers from three sources, in order of authority:
the lfs config (the interview's own answers), the environment `lfs` exports
into the chroot, and the system itself — collector groups live at gid 90000+
and every one carries the prefix, so on a built system the answer is in
/etc/group whether or not any config survived. The wizard now runs only for
what none of them answer, and prints where each adopted value came from.

`_SHARED_WITH_LFS` was `collector_prefix` alone; `pkgusr_prefix`,
`cfguser_prefix` and `main_user` are collected by the same interview and were
being asked for twice. `install-tools` writes all of them into
`packagemanager.conf` now — bare, without the trailing underscore, because
lfs's accessors return `p_` ready to concatenate while packagemanager stores
the word and adds the underscore itself. That only worked because it rstrips
on read: an accident, not an agreement.

**A default is not an opinion.** The conflict warning compared the lfs config
against whatever was in `_config`, and a built-in default counted, so a system
with no `packagemanager.conf` at all was told its settings disagreed:

    note: collector_prefix is 'sysgroup' here but 'nimgnu' in the lfs config

Nothing had said sysgroup. `load_config` now tracks which keys came from the
file, and only those can conflict.

## `setup` is `bootstrap`, and it walks you through  (1.11.7)

**The name.** Every other command is a verb naming what it does to packages --
install, update, remove, verify. `setup` named neither the thing nor the
action, and the word was already taken: `packagemanager user setup` applies the
shared-account treatment to an existing application user. Two unrelated
commands, one word. `setup` remains as a hidden alias, because an installed
`lfs` calls `packagemanager setup --sources` from `get-sources` and a rename
that breaks the tool which downloads the sources costs a reboot to discover.
`get-sources` asks for `bootstrap` first and falls back.

**The walkthrough.** Every check already existed -- wget, the book, make-ca,
the bundle, the wgetrc weakening -- as separate housekeeping that fired
whenever it happened to fire. What was missing was the ORDER, on a system where
all of them are unsatisfied at once and nothing says which to do first.
`bootstrap` is now five numbered stages:

    ok  1. a download tool          /usr/bin/wget
    --  2. book-parsing modules     0 of 7 installed
    --  3. the BLFS book            no book on disk
    --  4. make-ca                  not installed
    --  5. CA certificates          no bundle generated yet

Stages 1 and 2 need no network -- they come from what `get-sources` already
put in /sources -- so `--run` does those. Stages 3-5 each need a working
download that the previous stage buys, and each has to be SEEN to work before
the next is worth trying, so they are printed with the exact command and never
run. Running it again shows where you are.

## A native gcc means opposite things on either side of the build  (1.11.7)

Snapshotting a finished system said:

    toolchain: BROKEN: a native gcc (x86_64-pc-linux-gnu) is installed over
    ! this snapshot is of a tree whose toolchain is already broken.

on a tree with nothing wrong with it. Chapter 6 installs only under `$LFS_TGT`,
so mid-build a native gcc on top of the cross one is the toolchain being
clobbered. Chapter 8 **replaces** the cross toolchain with exactly that native
gcc: it is the finished state, the thing the build is for.

`_build_is_finished` asks the same question `lfs-sanity.sh` does -- every step
in `progress/steporder` present in `progress/steps-built` -- and both the
snapshot label and `verify`'s WARNING now read the native gcc against it. Same
species as the sticky-bit check, which had to learn the same distinction.

## The kernel and the bootloader are yours  (1.11.6)

Both are decisions about the whole machine rather than about a package, and
getting either wrong costs the system doing the building. So the build does
neither, and ends by **saying** so — `_say_what_is_yours_to_finish`, beside the
login and strip warnings — rather than leaving it to be discovered after a
reboot.

`bootloader` was already `none` by default and stays that way. The prompt now
says what that means: nothing is written to any ESP, boot sector or partition
table, and the machine keeps booting exactly as it does today. rEFInd is opt-in
by name, and the closing note prints how to ask for it.

## $LFS may never be the running system  (1.11.5)

Every path this tool writes is `$LFS/something`. Nothing checked that the tree
was not the host's own, so a config holding `/`, an `export LFS=/` in the wrong
shell, or a typo in the interview was enough for
`build-system restart --run` to delete the top-level directories of the machine
doing the building, and for `_verify_lfs_ownership` to run `chown -R lfs /usr`
on it.

`_is_host_path` is the rule; `_refuse_host_tree` is the hard stop. It is called
from `require_lfs_for_root`, the single door every command resolves `$LFS`
through, and from `_verify_lfs_ownership`, which resolved `$LFS` itself and was
therefore the one destructive path with no check at all. The interview refuses
the same paths at the prompt, where you can just type another one.

**Both spellings are checked.** On a merged-`/usr` system `/bin` is a symlink
to `usr/bin`, so `realpath("/bin")` is `/usr/bin` and a check on the resolved
path alone let `$LFS=/bin` through. The first version of the test caught this.

**Inside a system tree counts.** `/usr/src/lfs` is not a build tree, it is a
directory in the system's own `/usr`. `/home` and `/srv` are deliberately not
treated that way: `/home/you/lfs` is an ordinary place to build, and a check
that refuses `$LFS/usr` refuses every build there is.

What was already safe, and stays so: `restart` refuses while the chroot's bind
mounts are up, because deleting through `/dev` would reach the host. GRUB
scripts are not generated at all unless GRUB is the chosen bootloader, so
nothing that could run `grub-install /dev/sda` is left lying around. The rEFInd
step never formats, partitions or writes a raw device; it adds files to an
already-mounted ESP, backs the config up, adds a menu entry beside your
existing bootloader, and refuses to overwrite an existing rEFInd without
`REFIND_OVERWRITE=1`.

## A suppressed failure is a bug waiting to be found  (1.11.4)

`soft <what> -- <cmd ...>` runs a command that may fail, and **says so** when
it does, without stopping the build. Every ownership and permission call whose
failure changes what the system looks like goes through it: the wrappers'
own root:root, the install directories' group-writable bit, the staging tree's
inherited owner and mode, `passwd`/`group` backups, the `lfs` build user, and
the mode `verify --fix` counts as fixed.

Fifteen call sites. `2>/dev/null || true` is not banned — `mkdir -p` on a
directory that exists is fine — but an ownership call that keeps it must carry
a comment on the line immediately above saying **SUPPRESSED DELIBERATELY** or
**benign:**, and a test counts the ones that do not.

Any comment was not enough as a rule. The surrounding prose explains what a
call does, not why its failure may be thrown away, so a reintroduced
suppression inherits whatever comment happened to be above it — the first
version of the test passed a mutation that put one straight back.

The two deliberate ones are `mkstate` and `ensure_pkgusr_roots`: both run
before book 7.6, when the `install` group does not exist and the call cannot
succeed. Reporting them would print a failure on every invocation for the
first third of a build, and that is how a report becomes noise.

## The build says what it did not do  (1.11.4)

`strip` is collected by the interview, carried into the chroot environment as
`LFS_STRIP`, and acted on by nothing. `_warn_if_strip_was_asked_for` is now the
build's second-to-last word, beside `_warn_if_no_login` — the place where the
things you still have to do yourself are collected. It fires only if you asked.

Still not implemented, and the reason stands: stripping rewrites every binary,
and here a file's owner is the record of which package installed it, so it has
to run as that owner, package by package.

## One door per decision  (1.11.3)

Item 6 does not need a rewrite. `grant_dir_to_user` already showed the shape:
**ask `lfs-helper` when it is on the system, keep the local copy as the
fallback for when it is not.** Three more decisions now go through it.

**The wrappers.** `packagemanager_install` shipped its own 480-line copy and
wrote it to `/tmp/pkgusr-wrappers.$$` on every run. The wrappers *are* the rule
about what a package user may do — chown skipped, chgrp skipped, `install -d`
on an existing directory allowed to succeed — so that was a second answer to
the question, and `/etc/pkgusr/bash_profile` pointed at neither copy: it names
`/usr/lib/pkgusr`, which is where lfs-helper writes them. Now
`_wrapper_dir_from_lfs_helper` asks, and writes them through
`lfs-helper make-wrappers` if they are missing or incomplete — which also
repairs a tree whose wrappers predate a fix. The local copy stays, for a system
with no lfs-helper.

**Only a temporary directory is deleted.** Both call sites ended with
`rm -rf "$_wrapdir"`. Pointed at the shared directory that removes the wrappers
from every package user on the system, so the cleanup is now conditional on
having built a temporary one.

**The account home.** `pkgusr_home_for` re-derived the layout — root per kind,
prefix, `cfg_` special case. Correct today, wrong the moment the layout is
configured differently, which it can be. It asks `lfs-helper pkgusr-home` now.

**site-packages.** `pip_install_module` did its own `groupadd` + `chgrp -R` +
`chmod -R g+w`: a third implementation, and the only one that never asked what
group the directory already carried. It goes through `lfs-helper grant-dir`.
That is the debt 1.11.2 left.

Two new commands make the doors reachable: `lfs-helper wrapper-dir` and
`lfs-helper make-wrappers --run`.

**The dispatch repeated six entries** — `verify`, `install-as`, `pkgusr-info`,
`pkgusr-home`, `owner-name`, `clean-state` — and `case` takes the first match,
so the second set was unreachable code that looked like a second decision. A
test now fails on any repeat.

What is left of item 6 is the build loop itself: `cmd_build` and
`packagemanager_install` still each drive unpack/build/install/configure. That
is where staging (item 4) lives, and it is the part that needs a real build to
prove.

## packagemanager setup installs, not just declares  (1.11.2)

`--run` was a stub. It now does the bootstrap half of the old final step, and
`--sources` is unchanged, so `get-sources` still asks it the same question.

- **wget** comes from `packagemanager install wget --run`, invoked as a
  command. A build plan, a script, a package user and a manifest — there is no
  "just the wget part" of that which is not a second implementation of it.
- **The wheels** go through `pip_install_module`, extracted from `cmd_pip` so
  both commands run the same code. `--no-deps`, in the order `_SETUP_WHEELS`
  lists them, `--no-index --find-links /sources`: a fresh system has no CA
  certificates, so a pip index lookup is a hang rather than an error.
- **Idempotent.** It reads `<dist>-<version>.dist-info` in site-packages —
  what pip itself writes, so the check is an identity rather than a guess —
  and skips what is there. `--force` redoes it.
- **It refuses** when the wheels are not on disk, naming each one and saying
  they came from `get-sources` before the reboot.

**A bug fixed on the way in.** `cmd_pip` took `_sanitise_user_name(mod)` and
used it everywhere. `create_package_user` normalises internally, so the account
it created was `p_requests` while `usermod` and `su` were handed `requests`:

    usermod: user 'requests' does not exist

Nobody hit it because nothing called `packagemanager pip` on a real system.
Same species as `chown: invalid user: 'wget:wget'` — half the code asking for
the name, half assembling it.

Still owed: site-packages access is granted by `chgrp -R`/`chmod -R g+w` inside
`pip_install_module` rather than by `lfs-helper grant-dir`. Correct group,
right result, wrong door — fold it in with item 6.

## last-step is cleaned out of the tree  (1.11.1)

`last_build_step.sh` stopped existing in 1.10.0, but three things still spoke
as if it did:

- **`make install` copied it into `/etc/lfs`** and aborted, because the file is
  not in the repo. Installing was broken and nothing said so.
- **`build-all` sealed the install directories early** when the step name was
  `last-step` — dead since the final step became `init-accounts`, which runs as
  root and installs nothing. The seal after the loop was already doing the work.
- **Three tests looked for the file beside `lfs`** and skipped silently when it
  was absent, which is every run since 1.10.0.

The name stays in `_is_not_a_package`'s match: a tree generated before 1.10.0
still carries it in `steporder` and in its manifests, and the rule must still
say no. It is marked as legacy there.

`make clean` exists now, and `make install` no longer hides a failed test
install behind `2>/dev/null || true` — the first of item 10.

## The build's last word is whether you can log in  (1.11.0)

`init-accounts` asks for a root password, but it is skippable — a scripted run
has no terminal, and an interactive one can be answered with a blank line. So
`_warn_if_no_login` is the **last thing `build-all` does**, because it is the
last moment it can still be fixed. After the reboot the chroot is gone and the
way back is booting the host and mounting the tree by hand.

It checks the **result**, not that the step ran: `/etc/shadow` for a real root
password, or any account between uid 1000 and 9999 with one.

    !! NOBODY CAN LOG INTO THIS SYSTEM.
       Fix it NOW, while you are still in here:
           lfs-helper init-accounts --force

`lfs-helper check-login` runs it on its own.

## wget belongs to packagemanager setup  (1.11.0)

`packagemanager setup --sources` prints every URL setup needs, and
`lfs build-system get-sources` asks it. **One list, owned by the tool that
installs from it.**

The first version of this had `bootstrap_packages` in `lfs`'s own config,
resolving wget from the BLFS book separately from the tool that installs it —
a second thing to go stale, which is the mistake this project keeps making.
That key is gone.

`setup` itself is a stub: `--sources` works, `--run` says it is not implemented
and exits non-zero. That is deliberate — `get-sources` needs the list *now*, so
a fresh build still downloads what the finished system will need.

## A command that works in silence looks like one that hung  (1.10.3)

`lfs-helper verify` ran for five minutes printing nothing, on a tree it had
already verified clean, and was reported as a hang. It was not. Two faults:

**A fork per path, twice over.** `stat -c %U` for each path, and
`is_never_claimed` running `< <(never_claim_list)` — a process substitution —
for each path too. Across 66265 manifest paths that is ~130000 processes.

- `_never_claim_load` reads the list once into `_NEVER_CLAIM`; matching is then
  pure shell.
- Owners come from **one batched `stat` per manifest** via `xargs -0`.
  Measured on 8000 paths: **12.6s → 0.15s**.

**No output until every pass had finished.** Each pass now announces itself
before it runs, and the long one prints `[n/m] <package>` live.

Two traps worth remembering, both of which produced code that was *correct and
slow* — the hardest kind of wrong to notice:

- **`stat` does not expand escapes.** `stat -c '%U\t%n'` prints a literal
  backslash-t, so every line came back as one field, the map stayed empty, and
  the loop fell through to the per-path `stat` it was written to replace. Use a
  real tab (`$'\t'`).
- **I first pasted the batching into `cmd_build`**, not the verify pass — both
  contain `for man in ...` over manifests. The tests caught it.

## Scratch, and the one list that names it  (1.10.2)

`scan_prune_paths` / `scan_prune_set` name everything no ownership scan should
walk: `/dev /proc /sys /run /tmp`, `$LFS/sources`, `$BUILD_ROOT`, `$STATE`, and
**every package's unpacked source tree** (`<home>/$PKGUSR_BUILD_SUBDIR`).

There were five such lists and they had already diverged. Build trees moved from
`/build` into each package user's home in 1.7.6; the snapshot scans followed and
the ownership scans did not. So `lfs-helper verify` began walking every unpacked
source tree in the system — minutes of silence — and a finished tree filled the
sanity report with tcl's own documentation:

    !! files with no owner (first 40):
         /usr/src/pkgusr/p_tcl/src/tcl8.6.16/html/Keywords/Z.htm

A tarball can carry any uid it likes. Unpacked sources are not installed,
nothing owns them, and asking who does has no answer.

**`SCAN_PRUNE` is an ARRAY, not a string spliced through `eval`.** The patterns
contain `*`, and `eval` lets the shell expand them against the real filesystem
before `find` ever sees them — `/usr/src/pkgusr/*/src/*` becomes a handful of
literal directory names and the prune silently matches almost nothing. That is
what the first version of this fix did, and it looked like it worked.

`lfs-sanity.sh` prunes the same paths, or it reports what `verify` does not.

Also: a config step that writes **root-owned** files (`cfg_clock` → `/etc/adjtime`)
is not an orphaned manifest. It installs no software, so it has no account, and
there is nothing adoption could ever want. Eleven such findings on a perfect
tree.

## The tree remembers which version generated it  (1.10.1)

`gen-chroot-scripts` writes `progress/generated-by` with the version, build id
and date, and deletes scripts for steps no longer in the order.
`_warn_if_scripts_are_stale` compares that against `lfs-helper`'s own version
before `build-all` runs anything.

**The step order and the scripts live in the TREE; the tools live outside it.**
Nothing connected the two, so a tree generated before 1.10.0 kept running
`last-step` — a step 1.10.0 had removed entirely — under an `lfs-helper` that no
longer knew what it was. The chroot *tools* have carried a build id for exactly
this reason since 1.6; the generated scripts did not.

Removing a step from the tools is therefore **two** changes: the code, and a
regeneration in every existing tree. The stamp is what makes the second one
visible instead of silent.

## last_build_step.sh is gone  (1.10.0)

It was a script created once on the HOST and then owned by the person, run last
inside the chroot. Wrong home for everything it held:

- a fix to it reached nobody who already had a copy — that is how
  `chown: invalid user: 'wget:wget'` survived three releases;
- bootstrapping the tooling is `packagemanager setup`'s job;
- setting the root password is not a matter of taste. Book 8.5 says to do it.

Split three ways:

| What | Where now |
|---|---|
| root password, login account | **`init-accounts`**, a built-in step in `lfs-helper`, ordered last |
| wget, the Python wheels, the wgetrc weakening | **`packagemanager setup`** — not written yet |
| the `SOURCES` array | **`bootstrap_packages`**, resolved from the BLFS book |

`init-accounts` could not move to `packagemanager setup`: setup runs on the
**booted** system, and you need to log in to run it.

`bootstrap_packages` defaults to `wget` and its URL comes from `blfs sources`,
which runs on the host with its own book store. One place knows where wget
comes from, and it is the same place `packagemanager` will ask when it installs
it. Set it empty to turn it off.

**Losing the "add your own steps here" hook is the real cost.** If it comes
back it should be a directory of drop-in scripts, not a template copied once
that then drifts from the tool that generated it.

## packagemanager setup: what it owes

Three guarantees left the suite with `last_build_step.sh` and belong to `setup`.
They are requirements, not history:

1. **Each module installs as its OWN package user, from a WHEEL.** A modern
   sdist needs its build backend, and with no index reachable pip cannot fetch
   one: `BackendUnavailable: Cannot import 'hatchling.build'`.
2. **site-packages access goes through the normal collector-group rules** —
   join the group that owns it, or ask which group should. Handing
   site-packages to the `install` group would mean "anyone may install here",
   which is what collector groups exist to avoid.
3. **Never rebuild an account name or home by hand** — `lfs-helper owner-name`
   and `lfs-helper pkgusr-home`. This is the bug that started all of it.

Also: wget needs `check_certificate = off` in `/etc/wgetrc` with the
`lfs-temporary-no-verify` marker, because a fresh system has no CA certificates
until BLFS `make-ca` — and you need wget to fetch make-ca.

## Things that belong to nobody

`never_claim_list` — files no package may own, however many write to them:

- `/usr/share/info/dir` — rewritten by every package that ships an info page
- `/etc/ld.so.cache`, `/var/cache/ldconfig/aux-cache` — regenerated by ldconfig
- **the user database** and Shadow's backups (`passwd-`, `group-`, `.pwd.lock`)
  — every `cmd_add_user` during a build touches them, so whichever package
  happened to be building swept them up. ncurses did not install `/etc/group-`;
  useradd did, while ncurses was building. A package owning the file that says
  which packages exist is the one ownership mistake with no way back.
- the wrapper directory — `root:root` **by design**, so a package user cannot
  rewrite the rule that constrains it

- **mail spools** (`/var/mail/<name>`) — Shadow creates one for every account
  it makes, so they arrive as a side effect of `useradd`

Recording any of them produces a conflict no repair can settle: the next
package takes the file straight back.

**A repair must not create the next run's finding.** Two passes disagreed about
`/var/mail/lfs` and each undid the other — the build-user pass gave it to root,
the unclaimed pass then reported that root holds a file no manifest claims.
`_vfy_build_user_leftovers` consults `is_never_claimed` for exactly this reason,
and there is a test on the property, not just on the one path.

## The wrappers

`make_wrappers` ships `chown`, `chgrp`, `chmod`, `cp`, `install`, `mkdir` in
`/usr/lib/pkgusr`, so a **package user** cannot change ownership. They are
ordinary files on `$PATH`, and if that directory is ever ahead of `/usr/bin`
for **root**, root's own privileged calls resolve to them too — and they report
success while doing nothing.

So every privileged ownership call goes through `real_chown` / `real_chgrp` /
`real_chmod`, which resolve the binary by absolute path via `_real_tool`.
**Ownership is root's business; no `$PATH` may come between the decision and
the filesystem.** `make_wrappers` itself deliberately uses plain `chmod` — it
is setting the mode on files it just wrote, and must stay self-contained.

## Mechanisms that are not obvious from the code

**Staged installs.** `make install DESTDIR=<stage>`, then each file is copied
beside its destination and `rename()`d over it. Never `cp -a` over a live
system: that truncates in-use shared libraries and kills running processes.
Only for `gcc glibc binutils bash coreutils`, and only for a lone
`--phase install` — see open item 4.

**Earlier stages.** A package is built more than once (ncurses in chapter 6 as
`lfs`, `python-tmp` in chapter 7 as root, then the real one as its package
user). Before building X, `_claim_earlier_stages` hands X every path recorded
under X, X-tmp, X-pass1, X-pass2 — matching case-insensitively, because book
titles are capitalised and tarball names are not.

**Adoption.** Chapter 5-6 packages get their users from the manifests. This
cannot run before book 7.6 creates `/etc/passwd`; it happens at the ownership
epoch (`init-ownership`), which is the one place that decides. Walks manifests in build order so uids read as the
build order. `adopted.list` records `name size` per package so it runs once.

**verify.** Ownership is derived state: manifests + install-dir list +
collector map determine what the tree should look like. `lfs-helper verify
[--fix]` reconciles actual against expected.

**Build ids.** Each tool prints an md5 of its own contents. Compare host and
chroot — a mismatch means the chroot is running old code, which wasted a lot of
debugging time.

**Section resolution.** `_resolve_section` matches a book section by id **or**
title. Some sub-sections carry ids the book toolchain generated
(`idm139921653990176` = 8.5.2.1 Adding nsswitch.conf) which change on every
rebuild of the book. An ambiguous title fragment is refused, not guessed at.

**Sections that ship a file.** 9.6.8 prints `/etc/sysconfig/rc.site` as a
`<pre class="auto">` block with no commands at all. `_auto_file_block` extracts
it into a quoted heredoc. Every line is commented; install it anyway — it
documents the boot-script knobs where the boot scripts look.

**Steps that are not packages.** `last-step`, `init-*` and `refind` never get
a user. `cfg_*` is decided by READING the generated script: a versioned book
section produces a phased build with `pkg_glob`, prose produces a plain root
script. Book 9.2 is `LFS-Bootscripts-20250827`, a real package.


## Sanity script

`lfs-sanity.sh` — read-only, run inside the chroot as root, writes one file:

```sh
./lfs-sanity.sh              # -> /tmp/lfs-sanity.txt
```

Eight sections: tool build ids, shared-directory modes (flags early sealing),
uid/gid collisions, unprefixed accounts, home ownership, files with no owner,
groups, and root-owned counts. Each says what a hit MEANS, so a report reads on
its own.

Section 1 **asserts** the owner and group it prints, not just the mode — a tree
ran 34 packages with every install directory at `root:root 775` while the
report said nothing, because that column was decoration.

Section 3 flags an account wearing **two** prefixes (`p_cfg_*`, `p_u_*`,
`p_p_*`). Nothing creates those any more, so one appearing means a tool is
still applying the package prefix regardless of kind. `tmp_` and `init_` are no
longer allowed either: there is no such kind of account.


## Watch on the next build

(Written before the 1.9-era rebuild; that build and a 1.11.6 build have both
completed since, and items here that they exercised are confirmed good. Kept
because a FRESH tree on a new machine walks the same order.)

1. **`ls /usr/src`** should show `pkgusr/ cfg/ lfs-pkgusr/` and nothing loose.
2. **`init-ownership` appears in `lfs-helper list`** as step 3, and turns
   `built` right after `init-files`. If it says `pending` afterwards, the
   checkpoint ran but did not mark it.
3. **`# 27 install directories are now root:install`** — not `0`. Zero is now
   an error, but see it green rather than trusting it.
4. **`ls -ald /usr/src/pkgusr/p_*` after the first few packages** — each home
   owned by its own user, not `root:root`.
5. **`/usr/src/pkgusr/p_gettext/src`** exists and is a directory, not a
   symlink.
6. **The first config step** (`cfg_nsswitch`) comes out as `cfg_nsswitch`
   under `/usr/src/cfg`, with no `p_` on it.
7. **A collector-group prompt** offers `<prefix>_perl`, never `<prefix>_p_perl`.
8. **`lfs-helper verify`** at the end: expect nothing, or a stale manifest
   entry for a file two packages both install (`/usr/bin/hostname`).

Then `bash lfs-sanity.sh` and read the `!!` lines.

## Open items

**Start here (as of 1.12.0).** The plan "one build loop, four tools" is
COMPLETE: a full fresh build proved the merged loop, and the fifth tool is
retired.  What remains is smaller: boot-test the fresh system, prove
`packagemanager update` (--phase update) on one real package, the slice-noise
sweep (item 11), and a verify + snapshot baseline of the finished system. Alongside it:

- **SysV branch, from the merged session**: booting a finished 13.0-sysv
  system is untested (the build reached chapter 8 + BLFS bootstrap). And the
  BLFS default-flavour issue below is now doubly relevant — BLFS must not
  pick a systemd-flavour default for a SysV system.
- **The live system has ~29 stale packages** against 13.0-systemd, in book
  order, with glibc/binutils behind `--toolchain`. `packagemanager update
  --reinstall` plans the whole system. Nothing large has been rebuilt yet;
  m4 is the only package that has gone through the merged runner.
- **Slice noise (item 11)** still prints `soft: command not found` and
  `unbound variable` from sliced functions; every affected test passes
  anyway, which is the trap this project has been bitten by repeatedly.

1. ~~`packagemanager setup`~~ — **done in 1.11.2.** What is left of it is the
   grant-dir door, folded into item 6.

2. ~~`strip` is asked for but does nothing~~ — **done in 1.11.27** (see the
   section above). What remains is watching the first `--run` on a real tree:
   run `lfs-helper verify` right after it.

3. **Steps 88-99 have never completed.** Steps 1-87 are well proven — the
   sources/build split ran across all of them. The last twelve are all `cfg_*`
   steps, and the fixes to them are unit-tested but have never run against the
   real book.

4. **Staging is limited to `--phase install`,** so `build-all` does not stage
   gcc or glibc. `--phase all` runs the book's post-install commands in the
   same script, and those touch live paths (`mv /usr/bin/chroot /usr/sbin`),
   which fails with DESTDIR set. Only bites on rebuilds of a *running* system.
   Deliberately deferred to item 6 — fixing it separately means restructuring
   the build loop twice.

5. **Root password** — the one decision the interview cannot hold; a plaintext
   config would be worse. Handled as far as it can be: `init-accounts` prompts,
   and `_warn_if_no_login` checks the *result* as build-all's last word. A
   non-interactive run therefore finishes with a system nobody can log into,
   loudly. Nothing further is planned.

6. **The build loop is still two implementations — and the endpoint is four
   tools, not five.** Everything else went through one door in 1.11.3 —
   wrappers, account home, collector grants — and what remains is the loop
   itself: `cmd_build` and `packagemanager_install` each drive
   unpack/build/install/configure. Item 4 (staging) lives inside it. Needs a
   real build to prove, so it is not a desk change.

   `packagemanager_install` is absorbed by the same work: its 990 lines are
   almost all duplicates of lfs-helper functions, and its one distinctive
   part (`u_` application users) is a third implementation of what
   `packagemanager user create` already does in python.

   **There is now a written plan: "Plan: one build loop, four tools" near the
   end of this file.** Read that before touching either driver.

   The original framing, still true of the loop: Nearly every bug this project has had was the same species: one
   decision held in several places, free to disagree — `cfg_bootscripts`,
   `adopted.list`, the package-user prefix, the `/sources` permissions, the
   account's kind. `install-as` is the entry point that makes unifying them
   possible. Highest value, highest risk.

7. **`migrate-layout`** — layout is configurable but only takes effect on a
   fresh build. Moving an existing system's users is not written, and the
   naming split widened the gap again: an existing tree holds
   `p_cfg_bootscripts` accounts and directories. The tools *read* those
   correctly — `pkgusr_kind` strips the package prefix before it looks, so a
   legacy name resolves to the right kind and root — but nothing renames the
   account or moves the directory. A fresh build is still the answer.

8. ~~`README.md` is stale~~ — done, and kept current. Build ids are
   deliberately not in it; they are in "Current state" above, which is the
   file that gets handed over.

9. **`lfs-sanity.sh` still reads the old state path on an old tree.** It
   takes `LFS_PKGUSR_DIR`, so it is right on anything built by 1.9.0, but it
   has no fallback for a tree built before the move. Harmless given that no
   tree is migrated; worth deleting the ambiguity if migration is ever written.

10. ~~The `2>/dev/null || true` sweep~~ — **done in 1.11.4** for ownership and
   permission calls, with `soft` and a test on the marker. `packagemanager_install`
   still has seven, all benign (chmod on a scratch directory, `disown` on a
   backgrounded mandb); they have not been reviewed one by one.

11. **Slice noise: tests that shout but still pass.** A real-system run
   prints dozens of `soft: command not found`, `WRAPPERS: unbound variable`,
   `_NEVER_CLAIM: unbound variable`, `pkgusr_prefix_for: command not found`
   from sliced functions run without their dependencies. Every affected test
   currently passes anyway — which is exactly the "empty result is not a
   pass" trap this project has been bitten by twice. The sweep: each slice
   should stub or slice its dependencies, and the suite should treat an
   unbound-variable death inside a slice as a failure of the slice, not
   silence. About ten distinct sites.


## Useful commands

```sh
lfs build-system verify        # what state is this tree in?
lfs build-system run           # continue from wherever it stopped
lfs snapshot save <n> --run    # records the toolchain state in metadata
lfs-helper verify --fix        # reconcile ownership
lfs-helper which-package <p>   # which package installed this
lfs-helper install-as <n> -- <cmd>   # install anything as its own package user
lfs-helper pkgusr-info         # where each package came from
```


## Tests

```sh
bash test_lfs_crosschain.sh ./lfs      # 644 counted results, 640 pass bare
```

Counts are kept in files, not shell variables, so subshell increments survive.
A few Python blocks print several PASS lines but count once.

"Nothing can fail silently" was not true: a test whose helper died before its
first assertion reported PASS. Use `_slice_fn` to lift a function out of a
script — never `sed -n "/^fn() {/,/^}/p"`, which cannot handle a one-liner.

**Slice the whole function, never a fixed window.** Several tests used
`grep -B 14` or `sed -n '/marker/,+6p'` around a message. Adding a branch above
the marker pushed what they were asserting out of the window, and they failed
without anything being wrong. Use `_slice_fn`.

**Do not define a function inside another one.** `_package_already_owns_files`
was first written inside `cmd_build`. bash accepts it -- and it is then defined
only after `cmd_build` has run once -- but every `sed -n '/^cmd_build() {/,/^}/p'`
in the suite stopped at the inner closing brace, silently truncating what those
tests examined.

**Match invocations, not message text.** Several tests assert that a function
no longer calls something. The comment explaining *why* it no longer calls it
names the thing, so a naive grep matches the explanation and the test can never
pass. Strip comments first, or anchor on the call syntax.

Run it from a directory holding ALL five scripts, plus `lfs-sanity.sh` and
`skel-u_xdg/.bash_profile` — about 100 tests silently skip if the others are
not beside `lfs`.


## Working style that worked

- Diagnose from evidence in the output, not from the most recent theory.
- Every bug fixed gets a regression test with a comment naming what broke.
- Verify a new test **fails on the old code**. A test that cannot fail is
  worse than no test. One nearly shipped because its slice boundary was wrong
  and it reported four false failures; another shipped and sat green for
  months, its four assertions never reached, because `sed -n "/^fn() {/,/^}/p"`
  cannot slice a one-line function and the over-captured text died under
  `set -u` before the first check. If a test has never been seen red, it has
  not been tested. Use `_slice_fn`.
- **An empty result is not a pass.** Both of those failed the same way: a
  helper was missing, the output was empty, and empty read as "no findings".
  Assert the helper exists before trusting that it found nothing.
- Assert intent, not implementation. Three tests broke on the rename because
  they grepped for literal paths rather than the property that mattered.
- Fix causes, not symptoms. Remove workarounds once the cause is fixed.
- Say plainly when something is uncertain or untested.
- **Before any restructuring, diff the command list before and after.** A
  deleted command passes every test that does not mention it — that is how
  `adopt-existing`, `sort-users` and `seal-install-dirs` silently disappeared.


## Plan: one build loop, four tools  (item 6)

Written after the "0 of 97 judged" bug (1.11.36/37) made the cost concrete,
then retargeted once the inventory showed where it actually ends: **the
endpoint is four tools, not five.** Nothing below is implemented yet.

### Why now

The split is no longer theoretical. `cmd_build` and `packagemanager_install`
each drive unpack/build/install/configure, and they diverge where it counts:

| | lfs-helper `cmd_build` | `packagemanager_install` |
|---|---|---|
| phase tracking, resumable | yes | no |
| staging / DESTDIR (item 4) | yes | effectively no |
| install record | `$MANIFESTS/<n>.files` | `~/pkg.lst` |
| version record | `VERSION` | `install_last` |

The last two rows produced the bug: two records of one fact, and each tool
blind to the other's. 1.11.37 bridged the *reading* side. This plan removes
the split.

### Where it ends: packagemanager_install is absorbed

990 lines, and almost none of it is uniquely its own:

| what it does | already exists in |
|---|---|
| build wrappers | `lfs-helper cmd_make_wrappers` |
| create the package user | `lfs-helper cmd_add_user` |
| collector groups | `lfs-helper`'s allocator |
| grant a directory, retry | `lfs-helper cmd_grant_dir` |
| diagnose a failed install | `lfs-helper` |
| stage source from /sources | `lfs-helper` |
| `u_` app users, PAM `su_u_user` | `packagemanager user create` (python) |

That last row is the sharpest: its one distinctive feature is a THIRD
implementation of application-user setup. And `packagemanager`'s own header
has carried the question since the beginning — *"keep packagemanager_install
(bash) as the privileged engine, or fold it in?"* It is answered here: fold
it in. Steps 3-5 below already hollow it out; what remains afterwards is a
shim, so the plan says so up front rather than leaving a fifth tool standing
because nobody named the endpoint.

Two things this must not lose:

- **The privilege boundary.** It is the root-side engine: it runs as root and
  does the `su -` into the package user. That boundary moves to `lfs-helper`
  (already root-only, `need_root`) deliberately — it must not dissolve into
  the python tool, which runs unprivileged for most commands.
- **The entry point.** `packagemanager_install <user> <script>` is documented,
  printed in this project's own hints, and people run it by hand. It survives
  as a COMPATIBILITY SHIM that delegates to `lfs-helper build`, for at least
  one full release, with a notice. Only then is it removed.

### The one thing to get right first: the install record

Two recorders exist because they answer the same question by different means,
and each is the only one that works in its own window:

- **Scan by timestamp** (`find -newer $stamp`) — the BUILD-STAGE recorder.
  Early in the LFS build a package's files are not yet owned by its package
  user (ownership is established later), so an ownership-based listing returns
  nothing. This variant must stay. It is also the only one that catches a
  config step that rewrites an existing file without installing a new one.
- **Scan by owner** (`list_package`, i.e. `find -user`) — the DEFAULT
  everywhere after the build stage. Authoritative once ownership holds, and
  self-correcting: it reflects the tree as it is now, not as some past run
  recorded it.

So: **one recorder function, two strategies, one explicit predicate.**

    record_install <name>
        if ownership_established_for <name>   -> owner scan  (pkg.lst)
        else                                  -> timestamp scan (manifest)
        then: reconcile, so both files exist and agree

`ownership_established_for` must be ONE named function, not an inline test
repeated in two drivers — that is the shape of every bug this project has
had. Candidate source of truth: whatever `establish-ownership` records, plus
the existing `pkgusr_ready`.

Rules the reconcile step must satisfy:

- After the build stage, `pkg.lst` is the record that gets read; the manifest
  is kept as the build-stage artifact and for cleanup (it holds *touched*
  files, which the owner scan cannot know).
- A package built in the build stage and later owned must end up with a
  `pkg.lst` without being rebuilt — the reconcile runs at `establish-
  ownership` time for every package, once.
- Neither file is ever the only copy of a fact the other needs.

### Same treatment for the version record

`VERSION` and `install_last` both say what was installed. One writer, both
files, or one file both read — decided when the loop is merged, not before.
1.11.37's read-both fallback comes OUT once this lands (fix causes, remove
workarounds).

### Steps, each shippable and testable on its own

1. **Extract the recorder.** `record_install` + `ownership_established_for`,
   both drivers call it. No behaviour change intended; the test asserts both
   files exist and agree after a build in each stage. *This step alone fixes
   the class of bug that started this.*
2. **Extract the version writer.** One function, called from both. Remove the
   1.11.37 read-fallback in the same release, with its test inverted.
3. **Extract the runner.** The `su - … bash install_<n> <phase>` invocation,
   wrappers, `pipefail`/`tee`, and the exit-code capture — one function, in
   lfs-helper, where root already lives. Both drivers spell this differently
   today; that is where "no wrappers" bugs come from.
4. ~~Move phase tracking into the shared runner~~ -- **done in 1.11.55.**
   run_phase_as takes the record key; cmd_build's private clear/record/infer
   copies are deleted; `run-script` derives the key from --user (--name
   overrides, --name '' disables).  Old-style scripts are never tracked:
   `bash script unpack` on one runs EVERYTHING, so a record of "unpack"
   would lie.  A packagemanager install that dies mid-phase now leaves a
   record `lfs-helper build <n> --phase <next>` can resume from.
5. ~~Delegate~~ -- **done in 1.11.57.**  cmd_build takes `--script <path>`
   (the loop, for a script that is not in $SCRIPTS), normalises its name
   argument through unprefix_pkg_user so records land under the step name
   whichever form the caller passed, and treats `--phase update` as a full
   run (stale-source clean, finalise, no false "earlier phases" hint;
   staging still never fires for it).  The engine's installPkg hands its
   prepared script over for every phased script when lfs-helper is
   installed; its private loop survives only for nimgnu_/u_ accounts,
   old-style scripts, and lfs-helper-less systems.  The engine's after-care
   (mandb refresh) stays in the front-matter; record-install/VERSION are the
   loop's.
6. ~~Staging applies to both~~ -- **true by construction since 1.11.57**:
   there is one loop, and _phase_can_stage rules it (lone install phase
   only, so all/update never stage).  The existing staging tests pass; the
   real-system proof rides on the next full build.
7. ~~Retire the fifth tool~~ -- **done in 1.12.0.**  See the changelog
   entry; the endpoint item 6 named is reached.

### How it gets proved

Not by desk-checking. The system now has ~30 genuinely stale packages, which
is the test bed this always needed:

    lfs-helper snapshot create pre-item6      # rollback, first
    lfs-helper verify                          # baseline, keep the output
    # pick ONE low-risk package with no dependents mid-tree: less, xz or m4
    packagemanager update less --run
    lfs-helper verify                          # must differ only for 'less'
    # then the same package by the other door, to prove they agree:
    lfs install --reinstall m4

Only after those agree: a batch of five, then the rest. Never glibc,
binutils or gcc until the loop has proven itself on the small ones.

### What would make this go wrong

- Doing it as one commit. Seven steps, seven releases, each red-tested.
- Changing the record format while merging the writers. Merge first, change
  formats never if avoidable.
- Deleting the fifth tool before the shim release. Someone's notes say
  `packagemanager_install p_foo /path/script`; that has to keep working long
  enough to be told otherwise.
- Letting the privilege boundary blur. Root-side work stays in lfs-helper,
  named and `need_root`-guarded, not sprinkled into the python tool.
- Trusting an empty scan. If `record_install` finds nothing, that is a
  failure to report, not a package that installed nothing — the project has
  been bitten by empty-as-pass at least three times.


## Known limits

x86_64 only. Kernel and bootloader are left to the user.

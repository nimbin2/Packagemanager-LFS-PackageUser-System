# lfs-pkgusr — context for a new chat

Five scripts that build and maintain an LFS/BLFS system where **every package
is owned by its own unprivileged user**.

Attach: the five scripts (`lfs`, `lfs-helper`, `packagemanager`,
`packagemanager_install`, `blfs`), plus `test_lfs_crosschain.sh`,
`lfs-sanity.sh` and this file.

**New here? "Start here" below says what to read and in what order.**

## Current state

All five tools at **1.11.6**. Build ids — check these match what is installed:

    lfs                     f1f6164
    lfs-helper              3e99aa1
    packagemanager          df7bb26
    blfs                    c479327
    packagemanager_install  1d6c685

589 regression tests, 584 pass in a bare checkout.

**This is a build candidate.** Everything since 1.11.0 is desk work — no
change has met a real build. The remaining open items need one to make
progress, so the next move is a full run, not more code. The five failures are
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

**A fresh build is required and no tree is migrated.** Account names, home
directories, the build scratch and the state directory have all moved.

    make install
    lfs build-system restart --run
    lfs build-system session --reconfigure    # several new questions
    lfs run
    # inside the chroot:
    lfs-helper --version                      # MUST read 7a7b240
    lfs-helper build-all

Afterwards `lfs-helper verify` is the real check — it reconciles ownership
across the whole tree. Then `check-toolchain`.

Kernel and bootloader are still yours to finish.

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

Nothing below has run against the real book on 1.9.0. In rough order of when
you would see it:

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

1. ~~`packagemanager setup`~~ — **done in 1.11.2.** What is left of it is the
   grant-dir door, folded into item 6.

2. **`strip` is asked for but does nothing** — and since 1.11.4 the build says
   so at the end, so it is no longer silent. Implementing it: The answer is collected and the
   prompt says NOT YET IMPLEMENTED. Not a book copy-paste: stripping rewrites
   each binary, and here a file's owner is the record of which package
   installed it, so it must run as that owner or the record drifts. Book 8.85
   also removes libtool `.la` files, which can make later BLFS builds link
   against stale paths.

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

6. **The build loop is still two implementations.** Everything else went
   through one door in 1.11.3 — wrappers, account home, collector grants — and
   what remains is the loop itself: `cmd_build` and `packagemanager_install`
   each drive unpack/build/install/configure. Item 4 (staging) lives inside it.
   Needs a real build to prove, so it is not a desk change.

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
bash test_lfs_crosschain.sh ./lfs      # 577 tests, 576 pass
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


## Known limits

x86_64 only. Kernel and bootloader are left to the user.

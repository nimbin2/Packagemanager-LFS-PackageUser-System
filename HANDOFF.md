# lfs-pkgusr — handoff

Tools for building Linux From Scratch and Beyond LFS as **package users**: one
account per package, so every file on the system has an owner, and
`packagemanager verify` can say what is installed and what is not.

Written for a **SysV** system (no systemd) built from the **systemd** BLFS
book, because BLFS published no SysV edition for 13.0.  CORRECTED
2026-09-24: the BLFS DEVELOPMENT book (`svn`, /blfs/view/svn/) is the
**System V Edition** and current -- r13.1-245, 2026-09-23.  media.stack
reads it (`from-book svn`), which for this machine is the better match: its
pages carry SysV commands, not systemctl.

    all six tools at 1.14.370  (lfs-backup has its own: 1.3.0)
    lfs               d3a1e85
    lfs-helper        281f7c9
    packagemanager    f142812
    blfs              03457ff
    lfs-phases        f299492
    lfs-kernel        f74f161   (no version line of its own)
    lfs-backup        c73acaa   (1.3.0; replaces lfs-config)
    lfs-sysvbook      62ebe64   (1.0.0; untouched since it was written)

**`BUILD.md` is the one document for building a whole system**, host to
desktop, with what to configure before each step. README.md points at it.
Keep it true: when a command or a config key changes, it changes there too.

`test_lfs_crosschain.sh` is the regression suite. It runs in pieces now:
`--list` numbers the blocks, `--from N --to M` or `--only N,M|<text>` runs
some, and a selection re-executes a generated subset (preamble + blocks +
summary) whose path it prints. rc.site now SKIPs when the book cannot have
it, so a clean run reads clean.

The full per-release history — 144 entries, every bug and what it taught — is
`HANDOFF-history.md`. It is worth grepping when something looks familiar; it
is too long to read.

---

## The state of the machine

A ThinkPad-class AMD Renoir laptop, SysV init, 93 package accounts, collector
prefix `nimgnu`, package prefix `p`.

**Built and verified: 319 packages**, `packagemanager verify` clean — the
whole sway stack (wlroots, sway, swaybg, foot, seatd, elogind, webkitgtk,
pipewire, mesa, gtk3/4, gstreamer), the network stack (wpa_supplicant, libnl,
iptables-nft with libnftnl, net-tools, dhcpcd), services (dbus, alsa,
bluetooth, acpid, fcron, blfs-bootscripts, openssh) and bash-completion.

**Kernel 7.2.4 built, installed, verified and BOOTED.** `su -` works, the
setuid bits are back, and the desktop runs: sway with foot, and the
application-account launchers in it.

**The desktop is in daily use.** 14 application accounts (browser, claude,
chatgpt, gemini, nrwgpt, grok, mercury, deepseek, github, codeberg, reddit,
youtube, dokus, mpv) with their launchers, menu entries and icons; `~/Shared`
links for the ten that asked for one; passwordless `su` to each through
/etc/pam.d/su_u_user.

**Wired networking works and now starts itself.** The interfaces are
`enp2s0f0` and `enp5s0` (not the `eth0` of any example), and `cfg bootscripts`
wrote an `/etc/sysconfig/ifconfig.<iface>` for each: ONBOOT, SERVICE=dhcpcd.
sshd's init script and its rc?.d links are installed.

**Wireless is the one piece still missing.** The interface is `wlan0` on this
kernel — NOT the `wlp3s0` this file said for months, and not `wifi0`. It needs
two files nothing may write for you, because one of them holds a key:
/etc/sysconfig/ifconfig.wlan0 (SERVICE=wpa, handing off to dhcpcd) and a
per-SSID /etc/sysconfig/wpa_supplicant/wpa_supplicant-wlan0.conf, chmod 600.
`packagemanager stack network --only net-wifi --run` prints both, with the
hand-off variable read off this machine's own `/lib/services/wpa`.

**Not verified since the tools changed under it:** whether the locale step has
run (see below), whether a .desktop entry launches now that the launcher
allocates a pty, and `packagemanager service`, which has never run on this
machine.
---

## What to do next, in order

Everything here is on the machine, not in the tools.  The tools are at
1.14.302 and clean.

1. **The locale.**  Nothing sets `$LANG`: lfs-helper wrote an i18n.sh with the
   export commented out (1.14.298) and there is no /etc/locale.conf.  Every
   program is in the C locale and foot says so at every start.

       lfs config locale de_DE.UTF-8         # if it is not that already
       packagemanager stack services --only shell-env --run
       # then log in again, or:  . /etc/profile.d/i18n.sh

2. **The launchers written before 1.14.295.**  A menu entry does nothing when
   the launcher does not allocate a pty for `su`, and a launcher these tools
   did not write is left alone.  `~/bin/claude` is the last hand-made one:

       rm ~/bin/claude
       packagemanager stack services --only app-users --run

   Then click a menu entry.  If one still does nothing, run it from a
   terminal first -- that path prints everything `su` has to say.

3. **Wireless.**  `packagemanager stack network --only net-wifi --run`, then
   write the two files it prints for `wlan0`.

4. **make-ca's weekly job.**  The systemd book enables a timer, which the shim
   skips; fcron is installed, so the 12.4 book's cron entry goes in by hand:

       cat > /etc/cron.weekly/update-pki.sh << "EOF"
       #!/bin/bash
       /usr/sbin/make-ca -g
       EOF
       chmod 754 /etc/cron.weekly/update-pki.sh

5. **Try the new commands once**, so their first use is not in an emergency:
   `packagemanager service` (list, then `service sshd start`), and
   `packagemanager stack dev --run` for gdb.

Smaller, none blocking: `dbus` was built before `[dbus] systemd = disabled`
went into machine.conf (rebuild or accept); a stray `.service` from
at-spi2-core sits in `/usr/lib/systemd/user`; `/etc/bashrc` on this machine
has a mangled line (`# End /etc/bashrcCK=$(tput setaf 0)`) where an append
ran without a leading newline -- harmless, `BLACK` is simply unset.
---

## The tools

    lfs                 the LFS build: interview, chroot, chapters 5-8
    lfs-helper          the in-chroot driver (bash; no Python in the chroot)
    packagemanager      BLFS packages, stacks, accounts, verify
    blfs                turns book pages into install scripts
    lfs-phases          the phase runner every generated script sources
    lfs-kernel          build/install/verify a kernel and its firmware
    lfs-backup          back up backup.conf's files; restore creates what is
                        missing and writes .new beside everything else
                        (replaced lfs-config in 1.14.291)
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

**A feature is not proved by a file existing.** ffmpeg and SDL3 installed,
passed `have=`, and had no ALSA, because the library was built after them.
An autodetected feature needs its dependency placed by entry order and a
probe (`expect=`) that reads the built artifact.

**A repair must not be able to fail the thing it is repairing.** It runs
after something already went wrong, so every input it reads may be missing
and every variable it names must be one the caller actually sets.

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

## 1.14.239 -- shadow stops at configure: --disable-logind

    checking for sd_session_get_remote_host in -lsystemd... no
    configure: error: libsystemd not found.  If logind integration is not
    required, disable it using the --disable-logind option.

shadow 4.20 auto-detects logind, and the book's page -- written for a
systemd host where libsystemd is simply present -- passes no switch either
way.  On this machine it stops.  configure names the flag itself, so:

    [shadow]
    configure_args = --disable-logind

Verified: the flag lands on the book's own `./configure` line.

This IS the case `book =` was built for -- a page whose COMMANDS do not
suit this machine -- but the 12.4 page would also mean shadow 4.18.0, and
one switch is cheaper than four versions back.  Recorded next to the setting.

**shadow was interrupted mid-build**, so on the machine:

    packagemanager update shadow --reinstall --regenerate --run --yes

`--regenerate` matters: machine.conf is applied when the script is written,
and the script on disk was written before that section existed.

## 1.14.240 -- `book` is for the tool, and it reached the build line

    meson setup -Dbook=/usr/share/blfs/books/BLFS-BOOK-12_4-nochunks.html ..
    ERROR: Unknown option: "book".

`[linux-pam] book = ...` says WHICH BOOK to read that package from.  It is
addressed to the tool, and every other key in a machine.conf section is a
BUILD option, so it went straight onto the meson line.  `jobs` and
`configure_args` were each popped out by hand; `book` was new and nobody
popped it.

A reserved SET now, so the next such key cannot leak the same way.
`_warn_unknown_meson_opts` could not have saved this: at script-generation
time the source is not unpacked, so there is no meson.options to check
against.

Asserted with a fixture carrying BOTH kinds in one section -- `book` must
not reach the build line, `jobs` must still become `ninja -j4`.

Two things visible in that script worth noting:

  * the override WORKS -- `required=('Shadow-4.18.0')`,
    `name_version='Linux-PAM-1.7.1'`, `pkgusr_book_mirror=.../12.4`: the
    whole page came from the older book, which is the design.
  * 1.14.238 said linux-pam does not need the override (13.1's page needs
    nothing from systemd to build, and `install` drops avoided packages by
    itself).  With this fixed, either choice now works; the newer page
    still means 1.7.2 instead of 1.7.1.

## 1.14.241 -- zathura and imv, and a package that was built and avoided

Neither is in the BLFS book, so they are `git` entries in **sway.stack**
(with the other applications, not media.stack -- media is the codec chain,
and a PDF viewer is not a codec).

CHECKED with git ls-remote, all four at once:

  * **girara, zathura, zathura-pdf-poppler share the tag 2026.07.18** --
    they are one project released together, and mixing tags is the usual way
    to end up with a zathura that cannot open a PDF.  The suite asserts one
    tag across the three.
  * **imv v4.3.0**; its repo answers on both exec64/imv and eXeC64/imv.

**zathura is three packages.** girara is its widget library, the core opens
no formats at all, and the backend is a separate plugin -- a zathura with no
plugin starts, shows a grey window and says nothing.  So the probe looks for
`/usr/lib/zathura/libpdf-poppler.so`, not for the binary.

**poppler left avoid.stack.**  It was there as libcupsfilters' child;
zathura's backend wants it, so it is a `book poppler` entry now.  mupdf
stays avoided -- it is the other backend and one is enough.

**And the check for that class found a real contradiction:** `avoid openssh`
was in avoid.stack while network.stack BUILT openssh with the install-sshd
bootscript.  Two files disagreeing about one package, and whichever a plan
saw first won.  Removed, and every stack is now checked for it.

One test bug fixed on the way: the accounts-before-openssh assertion
compared an AVOID entry (index 50) against a build entry (73) and called
the order wrong.  It filters to build entries now -- the cost of every
stack including the exclusions is that an index means nothing unless you
say which kind you mean.

## 1.14.242 -- cmake will not overwrite a symlink, and journald came back

**tiff.**  Round 1 of the repair worked -- `/usr/lib/pkgconfig/libtiff-4.pc
belongs to p_libtiff -- handing it to p_tiff` -- and the retry then died on

    file INSTALL cannot duplicate symlink ... at /usr/lib/libtiff.so.6
    because: File exists

Ownership was never the problem: cmake refuses to REPLACE a symlink at all,
so handing it over changes nothing.  It has to go.  The repair removes a
symlink owned by ANOTHER PACKAGE USER (never root's, and it says whose it
was) and lets the install create its own.

The extractor also had to grow: in the symlink message the paths are NOT
quoted, unlike `cannot copy file "A" to "B"`, which is why it saw nothing
and the round did nothing.

**p_libtiff AND p_tiff are the same upstream package** -- 12.4 titles the
page libtiff, 13.1 titles it tiff.  Two accounts, two copies of one
library, and whichever installed last owns every file.  Reported here, NOT
fixed: `packagemanager which-package /usr/lib/libtiff.so.6` says who holds
it today, and one of the two accounts should be retired deliberately.

**webkitgtk: `fatal error: systemd/sd-journal.h`** -- my regression.  The
machine's own conf had `ENABLE_JOURNALD_LOG = OFF`; the [webkitgtk] section
I shipped at 1.14.203 did not, so taking the shipped version dropped it and
webkit autodetected journald.  Nine thousand files in.  Restored, with
ENABLE_BUBBLEWRAP_SANDBOX = OFF beside it (also in the machine's conf and
also missing from mine).

When a shipped section replaces a hand-made one, every switch that is
missing from it is a switch silently turned back to its default.  `diff
machine.conf machine.conf.new` before taking one.

## 1.14.243 -- poppler's soft-mandatory deps, and bubblewrap confirmed

**ENABLE_BUBBLEWRAP_SANDBOX = OFF is in the shipped [webkitgtk] section**
(1.14.242, beside ENABLE_JOURNALD_LOG).  Both were restored in the same
edit; `grep -A9 '^\[webkitgtk\]' machine.conf` shows the pair.

**poppler stops at configure for nss, and would then stop twice more.**
cmake calls these "soft mandatory" -- absent, they fail the configure and
name the switch themselves:

    Could not find the 3.98 version of NSS3.  If you're not interested in
    the features it provides set the cmake ENABLE_NSS3 option to OFF

The point nobody had noticed: **nss, boost and gpgmepp are in avoid.stack
AS POPPLER'S CHILDREN** -- they were avoided because poppler was.  Promoting
poppler out of that list (1.14.241, for zathura's backend) brought all three
back into question, and each would have failed in turn, one long configure
apart.  They serve PDF signature verification and the splash backend;
zathura's poppler-glib backend needs none of it:

    [poppler]
    ENABLE_NSS3  = OFF      # OBSERVED -- the failure above
    ENABLE_GPGME = OFF      # ANTICIPATED, same avoid list, same mechanism
    ENABLE_BOOST = OFF      # ANTICIPATED

The comment marks which was seen and which was inferred, and the three
children STAY avoided -- turning the features off is the whole point.
Verified the switches reach the book's `cmake -D CMAKE_BUILD_TYPE=...` line
(it sits after `&&`, which 1.14.222 taught the merge to handle).

**The general rule worth carrying:** a package promoted out of avoid.stack
brings its avoided children back into question.  The suite now checks this
particular case; the pattern will recur the next time something is
promoted.

## 1.14.244 -- two invented values in one entry

Both mine, both from guessing instead of reading, and both caught by
machinery that was working correctly:

  * **`-Dsqlite=enabled`** stopped meson dead: `Unknown option: "sqlite"`.
    zathura has no such option.  Its meson.build takes sqlite
    unconditionally -- `dependency('sqlite3', version: '>=3.35.0')` -- and
    its only options are synctex, seccomp, landlock, manpages, tests-x11,
    tests-wayland and convert-icon.  Dropped; sqlite3 is already installed
    (p_sqlite).
  * **`have=/usr/lib/pkgconfig/girara-gtk3.pc`** made the stack refuse to
    record a girara that had installed perfectly:
        girara finished, but /usr/lib/pkgconfig/girara-gtk3.pc is still
        missing -- NOT recording it as done
    girara's meson.build says `pkg.generate(name: 'girara')`, so the file
    is **girara.pc**.  That message is the have= check doing its job on a
    wrong have=, which is the better failure of the two.

The pattern, three sessions running now (librice's four wrong guesses, the
zathura option, the girara filename): an entry's option names and installed
filenames must come from the source, and the source is one `git clone
--depth 1` away.  Asserted both, by the shape that was wrong.

(The run also reported `misplaced home: p_zathura is recorded at
/usr/src/p_zathura` and moved it to /usr/src/pkgusr/p_zathura by itself --
that check earning its keep.)

## 1.14.245 -- zathura also wants libxxhash

    Run-time dependency libxxhash found: NO (tried pkgconfig and cmake)
    meson.build:57:9: ERROR: Dependency "libxxhash" not found

The BLFS book mentions xxhash eight times and gives it **no page**, so the
entry is ours.  Checked in the checkout rather than guessed, for once
without a correction afterwards:

  * newest tag **v0.8.3**;
  * it ships `libxxhash.pc.in`, so the pkg-config module really is
    `libxxhash` -- the name meson asks for -- and `make install` runs
    `install_libxxhash.pc` among its targets;
  * a plain Makefile, no meson or cmake: `PREFIX` and `LIBDIR` are what it
    takes.

Placed at 143, between girara (142) and zathura (144); the suite fails if
either dependency lands after zathura.

Everything else in that run was right: girara `installed` with the
corrected have=, poppler `done` with the three ENABLE_*=OFF switches, and
poppler and openssh both gone from the "never built by this stack" line.

## 1.14.246 -- a book entry was recorded done without being checked

    pkg-config --list-all | grep -i poppler     -> nothing
    ...while the stack said:  book poppler  done (stack cache)

poppler was never installed, the stack believed it was, and every later run
skipped it -- so zathura-pdf-poppler kept failing on
`Dependency "poppler-glib" not found` for a dependency the plan was certain
it had.

The "is it actually there afterwards?" guard existed and covered **git and
tar only**.  A `book` entry went straight to `_stack_mark_done`.  Now every
kind answers the same question: git/tar by have=/prog=, book by the package
state that `verify` reads -- and an empty manifest is not an install.

Also asked for and added:

    [poppler]
    ENABLE_GLIB = ON

cmake autodetects the glib frontend, and that frontend is the entire reason
poppler is in this stack.  The thing a chain exists for should be asked
for, not inferred -- the gst-plugins-ugly `gpl` rule again.

### Why the dependency was not "pulled in"

It cannot be.  girara, xxhash, zathura and the backend are `git` entries,
and dependency resolution only works for `book` entries -- required= and
recommended= come from the book page.  A git entry has no page, so nothing
can know zathura needs girara.  That ordering is by hand in the stack file,
which is why the suite asserts it.

## 1.14.247 -- the fourth soft-mandatory switch, and how to stop guessing

    Could not find the 6.4 version of Qt6Core.  If you're not interested in
    the features it provides set the cmake ENABLE_QT6 option to OFF

`ENABLE_QT6 = OFF`.  qt6 is in avoid.stack and poppler's page passes only
`ENABLE_QT5=OFF`, because a BLFS system is expected to have qt6.

That is **four** of these found one configure at a time -- NSS3, then GPGME
and BOOST (guessed from the avoid list), now QT6 -- each a full cmake run
apart.  The list was never a guessing game: poppler's own CMakeLists names
every one, and on that machine the file is right there:

    grep -n find_soft_mandatory_package \
         /usr/src/pkgusr/p_poppler/src/poppler-*/CMakeLists.txt

That is in machine.conf beside the switches now, to be read once when
poppler moves version rather than rediscovered a configure at a time.  The
suite checks the four switches and that the grep is written down.

The general shape, for the next package like this: when a build names a
switch in its own error message, that switch has SIBLINGS, and the
mechanism that produced the message (here `find_soft_mandatory_package`) is
greppable in the source that is already unpacked.

## 1.14.248 -- `update` is a compound phase too

Asked whether there is a general problem with rebuilding the whole package.
There was:

    !! phase 'install' FAILED          <- the inner phase that failed
    /usr/share/gir-1.0 -> group nimgnu_gir (owner p_glib2, + p_poppler)
    # retrying poppler (phase update), round 1 ...
    unpacked into /usr/src/pkgusr/p_poppler/src/poppler-26.08.0
    -- The C compiler identification is GNU 15.2.0        <- from scratch

145 files were already installed and the grant had fixed the one thing that
was wrong.  The retry re-unpacked the tarball and re-ran cmake anyway.

`_retry_phase` mapped the inner failure for `all` and for nothing else, so
a failure inside `update` retried `update` -- and `update` re-unpacks.  Both
compound phases use the inner phase now; a single-phase run keeps its own
(1.14.209).

That is the third time this exact shape has cost a rebuild: 1.14.70 (foot,
seven rounds), 1.14.209 (the second round re-cloning), and now the compound
phase that was not in the list.  The rule: **whenever a retry picks a
phase, it picks the one that FAILED, and the log says which that was.**

The grant itself worked exactly as intended, and is worth noting because it
is the good half of that output: `/usr/share/gir-1.0 is owned by 'p_glib2'
-- asking rather than opening it to every package`, then a collector group
for the two of them.

## OPEN BUG -- a skipped step leaves its privileged half live (poppler)

    make: *** No rule to make target 'install'.  Stop.
    !! phase 'install' FAILED (exit 2)     ...after 218 files installed fine

**Diagnosed, NOT fixed.**  Generated from the real book, poppler's install
phase comes out as:

    ninja install
    install -v -m755 -d /usr/share/doc/poppler-26.08.0 &&
    cp -vr ../glib/reference/html /usr/share/doc/poppler-26.08.0
    ## SKIPPED -- the book says: If you downloaded the additional encoding data package...
    # tar -xf ../../poppler-data-0.4.12.tar.gz &&
    # cd poppler-data-0.4.12
    make prefix=/usr install          <- LIVE

The book writes an optional step as a PAIR: an unprivileged block that
unpacks and `cd`s into a sub-package, then a `<pre class="root">` block that
installs it.  The guard comments out the first half and leaves the second
running -- so `make` runs in poppler's own ninja build directory, which has
no Makefile.  The tell is the `cd`: whatever follows a skipped block that
ends by changing directory runs in that directory or not at all.

I wrote that rule into both emitters (`extract_commands` and
`extract_commands_phased`) and **neither fired** -- the regenerated script
was byte-identical.  **1.14.262 found why: there is no third path.**  The
index cache was keyed on the book file and a hand-bumped CACHE_VERSION, so
the script was rendered from data the OLD code had extracted; the patches
never ran.  The cache key now includes blfs's build id.  The reverted rule
is probably right as written -- re-apply it and regenerate.  Both patches are REVERTED rather than shipped: code that
fails the one case it was written for is worse than an admitted bug, and
the next person needs the diagnosis, not my dead code.

Still reproducible from the rendered book (poppler-26.09.0, 1.14.262).
Where to start: re-apply the `cd` rule, then regenerate poppler --

    blfs --book-file <the 13.1 book> script poppler -o /tmp/x

-- and find which emitter actually appends `make prefix=/usr install`.

**Meanwhile, on the machine:** poppler IS installed (218 files, and
`ninja install` plus the doc copy both ran).  Delete that one line from the
script and finish:

    sed -i '/^make prefix=\/usr install$/d' /usr/src/pkgusr/p_poppler/install_Poppler-26.08.0
    lfs-helper build poppler --phase install --force
    pkg-config --modversion poppler-glib

Do NOT `--regenerate` poppler until this is fixed: it will put the line
back.

## 1.14.250 -- `home` was not in scope, so the marker was never written

    # tracked 218 file(s) for 'poppler'
    /usr/bin/lfs-helper: line 7345: home: unbound variable
    # poppler: done (all phases complete)

poppler installed.  The line between those two is mine: the
`.pkgusr-installed` marker from 1.14.236 reads `$home`, which is a local of
the INSTALL function and not of the one that prints "done (all phases
complete)".  Under `set -u` that aborted the block -- so the marker, the
entire point of 1.14.236, was never written for any package.

It resolves the home the way every other caller here does,
`pkgusr_home_for "$name"`, and only writes when install_last is really
there.  Asserted three ways: the old `$home` read must be gone, the
resolver must be used, and the marker must still sit within a few lines of
the success line.

Worth naming the shape: 1.14.236 was tested by calling the PREDICATE
(`gather_user().version` with and without a marker) and never by running
the code that writes it.  A test that exercises the reader and not the
writer proves half a feature.

## 1.14.251 -- application homes in /usr/src, and imv's missing DSO

    ls /usr/src/
    cfg  lfs-pkgusr  linux  p_mytools  pkgusr  u_browser-big  u_browser-mini  u_claude  u_test

**An application user is not a package user.**  `add_package_user` creates
the account -- it handles the uid range and the matching group -- and it
puts the home where PACKAGE homes go.  A package user's home is a build
tree; an application user's home holds a browser profile, a .config, a
Downloads directory.  It belongs in /home, which is also where the shared
links and the XDG skeleton expect it.

`_relocate_app_home` moves it with `usermod -m` (contents included) and
chmods 0750 -- but ONLY from the package tree, and only when the target
does not exist.  A home someone has already placed elsewhere is left alone
and said so.

For the four accounts already made:

    usermod -d /home/u_claude       -m u_claude       && chmod 0750 /home/u_claude
    usermod -d /home/u_browser-mini -m u_browser-mini && chmod 0750 /home/u_browser-mini
    usermod -d /home/u_browser-big  -m u_browser-big  && chmod 0750 /home/u_browser-big
    usermod -d /home/u_test         -m u_test         && chmod 0750 /home/u_test

**imv: `undefined reference to symbol 'ubrk_close_78' ... DSO missing from
command line`.**  icu splits its API across libicuuc (common), libicui18n
and libicuio; imv's meson names libicuio, calls into libicuuc, and links
with -Wl,--no-undefined -- so the indirect dependency is an error, not a
warning.  `-D c_link_args=-licuuc` names it.  Nothing is patched.

### (FIXED in 1.14.252 -- see above) shadow's install strips su's setuid bit

Named, not fixed, and it needs its own session: the LFS Shadow page sets
4711 on /usr/bin/su and the BLFS page does not, so a BLFS-driven reinstall
of shadow leaves su non-setuid -- and the same applies to passwd, chage,
gpasswd and newgrp.  `lfs-helper setid` records bits a PACKAGE USER was
refused; these are bits the SCRIPT never asks for, so there is nothing to
record.  What it wants is a declared list of required setuid/setgid files
(the accounts.conf shape), enforced after any install that touches them.
Until then, after any shadow install:

    ls -l /usr/bin/su /usr/bin/passwd /usr/bin/chage /usr/bin/gpasswd /usr/bin/newgrp
    chmod 4711 /usr/bin/su

## 1.14.252 -- pam then shadow, and the modes are FIXED not reported

Asked for both, and both were right.

**`cfg shadow-pam`, immediately after `book linux-pam` in services.stack.**
Installing PAM changes nothing on its own: until shadow is rebuilt against
it nothing reads /etc/pam.d, so `su - u_claude` kept asking for a password
however correct su_u_user was.  The book's Linux-PAM page ends with "You
should now reinstall the Shadow package"; that is now a step rather than a
sentence.  It checks its own effect with `ldd /usr/bin/su | grep libpam`,
and with no PAM installed it says so and does nothing.

**And the setuid bits are applied, not warned about.**  The rebuild strips
them -- the BLFS Shadow page never sets them, the LFS one does -- so the
very rebuild that makes PAM usable broke su.  Declared in
**stacks/setid.conf**:

    /usr/bin/su       | 4711 | root | -
    /usr/bin/passwd   | 4711 | root | -
    /usr/bin/chage    | 4711 | root | -
    /usr/bin/gpasswd  | 4711 | root | -
    /usr/bin/newgrp   | 4711 | root | -
    /usr/sbin/unix_chkpwd | 4755 | root | -

`-` in the group column KEEPS what is there, which is what was asked for:
the group stays p_shadow (ownership follows the installer in this system;
only the USER must be root for a setuid bit to mean root).  Result on a
test file: `4711 root:p_shadow`.

Two details that decide whether this works at all:

  * **chown CLEARS the setuid bit**, so chmod runs last.  The suite checks
    the line order, not just that both calls exist.
  * it reads the mode BACK afterwards -- a setuid bit that did not take is
    the entire failure this step exists to end.

`lfs-helper setid` is still the right tool for bits a build ASKED for and
was refused; these are bits no script ever asks for, which is why they need
declaring.

## 1.14.253 -- `pam_start: error 26` -- linked, with nothing to read

    su: pam_start: error 26

PAM_ABORT: there is no /etc/pam.d/su.  So the rebuild in 1.14.252 worked --
su links libpam now -- and left it worse than before, because a PAM-linked
su with no service file cannot fall back to anything.

`update` runs install.  It does NOT run configure, and those files are
written by the CONFIGURE phase: linux-pam's writes /etc/pam.d/system-auth,
system-account, system-session, system-password; shadow's writes
/etc/pam.d/su, login, passwd, chage and the rest.  Both were skipped by
every `update --reinstall` of either package.

`cfg shadow-pam` now checks for /etc/pam.d/su and /etc/pam.d/system-auth,
runs `packagemanager script configure linux-pam` and `... shadow` when they
are missing, and reads back that both files exist -- naming the error they
produce if they do not.

The general shape, worth keeping: **install and configure are different
phases, and a package whose configure writes system files is not finished
by an install.**  That is the third face of the same coin as
"/etc/pam.d/su_u_user is inert until shadow links pam" and "a rule on disk
is not a rule in force".

## 1.14.254 -- config BEFORE the rebuild (the window where nothing builds)

1.14.252/253 rebuilt shadow and THEN wrote /etc/pam.d.  Between those two
there is a state where su links libpam and has no service file -- and every
build in this system runs as its package user through `su - p_<pkg>`, so
that window is one where **nothing can be built**, including the configure
phases that would write the missing file:

    # packagemanager script configure linux-pam
    su: pam_start: error 26

Root's own su survives it because pam_rootok is sufficient -- which is why
`su - p_bash` still worked and reported the pam failure as `(Ignored)`.
That is the only reason this was recoverable.

So the step is reordered: **write the config, then rebuild.**  A run that
stops midway now leaves pam config and a non-pam su (harmless) rather than
a pam su and no config (nothing builds).  Asserted by LINE ORDER, not by
the presence of both calls.

One more bug in the same file: step 1 called `_pam_installed` forty lines
above where it was defined.  Under `set -u` that is a command that does not
exist yet, so the config would silently never have been written.  Both
helpers are defined before either step, and the suite checks that too.

### If it ever happens again

Root can write those files directly -- no su involved.  The contents are on
the book's Linux-PAM and Shadow pages; /etc/pam.d/su wants the `pam_exec.so
quiet /etc/pam.d/su_u_user` line FIRST, then pam_rootok, then pam_unix.

## 1.14.255 -- the noise on every build: package users have no shadow entry

    su: Authentication service cannot retrieve authentication info
    (Ignored)

Not cosmetic, because **every build in this system is a `su - p_<pkg>`**:
that line will now appear in every package build and every log.  pam_unix
reads /etc/shadow; `add_package_user` writes /etc/passwd and leaves no
shadow entry, so pam_unix cannot find the account.  It is "(Ignored)" only
because pam_rootok already succeeded for root -- for a non-root caller it is
a real failure.

`cfg shadow-pam` step 4 lists the accounts with no /etc/shadow entry, backs
up /etc/shadow, runs **pwconv** (shadow's own tool: it adds a locked entry
for every passwd entry that lacks one), and reads back whether they
appeared -- naming any that did not.

**UNVERIFIED:** detection, backup and read-back were exercised against a
fixture; `pwconv` itself was not, because it edits the real /etc/shadow and
there is no safe way to run that here.  The script says so where it runs it.
If pwconv turns out not to cover these accounts, the read-back names them
and the backup is beside the file.

### State after this session

pam config in place, `/usr/bin/su` links libpam, 6 setid files checked and
0 corrected (the bits were already right).  What remains is one test:

    su - u_browser-mini -c id

and, if that works, the home moves (`usermod -d /home/u_<n> -m u_<n>`) plus
`packagemanager stack services --only app-users --run` to recreate the
~/Shared links and the SHARED_* fragment against the new homes.

## 1.14.256 -- the shared directory was built under /usr/src too

    $ mkdir -p /usr/src/u_claude/Shared
    /home/n76310/Shared/Claude -> /usr/src/u_claude/Shared

The homes had been moved to /home with usermod, and the next
`cfg app-users` run rebuilt Shared in the package tree anyway.  Cause:
`appuser_home()` returned **BASE_DIR** -- so an application user's home,
its shared directory and its XDG profile link all defaulted to /usr/src.
1.14.251 moved the ACCOUNT's home and left three other places reading the
old default.

Two changes:

  * `appuser_home()` defaults to **/home** (still configurable as
    `appuser_home`).
  * `_app_home(u)` asks **passwd first**, then falls back -- so an account
    whose home has already been moved keeps it, which is exactly the case
    that failed.  The shared directory and the .bash_profile link both use
    it.

### STILL OPEN from the same output

  * **step 4 (pwconv) did not run.**  `shadow-pam` printed neither "every
    account has an /etc/shadow entry" nor the missing list, so the block was
    not reached -- and `su - p_bash` still says "cannot retrieve
    authentication info".  The installed script is the thing to check:
        grep -n pwconv /etc/pkgusr/stacks/shadow-pam.sh
    If that is empty, `make install` kept an older copy (it keeps a file you
    have edited, and says so).  If it is present, the guard above it
    (`[ -r /etc/passwd ] && [ -r /etc/shadow ]`) is what to instrument.
  * **/etc/pkgusr/skel-u_xdg/.bash_profile does not exist** on that
    machine, so the profile link fails with ENOENT for every account.  The
    file is in the zip under skel-u_xdg/; `make install` reported "kept your
    existing .bash_profile" for it, which cannot be true if the file is
    missing -- that message is worth distrusting.

### Corrective commands for the machine

    for u in u_claude u_browser-mini u_browser-big; do
      mkdir -p /home/$u/Shared && chown $u:$u /home/$u/Shared && chmod 2770 /home/$u/Shared
      cp -a /usr/src/$u/Shared/. /home/$u/Shared/ 2>/dev/null || true
      rm -f "/home/n76310/Shared/$(echo ${u#u_} | sed 's/^./\U&/')"
    done
    packagemanager stack services --only app-users --run     # relinks to /home

## 1.14.257 -- there is no /etc/shadow on this machine

    # ls -l /etc/shadow
    ls: cannot access '/etc/shadow': No such file or directory

That is the whole explanation for `su: Authentication service cannot
retrieve authentication info` on every package build: pam_unix reads
/etc/shadow and there is none, so it can look up NO account.  The passwords
live in /etc/passwd, the traditional way, which is what LFS leaves when
Shadow is built without PAM.

And my guard was `[ -r /etc/passwd ] && [ -r /etc/shadow ]` -- so the step
skipped in silence on precisely the system that needs it.  That is why the
earlier run printed nothing either way.

`pwconv` CREATES /etc/shadow from /etc/passwd, moving each hash out and
leaving `x` behind.  That changes how the machine authenticates, so the new
branch:

  * backs up **/etc/passwd** (the file that changes), not /etc/shadow;
  * requires `^root:` in BOTH files afterwards before calling it done;
  * chmods /etc/shadow 600 and reports the entry count;
  * on any failure restores passwd, removes the half-made shadow, and says
    nothing changed;
  * prints the undo by hand: `cp -p <backup> /etc/passwd && rm -f /etc/shadow`.

**CONFIRMED ON THE MACHINE.**  The rollback path was exercised here
(shadow absent, passwd restored); the SUCCESS path was then run for real:
pwconv created /etc/shadow, root survived, and

    # su - p_bash -c id
    uid=10006(p_bash) gid=10006(p_bash) groups=10006(p_bash),9999(install)

-- silent, no "cannot retrieve authentication info".  That line is gone
from every future build log.  The remaining `cannot set terminal process
group` / `no job control` pair on an interactive `su -` is unrelated to
pam -- and CONFIRMED on the machine: shadow 4.20's su calls setsid() for
the target shell when the CALLER IS ROOT and the kernel still allows legacy
TIOCSTI (`/proc/sys/dev/tty/legacy_tiocsti` not 0), so the user cannot push
keystrokes into root's terminal.  The shell gets its own session (SID = its
PID, TTY `?`), and bash has no job control.  Fix is the kernel's:
`dev.tty.legacy_tiocsti = 0` (sysctl) or CONFIG_LEGACY_TIOCSTI=n -- the
latter is in kernel.conf's CONFIG_SET since 1.14.277.

It is also worth asking whether this is wanted at all: the system works
today, and the only symptom is a noisy line on every build.  Converting to
shadow passwords is the conventional answer and PAM expects it -- but
"leave it alone" is a legitimate choice, and then the line is cosmetic.

### And the Shared layout is right now

    Claude       -> /home/u_claude/Shared
    Browser-mini -> /home/u_browser-mini/Shared
    Browser-big  -> /home/u_browser-big/Shared

with `.bash_profile already points at the XDG profile` for all three.  One
thing still open there: `/tmp/xdg-n76310 is group 'n76310', which is not a
shared group` -- the session-group half of --shared, which needs the sway
session up with a proper runtime group.

## 1.14.258 -- apply the setid bits, and four that were missing

Two things from shadow's install output.

**It printed nine chmod lines and walked away.**
`report_setid_requests` runs AS ROOT, immediately after the install -- the
one moment when the thing that is missing can simply be done.  It now calls
`cmd_setid --run` (which applies each recorded request and reads the mode
back) and reports what it DID.  Non-root callers still get the old advice,
because then it really is advice.  Same lesson as the PAM file's mode and
/etc/pam.d/su: warning about a one-line fix you are already privileged to
make is not help.

**And setid.conf declared five of shadow's nine.**  chfn, chsh, newgidmap
and newuidmap were missing -- read off that request list, not guessed.  Ten
lines now.

### On the other question: do shadow and pam each get the other's features?

**Shadow has to be built TWICE, and that is unavoidable.**  Their pages
require each other: Linux-PAM's page lists Shadow as required, and shadow
only gains PAM support if libpam exists when it configures.  So the order is

    1. shadow        (no PAM -- this is what the LFS build leaves)
    2. linux-pam     (needs shadow)
    3. shadow again  (now with PAM)  <- `cfg shadow-pam` does this

PAM itself does NOT need a second pass: nothing in its configure depends on
a feature shadow gains later.  So one rebuild, of shadow, in that order --
which is exactly what services.stack does, with `cfg shadow-pam`
immediately after `book linux-pam`.  The step checks `ldd /usr/bin/su |
grep libpam` rather than assuming, so a shadow that somehow already has it
is not rebuilt.

### Asked for and NOT built: a general post-install root file

The idea is right and the mechanism half exists (`.pkgusr-setid.requests`
is exactly this, for one kind of request).  A general
`$home/.pkgusr-root.post` run by root after a successful install would cover
setid bits, udev reloads, ldconfig, bootscript symlinks -- everything that
currently needs a named repair.

It is NOT implemented here because of one hard requirement: that file must
be **root-owned and unwritable by the package user**, and the runner must
verify that before executing a line of it.  A file inside the package
user's own home, written by root, that root later executes -- if the
package user can touch it, every package on this system has a root
escalation.  The verification (ownership, mode, no symlink, parent
directory not writable) is the feature, and it wants writing deliberately
rather than at the end of a long session.

## 1.14.259 -- root:p_shadow, and a backtick that ran a command

Both mine, both visible in that output.

**`root:root` threw away the package group.**  Only the USER has to be root
for a setuid bit to mean root; the group is how this system records which
package owns a file, which is the whole point of package users.
setid.conf already used `-` for exactly this -- the REQUEST path
(`cmd_setid --run`, which handles the bits a build asked for and was
refused) forced root.  It keeps the group the file already has now:

    /usr/bin/su is now 4755 root:p_shadow

**And the report printed twice, mid-sentence:**

    applied.  Setuid/setgid bits refused during the build ...
    ... every setid bit this system needs is in place lists anything still outstanding.

My success line said `` `lfs-helper setid` `` inside double quotes, so the
shell RAN it and pasted a whole second report into the middle of the
sentence.  Single quotes.  A backtick in a double-quoted string is a
command, not punctuation -- and this is the fourth time this session that
a quoting mistake produced output that looked like a tool bug.

Test-harness note in the same spirit: the first version of the group check
created its fixture as root, so root:root came out either way and the
assertion compared nothing.  It chgrps to a real non-root group first now.

## 1.14.260 -- two tables disagreeing, seventeen changes to the wrong answer

1.14.259 made the REQUEST path keep the group.  The output then read:

    /usr/bin/su is now 4755 root:p_shadow      <- request table
    ...
    /usr/bin/su is now 4755 root:root          <- "upstream" table, one line later
    Applied 17 change(s).

`cmd_setid` has TWO tables: the bits a build asked for and was refused, and
`_setid_known` -- what upstream installs, for packages whose request was
never recorded.  The second hard-coded `root` in its group column, so it
ran immediately after the first and undid it.  Nine files changed twice.

`-` in that column now means KEEP WHAT IS THERE, and the shadow rows use
it.  A file already at `4755 root:p_shadow` is recognised as correct and
skipped, so the two tables agree instead of fighting.

**A setGID entry keeps its NAMED group**, because there the group IS the
purpose: dbus-daemon-launch-helper must be group messagebus, fcrontab group
fcron.  That row is unchanged and asserted unchanged.

The general rule, now written in the table's own header: **for setuid, only
the owner matters and the group belongs to whoever installed the file; for
setgid, the group is the feature.**

## 1.14.261 -- the setid pass locked linux-pam out of its own file

    rm: cannot remove '/etc/pam.d/other': Permission denied
    /etc/pam.d -> already group nimgnu_bash-completion, and 'p_linux-pam' is a member
    # retrying linux-pam (phase install only -- the build is done), round 1 ...
    PermissionError: [Errno 1] Operation not permitted: '/usr/sbin/unix_chkpwd'

Round 1 was right and worked.  The second failure is one I created two
releases ago: **/usr/sbin is sticky**, so only a file's owner may unlink it
there.  linux-pam installs /usr/sbin/unix_chkpwd 4755, the post-install
setid pass chowns it to root -- which is exactly what a setuid bit needs --
and the next reinstall can no longer replace its own file.  EPERM, not
EACCES, which is why no permission repair recognised it.

Three parts to the fix, all in `_take_cmake_dest`:

  * **meson's wording**: `Operation not permitted: '<path>'` extracts the
    path.  cmake says `cannot copy file "A" to "B"`; python says this.
  * **the GATE learned it too** -- it only accepted cmake's phrasing, so the
    function returned before looking.  The same two-places-one-fact shape as
    1.14.222.
  * **root's files are still off limits, with one exception**: a path the
    package's OWN manifest claims.  That is the file it installed and we
    then gave to root; handing it back for the install is safe, and the
    setid pass re-applies the bit afterwards -- so the loop closes instead
    of alternating.  A root-owned file no manifest claims is left alone,
    which the suite checks with two files and one manifest.

The lesson is about the shape, not the file: **a repair that changes
ownership creates work for the next install of the same package.**  The
setid pass and this take-back are two halves of one cycle, and either alone
is a bug.

## 1.14.320 -- the stacks, reorganised: wayland / sway / apps

Asked to recheck every stack for naming and fit, and to take sway and its
tooling out of the Wayland base.  sway.stack was 477 lines answering four
questions at once.  Now:

    wayland.stack   kernel check, dbus/elogind, the audio floor (alsa-lib,
                    ffmpeg), llvm/glvnd/mesa, wayland, GTK4 + libsoup3, git,
                    seatd, libdisplay-info, wlroots.  Nothing sway-specific.
    media.stack     unchanged (codecs, gstreamer, WebRTC, webkitgtk, mpv,
                    yt-dlp).
    sway.stack      `include wayland`, `include media`, then the audio
                    server (after media, so pipewire finds gstreamer), SDL3,
                    scdoc, sway, swaybg, grim/slurp/swayidle, wl-clipboard,
                    wf-recorder, light, foot (+tllist, fcft), fonts, and the
                    user's own programs (minibrowser, swbr, swov, swas) and
                    sway-session.  `stack sway --run` is still the whole
                    desktop.
    apps.stack      poppler, girara, xxhash, zathura, zathura-pdf-poppler,
                    imv -- programs, not the desktop.
    tools.stack     translate-shell, and jq (moved from sway.stack).

Every entry was carried over by slicing the file at its comment markers, so
the comments travel with their entries; a script compared the entry lists
before and after (none lost, none doubled).  One order change, on purpose:
`book git` now comes before media.stack's git entries (libnice, libsrtp,
...) instead of after them.

On a built machine nothing is rebuilt: `stack sway`'s progress file is keyed
by the stack you run, so its cached entries stay cached; `stack apps` and
`stack tools` have no progress file yet and re-judge their entries, which
are installed and skipped.

Tests: every check that looked for an ENTRY in sway.stack now reads all five
desktop files in build order ($_DESKTOP_STACK, built in the preamble); a new
block checks the includes, the placement of key entries, and that no entry
is written in two stacks.  The expect= "thin probe" heuristic now accepts
`pkg-config --exists` (it flagged librice and xxhash once it saw them).
Full suite: the same failures as before the split, minus two.

Reviewed and left alone: network (fits), services (see NEXT-TASK -- its name
undersells it), dev, diag, vision, avoid.

## 1.14.319 -- tools.stack, with translate-shell

A new stack for "the small programs you type": nothing boots with them and
nothing depends on them, so none of the other stacks is the right answer.
First entry: translate-shell (`trans`) v0.9.7.1, the newest tag.  Built and
installed here with the entry's own two commands (`make` is gawk writing one
script; `make PREFIX=/usr install` copies it and the man page).  needs=curl:
it fetches with curl and returns nothing without it.  expect= only tests the
file -- `trans -V` went to the network and hung in the sandbox.

## 1.14.318 -- scdoc

grim stopped on `Program 'scdoc' not found`.  1.14.316 asked grim, slurp
and swayidle for man pages on the assumption that scdoc was present because
sway's own line asks for them -- it was not on the machine.  scdoc 1.11.5
(SLFS's version, from git.sr.ht) is now a git entry in sway.stack, before
sway, so a replay meets it in order.  Not built here: sr.ht is not reachable
from this sandbox and no mirror carries the tag.

## 1.14.317 -- needs= by the package's name, not only the book's anchor

grim's `needs=libjpeg-turbo` stopped the stack: the book files
libjpeg-turbo-3.2.0 under the anchor `libjpeg`, so the name found no page
and the stack tried to INSTALL a package that was installed.  The stack
now says `libjpeg`, and `_resolve_need` maps a name that is not an anchor
but matches exactly one page's own package name (version string minus the
version) to that page -- and says so.  Ambiguous or unknown names are used
as given and fail as before.

## 1.14.316 -- grim, slurp, swayidle

Three git entries in sway.stack after swaybg, refs checked: grim v1.5.0 from
gitlab.freedesktop.org (the SLFS page's source; the GitHub mirror stopped at
v1.4.0 in 2022), slurp v1.5.0 and swayidle v1.9.0 from GitHub.  Options
asked for rather than autodetected: grim jpeg + man pages, slurp man pages.
swayidle is built -Dlogind=disabled: sway takes its seat from seatd-<user>,
so there is no logind session for that half to talk to; the timeouts work
without it.

## 1.14.315 -- the shared DATA lives in /home/Shared, and app homes are 0700

1.14.312 moved only the LINKS to a hub; the data stayed in
<account home>/Shared.  Reaching it went through the account's home, which
therefore had to be group-readable (0750) -- and the main user is in every
account's group, so it could read each account's browser profile and
cookies.  Pointed out from the machine, with the fix: put the real
directory in /home/Shared and link from the home.

  * /home/Shared/<Name> is the directory (2770 u_<name>:u_<name>); the
    hub is root:<main> 0775.  `shared_hub=` still moves it.
  * The account's own ~/Shared is a link to it, so `--download-dir
    ~/Shared` in app-users.conf means the same thing.  The main user's
    ~/Shared links to /home/Shared.
  * Application homes are 0700 now.
  * Data is never moved by the tools: a ~/Shared with files in it is left,
    and the one-line mv is printed.  The machine was migrated by hand, with
    commands given in the conversation, as asked.
  * `user delete`: the account's hub directory is removed when empty and
    kept (with a note) when not -- it is no longer inside the archived home.
  * 1.14.312's argument against /home ("a directory there looks like a
    home") was about a hub of links; a hub holding the one shared thing is
    what lets every home be private, which outweighs it.

## 1.14.314 -- `book hatchling` was not "make sure it is there"

1.14.312 put `book hatchling` in front of yt-dlp, as its build backend.  On
the machine hatchling 1.28.0 was already installed, and the entry still
planned a chain from the book -- vcs_versioning first, which stopped on
`packaging>=26.2` (installed: older) -- so the stack ended at "0 of 2 done"
and yt-dlp never started.  A dependency that every python build on the
machine already needed is not a stack entry; if it is ever missing the
build says `BackendUnavailable: Cannot import 'hatchling.build'`, which
lfs-helper already maps to its page.  Removed.

Not fixed here, noted: a plan that includes a package whose INSTALLED
dependency is too old (vcs_versioning wants packaging >= 26.2) does not put
that dependency's update in front of it.

## 1.14.313 -- the machine's own files, adopted

The machine sent its current app-users.conf, machine.conf, sway-session.sh
and install_mytools.  The last two were identical to what ships.  The first
two differed only by what the machine had added -- a `git` and a `discord`
account, and `USE_GTK4 = ON` under [webkitgtk] -- so those are now in the
shipped copies, byte for byte.  Why it matters: `make install` updates a
stack file only while the installed copy matches the last one it shipped;
an edited file is kept and the new one parked as `.new`.  With the two
identical, the next install records them as ours again and later fixes
arrive without a manual merge.

Also: block 121 had failed since 1.14.307 -- its checks still looked for
the "left alone" wording that release replaced with a real answer (branch
moved? newer tag?).  They check the new wording now.

## 1.14.312 -- the shared hub is a system path; yt-dlp

**The hub.**  The links to every shared directory lived in the main user's
~/Shared.  Asked to move them "where a package could reach them too", maybe
/home/Shared.  They are now in ONE hub, `/home/shared_user/Shared` by
default -- beside the u_* homes they point into -- and ~/Shared is a link to
it, so nothing typed changes.  `packagemanager config --shared-hub DIR`
moves it.  Not /home/Shared: /home holds homes, and a directory there that
is not one looks like an account to anything that lists /home.

  * root owns the hub, your login's group may add a link by hand (0775).
  * The move takes only links; a file of yours in ~/Shared keeps it a
    directory, and says so.  Re-running is a no-op.
  * The SHARED_* variables come from the hub, so every account sees the
    same set.  Before, each login enumerated its OWN $HOME/Shared -- and in
    an app account that is its data directory, so u_claude got one SHARED_*
    variable per FILE it had downloaded.
  * PKGUSR_SYS_SHARED names the hub.  app-users.sh asks the tool for it
    rather than reading that variable, which the running shell inherited
    from before the move.
  * cfg app-users' expect= now fails while ~/Shared is still a real
    directory, so the step re-runs once on this machine and does the move.

What the hub does NOT change: who may open a directory.  Each is still 2770
u_<name>:u_<name>, and a program runs as whoever STARTS it, never as the
package user that owns its file -- so your own programs already reach
everything your login can.  Only a daemon running under its own account
needs a membership, and that is `usermod -aG u_<name> <account>`, or a
collector group (`sysgroup create` / `make-group-dir` / `sysgroup add`) for
a directory several accounts share.

**yt-dlp** in media.stack, from upstream's release tarball (not a BLFS
page).  The release asset, not the git tree: the wheel's shared-data names
the man page, README.txt and the completions, which are generated at release
time, and hatchling stops on the first one missing.  Built here with the
book's wheel recipe; `yt-dlp --version` answers 2026.08.19.  Pinned, with
the two lines to change when YouTube breaks it.  (A `book hatchling` line
before it was removed again in 1.14.314.)

## 1.14.311 -- --clean deleted current files, and its repair had not run since 1.14.16

    packagemanager update webkitgtk --run --clean      # all green
    jsc/jsc.h:29:10: fatal error: jsc/JSCOptions.h: No such file or directory

`packagemanager script install webkitgtk` fixed it, which was the clue: the
files were missing, not wrong.

  * --clean calls a file an orphan when it is in the old pkg.lst and older
    than the install.  **"Older" is not "no longer installed":** CMake's
    install skips a file whose content has not changed ("-- Up-to-date:"),
    so webkitgtk's unchanged jsc headers kept their old date.  meson and
    `install -p` do the same with timestamps.
  * The code knew -- it re-ran the install step afterwards "to restore
    current files".  That step ran `bash ~/install_<account>`, the copy
    1.14.16 stopped writing, with stdout and stderr sent to /dev/null and
    the exit status ignored.  It failed on `No such file or directory` for
    every --clean since, where nobody could see it.

Now nothing is deleted on the mtime test's word alone.  Candidates are
renamed aside in place (`<file>.pkgusr-clean`, one rename, nothing copied),
the install step runs through the same door as `script install`
(`lfs-helper build --phase install`, logged, exit checked), and then: what
it put back is current and kept; what it did not is removed; **if it fails,
every file is put back and the clean is reported as not done.**  A ledger
survives an interruption and is undone at the next clean.

Tested: an unchanged "header" the reinstall re-creates is kept, a real
orphan goes, no `.pkgusr-clean` litter; a failing reinstall puts both back
untouched and leaves no ledger; and the reapply is checked to log, to return
its status, and to use the versioned script.

## 1.14.310 -- who INSTALLED it, not who holds it

Reported from the machine a THIRD time, and this time with the evidence that
finally named the mechanism:

    find /usr/sbin -user p_webkitgtk
    /usr/sbin/iptables -> xtables-nft-multi        (six links, Sep 12 12:56)
    grep iptables /usr/src/pkgusr/p_webkitgtk/pkg.lst
    /usr/sbin/iptables
    /usr/sbin/iptables-restore
    /usr/sbin/iptables-save

Those links were made by `cfg iptables-nft` on a different day.  1.14.308
guarded the ownership sweep and the damage came back anyway, because the
sweep was not the one doing it.  **The lease was.**

  * A build manifest is built BY TIME WINDOW: everything newer than the
    build stamp.  A webkitgtk build runs for hours, so whatever root wrote
    in those hours -- `cfg shadow-pam` touching /usr/bin/su, `cfg
    iptables-nft` making six links -- landed in `webkitgtk.files`.
  * Before an install phase, `lease_files` reads that manifest and hands
    the package everything in it that someone else owns.  Its guard for
    root's files had two doors, and **"the file carries a setid bit" was
    one of them, with no lock on it**: any package whose manifest named
    /usr/bin/su was given it.  `chown` then cleared the setuid bit, which
    is why the file came back as `p_webkitgtk 0711` every time.  The user
    was mid-rebuild each time they looked: the lease is held for the whole
    phase.
  * `lease_settle` decides whether the package keeps a leased file by
    `cmp`.  **For a symlink that test can never say "unchanged":** `cp -a`
    copies a relative link as a relative link, so the copy in the lease
    directory dangles, `cmp` cannot open it, and the failed compare reads
    as "the phase rewrote it".  Every leased symlink was kept.  That is the
    six iptables links, and pkg.lst then recorded them because pkg.lst is
    an owner scan.
  * And it was self-sustaining.  The manifest fed the lease, the lease made
    the package the owner, and the manifest filter -- which asks who owns
    the file NOW -- saw the owner's own file and kept it.  So the same
    damage repeated on every rebuild.

So both answers to the question asked ("did we do something wrong with the
pkg list, or is there an error in the scripts?") are yes, and they are the
same fault: **nothing anywhere asked who INSTALLS a file, only who holds it,
and that was the thing that had gone wrong.**  Two facts that do not depend
on current ownership now decide it:

  * `setid.conf` gained a 5th column, the package that installs the file
    (`/usr/bin/su | 4711 | root | - | shadow`).  shadow may reclaim its own
    su; nobody else may borrow it, and a line with no package is leased to
    nobody.  The old three-column readers are unaffected -- the group is
    still field 4.
  * **A symlink belongs to whoever owns its target.**  Applied in
    `lease_settle` (compared with `readlink`, as `lease_restore` already
    did), in the ownership sweep, and in the manifest filter.

### Repairing a machine that already went through those doors

    packagemanager disown --all            # what it would hand back
    packagemanager disown --all --run      # hand it back
    lfs-helper setid --run                 # put the setuid bits back

`disown` is `reclaim` in the other direction: `reclaim` pushes ownership
towards pkg.lst, which is right when a package lost files and wrong when the
RECORD is what went bad.  It hands back only what the two rules above prove
is not the package's, restores the mode from setid.conf (the chown that took
the file cleared it), and strikes the paths from pkg.lst **and** from the
build manifest -- because leaving them in pkg.lst means `update webkitgtk
--clean` would delete the iptables links, and leaving them in the manifest
re-arms the lease on the next build.

Tested: the lease fixture gained a setuid file setid.conf gives to another
package (not leased), one with no package column (not leased), a relative
symlink the phase did not touch (given back) and one it repointed (kept);
the manifest filter dropping both kinds; and `disown` end to end on real
files and real accounts -- dry run changes nothing, the setuid file goes
back to root at 4711, the link goes to the owner of its target, the
package's own file is left alone, and both records come out clean.

## 1.14.309 -- turning the machine off is a membership, and nothing re-checked it

Asked what a good way is for the desktop user to poweroff and reboot, and at
which step.  The answer was already built -- `cfg power` in services.stack --
and it had the same weakness as everything else that sets a mode:

  * halt, poweroff and reboot become 4550 root:<collector>_power.  Setuid root
    so they can do the job, executable only by the group so not everyone may:
    the privilege is a MEMBERSHIP, which is the same shape as seatd-<user> and
    su_u_user.  The desktop user is added to that group; a package user owns
    files, never identity.
  * /sys/power/state and /sys/power/disk are made fresh at every boot, so the
    step also writes /etc/rc.d/init.d/power-perms and links it into rcS.d.
    udev cannot do this: a sysfs attribute has no uevent, so no rule ever
    fires for it.
  * **The entry had no `expect=`.**  Once cached it was never looked at again
    -- and these are exactly the modes that vanish quietly: a sysvinit rebuild
    reinstalls halt without the setuid bit, and a chown clears it as a side
    effect the kernel never reports (1.14.308, on su).  It now re-checks the
    group, `4550 root:<group>` on halt, and the boot script, on every run.
  * setid.conf says why those three are NOT in it: the group's name is
    configured, so a `| root | -` line would keep whatever group the file
    happens to carry -- p_sysvinit on a machine where `cfg power` never ran,
    which would hand shutdown to whoever builds sysvinit.  One place knows the
    group, and it is the step.

Answering the question directly: the step is `cfg power`, it belongs in
services.stack after the desktop user exists and after /etc/rc.d/init.d does,
and it is already there.  Running it again is free:

    packagemanager stack services --only power --run

Tested: the expect= read back out of the stack file and checked as valid shell,
and asserted to test the mode, the owner and the boot script; power.sh still
setting 4550 and still re-applying /sys/power/state at boot.

## 1.14.308 -- chown destroys a setuid bit, and su was root's

    ls -ald /bin/su
    -rwx--x--x 1 p_webkitgtk p_webkitgtk 169952 Sep 15 12:43 /bin/su

Reported from the machine, for the SECOND time.  One command explains both
halves: the kernel clears setuid and setgid on chown, so a single
`chown p_webkitgtk /usr/bin/su` changes the owner AND removes the bit that
makes su work.  Nothing warns, and nothing in the file says what it used to
be.

How the sweep reached su at all: ownership is attributed BY TIME WINDOW --
every file newer than the build stamp -- and a webkitgtk build runs for hours.
Anything that touched su in that window (`lfs-helper setid`, a shadow
reinstall, `cfg shadow-pam`) made it newer than the stamp.  It is root-owned,
and the loop's own comment says "files owned by root are fair game (the
temporary system's)".  For /usr/src that is true.  For /usr/bin/su it is the
opposite of true.

Two defects, one symptom:

  * **The root-owned rule was applied in one of the two places that needed
    it.**  The manifest already drops root-owned paths when the phase ran AS
    the package user -- a package user cannot have written a root-owned file,
    so whatever is root's now was not its doing.  The chown loop walked the
    RAW lists again and took exactly the files the manifest had refused.
  * **A setuid or setgid file is never the sweep's to take**, whoever ran the
    phase and whatever the time window says.  Those modes are the system's,
    declared in setid.conf, and a chown silently destroys them.  The sweep now
    skips any file with a mode of the form [1-7][0-7][0-7][0-7] and says so.

Also, because it turned every update into a keypress: `pm-install` asked
"check that p_imv is the right account" on every run.  That is a FIRST-INSTALL
question -- a typo in the account name scatters a package across the wrong
home -- and it is worth nothing on an update, where the account exists and
already owns the package's files.  It is now asked only when there is no
pkg.lst and no .pkgusr-installed for that account.  A prompt people press
through has stopped protecting anything.

ON THE MACHINE: `packagemanager stack services --only shadow-pam --run` is the
repair -- its expect= is exactly `test -u /usr/bin/su && stat -c %U = root`,
which is why it can see the damage.  By hand it is
`chown root:root /usr/bin/su && chmod 4711 /usr/bin/su`.  Worth a look for
others:  `find / -xdev -perm /6000 ! -user root -ls`.

Tested: the mode test against 4711, 2755, 6755 (skipped) and 0711, 0755
(taken); both guards asserted in the source; setid.conf still declaring su as
4711 root; and the prompt's decision against an installed package (silent), an
account with nothing recorded (asks) and no account at all (asks).

## 1.14.307 -- "updating from its repo" for a package with nothing to update to

    packagemanager update imv
    imv: git package -- updating from its repo.
    Dry run -- to proceed, re-run with --run

Everything there is correct -- `--run` is the missing word, as with every
command here that changes the system -- and it still does not answer the
question the person is asking, which is "will this get me anything?".  imv is
pinned to v4.3.0 and v4.3.0 is the newest tag exec64/imv has: the rebuild
produces the commit that is already installed.  The command works, does
exactly what it says, and changes nothing.

`update <git-pkg>` now says which of the three it is, before the dry-run line:

    imv: pinned to tag v4.3.0, which is the newest released -- this rebuilds
         the same commit
    zz:  pinned to tag v4.1.0; v4.3.0 is out
         a rebuild stays on v4.1.0.  To move it:
           packagemanager git-ref zz v4.3.0 --run
    sway: master moved 4e2a1b3 -> 9c7f0aa (12 commit(s)) -- this brings it in

`--no-git-check` skips the remote when there is no network.

Tested against the real exec64/imv (newest tag -> "rebuilds the same commit")
and a copy pinned to v4.1.0 (-> names v4.3.0 and the command to take it).

## 1.14.306 -- "phased" means it ends in the runner

    packagemanager update imv
    imv: git script isn't phased -- it won't fetch/rebuild cleanly.
    Regenerate it with:  packagemanager template imv --git <repo-url>

The script was perfectly current -- format v17, build_pkg, install_pkg, and
`. "${PKGUSR_LIB:-lfs-phases}" && pkgusr_run "$@"` at the end.  The test asked
whether it defines `unpack_pkg`, which is the RARE OVERRIDE that replaces the
built-in unpack entirely.  A correct script does not define it: the runner's
own unpack is what clones git.  So every properly phased git package was told
its script was broken.

The advice was worse than the warning.  `template --git` rewrites the file,
and imv's build_pkg carries `-D c_link_args=-licuuc` -- a fix found once and
not written down anywhere else.  Following the suggestion would have deleted
it and the next build would have failed at link time for a reason nobody
would connect to this message.

  * `_is_phased_script()` asks what actually matters: does it END IN THE
    RUNNER (`pkgusr_run`, PKGUSR_LIB/lfs-phases, or the `### phases:` header)?
    That is the thing that makes fetch, resume and single-phase re-runs work.
  * When a script really is unphased, the message now says what a phased one
    looks like, and warns that `template` does not keep the build commands --
    write it to a new file and move them across.

Tested: the machine's own imv script (recognised as phased), an old-style
script that clones inline (not phased), and the whole path end to end against
the REAL repository -- `git-status` on imv reports "tag, nothing newer
released", which is true: v4.3.0 is the newest tag exec64/imv has.

## 1.14.305 -- a branch is not a point in time

Asked whether `update` could follow a git package that tracks master, and
show the releases for one pinned to a tag.  The first half was not a missing
feature, it was a bug:

  * **`git checkout master` does not move the branch.**  The unpack phase
    fetches (`git fetch --all --tags --prune`) and then checks the ref out --
    and on an existing clone git answers "Already on 'master'" and stays
    exactly where it was.  So a package pinned to a branch fetched the new
    commits, rebuilt the OLD ones, installed them and reported success, for
    ever.  It now asks the repository what kind of ref it has: a remote
    branch is taken with `checkout -B <ref> origin/<ref>` and says what moved
    (`master: b21bd64 -> 6429c4b (3 new commit(s))`); a tag or a commit is
    checked out DETACHED, because that is what it is and it must not move;
    with no ref at all it follows origin's own default branch.
  * **`packagemanager git-status [pkg]`** -- for each git package: the ref,
    what kind it is *according to the remote* (guessing from the string is
    how a tag called `main` goes wrong), the local and remote commits, how
    far behind, and for a tag-pinned package every newer tag.  `--local-only`
    skips the network.
  * **`packagemanager git-ref <pkg> [<ref>]`** -- with no ref it lists the
    remote's branches and tags with the current one marked; with one it
    rewrites `git_ref=` in the install script (backup kept, dry run unless
    `--run`), refuses a ref the remote does not have, and NAMES THE STACK
    FILE that also carries it -- editing only the script is undone by the
    next stack run.
  * `update`'s "N packages follow GIT -- left alone" now answers the question
    instead of restating it: which are behind their branch (with the command
    to rebuild), which are pinned to a tag that has been superseded (with the
    command to move), and `--no-git-check` for no network.

Tested against two real repositories built in the fixture: one package
following a branch that gained a commit (reported as moved, old -> new sha),
one pinned to 2.0.0 with 2.1.0/2.2.0/2.3.0 released (all three offered,
newest suggested); `git-ref` listing, dry-run rewrite, and a refusal for a
ref the remote does not have (rc 1).  The branch bug itself is reproduced in
the suite: plain `checkout` leaves the clone where it was, `checkout -B`
moves it.

## 1.14.304 -- a library something still links against is not an orphan

From the machine: `pkg-config --modversion webkitgtk-6.0` said 2.50.5 while
the package said 2.52.5.  Not a failed install -- the dates tell the story:

    libwebkitgtk-6.0.so.4.13.8   Sep 13    the GTK4 port  (2.50.5)
    libwebkit2gtk-4.1.so.0.21.9  Sep 15    the GTK3 port  (2.52.5)

The rebuild switched PORTS.  The 6.0 files are old-version files this package
still owns and the new version never rewrote -- which is exactly what
`update --clean` deletes, and anything built against libwebkitgtk-6.0.so.4
would have broken on the spot, with no warning and no way back but a rebuild.

A package-user system records who INSTALLED every file and nothing about who
USES one.  `ldd` answers it for one file; nothing answered it for a library.

  * **`packagemanager used-by <package|soname|path>`** -- every ELF that
    records that soname in DT_NEEDED, grouped by the package user that owns
    it.  grep first (a soname is a literal string in .dynstr, so grep over
    /usr/lib is seconds), then readelf only on the hits, because the same
    string also appears in scripts, .la files and other libraries' rpaths.
    The SONAME is READ from the library (libwebkitgtk-6.0.so.4), not guessed
    from the file name (libwebkitgtk-6.0.so.4.13.8).
  * **`--clean` now asks that question before it deletes.**  A library still
    recorded by a file another package owns is KEPT, the packages are named,
    and the rebuild command is printed; the symlinks that point at it are kept
    with it, or the soname it is found by disappears anyway.  A library
    nothing links against is swept as before.  Files of the package being
    cleaned do not count -- they go with it.
  * `_needed_by`'s scan directories were a DEFAULT ARGUMENT, bound at import
    and therefore impossible to override -- which is how the first test of it
    appeared to find nothing. Resolved at call time now.

Tested for real, not by grep: gcc builds a library with a soname and a
consumer that records it, the consumer is chowned to another account, and
`_orphan_sweep` is run twice -- with the consumer present (library KEPT, no
files removed) and with it gone (both files swept).  That fixture is now a
block in the suite, and skips itself where there is no gcc.

## 1.14.303 -- the suite could not run, so nothing it guards was guarded

Asked "anything that needs fixing?", so the suite was run instead of guessed
at.  It could not run at all, and had not been able to for some time.  Five
things, in the order they were found:

  * **`lfs` would not start on Python 3.11.**  One f-string reused its own
    quote character inside the braces (`f"...{f(lfs, "progress", ...)}"`),
    which is legal only from 3.12.  `lfs` is the ONE tool that runs on the
    HOST, where Python is whatever the distribution ships -- Debian 12 is
    3.11 -- so it did not misbehave there, it refused to start, with a
    SyntaxError pointing at a debug print.  It also took the whole suite with
    it: the preamble builds a real package through a generated script, so
    every block downstream failed.  That one line was 12 of the failures in
    the first block run.
  * **The cleanup trap ate the tally.**  `trap cleanup EXIT` is inherited by
    every subshell, and the suite runs blocks inside `( )` and `$( )`
    constantly; the first one to exit removed $T and the counter directory
    out from under the run.  Every later `ok()` printed a shell error instead
    of counting, and the final line read `PASS:   FAIL:   SKIP:  (final)` --
    a suite that reports nothing, which is worse than one that reports a
    wrong number.  `$$` is the same in a subshell, `$BASHPID` is not; the
    trap now returns unless it is the shell that set it.  Counters also moved
    to a name nothing globs for and are recreated on write.
  * **The launcher test had drifted from the launcher.**  It neutralised `su`
    with `sed '/^exec su - /'`, which assumed one ending; since 1.14.295 the
    `exec su` is indented inside an `if` and there is a second path through
    `script`, so the sed matched neither and the REAL su ran ("user u_a does
    not exist").  It now stubs `su` first in PATH, which tests whatever shape
    the launcher has, and asserts the two contracts that were added without
    tests: a pty when there is no terminal, and a `{url}` default page.
  * **Every stack file said 1.14.292 while the tools said 1.14.302.**  The
    suite asserts they match ("they ship as one artifact, so they carry one
    number") and had been unable to say so for ten releases.  Stamped -- and
    `make stamp` now does it from `lfs --version`, because a rule only a human
    remembers is a rule that drifts.
  * **avoid.stack carried debris from the split out of sway.stack**: a second
    `# stack-version:` line under a `# sway.stack -- a working Sway desktop`
    header halfway down the file, and two orphaned section markers ("# 9. the
    nimbin2 family", "# 10. wire the session together") with nothing after
    them.  All comments, all inert, all misleading to read.

After: **751 PASS / 80 FAIL / 1 SKIP**, with a final line that prints.  The 80
are this container, not the tools -- it is not a package-user system, so the
/usr/lib/pkgusr wrappers, the book and the chroot blocks have nothing to test
against.  `make check` on the machine is the number that counts.

STILL BROKEN, not fixed here: `--only` / `--from` generate a subset script
that can cut a here-document in half ("here-document at line 667 delimited by
end-of-file") and lose helpers a previous block defined (`detail: command not
found`).  The documented limitation is that a block may need what an earlier
one computed; a truncated here-doc is a bug in the extractor.  Until it is
fixed, a selection can report failures a full run does not.

## 1.14.302 -- dev.stack: gdb

Asked for plainly: "we need gdb in a stack".  None of the six fitted.  Every
stack here answers one question -- services = what starts at boot, network =
how the machine gets an address, sway = the desktop, diag = is the GPU doing
what I think, media = what plays, vision = computer vision -- and a debugger
is none of them.  Putting it in the nearest one is how a stack stops meaning
anything.

  * **stacks/dev.stack**: `book gdb expect="test -x /usr/bin/gdb"`, and the
    question it answers is "the program crashed and I want to know why".
    Nothing depends on it, so it is safe to build last and safe not to build
    at all -- the other reason it is not in a stack the desktop needs.
  * gdb's only "required" dependency in the book is the python module `six`,
    and that is for gdb's own scripting at runtime; the rest of the list
    (guile, doxygen, valgrind, rustc, SystemTap) is for gdb's test suite.
    The build line comes from the book page, so nothing is repeated in the
    stack.
  * The file says out loud that strace, ltrace and valgrind are the obvious
    neighbours and are NOT there: an entry in a stack is a package built on
    every replay of it, so they wait to be asked for.
  * BUILD.md runs it after services.

Tested: the file through _parse_stack_file -- `include avoid` pulls in all 78
exclusions and the one real entry parses as book/gdb with its probe.  NOT
tested: the build itself (this box has no BLFS book).

## 1.14.301 -- `packagemanager service`, and an exit code that was thrown away

Asked for after `cfg bootscripts` installed sshd: a way to see what services
there are and to start one without enabling it.  SysV has always kept those
two apart -- the init script starts it, the rc<N>.d links decide whether boot
does -- and nothing here made that easy to use.

    packagemanager service                      # all of them, at boot, running
    packagemanager service sshd start           # now, enabled or not
    packagemanager service sshd enable|disable  # boot only
    packagemanager service start sshd           # either order reads naturally

  * list: `at boot` (yes / other runlevel / no), `running` (asked of each
    script, LSB exit code), and which runlevels.  `functions`, `rc` and
    `template` are not services and are not listed -- listing them invites
    starting them.  `--quick` skips the running column.
  * start says "not enabled at boot -- starting it anyway" rather than
    refusing.  That was the point of the request.
  * **disable records the links it removed** in /var/lib/pkgusr/services, so
    enable restores exactly those.  The priority number (S30, S26) comes from
    the blfs-bootscripts Makefile and is the one thing that cannot be worked
    out again; with no record, the number comes from a surviving K link and
    the runlevels from the script's own `Default-Start:` header.  disable
    removes only the S links and says it has not stopped anything.
  * It also lists /lib/services/* separately -- run by ifup, never on their
    own, named by SERVICE= in ifconfig.<iface>.  Not saying so is how "dhcpcd
    is installed and nothing runs it" happens.
  * **main() threw away every command's return value**, so packagemanager
    exited 0 whatever happened -- including `service <name> status` on a
    stopped service, which is the one command people put in an `if`.  A
    non-zero int now becomes the exit status; anything else is unchanged.

Tested against a built fake /etc/rc.d (three scripts with INIT INFO headers,
one running, one not, one unlinked, plus a `functions` file): list; start on a
disabled service; enable from nothing (header runlevels, priority 50, seven
links); disable then enable (record written, K links untouched, links restored
identically); reversed word order; an unknown name; and the exit codes 0 / 3 /
1 / 0 for running, stopped, missing and list.  NOT tested: a real boot.

## 1.14.300 -- the build tree is one level deeper than the home

`cfg bootscripts` from 1.14.299 said

    !! no unpacked blfs-bootscripts tree under /usr/src

on a machine where it was right there.  lfs-phases builds in BUILD_ROOT,
which is `$HOME/src` whenever the package user has one, so the tree is
/usr/src/p_blfs-bootscripts/**src**/blfs-bootscripts-<date>.  The step looked
in the home and in the base, never a level deeper, and then told the reader to
unpack something that already existed -- the worst kind of error message, the
one that sends you to redo work that is done.

  * Four patterns now, newest wins: `<base>/*/src/`, `<base>/*/`, `<base>/`
    and the sources directory.  Then a `find` bounded at depth 4 for a layout
    nobody thought of.
  * **The tarball is enough.**  A build tree can be cleaned away and these
    targets only copy files, so with no tree at all the step unpacks
    blfs-bootscripts-*.tar.* from $LFS_SOURCES_DIR (/sources) into a
    temporary directory, installs from there, and removes it on exit (trap).
    It says that those files land owned by root rather than by the package
    user, because that is the one thing this path does differently.
  * When it really finds nothing it now prints WHERE IT LOOKED, so the next
    failure is diagnosable instead of another guess.

Tested: the real layout (<home>/src/blfs-bootscripts-*, found and installed
from), and the tarball fallback with the tree deleted (unpacked, installed,
temp directory gone afterwards).

## 1.14.299 -- a package and the thing that starts it come from different tarballs

"dhcpcd does not start at boot; did we forget its init script?"  There is no
init script to forget: BLFS ships no /etc/rc.d/init.d/dhcpcd at all.  The only
target is install-service-dhcpcd (/lib/services/dhcpcd), which services.stack
already installs, and that script is started by nothing on its own -- the LFS
`network` script reads /etc/sysconfig/ifconfig.<iface> at boot and hands each
interface to the service ITS file names.  With no such file the machine comes
up with dhcpcd installed, its service script in place, and no address.
`lfs config network dhcp` writes no interface files on purpose, and nothing
else wrote one either.

  * **stacks/bootscripts.conf** -- the services.stack install= list as a
    MAPPING: `package | proof | targets | creates`.  proof and creates take
    several comma-separated alternatives (a daemon that moved between /sbin
    and /usr/sbin is still installed; /lib/services and /usr/lib/services are
    the same service).
  * **cfg bootscripts** installs the targets whose package IS here and whose
    script is NOT, skipping packages that are absent (an init script for
    something uninstalled is a symlink in rc?.d that fails at boot), and then
    **checks the disk rather than make's exit status** -- a target that
    prints nothing and installs nothing is the failure that matters.  make
    runs as the tree's owner, so the files keep saying which package user
    installed them, with root as a fallback that says so.
  * The same step writes /etc/sysconfig/ifconfig.<iface> for a WIRED
    interface that has none: ONBOOT, IFACE, SERVICE=dhcpcd, DHCP_START/STOP.
    That file holds no secret, which is exactly why it can be written here --
    a wireless one needs an SSID and a key, so those are still left to
    `check net-wifi`, which prints the file to paste.
  * The entry carries `expect=`, re-checked when cached, so a package
    installed later is noticed on the next run instead of on the next boot.

Tested: a fake bootscripts tree with three targets, one package installed,
one absent and one target that lies (prints success, installs nothing) -- the
absent package skipped, the two real ones installed, the liar caught by the
after-check and the step exiting 1; a second run changing nothing; the
interface file written for eth0, wlan0 left to net-wifi, and an existing file
naming another service left alone.  NOT tested: a real blfs-bootscripts
Makefile, and a boot.

## 1.14.298 -- we wrote the file that unsets the locale

The i18n.sh on the machine was not BLFS's.  It was OURS --
`lfs-helper install_shell_startup_files`, which wrote:

    # Locale.  Set LANG here (e.g. en_US.UTF-8); an unset LANG means the C
    # locale, which is a choice, not an accident.
    if [ -z "${LANG:-}" ] && command -v locale >/dev/null 2>&1; then
        : # export LANG=en_US.UTF-8
    fi

The export is commented out, and the comment argues that this is deliberate.
It is not a choice anyone makes: nothing else on the system sets LANG either,
so every machine built with these tools sits in the C locale until a terminal
complains, and the only repair is to hand-edit a generated file.  The three
previous releases chased this through /etc/profile and BLFS's own placeholder
without ever looking at who wrote the file.

  * lfs-helper writes an i18n.sh that reads /etc/locale.conf -- the file LFS
    uses and the one `cfg shell-env` now writes from `lfs config locale`.  It
    carries `# written by lfs-helper`, and with no locale.conf it does
    nothing, exactly as before.  `_write_if_absent` still keeps an existing
    file, so this only helps new systems.
  * shell-env.sh therefore recognises all THREE writers of that file as ours
    to replace when it produces no LANG: its own marker, `# written by
    lfs-helper`, the book's `Begin /etc/profile.d/i18n.sh`, and -- for
    machines already built -- the commented-out line `: # export LANG=`
    itself.  A file nobody here wrote is still left alone and reported.
  * The replacement keeps `LESSCHARSET=utf-8`, which lfs-helper's version set
    and less(1) reads instead of the locale.

Tested: shell-env against a byte-for-byte copy of the machine's i18n.sh
(recognised, backed up, replaced, LESSCHARSET kept, LANG then set from the
locale.conf it had just written), and lfs-helper's new fragment sourced in an
empty environment with a locale.conf present (LANG set, rc 0) and absent
(nothing, rc 0).

## 1.14.297 -- i18n.sh was already there, and /etc/profile.d belongs to nobody

1.14.296 would not have fixed the machine it was written for.  `ls
/etc/profile.d` showed i18n.sh already present (root, Sep 4, from the BLFS
page) -- so "exists and is not ours, left alone" would have been the whole of
it, and $LANG would still have been empty.  The file was never the problem:
it does `. /etc/locale.conf`, and /etc/locale.conf did not exist.

  * **i18n.sh is judged by what it produces, not by who wrote it.**  It is
    sourced in an empty environment (TERM=xterm, because both the LFS and
    BLFS versions hard-code C.UTF-8 when TERM=linux) and the LANG that comes
    out is compared with the one this machine should have.  Right -> left
    alone, whoever wrote it.  Wrong, and it carries the book's header ->
    backed up and replaced.  Wrong and hand-written -> left alone and
    reported.  locale.conf is written FIRST, so the book's own file usually
    starts working and is never touched.
  * **Root writes it, root owns it.**  /etc/profile.d/pkgusr-system.sh was
    owned by p_gstreamer10: `env --system` opens the existing file for
    writing, which keeps its owner, and it was first created inside a build
    window.  A package owning a file no package installed is wrong on a
    package-user system, and every login shell sources that directory --
    whoever may write there runs code as everyone who logs in.  `env
    --system`, shell-env.sh (dircolors, bashrc, locale.conf, i18n.sh) and
    app-users.sh (shared-dirs.sh, xdg-runtime-share.sh, /usr/bin/xdg-runtime-share)
    now re-assert root:root on every run, as the PAM file already did.
  * **/etc/profile.d joins SHARED_DIR_PATTERNS.**  rust, bash-completion,
    gettext and the book's own config pages each drop ONE file in it, so the
    first package to create it owned it -- p_libnice here -- and every later
    package had to be granted it by hand.
  * Permissions there are right as they are: /etc/profile SOURCES these
    files (`. $script`), it does not execute them, so 644 is correct and +x
    would mean nothing.  Contrast /etc/pam.d/su_u_user, which pam_exec really
    does run and which app-users forces to 755.

Tested: the locale block against a stock BLFS i18n.sh with no locale.conf
(writes locale.conf, leaves the script alone -- the machine's own case), an
i18n.sh that yields nothing with locale.conf present (backed up, replaced),
and a hand-written one (left alone, reported); is_shared_dir on
/etc/profile.d with and without a trailing slash.  NOT tested: the chowns on
a system where the files are really owned by a package user.

## 1.14.296 -- nobody set $LANG

    warning: foot: 'C' is not a UTF-8 locale, falling back to 'C.UTF-8'

Nothing was built wrong.  LFS's own /etc/profile reads /etc/locale.conf, but
BLFS's "The Bash Shell Startup Files" page REPLACES /etc/profile with one that
reads /etc/profile.d/*.sh instead -- and i18n.sh, the piece of that page which
exports LANG, is a separate block, easy to walk past.  Take that page (this
machine did: its /etc/bashrc is the BLFS one) and the locale quietly falls back
to C.  `lfs config locale` was set, and nothing after the chroot ever read it.

  * shell-env.sh -- the step that exists because that page is config and no
    package stack runs it -- now also does the locale, and writes BOTH files,
    so it works whichever /etc/profile is installed: /etc/locale.conf
    (`LANG=`) and /etc/profile.d/i18n.sh (sources it, exports LANG, and
    LC_ALL when set).
  * The locale is taken, in order, from $LFS_LOCALE, /etc/locale.conf,
    `locale` in /usr/share/lfs/config.json (what `lfs config locale` wrote),
    then en_US.UTF-8, then C.UTF-8 -- and only if `locale -a` really has it.
    **A name is not a locale until glibc has built it**: locale.conf may name
    one nobody generated, which looks exactly like setting nothing.  That is
    reported with the localedef line to fix it, as glibc's package user --
    the locale archive is glibc's, and root would leave root's files in it.
  * An existing /etc/locale.conf is never rewritten; a hand-written i18n.sh
    is left alone.  A non-UTF-8 choice is reported, not overridden.
  * services.stack gives `cfg shell-env` an `expect=` -- /etc/bashrc,
    /etc/locale.conf and i18n.sh.  Without it a machine that ran this step
    before the locale was part of it stays `done (stack cache)` for ever and
    the terminal keeps complaining with nothing to say why.

Tested: the locale block with a de_DE.UTF-8 asked for and not installed (it
says so, names the localedef line, falls back), run twice (second run changes
nothing), the generated i18n.sh sourced in a shell with LANG unset (sets it,
returns 0), and a hand-written i18n.sh left alone; the expect= expression run
as the stack runs it.  NOT tested: a real login, and a machine that has
de_DE.UTF-8.

## 1.14.295 -- a menu entry has no terminal, and su wants one

Three from the machine after 1.14.294: the .desktop entries did nothing, the
/etc/bashrc hook refused to apply, and /root filled with tarballs of homes
that held nothing.

  * **The launcher now allocates a pty when there is no tty.**  Run from a
    terminal, `~/bin/reddit` worked; clicked in the menu it did nothing --
    `su` fails without a terminal and its message goes to a stderr nobody
    reads.  The old hand-made entry worked around it with
    `Exec=script -c 'reddit' /dev/null`, which is the same fix in the wrong
    place: every entry had to remember it.  The launcher now branches on
    `[ -t 0 ] && [ -t 1 ]` -- `exec su` as before with a terminal, otherwise
    `script -qec "$(printf '%q ' su ...)" /dev/null`, which gives su a pty,
    sends the typescript to /dev/null and returns the program's own exit
    status.  A non-zero status with no terminal to print to is passed to
    `notify-send` when it exists.
  * **Menu entries get `Categories=`** -- Network;WebBrowser; for the
    browsers, AudioVideo;Video;Player; for mpv, Utility; otherwise.  Without
    one an entry is "Other" at best and invisible at worst.
  * **/etc/bashrc is recognised by `# Begin /etc/bashrc`**, its first line in
    both the BLFS file and the one shell-env.sh writes.  1.14.294 looked only
    for shell-env.sh's own line, so a machine carrying the BLFS file got the
    line printed and the variables stayed unreachable from a terminal.  One
    line is appended, after a backup, starting with a newline -- the file on
    this machine ends `# End /etc/bashrcCK=$(tput setaf 0)`, which is what an
    append without one leaves behind.
  * **No archive for a home that was never used.**  The tarball exists for a
    browser profile -- logins, cookies, history, downloads, which
    `userdel -r` would take with it.  A home holding only the .bash_profile
    symlink these tools made and an empty Shared has none of that, so
    `_home_is_untouched` skips it: a purge of fourteen fresh accounts now
    leaves nothing in /root.  When archives ARE kept, purge ends by saying
    how many, how to look inside one and how to drop them.

Tested: the launcher with and without a terminal, su replaced by a printer
that reports whether it got a tty (no tty -> wrapped in script, su sees a
tty; tty -> exec su direct), arguments and the default page surviving the
extra quoting, and a failing su's exit status coming back out; the archive
skip against an untouched home and one with a .mozilla in it, dry and real;
the bashrc hook against a BLFS-style file, twice (appends once, backs up
once).  NOT tested: a real su from a real menu.

## 1.14.294 -- the variables were right and invisible; simpleicons dropped OpenAI

From the machine after 1.14.293 ran clean: `~/Shared` held the ten new links,
`shared-dirs.sh` was correct, and `$SHARED_<TAB>` still offered only
BROWSER_BIG, BROWSER_MINI, CLAUDE -- the three from the login BEFORE the
change.

  * **/etc/profile.d is read by LOGIN shells.**  A terminal opened inside
    sway is not one: it reads ~/.bashrc and shows whatever the session
    inherited at login.  The step now also sources the fragment from
    /etc/bashrc -- the file every interactive shell reads, and the one
    shell-env.sh writes, recognised by its `Based on the BLFS "Bash Shell
    Startup Files" page` line.  Anything else is left alone with the line
    printed.  `APP_USERS_BASHRC` overrides the path for testing.
  * **The fragment now takes variables away too.**  An account removed after
    login left `SHARED_X` in the environment pointing at nothing, inherited
    by every shell the session started -- so a correct removal looked like it
    had failed.  It drops every `SHARED_*` whose directory is gone (`env` +
    sed + `eval`, POSIX, tested under dash) before exporting what is there,
    and is safe to source again at any time: `. /etc/profile.d/shared-dirs.sh`
    refreshes a running shell.
  * **simpleicons.org has dropped `openai` and `grok`** (confirmed: both 404
    in the upstream repo, `claude` still there).  That is why chatgpt, nrwgpt
    and grok got no icon.  Those three lines now carry Wikimedia URLs in the
    stable `Special:FilePath/<File.svg>` form.
  * **`#RRGGBB` at the end of the icon field** paints a one-colour SVG after
    it is fetched (`_recolor_svg`): fills in attributes and in `style=`,
    `fill="none"` left alone, a root `fill` added when there is none.  It
    replaces simpleicons' `/slug/colour` service, which cannot help for a
    brand it no longer carries -- nrwgpt is the ChatGPT mark in sky blue.
    The `.from` stamp records URL+colour, so changing only the colour
    refetches.
  * A launcher that is not ours is still left alone, but now says
    `rm <path> and run this again` -- launchers from an older version are not
    recognised either, so "left alone" had quietly kept the OLD behaviour (no
    default page, no --app-id) on chatgpt, nrwgpt, grok, mercury, deepseek
    and youtube.

Tested: the fragment under bash and dash with a dead variable, a moved one
and a dangling link (dead dropped, moved corrected, dangling skipped); the
/etc/bashrc hook against a shell-env.sh file and a foreign one; `_recolor_svg`
on a real simple-icons file and on one with attribute, `style=` and `none`
fills; the launcher suite re-run unchanged.  NOT tested: the Wikimedia
downloads (this machine cannot reach them).

## 1.14.293 -- undoing the application accounts, and a default page per launcher

Three things the last release left half-done: removal stopped at the account,
a search launcher with nothing typed landed on an empty search page, and the
conf did not say which window is which.

  * `packagemanager user purge [--run] [--yes] [--keep-home] [--no-archive]
    [--accounts a,b] [--conf F]`: the whole undo.  Every account in
    app-users.conf, plus **strays** -- accounts with the user prefix whose
    home is under `appuser_home` but whose line is gone (exactly
    u_browser-mini/u_browser-big after the layout change) -- each through
    `user delete`, so each home is archived to /root first.  Then what no
    per-account command could remove because the next account still needed
    it: dead ~/Shared links, the hub and the icon dir when empty,
    /etc/profile.d/shared-dirs.sh, /etc/profile.d/xdg-runtime-share.sh,
    /usr/bin/xdg-runtime-share (each only if it carries the app-users
    marker), /etc/pam.d/su_u_user, the `pam_exec` line in /etc/pam.d/su
    (backup first), appuser_home when empty, and the session group last.
    Kept on purpose: the /root archives and app-users.conf.
  * `user delete` now removes **every dangling link** in ~/Shared, not only
    the ones pointing into this home.  A home moved after the link was made
    (usermod -d, or the move to /home/shared_user) left the link behind, and
    shared-dirs.sh enumerates that directory -- which is why
    `$SHARED_BROWSER_MINI` outlived the account.  Both commands end by
    naming the SHARED_* variables an already-open shell still has, and the
    `unset` for them: that file is read at LOGIN.
  * `cfg app-users` takes a shared directory away again: a line changed to
    `dir=no` has its ~/Shared/<Name> link removed when the target is empty
    or dangling, and is reported, not touched, when it still holds files.
  * Launcher templates take a default: `...?q={https://www.reddit.com/}`.
    With something typed it is the search; with nothing typed the word
    becomes what is inside the braces, instead of the URL cut at its `?`
    (`/search/` -- a search page for a search nobody made).  Plain `{}` is
    unchanged.  The fallback cannot contain `|`: that is app-users.conf's
    field separator.  `_write_launcher` now fills a plain template with
    .replace() rather than %-formatting bash full of `%02X` and `${w%%...}`.
  * app-users.conf: `--app-id <name>` spelled out on every browser line
    except the four generic ones (browser-mini, browser-big, google,
    duckduckgo), which keep the automatic one.  Shared directory (and
    `--download-dir ~/Shared`) on the accounts that want it; **not** on
    dokus, reddit and youtube -- what they download stays in the account.
    Default pages for google, duckduckgo, github, codeberg, reddit, youtube.
    Icons: ARD and arte from Wikimedia, nrwgpt as the OpenAI mark in sky
    blue (`https://cdn.simpleicons.org/openai/38BDF8`).

Tested: launchers generated and run with su replaced by a printer (default
page with no arguments, search with `&` and an umlaut, `{}` passthrough, `~/`
expansion); the conf through the step with a stubbed packagemanager (every
line parses, the four accounts aggregate as expected); the dir=no cleanup
against an empty, a dangling and a non-empty link; purge dry and real against
a built fake state -- two accounts (one a stray), dead links, the marker
files, the su line, the group -- verified afterwards by hand.  NOT tested: a
real su, and the icon downloads (this machine cannot reach the CDN).

## 1.14.292 -- application accounts: several launchers, {} arguments, icons, delete

From the user's app-users.conf (already written as `user | name | app ...`,
which the step could not read -- hence `~/bin/browser-mini` still running
u_browser, an account never created):

  * app-users.conf: `account | name | app | share | dir | desktop | launcher |
    groups | icon`, one line per LAUNCHER.  Accounts are aggregated: the
    strongest share, any dir, all groups; created/set up once.  Then
    `packagemanager user launcher <account> <name> --app ... [--icon]` per
    line.  The old 7-column format (header `name`) still reads.
  * Launcher (packagemanager `_write_launcher`): the argv is built in the
    script -- a word `{}` = the arguments; `{}` inside a word = URL-encoded
    search term, or with no arguments the word cut before its `?`; no `{}` =
    nothing passed (claude's "a second address:" came from an extra ''
    argument).  `~/` in the app = the ACCOUNT's home.  browser-mini/big get
    `--app-id <name>` when missing.  `exec su - u -c 'exec "$0" "$@"' -- argv`.
  * Menu entry: named after the launcher; Exec %U only with {}; Icon from
    `_fetch_icon`: URL, simpleicons slug, empty -> the name, - -> none; fetched
    once into ~/.local/share/icons/lfs-apps (.from records the URL).
  * `user delete <account> [--run] [--keep-home] [--no-archive]`: application
    accounts only (prefix, home under appuser_home or the package tree),
    refused while it runs anything; home archived to /root/<u>-home-<date>
    .tar.gz (0600) first; removes its launchers/menu entries/icons (only ones
    that run as it), ~/Shared links into its home, its su_u_user line,
    account, group, home.  `user remove-launcher <name> [--run]` for one
    launcher.  Both remind that the conf line must go too.
  * The shipped app-users.conf is the user's list, corrected: google/ddg/
    youtube/reddit/github/codeberg search URLs, chatgpt/gemini pointed at
    their own sites (both were claude.ai), codeberg .org, download dirs
    ~/Shared (were /usr/src/u_*), media accounts full, broken ard/zdf/mpv
    lines completed, icon slugs where the name differs (openai,
    googlegemini).

Tested: generated launchers run with su replaced by a printer (search term
with umlaut and &, no args, fixed URL with an extra arg, ~/ expansion), the
conf parser against the shipped file with a stub packagemanager, delete dry
and real (archive, launchers, link, pam regex), remove-launcher leaving a
hand-made file.  NOT tested: real su, icon downloads.

On the machine: u_browser-mini and u_browser-big stay until deleted.

## lfs-backup 1.3.0 -- merge

`merge <archive> [--plan f] [--only/--skip]`: the archive's existing .new
files one at a time, `diff -u` (MERGE_LINES, default 60), then k (keep live,
remove .new), n (take the backup's CONTENT; live owner/mode stay; .new
removed), e (MERGE_TOOL or vimdiff live .new, else $EDITOR .new; asks again),
s, q.  passwd/group/shadow/gshadow refuse n.  Answers from /dev/tty, or stdin
without one.  Tested with piped answers (k, n twice with a 600 live file,
refusal for passwd); suite block extended.

## lfs-backup 1.2.2 -- plan lines keyed by kind; absolute targets

The user's first plan: `~/.bashrc` etc. exist in [user] and [root]; the plan
named them identically and restore took the FIRST matching line, so root's
file followed the user's line.  And `~/` targets read as /root to someone
checking as root (953 "same" ALE files were the main user's, correctly).
Section column is now `kind:section`, the lookup key is kind:name, and the
target column is the resolved path (~/ still accepted).  Older plans are
refused with "write a new one".  Tested: user line skipped, root line kept.

## lfs-backup 1.2.1 -- secrets restored 0600-or-less

Second real backup: excludes worked (1043 files, 9.3 MB; no .git, test,
*~, .netrwhist).  The host modes are unchanged (gshadow 644, Wi-Fi keys
644/664), so restore now drops group/other bits for shadow, gshadow,
wpa_supplicant/*, ssh host keys, ~/.ssh/id_*, authorized_keys, and says so.
Tested with a 664 key and a 644 gshadow -> 600 each.

## lfs-backup 1.2.0 -- restore plan, excludes, ownership by kind

  * `plan <archive> [file]` writes `action | state | section | name | target`
    per file (identical -> skip); `restore/clean --plan file` follow it: skip
    lines are left alone, the target column may be ~/... (home of that kind)
    or absolute.  Unknown actions / short lines stop with the line numbers.
  * `!pattern` lines exclude matching names everywhere (bash [[ == ]], so *
    crosses /).  Shipped: plugin .git and test trees, *~, .netrwhist.
  * Owner on restore by KIND: [root] root:root always; [user] the main user
    (group kept only if it is another existing group); [system] recorded
    names that exist, never the main user, else root.

From the user's first real backup (manifest reviewed): root's .bashrc and
.bash_profile were links into ~/LFS/lfs-config and recorded as n76310's --
by name that restores a root dotfile the main user can edit.  Also on the
HOST, not the tool: /etc/passwd, /etc/group, /etc/hosts owned by uid 9999
mode 664/774; /etc/gshadow 644 (world-readable hashes); most
wpa_supplicant PSK files 644/664; /etc/vimrc owned by n76310 664.
/usr/share/vim/vimfiles held only cmake's files -- dropped from the config.

Tested: plan with a skip and a moved target, root file ownership, clean by
plan, a malformed plan line; suite block extended.

## lfs-backup 1.1.0 -- named sections, --only/--skip, clean

  * `[user:vim]`, `[system:accounts]` ...: a section's NAME (default: its
    kind) is recorded per file in the manifest (7th column; older archives
    fall back to the kind).  `--only a,b` / `--skip a,b` select by name or
    kind for create, restore and clean.  `sections [archive]` lists them.
  * `clean <archive> [--run]`: removes <target>.new for the archive's files
    only when its content is still what restore wrote; an edited .new is
    kept and listed; .new files from anything else are never touched.
  * The shipped backup.conf is the user's list, sectioned, plus vim
    (~/.vimrc, ~/.vim for user and root; /etc/vimrc, /usr/share/vim/vimfiles)
    and /etc/pkgusr/backup.conf itself.  /etc/rc.d is NOT taken whole: its
    init.d scripts and rc?.d links come from the bootscript packages.

Tested in the sandbox (sections from config and archive, --skip, --only,
clean with one edited .new); suite block extended.

## 1.14.291 -- lfs-backup replaces lfs-config

lfs-config was a git-repo manager (init/pull/push/adopt/mirror/undo).  The
user wanted a backup: one list of files, carried to a new system, put back
without replacing anything.

  * /etc/pkgusr/backup.conf: [user] (~ = PKGUSR_SYS_MAIN_USER's home, read
    from the environment or /etc/profile.d/pkgusr-system.sh), [root],
    [system]; globs; a directory takes its files.  Ships the user's list plus
    suggestions (passwd/group/gshadow with shadow, hostname, hosts, resolv,
    inittab, clock, console, profile, inputrc, sysctl, modprobe.d, sshd +
    host keys, app-users.conf, packagemanager.conf, ~/.gitconfig, ~/.ssh/config).
  * `create [--run] [archive]` (root): tar.gz with a manifest of mode + owner
    and group NAMES (ids resolved through the tree's own passwd/group); a
    symlink is stored as its target file.  Archive 0600 (secrets).
  * `restore <archive> [--run]` (root): missing -> created with mode/owner
    (old main user's name -> this system's main user; unknown names -> root,
    reported); identical -> left, mode differences reported; different ->
    <file>.new; passwd/group/shadow/gshadow ALWAYS .new.  Missing parent dirs
    under a home belong to that user.  The .new list is printed at the end;
    an identical existing .new is not rewritten.
  * LFS_BACKUP_ROOT restores into (or backs up from) a mounted tree.
  * Makefile installs lfs-backup + backup.conf (yours kept, .new beside),
    removes a retired /usr/bin/lfs-config.

Tested end to end in the sandbox (list, create, show, restore dry and real,
re-run); suite block replaced with a functional one.

## 1.14.290 -- machine.conf [gstreamer10] gst_debug = true

The user wants GST_DEBUG logging.  The book configures the core with
`-D gst_debug=false`; the machine option REPLACES that switch (tested:
apply_machine_opts turns the script's `-D gst_debug=false` into
`-Dgst_debug=true`).  `gstreamer:gst_debug` is the subproject form -- not
applicable to BLFS's separate core package, not added.  Plugin packages must
be rebuilt after the core: gstconfig.h's GST_DISABLE_GST_DEBUG is compiled
into each of them.  No tool changed; the version moves with the stack file.

## 1.14.289 -- launchers: a stale account, and an empty argument

    ~ > browser-mini
    No passwd entry for user 'u_browser'

~/bin/browser-mini was written when the account was still u_browser; every
later setup said "already exists -- left alone".  Launchers and menu entries
that carry this tool's header ("# Runs ... as the application user ..." /
"Comment=Runs as the application user ...") are now rewritten when they
differ from what would be written; files without it are left alone.

The CURRENT writer was also wrong: `su - u -c "app $(printf '%q ' "$@")"`,
and printf '%q ' with no arguments prints '' -- every launch without a URL
passed one empty argument.  Now `exec su - u -c 'app "$@"' -- <name> "$@"`:
shadow su passes what follows the user name to the shell (checked in
su.c 4.20.2), so bash gets $0=<name> and exactly the typed arguments (n=0
with none).  Tested the writer (stale rewritten, current kept, hand-made
kept) and the argument count.

Pre-existing in the upload: "a launcher could point at a program that does
not exist" (its sed range no longer matches the call).

## 1.14.288 -- `script install mesa` ran the OLD version's script

    $ build p_mesa --script /usr/src/pkgusr/p_mesa/install_Mesa-25.3.5 --phase install --force
    (Mesa 26.1.7 is what is installed)

`_versioned_script_in` returned the alphabetically first install_<name>-<ver>
in the home, and every version's script stays there.  It now takes the one
install_last names, else the newest by mtime.  Tested both paths; suite runs
it on a fake home.

Also: `# user 'p_<pkg>' already exists` is no longer printed on every build
(the build calls add-user with _QUIET_EXISTING=1); `lfs-helper add-user`
still says it.

## 1.14.287 -- three undefined names (pyflakes)

    could not work out what WebKitGTK-2.52.5 depends on -- NameError: name 'ignore' is not defined

  * cmd_install's one-package missing-dependency check used `ignore`, a
    local of build_install_plan.  Every non-recursive install printed the
    NameError instead of its missing dependencies.  It now builds the same
    set from args.ignore.
  * cmd_script_status: `versions.get(...)` in a block that cannot currently
    run (its states are script states); now `assess(u, None, run_cmd=False)`.
  * lfs `_accounts_root`: `read_config()` does not exist; the NameError was
    swallowed, so a configured pkgusr_subdir/cfguser_subdir was ignored.
    Now load_config().

pyflakes finds nothing else but STACK_DIR (globals()-guarded on purpose).
Suite: runs pyflakes on packagemanager, lfs, blfs when it is installed.

## 1.14.286 -- the session group: <prefix>_xdg-runtime

    /tmp/xdg-n76310 is group 'n76310', which is not a shared group -- u_x was not added
      Set up a runtime group for the session first, then re-run this.

Nothing ever set one up.  The user's decision: one named group,
nimgnu_xdg-runtime, on the main user's XDG runtime directory; every shared
u_* account and the main user in it.

  * packagemanager `xdg_runtime_group()` = collector prefix + "xdg-runtime";
    `_join_xdg_runtime_group` creates it (collector range), adds main + u,
    and chgrp/chmod 0750 the runtime directory if it exists now.  The old
    "read the group off the directory" rule and its tests are replaced.
  * The directory is recreated each boot, so the SESSION applies the group:
    app-users writes /usr/bin/xdg-runtime-share (dir 0750 + g+rw on
    wayland-N and pipewire-0 sockets, polling ~30 s as they appear) and
    /etc/profile.d/xdg-runtime-share.sh (dir only, at login).  Not the
    session bus: dbus refuses other uids.  The user's sway config is not
    edited; the step prints the `exec xdg-runtime-share` line to add.
  * app-users expect= requires the helper, so the cached step re-runs.

Tested: the generated helper, run as a non-root member, grouped the dir
(0750) and the wayland socket (g+rw), left the .lock alone.  Not tested in a
real session: whether pipewire lets another uid in beyond the socket mode.

## 1.14.285 -- "done" is not "current", and media's entries were done by sway

    media  1/19 done        (with 189 of 215 packages installed)
    ... ~70 lines of "(book is newer)" in `stack media --status --full`

By design a stack run builds what is MISSING and never updates what is
installed; `update --stack <name>` does that.  Two displays hid it:
  * done counts read only the stack's OWN cache.  sway includes media, so
    media's entries were recorded under sway.  The list and --status now
    count an entry done if ANY stack's cache has it.
  * --status printed the per-package "(book is newer)" only with --full.  It
    now prints `behind : N installed older than the book (...)` and the
    `update --stack` command.  The list shows "N entries behind the book"
    (top-level entries only -- the dependency tree is --status's job).
Tested: the list with stubbed book/user data.  Status blocks' failures are
pre-existing in the uploaded zip.

Noticed in that status (unverified): spirv-llvm-translator and libclc show
installed at 22.x, but both last ended in failures under the record bug --
check `llvm-spirv --version`.  libical 3.0.20 -> 4.0.5 is a major (soname)
bump: update it with -R.

## 1.14.284 -- `packagemanager stack` lists the stacks

`name` is optional now.  Without it: every *.stack in /etc/pkgusr/stacks
(and stacks/ beside the tool if different), its description (the header's
text after " -- "), buildable entries done/total from the stack cache (the
included avoid list is not counted), and a `.new waiting` note.  avoid.stack
shows as "never built".  Suite: the sway line is listed.  README shows it.

## 1.14.283 -- app-users' probe judged accounts it does not manage

The 1.14.282 probe failed after a correct run: it checked EVERY u_* account,
and u_test (made by hand, not in app-users.conf) is still /home/u_test.  A
permanently failing probe also re-runs the cached step on every stack run.
It now checks only the names in app-users.conf.  Tested with a stub getent:
a managed account in /home fails, an unmanaged one does not.

The failure text for a cfg entry said "MISSING A FEATURE ... optional
dependency" and suggested installing one.  A cfg entry now gets: the step ran,
what it keeps true is still false, read its output, run it again.

## 1.14.282 -- application homes in one subdirectory, as configured

    # ls /home
    n76310  tester  u_browser-big  u_browser-mini  u_claude  u_test

The machine's layout is appuser_home=/home/shared_user (history, "the user's
system").  `_relocate_app_home` ignored it and moved every account to a
hard-coded /home/<user>; `_setup_application_user` chmod-ed
appuser_home()/<user> instead of the real home; `lfs` defaulted
appuser_home to /usr/src.

  * APPUSER_HOME_DEFAULT = /home/shared_user (packagemanager), the same in
    lfs's layout defaults; `appuser_home` in the config still overrides.
  * Relocation targets appuser_home()/<user>, from the package tree OR the
    old /home/<user>; creates the subdirectory root:root 755; re-points the
    main user's ~/Shared/<Name> links into the new home.
  * `user setup` relocates too, so `cfg app-users` moves existing accounts;
    its expect= fails while any u_* home sits directly in /home, so the
    cached entry re-runs.

Tested in the sandbox: home moved with contents, 0750, parent created, link
re-pointed.  Tests pinning the old /home and /usr/src defaults updated.

## 1.14.281 -- no version record was written on a normal install

    .pkgusr-installed: LLVM-21.1.8    install_last: LLVM-22.1.8    llvm-config: 22.1.8

The "why is LLVM in the plan again" answer.  cmd_build's success has two
branches: `--phase all|update` (every packagemanager install) and a
single-phase run finishing the last phase.  .pkgusr-installed was written
ONLY in the second.  VERSION, written before both, parsed only
name_version="..." -- the generator writes '...' -- so it was never written
for BLFS scripts either.  Readers fell back to install_last, staged before
the build (the webkitgtk/LLVM "failed build advanced the version" bug).
1.14.273's seeding then pinned the OLD version with nothing to update it.

`_record_installed` writes both records, parsing either quote style, and
both success branches call it.  Suite: both calls, and a functional run of
the function; fails on 1.14.280.

On the machine: markers seeded since 1.14.273 are stale for every package
that installed successfully since -- listed by a one-off in chat, set by hand
(LLVM: 22.1.8).

The manifest cleanup found the pollution in 11 manifests and 4 pkg.lst
files, not only LLVM's (gst10-plugins-bad, libclc, libnftnl, librice,
libsndfile, mesa, opencv, pkgusr, shadow, webkitgtk).

## 1.14.280 -- the earlier-stages claim took root's files from LLVM's manifest

    # claiming files from earlier stages of p_llvm ...
    # gave 'p_llvm' 13 path(s) from its earlier build stages

1.14.278 stopped the lease lending LLVM's polluted root entries, but the
claim step (before every phase) CHOWNS root-owned manifest entries to the
package for good: su_u_user and the tools became p_llvm's.  The claim exists
for chapter 7's root-built leftovers under the same step name.

Now: once the package has installed as itself (.pkgusr-installed or VERSION
in its home), only its -tmp/-pass1/-pass2/libstdcpp stage manifests are
claimed from, never its own.  Claim blocks 87/197/210/214 pass.

On the machine: chown the 13 back to root and run the 1.14.278 manifest
cleanup.  Why LLVM is in the plan as "update" again is NOT known yet --
its record should say 22.1.8 after the run that reached libclc; asked for
.pkgusr-installed and install_last.  The install phase re-runs cmake+ninja
(the compile is in install_pkg) but the build tree is kept, so ninja should
have little to do.

Pre-existing (upload): block "a failed build makes no install claim" fails
on libdisplay-info and poppler after sway.stack's git marker.

## 1.14.279 -- firmware: patterns at any depth, flat names from WHENCE

    !! FIRMWARE_ONLY asks for 'iwlwifi-*.ucode', which is not in .../linux-firmware
       intel/iwlwifi/iwlwifi-100-5.ucode ...
    !! this config builds firmware INTO the kernel, so the build cannot proceed

linux-firmware moved the iwlwifi blobs into intel/iwlwifi/ and keeps the flat
names drivers ask for as `Link:` lines in WHENCE (its copy-firmware.sh makes
the links).  The sparse checkout already fetched the files at their new depth
(no-cone patterns match anywhere); the install looked at the top level only.

  * A pattern entry now matches files at any depth (and counts WHENCE link
    names); files keep their paths (cp --parents).
  * After a selective install, every WHENCE `Link:` whose target was
    installed is created, never over a real file.  `intel` alone now yields
    the flat iwlwifi names too.
  * No-cone sparse checkouts include /WHENCE.

Tested on a fake checkout: both blobs copied under intel/iwlwifi/, three
links made, a link to a missing target skipped.  WHENCE's exact format is
from memory (gitlab unreachable).

**Also fixed:** 1.14.270 broke two existing suite checks -- the mesa probe
must use `test -e a -o -e b`, and the llvmpipe comment must sit directly
above `book mesa`.  libglvnd now comes before that comment.

**Pre-existing suite failures** (present in the uploaded zip, not touched):
alsa option for gst-plugins, mesa software gallium/vulkan drivers in
machine.conf, webkitgtk USE_LIBRICE / USE_WOFF2 / woff2 probe, openh264
out-of-book markings.

## 1.14.278 -- LLVM's manifest swallowed root's files, and the lease lent them

    #   leased /etc/pam.d/su_u_user (755 root:root) to p_llvm for this phase
    #   leased /usr/bin/lfs (755 root:root) to p_llvm for this phase  ... 14 files

LLVM's compile is generated into install_pkg (OPEN, 1.14.273), so its
install window lasted hours.  Root ran `make install` of these tools and
`cfg app-users` inside it; the touched-file scan is by time window and keeps
root-owned files, so they entered LLVM's manifest.  The lease then treated
each as LLVM's own root file and chowned su_u_user -- run by root on every
su -- to p_llvm, every install round.

  * **Scan:** when a phase ran as the package user (not as_root, not
    chown-after), a root-owned file it "touched" is not recorded -- it cannot
    have written one; a leased file it rewrote is its own after settle.
  * **Lease:** a root-owned file is lent only if it is setid (bit or
    setid.conf) or the package's configure commands write it.  A manifest
    claim alone is no longer enough.  Suite block 111 case 7; fails on
    1.14.277.
  * Existing polluted manifests: one-off cleanup in chat (tool files,
    su_u_user, S99power-perms, completions).

**libclc: "Producer LLVM22.1.8, Reader LLVM 21.1.8"** -- llvm-spirv is still
the 21 build.  spirv-llvm-translator failed at 22.1.5 before the 1.14.273
marker fix, so its record says 22.1.5 and the plan skipped it (same poisoning
as LLVM's).  Fix on the machine: rebuild it explicitly, then libclc, mesa.
After an LLVM major bump, `packagemanager update llvm -R` rebuilds dependents.

## 1.14.277 -- kernel.conf CONFIG_SET

lfs-kernel had no way to say "this machine always wants option X": the config
came from the running kernel, a refresh answered new symbols, and anything
else meant menuconfig by hand every time.  `CONFIG_SET="SYM=val ..."` (y, m,
n, number, string) is applied after the refresh with scripts/config, resolved
with olddefconfig, and READ BACK -- a value the kernel reverts (missing
dependency, unknown symbol) is named and stops before compiling.

Shipped value: `LEGACY_TIOCSTI=n` (shadow 4.20 su detaches root's `su -`
shells while TIOCSTI is allowed).  An edited kernel.conf is kept by
`make install` (.new beside it), so an existing machine adds the line by hand.

Tested: the apply/read-back block on a fake tree (disable taken; an unknown
symbol reported, exit 1).  Kernel blocks 155 and 401 pass.  Not built.

## 1.14.276 -- lfs-helper regroup-dir

    /etc/pam.d  p_bash-completion:nimgnu_bash-completion  drwxrwxr-x

A directory shared through the wrong group.  `lfs-helper regroup-dir <dir>`:
  * installers = packages whose manifest or pkg.lst has a direct child of it,
    package/config accounts owning an entry in it, and its owner;
  * asks the new name (1 dir-named, 2 owner-named, typed, q) -- pam.d gives
    nimgnu_pam-d;
  * members of the old group keep it only if they own, or install into,
    another directory of that group -- found on EVERY real filesystem
    (a missed mount would have dropped memberships);
  * prints the plan, applies only on y; updates collector-map and granted.
  * Leaves the old group in place and says when it is on no directory.

Tested in the sandbox: installers found, two members dropped, the owner and a
member of another directory kept, q cancels, new group at 90000.

(The 1.14.275 open item on /etc/pam.d stays: it should be root's.  This
command at least narrows who can write it.)

## 1.14.275 -- su to application users: four faults, one symptom

    ~ > su - u_browser-mini
    su: Authentication failure
    su: Authentication token manipulation error

  1. **/etc/pam.d/su had no pam_exec line.**  Shadow's configure rewrote su
     (1.14.263); `cfg app-users` was `done (stack cache)` and never re-ran.
     **A cached cfg entry with expect= is now re-checked on every run** and
     re-run when the check fails.  shadow-pam and app-users got expect=
     probes (su setuid root + pam.d files; su calls su_u_user, root owns it,
     caller check present).  Probe tested against good and bad files.
  2. **SECURITY: su_u_user compared the TARGET with a list containing it**
     (`[[ "$USERS" =~ "$PAM_USER" ]]`, empty PAM_RUSER filled with PAM_USER)
     -- always true: any account could su to every listed account without a
     password once the pam line was there.  Now `[[ -n $PAM_RUSER ]] || exit
     1` and a whole-word check on PAM_RUSER.  Existing files are repaired in
     place with a backup.  Tested: main user passes, another u_ and an empty
     caller are refused.
  3. **SECURITY: su_u_user was owned by p_librice** (attributed to librice's
     build window) -- a package user could replace a script root runs on
     every su.  app-users forces root:root 755 on every run.
  4. **"token manipulation error"** = the account step demanding a new
     password: /etc/shadow last-change 0.  app-users locks an EMPTY password
     field (Enter would have logged in) and sets last-change when it is 0.
     Tested on a sandbox account.

**Open:** /etc/pam.d itself is p_bash-completion:nimgnu_bash-completion 775
-- every member (bash-completion, gstreamer10, linux-pam, shadow) can replace
any PAM file.  It should be root-owned; collector grants on /etc/pam.d need a
rule.

## 1.14.274 -- the slow scan, and CMake's wrapped permission error

**"scanning the tree ... takes a moment" took minutes** after a two-second
install.  Every phase end walked the whole tree five times (snapshot,
snapshot_dirs twice, two `find -newer`), and every walk used
`-not -path "$SRCROOT/*"` -- which filters AFTER descending, so each one
went through /usr/src: every package's unpacked sources and build trees.
Now `-prune` (same output: compared old vs new on a synthetic tree, both
snapshot lists and both touched lists identical), snapshot_dirs once, and one
walk for touched files+dirs.  Scan-related suite blocks pass; block 240's
string check accepts the pruned form.

**nvtop stopped after one round** on a plain permission error.  CMake wraps
it: `...metainfo.xml": Permission` / `denied.` -- no line matched, round 2
found nothing and the loop ended.  `unwritable_dirs_from_log` joins each
`file INSTALL` block; the repair gate also accepts "file INSTALL cannot".
Tested on nvtop's log text.

The retry loop itself already runs while each round fixes something (cap
20, stops when the same directories repeat) -- it was the parser.

## 1.14.273 -- a failed LLVM update was taken as installed

    CMake Error ... Could not find a configuration file for package "LLVM"
    compatible with requested version "22.1.0" ... version: 21.1.8

The mesa plan was 9 entries (LLVM failed on its patch, 1.14.272); the
re-run's was 6, without LLVM.  `User.version` reads `.pkgusr-installed`
(written after success) and, for a package built before that marker
existed, falls back to `install_last` -- which lfs-helper replaces BEFORE
the build.  So LLVM's failed 22.1.8 attempt made it "current".

The staging step now seeds `.pkgusr-installed` from the OLD install_last
before replacing it (only when the marker is absent).  A failure then leaves
the old version recorded.  Tested: the version extraction.  Suite: grep.

On the machine the record is already wrong -- one-time fix:
    echo LLVM-21.1.8 > /usr/src/pkgusr/p_llvm/.pkgusr-installed

### OPEN -- LLVM's compile is generated into install_pkg

The page creates /etc/clang/*.cfg as root BEFORE cmake (on purpose: SSP for
compiler-rt), and the phase split starts install at the first root block,
so cmake + ninja + `ninja install` all land in install_pkg.  It works, but
"re-run only the install step (no recompile)" is false for LLVM, and a
repair round in install recompiles.  Needs a rule for a root block the page
says must precede the build.

## 1.14.272 -- extra downloads were saved under the tarball's name

    HTTP request sent, awaiting response... 416 Requested Range Not Satisfiable
        The file is already fully retrieved; nothing to do.
    patch: **** Can't open patch file ../llvm-22.1.8-upstream_fix-1.patch

`_pp_unpack` called `_pp_fetch "$li"` for each additional_links entry with no
output name, and `_pp_fetch` defaults the name to `$pkg` (the openh264
rename).  So every patch was `wget -c -O <the tarball>`: 416 when the tarball
is bigger (patch silently missing), and appended onto it when smaller.  Now
`_pp_fetch "$li" "$f"`, and a missing file after the fetch is an error.

Every BLFS page with a patch or extra tarball was affected since that rename.
Tested with a stub wget.  Suite: grep in "one list, two entry points".

The run was mesa's dependency plan updating LLVM to the 13.1 book's 22.1.8
-- hours; there is no skip-dependencies switch.

## 1.14.271 -- libglvnd taking Mesa's headers was called a bundled copy

    /usr/include/GLES/egl.h belongs to p_mesa -- handing it to p_libglvnd
    ! libglvnd has now taken three files, one per round, from 'p_mesa'.
    ! It is building a BUNDLED COPY of that package ...

It was not.  Mesa with glvnd=disabled owned GL/GLES/EGL/KHR headers and
libGL; libglvnd legitimately replaces them.  meson stops at the first file
it may not chmod, so the log named one per round, and the 1.14.116 streak
rule (3 single handovers from one owner) fired.

`meson_takeover_from_log` now, after a handover, reads
`meson-info/intro-installed.json` (found by walking up from the source path,
no further than the package user's home) and hands over EVERY planned
destination still owned by that same package -- one round.  Not done for a
subprojects/ source, and only a subprojects/ source now counts toward the
bundled-copy streak, so libdisplay-info's case still stops.

Tested in the sandbox with two users: 1 logged + 3 planned files moved, a
file outside the plan untouched; a subproject source still sets the streak.
Suite: grep checks; "the directory was never the problem" and "one file per
round" blocks still pass.

**Open:** directories (GL/, EGL/, KHR/) owned by p_mesa still get one
collector-group question each.

## 1.14.270 -- Mesa with glvnd; libglvnd in sway.stack

The user asked for it.  `[mesa] glvnd = enabled` in machine.conf, and a
`git libglvnd` entry directly before `book mesa` in sway.stack.

  * **libglvnd is NOT a BLFS page** (the book only links GLFS).  An earlier
    chat reply said it was -- wrong.  URL is the canonical freedesktop
    gitlab; tag v1.7.0 and option names CHECKED on NVIDIA's GitHub copy.
    Default options.
  * **One go, or GL breaks**: between libglvnd's install and Mesa's
    rebuild, libGL.so.1 is glvnd's with no vendor.
        packagemanager stack sway --only libglvnd,mesa --run
    Existing binaries keep working (same sonames).
  * Mesa's probe now also requires 50_mesa.json and libGLX_mesa.so.0, and
    its `a; b` form (first test ignored) became one expression.
  * **`--clean` never deletes a file another package owns.**  Mesa's old
    manifest lists libGL.so.1, which libglvnd installed before the Mesa
    rebuild -- older than the install start, not rewritten: `_orphan_sweep`
    would have deleted the GL library.  It now skips files not owned by the
    package user.  Tested with a stub remover.

Suite: glvnd-before-mesa order and the sweep guard, in "one list, two entry
points".  Not built.

## 1.14.269 -- mesa-demos: libdecor's demo wants opengl.pc

    subprojects/libdecor-0/demo/meson.build:8:9: ERROR: Dependency "opengl" not found

Not a missing stack entry.  opengl.pc is libglvnd's, and machine.conf has
`glvnd = disabled` for Mesa, so Mesa ships gl.pc/egl.pc/glesv2.pc and no
opengl.pc -- by design.  Only libdecor's DEMO (a meson subproject pulled in
by mesa-demos' wayland demos) asks for it.  diag.stack passes
`-Dlibdecor-0:demo=false`, and wipes `build/` before `meson setup` in both
meson entries, since a failed setup leaves it half-configured.

**The failure box misleads here**: "packagemanager install opengl" -- there
is no such package, and installing libglvnd without rebuilding Mesa against
it would not help.  Not changed; worth a pc-module note later.  (1.14.270
switched the machine to glvnd.)

**machine.conf `[mesa] gbm = enabled`.**  Mesa builds gbm by default on
Linux, and sway works, so it is there.  Named so a Mesa that cannot build
it fails at configure rather than finishing and breaking wlroots.  No
rebuild needed.

`libdecor-0:demo` is from memory (gitlab unreachable) -- if meson says
"Unknown option", the name is in
`subprojects/libdecor-0/meson_options.txt` in the clone.

## 1.14.268 -- diag.stack: GPU diagnostic tools

New optional stack, none of it in the book: mesa-demos (glxinfo, eglinfo),
vulkan-tools (vulkaninfo), libva-utils (vainfo), nvtop.

  * **vulkan-tools and libva-utils pick their tag at build time** from the
    installed version (`pkg-config --modversion vulkan` / `libva`).  Both
    must match what is installed, and a fixed pin breaks on the next book.
    Tag patterns checked with git ls-remote.
  * **nvtop's vendor is the only choice in the file**, in a marked block at
    the top.  Every backend defaults ON on x86, so all are named; ON is
    AMD only (this machine).
  * **mesa-demos is NOT CHECKED**: gitlab.freedesktop.org was unreachable.
    Pinned mesa-demos-9.0.0; option names from memory -- first thing to
    look at if it fails.

Tested: parsed, the four generated scripts pass `bash -n`, libva-utils tag
selection on a real clone.  The conventions and version suite blocks pass.
Not built.

## 1.14.267 -- id ranges, and cfg power's three false failures

**Ranges, one per kind of id.**

    package users + private groups   10000-20000
    collector groups (no account)    90000-98999
    application users (u_*)          30000-39999

Found on the machine: `nimgnu_python-modules`, `-xorg7-input-driver`,
`-perl-modules` were group AND login account at 10096/10147/10162, home
`/usr/src/pkgusr/p_nimgnu_...` -- `sysgroup create` ran the package-user
helper.  It now calls `_create_collector_group`, group only.  `u_*` were
at 10324-10349 among the package users; `user create` now uses
`APP_UID_MIN/MAX`.  `nimgnu_power` was 997 (power.sh: system groupadd);
it now asks `packagemanager sysgroup create`.

The machine's existing ids are repaired by a one-off script given in chat
(dry run by default): removes the collector accounts, renumbers collector
groups into 90000+, u_* into 30000+, re-owns files on every real and tmpfs
mount, and puts each file's mode back -- chown/chgrp clear setuid, which
is how 1.14.265 lost su.  Tested in the sandbox on fake accounts: setuid
bit, group members and home ownership kept.

**power.sh, three false `!!`:**
  * poweroff/reboot are symlinks to halt; `stat` read the link (777).  It
    now resolves each path and handles every target once.
  * it linked only into rcsysinit.d; LFS's sysinit runlevel is rcS.d.
  * the two udev lines that never matched (KERNEL=="state", =="bootlog")
    are now removed, not explained -- the user asked.  No bootlog account
    or group is needed.

Suite: greps in "one list, two entry points"; the 1.14.266 files fail all
five.  Tested: power.sh's udev cleanup on sample rules.

## 1.14.266 -- cfg power could not find the collector prefix

    !! no collector_prefix in /etc/pkgusr/packagemanager.conf

power.sh parsed packagemanager.conf with the lfs config's JSON pattern
(`"collector_prefix": "..."`); that file is `key=value`.  It could never
match, and on a booted system with no lfs config it stopped the stack.  Two
parsers, one fact, again.

packagemanager now exports the RESOLVED `LFS_COLLECTOR_PREFIX` and
`LFS_MAIN_USER` to every cfg script: environment, lfs config,
packagemanager.conf, then the collector groups on the system -- never a
built-in default.  power.sh reads the variable, and falls back to the
conf's real `collector_prefix=` line.

Suite: grep checks in "one list, two entry points"; the old power.sh fails
them.  Tested: power.sh's group step with and without the variable.

**The stack cache hides the repair.**  `stack services --run` printed
`cfg shadow-pam  done (stack cache)` and did not run it, so the stripped
setid bits stayed stripped.  `--only shadow-pam --run` runs it.  Whether a
cfg entry should ever be cached is open.

## 1.14.265 -- the earlier-stages claim stripped every setuid bit

    ~ > su -
    su: Authentication service cannot retrieve authentication info

On the booted machine su had no u+s, nor had the rest.  The cause is in
the configure output of 1.14.263's run:

    # gave 'p_shadow' 16 path(s) from its earlier build stages

`_claim_earlier_stages` runs before EVERY phase and chowns root-owned
manifest entries to the package user -- its own manifest included, not only
-tmp/-pass stages.  chown clears setuid, so su, passwd, chage ... went
4711 root -> 755 p_shadow.  The lease then saw files the installer already
owned and had nothing to restore.  The claim fired before the lease could.

`_claim_candidates` now skips any file with a setuid or setgid bit; those
are the lease's (copy aside, restore on failure, setid.conf on success).
Suite block 111 case 6; checked to FAIL against 1.14.264.

**On the machine:** the bits are already gone, and shadow-pam's step 3
applies setid.conf -- that is the stack's own repair.  It needs root, and
su is what broke: log in as root on a tty, or run it from the chroot.

**`update --clean` does not touch this.**  It is opt-in, removes only
old-manifest files the new install did not rewrite, and never under /etc,
/var, /boot, /home, /root, /srv.

## 1.14.264 -- a package reclaims its own files

The rule, from the user: **a package owns what it installs, whoever holds
the file now.**  The lease already settled a rewritten file to its
installer, but on INSTALL it only leased the manifest's ROOT-owned entries.
A manifest file another package had taken was not leased, so a bash
redirect or `cp` over it failed with a wording no repair parses -- the same
shape as shadow's /etc/pam.d/su.

`_lease_candidates` now takes every manifest entry not owned by the
installer.  The guards stay in `lease_files`: package accounts only, root
only when the manifest claims it, no symlinked directory.  On success a
rewritten file stays with the installer; an unchanged one goes back.

Suite block 111, case 5; checked to FAIL against the 1.14.263 lfs-helper.
Not run on the machine.

## 1.14.263 -- the lease: hand files over before a phase, not after it fails

    /usr/src/pkgusr/p_shadow/install_Shadow-4.20.2: line 153: /etc/pam.d/su: Permission denied

/etc/pam.d/su was p_linux-pam's, 644.  The repair loop recognised nothing
in a bash redirect's wording, granted /etc/pam.d (never the problem) and
stopped.  Every tool words that refusal differently, and each needed its own
parser -- and the setid pass (root takes the file) and the 1.14.261
take-back (a repair hands it back) were two halves of one cycle.

**The lease**, in `run_phase_as` -- the one runner -- around every
install/configure/all/update phase, as root:

  * **before:** each file the phase will write that another account owns
    is COPIED to `$STATE/leases/<pkg>/` with owner and mode, and chowned
    to the installer.  Copied, never moved: the phase starts with
    `su - p_<pkg>`, and su, its pam file and unix_chkpwd must exist.
  * **failure** (including exit 0 with a failure in the log -- it settles
    AFTER that check): every copy back, owner and mode, read back.
  * **success:** a setid.conf path gets its policy; an unchanged file goes
    back to its owner; a rewritten one belongs to the installer.
  * a ledger left by a killed run is restored before the next lease.

**Which files:** the manifest's ROOT-owned entries (install), and what
`configure_pkg` writes (configure) -- `lfs-helper script-targets`: redirects,
tee, install/cp/mv/ln destinations, sed -i, for-loops expanded, heredoc
bodies and comments skipped, /tmp /dev /proc /sys /run ignored.

**Security:** a root-owned file is leased only when this package's manifest
claims it (the script is the package user's to edit; one line could name
/etc/shadow).  Non-package accounts' files never.  No path through a
symlinked directory.  The first install over another package's file cannot
be predicted, so the repair loop remains the fallback -- minus its root
take-back, which is gone.

**One setid table.**  `_setid_known` had its own list saying 4755 while
setid.conf said 4711, so `cfg shadow-pam` and `setid --run` corrected each
other.  It reads setid.conf now (the dbus helper line moved there), and a
requested bit on a path setid.conf names is left to setid.conf.

**The stale script on the machine.**  `packagemanager stack services` run
from ~/lfs read ~/lfs/services.stack, and `cfg` entries run
`<that dir>/<name>.sh` -- an old shadow-pam.sh.  packagemanager now warns
when a stack or cfg script found there differs from /etc/pkgusr/stacks.

shadow-pam asks `lfs-helper script-targets` for its pam.d set (one parser).
Stack stamps: all at 1.14.263 -- 1.14.262 bumped the tools and not the
stacks, which the suite reports.

**Tested:** `run-script` end to end with real su, two throwaway package
accounts and sticky directories (failed configure restored; install over a
root 4711 file settled to 4711 root:<pkg>; successful configure owned by
the installer; interrupted lease restored).  Suite block 111 does the same
without su; it FAILED until the fixture left /tmp (script-targets ignores
/tmp) and `_setid_conf` survived `set -u`; checked to FAIL against the
1.14.262 lfs-helper.  Whole suite, all 429 blocks, run against both trees:
identical FAIL lines except the stack-version ones 1.14.263 fixes -- the
1.14.262 zip shipped stacks still stamped 1.14.261.

**Not tested:** a real package build on the machine.

### Suite: pre-existing, not from this release

  * Block "one quote character, three symptoms" deletes the suite's
    counter directory; every PASS/FAIL total after it reads empty.  Same
    on the 1.14.262 tree.
  * `--only` of a block that uses `_hlv` without block 114 ("the version
    is what FINISHED") died on `_hlv: unbound variable`.  Fixed for block
    121 ("one list, two entry points"), which now sets it itself; other
    blocks may share the shape (grep `_hlv` before relying on --only).

## 1.14.262 -- shadow's pam.d files, and the cache that hid three fixes

    passwd: pam_start() failed, error 26
    login: PAM Failure, aborting

**The cache.**  The first try at this fix did not fire either, which is how
the real bug turned up: blfs's index cache was keyed on the book's size,
mtime and a hand-bumped CACHE_VERSION -- not on the code.  An edited
extractor rendered from the index the OLD code built.  That is the whole
story of 1.14.212 and both poppler patches "not firing".  `_book_stamp` now
includes `_build_id()`, so any edit to blfs re-indexes once (~20s).

**The walk.**  Shadow's commands are in `div.configuration > div.sect3 >
div.sect4 > pre.root`, and `extract_commands` dropped every div that was
not a note.  It now descends into `div.sect4`/`div.sect5` with the same
rules (guards included) and keeps their titles as `##` comments.  The top
level is unchanged byte for byte.

**Proved against a rendered book, not a sample.**  The BLFS source was
cloned and rendered (`make nochunks REV=systemd`).  Before and after, for
all 146 pages with a configuration section: 141 scripts byte-identical, no
build or install phase changed anywhere, and exactly five configure phases
gained blocks -- the five pages the XML says have commands in sub-sections:
Shadow, MIT-Kerberos, NFS-Utils, SANE, Samba.

  * Shadow: login.defs, login, passwd, su, chpasswd+newusers, chage, the
    `for PROGRAM` loop, access and limits renames.  16 pam.d files.
  * NFS-Utils, SANE: the new blocks are all guarded (SKIPPED).
  * Samba: `systemctl enable` lines (the shim's job); smb.conf examples
    have no command markup and stay out.
  * **MIT-Kerberos: see OPEN below.**

**`cfg shadow-pam` checks the SET.**  It read two files and said "in
place" while fourteen were missing.  Now `_book_pam_set` reads each
package's `configure_pkg` (every `/etc/pam.d/<n>` on a live line, plus the
words of a `for VAR in ...` loop writing `/etc/pam.d/${VAR}`) -- linux-pam 5,
shadow 16.  The script comes from `packagemanager script fetch`; if it names
no pam file (the stale pre-1.14.262 one), it is fetched again with
`--regenerate`, so a correct script is never regenerated just for a check.

**The su trap.**  Shadow's su block has no pam_exec line.  app-users greps
for `su_u_user` and re-adds it, and runs after shadow-pam in services.stack;
the suite now asserts that order.  shadow-pam says so when it happens.

Suite: block 110 renders a shadow-shaped page through the generator (with a
fresh BLFS_STORE), and runs `_book_pam_set` on the output.  Checked that it
FAILS five ways against 1.14.261's blfs.

### OPEN -- MIT-Kerberos's configure phase is now a transcript

It gained a KDC walkthrough: `kdb5_util create -r __EXAMPLE_ORG__ -s`,
`kadmin.local` followed by lines like `kadmin.local: addprinc ...` (typed
INTO the program, not shell), `kinit`.  stdin is closed, so nothing hangs;
the phase fails loudly instead of silently doing nothing, as before.  Not in
any stack.  The fix is a "prose is not code" rule: a line `<prog>: ...`
after a bare `<prog>` line is a transcript -- comment the block.

### Small: shadow's login.defs block is not idempotent

A second configure run copies the ALREADY-edited login.defs over
`login.defs.orig`.  Harmless for login; the pristine copy is lost.

## GAP IN THIS DOCUMENT -- 1.14.180 to 1.14.238

The per-release notes for **1.14.180 through 1.14.238** are NOT in this
file.  They were written each release and are not here now; the section
below jumps from 1.14.179 to 1.14.178.  I do not know which edit dropped
them, and I am not going to reconstruct fifty-eight sessions from memory --
invented notes would be worse than an admitted gap.

Where the real record is:

  * every release's zip contains the HANDOFF.md of that release.  The
    newest zip that still has a given section is the place to read it.
  * the CODE carries its own reasons: every fix in that range went in with
    a comment naming the failure it came from, and
    `test_lfs_crosschain.sh` carries an assertion per fix with the release
    number in its comment.  `grep -n '1\.14\.2' test_lfs_crosschain.sh`
    lists them in order and is a usable index of what changed and why.

What that range covered, from the assertions, in one line each: the
swallowed-failure dialects; the stale-destination and cmake-destination
repairs; job counts reaching make/cmake/cargo/ninja; the `[all]` section;
media.stack and `include`; avoid.stack and every stack including it;
app-users.conf with create-or-setup and the PAM script; `env --system`;
librice; the version marker; and the per-package `book =` override.

## This session (1.14.179) -- lfsconf is now lfs-config, and it installs

It was `lfsconf`, living inside the repo it managed: the repo carried a copy
of the tool, the tool had no version anyone could compare with the others,
and `make install` did not know it existed. It is `lfs-config` now, on the
Makefile's TOOLS line -- so install, uninstall, the stamp file and the chroot
refresh all pick it up with no second edit.

**The point of it is the other machine**, and that half was missing:

- **The repo records whose config it is** (`repo-user`). A directory's owner
  answers that only on the machine that made it; cloned elsewhere it is
  whoever ran git, while every `~` path and every owner field still means the
  original user.
- **`lfs-config install [--as USER]`** maps the recorded user to this one
  (`n76310:n76310` -> `chris:chris`), expands `~` to the target's home,
  refuses a user that does not exist here, and **keeps what it replaces** as
  `<path>.orig-<timestamp>`.
- It does NOT rewrite file contents. It lists the tracked files that still
  mention the old name, because a username inside a config file may be a
  path, a group, an SSID comment or a mistake, and only the reader can tell
  which. The suite fails if a `sed -i` ever appears there.
- **`lfs-config init`** makes the repo. Creating one used to be a side
  effect of every command -- `--help` in a directory with no repo wrote a
  manifest into ~/LFS/lfs-config and printed two errors before the help.

Tested end to end: collected as n76310, installed as chris, owner mapped,
original kept, the one file mentioning n76310 named.

## Previous session (1.14.178) -- the gate decides, the loop acts

    # /usr/share/doc/libtiff-4.7.1/tiff is p_libtiff's own output ...
    #   removing it so this install can replace it
    ! libtiff FAILED ... gate: recognised, rounds run: 0

The repair did exactly the right thing and the package failed anyway. I
called it from the GATE -- the code that decides whether a retry is worth
attempting -- so the directory was removed before the retry loop started,
and the loop counts only what IT fixed. Nothing re-ran the phase, and the
obstacle was already gone.

The gate now only greps for the message; `_clear_stale_dest` runs inside the
loop beside the other repairs, and setting `_fixed_something=1` is what
causes the retry. A second round finds the path gone and returns 1, so the
loop breaks instead of spinning.

Two things this cost, both now asserted:

- a repair called from the gate is a bug in itself: block 375 fails if
  `_clear_stale_dest` appears with `_perm_ish=1`.
- **`_slice_fn` stops at the first line starting with `}`**, and cmd_build is
  1700 lines with several of those -- so two assertions were matching against
  an empty slice and passing. They grep the file now. A test that cannot fail
  is worse than no test.

Resume: `packagemanager late-deps --rebuild --run` -- 45 left, and libtiff
should clear itself and carry on this time.

## Previous session (1.14.177) -- the repair failed the build it was repairing

    /usr/bin/lfs-helper: line 5914: user: unbound variable
    update failed for git (exit 1)

git's install had just finished -- every hardlink, every alias, 345 files
tracked. Then yesterday's repair hook, `_clear_stale_dest "$log" "$user"`,
read a variable that does not exist: `cmd_build` calls the package user
`owner`, and `set -u` turned a successful install into a failed one with a
line number and no explanation.

Two fixes, and the second is the rule:

- `${owner:-}`, which is what that function calls it.
- `_clear_stale_dest` returns 1 on an empty user instead of running. **A
  repair must not be able to fail the thing it is repairing**: it runs after
  something already went wrong, so anything it does must be safe when its
  inputs are not what it expected.

Block 375 asserts both, and that `cmd_build` never reads `$user` at all --
checked by putting the bug back and watching two assertions fire.

Resume: `packagemanager late-deps --rebuild --run`.  git is installed
(the install completed); it will be re-checked and skipped or redone
quickly.

## Previous session (1.14.176) -- a book command that works once

The rebuild pass stopped on libtiff, 38 packages from the end:

    mv: cannot overwrite '/usr/share/doc/libtiff-4.7.1/tiff': Directory not empty

Nothing was wrong with the system. libtiff's page moves its html docs into a
versioned directory; the first install creates that directory, and the
second cannot move onto it. The destination was **the package's own output
from last time**, and a reinstall means replacing it -- but the repair gate
did not recognise the message ("gate: did not recognise this failure, rounds
run: 0"), so a 38-package pass stopped on a directory the package itself had
put there.

`_clear_stale_dest` reads `cannot overwrite '<path>'` out of the log and
removes that exact path -- **only when the package being installed owns
it**. A directory owned by anyone else is a conflict, not stale output, and
deleting it would be the worst repair available: that case warns and leaves
it. Proved on real text in block 375, all three outcomes (own output
cleared, other owner refused, unrelated failure untouched).

Resume with:

    packagemanager late-deps --rebuild --run

libtiff will be retried from its install phase; what already succeeded is
recorded and does not repeat.

## Previous session (1.14.175) -- the help was two lists, both stale

No, it was not up to date.

- The grouped `packagemanager --help` -- the part a reader actually uses --
  had no `stack`, `probe`, `late-deps`, `reclaim`, `bootstrap` or `env`.
  `stack` is the primary command of this tool. Two new groups now: "a whole
  environment at once" and "features, not files".
- The module docstring kept a **Roadmap** marking check, search,
  dependencies, install, remove and reload-pkg-list as `[TODO]` -- all six
  implemented releases ago -- and none of the twenty commands added since
  appeared at all. Replaced by a pointer to `--help` and the two design
  questions that really are open.
- `lfs-helper --help` was missing `undone`, `sort-users` and `check-login`,
  and said nothing about the chroot build's own steps (init-accounts,
  establish-ownership, seal-install-dirs, install-profile,
  repair-adoption). They are listed as what they are: dispatched by
  build-all, and `lfs-helper list` names them.

Block 375 now asks ARGPARSE for the command list -- it prints one when given
a bad command -- and requires every name to appear in the grouped help.
A list of commands maintained anywhere but beside the commands goes stale
silently; this one now cannot.

## Previous session (1.14.174) -- audiornnoise needs no second git entry

It is in gst-plugins-rs already: the element lives in **gst-plugin-audiofx**,
not in a plugin of its own, so it is one more `-p` on the entry added in
1.14.172 rather than a new checkout. Its noise model is the nnnoiseless
crate, vendored by cargo, so there is no system library to install first.

The probe grew with it -- `webrtcsink && audiornnoise` -- and `check webrtc`
lists audiornnoise among the optional rust elements, with a line saying what
it is for (noise suppression for a microphone in a call).

Three assertions in block 376 that came out of writing this:

- an element named in a probe must be asked for by some `-p`, or the check
  tests something nothing builds;
- `audiornnoise` must NOT appear as `-p gst-plugin-audiornnoise`, which is
  the mistake that looks right and fails before anything builds;
- the build and install lines must ask for the SAME plugin set -- a plugin
  compiled and not installed is the most confusing outcome available
  (checked by removing audiofx from the install line and watching it fail).

## Previous session (1.14.173) -- a plugin is a shared object

The first real gst-plugins-rs run compiled everything (5m40s, four plugins)
and died installing a STATIC library:

    failed to copy `.../libgstrsrtp.a` to `/usr/lib/gstreamer-1.0/libgstrsrtp.a`
    Permission denied (os error 13)

Two separate faults, and neither was the permission:

- **cargo-c installs a .a as well as a .so by default.** Nothing loads a
  static GStreamer plugin. `--library-type cdylib` on both the build and the
  install line, and the file that failed is never produced.
- **The repair ran ZERO rounds** ("gate: recognised, rounds run: 0") because
  cargo names the destination in BACKTICKS, on the line above the reason --
  no quotes, and no "Permission denied" on the same line, so the path
  extractor found nothing while the box still said "grant access and retry".
  It now recognises `failed to copy ... to \`<path>\`` and offers the
  destination's directory; asserted against that exact text.

/usr/lib/gstreamer-1.0 is `p_gstreamer10:nimgnu_gst`, so the .so still needs
the group -- which the repair can now grant by itself, in one round.

    packagemanager stack sway --only gst-plugins-rs --run

The compile is cached, so the retry is the install step only.

## Previous session (1.14.172) -- gst-plugins-rs, and what it is honest about

Added to sway.stack at entry 124: after gst10-plugins-bad and gst10-libav,
which it builds against, and before webkitgtk. cargo-c is already installed
(librsvg pulled it in), so nothing new is needed to build it.

It is NOT a BLFS page, so three things that a book page would settle are
ours, and each is stated where the entry is -- the suite checks that the
statements are there:

- **`ref=main` is not a pin.** Upstream tags 0.14.x for GStreamer 1.28, but
  that pairing is unverified from here, so the entry follows main rather
  than claiming a tag that may not match. Pin it once a build succeeds: the
  ref that worked is the one to write down.
- **It downloads crates at build time.** There is no offline mode, so this
  entry cannot be part of a build that has no network.
- **The plugin list is a choice.** Four are named -- webrtc (webrtcsink and
  webrtcsrc), rtp, dav1d, gtk4 (gtk4paintablesink). All of gst-plugins-rs is
  enormous and mostly irrelevant here. Add with another `-p`.

`have=/usr/lib/gstreamer-1.0/libgstrswebrtc.so`, and
`expect="gst-inspect-1.0 webrtcsink"` -- an element again, not a file.

`check webrtc` reports webrtcsink, webrtcsrc and gtk4paintablesink as
OPTIONAL (`->`, not `!!`): the plugin set is not a BLFS page and not
everyone builds it, so its absence must not fail a stack. Verified by
deleting the network warning from the stack and watching the suite fail.

## Previous session (1.14.171) -- the advice was a loop

`stack sway --only sdl3 --run` on an INSTALLED package runs `install`, which
answers "Nothing to do -- everything is installed and up to date". The expect
probe then failed and the tool recommended... the same command. Four bugs in
one screen:

- **The suggested command could not work.** A stack entry does not rebuild an
  installed package. The expect= failure now prints
  `packagemanager update <pkg> --reinstall --regenerate --run --yes`
  (`_rebuild_cmd`, the one place that knows this) and says plainly that
  re-running the entry will not help. `probe` had the same mistake for the
  installed case.
- **And it named a stack that does not exist**: `stack sway.stack --only ...`
  -- `os.path.basename(path)` without dropping the suffix, while the probe
  path next to it stripped it correctly.
- **"NOT recorded as done, so the next run rebuilds it" was false** for an
  installed package. Removed; the truth is in its place.
- **The newer-stack notice argued against itself**: `(149 entries, this file
  has 149)` for two files differing in every entry's options. It reports
  added/removed lines now, and says when the entry count is unchanged so the
  difference is inside the entries. Also `--take-new` said "149 entries now"
  two lines above a header reading "(62 entries)" -- one counts file lines,
  the other the buildable plan. One measure, one word.

For sdl3 on the machine, after `make install` and taking the stack again
(the glob fix is in the shipped file):

    packagemanager probe sdl3
    packagemanager update sdl3 --reinstall --regenerate --run --yes

## Previous session (1.14.170) -- four probes pass; both failures were misreported

With the stacks taken, `probe` runs: **ffmpeg has ALSA, opusenc, v4l2src,
vp8enc, webrtcbin, dtlssrtpenc and srtpenc are all there** -- the WebRTC
chain and the earlier ALSA work came out right. The two failures were both
described wrongly:

- **gst10-libav is not installed at all** (it was missing from the stack
  until 1.14.167), and the report said "the feature is NOT in the installed
  package" -- which sends the reader looking for a build option. A probe
  failure now checks for `pkg.lst` and says NOT INSTALLED, with "build it"
  rather than "rebuild it".
- **The sdl3 probe named one path.** SDL3 installs `libSDL3.so.0.<n>` and
  the bare `libSDL3.so` symlink is not always there, so the probe could fail
  for a reason that has nothing to do with ALSA. It globs now. A failing
  probe also prints its own first line of output, because a probe can be
  wrong about a path as easily as a package can be wrong about a feature.

On the machine:

    packagemanager stack sway --only gst10-libav --run   # not built yet
    packagemanager probe sdl3                            # after make install
    # if it still fails, sdl3 really was built before alsa-lib:
    packagemanager stack sway --only sdl3 --run

Note the take-new also brought `cfg power` and `check net-wifi` into the
stacks as unbuilt entries -- both are read-only or root-only steps and can
be run with `--only`.

## Previous session (1.14.169) -- "no probes" was the wrong half of the answer

`packagemanager probe` on the machine: *no expect= probes in the stacks*.
True, and useless -- the probes are in the SHIPPED stack files, and an
edited stack is never overwritten, so they arrived as
`/etc/pkgusr/stacks/sway.stack.new`. The tool carried probes no installed
stack had, and the message read as "nothing to check".

It now looks for `*.stack.new` carrying `expect=` and says so, with the
command to take each one. Failing that, it says probes live in stack files
as `expect="..."` and that an older stack has none -- rather than leaving the
reader to conclude everything is fine.

**On the machine**, before probing anything:

    packagemanager stack sway --take-new       # then network, services
    packagemanager probe

The whole `.new` mechanism remains on the deferred list -- three functions
move stack files and it still surprises people.  This is the second time a
feature was invisible because the stack carrying it was sitting beside the
one in use.

## Previous session (1.14.168) -- "+0 day(s)" was the whole bug, filed as fine

`late-deps ffmpeg --why` came back clean on every encoder (x264, x265,
libvpx, aom, svt-av1, opus, lame, fdk-aac, dav1d -- all days earlier) and
showed one line that should have stopped the eye:

    recommended  alsa-lib-1.2.15.3   -> alsa-lib, built +0 day(s) relative to it

A day of slack was chosen because pkg.lst is rewritten by reload-pkg-list
and --clean, so packages from one run differ by minutes. But alsa-lib a few
HOURS after ffmpeg is the original bug exactly, and the slack filed it as
fine. An hour covers the rewrite noise; the report prints hours below a day,
and marks a gap under six as "same session: only a probe can settle it",
because two packages built in one session cannot be ordered by mtimes at
all.

`packagemanager probe` is that answer: it runs every `expect=` in the
installed stacks against what is installed, and a failure names the rebuild.
Timestamps are evidence, a probe reads the artifact.

    packagemanager probe            # all of them
    packagemanager probe ffmpeg     # one

## Previous session (1.14.167) -- gst10-libav was in no stack

Right: nothing built it. It carries the ffmpeg-backed decoders (avdec_h264,
avdec_aac and the rest), so without it H.264 -- most video on the web -- is
decoded by nothing, and the symptom is a black frame rather than an error.

`book gst10-libav` now sits after ffmpeg (entry 1b) and gst10-plugins-base,
which it needs, named as an entry rather than left to a dependency plan so
that stays true. Resulting order: ffmpeg 90, base 116, bad 122, **libav
123**, webkitgtk 125, mpv 126.

Its probe is an element, for the same reason as the others: the package
installs libgstlibav.so either way, and whether `avdec_h264` registers
depends on what ffmpeg was built with -- the thing that was wrong about
ffmpeg and ALSA. `check webrtc` reports it too, so a missing decoder shows
up beside the camera and the microphone.

Block 376 asserts both the order and the probe, and names it as MISSING when
the entry is absent (checked by deleting the line).

On the machine: `packagemanager stack sway --only gst10-libav --run` after
the reclaim and the rebuild pass.

## Previous session (1.14.166) -- repair the chown, not one package at a time

The rebuild pass stopped on glib2 with the SAME cause as gst-plugins-bad:
`/usr/include/glib-2.0` is `p_linux-headers`, from lfs-kernel's old
`chown -R "$_hacct" /usr/include`. The whole include tree is that package's,
so every package that ships a header fails to reinstall. The tool fix
(1.14.158) stops it happening again; the machine needs the ownership put
back.

`packagemanager reclaim` was the right repair but took a named list, and
finding the victims means finding them first. It takes `--all` now: every
installed package, checked against its own pkg.lst, and a package with no
manifest is skipped quietly rather than reported as an error ninety times.

**The repair, in order:**

    packagemanager reclaim --all --run       # ownership back, from manifests
    lfs-helper verify --fix                  # groups, modes, install dirs
    packagemanager late-deps --rebuild --run # resume; glib2 first again

Tested against the exact shape: a directory and a file under
/usr/include/glib-2.0 owned by p_linux-headers but recorded in p_glib2's
manifest -- both returned, directory included.

Also: `_slice_def` (slicing a python def for the suite's assertions) was
defined inside one block and used by another, where it returned nothing and
made two assertions pass vacuously. It is in the preamble now, beside
`_slice_fn`.

## Previous session (1.14.165) -- the optional edge is the whole point

The clusters came out right (freetype2+harfbuzz before fontconfig and cairo,
libdrm+libxcb before mesa, base before bad), and one thing was still
backwards: `mpg123` was rebuilt BEFORE `pulseaudio`, and mpg123's missing
feature IS pulseaudio. The order graph was required+recommended, which are
the edges that break a BUILD -- while the edges this whole pass exists for
are the optional ones.

The rebuild order now uses required + recommended + optional. That makes the
graph much more cyclic, which is honest rather than convenient, and the SCC
pass already handles it; inside a component the strong edges still decide,
because those are the ones that fail a build rather than a feature.

`--why` earned its keep immediately: libxcb RECOMMENDS mesa and mesa
REQUIRES xorg7-lib and libdrm, so libxcb/mesa are one genuine cycle -- the
plan puts libdrm and libxcb before mesa, which is the best an ordering can
do there. It also showed the unresolved names are what they should be:
Doxygen, libunwind, lm-sensors, Valgrind -- packages that are not installed.

## Previous session (1.14.164) -- order the clusters, not the nodes

Still wrong: freetype2 and harfbuzz came out LAST, after fontconfig and
cairo, which both require freetype2. The cycle-break picked one node and then
went back to the ready scan, which strands the rest of the cluster at the
end -- picking fontconfig out of the cluster made everything that depended
on it ready, and freetype2 was left over.

A cycle has to be ordered as a UNIT. Tarjan's strongly connected components,
computed iteratively (this graph has 400 nodes, so recursion is not an
option), condensed into a DAG that sorts by construction; inside a component
the rule is unchanged, least dependent and most depended on. The
freetype2/harfbuzz component now comes out before fontconfig and cairo,
asserted in block 375 on that exact shape.

`late-deps --why <pkg>` prints the edges actually used for a package -- what
each dependency resolved to, how many days apart they were built, and which
names resolved to nothing. When a position still looks wrong, that is the
output to read: an edge that does not resolve is invisible to the sort.

## Previous session (1.14.163) -- a cycle broken alphabetically is not an order

Still wrong, and visibly: `gst10-plugins-bad` before `gst10-plugins-base`,
`cairo` and `fontconfig` before `freetype2`. Those are CLUSTERS with no entry
point -- base needs mesa, mesa needs libxcb, bad needs base -- so the
topological sort ran out of ready nodes and the fallback was
`sorted(left)[0]`. Alphabetical order produced exactly the mistake the plan
exists to prevent.

The pick is now "least dependent, most depended on": fewest unmet
dependencies inside the cluster, then the most packages waiting for it. base
beats bad (bad needs base, nothing needs bad); libxcb beats mesa. And the
cycle is NAMED in the output, with the note that a cycle can need two passes
-- breaking one silently makes the second pass look like a failure.

Block 375 asserts it on the failing shape itself: three packages in a real
cycle, and base must come out before bad.

Also: "103 dependency names could not be matched" read as 103 problems. It
now says what it means -- a name that matches no INSTALLED package is
usually one that is not installed, and a package that is not there cannot
have been built after anything. A name you know IS installed appearing there
is the interesting case, and worth reporting.

## Previous session (1.14.162) -- the order was wrong, and the 119 explain why

"Are we sure about the ordering?" No, and the tool had already said why in
its own last line: *119 dependency names could not be matched to a package*.
An edge that does not resolve is an edge that does not exist, so the
topological sort ran on what was left -- and put `gst10-plugins-bad` before
`gst10-plugins-base`, which it REQUIRES, and `fontconfig` before
`freetype2`.

The mapping was being guessed by normalising strings: a dep is written as
the page TITLE (`gst-plugins-base-1.28.1`, `FreeType-2.14.1`), a package
directory is the page ID (`gst10-plugins-base`, `freetype2`), and no amount
of lowercasing bridges that. Every script already records `name_version` --
the tarball base, which IS the title. `_dep_index` builds the mapping from
that, and both cases now resolve (asserted in block 375 against a real
resolve, not a grep).

Two more, from the same run:

- **`--reinstall` is not a question about versions.** With no recorded
  version, `update curl --reinstall` answered "nothing to update, 1 it
  cannot judge" and did nothing -- for 28 packages whose records predate the
  tool. `--reinstall` now plans the rebuild regardless of what is recorded.
- **The rebuild order uses required + recommended.** mesa RECOMMENDS libxcb,
  so ordering by `required` alone rebuilds mesa against the old libxcb.
  Cycles are expected on that graph and are broken by picking one.

Re-run `late-deps` after installing this: the order will differ, the
unmatched count should drop a long way, and what is left in it is worth
reading.

## Previous session (1.14.161) -- there is no host any more

The machine boots on its own now, and packagemanager still printed, before
every single command:

    These tools differ from the copies on the host: blfs, lfs, ...
      On the HOST, run:  lfs build-system sync-tools --run

`/usr/share/lfs/tool-stamps.json` is written by `lfs build-system
install-tools`, which runs on a host against a chroot. After the system
boots, `make install` on the machine itself replaces the tools and nobody
updates the stamp -- so all seven "differ", and the advice names a host that
no longer exists.

- `make install` writes the stamp now: it records what is installed, so
  whoever installs it owns it.
- The check returns early unless it is actually in a chroot
  (`/proc/1/root` is not this root). No outside, nothing to be behind.

On the machine: `make install` from the repo once, and the warning goes for
good. `sync-tools` remains correct for the case it was written for -- editing
the tools on a host and refreshing a chroot.

## Previous session (1.14.160) -- the rebuild pass rebuilt nothing

Two bugs in 1.14.159, both visible in one run on the machine:

- **`install` does not rebuild.** The plan emitted
  `packagemanager install <pkg> --run --regenerate`, which answered
  "Nothing to do -- everything is installed and up to date" 28 times in a
  row -- correctly, and in a way that read like a successful pass. The verb
  that rebuilds at the same version is
  `packagemanager update <pkg> --reinstall --regenerate --run --yes`, and
  that is what `_rebuild_cmd` emits now, in the plan and in the per-package
  hint.
- **A recommended edge is still a dependency.** The cycle test walked only
  `required=`, so the report advised `put mesa before libxcb` -- and mesa
  needs libxcb; BLFS lists that edge as recommended. Same for cairo -> glib2,
  which is why glib2 showed up as orderable. Advice that cannot be taken is
  worse than none, so the "does an order exist" walk uses
  required + recommended.

Also widened the build-tool list (mako, setuptools, wheel, hatchling,
pytest, gi-docgen, gperf, unifdef) -- those were showing as missing features.

## Previous session (1.14.159) -- three answers, not one list

`late-deps` on the real machine returned 40 packages in one list, and they
are not one problem:

- **An order exists** (ffmpeg/alsa-lib, gst-plugins-bad/libnice, mpg123,
  libheif, pipewire, sdl3, v4l-utils): the dependency does not need the
  package, so it can be built first. Each line now says
  `in the stack: put alsa-lib, sdl2 before ffmpeg` -- a stack edit, fixed
  for the next machine.
- **No order exists** (glib2/cairo+dbus, libxcb/mesa, xwayland/mesa,
  xorg7-lib/dbus): the dependency REQUIRES the package. cairo cannot precede
  glib2. The only fix is a second pass, and saying "move it earlier" would
  be advice that cannot be taken. Detected by walking each package's own
  `required=` list.
- **Documentation and build tools** (graphviz against six packages,
  docutils, ruby, git, fcron, cython): rebuilding gains documentation, not
  features. Summarised in one line; `--include-docs` to see them.

`late-deps --rebuild` prints the plan in DEPENDENCY order -- rebuilding a
library after the thing that links it means doing it twice -- and
`--rebuild --run` carries it out, stopping at the first failure with what is
left. A finished stack run now ends by naming the question, because a second
pass is part of the job rather than an afterthought.

For the machine: `alsa-lib` before `ffmpeg`/`sdl3`/`v4l-utils`/`pipewire` is
already the stack's order since 1.14.156, so those entries only need the
rebuild. The circular ones stay circular -- they need the second pass on
every fresh build, which is what the reminder is for.

## Previous session (1.14.158) -- one line owned every header on the system

gst-plugins-bad could not install `mse-enumtypes.h` into
`/usr/include/gstreamer-1.0/gst/mse`, because that directory belonged to
**p_linux-headers**. The repair handed it one file per round; after three
rounds the bundled-copy heuristic concluded meson was vendoring
linux-headers. Every step of that reasoned correctly from a wrong fact, and
the wrong fact was one line in `lfs-kernel`:

    chown -R "$_hacct:$_hacct" /usr/include

A package owns what it INSTALLED, not the directory it installed into.
`make headers` output is now listed with `find -printf '%P\n'` before the
copy and only those paths are chowned; `/usr/include` itself stays root's,
because every package that ships a header shares it.

**Repair on the machine** (the ownership is already wrong there):

    packagemanager reclaim gstreamer10 --run
    packagemanager reclaim gst10-plugins-base --run
    packagemanager reclaim gst10-plugins-bad --run
    packagemanager install gst10-plugins-bad --run --regenerate

`lfs-helper fix-ownership --run` is the wider net if other packages' headers
were taken too -- everything under /usr/include that is not a kernel header
is suspect on that machine.

### packagemanager late-deps

The audit the last two sessions kept needing. Every generated script records
the page's own required/recommended/optional lists; every pkg.lst is written
when the install finished. So: which packages were built before something
they can use?

    packagemanager late-deps              # all of them
    packagemanager late-deps ffmpeg       # one
    packagemanager late-deps --kind recommended,optional,required

It reports the gap in days and the rebuild command, ignores gaps under a day
(pkg.lst is rewritten by reload-pkg-list, so packages from one run differ by
minutes), and counts the dependency names it could NOT match to a package --
a silent miss would under-report exactly what is being looked for. Tested
against a synthetic tree reproducing both the ALSA and the WebRTC cases.

## Previous session (1.14.157) -- a library is not a plugin

The browser: "GstWebRTC plugin not found." gst-plugins-bad *is* installed,
`verify` is clean, and `libgstwebrtc-1.0.so` is in its file list -- because
that library is always built. The **webrtcbin element**, which is what a
browser loads, is compiled only if libnice was there at configure time. Their
`p_gst10-plugins-bad/install_last` says `generated by blfs 1.14.43`: built
long before the WebRTC block was added to the stack, so libnice did not
exist yet. Same shape as the ALSA bug, one level further in -- the artifact
that proves the feature is an entry in the element registry, not a file.

- `opus` and `libvpx` are stack entries now, before gst10-plugins-base and
  -good: a call negotiates Opus and VP8, and both plugins are autodetected.
- `expect=` probes on all three gst entries, by element:
  `gst-inspect-1.0 webrtcbin && dtlssrtpenc && srtpenc` for -bad,
  `opusenc` for -base, `v4l2src && vp8enc` for -good.
- **`check webrtc`** (`stacks/webrtc.sh`): the whole chain in one report --
  eight elements with the library each needs and the command that rebuilds
  it, the .pc files, /dev/video* and the video group, what
  `p_webkitgtk/install_last` was built with, and a warning when a package's
  script is OLDER than `nice.pc` (built before its dependency existed --
  exactly this bug, detectable from mtimes).
- machine.conf gained a commented `[gst10-plugins-bad]` block: setting
  `webrtc = enabled` turns silent autodetect into a build failure. Commented
  because the option NAMES are machine-checkable, not memorable -- it says
  how to confirm them against the source on disk.

Fix on the machine: `packagemanager stack sway --only gst10-plugins-bad --run`
(libnice, libsrtp and usrsctp are installed now, so it picks them up), then
`--only webrtc --run` to confirm. webkitgtk does not need rebuilding for the
element -- the plugin is loaded at run time.

## Previous session (1.14.156) -- ffmpeg and SDL3 without ALSA

Both autodetect ALSA, and both were built before alsa-lib existed. `book
alsa-lib` sat at entry 7, while ffmpeg is built inside **mesa's** plan
(entry 2) and SDL3 inside gstreamer's. They configured cleanly, installed
cleanly, passed `have=`, and had no sound. Nothing failed, so nothing said
so.

The stack already stated the rule, for harfbuzz: an optional dependency of
something built inside a plan can only be placed by ENTRY ORDER, because a
plan builds its own tree in the book's order, not the stack's. It was simply
not applied to audio.

- `book alsa-lib` is entry 1b now, before mesa. `ffmpeg` and `sdl3` are
  named as entries there too, so they are built in this order rather than
  wherever a plan happens to reach them.
- **`expect="<shell>"` on a stack entry**: run after the entry installs, and
  it must succeed. A failing probe does NOT record the entry as done, so the
  next run rebuilds it. Two are shipped:
  `ffmpeg -hide_banner -devices | grep -qw alsa`, and for SDL3 (which
  dlopens libasound rather than linking it, so ldd says nothing)
  `strings /usr/lib/libSDL3.so | grep -q libasound`.
- Fix on the machine: `packagemanager stack sway --only alsa-lib --run`
  (already built -- it will say so), then
  `--only ffmpeg --run` and `--only sdl3 --run`. Anything else that wanted
  ALSA and was built early -- mpv, pipewire, gstreamer -- is worth the same
  treatment; `--only <name> --run` each.

Block 375 of the suite asserts the order out of the stack file itself, and
fails when alsa-lib is moved back after ffmpeg (checked both ways).

## Previous session (1.14.155) -- a package is not a service

The network stack ran on a second machine and stopped at 9 of 9:

- **`install-service-dhcpcd` was missing from blfs-bootscripts.** The dhcpcd
  package installs no service script; `/lib/services/dhcpcd` comes from that
  target, so `SERVICE=dhcpcd` and the wpa hand-off had nothing to run.
  Adding `book dhcpcd` in 1.14.153 was half the job. Re-run
  `packagemanager stack services --only blfs-bootscripts --run`.
- **`check net-wifi` failed the stack for the user's own files.** No
  /etc/sysconfig/ifconfig.wlan0 is not something the stack was ever going to
  write -- it holds an SSID. Two levels now: `!!` is the stack's and exits 1,
  `->` is yours and does not. The step completes and still lists the work.
- **Two contradictory lines about one file.** It said
  `wpa_supplicant-__wifi0__.conf has no psk` and, two lines later, that it
  `holds a key and is world-readable`. The permission warning is now tied to
  actually holding a key, and a `__placeholder__`/example/template name is
  reported as a template to copy rather than a broken config.

## Previous session (1.14.154) -- power as a group, and two dead udev rules

The reference machine delegated halt/poweroff/reboot/pm-suspend by hand:
`4550 root:nimgnu_power`, plus a boot script re-applying modes on
/sys/power/state because /sys does not survive a reboot. That is the same
shape as `seatd-<user>` and it was in no stack. It is `cfg power` in
services.stack now (`stacks/power.sh`): the group (from `collector_prefix`,
or `POWER_GROUP`), the desktop user's membership read back afterwards, the
setuid bits with the mode confirmed, and **one** boot script in
`/etc/rc.d/init.d/power-perms` symlinked into `rcsysinit.d` -- the machine
had a second full copy under `rc3.d`, which is a second place to edit.

Two pieces of that setup could never have worked, and both looked like
configuration that did:

- `SUBSYSTEM=="power", KERNEL=="state", MODE="4550"` -- /sys/power/state is a
  kernel attribute with no uevent, so udev is never asked about it. And the
  mode is wrong twice: setuid is meaningless on a sysfs file, and 550 has no
  write bit, so a group member could not write `mem` to it even if the rule
  had applied. The boot script is what does the work, and it uses 0660.
- `ACTION=="add", KERNEL=="bootlog", OWNER="nimgnu_bootlog"` -- /run/bootlog
  is an ordinary file the bootscripts write, not a device. No device, no
  match, no owner ever applied: **the `nimgnu_bootlog` account is not needed
  and never was.** Where the boot log goes and who may read it is `BOOTLOG`
  in /etc/sysconfig/rc.site.

`power.sh` reports both if it finds them in /etc/udev/rules.d, and does not
delete anything.

## Also this session (1.14.153) -- dhcpcd was never in the stack

`wlp3s0` exists, so 7.2.4 booted and the driver found its firmware. The link
would not go anywhere because **nothing in any stack installs a DHCP
client** -- the network stack had wpa_supplicant, libnl, libmnl, libnftnl,
iptables and net-tools, and `lfs config network dhcp` deliberately writes no
static interface files *because* a client from BLFS is supposed to follow.
Nothing followed. `book dhcpcd` is in `network.stack` now.

Beside it, `check net-wifi` (`stacks/net-wifi.sh`): a read-only report of
the five separate things that each produce "wifi does not come up" --
missing client, missing `ifconfig.<iface>`, a file named for the wrong
interface, missing per-SSID config, or a `SERVICE=` no installed script
implements. It reads the wireless interface names out of `/sys/class/net`
(a file called `ifconfig.wifi0` does nothing for `wlp3s0`) and the hand-off
variable out of `/lib/services/wpa` rather than remembering which release
uses which. It also flags a world-readable psk file.

The new script needed no list edits: the Makefile and the chroot refresh
both walk `stacks/` (the "derive lists" rule, already applied there).

## Also this session -- the regulatory database, and a latent failure

The run came back healthy: 686 of 723 amdgpu declarations installed, 32 of
50 iwlwifi, the four embedded blobs present, `iwlwifi-cc-a0-77.ucode` flat
where the loader wants it. One item left, and it was homework rather than a
fix:

- **wireless-regdb is now installed by the tool.** `_install_regdb` reads
  kernel.org's listing, takes the newest release, unpacks it as
  `p_linux-firmware` and installs `regulatory.db` + `.p7s` into
  /lib/firmware -- one directory, one owner. `REGDB=yes` in kernel.conf
  (default), and `--fix` does it. Tested against a local http mirror; the
  sed that parses **kernel.org's real listing is unverified** (no network to
  kernel.org from the authoring sandbox), and if it comes back empty the
  command says so and prints the two manual commands.
- **A latent failure in the shipped config.** 1.14.147 put
  `regulatory.db*` in FIRMWARE_ONLY. A pattern that matches nothing in the
  repository is an error, so the next full `lfs-kernel firmware` would have
  failed outright, blaming the pattern. Removed from the shipped value, and
  `_install_firmware` now recognises an entry that lives elsewhere and
  installs it from there instead of failing.
- **A message that contradicted the note above it.** The candidate section
  said the boot list "is the reliable one" two lines under a note saying a
  chroot's boot list is the host's. In a chroot it now says to boot this
  kernel and run it again there.

## Previous session (1.14.152) -- the chroot host is another machine

`ls` settled the wifi question: `/lib/firmware/iwlwifi-cc-a0-77.ucode` is
there, flat, 1368100 bytes -- the file 7.2.4 asked for. It is in place, and
`intel/iwlwifi/` has the -50 to -77 series beside it. Nothing more to
install for the AX200; **boot 7.2.4 and look**.

Three things the report was getting wrong about its own authority:

- **A satisfied request was skipped in silence**, so a run with everything
  in place looked identical to one that had not looked. Boot and config
  lines now print `ok ... installed now`, which in a chroot is the only
  reassuring thing on the page.
- **The candidate summary counted only what is absent.** It says "1 of 2
  declared file(s) not installed" now, so a module with most of its
  declarations present reads as such.
- **The chroot note was too weak.** The host may be another distribution on
  other hardware -- it is here -- in which case its boot log can neither
  confirm nor deny anything about this tree. And no static check can
  promise a driver will find its firmware: iwlwifi derives the name from
  the RF and CRF ids it reads off the card at run time. The report says
  both.

Still open for the machine: `regulatory.db` (wireless-regdb, not
linux-firmware) and the boot itself.

## Previous session (1.14.151) -- say what IS there

The 7.2.0 boot logs no iwlwifi firmware failure, so that kernel's wifi
firmware loaded: a cc-a0 blob is on this disk somewhere, and 7.2.4's driver
would not take it. The report said nothing about either fact. It now checks,
for every proven miss, the two things that change what you do next:

- **the same file under another path.** A `FIRMWARE_ONLY` entry keeps the
  repository's path, so `intel` installs
  `/lib/firmware/intel/iwlwifi/iwlwifi-cc-a0-77.ucode`, and the loader asks
  for `/lib/firmware/iwlwifi-cc-a0-77.ucode` and nothing else. `--fix`
  copies it into place, no network and no repository needed.
- **an older firmware API installed.** `iwlwifi-cc-a0-72.ucode` present
  while the driver requires 77: the number is the API the driver demands and
  it does not fall back, so the answer is a newer checkout, not a different
  path. The line names the sibling that is there, and the newest three the
  checkout has.

`_fw_neighbours` returns the path in `_FW_LOCAL` rather than on stdout --
the first version had the caller's `$(...)` swallow the whole explanation
along with it, so the report said only "installed".

## Previous session (1.14.150) -- two bugs the chroot run exposed

The modules scan worked and printed 56 MISSING lines. Both problems were in
how that list was produced and presented.

- **`git ls-files` lies under a sparse index.** Git collapses every excluded
  directory into a single entry, so the listing was `intel/` and every blob
  under it looked absent: 56 files reported as "this checkout has no file by
  that name" while they were all in the repository. `_fw_index` now uses
  `git ls-tree -r --name-only HEAD`, which reads the commit and no sparse
  setting touches. (Reproduced here: `ls-files --sparse` prints `intel/`.)
- **A declaration is not a failure.** `modinfo -F firmware amdgpu` lists
  firmware for every chip amdgpu supports -- Vega, Sienna Cichlid,
  Aldebaran, gc_12_1_0 -- and iwlwifi lists five RF families this laptop
  does not have. All true, and the conclusion ("56 missing") was wrong: a
  driver loads what its own chip needs. `modules` lines are now collected
  per module and summarised in one line each as CANDIDATES; only `boot` and
  `config` lines are treated as things to fix. `--fix --all` installs the
  declared ones anyway.

The `boot` list stays the reliable one, which is why booting 7.2.4 and
re-running is still worth doing: it named `iwlwifi-cc-a0-77.ucode` exactly.

## Previous session (1.14.149) -- answer in the chroot

"Why not make me able to run in chroot?" -- fair. Refusing to answer where
the work happens is not an answer, and dmesg was the wrong source anyway: it
describes the boot that is running, and firmware is requested at boot, so it
can only ever report the PREVIOUS kernel's experience.

`--missing` now derives the list from three sources and labels every line
with the one that named it:

- `boot` -- the failed loads in dmesg (in a chroot, the host's; said so)
- `modules` -- every modalias under /sys/devices resolved against
  `/lib/modules/<ver>/modules.alias` (`modprobe -S <ver> -R`), then
  `modinfo -k <ver> -F firmware`. This machine's hardware, this tree's
  kernel, no boot required.
- `config` -- `CONFIG_EXTRA_FIRMWARE`, which a running kernel never
  complains about because the image already carries it.

Which kernel's modules: `VERSION` from kernel.conf first, then `uname -r`,
then the newest under /lib/modules -- and the report names it. `uname -r` in
a chroot is the host's.

Two more things the output showed:

- **`regulatory.db` is not in linux-firmware at all.** It is released as
  wireless-regdb, so "update the checkout" was advice that could never
  work. There is now a small table of firmware that lives elsewhere, with
  the URL and the two commands.
- **A nested blob with a flat request cannot be expressed in
  FIRMWARE_ONLY.** An entry is copied to the same relative path, so
  suggesting `intel/iwlwifi` for a driver asking for
  `iwlwifi-cc-a0-77.ucode` would install it where the loader never looks.
  The suggestion is now only made when the paths match, and the mismatch is
  named. Relatedly, `_install_firmware` copied a nested entry with
  `cp -a $src/$d /lib/firmware/`, dropping the directory (the deferred item
  from 1.14.147): it uses `cp -a --parents` from inside the checkout now.

## Previous session (1.14.148) -- three bugs in 1.14.147's firmware command

All three were found by the user's first real `firmware --missing --fix`, and
the first two are old rules re-broken:

- **A swallowed error became a confident wrong answer.** `git -C "$src"
  ls-files 2>/dev/null` returns nothing and rc 128 when the repository
  belongs to `p_linux-firmware` and the command runs as root (`fatal:
  detected dubious ownership`). The empty result was printed as
  "linux-firmware does not have a file by that name at all", about
  `regulatory.db`, which is in the repository. There is now one `_fw_index`,
  it passes `-c safe.directory=$src`, and a failed lookup reports UNKNOWN
  with git's message rather than "absent".
- **A check that did not know what it was measuring.** `dmesg` is a syscall
  against the running kernel, so in a chroot it works and answers about the
  host's boot. `--missing` now detects the chroot and says the list is the
  host's.
- **`local a="$2" d="/lib/firmware/$a"`** reads `$a` before that same
  `local` assigns it; `set -u` killed `_fw_place` on its first real call.
  Split into two statements.

Also: `--fix` no longer touches the sparse checkout at all. It read one blob
with `git show HEAD:<path>`, because the old path widened the checkout and
fell back to `sparse-checkout disable` -- which in cone mode would have
materialised all ten gigabytes to install one 2 MB file. And an unchanged
`FIRMWARE_ONLY` is no longer printed as though it were a fix.

Tested here: all four `_fw_place` branches (on disk, index-only,
nested-repo-path to flat-request, absent), the ownership failure, and blocks
109, 374, 375.

## Previous session (1.14.147)

- `lfs-helper setid [--run]`: the setid ledger is no longer emptied by the
  one notice that prints it. `setid` lists what was refused, checks a small
  on-disk list (su, passwd, chfn, chsh, gpasswd, newgrp, newuidmap,
  newgidmap, dbus-daemon-launch-helper) for the case where nothing was
  recorded, and `--run` chowns to root, sets the mode, and reads it back.
  `verify` now counts outstanding requests as a problem.
- The **install** wrapper records refused setid modes, against the file that
  actually landed, and only after the install succeeded. The chmod wrapper
  had done this since 1.14.82; the same rule, one of two places.
- `lfs-kernel firmware` (install firmware with no kernel build) and
  `lfs-kernel firmware --missing [--fix]`: reads the failed loads out of
  dmesg, finds each file in linux-firmware's git *index* (a sparse checkout
  has removed the very file being looked for), installs it at the path the
  driver asked for, widening the sparse checkout by that one path, and
  confirms the copy. The firmware functions were hoisted above the build to
  make this reachable without one.
- `lfs-kernel --help` derives its own slice from the header instead of a line
  range that a new command pushes out of view.
- Suite: `--list/--from/--to/--only`, a `skip()` counter, rc.site skips with
  a reason, and two new blocks (374, 375). Blocks 109, 293, 373, 374, 375,
  204 run green here; the rest of the suite was not run.

## Previous session (1.14.146)

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

## 1.14.370 -- SDL3_mixer

- sway.stack: `git sdl3-mixer` (libsdl-org/SDL_mixer, ref=release-3.2.4 --
  GitHub's latest release, read via the /releases/latest redirect), after
  sdl3-image and sdl3-ttf.  CMake with tests and examples off.  Read from
  the release's CMakeLists: built-in WAV/AIFF/VOC/AU, dr_flac, dr_mp3,
  stb_vorbis, timidity; libFLAC/mpg123/vorbisfile/opusfile/xmp/gme/
  fluidsynth/wavpack are optional and, without SDLMIXER_STRICT, a missing
  one is a status message, not an error.  Not built here.
- Noticed: SDL_image's latest release is 3.4.8; the stack pins 3.2.4.

## 1.14.369 -- fcron reinstall, run-parts, and `lfs-kernel promote`

**fcron.**  Reinstall failed: `install: cannot remove '/usr/bin/fcrontab':
Operation not permitted` -- fcrontab is root 6755 after the first install,
and the lease hands a root setid file only to the package setid.conf names.
fcron had no line.  The page's run-parts (and the cron.* folders the
system table calls) had never been installed, and the systemd book does not
pass --with-systemdsystemunitdir=no.

- setid.conf: fcrontab 6755 root:fcron (what the machine has), fcrondyn and
  fcronsighup with mode `-` = "the mode it had before the phase": the lease
  ledger records it, lease_settle uses it.  packagemanager's hand-back skips
  chmod for `-`; shadow-pam.sh skips `-` lines.
- shadow-pam.sh read FOUR columns since the package column arrived
  (1.14.310): group was "-|shadow", every chown asked for that group and
  failed (a warning only).  Reads five now.
- configure_args merge: compared flags as name=value, so
  --with-systemdsystemunitdir=no looked for an opposite that no page writes,
  and a book value for the same flag stayed -- after ours, so it won.  Now by
  name: the opposite form AND the same flag with any value are removed
  before ours goes in.  Tested both ways.
- package-fixes.conf [fcron] configure_args = --with-systemdsystemunitdir=no.
- services.stack: `cfg fcron-periodic` after fcron (stacks/fcron-periodic.sh):
  /usr/bin/run-parts exactly as the page writes it (replaced if it differs),
  /etc/cron.{hourly,daily,weekly,monthly} 754 if missing, systab.orig with
  the page's four lines ONLY if there is none (an existing one is the
  user's; it says whether it calls run-parts).  expect= run-parts + weekly.
  Tested in a scratch root: first run writes, second changes nothing,
  run-parts runs a job and skips its .bak.

**lfs-kernel promote [ver|file] [--run].**  With KERNEL_NAME=vmlinuz_new a
build never becomes the boot default; the ESP had collected vmlinuz.back,
vmlinuz_new_old and friends from doing it by hand.
- Reads each image's release from the bzImage header (offset 0x20E, as
  file(1) does), refuses without /lib/modules/<release>, keeps vmlinuz as
  vmlinuz_old, writes vmlinuz (via .tmp + mv, compared after) and
  vmlinuz-<release> for verify.  Says how to set KERNEL_NAME=vmlinuz and
  names leftover empty-version files.  Dry run without --run.  Skips the
  version lookup, account creation and src dir like the other reports.
- Install: the version comes from the built tree
  (include/config/kernel.release); an empty one refuses instead of writing
  vmlinuz-, config-, System.map-.
- Tested on a scratch ESP with fake bzImages: dry run, run (7.2.11 ->
  vmlinuz, 7.2.6 -> vmlinuz_old), rerun = nothing to do, missing modules
  refused.

## 1.14.368 -- evtest

- diag.stack: `git evtest` (gitlab.freedesktop.org/libevdev/evtest,
  ref=evtest-1.35), after usbutils/pciutils.  autotools: autogen.sh runs
  configure with --prefix=/usr; no library dependencies; the man page only
  when asciidoc + xmlto exist.  freedesktop's GitLab refuses automated
  reads from the sandbox, so the tag is from knowledge, not checked here:
  `packagemanager stack diag --check-refs` confirms it on the machine.

## 1.14.367 -- `update` for stack tarball entries (yt-dlp)

`update --run --yes yt-dlp`: "looking up yt-dlp in the book", then "1 not
in the BLFS book at all" and nothing.  yt-dlp is a `tar` entry of
media.stack (a pinned GitHub release tarball); update knew book pages and
git clones only.

- _update_tar_packages(), first thing in cmd_update after --stack
  expansion: for each named package whose stack entry is `tar`, a GitHub
  release URL (github.com/O/R/releases/download/TAG/...) is compared with
  _github_latest_tag() -- the /releases/latest redirect read without
  following it (pre-releases excluded); offline fallback: newest
  non-rc/beta/nightly tag from ls-remote.  Same tag: "is the latest
  release".  Newer: the entry with TAG replaced in every option (url, pkg)
  is generated and built via install_local("update"); after success the
  pin moves in the stack file (only the entry's own lines, .bak kept).
  Non-GitHub tarballs: says where the pin is and the --only command.
- _stack_git_entry(name, with_file=True) returns (entry, stack file).
- Tested: copy of media.stack + avoid.stack, mocked latest 2026.10.05 --
  dry run text; run builds .../2026.10.05/yt-dlp.tar.gz and
  pkg=yt-dlp-2026.10.05.tar.gz, verb update, stack diff = the two lines.
  The real lookup from the sandbox returned 2026.08.19 (= the pin).

## 1.14.366 -- wl-mirror

- sway.stack: `git wl-mirror` (github.com/Ferdi265/wl-mirror, ref=v0.18.5,
  the latest release), after slurp.  CMake; wayland-protocols and
  wlr-protocols are git submodules (proto/ uses them when their .git
  exists), and lfs-phases clones with --recurse-submodules.  Requires
  wayland-client/-egl, egl, glesv2 (mesa); WITH_GBM=ON adds gbm + libdrm
  (needs=mesa,libdrm); INSTALL_DOCUMENTATION=ON uses scdoc, which is an
  earlier entry of the same stack.  INSTALL_EXAMPLE_SCRIPTS off: wl-present
  needs pipectl, which no stack builds.
- Read from the project's CMakeLists (top, deps/, proto/); not built here.

## 1.14.365 -- the shipped backup.conf and kernel.conf follow the machine

The user's installed copies were ahead of the shipped ones (make install
had left both as .new):

- backup.conf: `/usr/share/vim/vim92/colors/restored.vim` in [system:vim];
  [system:accounts] commented out (a new system gets its accounts from its
  own build; old passwd lines bring back uids the new tree does not use).
  lfs-backup cuts every line at `#`, so the block is simply skipped.
- kernel.conf: CONFIG_SET gains BTRFS_FS=y, built in -- the new system's
  root is btrfs and nothing loads modules before / is mounted.

## 1.14.364 -- Errno 99 is IPv6; get-sources crashed on its own counter

Second get-sources run: all 35 GNU/savannah files failed every try with
`[Errno 99] Cannot assign requested address` (twice `timed out`), then
`TypeError: 'int' object is not callable`.

- The crash: cmd_bs_get_sources counted failures in a local `fail`, which
  shadowed fail() -- the md5 step called the int.  Counter is `nfail` now.
  With files missing, the md5 check is skipped and the message says MISSING
  (it blamed "a mirror returning an error page" for files that were absent).
- Errno 99 (EADDRNOTAVAIL) on connect: an IPv6 address the machine cannot
  send from.  Python's create_connection reports the FIRST error, hiding
  what IPv4 did.  _fetch_first now switches the process to IPv4
  (_force_ipv4 wraps socket.getaddrinfo) on EADDRNOTAVAIL/ENETUNREACH,
  says so once, and retries the same URL uncounted.
- _alt_urls: ftp.gnu.org/gnu/X -> ftpmirror.gnu.org/X (GNU's redirector);
  download.savannah.(non)gnu.org/releases -> download-mirror.savannah.gnu.org.
- Last resort, after every source failed in Python: the host's wget
  (`--tries=3 --timeout=30`, into .part, renamed on success).
- Tested with mocks: alt URL mapping; Errno 99 -> IPv4 -> success, and
  getaddrinfo returns only AF_INET afterwards; all-Python-fail -> wget tried
  in order, mirror succeeds.  Not tested against the user's network.

## 1.14.363 -- get-sources retries; ~lfs/.bashrc gets the configured triplet

New build (13.1-sysv on nvme0n1p9): get-sources failed half the GNU
tarballs with `<urlopen error [Errno 99] Cannot assign requested address>`
while other files from the same hosts came through.

- _fetch_first(sources, dest): per source up to 3 tries, pausing 3s/8s on a
  network error; an HTTPError (404 = this mirror does not have it) is final
  for that source and the next is asked at once.  After the loop, one more
  round for what still failed (after 20s), then the names that are still
  missing and the command to resume (existing files are skipped).
- 4.4: ~lfs/.bashrc was the book's text: LFS_TGT=$(uname -m)-lfs-linux-gnu
  and MAKEFLAGS=-j$(nproc), on a tree configured for x86_64-nimgnu-linux-gnu
  and -j14.  The build never reads it (run_as_lfs embeds the variables, the
  chroot reads config/env), but a `su - lfs` by hand would cross-compile for
  the wrong target.  Both lines now carry the configured values.
- Tested: mocked fetch -- mirror 404 asked once, upstream Errno 99 twice
  then success; all-fail returns the error; the .bashrc substitution.

## 1.14.362 -- remove found no files by package name; gitsync is `make install`

- `remove [--purge] <name>` passed the name AS TYPED to the file search and
  the delete (`su - gitsync`, `forall_direntries_from gitsync`).  No such
  account, so _can_su said no, the search ran as root for a user that does
  not exist and found nothing: "uninstalled 0 files owned by gitsync", then
  --purge deleted the account and home -- on an installed package that
  orphans every file it installed.  remove_one now resolves pkgusr_name()
  once and uses the account for groups, search, delete and the report.
  (Earlier the userdel itself had been fixed the same way; the search was
  not.)  Tested with mocks: groups/scan/remove all receive p_gitsync.
- --purge also deletes lfs-helper's phase record (progress/phases/<name>
  and /<account>): the rebuild after a purge said "keeping the source tree:
  'build' already finished here" about a deleted tree.
- gitsync: the served repository is flat (user's ls: apache cron gitsync
  gitsync.conf Makefile README.md web); install="make PREFIX=/usr install".

## 1.14.361 -- gitsync's real layout; one door for new accounts

- The cloned Git-Server repository (1d84f22) has `gitsync` as a FILE at the
  top level, so `make -C gitsync` stopped: "gitsync: Not a directory".  The
  web view had shown a gitsync/ folder.  The entry's install now takes
  whichever layout is there (`if [ -d gitsync ]; then make -C gitsync ...;
  else make ...; fi`).  Tested on both layouts with DESTDIR.
- install --local / stack git entries created a missing account with a bare
  add_package_user call, skipping create_package_user (fix-home + home
  init), so pm-install opened with "misplaced home: p_gitsync is recorded at
  /usr/src/p_gitsync" for a brand-new account.  It now calls
  create_package_user.

## 1.14.360 -- a useradd over two lines

rsync (pulled in by gitsync) failed in install:
`*** useradd: 'rsyncd' does not exist and a package user cannot create it`.

- create_service_accounts_from_script read the script line by line.
  rsync's page continues its useradd with a backslash, so the account name
  (the last argument) came out as the backslash: the group was created, the
  user never was, and the package user's own useradd hit the wrapper.
- _join_continued_lines() joins backslash-continued lines before the
  groupadd/useradd lines are picked out.
- Tested: rsync's two-line useradd -> name rsyncd, full command; fcron's
  one-line form unchanged.
- Noticed, not changed: rsync's generated build_pkg is empty and
  configure/make sit in install_pkg (they follow the root-only account
  block on the page).  It builds either way.

## 1.14.359 -- gitsync

- sway.stack: `git gitsync` from the Git-Server repository
  (https://git.christianimmanuel.de/web-tools/Git-Server.git -- the server
  says repos clone as <category>/<name>.git; not reachable from the
  sandbox, so unverified).  A bash script: build="true", install="make -C
  gitsync PREFIX=/usr install" (the root Makefile installs a `gitsync` FILE
  where the root has a directory; gitsync/Makefile is the real one).
  needs=rsync,openssh: rsync was in no stack.
- Meant to be a dev package like swas: `dev gitsync --hub
  ~/Git/Git-Server --run` after the first build.

## 1.14.358 -- untracked files in the package's clone

`update browser`: the tracked edits were saved and reset (1.14.355), then
`error: The following untracked working tree files would be overwritten by
checkout: HANDOVER.md` -- a hand-made file in p_browser's clone, which a
new commit now tracks.

- lfs-phases: untracked, NOT ignored files in a git package's clone are
  tarred to `$HOME/<name>-untracked-<date>.tar`, then `git clean -fd`.
  Ignored files (the project's build output) stay.  If the tar fails,
  nothing is removed and the phase fails saying so.
- Tested: clone with hand-made HANDOVER.md + ignored build/x.o; upstream
  adds a tracked HANDOVER.md -- tar holds it, checkout succeeds, x.o stays.

## 1.14.357 -- minibrowser is browser; `packagemanager rename`

The browser's entry was `minibrowser`, kept only because p_minibrowser
existed (the program is Browser: browser-mini, browser-big).

- sway.stack: `git browser ...` (stack-version 1.14.357).  sway-session.sh's
  skeleton binds Mod4+b to `browser-mini` -- `exec minibrowser` named no
  program at all.  Regression tests now expect the entry `browser`.
- `packagemanager rename <old> <new> [--run]`: refuses while the account
  has processes; usermod -l -d -m (uid kept, so every file keeps its
  owner), groupmod -n; in the home: install_<old>* renamed and only their
  name/name_version/pkg/### header lines rewritten, src/<old>-* renamed,
  VERSION's leading name; every installed stack entry `<kind> <old>`
  (with .bak); the stacks' .done records; the dev-sources line.
- Tested: throwaway p_minibrowser with script, VERSION, clone dir, stack,
  done-record and dev source -- all renamed; a command line mentioning the
  old word untouched.

## 1.14.356 -- dev --hub, and a status that says which copy is newest

The user's checkout and p_swas's clone differed (`/* test` in one), and
there was no way to see why short of diffing files.

- `packagemanager dev <pkg> --hub <checkout> --run`: as the checkout's
  owner, `git clone --bare` into /srv/git/<name>.git (DEV_HUB, created
  owner-owned 755; core.sharedRepository=0644 + a+rX so package users can
  read whatever the owner's umask), adds/re-points remote `local` in the
  checkout, registers the bare repo as the source, trusts it for the
  account, and removes the account's ACLs from a previous source under
  /home.  The home stays closed.  Release = `git push local <branch>`.
- dev-sources.conf lines may carry `<- <checkout>`; lfs-phases' awk strips
  it.  _dev_entries() returns (source, checkout).
- `packagemanager dev` lists per project: source + followed ref, installed
  commit (the package clone's HEAD), source commit ("<- newer: update"),
  and the checkout's branch/commit with unpushed commits and uncommitted
  files.
- _git() and _git_clone_dir read with --git-dir/--work-tree instead of
  -C.  Root reading a repository another account owns with -C is refused
  ("dubious ownership"), so _git returned "" for every package clone --
  `update swas` printed `main moved ? -> 0ec52012`.
- Tested with two real accounts (dev owner, package account; checkout under
  a 700 directory): hub creation; package account clones from the hub with
  no access to the checkout; status shows pushed = installed, then 1
  unpushed + 1 uncommitted, then "newer" after a push; migrating a home-ACL
  source to --hub removes the ACLs from the parents and the tree.

## 1.14.355 -- the package's clone is a build tree

First `update swas` from a dev source: fetch fine (9f42169..0ec5201), then
`error: Your local changes ... would be overwritten by checkout` for
Makefile, README.md, config.example, swas.c in p_swas's clone -- hand edits
from before there was a checkout to work in.

- lfs-phases: tracked uncommitted changes in a git package's clone are
  saved to `$HOME/<name>-local-changes-<date>.patch` (the package's home),
  then `reset --hard`.  If the patch cannot be written, nothing is reset
  and the phase fails saying so.  Untracked files (build output) stay.
- Tested: fragment on a clone with an edited tracked file and a build
  product -- patch holds the edit, checkout of the moved branch succeeds,
  build.o untouched.

## 1.14.354 -- dev sources: build your own programs from your checkout

swas, swbr, swov and the browser are developed on this machine.  Their git
entries cloned the server, so a change had to be pushed before the system
could have it, and the clone in p_swas's home is the package's, not a
place to work.

- `/etc/pkgusr/dev-sources.conf`: `<account> <checkout>` per line.
  `packagemanager dev <pkg> <path> --run` writes it, grants the account
  read access with ACLs (x on non-world-x parents, rX on the tree, the same
  as default ACL for later files), names the checkout in the ACCOUNT'S git
  config, and verifies by running ls-remote as the account.  `dev` lists
  with an access check; `--off --run` removes.  `~/` means main_user's home.
- lfs-phases: a dev source replaces link=; an existing clone whose origin
  differs is re-pointed (set-url) either way; local clones use --no-local.
- packagemanager: _git_pkg_state uses the dev source, so `update` sees
  local commits; _ls_remote reads a local repository with
  `git --git-dir=<.git> for-each-ref` (root, no ownership refusal).
- WHAT GIT REQUIRES, tested with 2.43: a repository owned by someone else
  is refused ("detected dubious ownership").  `-c safe.directory=*` does
  NOT help for clone/fetch/ls-remote -- git clears command-line config
  before the process that reads the other repository.  The entry must be
  in the reading account's global config and must be the .git path (the
  work-tree path alone is refused).  An explicit --git-dir read is allowed.
- Only committed work on the followed branch is installed.
- Tested: second account, private (700) parent, umask-077 repo: refused
  before, readable after the grant; clone, then fetch of a new commit and a
  new branch made AFTER the grant (default ACL).

## 1.14.353 -- ldconfig by absolute path (ntfs-3g)

ntfs-3g 2026.7.7 built and installed everything, then failed in
src/install-exec-hook:
`/sbin/ldconfig: Renaming of /etc/ld.so.cache~ to /etc/ld.so.cache failed:
Operation not permitted`.

- The ldconfig wrapper only works for packages that find ldconfig on PATH.
  ntfs-3g's configure searches /sbin first and bakes LDCONFIG=/sbin/ldconfig
  into its Makefile.
- lfs-helper auto-repair `_ldconfig_from_log`: on that error, the retry
  gets LDCONFIG=<wrapper> plus MAKEFLAGS='<current -jN> LDCONFIG=<wrapper>'.
  A variable in MAKEFLAGS counts as a command-line definition, so it beats
  the Makefile's assignment, in sub-makes too.  Once per build.  Root still
  refreshes the cache after the install.
- Tested: the function's output (keeps the effective -j), and GNU make
  honouring MAKEFLAGS LDCONFIG= over `LDCONFIG = /sbin/ldconfig` at top
  level and in a sub-make.

## 1.14.352 -- ntfs-3g

- services.stack: `book ntfs-3g` after exfatprogs.  The kernel's ntfs3
  mounts NTFS; ntfs-3g adds mkntfs / ntfsfix / ntfsresize / ntfslabel
  (what gparted calls for NTFS) and mount.ntfs-3g.  The book builds it with
  its bundled FUSE, so the only other need is FUSE_FS in the kernel.
- lfs-kernel: `enable fuse` (FUSE_FS=m).  kernel.conf ships it in
  CONFIG_SET.
- Not run: the book page itself (no book in the sandbox); the entry parses.

## 1.14.351 -- which version, which book, and `packagemanager books`

`stack media` printed `book webkitgtk  book WebKitGTK-2.54.0` for a
package that IS 2.54.0: "book X" read as "will build X", and nothing said
which book X came from.  `blfs books` listed four svn tarballs and a 13.0
book as "? version ?", with no way to tell whether anything used them.

- Stack rows are columns now: entry, installed, book, from, verdict
  (current / update available / not installed / newer than this book).
  Under the table: the books the stack reads, and one line each for
  `stack --run` (not installed) and `update --stack --run` (behind), with
  the names.  _stack_row_view() does the judging; the run logic still uses
  the old states.
- `packagemanager books`: every cached LFS and BLFS book with who reads it
  -- lfs default / build book, the BLFS default, each stack's from-book
  (with its entry count), each machine.conf / package-fixes.conf `book =`.
  The newest svn tarball is "source of the svn book"; older ones, and books
  nothing names, are "not used".  `--prune --run` removes those (+ .meta
  + blfs's parsed index of them).  Selectors are resolved with
  `blfs path --offline`: listing books never touches the network.
- blfs: after stitching a new svn tarball, the older dated tarballs are
  deleted (keep the newest -- the next refresh compares its name).
  `blfs books` labels files without .meta from their name and mtime
  instead of "?".  blfs was missing `import glob` for that -- pyflakes
  caught it before release.
- Tested: fake store (both tools' layouts) -- listing, then prune removes
  12.3 LFS, 13.0-systemd and the old svn tarball, keeps the rest; stack rows
  rendered with mocked versions.

## 1.14.350 -- --clean after `update` ran as the wrong account

`update --stack media` installed WebKitGTK 2.54.0; its --clean then kept
five libraries and undid itself:
`!! no unpacked source in /root`.

- `update` passes the BOOK name (`webkitgtk`) to _clean_after_install.
  getpwnam("webkitgtk") fails, so:
  - the reapply could not su and ran `sh -c "cd ~ && ..."` as root, in
    /root, where no source is;
  - own_uid was None, which silently turned off "only files this package
    still owns" and "its own files are not users of its libraries" (hence
    "1 file in p_webkitgtk still links against libjavascriptcoregtk-4.1").
  _clean_after_install, _orphan_sweep and _reapply_install now resolve
  pkgusr_name() first (idempotent, so the callers that already passed the
  account are unaffected).
- Old libraries kept "because p_minibrowser links against
  libjavascriptcoregtk-6.0.so.1" -- but that soname now points at the new
  file.  A library whose soname symlink resolves to a different, current
  file is not needed by anyone; only a soname that would vanish asks
  _needed_by.
- Tested: temp lib dir -- libjsc.so.1.6.10 behind a soname served by
  1.8.0 is a victim; libgone.so.0.10.13 whose soname would vanish, with a
  user, is kept.

## 1.14.349 -- compare a script with the book it came from

After 1.14.348, script-status still said "edited" for the five
machine.conf-only media scripts.

- The machine.conf check compared the script with the book the package
  reads NOW.  media reads svn (gst 1.28.7, WebKitGTK 2.54.0, SysV wording);
  the scripts on disk are 1.28.6 / 2.52.5 from the default book.  Different
  page, different text: that comparison can never match.
- classify_script now also finds a cached book that has the script's OWN
  version (default book, the package's book, /usr/share/blfs/books/*),
  generates that page and compares with machine.conf applied.  Only-
  machine.conf -> state `machine.conf`, safe to --regenerate.
- The comparison's merge runs quietly: no more "machine.conf [x]: ..."
  lines in script-status output.
- For scripts still marked edited, the summary also prints the
  `update ... --regenerate --run` command, for when you know you never
  edited them.
- Still conservative: if blfs itself generated that page differently since
  (a newer script format), the script still reads "edited".
- Tested: mocked books -- machine.conf-only -> machine.conf; one extra
  hand-written line -> edited.

## 1.14.348 -- 1.14.347 deleted half of packagemanager

`packagemanager script-status ...` on 1.14.347: `NameError: name 'cmd_info'
is not defined`.  Every command failed the same way -- argparse is built
before any command runs.

- Cause: the 1.14.347 script-status summary edit replaced a block found with
  `s.index()`.  That block (`_act` / "nothing needs attention") existed
  TWICE -- once in `verify`, once in `script-status` -- and the search hit
  verify's first.  Old-start-to-new-end swallowed everything between them:
  about 8,500 lines, including cmd_info, the network command, git installs,
  the per-stack book plan and the pruned pkg.lst scan.
- py_compile passed, because what was left was valid Python.  A NameError at
  argparse time is not a syntax error.
- Rebuilt from the 1.14.320 upload for the lost span, then every change of
  1.14.321..347 in that span re-applied with replacements that assert the
  old text occurs exactly once.  The network command was re-written from its
  1.14.342 draft plus the 343/344 checks (per-runlevel links, WPA_SERVICE
  hand-off, DHCP_START -b, /sbin paths).
- Check now part of every release: `pyflakes` on a copy, no undefined names
  except STACK_DIR (set through globals()); every `def` of the last good
  upload still present.  Here: 0 missing, 15,926 lines.
- Tested: --help, `network`, `script-status` in the sandbox.  Not run: the
  regression suite.

## 1.14.347 -- the tool's own edit is not yours

`script-status` on the media stack: five "edited", three "outdated" -- and
the five were exactly the five with a machine.conf section (gstreamer10
gst_debug, plugins-base alsa, plugins-bad webrtc..., plugins-ugly gpl,
webkitgtk's cmake switches).  The user had edited none of them.

- A generated script carries `### pm_md5=` of what the BOOK produced.
  apply_machine_opts merged machine.conf in AFTERWARDS, so the checksum
  stopped matching and the merge read as a hand edit -- with advice to
  hand-merge edits nobody made.
- Going forward: apply_machine_opts re-stamps the checksum after its merge,
  but ONLY for a script that was pristine before it.  One the person really
  edited keeps its old checksum, so a later migration still stops and asks.
  (_restamp_md5 touches the checksum only, never the format stamp.)
- Scripts already on disk: a new state, `machine.conf`.  classify_script
  builds what this machine would get -- the book's script with machine.conf
  applied -- and compares it with the version number and tarball checksums
  normalised away.  If that is the whole difference, nobody touched it.
  Conservative: a page whose commands changed between versions still reads
  as edited.  migrate-scripts treats it like "outdated" (no hand-merge).
- The summary said "nothing needs attention" directly under five "edited"
  lines.  It was copied from `verify` and tested for "not installed" /
  "broken", which a script never is.  It now says which scripts carry edits
  (merge) and which do not (safe to --regenerate, with the command).
- Tested: a script differing only by `-Dwebrtc=enabled` and the version is
  "machine.conf"; the same with one extra hand-edited command is "edited".

## 1.14.346 -- the replay command dropped --regenerate

First real run of `update --stack media` against svn: the plan was right
(webkitgtk 2.52.5 -> 2.54.0, gstreamer 1.28.6 -> 1.28.7, libvpx 1.16 ->
1.17, each "read from svn-combined-nochunks.html"), and three things around
it were not:

- "Dry run -- this exact command runs THIS plan" printed the stack EXPANDED
  into nineteen names and WITHOUT --regenerate, after a dry run that had
  --regenerate.  The command offered as exact would have brought the
  old-format-script warning straight back.  It now prints `--stack <name>`
  when a stack was asked for, and carries --regenerate, --recursive,
  --test and --keep-sources.
- "Checking 19 package(s) against the book (13.1-systemd)" was false for
  the 11 that read svn.  It now says "(13.1-systemd); 11 from
  svn-combined-nochunks.html".
- "other ways to choose: ... update --stack media" was offered to someone
  running `update --stack media`.  Not any more.

## 1.14.345 -- the svn book is the SysV edition, and it is alive

Checked against the site on 2026-09-24:

    /blfs/view/svn/      System V Edition   r13.1-245   2026-09-23   WebKitGTK-2.54.0
    /blfs/view/systemd/  systemd Edition    r13.1-212   2026-09-19

- `from-book svn` in media.stack (1.14.321) was written with "check the
  selector" as an open question.  It is the right selector -- and a better
  one than I knew: the development book is the SysV edition, so every page
  media.stack reads from it has SysV commands and no systemctl to shim.
- The "BLFS stopped publishing a SysV edition after 12.4" statements (this
  file's header, two comments in blfs) are corrected: there was no SysV
  13.0, but the development book is SysV and current.  The LFS side
  (lfs-sysvbook grafting) is untouched -- that is about the LFS book, which
  was not checked here.

## 1.14.344 -- the hand-off is optional, and without it there is no address

Read against the real blfs-bootscripts-20250225 (the user sent the tarball):

    services/wpa:    CFGFILE=/etc/sysconfig/wpa_supplicant-${IFCONFIG##*.}.conf
                     ... if [ -n "${WPA_SERVICE}" ]; then
                         IFCONFIG=${IFCONFIG} /lib/services/${WPA_SERVICE} $1 up
    services/dhcpcd: /sbin/dhcpcd $DHCP_START $1

- The config file is named after the IFCONFIG FILE's suffix, not after
  $IFACE -- so ifconfig.wlan0 reads wpa_supplicant-wlan0.conf even if
  IFACE= says something else.
- WPA_SERVICE is what starts dhcpcd, and it is OPTIONAL: a file that says
  SERVICE="wpa" and nothing more associates and never asks for an address.
  No FAIL line, because nothing failed.  `packagemanager network` and
  `cfg net-wifi` both report it now, with the two lines to add.
- DHCP_START without -b is reported (network) for any file that reaches
  dhcpcd, directly or through wpa.
- Both services hard-code /sbin/dhcpcd and /sbin/wpa_supplicant; the report
  checks those exact paths, not PATH.
- The report prints the chain per wpa interface:
      wlan0  SERVICE=wpa  WPA_SERVICE=dhcpcd  DHCP_START=-b -m 100
- There is nothing more to install for dhcpcd: blfs-bootscripts ships the
  two service scripts and no init script, and both are in place.

## 1.14.343 -- two network links in one runlevel

The first `network` report on the machine showed

    boot : S10network, S20network

which the command printed as a flat list, so it read like one fact.  It is
two: if both are in the SAME runlevel the network script runs TWICE at
boot -- every interface brought up twice, a second dhcpcd started for each
-- and that reads like a flaky boot rather than a leftover link.  Links are
now printed as rc<N>.d/S<NN>name, the default runlevel is named, and two
links in one runlevel is a "thing to look at".

## 1.14.342 -- one command for "why is there no address after a reboot"

`packagemanager network`, read-only:

  * every interface: state, address, its ifconfig.<iface> file (or none),
    whether ONBOOT is yes and which SERVICE it names
  * the default route, the dhcpcd processes (and whether one is a
    [manager]), the wpa_supplicant processes
  * where the INSTALLED wpa service looks for its config (read out of
    /lib/services/wpa, as net-wifi does since 1.14.333) and whether the file
    is there for each interface that asks for it
  * whether the `network` script is linked into any runlevel -- if it is
    not, nothing reads any of those files at boot
  * a "things to look at" list: a file for an interface that is not here, an
    interface that is up with nothing bringing it up, one that is up with no
    address, a missing wpa config

  It also states the thing that keeps being rediscovered: dhcpcd has no init
  script.  BLFS ships none (`blfs/init.d/dhcpd` is the SERVER), so
  /lib/services/dhcpcd runs only from ifup -- "enable dhcpcd at boot" is not
  a thing that exists, and bootscripts.sh has known this since 1.14.x.

## 1.14.341 -- a tool the book's commands never name

    checking for itstool... no
    configure: error: itstool not found

gparted's script says `./configure`; the word "itstool" is nowhere in it,
so the prereq check -- which reads the script -- could not know, and the
stack stopped one package short with the answer on the screen.

- `packagemanager provider <program>` is new: it answers from _BUILD_TOOLS
  plus the book (itstool -> itstool, xsltproc -> libxslt, cargo -> rust).
  The knowledge was already here; nothing outside could ask for it.
- lfs-helper's repair loop reads a missing tool out of the log --
  `configure: error: X not found`, `configure: error: cannot find X`,
  meson's `Program X not found`, `X: command not found` -- asks for its
  provider, installs THAT, and runs the phase again.  Only when the tool is
  really absent from PATH, and only one level deep (PM_IN_TOOL_REPAIR): a
  repair that can start a repair that can start a repair is a fork bomb
  with good intentions.
- When no page provides it, the box says so and stops, rather than
  pretending a retry would help.
- Tested: five wordings extracted correctly (itstool, cannot-find, meson's
  Program, command-not-found, and a name no page provides).

## 1.14.340 -- a man page with colons in its name

XML::Parser: six repair rounds, all of them granting directories, and the
install still failed.  The report said

    /usr/share/man/man3/XML   missing; parent /usr/share/man/man3 is drwxrwxr-t

-- a file that has never existed.  The real name is
`/usr/share/man/man3/XML::Parser.3`, and both path extractors cut it at the
first colon: their character class was `[A-Za-z0-9._/+-]`.  So every Perl
man page has been reported under a truncated name, and the file that
actually blocked the install was never named.  A trailing colon (from the
message's own "path: Permission denied") is stripped now.

- THE STICKY BIT IS THE POINT.  /usr/share/man/man3 is drwxrwxr-t, so only
  a file's OWNER may replace it -- and ExtUtils::Install replaces by
  unlinking first.  The file belongs to p_xml-parser, an older account for
  the same module (this one is p_perl-xml-parser, a different book anchor).
  No directory grant can ever fix that, which is why six rounds did not.
- takeover_files_from_log now reads perl's wording -- `Cannot forceunlink
  <path>`, `Can't unlink/remove/rename <path>` -- as a whole token, colons
  and all.  The file is handed to the package that is installing it.
- When two or more files move from an account whose name is this one's
  minus a language prefix (xml-parser <- perl-xml-parser), the box says
  they are one upstream module under two anchors and offers
  `packagemanager remove xml-parser --purge --run` for afterwards.
- Tested: both wordings extracted with their colons intact.

## 1.14.339 -- install_last is written BEFORE the build

The answer to 1.14.338's open question, and the reason the stack needed a
package named by hand.

- lfs-helper copies the script to `install_last` BEFORE running it ("RECORD
  WHAT IS INSTALLED BEFORE OVERWRITING THE RECORD").  So a build that dies
  at configure leaves one behind.  `User.state`, with no manifest and a page
  that declares no programs or libraries to check -- cairomm is exactly that
  -- then falls through to `if self.meta.get("name_version"): installed`.
- cairomm-1.0 failed at configure with 0 files tracked, was recorded
  installed by that rule, and every later plan skipped it as a dependency
  that was already there.  pangomm then failed on
      Run-time dependency cairomm-1.0 found: NO
  and only naming cairomm by hand got the chain moving.
- `_install_finished(u)`: a manifest with real paths, or `.pkgusr-installed`
  (the marker the runner writes AFTER a successful install), is evidence.
  A script copied in before the build is not.  The planner skips a
  dependency only with that evidence; without it the package goes into the
  plan, and the plan says so:
      N package(s) are recorded as installed but have no finished-install
      record: cairomm-1.0
- Tested end to end with three shapes: install_last only (planned),
  .pkgusr-installed (skipped), a manifest (skipped).
- NOT changed: `state` itself, which many commands read.  The rule here is
  the PLANNER's, where a wrong "installed" costs a broken chain and a
  needless rebuild costs minutes.

## 1.14.338 -- "recorded as installed" is not "on disk"

pangomm could not find cairomm-1.0, and the box said cairomm "IS installed
here ... if the .pc is absent, it installed without it".  Two very
different things hide behind that: a package that installed and later lost
a file, and one that is RECORDED as installed and put nothing on disk (a
build that failed after its account and home were made).  The manifest
answers it in one read, so the box now reads it:

  * manifest empty        -> "nothing of it is on disk.  Its last build did
                             not finish, and whatever marked it installed
                             was wrong."
  * manifest, but no .pc  -> "records N file(s), and NONE of them is a .pc"
  * manifest with .pc     -> each one printed, "(on disk)" or "MISSING from
                             disk", and both the rebuild and the
                             pkg-config-path checks

Tested against all three shapes.

STILL OPEN on that machine: why cairomm-1.0 was skipped as installed at
all.  Its previous build failed in the BUILD phase with 0 files tracked,
which `state` should read as "not installed" (no manifest, no
install_last).  Either something wrote install_last for a build that never
installed, or a DIFFERENT cairomm (the 1.16 API is its own package) is
being mistaken for it.  The next run's box will say which.

## 1.14.337 -- the build named the option; now the tool reads it

    Run-time dependency Boost found: NO (tried system)
    ERROR: Building the test programs requires Boost Test ... and Fontconfig.
    Install them or use -Dbuild-tests=false or -Dbuild-tests=if-dependencies-found

- cairomm stops at configure over TEST programs, which want Boost -- and
  Boost is in avoid.stack on purpose.  The dependency is never coming; the
  option meson prints is the whole answer, and it was on the screen while
  the chain sat stopped.
- `_meson_opt_from_log` takes the FIRST `use -D<opt>=<value>` the build
  suggested, adds it to the script's `meson setup` line (old script kept as
  .bak-<date>) and the retry loop runs the phase again.  Only an option the
  build itself named, only one that turns something OFF (=false, =disabled,
  =no, =if-dependencies-found), only once.  The gate lets such a failure
  reach the loop, and the "no repair attempted" line no longer claims the
  only repairs are permissions.
- A regenerated script loses the edit, so the note prints the machine.conf
  section to make it permanent -- and machine.conf now ships
  build-tests = false for cairomm-1.0, pangomm-2.48 and glibmm-2.68, which
  are the three in this chain with the same Boost test dependency.
- Tested: the option is added once, the second call is a no-op, and a
  suggestion that turns something ON is refused.

## 1.14.336 -- the test suite was in the BUILD block all along

XML::Parser died in the BUILD phase:

    make: *** [Makefile:1005: test_dynamic] Error 2
    Failed 60/62 test programs.

- Every Perl module in BLFS uses "the standard build and installation
  instructions", which are ONE block:
      perl Makefile.PL &&
      make &&
      make test
  The test suite is not a block to skip -- it is the last LINE of the block
  that builds the package, joined with &&.  So the block-level test filter
  could never see it, and every perl module on this machine has been
  running its test suite inside the build.  Class::Inspector's passed,
  which is why nobody noticed; XML::Parser's fail (60 of 62 files cannot
  load the module) and took the gparted chain with them.
- _strip_test_lines drops such a line, leaves the book's own text in a
  comment above it, and removes the now-dangling `&&` from the line before.
  A block that is ONLY tests still goes through the block-level guard with
  its reason.  `--test` (PKGUSR_TESTS=1) still runs the suite -- in the
  TEST phase, where a failure is reported and not fatal.
- Checked against seven blocks: the perl one, a plain configure+make, a
  bare `make check`, `make && LC_ALL=... make check_local`, `make install`,
  LVM2's two-target install, and meson+ninja+`ninja test`.
- Script format v19, so every generated script is rebuilt from the book.

Worth knowing: XML::Parser's tests failing to LOAD the module may mean its
Expat binding is not linking to the installed expat.  It is not in the way
of the build any more; after the install, check it:
    perl -MXML::Parser -e 'print "ok\n"'

## 1.14.335 -- a PDF that was never built is not a failed install

- parted installed 97 files -- every binary, every library -- and then
  failed:
      install: cannot stat 'doc/parted.pdf': No such file or directory
  The book's last line is
      install -v -m644 doc/{FAT,API,parted.{html,txt,pdf,ps,dvi}} \
              /usr/share/doc/parted-3.7
  and parted.pdf/ps/dvi and API exist only when texlive built them.
  texlive is in avoid.stack, so they never exist here -- for parted, and
  for every other page with a doc block like it.
- The install PHASE now defines an `install` function (and only that phase,
  which runs in a child process of its own -- nothing outside ever sees
  it).  For a destination under share/doc it runs the book's command
  unchanged first; only if that fails does it retry without the sources
  that are not there, and say which they were.  Everything else goes
  straight to /usr/bin/install.  A doc command that fails for any OTHER
  reason is re-run and its real error reported.
- Tested: the book's block with two files missing (installs the two that
  exist, rc 0, names the others), all sources missing, `-m 644` as two
  words, `install -dm755` on a doc directory, and a non-doc destination.
- kernel.conf ships CONFIG_SET="LEGACY_TIOCSTI=n EXFAT_FS=m" -- the kernel
  half of exfatprogs, and what this machine already has.  (It was the only
  difference left in kernel.conf.new.)

## 1.14.334 -- `mount -o remount,dev /tmp` in an install phase

LVM2 stopped the gparted chain with

    mount: /tmp: must be superuser to use mount.
    !! phase 'install' FAILED (exit 32)

and the report said "no line matched the usual error patterns".

- WHERE IT CAME FROM.  BLFS 13.0's LVM2 page has three blocks between the
  build and the install: a partial install for the test suite, then
  `mount -o remount,dev /tmp`, then `LC_ALL=... make check_local`.  The
  middle one prepares /tmp so the TESTS may create device nodes.  All three
  went into the install phase.
- `make check_local` was missed by the test filter for two reasons, both
  now fixed: the pattern wanted a word boundary after "check" (and
  "check_local" has none), and it did not allow the `LC_ALL=...` in front.
- A new rule, judged on the commands and not on the prose: a block
  containing mount, umount, modprobe, insmod, mknod, swapon or swapoff is
  never part of installing a package.  A package user cannot run those and
  no collector group can grant them; they are the system's business.  The
  script says so where the block would have been.
- lfs-helper recognises "must be superuser" and the like: it names the line
  and says the step wanted something root-only, instead of falling through
  to "no pattern matched".
- apps.stack: `book gparted ignore=lvm2`.  LVM2 is only RECOMMENDED by
  parted, and this laptop has no logical volumes.
- Tested: the block classifier against all seven blocks of the LVM2 page
  (mount -> root-only, check_local -> test, install/configure -> kept).

## 1.14.333 -- the wpa service reads one directory; we wrote the other

The boot log, not dhcpcd:

    Starting dhcpcd on the wlp3s0 interface...                      FAIL
    wpa_supplicant configuration file
      /etc/sysconfig/wpa_supplicant-wlan0.conf not present          FAIL
    Bringing up the eth0 interface... Interface eth0 doesn't exist. FAIL

- THE PATH.  This machine's wpa service reads
  /etc/sysconfig/wpa_supplicant-<iface>.conf; net-wifi wrote and looked in
  /etc/sysconfig/wpa_supplicant/ -- the subdirectory other bootscript
  releases use.  So wpa_supplicant never started, nothing associated, and
  dhcpcd had no link to ask on.  The path is now READ out of $svcdir/wpa
  ("the wpa service reads: ...") and used for the check and for COPY_WPA;
  a config in either layout is found and copied to the one that is read.
- Per interface, the step now says whether the config the service will look
  for exists, and prints the one-line copy when it does not.
- DHCP_START without -b is reported: dhcpcd in the foreground waits for a
  lease on a wireless link that is not associated yet, which is the
  "Starting dhcpcd ... FAIL" line.  Our writer has always used -b.
- A config for an interface the kernel does not have is a FAIL line at
  every boot.  It is reported with the sed that turns ONBOOT off, and
  DISABLE_MISSING=yes in net-wifi.conf does it for all of them (backed up;
  nothing is deleted -- the card may be back tomorrow).
- Tested in a sandbox with a fake service script, a fake /sys/class/net and
  a temporary /etc/sysconfig: the path is detected, the copy lands where
  the service reads, and a stale eth0 file is reported.

## 1.14.332 -- ExtUtils::Install says it in its own words

- File::ShareDir stopped the plan with
      ERROR: Can't create '/usr/lib/perl5/5.42/site_perl/File'
      Do not have write permissions on '/usr/lib/perl5/5.42/site_perl/File'
  and the box said "no automatic repair attempted: the failure does not
  look like a permission or missing-directory problem".  It is exactly a
  permission problem; ExtUtils::Install simply never writes the words
  "Permission denied" for it.  Two greps were blind to it:
    * the _perm_ish gate (so zero rounds ran), and
    * unwritable_dirs_from_log's tail filter (so even a round would have
      had nothing to grant).
  Both now know `Can't create '<path>'`, `Do not have write permissions`
  and `Cannot mkdir`.  Checked against the real log text: the gate fires
  and the extractor yields /usr/lib/perl5/5.42/site_perl, the directory
  the grant needs.
- Round two of the same lesson as 1.14.331: a Perl module's install writes
  into three trees owned by three different packages, and every one of them
  reports the refusal differently.

## 1.14.331 -- perllocal.pod is the info/dir of the perl tree

- `perl-class-inspector` installed both its modules and both its man pages
  and was then reported FAILED, for a line make itself had marked
  "(ignored)":
      /usr/lib/perl5/5.42/core_perl/perllocal.pod: Permission denied
  Every Perl module APPENDS to that file in its doc_install step, so it
  belongs to whichever module was installed first (p_xml-parser, 664, group
  p_xml-parser) and every module after that cannot write it.  Granting the
  DIRECTORY to the perl collector group -- which the auto-repair did --
  cannot help: the file's own group is one package's.
- It is in shared_files_list now, with the info/dir family: written by many
  packages, installed by none.  share_shared_files makes it root:install
  664, which every package user can append to.  The version is globbed
  (/usr/lib/perl5/*/*/perllocal.pod).
- shared_file_dirs SKIPS the perl directories: the file is shared, the
  directory is not -- /usr/lib/perl5/<ver>/core_perl is p_perl's install
  directory and is in its manifest.  Handing it to root:install would make
  `verify` right to complain.
- The "exited 0 but the log says otherwise" gate no longer fails a phase
  for a shared registry file it could not update.  It says so, runs
  share_shared_files, and lets the package's own files stand.  A real
  `install: cannot create ...: Permission denied` still fails, tested
  against both logs.

## 1.14.330 -- an installed dependency is not a thing to upgrade

- `install gparted --run --recursive` planned FIFTY-THREE packages: gparted,
  its missing dependencies -- and updates of bubblewrap, alsa-lib, gtk3,
  gtk4, librsvg, glycin, GnuTLS and thirty more that were installed and
  working, purely because the book had moved on.  Asking for one program is
  not asking to rebuild the desktop, and each rebuild is a chance to break
  a machine that was fine.  A DEPENDENCY that is installed is now left
  alone whatever its version; a package NAMED on the command line is
  unchanged; `--update-deps` restores the old behaviour.  The plan says how
  many it left and how to move them on purpose.
  (Unit-tested: gparted with gtk3 installed-but-behind plans 2 packages,
  and 3 with --update-deps.)
- exfatprogs is a `tar` entry now, not `book`: the BLFS index carries no
  exFAT package at all (checked).  1.4.2 from the project's release
  tarball, ./configure with an autogen.sh fallback.  The relan/exfat the
  book mentions is the FUSE implementation -- a different thing, and only
  for a kernel without EXFAT_FS.

## 1.14.329 -- gparted

- apps.stack: `book gparted`, last in the file (it is the heaviest entry --
  the planner brings gtkmm3 and parted).  Confirmed a BLFS page against the
  stable index: Gparted-1.7.0.
- It has no graphical privilege step here: the book's page uses polkit and
  polkit is avoided on this machine (it arrives only through colord and
  systemd).  So: run `gparted` from a ROOT terminal inside the session.
  The comment in the stack says so.
- The filesystem tools it drives are their own packages; exfatprogs and
  btrfs-progs (services.stack) are what stop entries being greyed out.

## 1.14.328 -- exfatprogs

- services.stack: `book exfatprogs` (mkfs.exfat, fsck.exfat, exfatlabel),
  beside btrfs-progs.  No `when=`: the card that needs it is not in the
  machine when the stack runs.  The kernel side stays separate --
  `lfs-kernel enable exfat` sets EXFAT_FS=m.
- Not tested against the book here: if the page's anchor is not
  `exfatprogs`, the stack says NOT IN BOOK and `blfs search exfat` gives
  the real one.

## 1.14.327 -- net-wifi writes what holds no secret, and prefers an antenna

- `cfg net-wifi` reported and wrote nothing, so a deleted
  /etc/sysconfig/ifconfig.<iface> meant pasting a file out of its output.
  It now reads stacks/net-wifi.conf and, with WRITE=yes, writes that file
  for every wireless interface that has none -- marked as ours, never over
  one of yours.  The wpa config is still never written: it holds the key.
- PREFER (patterns, best first) decides the dhcpcd route metric: the first
  interface PRESENT gets METRIC_PREFERRED, the rest METRIC_OTHER, so a USB
  antenna takes over while it is plugged in and the built-in card carries
  on when it is gone.  A file the step wrote is re-metered when PREFER
  changes (backed up); one of yours is reported, not edited.
- USB_RENAME writes a udev rule naming an adapter by its USB ids
  (0cf3:9271 -> wl-ext), because its bus name changes with the socket and
  ifconfig.<name> cannot follow.  It applies when the device next appears.
- COPY_WPA copies an existing wpa_supplicant-<iface>.conf to an interface
  that has none (chmod 600), and says so every time -- a key is duplicated.
- A config naming an interface the kernel does not have is now reported.
- diag.stack: usbutils and pciutils (lsusb, lspci) -- the first commands
  for a device that did not appear.
- Tested with a fake /sys/class/net (NET_WIFI_SYSFS) and a temporary
  /etc/sysconfig: first write, the metric flip when the preferred interface
  appears, the wpa copy, the orphan-config note, the udev rule text.

## 1.14.326 -- a build needs --run, a module can be loaded, a scan is pruned

- `lfs-kernel` alone no longer builds.  It prints what a build WOULD do --
  version, tree state (fetch / continue / already built), config source and
  CONFIG_SET, where the image and modules go, firmware, headers,
  v4l2loopback -- and says `--run`.  `--run` is taken from anywhere on the
  line.  An hour of compiling that replaces the booting kernel should not
  start from a bare word; every other tool here already waited.
- `lfs-kernel load <module> [--boot]` / `unload`: modprobe, confirm it in
  /proc/modules (and say when a symbol is built IN rather than missing),
  show the dmesg lines that mention it or firmware, and with --boot add it
  to /etc/sysconfig/modules (backed up, no duplicates).  `modules` points at
  it instead of telling people to type modprobe themselves.
- `reload-pkg-list` scans with its own pruned find instead of the hint's
  `list_package`: -xdev, and never /proc, /sys, /dev, /run, /tmp, /var/tmp,
  /var/cache, /mnt, /media, the snapshots, /sources, /build or the PACKAGE
  SOURCE ROOTS.  That last one is where the time went -- ninety unpacked
  source trees, the kernel's own among them.  Still run as the package user
  (so unreadable directories are skipped), with a line saying so and
  `--root` for the thorough scan.  The seconds are now printed.
- Tested: the plan for an already-built tree, load/unload with a stub
  modprobe and the boot file, the pruned find, py_compile / bash -n.

## 1.14.325 -- where are we, and a firmware report that needs no network

- `lfs-kernel status`: what is running and what is known to boot, whether
  the tree's .config carries every CONFIG_SET entry, whether the build is
  FINISHED / UNFINISHED (object files, no current image) / not started, how
  many modules are in the tree and in /lib/modules, what the ESP holds, and
  whether the installed config differs from the tree's.  Reads only; no
  network; works with the ESP unmounted.  Written because an interrupted
  build leaves nothing on the machine that says how far it got.
- `firmware --missing` asked kernel.org which kernel is newest, for a
  question /lib/modules and the boot log answer -- and EXITED on a machine
  with no network.  It uses the running kernel's version now.
- Tested: status against a tree with objects only and with a bzImage,
  CONFIG_SET read-back, the unmounted-ESP path.

## 1.14.324 -- a typo built a kernel, and the command line lost to the file

Two bugs in lfs-kernel's argument handling, both old, both found by one
paste: `lfs-kernel search AR9271` rebuilt and reinstalled 7.2.6.

- ANY unrecognised word became VERSION.  It is now refused, with the
  command list and a did-you-mean; only `latest` or something shaped like
  7.2.6 is a version.  `search` and `set` became real top-level commands
  (they are what a person types) and go to `config search` / `config set`.
- WORSE: `VERSION="$1"` was set BEFORE `. "$CONF"`, and kernel.conf's own
  VERSION= then overwrote it.  So `lfs-kernel 6.12.40` built whatever the
  file said (latest, here) and `lfs-kernel verify 7.2.4` reported on another
  kernel -- both documented, neither working, since the config file grew a
  VERSION line.  The command line is re-applied after the source now.
- `lfs-kernel prune` is named in two comments and has never existed; the
  comments are corrected rather than the command invented.
- Tested: unknown word refused, search alias, an explicit version surviving
  the config file.

## 1.14.323 -- hardware by name, and the modules a kernel really has

- `lfs-kernel enable <name>`: a table of hardware (ath9k-htc, ath9k, ath10k,
  ath11k, alx, atl1c, iwlwifi, rtl8xxxu, bluetooth-usb, btrfs, exfat, ntfs3,
  nvme, usb-serial, v4l2-usb) -> the symbols AND the firmware it needs,
  written into CONFIG_SET and FIRMWARE_ONLY.  A bare symbol works too: the
  tree says whether it is tristate (=m) or bool (=y).  `--list` shows them.
- `lfs-kernel modules [text]` -- what /lib/modules holds for this kernel,
  what is built in, what is loaded, with each module's description.
- `config search` now matches a symbol's NAME or its PROMPT and prints the
  prompt.  It used to list every symbol of every Kconfig file that merely
  mentioned the word: 40 lines of MIPS console options for "atheros".
- `config save [--good]` seeds the archive from the running kernel without a
  build -- what CONFIG_FROM=last-good needs before the first build ever runs.
  `config from <source>` sets CONFIG_FROM and refuses last-good when there
  is none.  One writer (`_conf_set_var`) for every kernel.conf edit.
- Tested: enable (name, bare symbol, unknown), search prompts, save/from,
  modules against a fake /lib/modules.  No kernel built here.

## 1.14.322 -- btrfs-progs when it applies, and the kernel configs are kept

- Stack entries take `when="<shell>"`: judged and run only where that
  command succeeds.  `book btrfs-progs when=...` is in services.stack --
  mounted btrfs, or a btrfs partition on any disk (so it is right in a
  chroot too).
- lfs-kernel keeps every config it builds with in /etc/pkgusr/kernel-configs
  (root's, outside the tree, so `prune` and `packagemanager remove linux`
  cannot take it): `config-<ver>-<date>` (newest CONFIG_KEEP=5),
  `last-good.config` and `prev-good.config` -- the last two that BOOTED,
  rotated where last-good is written, i.e. only from a kernel that ran.
  The archive is written BEFORE the compile, so a build that dies keeps its
  answers.
- CONFIG_FROM takes last-good | prev-good | saved, and `running` falls back
  to last-good instead of exiting when /proc/config.gz is unreadable.
- `lfs-kernel config` -- show | list | diff | search <text> | set SYM=VAL |
  unset SYM.  set/unset edit CONFIG_SET in kernel.conf with a backup;
  search reads the current config and the tree's Kconfig files and says
  that a NET_VENDOR_*/WLAN_VENDOR_* symbol alone builds no driver.
- Tested: the config subcommands against a fake tree and config directory
  (show/list/diff/search/set/unset), stack parse of the when= entry,
  py_compile / bash -n.  No kernel was built here.

## 1.14.321 -- git reinstall, a stack on the svn book, @setup

- `install <gitpkg> --reinstall [--clean]` builds from the package's own
  script and never asks the book.  It used to ask three times (map,
  `blfs debug`, `blfs search`), take a minute and say "not in the BLFS
  book" for imv.  A stack git/tar entry that was never built is found too.
  `book_version` remembers a miss, so no name is looked up twice.
- `from-book <selector>` in a stack file: its book entries read that book
  (versions, deps, scripts) -- permanently, so `update` and `info` agree.
  Deps outside the stack keep their own book; a page only the stack book
  has is read from it.  `blfs path` resolves a selector to the cached file
  once per run; `stack`/`update --stack` refresh it (`blfs fetch`) once.
  One version map per book (`book-versions-<md5>.json`).  The default map
  is the default book, no longer "newest file on disk" -- that would have
  become svn the moment it was fetched.  media.stack now says `from-book
  svn`.  NOT tested against a real svn book: check the selector exists
  (`blfs books --discover`).
- `stack` prints the avoid COUNT; `stack <name> --avoided` lists them.
- app-users.conf `@setup <account|*> <cmd|URL|script>`: runs as the account,
  once per line text (`/var/lib/pkgusr/app-setup/<account>`),
  `APP_USERS_RERUN=1` repeats.
- Tested: py_compile, bash -n, stack parse (media entries only get svn
  inside sway), `--avoided`, the git path with stubs.  Suite not run.

## Deferred tool work

None of this blocks the machine.

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
- The preamble of the suite (everything before block 1) always runs, and a
  block that needs a variable an earlier block computed dies on `set -u`
  rather than skipping. Only tool-path assignments are hoisted.
- The `modules` source needs `modprobe`/`modinfo` (kmod) and a mounted
  /sys; without either it falls back to the boot list silently apart from a
  header line. It was tested with stubs here, never against real kmod.
- The "busy tree" test is flaky: it races a `sleep` in the process table and
  should use a private marker.
- The whole-book invariants (954 scripts, 0 syntax errors, 0 empty install
  phases) have caught or confirmed nearly every filter change. Extend them to
  build phases, listing the known-empty pages by name.
- A BLFS-SysV counterpart tool: apply 12.4's init differences to 13.x pages.
  `blfs diff-init` is the survey that would drive it.

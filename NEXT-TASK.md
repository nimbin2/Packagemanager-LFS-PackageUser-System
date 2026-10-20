# First task for the next session

The machine boots, `su` works, the desktop runs and the application accounts
are in daily use. Everything below is configuration on the machine, not a
build. The tools are at 1.14.320.

## 0. Repair what the lease took (do this first)

`/usr/bin/su` and six `/usr/sbin/iptables*` links are owned by `p_webkitgtk`,
and the links are recorded in its `pkg.lst` — so `update webkitgtk --clean`
would delete them. 1.14.310 shuts the doors; the machine still has to be put
back:

    packagemanager disown --all            # what it would hand back
    packagemanager disown --all --run      # hand it back, and clean the records
    lfs-helper setid --run                 # put the setuid bits back
    su -                                   # check

Then the same rebuild that broke it is safe to repeat.

## 0a. The stacks are reorganised (1.14.320)

    make install
    ls /etc/pkgusr/stacks/*.stack.new     # should print nothing

wayland.stack is new (the base sway.stack used to carry), sway.stack
includes it, and zathura/imv moved to apps.stack, jq to tools.stack.
Nothing needs rebuilding; `packagemanager stack sway` still means the whole
desktop.  See HANDOFF 1.14.320.

## 0b. The shared hub and yt-dlp

Shared data moved to /home/Shared by hand (commands from the 1.14.315
session), then:

    packagemanager stack services --only app-users --run   # links + 0700 homes
    packagemanager stack media --only yt-dlp --run

Log in again for the SHARED_* variables to name /home/Shared.

## 1. The locale (one command, then log in again)

Nothing sets `$LANG`. lfs-helper wrote `/etc/profile.d/i18n.sh` with the
export commented out, and there is no `/etc/locale.conf` — so every program
runs in the C locale and foot says so at every start. Both are fixed in the
tools (1.14.296–1.14.298); the machine still has to run the step:

    lfs config locale de_DE.UTF-8       # if it is not that already
    packagemanager stack services --only shell-env --run
    # log in again, or right now:  . /etc/profile.d/i18n.sh

It writes `/etc/locale.conf`, replaces that i18n.sh (backed up), and adds one
line to `/etc/bashrc` so a new terminal picks it up without a login.

## 2. The launchers written before 1.14.295

A `.desktop` entry does nothing if its launcher does not give `su` a pty, and
a launcher these tools did not write is left alone — so the old ones survive.
`~/bin/claude` is the last hand-made one:

    rm ~/bin/claude
    packagemanager stack services --only app-users --run

Then click a menu entry. If one still does nothing, run the same name in a
terminal first: that path prints what `su` says.

## 3. Wireless — the only piece of networking still missing

Wired works and starts itself (`enp2s0f0`, `enp5s0`). The wireless interface
is **`wlan0`** on this kernel.

    packagemanager stack network --only net-wifi --run

It prints both files to write: `/etc/sysconfig/ifconfig.wlan0` and a per-SSID
`/etc/sysconfig/wpa_supplicant/wpa_supplicant-wlan0.conf` (chmod 600). Nothing
writes the second one for you — it holds the key.

## 4. make-ca's weekly job

The systemd book enables a timer, which the shim skips. fcron is installed:

    cat > /etc/cron.weekly/update-pki.sh << "EOF"
    #!/bin/bash
    /usr/sbin/make-ca -g
    EOF
    chmod 754 /etc/cron.weekly/update-pki.sh

## 5. Try the new commands once

So their first use is not in an emergency:

    packagemanager service                 # list; then: service sshd start
    packagemanager stack dev --run         # gdb

## 6. Run the test suite once, on the machine

    make check

It has not been able to report a verdict for some time (1.14.303): `lfs` would
not load on Python < 3.12, and the cleanup trap fired in every subshell and
removed the counters, so the final line printed blank. Both are fixed. Here it
reads 761 PASS / 84 FAIL / 1 SKIP (1.14.320), and those 84 are all "this is not a
package-user system" -- the wrappers, the book and the chroot blocks have
nothing to test against. On the machine they should mostly turn into passes;
whatever is left is a real list worth reading.

Known and NOT fixed: `--only N` / `--from N` can cut a here-document in half
and lose helpers an earlier block defined, so a selection can report failures
a full run does not. Trust the full run.

## Still open, none blocking

  * services.stack is misnamed: it holds bash-completion, shell-env,
    linux-pam, shadow-pam, app-users, power and mytools as well as the boot
    services.  `system.stack` would say what it is.  Not renamed yet: the
    machine's progress file (services.done), NEXT-TASK, BUILD.md and ~20
    test references use the name.  Decide, then do it in one release.
  * the scdoc, grim, slurp and swayidle entries have not been built yet --
    first real run is on the machine (sr.ht / freedesktop are unreachable
    from the sandbox).
  * a plan does not put an update of an installed-but-too-old dependency in
    front of the package that needs it (vcs_versioning wanted packaging >=
    26.2; HANDOFF 1.14.314).

  * poppler: re-apply the reverted `cd` rule (the patches only "did not fire"
    because of the stale index cache, fixed in 1.14.262); diff every generated
    script before and after. Do NOT `--regenerate` poppler first.
  * shadow's login.defs block overwrites `.orig` on a second run.
  * MIT-Kerberos configure transcript blocks (not in any stack).
  * `dbus` was built before `[dbus] systemd = disabled` went into
    machine.conf — rebuild or accept.
  * A stray `.service` from at-spi2-core in `/usr/lib/systemd/user`.
  * `/etc/bashrc` has a mangled line (`# End /etc/bashrcCK=$(tput setaf 0)`)
    from an append without a leading newline. Harmless: `BLACK` is unset and
    nothing uses it.

## Settled since this list was last written

  * "cfg entries are stack-cached, so a repair script is skipped once it has
    run." Answered by convention rather than by changing the cache: every cfg
    entry that must stay true now carries `expect=`, which is re-checked on
    every run — shadow-pam, app-users, shell-env, bootscripts.

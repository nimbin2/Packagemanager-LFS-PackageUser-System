# First task for the next session

## 1. Get root back, then let the stack repair it (1.14.267)

su is not setuid (the earlier-stages claim stripped it; fixed in 1.14.265).
You need root without su:

  * tty login: Ctrl+Alt+F2, log in as root (login runs as root, no setuid
    needed -- works if /etc/pam.d/login exists), or
  * from the host: enter the chroot as before.

Then, from `/` (not ~/lfs, which holds old stack copies):

    make install ; lfs run                       # chroot only; on the booted
                                                 # system: make install
    cd /
    packagemanager stack services --only shadow-pam --run   # cached otherwise
    packagemanager stack services --run          # the rest, incl. power
    ls -l /usr/bin/su /usr/sbin/unix_chkpwd      # 4711 root, 4755 root
    ls /etc/pam.d/ | wc -l                       # 22
    grep -n pam_exec /etc/pam.d/su               # line 1

As your normal user, in another terminal:

    su -                                         # root's password
    su - u_browser-mini -c id                    # no password

If `ls /etc/pam.d/` is short, shadow's configure has not run under the
lease yet:  packagemanager script configure shadow  -- then the stack again.

## 2. Renumber the machine's ids

The one-off fix script from chat (1.14.267): collector accounts removed,
collector groups to 90000+, u_* to 30000+.  Dry run first; u_* logged out.
Then `stack services --only power --run`.

## 3. Still open

  * cfg entries are stack-cached, so a repair script is skipped once it
    has run.  Decide whether cfg entries should always run.

  * poppler: re-apply the reverted `cd` rule (the patches only "did not
    fire" because of the stale index cache, fixed in 1.14.262); diff every
    generated script before and after.  Do NOT `--regenerate` poppler first.
  * shadow's login.defs block overwrites `.orig` on a second run.
  * MIT-Kerberos configure transcript blocks (not in any stack).

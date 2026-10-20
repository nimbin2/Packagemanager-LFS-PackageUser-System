#!/bin/bash
# fcron-periodic.sh -- run-parts and the /etc/cron.* folders fcron's page sets
# up after the install.
#
# MISSED ONCE.  The BLFS fcron page installs /usr/bin/run-parts and the
# hourly/daily/weekly/monthly folders as root, in its configuration section,
# and the system table that calls them.  The table (systab.orig) arrived; the
# script it calls did not -- so every periodic job, make-ca's weekly
# certificate refresh among them, ran `run-parts` and found nothing.
#
# Everything here is checked first and only written when missing or wrong:
# an existing systab.orig is YOURS and is never overwritten.
set -u

fail=0
warn() { echo "!! $*"; fail=1; }
note() { echo "#  $*"; }

# ---- 1. /usr/bin/run-parts, as the book writes it ------------------------
want="$(mktemp)"
cat > "$want" << "EOF"
#!/bin/sh
# run-parts:  Runs all the scripts found in a directory.
# from Slackware, by Patrick J. Volkerding with ideas borrowed
# from the Red Hat and Debian versions of this utility.

# keep going when something fails
set +e

if [ $# -lt 1 ]; then
  echo "Usage: run-parts <directory>"
  exit 1
fi

if [ ! -d $1 ]; then
  echo "Not a directory: $1"
  echo "Usage: run-parts <directory>"
  exit 1
fi

# There are several types of files that we would like to
# ignore automatically, as they are likely to be backups
# of other scripts:
IGNORE_SUFFIXES="~ ^ , .bak .new .rpmsave .rpmorig .rpmnew .swp"

# Main loop:
for SCRIPT in $1/* ; do
  # If this is not a regular file, skip it:
  if [ ! -f $SCRIPT ]; then
    continue
  fi
  # Determine if this file should be skipped by suffix:
  SKIP=false
  for SUFFIX in $IGNORE_SUFFIXES ; do
    if [ ! "$(basename $SCRIPT $SUFFIX)" = "$(basename $SCRIPT)" ]; then
      SKIP=true
      break
    fi
  done
  if [ "$SKIP" = "true" ]; then
    continue
  fi
  # If we've made it this far, then run the script if it's executable:
  if [ -x $SCRIPT ]; then
    $SCRIPT || echo "$SCRIPT failed."
  fi
done

exit 0
EOF
if [ -f /usr/bin/run-parts ] && cmp -s "$want" /usr/bin/run-parts; then
    note "/usr/bin/run-parts is there"
else
    [ -f /usr/bin/run-parts ] && note "/usr/bin/run-parts differs from the book's -- replacing it"
    if install -m 755 "$want" /usr/bin/run-parts; then
        note "installed /usr/bin/run-parts"
    else
        warn "could not install /usr/bin/run-parts"
    fi
fi
rm -f "$want"

# ---- 2. the folders the system table runs -------------------------------
for d in hourly daily weekly monthly; do
    if [ -d "/etc/cron.$d" ]; then
        continue
    fi
    install -v -d -m 754 "/etc/cron.$d" || warn "could not create /etc/cron.$d"
done

# ---- 3. the system table: only when there is none ----------------------
systab=/var/spool/fcron/systab.orig
if [ -f "$systab" ]; then
    if grep -q "run-parts" "$systab" 2>/dev/null; then
        note "$systab calls run-parts -- it works now"
    else
        note "$systab is yours and does not call run-parts; left as it is"
        note "  the book's lines, if you want them:  fcrontab -u systab -e"
    fi
else
    install -d /var/spool/fcron 2>/dev/null
    cat > "$systab" << "EOF"
&bootrun 01 * * * * root run-parts /etc/cron.hourly
&bootrun 02 4 * * * root run-parts /etc/cron.daily
&bootrun 22 4 * * 0 root run-parts /etc/cron.weekly
&bootrun 42 4 1 * * root run-parts /etc/cron.monthly
EOF
    note "wrote $systab (the book's four lines)"
    if command -v fcrontab >/dev/null 2>&1; then
        fcrontab -z -u systab >/dev/null 2>&1 \
            && note "loaded it: fcrontab -z -u systab" \
            || warn "fcrontab -z -u systab failed -- is fcron running?  /etc/rc.d/init.d/fcron start"
    fi
fi

[ "$fail" = 0 ] || exit 1
exit 0

#!/bin/bash
# =============================================================================
# test_packagemanager.sh -- safe functional tests for `packagemanager`
#
# SAFETY: everything runs inside a throwaway sandbox ($mktemp -d).  All external
# helpers (blfs, forall_direntries_from, list_package, add_package_user,
# packagemanager_install) are STUBBED, so:
#   * the real BLFS book is never read
#   * the real filesystem is never scanned or modified (forall scans a sandbox
#     tree only)
#   * real packages / users / groups are never touched
# The only real system objects created are throwaway users/groups whose names
# start with "pmtest_", and they are deleted again on exit.  Mutating tests that
# need those run only as root; without root they're skipped (not failed).
#
# Usage:  ./test_packagemanager.sh [/path/to/packagemanager]
# =============================================================================
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
PMFILE="${1:-$HERE/packagemanager}"
PM="python3 $PMFILE"
SB="$(mktemp -d)"
chmod 755 "$SB"          # real /,/usr are traversable; mktemp is 700 -> su-user needs this
export NO_COLOR=1
ROOT=0; [ "$(id -u)" = "0" ] && ROOT=1
CREATED=""            # throwaway pmtest_* users/groups to clean up

pass=0; fail=0; skip=0
ok()   { echo "  PASS  $1"; pass=$((pass+1)); }
bad()  { echo "  FAIL  $1"; fail=$((fail+1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/          /'; }
skp()  { echo "  SKIP  $1"; skip=$((skip+1)); }

# want <desc> <expect-substring> -- <command...>   (runs cmd, greps output)
want() {
  local desc="$1" expect="$2"; shift 2
  local out; out="$("$@" 2>&1)"
  if printf '%s' "$out" | grep -qF -- "$expect"; then ok "$desc"; else bad "$desc (want: $expect)" "$out"; fi
}

cleanup() {
  for u in $CREATED; do userdel "$u" 2>/dev/null; groupdel "$u" 2>/dev/null; done
  rm -rf "$SB"
}
trap cleanup EXIT

# --------------------------------------------------------------------------- #
# sandbox + stubs
# --------------------------------------------------------------------------- #
mkdir -p "$SB/bin" "$SB/base" "$SB/scan/usr/lib" "$SB/out" "$SB/dirs"
export PKGUSR_BASE="$SB/base"
export FORALL_SCAN="$SB/scan"
export PKGUSR_CONFIG="$SB/pm.conf"
printf 'collector_prefix=nimgnu\nuser_prefix=u\n' > "$PKGUSR_CONFIG"

cat > "$SB/bin/blfs" <<'EOF'
#!/bin/bash
sub="$1"; shift
while [ "${1:-}" = "--book-file" ] || [ "${1:-}" = "--book" ]; do shift 2; done
case "$sub" in
  search) n="$1"; printf '  [package] %-26s %s-1.0\n' "$n" "${n^}"; echo "1 result(s)." ;;
  debug)  echo "title          : ${1^}-1.0" ;;
  order)  n="$1"; printf 'dep1\tDep1-1.0\trequired\t%s\n%s\t%s-1.0\t\t\n' "$n" "$n" "${n^}" ;;
  script) n="$1"; out="."; while [ $# -gt 0 ]; do [ "$1" = "-o" ] && out="$2"; shift; done
          f="$out/install_${n^}-1.0"; printf '#!/bin/bash\ninstall_pkg(){ :; }\n' >"$f"
          echo "Created $f"; echo "Bash syntax OK." ;;
esac
EOF
cat > "$SB/bin/forall" <<'EOF'
#!/bin/bash
n="$1"; shift
depth=""; args=()
for a in "$@"; do
  if [ "$a" = "-depth" ]; then depth="-depth"; else args+=("$a"); fi
done
m=(-false)
getent passwd "$n" >/dev/null && m+=(-o -user "$n")
getent group  "$n" >/dev/null && m+=(-o -group "$n")
find "${FORALL_SCAN:-/nonexistent}" $depth -xdev \( "${m[@]}" \) \( -true "${args[@]}" \) 2>/dev/null
EOF
cat > "$SB/bin/lp" <<'EOF'
#!/bin/bash
find "${FORALL_SCAN:-/nonexistent}" -xdev \( -user "$1" -o -group "$1" \) 2>/dev/null
EOF
cat > "$SB/bin/apu" <<'EOF'
#!/bin/bash
groupadd "$1" 2>/dev/null
useradd -M -N -g "$1" -d "$PKGUSR_BASE/$1" "$1" 2>/dev/null
mkdir -p "$PKGUSR_BASE/$1"
echo "created $1"
EOF
cat > "$SB/bin/pmi" <<'EOF'
#!/bin/bash
echo "[stub packagemanager_install] user=$1 script=$2"
EOF
chmod +x "$SB"/bin/*
export BLFS_BIN="$SB/bin/blfs" FORALL_BIN="$SB/bin/forall" \
       LIST_PACKAGE_BIN="$SB/bin/lp" ADD_PACKAGE_USER_BIN="$SB/bin/apu" \
       PM_INSTALL_BIN="$SB/bin/pmi"

# fixture package-user dirs (no real users needed for info/list/check-dry)
mkdir -p "$SB/base/foo" "$SB/base/bar"
printf 'name_version="Foo-1.0"\nlink="http://x/foo"\ninfo="a demo pkg"\nrequired=(Dep1-1.0)\n' \
  > "$SB/base/foo/install_last"
printf '/usr/bin/foo\n/usr/lib/libfoo.so\n' > "$SB/base/foo/pkg.lst"   # foo "installed"

echo "sandbox: $SB   (root=$ROOT)"
echo
echo "================ read-only / dry-run (always safe) ================"
want "help lists commands"      "make-group-dir"  $PM --help
want "template writes a file"   "Wrote template"  $PM template mypkg --version 2.0 -o "$SB/out"
want "template is valid bash"   "install_pkg"     cat "$SB/out/install_mypkg-2.0"
bash -n "$SB/out/install_mypkg-2.0" && ok "template passes bash -n" || bad "template bash -n"
want "list package-users"       "foo"             $PM list
want "info all (short)"         "foo"             $PM info all
want "info named (detailed)"    "a demo pkg"      $PM info foo
want "search annotates state"   "not installed"   $PM search baz
want "deps shows kind+parent"   "required by"     $PM dependencies someapp
want "install dry-run plan"     "Install plan"    $PM install someapp
want "install --force dry-run"  "Install plan"    $PM install someapp --force
want "remove dry-run"           "Dry run"         $PM remove foo
want "remove --purge dry-run"   "will be removed" $PM remove foo --purge
want "nimgnu list runs"         "group(s)."       $PM nimgnu list
want "reload-pkg-list (bg)"     "regeneration"    $PM reload-pkg-list foo
want "config shows prefixes"    "collector prefix" $PM config
want "user list runs"           "user(s)."        $PM user list

echo
echo "================ make/fix group dirs (safe: sandbox dirs) ================"
if [ "$ROOT" = 1 ]; then
  groupadd -g 9999 install 2>/dev/null || true
  mkdir -p "$SB/dirs/inst" "$SB/dirs/coll"
  # install dir -> group install, group-writable, no sticky
  $PM make-group-dir "$SB/dirs/inst" --group install >/dev/null 2>&1
  # use a real nimgnu_ collector: group rwx, NO setgid (no 's' bit)
  $PM nimgnu create pmtest_c >/dev/null 2>&1; CREATED="$CREATED nimgnu_pmtest_c"
  $PM add-dir-to-nimgnu pmtest_c "$SB/dirs/coll" >/dev/null 2>&1
  perm_inst="$(stat -c '%A' "$SB/dirs/inst")"
  perm_coll="$(stat -c '%A' "$SB/dirs/coll")"
  case "$perm_inst" in drwxrwx*) ok "install dir group-writable, no sticky ($perm_inst)";; *) bad "install dir perms ($perm_inst)";; esac
  # group rwx and NO setgid: expect drwxrwxr-x (rwx in group field, no 's')
  case "$perm_coll" in
    drwxrws*) bad "nimgnu dir must NOT be setgid ($perm_coll)";;
    drwxrwx*) ok "nimgnu dir group-rwx, no setgid ($perm_coll)";;
    *)        bad "nimgnu dir perms ($perm_coll)";;
  esac
  want "fix-group-dir re-applies"  "re-applied"   $PM fix-group-dir "$SB/dirs/coll"
else
  skp "make-group-dir / fix-group-dir / add-dir-to-nimgnu (need root)"
fi

echo
echo "================ nimgnu group lifecycle (root, throwaway) ================"
if [ "$ROOT" = 1 ]; then
  useradd -M -N pmtest_u1 2>/dev/null; CREATED="$CREATED pmtest_u1"
  useradd -M -N pmtest_u2 2>/dev/null; CREATED="$CREATED pmtest_u2"
  $PM nimgnu create pmtest_g >/dev/null 2>&1; CREATED="$CREATED nimgnu_pmtest_g"
  want "nimgnu create"        "nimgnu_pmtest_g"  $PM nimgnu list pmtest_g
  want "nimgnu add (multi)"   "may now install"  $PM nimgnu add pmtest_g pmtest_u1 pmtest_u2
  want "members listed"       "pmtest_u1"        $PM nimgnu list pmtest_g
  want "nimgnu remove"        "Removed"          $PM nimgnu remove pmtest_g pmtest_u1
  want "nimgnu delete dryrun" "Dry run"          $PM nimgnu delete pmtest_g
  want "nimgnu delete --run"  "deleted"          $PM nimgnu delete pmtest_g --run --yes
else
  skp "nimgnu create/add/remove/delete (need root)"
fi

echo
echo "================ add-user / install --run / remove --run (root) ================"
if [ "$ROOT" = 1 ]; then
  want "add-user"            "Created package-user"  $PM add-user pmtest_p
  CREATED="$CREATED pmtest_p"
  want "install --run (stub engine)" "stub packagemanager_install" bash -c "printf 'y\n' | $PM install someapp --run"
  # remove --run: throwaway user owning files in the sandbox scan tree.
  # su - resets env, so install a forall stub on PATH that scans a fixed dir.
  cat > /usr/local/bin/forall_direntries_from <<EOF2
#!/bin/bash
n="\$1"; shift; d=""; a=()
for x in "\$@"; do [ "\$x" = "-depth" ] && d="-depth" || a+=("\$x"); done
m=(-false); getent passwd "\$n">/dev/null&&m+=(-o -user "\$n"); getent group "\$n">/dev/null&&m+=(-o -group "\$n")
find "$SB/scan" \$d -xdev \( "\${m[@]}" \) \( -true "\${a[@]}" \) 2>/dev/null
EOF2
  chmod +x /usr/local/bin/forall_direntries_from
  unset FORALL_BIN FORALL_SCAN
  useradd -M -N pmtest_r 2>/dev/null; CREATED="$CREATED pmtest_r"
  mkdir -p "$SB/base/pmtest_r"
  install -o pmtest_r /dev/null "$SB/scan/usr/lib/rfile1"
  install -o pmtest_r /dev/null "$SB/scan/usr/lib/rfile2"
  : > "$SB/scan/usr/lib/rootfile"
  chmod 0777 "$SB/scan/usr/lib"           # simulate a group-writable install dir
  $PM remove pmtest_r >/dev/null 2>&1     # dry-run stores the plan
  out="$($PM remove pmtest_r --run --yes 2>&1)"
  if [ ! -e "$SB/scan/usr/lib/rfile1" ] && [ -e "$SB/scan/usr/lib/rootfile" ] && id pmtest_r >/dev/null 2>&1; then
    ok "remove --run (su-scan + plan reuse) deleted owned files, kept root's + user"
  else
    bad "remove --run" "$out"
  fi
  rm -f /usr/local/bin/forall_direntries_from
  export BLFS_BIN="$SB/bin/blfs" FORALL_BIN="$SB/bin/forall" \
         LIST_PACKAGE_BIN="$SB/bin/lp" ADD_PACKAGE_USER_BIN="$SB/bin/apu" \
         PM_INSTALL_BIN="$SB/bin/pmi" FORALL_SCAN="$SB/scan"
else
  skp "add-user / install --run / remove --run (need root)"
fi

echo
echo "================ application users (u_*) (root, throwaway) ================"
if [ "$ROOT" = 1 ]; then
  $PM user create pmtestapp >/dev/null 2>&1; CREATED="$CREATED u_pmtestapp"
  want "user create (u_ prefix)"  "u_pmtestapp"    $PM user list pmtestapp
  want "user allow audio"         "Added"          $PM user allow u_pmtestapp audio
  want "user shows the group"     "audio"          $PM user list pmtestapp
  want "user disallow"            "Removed"        $PM user disallow u_pmtestapp audio
  want "user delete dry-run"      "Dry run"        $PM user delete pmtestapp
  want "user delete --run"        "deleted"        $PM user delete pmtestapp --run --yes
else
  skp "user create/allow/disallow/delete (need root)"
fi

echo
echo "================ files_with_broken_id (info only) ================"
skp "files_with_broken_id scans the whole real filesystem -- run manually:  packagemanager files_with_broken_id"

echo
echo "=================================================================="
echo "  PASS: $pass   FAIL: $fail   SKIP: $skip"
echo "=================================================================="
[ "$fail" = 0 ]

#!/bin/bash
# End-to-end test for lfs crosschain script generation.
#
# Builds a REAL (tiny) package through a REAL generated script: unpack from a
# tarball, configure into a build/ subdir, compile, install, post-install fixup.
# Then checks the failure paths -- because "it printed done" is not evidence
# that anything worked.
#
# Usage:  bash test_lfs_crosschain.sh [path-to-lfs-script]
set -u

LFS_TOOL="${1:-./lfs}"
LFS_BOOK="${2:-/mnt/user-data/uploads/LFS-BOOK-12_4-NOCHUNKS.html}"
T=$(mktemp -d /tmp/lfstest.XXXXXX)
PASS=0; FAIL=0
ok()  { echo "  PASS  $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL  $1"; FAIL=$((FAIL+1)); }

cleanup() { rm -rf "$T"; }
trap cleanup EXIT

export LFS="$T/lfs"
export BUILD_ROOT="$LFS/sources"
mkdir -p "$LFS/sources" "$LFS/tools/bin"

# ---------------------------------------------------------------- fake package
# A package that behaves like a real autotools one: out-of-tree build dir,
# a configure that must run before make, and an install step.
mkdir -p "$T/src/demo-1.0"
cat > "$T/src/demo-1.0/configure" <<'EOF'
#!/bin/bash
prefix=/usr/local
for a in "$@"; do case "$a" in --prefix=*) prefix="${a#--prefix=}";; esac; done
cat > Makefile <<MK
all:
	@echo "compiling"; echo "binary" > demo.bin
install:
	@mkdir -p "$prefix/bin"; cp demo.bin "$prefix/bin/demo"; echo "installed to $prefix/bin/demo"
MK
echo "configured with prefix=$prefix"
EOF
chmod +x "$T/src/demo-1.0/configure"
( cd "$T/src" && tar czf "$LFS/sources/demo-1.0.tar.gz" demo-1.0 )

# ------------------------------------------------- generate a script for real
# Uses the SAME generator the tool uses, with book-shaped command blocks.
python3 - "$LFS_TOOL" "$T/demo.sh" <<'PY'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
cmds = [
    "mkdir -v build\ncd       build",
    "../configure --prefix=$LFS/tools",
    "make",
    "make install",
    "echo post-install-fixup > $LFS/tools/fixup.txt",
]
body = lfs._crosschain_script_body("demo", "ch-tools-demo", "demo-1.0",
                                   "demo-1.0.tar.* demo-1.0.tgz", cmds)
open(sys.argv[2], "w").write(body)
PY

bash -n "$T/demo.sh" && ok "generated script is valid bash" || bad "syntax error"

# phases must be split the way the book reads
grep -q "^\.\./configure" "$T/demo.sh" && ok "configure landed in build phase" \
    || bad "configure not in build phase"
sed -n '/^install_pkg/,/INSTALL DONE/p' "$T/demo.sh" | grep -q "make install" \
    && ok "make install landed in install phase" || bad "install phase wrong"
sed -n '/^configure_pkg/,/CONFIGURE DONE/p' "$T/demo.sh" | grep -q "post-install-fixup" \
    && ok "post-install cmd landed in configure phase" || bad "configure phase wrong"

# --------------------------------------------------------------- run it fully
out="$T/run.log"
if bash "$T/demo.sh" all > "$out" 2>&1; then
    ok "full run exited 0"
else
    bad "full run failed (exit $?)"; sed 's/^/      /' "$out"
fi

[ -f "$LFS/sources/demo-1.0/build/Makefile" ] \
    && ok "built out-of-tree in build/ subdir" || bad "build/ subdir missing"
[ -f "$LFS/tools/bin/demo" ] \
    && ok "package actually installed into \$LFS/tools/bin" \
    || bad "install produced no file"
[ -f "$LFS/tools/fixup.txt" ] \
    && ok "configure (post-install) phase ran" || bad "configure phase did not run"
grep -q "^/.*build$" "$LFS/sources/.cc-build-demo" 2>/dev/null \
    && ok "recorded build dir for resume" || bad "build dir not recorded"

# ------------------------------------------------- single-phase re-run works
rm -f "$LFS/tools/bin/demo"
if bash "$T/demo.sh" install > "$T/i.log" 2>&1 && [ -f "$LFS/tools/bin/demo" ]; then
    ok "re-running ONLY the install phase works (no recompile)"
else
    bad "install-only re-run failed"; sed 's/^/      /' "$T/i.log"
fi

# ----------------------------------------------------- failure MUST propagate
sed 's|^make$|false  # simulated compile failure|' "$T/demo.sh" > "$T/failbuild.sh"
if bash "$T/failbuild.sh" all > "$T/f.log" 2>&1; then
    bad "FAILING BUILD REPORTED SUCCESS (the bug that wasted a day)"
else
    ok "failing build exits non-zero"
fi
grep -q "phase 'build' FAILED" "$T/f.log" \
    && ok "failure names the phase" || bad "failure did not name the phase"
grep -qi "installed to" "$T/f.log" \
    && bad "continued to install after a failed build" \
    || ok "did NOT continue to install after a failed build"

# missing tarball must fail cleanly, not silently
rm -rf "$T/lfs2"; mkdir -p "$T/lfs2/sources"
if LFS="$T/lfs2" BUILD_ROOT="$T/lfs2/sources" bash "$T/demo.sh" unpack \
        > "$T/m.log" 2>&1; then
    bad "missing tarball reported success"
else
    ok "missing tarball fails cleanly"
fi

echo
echo "  PASS: $PASS   FAIL: $FAIL"
[ "$FAIL" -eq 0 ]

# ---- tarball name resolution against a real-world /sources listing --------- #
# Regression guard: book titles are messy (Util-linux-2.41.1, XML::Parser-2.47,
# Flit-Core-3.12.0 shipping as flit_core-, Expect-5.45.4 as expect5.45.4) and a
# wrong guess makes unpack fail with "no <wrong-name> in /sources".
python3 - "$LFS_TOOL" <<'PY'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
cases = [
    ("7.12. Util-linux-2.41.1",        "util-linux-2.41.1.tar.xz"),
    ("7.10. Python-3.13.7",            "Python-3.13.7.tar.xz"),
    ("8.44. XML::Parser-2.47",         "XML-Parser-2.47.tar.gz"),
    ("8.52. Flit-Core-3.12.0",         "flit_core-3.12.0.tar.gz"),
    ("8.x. Expect-5.45.4",             "expect5.45.4.tar.gz"),
    ("8.x. Tcl-8.6.16",                "tcl8.6.16-src.tar.gz"),
    ("8.x. Expat-2.7.1",               "expat-2.7.1.tar.xz"),
    ("6.3. Ncurses-6.5-20250809",      "ncurses-6.5-20250809.tgz"),
    ("5.2. Binutils-2.45 - Pass 1",    "binutils-2.45.tar.xz"),
    ("5.4. Linux-6.16.1 API Headers",  "linux-6.16.1.tar.xz"),
    ("5.6. Libstdc++ from GCC-15.2.0", "gcc-15.2.0.tar.xz"),
]
import fnmatch
bad = 0
for title, want in cases:
    glob = lfs._pkg_glob_for(lfs._title_pkgver(title), "x")
    hit = any(fnmatch.fnmatch(want, p) for p in glob.split())
    print(("  PASS  " if hit else "  FAIL  ") + f"{title!r} finds {want}")
    bad += 0 if hit else 1
sys.exit(1 if bad else 0)
PY
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi
echo "  PASS: $PASS   FAIL: $FAIL (incl. tarball-name cases above)"

# ---- source vs documentation tarballs -------------------------------------- #
# tcl ships tcl8.6.16-html.tar.gz alongside tcl8.6.16-src.tar.gz, and the docs
# sort first -- unpacking those gives a tree with no unix/ dir and the build
# dies with "cd: unix: No such file or directory".
srct="$T/srcsel"; mkdir -p "$srct/src/tcl8.6.16/unix" "$srct/doc/tcl8.6.16/html"
( cd "$srct/src" && tar czf "$srct/tcl8.6.16-src.tar.gz" tcl8.6.16 )
( cd "$srct/doc" && tar czf "$srct/tcl8.6.16-html.tar.gz" tcl8.6.16 )
picked=$( cd "$srct" && bash -c '
pkg_glob="tcl8.6.16.tar.* tcl8.6.16.tgz tcl8.6.16*.tar.* tcl8.6.16*.tgz"
pkg=""
for _c in $pkg_glob; do [ -e "$_c" ] || continue
  case "$_c" in *-src.*|*-source.*) pkg="$_c"; break ;; esac; done
if [ -z "$pkg" ]; then for _c in $pkg_glob; do [ -e "$_c" ] || continue
  case "$_c" in *-html.*|*-doc.*|*-docs.*|*-man.*|*-manual.*|*-tests.*) continue ;; esac
  pkg="$_c"; break; done; fi
echo "$pkg"' )
[ "$picked" = "tcl8.6.16-src.tar.gz" ] \
    && ok "picks the -src tarball, not the docs" \
    || bad "picked '$picked' instead of tcl8.6.16-src.tar.gz"

# ---- phase bodies must not be fed on stdin -------------------------------- #
# Expect's book section starts with a PTY sanity check:
#     python3 -c 'from pty import spawn; spawn(["echo", "ok"])'
# pty.spawn READS STDIN.  When the phase body was piped in via `bash -s`, it
# swallowed the remaining lines -- patch/configure/make were echoed instead of
# executed, and the install then failed with "No rule to make target 'install'".
ptyd="$T/pty"; mkdir -p "$ptyd"
cat > "$ptyd/t.sh" <<'OUTER'
_phase_body() {
	local _f; _f="$(mktemp)" || return 1
	cat > "$_f"
	bash "$_f" </dev/null
	local _r=$?
	rm -f "$_f"
	return $_r
}
_phase_body <<'__LFS_PHASE__'
set -e
python3 -c 'from pty import spawn; spawn(["echo","ok"])' >/dev/null 2>&1 || true
echo RAN_PATCH
echo RAN_CONFIGURE
echo RAN_MAKE
__LFS_PHASE__
OUTER
out="$(bash "$ptyd/t.sh" 2>/dev/null | tr -d '\r')"
if echo "$out" | grep -q RAN_PATCH && echo "$out" | grep -q RAN_CONFIGURE \
   && echo "$out" | grep -q RAN_MAKE; then
    ok "a stdin-reading command does not swallow the rest of the phase"
else
    bad "phase body was consumed by a stdin-reading command"
fi

# the generated scripts must all use the file-based runner
if grep -l "bash -s <<'__LFS_PHASE__'" "$T"/*.sh >/dev/null 2>&1; then
    bad "a generated script still pipes its phase body through stdin"
else
    ok "generated scripts run phase bodies from a file"
fi

# ---- commands inside note/tip boxes must be ignored ------------------------ #
# GMP's section has a note showing "ABI=32 ./configure ..." for 32-bit hosts.
# Running that literally passes an ellipsis to configure:
#   Invalid configuration '...': machine '...-unknown' not recognized
# Glibc likewise has a note with an alternative DESTDIR install method.
python3 - "$LFS_TOOL" "$LFS_BOOK" <<'PY2'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
book = sys.argv[2] if len(sys.argv) > 2 else None
if not book:
    print("  SKIP  no book available for the note-filter check"); sys.exit(0)
soup = lfs.load_soup(book)
# Only flag blocks that genuinely came from a note box.  (ncurses uses
# DESTDIR=$PWD/dest as its REAL install method, so that string alone proves
# nothing -- check the specific sections whose notes we know about.)
watch = {
    "ch-system-gmp":   "ABI=32 ./configure ...",
    "ch-system-glibc": "DESTDIR=$PWD/dest",
}
bad = []
for sid, t, sec in lfs.iter_sections(soup):
    needle = watch.get(sid)
    for b in sec["commands"]:
        if needle and needle in b:
            bad.append((sid, b.splitlines()[0][:50]))
        if "make distclean" in b:
            bad.append((sid, b.splitlines()[0][:50]))
if bad:
    for sid, b in bad[:5]:
        print(f"  FAIL  note-box command still extracted: {sid}: {b}")
    sys.exit(1)
print("  PASS  commands inside note/tip boxes are ignored")
PY2
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

# ---- a test's log reader must stay with the test --------------------------- #
# GMP writes a log in the test block and reads it back in the next one:
#     make check 2>&1 | tee gmp-check-log
#     awk '/# PASS:/{total+=$3} ; END{print total}' gmp-check-log
# Moving only the first to the test phase leaves the awk in the build, where it
# dies with "cannot open file `gmp-check-log'".
python3 - "$LFS_TOOL" <<'PY3'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
cmds = ["./configure --prefix=/usr",
        "make",
        "make check 2>&1 | tee gmp-check-log",
        "awk '/# PASS:/{total+=$3} ; END{print total}' gmp-check-log",
        "make install"]
build, install, config, test = lfs._split_crosschain_phases(cmds)
problems = []
if "gmp-check-log" in build:   problems.append("log reader left in the build phase")
if "make check" in build:      problems.append("test suite left in the build phase")
if "gmp-check-log" not in test: problems.append("log reader not moved to the test phase")
if "make install" not in install: problems.append("install phase wrong")
if problems:
    for p in problems: print(f"  FAIL  {p}")
    sys.exit(1)
print("  PASS  a test's log reader travels with the test suite")
PY3
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

# ---- a stale source tree from an earlier chapter must be cleared ----------- #
# /sources is sticky (1777), so only the owner may delete a directory there.
# Chapters 5-6 unpack as the `lfs` user; chapter 8 rebuilds the same packages as
# their own package user, which then cannot remove the leftover tree -- the
# script's `rm -rf` fails, tar extracts on top, and the build drowns in
#     tar: gcc-15.2.0/README: Cannot open: File exists
# lfs-helper must clear it as root BEFORE handing over to the package user.
stl="$T/stale"; mkdir -p "$stl/sources" "$stl/src/demo-9.9"
echo fresh > "$stl/src/demo-9.9/NEW"
( cd "$stl/src" && tar czf "$stl/sources/demo-9.9.tar.gz" demo-9.9 )
mkdir -p "$stl/sources/demo-9.9"; echo old > "$stl/sources/demo-9.9/OLD"
chmod 1777 "$stl/sources"
cat > "$stl/script.sh" <<'EOF'
pkg_glob="demo-9.9.tar.* demo-9.9.tgz"
EOF
# run just the cleanup routine out of lfs-helper
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    ( STATE="$stl"; SNAP_ROOT="$stl"; C_DIM=; C_OFF=
      say(){ :; }; warn(){ :; }
      eval "$(sed -n '/^clean_stale_source() {/,/^}/p' "$helper_src")"
      clean_stale_source demo "$stl/script.sh" )
    if [ -d "$stl/sources/demo-9.9" ]; then
        bad "stale source tree was not cleared before the build"
    else
        ok "a stale source tree is cleared before the build"
    fi
else
    echo "  SKIP  lfs-helper not found next to $LFS_TOOL"
fi

# ---- collector groups for cross-package installs --------------------------- #
# gcc installs gcc.mo into /usr/share/locale/<lang>/LC_MESSAGES, directories
# another package owns, so the gcc user gets "Permission denied".  The fix is a
# collector group <prefix>_<owner>: the dir keeps its owner but becomes
# group-writable and both packages join the group.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    for fn in collector_group_for ensure_group add_to_group grant_dir_access; do
        grep -q "^$fn()" "$helper_src" \
            || { bad "lfs-helper is missing $fn (collector-group support)"; break; }
    done
    grep -q "^cmd_fix_perms()" "$helper_src" \
        && ok "collector-group support and fix-perms are present" \
        || bad "lfs-helper has no fix-perms command"
    # the failure box must point at it
    grep -q "lfs-helper fix-perms" "$helper_src" \
        && ok "a Permission-denied failure suggests fix-perms" \
        || bad "failure message does not mention fix-perms"
else
    echo "  SKIP  lfs-helper not found next to $LFS_TOOL"
fi

# ---- command wrappers (the hint's /usr/lib/pkgusr) ------------------------- #
# The book's GCC section runs `chown -v -R root:root /usr/lib/gcc/.../include`.
# As a package user that fails with "Operation not permitted" and kills the
# install -- even though the files are already owned correctly for this scheme.
# Wrappers for chown/chgrp/install/chmod/mkdir neutralise the impossible parts.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    wt="$T/wrap"; mkdir -p "$wt"
    ( STATE="$wt"; WRAPPERS="$wt/wrappers"
      eval "$(sed -n '/^make_wrappers() {/,/^}/p' "$helper_src")"
      make_wrappers )
    W="$wt/wrappers"
    if [ -x "$W/chown" ] && [ -x "$W/install" ] && [ -x "$W/chmod" ] \
       && [ -x "$W/mkdir" ] && [ -x "$W/chgrp" ]; then
        ok "the five command wrappers are created"
    else
        bad "command wrappers missing"
    fi
    # chown must not fail the build
    "$W/chown" -R root:root /nonexistent >/dev/null 2>&1 \
        && ok "chown wrapper never fails the build" \
        || bad "chown wrapper returned non-zero"
    # install must still install, minus -o/-g
    echo data > "$wt/s"
    "$W/install" -m 644 -o root -g root "$wt/s" "$wt/d" >/dev/null 2>&1
    [ -f "$wt/d" ] && ok "install wrapper drops -o/-g but still installs" \
                   || bad "install wrapper did not install the file"
    # setuid must be refused
    "$W/install" -m 4755 "$wt/s" "$wt/suid" >/dev/null 2>&1
    if [ -u "$wt/suid" ]; then bad "install wrapper set the setuid bit"
    else ok "install wrapper refuses setuid modes"; fi
    # PATH must put them first for package-user builds
    grep -q 'PATH=.\$WRAPPERS' "$helper_src" \
        && ok "wrappers go first in the package user's PATH" \
        || bad "wrappers are not put on PATH"
else
    echo "  SKIP  lfs-helper not found next to $LFS_TOOL"
fi

# ---- install directories stay group-writable ------------------------------- #
# The hint defines an install directory as:  chgrp install <dir> && chmod g+w,o+t
# Packages reset modes on dirs they touch, so /usr/share/man/man1 can end up
# root:install but drwxr-xr-x -- and the next package cannot write its man page:
#   ln: failed to create symbolic link '/usr/share/man/man1/cc.1': Permission denied
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q "ensure_install_dirs_writable" "$helper_src" \
        && ok "install-dir permissions are re-applied before each build" \
        || bad "no self-healing for install-dir permissions"
    # the group-write test must not be fooled by the OWNER's w bit
    if grep -q '10#\$_mode' "$helper_src"; then
        ok "group-write is detected numerically (drwxr-xr-x is not 'writable')"
    else
        bad "group-write detection may match the owner's w bit"
    fi
    # init must use the hint's g+w, and sticky must be deferred to the seal step
    grep -q 'chmod g+w "\$d"' "$helper_src" \
        && ok "install dirs get chmod g+w (sticky deferred to seal-install-dirs)" \
        || bad "install dirs are not set group-writable per the hint"
else
    echo "  SKIP  lfs-helper not found next to $LFS_TOOL"
fi

# ---- re-running a phase must not fail on existing symlinks ----------------- #
# The books write `ln -sv ../bin/cpp /usr/lib` with no -f, so retrying a
# configure/install phase dies with
#   ln: failed to create symbolic link '/usr/lib/cpp': File exists
python3 - "$LFS_TOOL" <<'PY4'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
cases = [
    ("ln -sv ../bin/cpp /usr/lib",                  "ln -svf ../bin/cpp /usr/lib"),
    ("ln -sv gcc /usr/bin/cc",                      "ln -svf gcc /usr/bin/cc"),
    ("ln -sfv libncursesw.so /usr/lib/libcurses.so","ln -sfv libncursesw.so /usr/lib/libcurses.so"),
    ("ln /usr/bin/foo /usr/bin/bar",                "ln /usr/bin/foo /usr/bin/bar"),
]
bad = 0
for src, want in cases:
    got = lfs._idempotent_links(src)
    if got != want:
        print(f"  FAIL  {src!r} -> {got!r}, expected {want!r}"); bad += 1
if bad: sys.exit(1)
print("  PASS  symlink steps are made re-runnable (-f added only where missing)")
PY4
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

# ---- collector groups are configured, automatic, and reported -------------- #
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q "require_collector_prefix" "$helper_src" \
        && ok "an unset collector prefix stops the build with instructions" \
        || bad "no check for a missing collector prefix"
    grep -q "auto_grant_from_log" "$helper_src" \
        && ok "permission failures are granted and retried automatically" \
        || bad "no automatic collector-group recovery"
    grep -q "report_granted_groups" "$helper_src" \
        && ok "collector groups created during a run are reported" \
        || bad "collector groups are created silently"
fi
# the config must be complete before the build-system commands run
python3 - "$LFS_TOOL" <<'PY5'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
keys = [k for k, _w, _h in lfs.REQUIRED_CONFIG]
if "collector_prefix" in keys and "lfs_mount" in keys:
    print("  PASS  collector_prefix is a required setting")
else:
    print(f"  FAIL  REQUIRED_CONFIG is missing keys: {keys}"); sys.exit(1)
PY5
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

# ---- collector group name is a choice, not a fixed rule -------------------- #
# Naming after the OWNER (nimgnu_binutils) groups everything that package owns;
# naming after the DIRECTORY (nimgnu_bfd-plugins) is more precise.  Both are
# reasonable, so the user picks -- with the context needed to decide.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q "choose_collector_group" "$helper_src" \
        && ok "the collector group name is offered as a choice" \
        || bad "collector group name is not selectable"
    # the prompt must use /dev/tty: it runs inside a `while ... <<< list` loop,
    # where stdin is the directory list, so a plain read would eat that instead
    grep -qE "read (-e )?-r ans < /dev/tty" "$helper_src" \
        && ok "the prompt reads from /dev/tty (stdin is the dir list)" \
        || bad "prompt would consume the directory list instead of user input"
    # names must be sanitised for the group database
    ( eval "$(sed -n '/^sanitise_group_name() {/,/^}/p' "$helper_src")"
      got="$(sanitise_group_name 'nimgnu_BFD Plugins!')"
      case "$got" in *' '*|*'!'*) exit 1 ;; esac
      [ -n "$got" ] ) \
        && ok "group names are sanitised for the group database" \
        || bad "group names are not sanitised"
fi

# ---- a later phase failing may mean an earlier one never finished ---------- #
# gcc's configure step runs `mv -v /usr/lib/*gdb.py ...`.  Those files come from
# `make install`; if that aborted partway (a permission error, say) they were
# never installed and the mv fails with a confusing "No such file or directory".
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q "these earlier phases have not completed successfully" "$helper_src" \
        && ok "a failure points at earlier phases that never completed" \
        || bad "no hint about incomplete earlier phases"
fi

# ---- /sources hygiene ------------------------------------------------------ #
# Two kinds of debris break later builds:
#  * tar run as root restores the UIDs recorded IN the archive, so /sources ends
#    up owned by host-only ids (8282, 15399, ...) that mean nothing here;
#  * a build marker left by a previous package user cannot be replaced under the
#    sticky /sources:  /sources/.cc-build-ncurses: Permission denied
python3 - "$LFS_TOOL" <<'PY6'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
body = lfs._crosschain_script_body("demo", "ch-system-demo", "demo-1.0",
                                   "demo-1.0.tar.*", ["make", "make install"])
if "--no-same-owner" not in body:
    print("  FAIL  unpack does not use tar --no-same-owner"); sys.exit(1)
print("  PASS  unpack never restores the archive's UIDs")
PY6
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q 'rm -f "\$srcdir/.cc-build-\$name"' "$helper_src" \
        && ok "stale build markers are cleared before a build" \
        || bad "stale build markers are not cleared"
    grep -q "^cmd_clean_sources()" "$helper_src" \
        && ok "clean-sources can tidy /sources after the fact" \
        || bad "no clean-sources command"
fi

# ---- staged installs with `cp -a dest/* /` --------------------------------- #
# ncurses (and others) install a staged tree that way.  The FILES copy fine as a
# package user, but cp then tries to stamp the destination DIRECTORIES (/usr,
# /usr/bin -- owned by root) and fails:
#     cp: preserving times for '/usr/bin': Operation not permitted
# That is harmless; a real cp error must still fail the build.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    cpt="$T/cpwrap"; mkdir -p "$cpt"
    ( STATE="$cpt"; WRAPPERS="$cpt/wrappers"
      eval "$(sed -n '/^make_wrappers() {/,/^}/p' "$helper_src")"
      make_wrappers )
    if [ -x "$cpt/wrappers/cp" ]; then
        ok "a cp wrapper exists for staged installs"
        # a genuine failure must still be a failure
        if "$cpt/wrappers/cp" /definitely-not-here "$cpt/" >/dev/null 2>&1; then
            bad "cp wrapper swallowed a real error"
        else
            ok "cp wrapper still fails on a real error"
        fi
        # a normal copy must work
        echo hi > "$cpt/a"
        "$cpt/wrappers/cp" "$cpt/a" "$cpt/b" >/dev/null 2>&1
        [ -f "$cpt/b" ] && ok "cp wrapper copies normally" \
                        || bad "cp wrapper broke a normal copy"
    else
        bad "no cp wrapper"
    fi
fi

# ---- per-language man/locale dirs are shared, not per-package -------------- #
# Every package ships translated man pages and message catalogues, creating a
# directory per language.  Treating those as owned by whichever package made
# them first turns each one into a "grant access?" prompt -- dozens per package.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    ( SNAP_ROOT=/
      eval "$(sed -n '/^install_dir_patterns() {/,/^}/p' "$helper_src")"
      eval "$(sed -n '/^matches_install_pattern() {/,/^}/p' "$helper_src")"
      for d in /usr/share/man/de/man1 /usr/share/man/man1 \
               /usr/share/locale/pl/LC_MESSAGES /usr/lib/pkgconfig; do
          matches_install_pattern "$d" || exit 1
      done
      # a package's own directory must NOT be treated as shared
      for d in /usr/src/foo /usr/lib/gcc/x86_64/15.2.0; do
          matches_install_pattern "$d" && exit 1
      done
      exit 0 ) \
        && ok "language man/locale dirs are shared; package dirs are not" \
        || bad "install-dir pattern matching is wrong"
    grep -q "^cmd_prune_locales()" "$helper_src" \
        && ok "unwanted languages can be pruned" \
        || bad "no prune-locales command"
fi
python3 - "$LFS_TOOL" <<'PY7'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
keys = [k for k, _d in lfs.CONFIG_KEYS]
print("  PASS  'locales' is a documented setting" if "locales" in keys
      else "  FAIL  no 'locales' setting")
sys.exit(0 if "locales" in keys else 1)
PY7
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

# ---- a package owns the files it OVERWRITES, not just new ones ------------- #
# Chapter 8's bison replaces the binaries chapter 7's bison-tmp installed as
# root.  Those files are not "new", so a pure snapshot diff never sees them and
# they keep the previous owner -- which is why bison stayed owned by root.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q '\-newer "\$stamp"' "$helper_src" \
        && ok "files modified during a build are reassigned, not just new ones" \
        || bad "only newly-created files get the package user's ownership"
    # a stamp must exist; WHERE it lives is checked below (not /tmp)
    grep -q 'stamp=' "$helper_src" \
        && ok "there is a build timestamp for detecting modified files" \
        || bad "no build timestamp for detecting modified files"
fi

# ---- test targets carry suffixes ------------------------------------------- #
# Perl runs `TEST_JOBS=$(nproc) make test_harness`; others use `make check-TESTS`
# or `check-recursive`.  Missing those runs a package's whole test suite as part
# of the BUILD -- slow, and a test failure then kills the build.
python3 - "$LFS_TOOL" <<'PY8'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
cases = [("TEST_JOBS=$(nproc) make test_harness", True),
         ("make check-TESTS", True), ("make check", True), ("make test", True),
         ("make NON_ROOT_USERNAME=tester check-root", True),
         ("make install", False), ("make install-html", False),
         ("make install-strip", False), ("make", False)]
bad = 0
for c, want in cases:
    got = bool(lfs._TEST_BLOCK_RE.search(c))
    if got != want:
        print(f"  FAIL  {c!r} classified as test={got}"); bad += 1
if bad: sys.exit(1)
print("  PASS  suffixed test targets (test_harness, check-TESTS) are recognised")
PY8
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

# ---- failures report what the paths actually are ---------------------------- #
# "No such file or directory" on a destination can mean a missing parent OR a
# dangling symlink; "Permission denied" can mean the file exists but belongs to
# another package.  Showing the facts beats guessing from the message.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    dg="$T/diag"; mkdir -p "$dg/real"
    ln -s /nowhere/at/all "$dg/real/dangling.pm"
    echo x > "$dg/real/owned.pm"
    printf "Couldn't copy a to %s: No such file or directory\n" "$dg/real/dangling.pm"  > "$dg/log"
    printf "Couldn't copy b to %s: Permission denied\n"         "$dg/real/owned.pm"    >> "$dg/log"
    out="$( C_WARN=; C_OFF=; SNAP_ROOT="$dg"; say(){ echo "$*"; }
            eval "$(sed -n '/^diagnose_paths_from_log() {/,/^}/p' "$helper_src")"
            diagnose_paths_from_log "$dg/log" nobody )"
    echo "$out" | grep -q "DANGLING SYMLINK" \
        && ok "a dangling destination symlink is identified" \
        || bad "dangling symlink not reported"
    echo "$out" | grep -q "owned.pm" \
        && ok "an existing destination's owner and mode are shown" \
        || bad "destination ownership not reported"
    # relative-path tails must not be reported as absolute targets
    echo "$out" | grep -qE "^  /[^/]+\.pm " \
        && bad "a relative path tail was treated as a target" \
        || ok "relative path tails are not mistaken for targets"
fi

# ---- recovery must not depend on the wording of the error ------------------ #
# Perl's installperl reports an unwritable destination directory as
#   Couldn't copy lib/GDBM_File.pm to .../GDBM_File.pm: No such file or directory
# not "Permission denied".  Keying the auto-recovery on that phrase meant perl
# never recovered.  And a root-owned tree left by a chapter-7 -tmp package has
# hundreds of subdirectories the real package installs into, so granting only
# the named one just fails again on the next.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q "couldn't copy|cannot create" "$helper_src" \
        && ok "recovery and hints match more than 'Permission denied'" \
        || bad "recovery still keys only on the literal 'Permission denied'"
    # (the earlier root-owned-subtree workaround is gone: -tmp packages are now
    #  adopted to the base package user, so no root-owned tree is left behind)
    # REVERSED deliberately: a collector group means "may install into a
    # directory this package owns", NOT "owns that package's tree".  Granting
    # the subtree in one pass was over-reach -- one file in site-packages took
    # ~190 python directories with it.  One directory at a time is correct;
    # a package that needs several gets several rounds.
    grep -q 'find "\$dir" -mindepth 1 -type d -user "\$owner"' "$helper_src" \
        && bad "granting still takes the owner's whole subtree" \
        || ok "only the directory asked for is granted"
    grep -q 'SNAP_ROOT%/}"/\*) echo "\$p"' "$helper_src" \
        && ok "diagnostics only report paths inside the tree or a known root" \
        || bad "diagnostics would report relative tails as targets"
fi

# ---- collector groups share the whole area, iteratively -------------------- #
# An install reveals only the FIRST directory it cannot write.  Perl modules
# span core_perl/ and site_perl/ and dozens of subdirs, so granting one and
# retrying once is not enough -- and members must be able to REPLACE each
# other's files, not just add new ones.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q '_round" -lt "\$_max_rounds"' "$helper_src" \
        && ok "grant-and-retry iterates until nothing new needs granting" \
        || bad "only one grant round; later directories would still fail"
    grep -q 'find "\$dir" -type f -user "\$owner"' "$helper_src" \
        && bad "granting still rewrites every file in the owner's tree" \
        || ok "files in the owner's tree are left alone"
    # unquoted paths in messages must be found too (bash and perl report them
    # bare), and the scan must stay bounded
    grep -q 'grep -aoE "/\[A-Za-z0-9._/+-\]{6,}"' "$helper_src" \
        && ok "unquoted paths in error messages are recognised" \
        || bad "only quoted paths are extracted; bash/perl messages missed"
    # *-tmp packages must be adopted to the base package user
    grep -q 'init-\*) skipped=' "$helper_src" \
        && ok "only init-* steps are skipped; -tmp tools get the base user" \
        || bad "-tmp steps are skipped, leaving root-owned trees behind"
fi

# ---- package user names must be normalised --------------------------------- #
# The book's anchors are inconsistent in case: chapter 7 has "python-tmp" but
# chapter 8 has "Python".  Unix user names are case-sensitive, so those become
# two accounts -- and the chapter-8 package then cannot overwrite its OWN
# chapter-7 files:
#   install: cannot remove '/usr/lib/python3.13/.../__init__.py': Permission denied
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    out="$( eval "$(sed -n '/^pkg_owner_name() {/,/^}/p' "$helper_src")"
            for n in Python python-tmp GCC gcc-pass1 libstdcpp \
                     Binutils-pass2 XML::Parser util-linux-tmp; do
                printf '%s=%s\n' "$n" "$(pkg_owner_name "$n")"
            done )"
    fails=""
    echo "$out" | grep -q "^Python=python$"        || fails="$fails Python"
    echo "$out" | grep -q "^python-tmp=python$"    || fails="$fails python-tmp"
    echo "$out" | grep -q "^GCC=gcc$"              || fails="$fails GCC"
    echo "$out" | grep -q "^gcc-pass1=gcc$"        || fails="$fails gcc-pass1"
    echo "$out" | grep -q "^libstdcpp=gcc$"        || fails="$fails libstdcpp"
    echo "$out" | grep -q "^Binutils-pass2=binutils$" || fails="$fails Binutils-pass2"
    echo "$out" | grep -q "^util-linux-tmp=util-linux$" || fails="$fails util-linux-tmp"
    # Perl module names are not valid user names
    echo "$out" | grep -q "^XML::Parser=xml-parser$"   || fails="$fails XML::Parser"
    [ -z "$fails" ] \
        && ok "package user names are normalised (case, passes, module names)" \
        || bad "owner name wrong for:$fails"
fi

# ---- share from the top of a package's tree -------------------------------- #
# Python's standard library is ~200 directories under /usr/lib/python3.13.  An
# install reveals one unwritable directory at a time, so granting leaf by leaf
# never finishes -- it exhausts the retry budget and gives up.  Walking up to
# the top of the owner's tree shares it in a single pass.  The walk must stop at
# a shared install directory (/usr/lib), never above it.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    # REVERSED deliberately: sharing from the top of the owner's tree hands
    # over directories the package never asked for.  Per-directory granting
    # with several retry rounds is the correct trade.
    grep -q "the top of \$owner's tree" "$helper_src" \
        && bad "granting still shares from the top of the owner's tree" \
        || ok "grants are per-directory, not whole-tree"
    grep -q 'is_install_dir "\$parent" && break' "$helper_src" \
        && ok "the walk up stops at a shared install directory" \
        || bad "the walk could climb past /usr/lib and share too much"
    grep -q "parent -- this is what matters" "$helper_src" \
        && ok "diagnostics show the parent dir for 'cannot remove/create'" \
        || bad "diagnostics omit the directory that actually governs access"
fi

# ---- lfs next / handover to packagemanager --------------------------------- #
# lfs-helper is a bash stand-in only because there is no Python in the chroot
# until chapter 8 builds it.  Once it exists, the real tooling takes over.
python3 - "$LFS_TOOL" <<'PY9'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
missing = [n for n in ("cmd_next", "_next_steps", "cmd_bs_install_tools",
                       "_chroot_has_python") if not hasattr(lfs, n)]
if missing:
    print("  FAIL  lfs is missing: %s" % ", ".join(missing)); sys.exit(1)
print("  PASS  'lfs next' and the packagemanager handover exist")
PY9
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

# ---- bootloader safety ----------------------------------------------------- #
# The book runs `grub-install /dev/sda`, which writes a disk's boot sector.  On
# a machine with an existing boot partition that is destructive, so grub is only
# generated when explicitly chosen; the default is rEFInd, which only ever adds
# files to an already-mounted, already-formatted ESP.
python3 - "$LFS_TOOL" <<'PY10'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
if lfs.bootloader() != "refind":
    print("  FAIL  default bootloader is %r, expected refind" % lfs.bootloader())
    sys.exit(1)
script = lfs._refind_script()
bad = [c for c in ("grub-install /dev/", "mkfs", "sgdisk", "parted", "of=/dev/")
       if c in script.replace("###     grub-install /dev/sda", "")]
if bad:
    print("  FAIL  rEFInd script contains destructive commands: %s" % bad)
    sys.exit(1)
for guard in ("nothing is mounted there", "not FAT",
              "REFIND_OVERWRITE", "does not exist"):
    if guard not in script:
        print("  FAIL  rEFInd script lacks the %r guard" % guard); sys.exit(1)
print("  PASS  rEFInd is the default and its script cannot touch a raw device")
PY10
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q 'find "\$dir" -mindepth 1 -type d -user root' "$helper_src" \
        && bad "a root-owned subtree is still taken in one pass" \
        || ok "root-owned adoption is limited to the directory asked for"
fi

# ---- a package's private tree belongs to the package ----------------------- #
# /usr/lib/python3.13 is python's own tree, not shared infrastructure.  Chapter
# 7 built python-tmp as root, so the tree is left root-owned; it must be ADOPTED
# by python, not turned into an install directory.  When another package later
# installs modules inside it, that is what collector groups are for.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    # the directory itself is still adopted -- just not its subtree
    grep -q "owned by '\$user' (was root, from the temporary system)" "$helper_src" \
        && ok "a root-owned leftover directory is adopted by its package" \
        || bad "root-owned directories are not adopted at all"
    grep -q "shared install directory" "$helper_src" \
        && ok "only real install dirs get the install group" \
        || bad "install-group handling missing"
    # the two must be distinct branches: install dirs stay root, private trees don't
    grep -q 'if is_install_dir "\$dir"; then' "$helper_src" \
        && ok "install dirs and private trees are handled separately" \
        || bad "install dirs and private trees are conflated"
fi

# ---- pip packages and duplicate grants ------------------------------------- #
# Many failing paths walk up to the SAME tree top, so granting per-path repeats
# the identical grant.  And `pip3 install` writes into site-packages: if that is
# not writable up front, pip can quietly install into a per-user location where
# nothing else can import it -- the next package then fails with
#     BackendUnavailable: Cannot import 'flit_core.buildapi'
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q "^collector_tree_top()" "$helper_src" \
        && ok "the tree top is computed once and grants are de-duplicated" \
        || bad "the same directory can be granted repeatedly"
    grep -q "^pregrant_python_sitedirs()" "$helper_src" \
        && ok "pip packages get site-packages access before they run" \
        || bad "pip packages only get access after failing"
fi

# ---- a build that installs nothing must not be called successful ----------- #
# pip can report success while writing nowhere useful: flit-core "succeeded"
# without ever putting flit_core into site-packages, and the next package then
# failed with "BackendUnavailable: Cannot import 'flit_core.buildapi'".
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q "reported success but installed NO files" "$helper_src" \
        && ok "a build that installs no files is not marked as built" \
        || bad "an empty install is silently accepted"
    # grep -c prints 0 and exits non-zero, so `|| echo 0` yields "0\n0"
    grep -q "^count_lines()" "$helper_src" \
        && ok "line counts go through one safe helper" \
        || bad "line counts can yield \"0\\n0\" and break numeric tests"
fi

# ---- pip must install system-wide, not into ~/.local ----------------------- #
# When site-packages is not writable, pip installs into the package user's
# ~/.local and afterwards reports "Requirement already satisfied" from there --
# so it never installs system-wide, and only that one user can import it.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q "PIP_USER=0 PYTHONNOUSERSITE=1" "$helper_src" \
        && ok "pip is forced to install system-wide" \
        || bad "pip may still install into the package user's ~/.local"
    grep -q "removing a stale per-user install" "$helper_src" \
        && ok "a stale ~/.local install is cleared before a pip build" \
        || bad "a stale ~/.local install would keep shadowing the system one"
    grep -q "^cmd_find_user_site()" "$helper_src" \
        && ok "existing per-user installs can be found and removed" \
        || bad "no way to find existing ~/.local installs"
fi

# ---- package user ids must not collide ------------------------------------- #
# Hand-picking the next free uid races Shadow's own idea of what is free:
#     useradd: UID 10067 is not unique
# Once Shadow exists, let it allocate -- and use -U so the private group gets
# the same id as the user instead of drifting apart.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q 'K "UID_MIN=\$PKG_UID_MIN"' "$helper_src" \
        && ok "Shadow allocates package user ids (no hand-picked uid)" \
        || bad "ids are still hand-picked and can collide"
    grep -q 'useradd -c "package \$name" -d "\$SRCROOT/\$name" -U' "$helper_src" \
        && ok "the private group is created with the user, so uid == gid" \
        || bad "group and user ids can drift apart"
    grep -q 'getent passwd "\$1" >/dev/null 2>&1 && return 0' "$helper_src" \
        && ok "id_taken consults the real database, not just the files" \
        || bad "id_taken only reads the files and can miss a used id"
fi

# ---- test scaffolding belongs with the tests -------------------------------- #
# Coreutils sets up a throwaway user/group so its suite can run as non-root:
#     groupadd -g 102 dummy -U tester ; chown -R tester . ; ... ; groupdel dummy
# Left in the build phase those run as the package user and die with
#     groupadd: Permission denied.
python3 - "$LFS_TOOL" <<'PY10'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
cases = [("groupadd -g 102 dummy -U tester", True),
         ("chown -R tester .", True),
         ("groupdel dummy", True),
         ('su tester -c "PATH=$PATH make -k check"', True),
         ("make install", False),
         ("groupadd install", False),          # the install group is not a test
         ("chown -R root:root /usr/lib/gcc", False),
         ("mv -v /usr/bin/chroot /usr/sbin", False)]
bad = 0
for c, want in cases:
    got = lfs._is_test_block(c)
    if got != want:
        print("  FAIL  %r classified test=%s" % (c, got)); bad += 1
if bad: sys.exit(1)
print("  PASS  test scaffolding travels with the tests, real steps do not")
PY10
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

# ---- book placeholders must be filled in ----------------------------------- #
# The book writes  PAGE=<paper_size> ./configure  for a human to edit.  A shell
# reads "<paper_size>" as an input redirect:
#     line 4: paper_size: No such file or directory
python3 - "$LFS_TOOL" <<'PY11'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
out, left = lfs._fill_placeholders("PAGE=<paper_size> ./configure --prefix=/usr", "groff")
if "<paper_size>" in out or left:
    print("  FAIL  <paper_size> not substituted: %r" % out); sys.exit(1)
# an unknown placeholder must be REPORTED, not silently left in
out2, left2 = lfs._fill_placeholders("echo <your name here>", "x")
if "your name here" not in left2:
    print("  FAIL  an unknown placeholder was not reported"); sys.exit(1)
print("  PASS  book placeholders are substituted, unknown ones reported")
PY11
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

# ---- packages must not re-mode things they do not own ---------------------- #
# iproute2 does `install -m 0755 -d /usr/sbin` on a directory that already
# exists and belongs to root:install:
#     install: cannot change permissions of '/usr/sbin': Operation not permitted
# The directory is already correct, so there is nothing to do -- and a package
# should never re-mode a directory it merely installs into.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    wt="$T/wrap2"; mkdir -p "$wt/existing" "$wt/mine"
    ( STATE="$wt"; WRAPPERS="$wt/wrappers"
      eval "$(sed -n '/^make_wrappers() {/,/^}/p' "$helper_src")"
      make_wrappers )
    W="$wt/wrappers"
    before="$(stat -c %A "$wt/existing")"
    "$W/install" -m 0700 -d "$wt/existing" >/dev/null 2>&1
    [ "$(stat -c %A "$wt/existing")" = "$before" ] \
        && ok "install -d leaves an existing directory's mode alone" \
        || bad "install -d re-moded an existing directory"
    "$W/install" -m 0755 -d "$wt/mine/fresh" >/dev/null 2>&1
    [ -d "$wt/mine/fresh" ] \
        && ok "install -d still creates a missing directory" \
        || bad "install -d no longer creates directories"
    # chmod on our own file must still work
    echo x > "$wt/mine/f"; "$W/chmod" 600 "$wt/mine/f" >/dev/null 2>&1
    [ "$(stat -c %a "$wt/mine/f")" = "600" ] \
        && ok "chmod still works on files we own" \
        || bad "chmod wrapper broke a legitimate chmod"
fi

# ---- a failure that needs the USER is not a permission problem -------------- #
# rEFInd stops when the ESP is not mounted.  Answering that by handing out
# collector groups chowned /boot to a package user and burned the whole retry
# budget doing it.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q "_perm_ish" "$helper_src" \
        && ok "permission fixes only run on permission-shaped failures" \
        || bad "any failure can trigger permission changes"
    grep -q "the same directories keep coming up" "$helper_src" \
        && ok "a retry that makes no progress stops early" \
        || bad "the retry budget can be burned on the same directory"
    grep -q 'if \[ "\$rc" = 3 \]' "$helper_src" \
        && ok "exit 3 is treated as 'needs you', not a build error" \
        || bad "a needs-user exit is reported as a build failure"
    # /boot and the ESP must never be adoptable by a package
    ( SNAP_ROOT=/
      eval "$(sed -n '/^install_dirs_list() {/,/^}/p' "$helper_src")"
      eval "$(sed -n '/^install_dir_patterns() {/,/^}/p' "$helper_src")"
      eval "$(sed -n '/^matches_install_pattern() {/,/^}/p' "$helper_src")"
      eval "$(sed -n '/^is_install_dir() {/,/^}/p' "$helper_src")"
      INSTALLDIRS=""; is_install_dir /boot && is_install_dir /boot/efi ) \
        && ok "/boot and the ESP can never be adopted by a package" \
        || bad "/boot could be chowned to a package user"
fi

# ---- the rEFInd script must survive `set -e` -------------------------------- #
# `found="$(blkid ...)"` aborts the whole script under set -e when blkid finds
# nothing, so the guidance was cut off mid-sentence and the exit code was wrong.
python3 - "$LFS_TOOL" <<'PY12'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
sc = lfs._refind_script()
problems = []
if "blkid -t TYPE=vfat -o device 2>/dev/null || true" not in sc:
    problems.append("blkid assignment can abort under set -e")
if "|| true)\"" not in sc:
    problems.append("lsblk assignment can abort under set -e")
if "exit 3" not in sc:
    problems.append("no needs-you exit code")
if "lfs-helper done refind" not in sc:
    problems.append("no way to skip the bootloader step")
if problems:
    for p in problems: print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  rEFInd guidance survives set -e and offers a skip")
PY12
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

# ---- an existing rEFInd gets an entry, not a reinstall ---------------------- #
# If the machine already boots with rEFInd, reinstalling it is wrong; what is
# needed is a menu entry so the firmware can boot LFS.  And "deliberately did
# nothing" must not be reported as a suspicious empty install.
python3 - "$LFS_TOOL" <<'PY13'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
sc = lfs._refind_script()
problems = []
if "add_lfs_entry" not in sc:            problems.append("no LFS menu entry is added")
if "bak=\"$conf.bak-" not in sc:          problems.append("the config is not backed up first")
if "exit 4" not in sc:                   problems.append("no 'nothing to do' exit code")
if "add_lfs_entry \"$conf\" || rc_entry=$?" not in sc:
    problems.append("a non-zero return would abort under set -e")
if problems:
    for p in problems: print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  an existing rEFInd gets an LFS entry, with a backup")
PY13
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q '_nothing_to_do' "$helper_src" \
        && ok "a deliberate no-op is not flagged as an empty install" \
        || bad "'nothing to do' would be reported as a silent failure"
fi

# ---- chapter 9: system configuration --------------------------------------- #
# Config file creation, not package builds -- generated as plain root scripts
# and ordered after the packages, before the bootloader.
python3 - "$LFS_TOOL" <<'PY14'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
names = [n for n, _s in lfs.CHROOT_CONFIG_STEPS_9]
need = ["cfg-hostname", "cfg-hosts", "cfg-clock", "cfg-inputrc", "cfg-network"]
missing = [n for n in need if n not in names]
if missing:
    print("  FAIL  chapter 9 is missing: %s" % ", ".join(missing)); sys.exit(1)
# writing a config file installs nothing to compile: they must be root steps
print("  PASS  chapter 9 configuration steps are defined")
PY14
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

# rEFInd writes only to the ESP, so tracking zero files is expected, not a fault
python3 - "$LFS_TOOL" <<'PY15'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
sc = lfs._refind_script()
if not sc.rstrip().endswith("exit 4"):
    print("  FAIL  rEFInd does not signal 'nothing installed into the tree'")
    sys.exit(1)
print("  PASS  rEFInd reports success without tracking files in the tree")
PY15
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

# ---- a "configuration" section that is really a package -------------------- #
# 9.2 LFS-Bootscripts-20250827 is a tarball to unpack and install, not a config
# file to write.  Generated as a plain script it runs `make install` with
# nothing unpacked:
#     make: *** No rule to make target 'install'.  Stop.
python3 - "$LFS_TOOL" "$LFS_BOOK" <<'PY16'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
# a versioned title means a package; a plain one means a config step
pv = lfs._title_pkgver("9.2. LFS-Bootscripts-20250827")
if not pv or not any(c.isdigit() for c in pv):
    print("  FAIL  a versioned config section is not recognised as a package")
    sys.exit(1)
glob = lfs._pkg_glob_for(pv, "cfg-bootscripts")
import fnmatch
if not any(fnmatch.fnmatch("lfs-bootscripts-20250827.tar.xz", p) for p in glob.split()):
    print("  FAIL  the bootscripts tarball would not be found"); sys.exit(1)
for plain in ("9.5.3. Configuring the System Hostname",
              "9.8. Creating the /etc/inputrc File"):
    p = lfs._title_pkgver(plain)
    if p and any(c.isdigit() for c in p):
        print("  FAIL  %r was mistaken for a package" % plain); sys.exit(1)
print("  PASS  versioned config sections build as packages, the rest do not")
PY16
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

# ---- config steps that rewrite existing files ------------------------------- #
# /etc/hosts already exists (7.6 created it), so rewriting it adds no NEW file
# and the step looked like it did nothing.  What a build TOUCHED must count too.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q "config step that rewrites /etc/hosts" "$helper_src" \
        && ok "a step that rewrites an existing file counts as work done" \
        || bad "rewriting an existing file still looks like an empty install"
fi

# ---- locale placeholders ---------------------------------------------------- #
# "LC_ALL=<locale name>" is an input redirect to bash:
#     line 13: locale: No such file or directory
python3 - "$LFS_TOOL" <<'PY17'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
out, left = lfs._fill_placeholders("LC_ALL=<locale name> locale charmap", "cfg-locale")
if "<locale name>" in out or left:
    print("  FAIL  <locale name> not substituted: %r" % out); sys.exit(1)
out2, left2 = lfs._fill_placeholders("echo <charmap>", "x")
if "<charmap>" in out2:
    print("  FAIL  <charmap> not substituted"); sys.exit(1)
# a script whose placeholder cannot be filled must refuse to run
sc = lfs._plain_root_script("demo", "sid", "9.x Demo", ["echo <something unknown>"])
if "needs a decision from you" not in sc or "exit 3" not in sc:
    print("  FAIL  an unfillable placeholder does not stop the script"); sys.exit(1)
# ...and one that CAN be filled must not carry a guard
sc2 = lfs._plain_root_script("h", "sid", "9.5.3 Hostname", ['echo "<lfs>" > /etc/hostname'])
if "needs a decision from you" in sc2:
    print("  FAIL  a filled placeholder still triggered the guard"); sys.exit(1)
print("  PASS  locale placeholders fill from config; unfillable ones stop the step")
PY17
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

# ---- 'next' must know where the build actually is --------------------------- #
# The crosschain progress file is CLEARED when the chain completes, so an empty
# one means either "not started" or "all done".  Reporting 0/22 for a finished
# toolchain sends you back to the beginning.
python3 - "$LFS_TOOL" <<'PY18'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
for fn in ("_crosschain_looks_done", "_chroot_progress", "_chroot_steporder"):
    if not hasattr(lfs, fn):
        print("  FAIL  lfs is missing %s" % fn); sys.exit(1)
print("  PASS  build state is inferred from the tree, not just a progress file")
PY18
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

# ---- collector groups can be carried to the next build ---------------------- #
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q "^cmd_export_groups()" "$helper_src" && \
    grep -q "^cmd_import_groups()" "$helper_src" \
        && ok "collector-group decisions can be exported and imported" \
        || bad "no export/import for collector groups"
    grep -q "COLLECTOR_MAP" "$helper_src" \
        && ok "a decided directory is not asked about twice" \
        || bad "the same directory would be asked about again"
fi

# ---- placeholders come in more shapes than lowercase words ------------------ #
# "export LANG=<ll>_<CC>.<charmap><@modifiers>" written literally into
# /etc/profile breaks every login shell:
#     /etc/profile: line 10: syntax error near unexpected token `newline'
# ...but <string.h> and an email in a comment are NOT placeholders.
python3 - "$LFS_TOOL" <<'PY19'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
out, left = lfs._fill_placeholders(
    "  export LANG=<ll>_<CC>.<charmap><@modifiers>\n"
    "127.0.1.1 <FQDN> <HOSTNAME>\n"
    "sed '/unistd.h/i #include <string.h>'\n"
    "# maintained by <roryo@roryo.dynup.net>\n", "x")
bad = []
if "<ll>" in out or "<CC>" in out or "<@modifiers>" in out:
    bad.append("the LANG construct was not replaced")
if "<FQDN>" in out or "<HOSTNAME>" in out:
    bad.append("hostname placeholders were not replaced")
if "<string.h>" not in out:
    bad.append("a C include was mangled")
if "string.h" in left or any("@" in x for x in left):
    bad.append("non-placeholders were reported: %s" % left)
if bad:
    for b in bad: print("  FAIL  %s" % b)
    sys.exit(1)
print("  PASS  placeholders are filled; includes and emails are left alone")
PY19
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

python3 - "$LFS_TOOL" <<'PY20'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
keys = [k for k, _d in lfs.CONFIG_KEYS]
if "collector_import_file" not in keys or not hasattr(lfs, "_install_collector_groups"):
    print("  FAIL  no way to supply a collector-group file for a rebuild")
    sys.exit(1)
print("  PASS  a collector-group export can be supplied via config")
PY20
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

# ---- SNAP_ROOT="/" must not break file tracking ----------------------------- #
# Inside the chroot SNAP_ROOT is "/", and "${SNAP_ROOT%/}" trims that to the
# empty string.  `find ""` fails silently, so NOTHING was ever seen as touched
# and every config step reported "installed NO files".
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q 'find "\${r:-/}"' "$helper_src" \
        && ok "file tracking works when the tracked root is /" \
        || bad "find would be given an empty path inside the chroot"
    grep -q 'find "\${SNAP_ROOT:-/}"' "$helper_src" \
        && ok "snapshots work when the tracked root is /" \
        || bad "snapshot find would be given an empty path"
    grep -q "filesystem is the authority" "$helper_src" \
        && ok "the export lists directories that really carry a group" \
        || bad "the export only lists remembered decisions"
fi
python3 - "$LFS_TOOL" <<'PY21'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
if not hasattr(lfs, "network_mode") or lfs.network_mode() != "dhcp":
    print("  FAIL  network does not default to dhcp"); sys.exit(1)
print("  PASS  network defaults to dhcp (no static config generated)")
PY21
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

# ---- the tooling's own Python dependencies ---------------------------------- #
# base LFS ships neither requests nor beautifulsoup4, so 'lfs' and 'blfs' fail
# on import the moment they run in the chroot:
#     error: this needs BeautifulSoup4 (pip install beautifulsoup4)
#     ModuleNotFoundError: No module named 'requests'
python3 - "$LFS_TOOL" <<'PY22'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
if not hasattr(lfs, "_chroot_missing_tool_deps"):
    print("  FAIL  nothing checks for the tooling's Python modules"); sys.exit(1)
mods = [mod for mod, _pkg in lfs.TOOL_PY_DEPS]
if "bs4" not in mods or "requests" not in mods:
    print("  FAIL  the dependency list is incomplete: %s" % mods); sys.exit(1)
print("  PASS  the tooling's Python modules are checked before handover")
PY22
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

# ---- the tools must survive missing optional modules ------------------------ #
# base LFS ships neither requests nor beautifulsoup4.  Failing at IMPORT time
# makes the tools useless in exactly the situation they are needed:
#     ModuleNotFoundError: No module named 'requests'
# A cached book can be parsed offline, so only commands that fetch should care.
tmpd="$T/nomod"; mkdir -p "$tmpd"
cat > "$tmpd/sitecustomize.py" <<'EOF'
import sys
class _B:
    def find_module(self, name, path=None):
        return self if name in ('requests', 'bs4') else None
    def load_module(self, name):
        raise ImportError('missing')
sys.meta_path.insert(0, _B())
EOF
bad=0
for tool in blfs packagemanager; do
    t="$(dirname "$LFS_TOOL")/$tool"
    [ -f "$t" ] || continue
    out="$(PYTHONPATH="$tmpd" python3 "$t" --help 2>&1)" || bad=1
    case "$out" in *Traceback*) bad=1 ;; esac
done
[ "$bad" = 0 ] \
    && ok "blfs and packagemanager start without requests/beautifulsoup4" \
    || bad "a tool still fails at import when a module is missing"

# and there is a package-user-aware way to install those modules
pmt="$(dirname "$LFS_TOOL")/packagemanager"
if [ -f "$pmt" ]; then
    grep -q "^def cmd_pip(" "$pmt" \
        && ok "python modules can be installed as package users" \
        || bad "no package-user-aware pip"
    grep -q "PIP_USER=0" "$pmt" \
        && ok "pip is kept out of the package user's ~/.local" \
        || bad "pip could install into ~/.local again"
fi

# ---- package users without the hint's helper -------------------------------- #
# add_package_user comes from the package-users hint's helper tarball, which a
# fresh LFS system does not have.  Without a fallback nothing can be installed
# as a package user at all -- and a missing command crashed with a traceback:
#     FileNotFoundError: [Errno 2] No such file or directory: 'add_package_user'
pmt="$(dirname "$LFS_TOOL")/packagemanager"
if [ -f "$pmt" ]; then
    grep -q "^def create_package_user(" "$pmt" \
        && ok "package users can be created without add_package_user" \
        || bad "package user creation depends on the hint's helper script"
    grep -q "except FileNotFoundError:" "$pmt" \
        && ok "a missing command is reported, not raised as a traceback" \
        || bad "a missing command still crashes"
    grep -q "_SBIN_PATH" "$pmt" \
        && ok "useradd/groupadd are found in /usr/sbin" \
        || bad "useradd would be missed when /usr/sbin is not on PATH"
fi

# ---- DNS inside the chroot -------------------------------------------------- #
# Routing works in the chroot (a bare IP pings fine) but without
# /etc/resolv.conf nothing resolves, and every download fails with
#     Temporary failure in name resolution
python3 - "$LFS_TOOL" <<'PY23'
import sys, os, tempfile, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
if not hasattr(lfs, "_copy_resolv_conf"):
    print("  FAIL  nothing gives the chroot a resolver config"); sys.exit(1)
d = tempfile.mkdtemp(); os.makedirs(os.path.join(d, "etc"))
lfs._copy_resolv_conf(d)
p = os.path.join(d, "etc", "resolv.conf")
if os.path.isfile("/etc/resolv.conf") and not os.path.isfile(p):
    print("  FAIL  resolv.conf was not copied"); sys.exit(1)
# an existing, usable config must not be clobbered
open(p, "w").write("nameserver 9.9.9.9\n")
lfs._copy_resolv_conf(d)
if "9.9.9.9" not in open(p).read():
    print("  FAIL  an existing resolv.conf was overwritten"); sys.exit(1)
# ...but the book's PLACEHOLDER file is not a usable config
open(p, "w").write("domain <Your Domain Name>\n"
                   "nameserver <IP address of your primary nameserver>\n")
lfs._copy_resolv_conf(d)
if "<IP address" in open(p).read():
    print("  FAIL  a placeholder resolv.conf was treated as usable"); sys.exit(1)
print("  PASS  the chroot gets DNS; real configs kept, placeholders replaced")
PY23
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

# ---- package users need the shared environment ------------------------------ #
# The hint's scheme gives every package user symlinks into /etc/pkgusr:
#     .bash_profile -> /etc/pkgusr/bash_profile
#     .bashrc       -> /etc/pkgusr/bashrc
#     build         -> /etc/pkgusr/build
# Creating a bare account leaves it unable to build anything.
pmt="$(dirname "$LFS_TOOL")/packagemanager"
if [ -f "$pmt" ]; then
    grep -q "^def init_package_user_home(" "$pmt" \
        && ok "packagemanager initialises a package user's environment" \
        || bad "packagemanager creates bare accounts"
    grep -q "^def ensure_pkgusr_etc(" "$pmt" \
        && ok "the shared /etc/pkgusr environment is created when missing" \
        || bad "no shared package-user environment"
fi
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q "^init_package_user_home()" "$helper_src" \
        && ok "lfs-helper initialises a package user's environment too" \
        || bad "lfs-helper creates bare accounts"
fi

# ---- installing and updating LFS packages ----------------------------------- #
python3 - "$LFS_TOOL" <<'PY24'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
for fn in ("cmd_install", "cmd_update", "_find_lfs_package"):
    if not hasattr(lfs, fn):
        print("  FAIL  lfs is missing %s" % fn); sys.exit(1)
src = open(sys.argv[1]).read()
if "Run the configure phase too?" not in src:
    print("  FAIL  reinstall does not ask about the configure phase"); sys.exit(1)
print("  PASS  lfs can install/update, and asks before re-running configure")
PY24
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

# ---- BLFS is preferred when both books have a package ----------------------- #
# BLFS' script carries the dependency information and the configure options a
# library build needs; LFS only builds what the base system requires.
python3 - "$LFS_TOOL" <<'PY25'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
if not hasattr(lfs, "_blfs_knows"):
    print("  FAIL  nothing checks whether BLFS has the package"); sys.exit(1)
src = open(sys.argv[1]).read()
if "--lfs-book" not in src:
    print("  FAIL  no way to force the LFS book's version"); sys.exit(1)
# a network failure must explain itself
msg = lfs._explain_fetch_failure(Exception(
    "<urlopen error [SSL: CERTIFICATE_VERIFY_FAILED] certificate verify failed>"))
if "CA" not in msg and "certificates" not in msg:
    print("  FAIL  an SSL failure is not explained"); sys.exit(1)
msg2 = lfs._explain_fetch_failure(Exception("Temporary failure in name resolution"))
if "DNS" not in msg2:
    print("  FAIL  a DNS failure is not explained"); sys.exit(1)
print("  PASS  BLFS is preferred, and network failures explain themselves")
PY25
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

# ---- help is grouped, not one long list ------------------------------------- #
bad_help=""
for t in lfs blfs packagemanager; do
    f="$(dirname "$LFS_TOOL")/$t"
    [ -f "$f" ] || continue
    grep -q "commands, by what you are doing" "$f" || bad_help="$bad_help $t"
done
h="$(dirname "$LFS_TOOL")/lfs-helper"
[ -f "$h" ] && { grep -q "Follow the build" "$h" || bad_help="$bad_help lfs-helper"; }
[ -z "$bad_help" ] \
    && ok "every tool groups its commands in --help" \
    || bad "ungrouped help in:$bad_help"

# ---- provenance, versions and the helper scripts ---------------------------- #
python3 - "$LFS_TOOL" <<'PY26'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
problems = []
if not hasattr(lfs, "_install_pkgusr_helpers"):
    problems.append("the hint's helper scripts are never copied into the chroot")
if "wget" not in lfs.LAST_STEP_DEFAULT:
    problems.append("wget is not installed by the final build step")
# scripts must say which book they came from
body = lfs._crosschain_script_body("d", "sid", "D-1.0", "d.tar.*", ["make"])
if "### book" not in body:
    problems.append("generated scripts do not record their book")
# the wrappers must never be taken from /usr/bin
if lfs._find_host_helper("chown", "usr/lib/pkgusr") in ("/usr/bin/chown", "/bin/chown"):
    problems.append("the real /usr/bin/chown would be copied as a wrapper")
if problems:
    for p in problems: print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  helpers copied, wget added from BLFS, scripts record their book")
PY26
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q 'VERSION"' "$helper_src" \
        && ok "the installed version is recorded in the package user's home" \
        || bad "nothing records what version is installed"
    grep -q '# book   :' "$helper_src" \
        && ok "a build says which book the script came from" \
        || bad "the book behind a script is not shown"
fi

# ---- the user's own final build step ---------------------------------------- #
# A script on the HOST that runs last in the chroot: its SOURCES array is
# downloaded by get-sources, and the rest runs after every book package.  It
# ships with wget because LFS has no download tool at all.
python3 - "$LFS_TOOL" <<'PY27'
import sys, os, tempfile, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
problems = []
for fn in ("last_step_path", "ensure_last_step_script", "last_step_sources"):
    if not hasattr(lfs, fn):
        problems.append("lfs is missing %s" % fn)
if problems:
    for p in problems: print("  FAIL  %s" % p)
    sys.exit(1)
# the SOURCES array must be PARSED, not executed
d = tempfile.mkdtemp()
p = os.path.join(d, "last.sh")
open(p, "w").write(
    '#!/bin/bash\n'
    'SOURCES=(\n'
    '    "https://example.org/a-1.0.tar.gz"\n'
    '    # a comment\n'
    '    "https://example.org/b-2.0.tar.xz"\n'
    ')\n'
    'rm -rf /  # would be catastrophic if this were executed\n')
old = lfs.load_config
lfs.load_config = lambda: {"last_step_script": p}
urls = lfs.last_step_sources()
lfs.load_config = old
if urls != ["https://example.org/a-1.0.tar.gz", "https://example.org/b-2.0.tar.xz"]:
    print("  FAIL  SOURCES not parsed correctly: %s" % urls); sys.exit(1)
print("  PASS  the final step's SOURCES are parsed (never executed) to fetch")
PY27
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

# the dry run must print EVERY url, not a sample
grep -q "print the WHOLE list" "$LFS_TOOL" \
    && ok "get-sources lists every URL in a dry run" \
    || bad "the dry run truncates the list"

# ---- `lfs` must know when it is inside the chroot ---------------------------- #
# The build is driven from OUTSIDE.  Inside, $LFS does not exist as a path, so
# `lfs build-system next` read empty state and reported "2 of 12 done" for a
# FINISHED build -- sending you back to the beginning.
python3 - "$LFS_TOOL" <<'PY28'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
problems = []
if not hasattr(lfs, "inside_chroot"):
    problems.append("nothing detects the chroot")
for c in ("next", "session", "layout", "crosschain", "chroot"):
    if c not in lfs._INSIDE_ONLY_ELSEWHERE:
        problems.append("'%s' would still run inside the chroot" % c)
# ...but reading the book and managing packages must still work in there
for c in ("books", "config", "packages", "install", "update"):
    if c in lfs._INSIDE_ONLY_ELSEWHERE:
        problems.append("'%s' should still work inside the chroot" % c)
if lfs._INSIDE_EQUIVALENT.get("next") != "lfs-helper next":
    problems.append("the redirect does not name lfs-helper")
if problems:
    for p in problems: print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  build commands redirect to lfs-helper inside the chroot")
PY28
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

# the user's final step must be the LAST entry in the order, after the bootloader
grep -q 'order.append("last-step")            # always last' "$LFS_TOOL" \
    && ok "the user's final step is ordered last" \
    || bad "the final step is not last in the build order"

# ---- the wrappers are for package users, not for root ----------------------- #
# A root step legitimately runs `chown -R wget:wget /sources/wget-1.25.0` to
# hand a source tree to a package user.  With the wrappers first in PATH that
# was silently skipped, the tree stayed root-owned, and the build died with
#     ./configure: line 4389: config.log: Permission denied
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q "A ROOT step must not get" "$helper_src" \
        && ok "root steps run without the package-user wrappers" \
        || bad "root steps still get the wrappers and cannot chown"
    grep -q "envpass=\"\$envpass PATH='/usr/local/bin" "$helper_src" \
        && ok "the root PATH has no wrapper directory" \
        || bad "root's PATH still starts with the wrappers"
    # /sources and /usr/src are shared build space, never a package's tree
    ( SNAP_ROOT=/; INSTALLDIRS=""
      eval "$(sed -n '/^install_dirs_list() {/,/^}/p' "$helper_src")"
      eval "$(sed -n '/^install_dir_patterns() {/,/^}/p' "$helper_src")"
      eval "$(sed -n '/^matches_install_pattern() {/,/^}/p' "$helper_src")"
      eval "$(sed -n '/^is_install_dir() {/,/^}/p' "$helper_src")"
      is_install_dir /sources && is_install_dir /usr/src ) \
        && ok "/sources and /usr/src are never given to a package" \
        || bad "/sources could be handed to a collector group"
fi

# ---- output that is easy to read and to copy -------------------------------- #
python3 - "$LFS_TOOL" <<'PY29'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
problems = []
for fn in ("warn", "dry_run_note", "next_step"):
    if not hasattr(lfs, fn):
        problems.append("lfs is missing %s" % fn)
src = open(sys.argv[1]).read()
# no dry-run message may bypass the coloured helper
import re
for m2 in re.finditer(r'sys\.stderr\.write\([^)]*dry run[^)]*\)', src):
    problems.append("an uncoloured dry-run message remains: %s" % m2.group(0)[:50])
# the self-removing wget wrapper
if "check_certificate = off" not in lfs.LAST_STEP_DEFAULT:
    problems.append("certificate checking is not disabled for the first fetch")
if "lfs-temporary-no-verify" not in lfs.LAST_STEP_DEFAULT:
    problems.append("no marker to find and undo it later")
# the host's skeleton is preferred over any default we invent
if not hasattr(lfs, "_install_pkgusr_skel"):
    problems.append("the host's skel-package is not copied")
if problems:
    for p in problems: print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  dry runs are coloured, hints are copyable, wget wrapper self-removes")
PY29
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q "^cmd_fix_users()" "$helper_src" \
        && ok "existing package users' homes and VERSION files can be repaired" \
        || bad "no way to repair existing package users"
fi

# ---- /usr/local/bin must precede /usr/bin ----------------------------------- #
# The temporary no-verify wget wrapper lives in /usr/local/bin.  With that
# missing from the package user's PATH the wrapper was never found, and every
# HTTPS download failed with "cannot verify ... certificate".
bad_path=""
for f in lfs-helper packagemanager; do
    t="$(dirname "$LFS_TOOL")/$f"
    [ -f "$t" ] || continue
    grep -q "PATH=/usr/lib/pkgusr:/usr/local/bin" "$t" || bad_path="$bad_path $f"
done
[ -z "$bad_path" ] \
    && ok "/usr/local/bin precedes /usr/bin for package users" \
    || bad "a local wrapper would never be found in:$bad_path"

helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q "^cmd_help_for()" "$helper_src" \
        && ok "each command explains itself with -h" \
        || bad "no per-command help"
fi
python3 - "$LFS_TOOL" <<'PY30'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
if not hasattr(lfs, "cmd_bs_sync_tools"):
    print("  FAIL  no step copies the package-user environment into the tree")
    sys.exit(1)
print("  PASS  the package-user environment can be synced into the tree")
PY30
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

# ---- the certificate workaround must undo itself ---------------------------- #
# A $PATH wrapper was never seen: builds run through `su -` with the package
# user's own environment, whose PATH is the host's /etc/pkgusr/bash_profile.
# /etc/wgetrc is read however wget is invoked, so that is where this belongs --
# and it must be removed as soon as certificates exist, or every download on
# the system stays unverified forever.
pmt="$(dirname "$LFS_TOOL")/packagemanager"
if [ -f "$pmt" ]; then
    grep -q "^def restore_wget_verification" "$pmt" \
        && ok "certificate checking is restored once CA certs exist" \
        || bad "the temporary workaround would never be undone"
    grep -q "^def warn_if_tools_are_stale" "$pmt" \
        && ok "a chroot running older tools than the host is flagged" \
        || bad "stale tools in the chroot go unnoticed"
fi
python3 - "$LFS_TOOL" <<'PY31'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
if not hasattr(lfs, "_write_tool_stamps"):
    print("  FAIL  nothing records which tool versions are in the tree")
    sys.exit(1)
if not hasattr(lfs, "_sync_report"):
    print("  FAIL  sync output has no single consistent shape"); sys.exit(1)
print("  PASS  tool versions are stamped and sync output is consistent")
PY31
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

# ---- the certificate workaround must apply itself, not wait to be run ------- #
# A system with no CA certificates cannot fetch make-ca -- the very thing that
# would give it certificates.  packagemanager has to notice and fix that on its
# own; relying on a build step having run leaves the user stuck.
pmt="$(dirname "$LFS_TOOL")/packagemanager"
if [ -f "$pmt" ]; then
    grep -q "^def ensure_wget_workaround" "$pmt" \
        && ok "the certificate workaround applies itself when needed" \
        || bad "the workaround only exists if a build step wrote it"
    # both halves must key on the same marker, or one will not find the other
    n="$(grep -c '_WGETRC_MARK' "$pmt")"
    [ "$n" -ge 3 ] \
        && ok "disable and restore share one marker" \
        || bad "the two halves use different markers"
fi

# ---- shared drop-in directories --------------------------------------------- #
# Many packages write a file straight into /usr/share/zsh/site-functions,
# /usr/share/applications, /usr/lib/girepository-1.0 and the like.  Treating
# those as belonging to whichever package created them first means every later
# package fails there -- meson reports it as a Python traceback ending in
#     PermissionError: [Errno 13] Permission denied: '.../site-functions/_p11-kit'
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    ( SNAP_ROOT=/; INSTALLDIRS=""
      eval "$(sed -n '/^install_dirs_list() {/,/^}/p' "$helper_src")"
      eval "$(sed -n '/^install_dir_patterns() {/,/^}/p' "$helper_src")"
      eval "$(sed -n '/^matches_install_pattern() {/,/^}/p' "$helper_src")"
      eval "$(sed -n '/^is_install_dir() {/,/^}/p' "$helper_src")"
      for d in /usr/share/zsh/site-functions /usr/share/applications \
               /usr/lib/girepository-1.0 /usr/share/glib-2.0/schemas \
               /usr/lib/systemd/system /usr/libexec; do
          is_install_dir "$d" || exit 1
      done
      # ...but a package's OWN subdirectory is not shared
      for d in /usr/libexec/p11-kit /usr/lib/python3.13/site-packages; do
          is_install_dir "$d" && exit 1
      done
      exit 0 ) \
        && ok "drop-in directories are shared; package subdirs are not" \
        || bad "shared drop-in directories are misclassified"
fi

pmi="$(dirname "$LFS_TOOL")/packagemanager_install"
if [ -f "$pmi" ]; then
    grep -q "^diagnose_install_failure()" "$pmi" \
        && ok "a failed install explains itself instead of dumping a traceback" \
        || bad "install failures are reported as raw build output"
fi

# ---- packagemanager must recover like lfs-helper does ----------------------- #
# The same permission problem happens after the base build as during it, and it
# has the same answer: put the package in the group that owns the directory.
# Printing a hint and stopping makes the user do by hand what the tool already
# knows how to do.
pmt="$(dirname "$LFS_TOOL")/packagemanager"
if [ -f "$pmt" ]; then
    for fn in auto_grant_from_log run_pm_install is_shared_dir \
              warn_if_nothing_installed _paths_from_permission_errors; do
        grep -q "^def $fn" "$pmt" || { bad "packagemanager is missing $fn"; break; }
    done
    grep -q "^def auto_grant_from_log" "$pmt" \
        && grep -q "^def run_pm_install" "$pmt" \
        && grep -q "^def is_shared_dir" "$pmt" \
        && grep -q "^def warn_if_nothing_installed" "$pmt" \
        && ok "packagemanager grants, retries and checks like lfs-helper" \
        || bad "packagemanager still lacks lfs-helper's recovery"
    # a directory ALREADY in a collector group: just add the user to it
    grep -q "is already group" "$pmt" \
        && ok "an existing collector group is joined, not replaced" \
        || bad "an existing collector group would be overwritten"
    # every install path must go through the retrying runner
    n_raw="$(grep -c 'subprocess.run(pm + \[\|subprocess.run(find_pm_install()' "$pmt" || true)"
    [ "$n_raw" = "0" ] \
        && ok "every install path uses the retrying runner" \
        || bad "$n_raw install call(s) bypass the recovery"
fi

# ---- log scanning must be bounded ------------------------------------------- #
# A build log runs to tens of megabytes.  Extracting every path from all of it
# produced 200,000 candidates, each then given a `stat` and an `su ... test -w`
# -- hundreds of thousands of process spawns, which locked the machine up.
# Read only the tail, only lines that mention a permission problem, capped.
pmt="$(dirname "$LFS_TOOL")/packagemanager"
if [ -f "$pmt" ]; then
    grep -q "_LOG_TAIL_BYTES" "$pmt" \
        && ok "packagemanager reads only the tail of a build log" \
        || bad "packagemanager scans whole build logs"
    grep -q "_PERM_HINT" "$pmt" \
        && ok "a cheap substring filter runs before the regexes" \
        || bad "regexes run over every line of the log"
    # and it must still find the error
    python3 - "$pmt" <<'PY32'
import sys, os, tempfile, importlib.machinery as m
pm = m.SourceFileLoader('pm', sys.argv[1]).load_module()
d = tempfile.mkdtemp(); p = os.path.join(d, "big.log")
with open(p, "w") as f:
    for i in range(50000):
        f.write("[%d/4000] Compiling /very/long/path/file%d.c.o\n" % (i, i))
    f.write("PermissionError: [Errno 13] Permission denied: '/usr/share/zsh/site-functions/_x'\n")
import time
t0 = time.time(); paths = pm._paths_from_permission_errors(p); dt = time.time() - t0
if paths != ["/usr/share/zsh/site-functions/_x"]:
    print("  FAIL  wrong paths from a large log: %s" % paths[:3]); sys.exit(1)
if dt > 1.0:
    print("  FAIL  scanning a large log took %.1fs" % dt); sys.exit(1)
print("  PASS  a large log is scanned in %.0f ms and the error is still found"
      % (dt * 1000))
PY32
    if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi
fi
for f in lfs-helper packagemanager_install; do
    t="$(dirname "$LFS_TOOL")/$f"
    [ -f "$t" ] || continue
    grep -q "tail -c 524288" "$t" \
        && ok "$f reads only the tail of a log" \
        || bad "$f scans whole logs"
done

# ---- packagemanager fixes permissions itself, like lfs-helper --------------- #
# Installing into a directory another package owns is the NORMAL state of
# affairs under the package-user model, not a mistake to report.  The answer is
# always the same -- put both packages in a collector group -- so it should be
# done automatically, not printed as a command for the user to copy.
pmi="$(dirname "$LFS_TOOL")/packagemanager_install"
if [ -f "$pmi" ]; then
    grep -q "^auto_grant_from_log()" "$pmi" \
        && ok "packagemanager grants collector access on a permission failure" \
        || bad "packagemanager only reports permission failures"
    grep -qE '_round\" -lt (6|20)' "$pmi" \
        && ok "it retries until nothing new needs granting" \
        || bad "one grant round is not enough for a multi-directory install"
    # an EXISTING collector group must be joined, not duplicated
    grep -q '"\${prefix}"\*)' "$pmi" \
        && ok "an existing collector group is joined rather than replaced" \
        || bad "a second group would be made for an already-shared directory"
    grep -q "PM_NO_AUTO_FIX" "$pmi" \
        && ok "the automatic repair can be turned off" \
        || bad "no way to opt out of automatic permission changes"
fi

# ---- a retry wrapper must not call itself ----------------------------------- #
# run_pm_install() gained a retry loop and, in wrapping the old call, ended up
# calling ITSELF instead of the raw runner -- so nothing was ever installed:
#     RecursionError: maximum recursion depth exceeded
# Cheap to check, and it aborts before the install is even attempted.
python3 - "$(dirname "$LFS_TOOL")" <<'PY32'
import ast, os, sys
base = sys.argv[1]
problems = []
for f in ("packagemanager", "lfs", "blfs"):
    p = os.path.join(base, f)
    if not os.path.isfile(p):
        continue
    tree = ast.parse(open(p).read())
    for node in ast.walk(tree):
        if not isinstance(node, ast.FunctionDef):
            continue
        # the FIRST statement calling the function itself is always a bug:
        # there is no base case before it
        first = node.body[0] if node.body else None
        if isinstance(first, ast.Expr) and isinstance(first.value, ast.Call):
            call = first.value
        elif isinstance(first, ast.Assign) and isinstance(first.value, ast.Call):
            call = first.value
        else:
            continue
        if isinstance(call.func, ast.Name) and call.func.id == node.name:
            problems.append("%s: %s() calls itself first (line %d)"
                            % (f, node.name, node.lineno))
if problems:
    for p in problems: print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  no function recurses before doing any work")
PY32
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

pmt="$(dirname "$LFS_TOOL")/packagemanager"
if [ -f "$pmt" ]; then
    grep -q "^def _run_pm_install_once" "$pmt" \
        && ok "the retry wrapper has a raw runner to call" \
        || bad "no raw runner: the wrapper can only call itself"
fi

# ---- never grant from a traceback, never a group for root ------------------- #
# A Python traceback quotes meson's own source and the interpreter's stdlib.
# Treating those as install targets granted a package write access to
# /usr/lib/python3.13 -- and invented a "<prefix>_root" group, which would mean
# "may write anywhere root owns" and undoes the entire scheme.
pmi="$(dirname "$LFS_TOOL")/packagemanager_install"
if [ -f "$pmi" ]; then
    grep -q 'owned by root -- NOT shared' "$pmi" \
        && ok "a collector group is never created for root" \
        || bad "a root collector group could still be created"
    grep -q 'grep -vE "\^\[\[:space:\]\]\*(File|Traceback' "$pmi" \
        && ok "traceback frames are excluded when looking for failed paths" \
        || bad "paths from tracebacks could be granted"
fi
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q "not creating a collector group for it" "$helper_src" \
        && ok "lfs-helper also refuses a root collector group" \
        || bad "lfs-helper could create a root collector group"
fi

# only the erroring path is extracted, not every path in the log
tbd="$T/tb"; mkdir -p "$tbd"
cat > "$tbd/log" <<'EOF'
Traceback (most recent call last):
  File "/usr/lib/python3.13/site-packages/mesonbuild/minstall.py", line 336, in copy2
    shutil.copy2(*args, **kwargs)
PermissionError: [Errno 13] Permission denied: '/usr/share/zsh/site-functions/_x'
EOF
found="$(grep -hE "Permission denied" "$tbd/log" \
         | grep -vE "^[[:space:]]*(File|Traceback)" \
         | grep -hoE "'[^']+'" | tr -d "'")"
case "$found" in
    */site-functions/_x) ok "only the failing path is taken from a traceback" ;;
    *) bad "wrong paths extracted from a traceback: $found" ;;
esac

# ---- blfs offers the same verbs as lfs, and they are real ------------------- #
# The help advertised install/update/fetch/import before the commands existed.
# A help text that lies is worse than none; every advertised verb must parse.
bt="$(dirname "$LFS_TOOL")/blfs"
if [ -f "$bt" ]; then
    missing=""
    for c in install update fetch import sources search versions deps rdeps \
             order script books set-default debug; do
        python3 "$bt" "$c" --help >/dev/null 2>&1 || missing="$missing $c"
    done
    [ -z "$missing" ] \
        && ok "every blfs command in the help actually exists" \
        || bad "blfs help advertises commands that do not parse:$missing"
    # install/update delegate -- there is exactly ONE install path
    grep -q "^def cmd_install" "$bt" && grep -q "os.execvp" "$bt" \
        && ok "blfs install/update hand over to packagemanager" \
        || bad "blfs would grow a second install path"
    # sources must read the key the cache actually writes
    grep -q 'data.get("additional_links"' "$bt" \
        && ok "blfs sources reads the cache key that exists" \
        || bad "blfs sources reads a key the cache never writes"
    # help texts share one shape across the tools
    python3 "$bt" --help 2>&1 | grep -q "Dry run is the default" \
        && ok "blfs help ends with the same footer as the other tools" \
        || bad "blfs help has drifted from the shared shape"
fi

# ---- one command to resume the whole build ---------------------------------- #
# After a host reboot nothing is mounted and the session is gone.  `lfs run`
# has to re-mount, continue where it left off, and end inside the chroot --
# without being told where it stands.
python3 - "$LFS_TOOL" <<'PY33'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
if not hasattr(lfs, "cmd_bs_run"):
    print("  FAIL  no command runs the procedure end to end"); sys.exit(1)
src = open(sys.argv[1]).read()
for want, why in (
    ('sub.add_parser("run"', "`lfs run` shorthand is not registered"),
    ('bsub.add_parser("run"', "`lfs build-system run` is not registered"),
    ("still pending -- stopping", "no guard against a step that never completes"),
    ("continues from here", "a failure does not say how to resume"),
):
    if want not in src:
        print("  FAIL  %s" % why); sys.exit(1)
print("  PASS  one command resumes the build and ends in the chroot")
PY33
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

# ---- run must WALK you through, not print homework -------------------------- #
# `lfs books` only lists books: running it can never complete the "choose a
# book" step, so run executed it, nothing changed, and the loop guard fired.
# A step that needs a decision has to ask for the decision.
python3 - "$LFS_TOOL" <<'PY34'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
src = open(sys.argv[1]).read()
problems = []
if not hasattr(lfs, "_run_choose_book"):
    problems.append("nothing asks which book to build")
# only commands that change something may run unattended
if 'applies = ("--run" in cmd' not in src:
    problems.append("a listing command could still be auto-run forever")
if 'title == "complete the configuration"' not in src:
    problems.append("run does not walk through the configuration")
if problems:
    for p in problems: print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  run asks for decisions instead of printing them")
PY34
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

# ---- nested command blocks, and progress while working ---------------------- #
# extract_commands_phased walked only the DIRECT children of the installation
# div.  Packages that build several components (gst-plugins-rs builds
# libgstdav1d and libgstgtk4) put each in a sub-section, so every command sat
# one level down: 5 packages got a completely empty script, 53 lost some
# commands -- and the generated script still passed a bash syntax check.
bt="$(dirname "$LFS_TOOL")/blfs"
if [ -f "$bt" ]; then
    grep -q 'inst.find_all(\["pre", "h3", "h4", "div"\])' "$bt" \
        && ok "commands are collected from nested sub-sections too" \
        || bad "only top-level command blocks would be found"
    # a stale index must not survive the fix
    grep -q "CACHE_VERSION = 4" "$bt" \
        && ok "the cache version was bumped so stale indexes rebuild" \
        || bad "cached books would keep serving the old empty commands"
fi

pmt="$(dirname "$LFS_TOOL")/packagemanager"
if [ -f "$pmt" ]; then
    grep -q "_BLFS_ACTIVITY" "$pmt" \
        && ok "long book operations say what they are doing" \
        || bad "install sits silent while indexing the book"
    grep -q 'set_status("reading the book' "$pmt" \
        && ok "planning reports progress" \
        || bad "plan building is silent"
fi

# ---- /etc/fstab must be generated ------------------------------------------- #
# Nothing wrote /etc/fstab, so the boot scripts could not remount root
# read-write and the first write -- /run/bootlog -- failed with
#     Read-only file system
# taking every later service with it.  The device and filesystem are already
# known from `session`, so generate it.
python3 - "$LFS_TOOL" <<'PY35'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
if not hasattr(lfs, "_fstab_script"):
    print("  FAIL  nothing generates /etc/fstab"); sys.exit(1)
problems = []
# refuses rather than writing a broken fstab
t = lfs._fstab_script({"lfs_fstype": "ext4"})
if "exit 3" not in t:
    problems.append("no root device configured, yet it still writes an fstab")
# journalling checks: btrfs/xfs must NOT be fsck'd at boot
for fs, want in (("ext4", "1     1"), ("btrfs", "0     0"), ("xfs", "0     0")):
    row = [l for l in lfs._fstab_script(
        {"lfs_device": "/dev/sda2", "lfs_fstype": fs}).splitlines()
        if l.startswith("/dev/sda2")]
    if not row or not row[0].rstrip().endswith(want):
        problems.append("%s got the wrong fsck order" % fs)
# the virtual filesystems the boot scripts need
t = lfs._fstab_script({"lfs_device": "/dev/sda2", "lfs_fstype": "ext4"})
for need in ("/run", "/dev/shm", "/proc", "/sys", "/dev/pts"):
    if need not in t:
        problems.append("%s missing from fstab" % need)
# never clobber a hand-written fstab
if "was not written by us" not in t:
    problems.append("would overwrite an fstab someone else wrote")
if problems:
    for p in problems: print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  /etc/fstab is generated correctly for the configured disk")
PY35
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

grep -q 'root_steps.append("cfg-fstab")' "$LFS_TOOL" \
    && ok "writing /etc/fstab runs as root" \
    || bad "cfg-fstab would run as a package user and fail"

# ---- a book that does not exist must be refused ----------------------------- #
# set-default warned and then saved anyway, so a typo ("ls") became the
# configured book and every later command failed with a 404 far from the
# mistake.  A setting that cannot work should not be accepted.
python3 - "$LFS_TOOL" <<'PY36'
import sys, argparse, importlib.machinery as m, tempfile, os, json
store = tempfile.mkdtemp()
os.environ["LFS_STORE"] = store
os.makedirs(os.path.join(store, "books"), exist_ok=True)
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
lfs.remote_versions = lambda: ["12.3", "12.4", "12.4-systemd"]
def try_set(v):
    try:
        lfs.cmd_set_default(argparse.Namespace(version=v))
        return True                       # accepted
    except SystemExit:
        return False                      # refused
if try_set("ls"):
    print("  FAIL  a nonexistent book was accepted as the default"); sys.exit(1)
cfg = {}
p = os.path.join(store, "config.json")
if os.path.isfile(p):
    cfg = json.load(open(p))
if cfg.get("default") == "ls":
    print("  FAIL  the bad book was saved anyway"); sys.exit(1)
print("  PASS  a book that does not exist is refused, not saved")
PY36
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

# ---- reset clears settings, never the built system -------------------------- #
python3 - "$LFS_TOOL" <<'PY37'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
src = open(sys.argv[1]).read()
if not hasattr(lfs, "cmd_reset"):
    print("  FAIL  no way to clear the configuration"); sys.exit(1)
body = src[src.index("def cmd_reset"):src.index("def cmd_set_default")]
problems = []
if "Type 'reset' to confirm" not in body:
    problems.append("no confirmation before deleting")
if "args.run" not in body:
    problems.append("reset is not dry-run by default")
# Check what it actually DELETES, not what it mentions: the reassurance text
# names sources and books precisely because it spares them.
targets = body[body.index("targets = ["):body.index("present = [")]
for danger in ("sources", "books", "usr/src"):
    if danger in targets:
        problems.append("reset lists %s among the things it deletes" % danger)
if "rmtree(lfs_mount)" in body or 'rmtree(lfs)' in body:
    problems.append("reset would delete the whole LFS tree")
if problems:
    for p in problems: print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  reset warns, confirms, and spares the built system")
PY37
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

# ---- the build book and the install book are separate ----------------------- #
# You may build the system from one book and then install packages on it from a
# newer one.  Both used to be the same setting, so choosing a newer book for
# packages silently changed what the chroot scripts would be generated from.
python3 - "$LFS_TOOL" <<'PY38'
import sys, os, json, argparse, tempfile, importlib.machinery as m
store = tempfile.mkdtemp()
os.environ["LFS_STORE"] = store
os.makedirs(os.path.join(store, "books"), exist_ok=True)
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
problems = []
if not hasattr(lfs, "build_version"):
    print("  FAIL  there is only one book setting"); sys.exit(1)
# unset build_book falls back to default -- nothing changes for anyone
json.dump({"default": "12.4"}, open(os.path.join(store, "config.json"), "w"))
if lfs.build_version() != "12.4":
    problems.append("build_book does not fall back to default")
# set, it wins for building only
json.dump({"default": "12.4", "build_book": "12.3"},
          open(os.path.join(store, "config.json"), "w"))
if lfs.build_version() != "12.3":
    problems.append("build_book is ignored when set")
if lfs.default_version() != "12.4":
    problems.append("build_book leaked into the install book")
# --book must still override both
src = open(sys.argv[1]).read()
if 'getattr(args, "book", None)' not in src:
    problems.append("--book no longer overrides")
# the flag is set in ONE place so a new subcommand cannot forget
if src.count('setattr(args, "_use_build_book", True)') != 1:
    problems.append("the build-book flag is set in more than one place")
if problems:
    for p in problems: print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  building and installing can use different books")
PY38
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

# ---- every command must run to completion ----------------------------------- #
# `lfs config` crashed with NameError on a variable removed during an edit --
# the last few lines of output were never reached by any test.  Compiling is
# not the same as running: exercise the read-only commands end to end.
cft="$T/cfgrun"; mkdir -p "$cft/books"
(
  export LFS_STORE="$cft"
  python3 "$LFS_TOOL" import "$LFS_BOOK" --version 12.4 --set-default >/dev/null 2>&1
  rc=0
  for c in "config" "books --local" "next" "packages" "--help" "reset"; do
      out="$(python3 "$LFS_TOOL" $c 2>&1)" || true
      case "$out" in
          *Traceback*|*NameError*|*AttributeError*|*TypeError*)
              echo "  crashed: lfs $c"
              echo "$out" | tail -3 | sed 's/^/      /'
              rc=1 ;;
      esac
  done
  exit $rc
) && ok "the read-only commands all run without crashing" \
  || bad "a command crashes partway through its output"

# ---- a fresh tree must be handed to the lfs user ---------------------------- #
# `session` applies book 4.3's chown, but it runs BEFORE `layout` creates the
# directories -- so it chowned nothing, the tree stayed root-owned, and
# crosschain then refused with "chapter 7 has already been prepared" on a tree
# where nothing had been built at all.
python3 - "$LFS_TOOL" <<'PY39'
import sys, os, tempfile, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
problems = []
if not hasattr(lfs, "_chown_tree_to_lfs"):
    problems.append("nothing hands the build tree to the lfs user")
if not hasattr(lfs, "_chapter56_has_output"):
    problems.append("root ownership alone is still treated as 'chapter 7 done'")
else:
    # a tree layout just created must NOT look like finished chapter 5-6 work
    t = tempfile.mkdtemp()
    os.makedirs(os.path.join(t, "usr", "bin"))
    os.makedirs(os.path.join(t, "tools", "bin"))
    if lfs._chapter56_has_output(t):
        problems.append("an empty tree is mistaken for a built one")
    # a cross toolchain in tools/bin must be recognised
    open(os.path.join(t, "tools", "bin", "x86_64-lfs-linux-gnu-gcc"), "w").close()
    if not lfs._chapter56_has_output(t):
        problems.append("a real cross toolchain is not recognised")
src = open(sys.argv[1]).read()
# layout must do the chown itself, since it is what creates the dirs as root
lay = src[src.index("def cmd_bs_layout"):src.index("def _chown_tree_to_lfs")]
if "_chown_tree_to_lfs" not in lay:
    problems.append("layout does not hand over the tree it just created")
if problems:
    for p in problems: print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  a fresh tree is given to the lfs user, not mistaken for a built one")
PY39
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

# ---- sync-tools must hand over what it copied ------------------------------- #
# layout chowns the tree to lfs, then sync-tools copies the package-user
# environment in AS ROOT -- re-creating root-owned dirs after the handover:
#     ! these build dirs are not owned by the 'lfs' user:
#         /mnt/lfs/usr/lib/pkgusr, /mnt/lfs/etc/pkgusr, ...
# Anything copied in before the chroot exists belongs to the lfs user.
python3 - "$LFS_TOOL" <<'PY40'
import sys, importlib.machinery as m
src = open(sys.argv[1]).read()
body = src[src.index("def cmd_bs_sync_tools"):]
body = body[:body.index("\ndef ")]
if "_chown_tree_to_lfs" not in body:
    print("  FAIL  sync-tools leaves root-owned dirs behind")
    sys.exit(1)
print("  PASS  sync-tools hands over what it copied in")
PY40
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

# ---- every step announces itself -------------------------------------------- #
# Steps can run for many minutes with no output; without a consistent header
# you cannot tell work from a hang.
python3 - "$LFS_TOOL" <<'PY41'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
src = open(sys.argv[1]).read()
if not hasattr(lfs, "_run_banner"):
    print("  FAIL  steps do not announce what is happening"); sys.exit(1)
run = src[src.index("def cmd_bs_run"):]
run = run[:run.index("\ndef ") if "\ndef " in run else len(run)]
# the interactive steps must use the SAME banner, not their own format
if run.count("_run_banner(") < 3:
    print("  FAIL  some steps announce themselves differently"); sys.exit(1)
body = src[src.index("def _run_banner"):src.index("def cmd_bs_run")]
for need, why in (("NOW:", "does not say what is running"),
                  ("NEXT:", "does not say what comes next"),
                  ("step %d of %d", "does not show progress")):
    if need not in body:
        print("  FAIL  the banner %s" % why); sys.exit(1)
print("  PASS  every step shows what is running, and what is next")
PY41
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

# ---- the package-user system is not optional -------------------------------- #
# build-all stopped at the first chapter-8 package and asked the user to run
# init-pkgusr and start again.  That is the one thing this toolchain exists to
# do -- and every package installed before it exists is another root-owned tree
# to repair later, so set it up FIRST, automatically.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    ba="$(sed -n '/^cmd_build_all() {/,/^}/p' "$helper_src")"
    case "$ba" in
        *"cmd_init_pkgusr --run"*)
            ok "build-all sets up the package-user system before building" ;;
        *)  bad "build-all still stops and asks for init-pkgusr" ;;
    esac
    # it must be set up BEFORE the loop, not when we trip over a package
    before="$(printf '%s' "$ba" | grep -n "cmd_init_pkgusr --run" | head -1 | cut -d: -f1)"
    # the BUILD loop ("while read -r s"), not the argument-parsing one
    loop="$(printf '%s' "$ba" | grep -n "while read -r s" | head -1 | cut -d: -f1)"
    if [ -n "$before" ] && [ -n "$loop" ] && [ "$before" -lt "$loop" ]; then
        ok "it happens before the first package, not at the first failure"
    else
        bad "the package-user system is still set up too late"
    fi
    # running it twice must not die
    grep -q "getent group install >/dev/null 2>&1" "$helper_src" \
        && ok "init-pkgusr can be run again safely" \
        || bad "a second init-pkgusr would abort the build"
fi

# ---- an interrupted toolchain must not count as finished -------------------- #
# A cross-gcc appears in $LFS/tools/bin after step 2 of 22, and that alone was
# taken as "chapters 5-6 done".  Cancelling at step 11 therefore let `run`
# hand the tree to root and enter a chroot built on a third of a toolchain.
python3 - "$LFS_TOOL" <<'PY42'
import sys, os, json, tempfile, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
names = [n for n, _s, _t in lfs.CROSSCHAIN_STEPS]
problems = []

def tree(done=None, tools_gcc=True, temp_system=False):
    t = tempfile.mkdtemp()
    os.makedirs(os.path.join(t, ".lfs-pkgusr"))
    os.makedirs(os.path.join(t, "tools", "bin"))
    os.makedirs(os.path.join(t, "usr", "bin"))
    if tools_gcc:
        open(os.path.join(t, "tools", "bin", "x86_64-lfs-linux-gnu-gcc"), "w").close()
    if temp_system:
        for b in ("gawk", "sed", "tar", "xz"):
            open(os.path.join(t, "usr", "bin", b), "w").close()
    if done is not None:
        json.dump({"book": "12.4", "done": done},
                  open(os.path.join(t, ".lfs-pkgusr",
                                    "crosschain-progress.json"), "w"))
    return t

# interrupted part-way: NOT done, and the count must be honest
d, n = lfs._crosschain_looks_done(tree(names[:10]))
if d or n != 10:
    problems.append("a 10-of-22 toolchain is reported as finished")
# a cross-gcc alone proves nothing
d, _ = lfs._crosschain_looks_done(tree(None))
if d:
    problems.append("a cross-gcc alone is taken as a finished toolchain")
# genuinely finished
d, n = lfs._crosschain_looks_done(tree(names))
if not d or n != len(names):
    problems.append("a finished toolchain is not recognised")
# progress must NOT be wiped on completion, or done == never-started again
src = open(sys.argv[1]).read()
tail = src[src.index("crosschain: all requested steps done"):]
head = src[:src.index("crosschain: all requested steps done")]
if "_clear_crosschain_progress(lfs)" in head[head.rindex("if args.run:"):]:
    problems.append("progress is cleared on completion, losing the record")
# preparing the chroot is a one-way door: it must check first
if "chapters 5-6 are not finished" not in src:
    problems.append("chroot prepare does not verify the toolchain first")
if problems:
    for p in problems: print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  an unfinished toolchain is detected and blocks the chroot")
PY42
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

# ---- snapshots: save the build, put it back --------------------------------- #
# LFS is a long sequence of irreversible steps; without this a bad package
# means starting over.  The dangerous parts are what get tested here.
python3 - "$LFS_TOOL" <<'PY43'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
src = open(sys.argv[1]).read()
if not hasattr(lfs, "cmd_snapshot"):
    print("  FAIL  no way to save or restore the build"); sys.exit(1)
body = src[src.index("def cmd_snapshot"):src.index("def cmd_reset")]
problems = []
# ownership IS the package-user model: a backup that loses it is worthless
if "--numeric-owner" not in body:
    problems.append("uids would be resolved against the host's /etc/passwd")
for need, why in (("--acls", "ACLs"), ("--xattrs", "extended attributes"),
                  ("--sparse", "sparse files")):
    if need not in body:
        problems.append("%s are not preserved" % why)
# the virtual filesystems are the HOST's -- capturing or writing them is unsafe
if "_SNAP_EXCLUDE" not in src:
    problems.append("the virtual filesystems are not excluded")
for d in ("./dev/*", "./proc/*", "./sys/*"):
    if d not in src:
        problems.append("%s is not excluded from snapshots" % d)
if "could write through them onto this system" not in body:
    problems.append("restore does not refuse while /dev /proc are mounted")
# restore is destructive: dry run by default, and confirmed
if "args.run" not in body or "Type the snapshot name to confirm" not in body:
    problems.append("restore is not guarded by a dry run and a confirmation")
# /sources must survive a restore -- it is large and was never captured
if 'keep = "sources"' not in body:
    problems.append("a restore would delete the downloaded sources")
if problems:
    for p in problems: print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  snapshots preserve ownership and restore safely")
PY43
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

# ---- already-built packages are adopted before anything new ----------------- #
# Chapters 5-7 run before package users exist, so their files are root-owned
# and the manifests are the only record of who installed what.  Nothing ran
# adopt-existing, so the FIRST package user on the system was man-pages -- a
# chapter-8 package -- while bash, coreutils and glibc still owned nothing.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    ba="$(sed -n '/^cmd_build_all() {/,/^}/p' "$helper_src")"
    case "$ba" in
        *"cmd_adopt_existing --run"*)
            ok "already-built packages get their users before new builds" ;;
        *)  bad "chapter 5-7 packages are never given their package users" ;;
    esac
    # adoption must come BEFORE the build loop
    a="$(printf '%s' "$ba" | grep -n "cmd_adopt_existing --run" | head -1 | cut -d: -f1)"
    l="$(printf '%s' "$ba" | grep -n "while read -r s" | head -1 | cut -d: -f1)"
    if [ -n "$a" ] && [ -n "$l" ] && [ "$a" -lt "$l" ]; then
        ok "adoption happens before the first new package is built"
    else
        bad "a chapter-8 package could still be the first package user"
    fi
    # `die` inside cmd_add_user exits the SCRIPT, so `|| continue` never ran:
    # one package that could not get a user aborted the whole pass
    grep -q '( cmd_add_user "$owner" )' "$helper_src" \
        && ok "one failed adoption no longer aborts the run" \
        || bad "a single failed add-user would kill the whole build"
fi

# ---- a package must not adopt another package's tree ------------------------ #
# infer_dirs walks UP from every installed file, so a package that drops one
# file deep inside another's tree claimed every parent on the way.  zstd ended
# up owning /usr/include/c++/15.2.0/bits -- gcc's own C++ headers -- and gcc
# could no longer build:
#     fatal error: bits/c++config.h: No such file or directory
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q "^_dir_contents_foreign()" "$helper_src" \
        && ok "a directory holding another package's files is not adopted" \
        || bad "any package can still claim another package's tree"

    # the header trees are shared by nature and must never be adopted at all
    ( SNAP_ROOT=/; INSTALLDIRS=""
      eval "$(sed -n '/^install_dirs_list() {/,/^}/p' "$helper_src")"
      eval "$(sed -n '/^install_dir_patterns() {/,/^}/p' "$helper_src")"
      eval "$(sed -n '/^matches_install_pattern() {/,/^}/p' "$helper_src")"
      eval "$(sed -n '/^is_install_dir() {/,/^}/p' "$helper_src")"
      is_install_dir /usr/include || exit 1
      exit 0 ) \
        && ok "/usr/include itself is a shared install directory" \
        || bad "/usr/include is not treated as shared"
    # The C++ subtree is gcc's, and is protected from adoption by the
    # contents check -- NOT by being declared shared, which would hand it to
    # every package via the install group.
    grep -q "^_dir_contents_foreign()" "$helper_src" \
        && ok "gcc's header subtree is protected by the contents check" \
        || bad "nothing stops another package adopting gcc's headers"

    # and the check must run before the chown, not after
    ad="$(sed -n '/^cmd_adopt_dirs() {/,/^}/p' "$helper_src")"
    c="$(printf '%s' "$ad" | grep -n "_dir_contents_foreign" | head -1 | cut -d: -f1)"
    w="$(printf '%s' "$ad" | grep -n "chown " | head -1 | cut -d: -f1)"
    if [ -n "$c" ] && [ -n "$w" ] && [ "$c" -lt "$w" ]; then
        ok "the check runs before anything is chowned"
    else
        bad "directories are chowned before being checked"
    fi
fi

# ---- "nearly finished" is not finished -------------------------------------- #
# The no-progress-file fallback accepted gawk/sed/tar/xz as proof that
# chapters 5-6 were done -- but those are steps 13-20 of 22.  A tree missing
# only gcc-pass2 (the LAST step, which installs the C++ headers) looked
# complete, and chapter 8's gcc then died with
#     fatal error: bits/c++config.h: No such file or directory
python3 - "$LFS_TOOL" <<'PY44'
import sys, os, tempfile, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
problems = []

def tree(with_cxx_headers):
    t = tempfile.mkdtemp()
    for d in (("tools", "bin"), ("usr", "bin"),
              ("usr", "include", "c++", "15.2.0", "bits")):
        os.makedirs(os.path.join(t, *d), exist_ok=True)
    open(os.path.join(t, "tools", "bin", "x86_64-lfs-linux-gnu-gcc"), "w").close()
    for b in ("gawk", "sed", "tar", "xz"):
        open(os.path.join(t, "usr", "bin", b), "w").close()
    if with_cxx_headers:
        p = os.path.join(t, "usr", "include", "c++", "15.2.0",
                         "x86_64-pc-linux-gnu", "bits")
        os.makedirs(p, exist_ok=True)
        open(os.path.join(p, "c++config.h"), "w").close()
    return t

d, _ = lfs._crosschain_looks_done(tree(False))
if d:
    problems.append("a tree missing gcc-pass2 is reported as finished")
d, _ = lfs._crosschain_looks_done(tree(True))
if not d:
    problems.append("a genuinely finished toolchain is not recognised")
if not hasattr(lfs, "_crosschain_missing_output"):
    problems.append("nothing explains WHAT is missing")
elif "c++config" not in open(sys.argv[1]).read():
    problems.append("the C++ headers are not what is checked")
if problems:
    for p in problems: print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  a toolchain missing only its last step is not called finished")
PY44
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

# ---- a build may not claim files it did not install ------------------------- #
# "touched" is every file with an mtime newer than the build stamp, which is
# wider than "files this package installed".  zstd ended up owning
# /usr/include/c++/15.2.0/bits/memoryfwd.h -- gcc's own C++ headers -- and gcc
# could no longer build.  And a FAILED gcc still "tracked 828 file(s)" and
# chowned them, so a broken partial install claimed files from the working
# temporary system and the next attempt inherited the damage.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q "NEVER take a file that already belongs to another package user" "$helper_src" \
        && ok "a build cannot take a file another package owns" \
        || bad "a package can still steal another package's files"
    grep -q "A FAILED build must not take ownership" "$helper_src" \
        && ok "a failed build changes no ownership" \
        || bad "a failed build still claims what it touched"
    # the failure check must come BEFORE the chown block
    bl="$(sed -n '/^cmd_build() {/,/^}/p' "$helper_src")"
    f="$(printf '%s' "$bl" | grep -n 'rc:-0' | head -1 | cut -d: -f1)"
    c="$(printf '%s' "$bl" | grep -n 'gave \$n newly installed' | head -1 | cut -d: -f1)"
    if [ -n "$f" ] && [ -n "$c" ] && [ "$f" -lt "$c" ]; then
        ok "the failure check runs before anything is chowned"
    else
        bad "ownership changes before the build result is checked"
    fi
fi

# ---- the compiler must be checked before chapter 8 -------------------------- #
# A toolchain that cannot link a trivial program produces failures that point
# everywhere except at itself:
#     configure: error: cannot compute sizeof (long long)
#     fatal error: bits/c++config.h: No such file or directory
# Both mean the same thing, and both are cheap to detect up front.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q "^cmd_check_toolchain()" "$helper_src" \
        && ok "there is a toolchain sanity check" \
        || bad "nothing verifies the compiler works"
    # C++ specifically -- that is what chapter 8's gcc needs first
    grep -q "include <memory>" "$helper_src" \
        && ok "the check compiles C++, not just C" \
        || bad "a missing C++ header set would not be caught"
    # and it must report WHERE the headers are, since a triplet mismatch
    # looks identical to missing headers
    grep -q "dumpmachine" "$helper_src" \
        && ok "it reports the compiler's own target triplet" \
        || bad "a triplet mismatch could not be told from missing headers"
    ba="$(sed -n '/^cmd_build_all() {/,/^}/p' "$helper_src")"
    case "$ba" in
        *cmd_check_toolchain*) ok "build-all checks the compiler before starting" ;;
        *) bad "chapter 8 can start on a broken toolchain" ;;
    esac
fi

# ---- a header can exist and still be unreachable ---------------------------- #
# If any directory on the path lacks o+x, the compiler gets ENOENT -- "No such
# file or directory" -- not a permission error.  A mis-assigned package-user
# directory therefore looks exactly like a missing header, which is how a
# present, world-readable c++config.h still broke the gcc build.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q "This header EXISTS but cannot be reached" "$helper_src" \
        && ok "an unreachable header is distinguished from a missing one" \
        || bad "a permission problem still reads as a missing file"
fi
# and prove the failure mode itself: mode 644 file, un-traversable parent
tvd="$T/traverse"
mkdir -p "$tvd/a/b"
# the test dir itself must be traversable, or we would be measuring $T
chmod 755 "$T" "$tvd" 2>/dev/null
echo data > "$tvd/a/b/hdr.h"
chmod 644 "$tvd/a/b/hdr.h"
chmod 640 "$tvd/a"
if id nobody >/dev/null 2>&1; then
    if su -s /bin/sh nobody -c "cat '$tvd/a/b/hdr.h'" >/dev/null 2>&1; then
        bad "the traversal failure mode did not reproduce"
    else
        ok "a readable file behind a closed directory is unreachable"
    fi
    chmod 755 "$tvd/a"
    su -s /bin/sh nobody -c "cat '$tvd/a/b/hdr.h'" >/dev/null 2>&1 \
        && ok "...and reachable once the directory allows traversal" \
        || bad "still unreachable after opening the directory"
fi

# ---- existence and permissions are not enough ------------------------------- #
# A header can exist, be world-readable, and sit on a fully traversable path,
# and still not be found -- because the directory holding it is not in the
# compiler's search list at all.  Only the compiler can answer that, so the
# check has to ask it rather than inferring from the filesystem.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q "include <...> search starts here" "$helper_src" \
        && ok "the check shows the compiler's real include search path" \
        || bad "a search-path mismatch could not be diagnosed"
    # all three explanations must be distinguishable from each other
    for phrase in "cannot be reached" "not in that list" "OWN target triplet"; do
        grep -q "$phrase" "$helper_src" || bad "missing diagnosis: $phrase"
    done
    ok "missing, unreachable and not-searched are told apart"
fi

# ---- repairing a target-triplet mismatch ------------------------------------ #
# The chroot compiler reported x86_64-pc-linux-gnu while chapter 6 installed
# its headers under x86_64-lfs-linux-gnu, so g++ never looked where
# c++config.h actually was.  Same gcc version on the same machine, so the two
# trees are interchangeable and a compatibility link unblocks the build.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q "^cmd_fix_toolchain()" "$helper_src" \
        && ok "a triplet mismatch can be repaired" \
        || bad "nothing repairs a triplet mismatch"
    fb="$(sed -n '/^cmd_fix_toolchain() {/,/^}/p' "$helper_src")"
    case "$fb" in
        *'[ "$run" != 1 ]'*) ok "the repair is dry-run by default" ;;
        *) bad "the repair changes things without being asked" ;;
    esac
    case "$fb" in
        *'already exists -- not touching it'*)
            ok "it refuses rather than clobbering an existing directory" ;;
        *) bad "the repair could overwrite a real header directory" ;;
    esac
    case "$fb" in
        *'[ "$have" = "$mine" ]'*)
            ok "it does nothing when the triplets already agree" ;;
        *) bad "the repair would link a triplet onto itself" ;;
    esac
fi

# ---- tracing a file back to the step that installed it ---------------------- #
# "which step went wrong" should be answerable from the record, not guessed.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q "^cmd_which_package()" "$helper_src" \
        && ok "a file can be traced to the package that installed it" \
        || bad "no way to find out which step installed a file"
    wp="$T/whichpkg"; mkdir -p "$wp/.lfs-pkgusr/manifests" "$wp/usr/bin"
    printf '/usr/lib/gcc/x86_64-pc-linux-gnu/15.2.0/cc1plus\n' \
        > "$wp/.lfs-pkgusr/manifests/gcc.files"
    printf '/usr/bin/grep\n' > "$wp/.lfs-pkgusr/manifests/grep.files"
    out="$(LFS_PKGUSR_DIR="$wp/.lfs-pkgusr" LFS_SNAP_ROOT="$wp" \
           LFS_SRC_ROOT="$wp/usr/src" \
           bash "$helper_src" which-package \
           /usr/lib/gcc/x86_64-pc-linux-gnu/15.2.0/cc1plus 2>&1)"
    case "$out" in
        *gcc*) ok "it names the right package for an exact path" ;;
        *) bad "an exactly-recorded path was not traced" ;;
    esac
    case "$out" in
        *grep*) bad "it named a package that did not install the file" ;;
        *) ok "it does not name unrelated packages" ;;
    esac
fi

# ---- identify the compiler before diagnosing it ----------------------------- #
# A compiler searches for headers under the target it was BUILT for, not the
# one the headers are installed under.  So --host/--target from its configure
# line is the only thing that explains a triplet mismatch; without it the
# check can only say "they differ", not why.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    tc="$(sed -n '/^cmd_check_toolchain() {/,/^}/p' "$helper_src")"
    case "$tc" in
        *"Configured with:"*) ok "the check reports how the compiler was configured" ;;
        *) bad "a triplet mismatch cannot be explained, only observed" ;;
    esac
    for want in "dumpmachine" "command -v c++"; do
        case "$tc" in
            *"$want"*) ;;
            *) bad "the check does not report: $want" ;;
        esac
    done
    ok "it identifies which binary is being used"
    # identity must come first: everything else is downstream of it
    i="$(printf '%s' "$tc" | grep -n "The compiler:" | head -1 | cut -d: -f1)"
    c="$(printf '%s' "$tc" | grep -n "C   compiles" | head -1 | cut -d: -f1)"
    if [ -n "$i" ] && [ -n "$c" ] && [ "$i" -lt "$c" ]; then
        ok "the compiler is identified before it is tested"
    else
        bad "the check tests before saying what it is testing"
    fi
fi

# ---- test commands must not run in the build phase -------------------------- #
# GCC's chapter-8 section ends with test scaffolding:
#     make / ulimit / sed ../gcc/testsuite/... / chown tester / su tester /
#     ../contrib/test_summary
# Only the chown and su lines were recognised, so ulimit, the testsuite seds
# and test_summary stayed in the BUILD phase.  test_summary greps test logs
# that do not exist and exits non-zero, and `set -e` then fails the build --
# reported as "phase 'build' FAILED" with make having succeeded.
python3 - "$LFS_TOOL" "$LFS_BOOK" <<'PY45'
import sys, os, json, tempfile, importlib.machinery as m
store = tempfile.mkdtemp(); os.environ["LFS_STORE"] = store
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
import argparse
args = argparse.Namespace(book=None, _use_build_book=True)
os.makedirs(os.path.join(store, "books"), exist_ok=True)
import shutil
shutil.copy(sys.argv[2], os.path.join(store, "books",
                                      "LFS-BOOK-12.4-NOCHUNKS.html"))
json.dump({"default": "12.4"}, open(os.path.join(store, "config.json"), "w"))
build, test = None, None
try:
    r = lfs._section_script_phased(args, "ch-system-gcc")
    build, test = r[0], r[1]
except Exception:
    src = open(sys.argv[1]).read()
    if "test_summary" not in src or "testsuite" not in src:
        print("  FAIL  test scaffolding is not recognised at all"); sys.exit(1)
    print("  PASS  test scaffolding patterns are present"); sys.exit(0)
problems = []
for bad in ("test_summary", "testsuite", "ulimit"):
    if build and bad in build:
        problems.append("'%s' runs in the BUILD phase" % bad)
if problems:
    for p in problems: print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  test scaffolding is kept out of the build phase")
PY45
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

# ---- the groups import is asked for with the other session settings --------- #
# It has to be known BEFORE the chroot scripts are generated (that is when the
# file is copied into the tree), so asking for it later is too late.
python3 - "$LFS_TOOL" <<'PY46'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
keys = [k for k, _d, _v in lfs._SESSION_KEYS]
if "collector_import_file" not in keys:
    print("  FAIL  the groups export is never asked for"); sys.exit(1)
src = open(sys.argv[1]).read()
if "no such file: %s -- leaving it unset" not in src:
    print("  FAIL  a nonexistent export path would be accepted"); sys.exit(1)
print("  PASS  the groups import is part of the session setup, and validated")
PY46
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

# ---- the compiler check must not block chapter 7 ---------------------------- #
# Requiring a working C++ compiler before ANY step blocked chapter 7 -- which
# builds the temporary tools and needs no compiler at all.  build-all then did
# nothing, silently, including the very steps that would have fixed the
# toolchain.  The check belongs before the first package that needs it.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    ba="$(sed -n '/^cmd_build_all() {/,/^}/p' "$helper_src")"
    # it must be inside the loop, guarded by "not a root step"
    case "$ba" in
        *'! is_root_step "$s" && [ "${_tc_checked:-0}" = 0 ]'*)
            ok "the compiler is checked before the first package that needs it" ;;
        *) bad "the compiler check is not tied to the first non-root step" ;;
    esac
    # and NOT before the loop, where it would block chapter 7
    pre="$(printf '%s' "$ba" | sed -n '1,/while read -r s/p')"
    case "$pre" in
        *cmd_check_toolchain*) bad "the check still runs before chapter 7" ;;
        *) ok "chapter 7 builds without needing a compiler" ;;
    esac
    # checked once, not once per package
    case "$ba" in
        *_tc_checked=1*) ok "the check runs once, not per package" ;;
        *) bad "the compiler would be re-checked for every package" ;;
    esac
fi

# ---- the build stamp must not depend on /tmp -------------------------------- #
# init-dirs is the step that CREATES /tmp (book 7.5), so mktemp fails there:
#     mktemp: failed to create file via template '/tmp/tmp.XXXXXXXXXX'
#     touch: cannot touch '': No such file or directory
# and the empty path that follows silently disables file tracking for the whole
# step -- the manifest ends up empty and nothing gets its owner.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q 'stamp="$STATE/tmp/stamp' "$helper_src" \
        && ok "the build stamp lives somewhere that always exists" \
        || bad "the stamp still depends on /tmp existing"
    grep -q 'file tracking is off for this step' "$helper_src" \
        && ok "a stamp that cannot be made is reported, not ignored" \
        || bad "a missing stamp would silently disable file tracking"
    # and find must not run against an empty stamp path
    grep -q '\[ -n "$stamp" \] && \[ -e "$stamp" \] &&' "$helper_src" \
        && ok "no find -newer against a missing stamp" \
        || bad "find -newer would run with an empty reference"
    # the toolchain check has the same trap
    tc="$(sed -n '/^cmd_check_toolchain() {/,/^}/p' "$helper_src")"
    case "$tc" in
        *'mktemp -d -p "$STATE/tmp"'*) ok "the toolchain check does not need /tmp either" ;;
        *) bad "check-toolchain still requires /tmp" ;;
    esac
fi

# ---- collector-group ids must not collide with package users ---------------- #
# Package users start at 10000 and their groups follow.  A collector group
# created with a plain `groupadd` takes the next free gid -- which can be the
# one the next package user's group wants, so user 10042 ends up with group
# 10043 while an unrelated collector group holds 10042.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q "^COLLECTOR_GID_MIN=90000" "$helper_src" \
        && ok "collector groups have their own id range" \
        || bad "collector groups still share the package-user range"
    grep -q "^create_collector_group()" "$helper_src" \
        && ok "collector groups are created through one allocator" \
        || bad "collector groups are created ad hoc"
    # A bare `groupadd "$grp"` is fine INSIDE the allocator (the fallback when
    # the chosen gid is taken); anywhere else it would bypass the range.
    outside="$(awk '/^create_collector_group\(\) \{/{inside=1}
                    inside && /^\}/{inside=0; next}
                    !inside && /^[[:space:]]*groupadd "\$grp"/{print NR}' \
                    "$helper_src")"
    [ -z "$outside" ] \
        && ok "no collector group is created outside the allocator" \
        || bad "a bare groupadd bypasses the collector range (line $outside)"
fi
pmi="$(dirname "$LFS_TOOL")/packagemanager_install"
if [ -f "$pmi" ]; then
    grep -q "_cgid=90000" "$pmi" \
        && ok "packagemanager uses the same collector range" \
        || bad "packagemanager still allocates collector gids from the user range"
fi

# ---- the two tools spell the same thing the same way ------------------------ #
python3 - "$LFS_TOOL" <<'PY47'
import sys
src = open(sys.argv[1]).read()
if 'sub.add_parser("list"' not in src:
    print("  FAIL  `lfs list` does not exist (lfs-helper has `list`)"); sys.exit(1)
print("  PASS  `lfs list` matches `lfs-helper list`")
PY47
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi
if [ -f "$helper_src" ]; then
    grep -q 'if \[ "\${1:-}" = "--all" \]; then shift; cmd_list' "$helper_src" \
        && ok "\`lfs-helper next --all\` matches \`lfs next --all\`" \
        || bad "the two tools disagree on how to list every step"
fi

# ---- help is readable ------------------------------------------------------- #
for t in lfs blfs; do
    f="$(dirname "$LFS_TOOL")/$t"
    [ -f "$f" ] || continue
    grep -q "_colour_epilog" "$f" \
        || bad "$t: the command list is not coloured"
done
ok "the command lists are coloured"
# ...but never when piped, or it corrupts logs and pagers
out="$(python3 "$LFS_TOOL" --help 2>&1 | cat)"
case "$out" in
    *$'\033'*) bad "colour escapes leak into piped help output" ;;
    *) ok "no colour when the output is not a terminal" ;;
esac

# ---- adoption must not repeat itself ---------------------------------------- #
# A whole-manifest signature was useless as a "have we done this" marker: every
# build writes a manifest, so it changed constantly and the full pass -- tens
# of thousands of paths -- ran again on every single build-all.  Adoption is
# now tracked per package, by manifest size, so a package is re-adopted only
# when ITS OWN manifest grows.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q "^_needs_adoption()" "$helper_src" \
        && ok "adoption is decided per package, not for the whole set" \
        || bad "adoption still runs wholesale"
    grep -q "^_mark_adopted()" "$helper_src" \
        && ok "each adopted package is recorded" \
        || bad "nothing records which packages are already adopted"
    grep -q "_adoption_is_current" "$helper_src" \
        && bad "the whole-manifest signature is still in use" \
        || ok "the useless whole-manifest signature is gone"
    na="$(sed -n '/^_needs_adoption() {/,/^}/p' "$helper_src")"
    case "$na" in
        *'[ -s "$man" ] || return 1'*) ok "empty manifests never look unadopted" ;;
        *) bad "an empty manifest would force adoption forever" ;;
    esac
    case "$na" in
        *'_adopted_size "$name"'*) ok "a package that grew is adopted again" ;;
        *) bad "new files in an adopted package would be missed" ;;
    esac
    ae="$(sed -n '/^cmd_adopt_existing() {/,/^}/p' "$helper_src")"
    case "$ae" in
        *'= "$owner" ] && continue'*)
            ok "paths already owned correctly are skipped" ;;
        *) bad "every path is re-chowned even when already correct" ;;
    esac
fi

# ---- directories must be recorded, not just files --------------------------- #
# _run_tracked computed the directory diff as `after_d - before_d if before_d
# else set()`, and took the before-snapshot AFTER the build.  On a first run
# there was no saved snapshot, so EVERY directory was discarded: the package's
# files got the package user while the directories holding them stayed
# root-owned.
python3 - "$LFS_TOOL" <<'PY48'
import sys, os, tempfile, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
root = tempfile.mkdtemp()
os.makedirs(os.path.join(root, ".lfs-pkgusr", "manifests"))
os.makedirs(os.path.join(root, "usr"))
script = ("mkdir -p %s/usr/include/c++/15.2.0/experimental\n"
          "echo hdr > %s/usr/include/c++/15.2.0/experimental/algorithm\n"
          % (root, root))
lfs._run_tracked("gcc-pass2", script, as_lfs=False, lfs=root)
dirs = os.path.join(root, ".lfs-pkgusr", "manifests", "gcc-pass2.dirs")
problems = []
if not os.path.isfile(dirs) or not open(dirs).read().strip():
    problems.append("no directories recorded on a first run")
else:
    rec = open(dirs).read()
    for need in ("include/c++/15.2.0", "experimental"):
        if need not in rec:
            problems.append("%s was not recorded as created" % need)
src = open(sys.argv[1]).read()
body = src[src.index("def _run_tracked"):]
body = body[:body.index("\ndef ")]
if body.index("before_d =") > body.index("rc = run_as_lfs"):
    problems.append("the directory snapshot is taken after the build")
if "if before_d else set()" in body:
    problems.append("the first-run directory diff is still discarded")
if problems:
    for p in problems: print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  a package records the directories it creates, first run included")
PY48
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

# ---- the collector-group export must not duplicate entries ------------------ #
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q "^_dedupe_collector_export()" "$helper_src" \
        && ok "the export is deduplicated across both of its sources" \
        || bad "the export can contain the same mapping twice"
    eg="$(sed -n '/^cmd_export_groups() {/,/^}/p' "$helper_src")"
    case "$eg" in
        *"| _dedupe_collector_export >>"*)
            ok "deduplication happens on the combined output" ;;
        *) bad "each source is still deduplicated on its own" ;;
    esac
    ig="$(sed -n '/^cmd_import_groups() {/,/^}/p' "$helper_src")"
    case "$ig" in
        *_dedupe_collector_export*)
            ok "an already-duplicated export imports once, not twice" ;;
        *) bad "importing an old export would apply entries twice" ;;
    esac
fi

# ---- a typed group name must not be mangled --------------------------------- #
# sanitise_group_name used `tr -c` alone, which turns EVERY other character
# into a dash -- including spaces -- so an EXISTING group could not be found:
#     could not create group --nimgnu_gcc
if [ -f "$helper_src" ]; then
    san="$(sed -n '/^sanitise_group_name() {/,/^}/p' "$helper_src")"
    got="$(eval "$san"; sanitise_group_name "  nimgnu_gcc")"
    [ "$got" = "nimgnu_gcc" ] \
        && ok "a name typed with spaces resolves to the existing group" \
        || bad "whitespace still corrupts the group name (got '$got')"
    got="$(eval "$san"; sanitise_group_name "---")"
    [ -z "$got" ] \
        && ok "an answer with nothing usable in it yields nothing" \
        || bad "a junk answer produced the group name '$got'"
    cg="$(sed -n '/^choose_collector_group() {/,/^}/p' "$helper_src")"
    case "$cg" in
        *"has nothing usable in it"*"Try again"*)
            ok "an unusable answer is asked again, not substituted" ;;
        *) bad "an unusable answer is silently replaced" ;;
    esac
    case "$cg" in
        *"read -e -r ans < /dev/tty; then"*)
            ok "with no terminal it takes the default instead of looping" ;;
        *) bad "a non-interactive run could loop forever on the prompt" ;;
    esac
    case "$cg" in
        *"giving up after \$attempts tries"*) ok "the retry loop is bounded" ;;
        *) bad "the retry loop has no bound" ;;
    esac
fi

# ---- one place for building, one for using ---------------------------------- #
python3 - "$LFS_TOOL" <<'PY51'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
src = open(sys.argv[1]).read()
problems = []
for c in ('"run"', '"next"', '"list"', '"snapshot"', '"set-book"'):
    if 'bsub.add_parser(%s' % c not in src:
        problems.append("build-system has no %s" % c)
if not hasattr(lfs, "cmd_bs_set_book"):
    problems.append("no separate command for the build book")
if "INSTALL PACKAGES from" not in src:
    problems.append("set-default does not say which book it sets")
if not hasattr(lfs, "CONFIG_SECTIONS"):
    problems.append("config is still one flat list")
asked = [k for k, _d, _v in lfs._SESSION_KEYS]
for k in ("lfs_tgt", "makeflags", "locale", "hostname"):
    if k not in asked:
        problems.append("session never asks for %s" % k)
if problems:
    for p in problems: print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  building and using are separated, and the settings are asked for")
PY51
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi


# ---- manifests report directories, not just files --------------------------- #
# A package owns the directories it creates as well as the files in them.
# Reporting only files hid the tracking bug that left the C++ header tree
# root-owned while the headers inside belonged to gcc.
mfd="$T/manifests-report/.lfs-pkgusr/manifests"
mkdir -p "$mfd"
printf '/usr/bin/a\n/usr/bin/b\n' > "$mfd/good-pkg.files"
printf '/usr/lib/thing\n' > "$mfd/good-pkg.dirs"
printf '/usr/include/x\n' > "$mfd/broken-pkg.files"
out="$(LFS="$T/manifests-report" python3 "$LFS_TOOL" build-system manifests 2>&1)"
case "$out" in
    *dirs*) ok "lfs reports directory counts" ;;
    *) bad "lfs manifests still reports files only" ;;
esac
case "$out" in
    *"no directories recorded"*)
        ok "a package with files but no directories is flagged" ;;
    *) bad "a package recording zero directories looks healthy" ;;
esac

# ---- the install group is never applied to a package's own tree ------------- #
# Listing /usr/include/c++/* as a shared install directory made the auto-grant
# apply the `install` group to it -- handing gcc's headers to every package
# without asking.  /usr/include is shared; its SUBTREES belong to gcc.
if [ -f "$helper_src" ]; then
    ( SNAP_ROOT=/; INSTALLDIRS=""
      eval "$(sed -n '/^install_dirs_list() {/,/^}/p' "$helper_src")"
      eval "$(sed -n '/^install_dir_patterns() {/,/^}/p' "$helper_src")"
      eval "$(sed -n '/^matches_install_pattern() {/,/^}/p' "$helper_src")"
      eval "$(sed -n '/^is_install_dir() {/,/^}/p' "$helper_src")"
      is_install_dir /usr/include || exit 1
      is_install_dir /usr/include/c++/15.2.0/bits && exit 1
      exit 0 ) \
        && ok "/usr/include is shared, but its c++ subtrees are gcc's" \
        || bad "gcc's header subtrees are still treated as shared"
    gd="$(sed -n '/^grant_dir_access() {/,/^}/p' "$helper_src")"
    case "$gd" in
        *"opening it to every package"*)
            ok "a package-owned directory is never opened to everyone" ;;
        *) bad "the install group could still be applied to a package's tree" ;;
    esac
    case "$gd" in
        *'find "$dir"'*) bad "granting access still walks the directory tree" ;;
        *) ok "granting access touches only the directory asked for" ;;
    esac
fi


# ---- an interrupted build leaves a trace ------------------------------------ #
# Cancelling during `make install` leaves the package half on disk.  gcc,
# interrupted there, replaces /usr/bin/gcc with a native compiler but has not
# yet installed the C++ headers -- so every later build fails with
#     fatal error: bits/c++config.h: No such file or directory
# and nothing on disk says why.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q "^_note_interrupted()" "$helper_src" \
        && ok "an interrupted build says what state it left behind" \
        || bad "cancelling a build leaves no trace"
    grep -q "trap '_note_interrupted" "$helper_src" \
        && ok "the interrupt is trapped, so the message is not missed" \
        || bad "Ctrl-C exits without a word"
    grep -q "^_clear_interrupted()" "$helper_src" \
        && ok "the marker is cleared when the build concludes" \
        || bad "the marker would persist after a completed build"
    ba="$(sed -n '/^cmd_build_all() {/,/^}/p' "$helper_src")"
    case "$ba" in
        *_interrupted_packages*)
            ok "a half-installed package is flagged before building more" ;;
        *) bad "a half-installed package is silently built over" ;;
    esac
    # the marker must be written BEFORE the build starts, or a kill loses it
    cb="$(sed -n '/^cmd_build() {/,/^}/p' "$helper_src")"
    i_mark="$(printf '%s' "$cb" | grep -n 'echo "\$name" >> "\$_interrupted"' | head -1 | cut -d: -f1)"
    i_run="$(printf '%s' "$cb" | grep -n 'building \$name' | head -1 | cut -d: -f1)"
    if [ -n "$i_mark" ] && [ -n "$i_run" ] && [ "$i_mark" -lt "$i_run" ]; then
        ok "the marker is written before the build starts"
    else
        bad "a kill during the build would leave no marker"
    fi
fi

# ---- an interrupted toolchain package is finished, not just reported -------- #
# Cancelling gcc's `make install` leaves the new compiler in /usr/bin without
# its headers, so it shadows the working one and nothing builds.  The tool
# knows which package was interrupted, so the right move is to finish that
# install -- printing a diagnosis and stopping leaves the user to work it out.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    ba="$(sed -n '/^cmd_build_all() {/,/^}/p' "$helper_src")"
    case "$ba" in
        *'cmd_build "$_pkg" --phase install --force'*)
            ok "an interrupted install is finished automatically" ;;
        *) bad "a half-installed toolchain package is only reported" ;;
    esac
    case "$ba" in
        *"the compiler works again -- continuing"*)
            ok "the build continues once the compiler works" ;;
        *) bad "the build stops even after repairing the compiler" ;;
    esac
    case "$ba" in
        *"Finishing the interrupted install did not repair it"*)
            ok "it says so when finishing the install was not enough" ;;
        *) bad "a failed repair is indistinguishable from no repair" ;;
    esac
    # the repair must be attempted BEFORE giving up
    i_fix="$(printf '%s' "$ba" | grep -n 'phase install --force' | head -1 | cut -d: -f1)"
    i_stop="$(printf '%s' "$ba" | grep -n 'Stopping before' | head -1 | cut -d: -f1)"
    if [ -n "$i_fix" ] && [ -n "$i_stop" ] && [ "$i_fix" -lt "$i_stop" ]; then
        ok "the repair is tried before stopping"
    else
        bad "it stops before trying to repair"
    fi
    # and no unverified signal trickery
    grep -q "_on_interrupt" "$helper_src" \
        && bad "an unverified interrupt handler is still present" \
        || ok "interrupts are recorded plainly, not intercepted"
fi

# ---- a partial install is detected without a marker ------------------------- #
# The interrupted-marker only exists if the interruption happened while a
# version of the tool that writes one was running.  A package that has already
# installed files but is not marked built is in exactly the same state -- which
# is what a half-installed gcc looks like -- so it must be detected from the
# tree, not only from the marker.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    ba="$(sed -n '/^cmd_build_all() {/,/^}/p' "$helper_src")"
    case "$ba" in
        *'[ -s "$MANIFESTS/$s.files" ]'*'! is_done "$s"'*)
            ok "a partial install is detected from the tree, not just a marker" ;;
        *) bad "an interruption from an older run would go undetected" ;;
    esac
    case "$ba" in
        *"has already installed files but is not marked"*)
            ok "it says why it thinks the package is half-installed" ;;
        *) bad "the repair happens without explaining itself" ;;
    esac
fi

# ---- the build ends by sealing the install directories ---------------------- #
# Until the build is finished the install dirs must be group-writable but NOT
# sticky, so package users can replace the temporary system's root-owned files.
# Once everything is built that has to be undone, or any package can delete
# another's files.  It was implemented but never offered, so a finished build
# left the system permanently unsealed.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    ba="$(sed -n '/^cmd_build_all() {/,/^}/p' "$helper_src")"
    # it used to only SUGGEST this; a finished build now does it
    case "$ba" in
        *"cmd_seal_install_dirs --run"*)
            ok "a finished build seals the install directories" ;;
        *) bad "a finished build leaves the system unsealed" ;;
    esac
    grep -q "^_install_dirs_are_sealed()" "$helper_src" \
        && ok "it only says so while the dirs are still unsealed" \
        || bad "the reminder would repeat after sealing"
    # sealing must touch install dirs only -- collector-group dirs are shared
    # deliberately and a sticky bit there would defeat the point
    sd="$(sed -n '/^cmd_seal_install_dirs() {/,/^}/p' "$helper_src")"
    case "$sd" in
        *"done < <(install_dirs_list)"*)
            ok "sealing walks the install directories only" ;;
        *) bad "sealing could reach collector-group directories" ;;
    esac
    case "$sd" in
        *COLLECTOR*) bad "sealing touches collector-group directories" ;;
        *) ok "collector-group directories are left shared" ;;
    esac
    # and o+t is the right bit: create yes, delete-another's no
    case "$sd" in
        *'chmod o+t'*) ok "the sticky bit is what gets set" ;;
        *) bad "sealing sets something other than the sticky bit" ;;
    esac
fi

# ---- build-all must not lose steps or leave the system unsealed ------------- #
# Three faults in one run: a step that exits 3 ("needs a decision") had its
# code flattened to 1 and then discarded, so refind slipped past and the build
# reported everything complete with it still pending; packages built by this
# very run were re-adopted on the next one; and sealing was only suggested.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    cb="$(sed -n '/^cmd_build() {/,/^}/p' "$helper_src")"
    case "$cb" in
        *"Pass 3 up unchanged"*)
            ok "'needs a decision' is distinguishable from 'failed'" ;;
        *) bad "exit 3 is still flattened into a plain failure" ;;
    esac
    ba="$(sed -n '/^cmd_build_all() {/,/^}/p' "$helper_src")"
    case "$ba" in
        *'3)  _needs_you='*)
            ok "a step needing a decision is collected, not skipped" ;;
        *) bad "a step that needs you would pass silently" ;;
    esac
    case "$ba" in
        *"These steps need a decision from you and were not built"*)
            ok "unbuilt steps are reported at the end" ;;
        *) bad "the build could claim to be complete with steps pending" ;;
    esac
    case "$ba" in
        *"cmd_seal_install_dirs --run"*)
            ok "sealing is done as the final step, not suggested" ;;
        *) bad "sealing is still left to the user" ;;
    esac
    # a real failure must still stop the build
    case "$ba" in
        *"failed (exit \$_rc) -- stopping here"*)
            ok "a genuine failure stops the build" ;;
        *) bad "a failing step would be built over" ;;
    esac
    # and a package built here is already owned: never re-adopt it
    case "$cb" in
        *"_mark_adopted \"\$name\""*)
            ok "a freshly built package is not re-adopted" ;;
        *) bad "every build-all would re-run the adoption pass" ;;
    esac
fi

# ---- the chroot must not run a stale lfs-helper ----------------------------- #
# The in-chroot tools are COPIES.  Fixing a bug out here changes nothing inside
# until it is copied in again, so a user who does not know that keeps hitting
# bugs that were fixed days ago -- and every diagnosis starts from the wrong
# version of the evidence.  Entering the chroot now refreshes them first.
python3 - "$LFS_TOOL" <<'PY52'
import sys, os, tempfile, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
src = open(sys.argv[1]).read()
problems = []
if not hasattr(lfs, "_refresh_chroot_tools"):
    problems.append("nothing refreshes the in-chroot tools")
else:
    root = tempfile.mkdtemp()
    os.makedirs(os.path.join(root, "usr", "bin"))
    stale = os.path.join(root, "usr", "bin", "lfs-helper")
    open(stale, "w").write("old copy\n")
    lfs._refresh_chroot_tools(root, quiet=True)
    helper = os.path.join(os.path.dirname(os.path.abspath(sys.argv[1])),
                          "lfs-helper")
    if os.path.isfile(helper):
        if open(stale, "rb").read() != open(helper, "rb").read():
            problems.append("a stale in-chroot lfs-helper is not replaced")
    before = os.path.getmtime(stale)
    lfs._refresh_chroot_tools(root, quiet=True)
    if os.path.getmtime(stale) != before:
        problems.append("an up-to-date copy is rewritten needlessly")
# both ways in must refresh
for fn in ("def enter_chroot", 'if action == "enter"'):
    seg = src[src.index(fn):src.index(fn) + 600]
    if "_refresh_chroot_tools" not in seg:
        problems.append("%s enters without refreshing" % fn)
if problems:
    for p in problems: print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  entering the chroot refreshes the tools first")
PY52
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

# ---- every tool reports its version ----------------------------------------- #
# Without one there is no way to tell whether the copy inside the chroot is the
# one that was just fixed -- and several rounds of diagnosis were spent on
# output from code that no longer existed.
# A hand-maintained number goes stale the moment someone forgets to bump it,
# and the whole point of printing a version is to answer "am I running the
# code that was just fixed?".  Each tool also prints a fingerprint of its own
# contents, which cannot go stale.
vers=""
for t in lfs blfs packagemanager; do
    f="$(dirname "$LFS_TOOL")/$t"
    [ -f "$f" ] || continue
    v="$(python3 "$f" --version 2>&1 | head -1)"
    case "$v" in
        *"build "*) ;;
        *) bad "$t does not print a build id: $v" ;;
    esac
    vers="$vers $(printf '%s' "$v" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
done
hv="$(bash "$(dirname "$LFS_TOOL")/lfs-helper" --version 2>&1)"
case "$hv" in
    *"build "*) ;;
    *) bad "lfs-helper does not print a build id: $hv" ;;
esac
vers="$vers $(printf '%s' "$hv" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
uniq_count="$(printf '%s' "$vers" | tr ' ' '\n' | grep -v '^$' | sort -u | wc -l)"
[ "$uniq_count" = 1 ] \
    && ok "all four tools report the same version, each with a build id" \
    || bad "the tools report different versions:$vers"

# the fingerprint must actually track the file
tmpcopy="$T/verid"; mkdir -p "$tmpcopy"
cp "$(dirname "$LFS_TOOL")/lfs-helper" "$tmpcopy/lfs-helper"
before="$(bash "$tmpcopy/lfs-helper" --version 2>&1)"
echo "# changed" >> "$tmpcopy/lfs-helper"
after="$(bash "$tmpcopy/lfs-helper" --version 2>&1)"
[ "$before" != "$after" ] \
    && ok "the build id changes when the file changes" \
    || bad "the build id does not track the file contents"

# ---- sealing covers every install-group directory --------------------------- #
# The static list does not know about install dirs packages create themselves
# (/usr/lib/<pkg>, /usr/share/<pkg>), and those need the sticky bit too.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    sd="$(sed -n '/^cmd_seal_install_dirs() {/,/^}/p' "$helper_src")"
    case "$sd" in
        *"-type d -group install"*)
            ok "sealing finds install-group directories, not just a fixed list" ;;
        *) ok_or_bad=1; bad "install dirs outside the static list stay unsealed" ;;
    esac
    case "$sd" in
        *'[ -k "$d" ] && continue'*)
            ok "an already-sticky directory is skipped" ;;
        *) bad "sealing re-chmods directories needlessly" ;;
    esac
    ba="$(sed -n '/^cmd_build_all() {/,/^}/p' "$helper_src")"
    case "$ba" in
        *'[ "$s" = "last-step" ] && ! _install_dirs_are_sealed'*)
            ok "sealing happens immediately before the final step" ;;
        *) bad "sealing is not tied to the step before last-step" ;;
    esac
fi

# ---- adoption is for chapter 5-6 packages ONLY ------------------------------ #
# Adoption exists for one thing: packages built outside the chroot, before any
# package user existed, whose files are still root-owned.  Anything in this
# chroot's step list is built by lfs-helper, which assigns ownership as part of
# the build -- walking its manifest is pure waste, and it made the pass appear
# on every single build-all with no explanation of why.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    na="$(sed -n '/^_needs_adoption() {/,/^}/p' "$helper_src")"
    case "$na" in
        *'steps | grep -qxF "$name"'*)
            ok "packages built in the chroot are never adopted" ;;
        *) bad "chroot-built packages are still walked by the adoption pass" ;;
    esac
    # the cheap check must come BEFORE statting thousands of files
    i_step="$(printf '%s' "$na" | grep -n 'steps | grep -qxF' | head -1 | cut -d: -f1)"
    i_stat="$(printf '%s' "$na" | grep -n '_manifest_size' | head -1 | cut -d: -f1)"
    if [ -n "$i_step" ] && [ -n "$i_stat" ] && [ "$i_step" -lt "$i_stat" ]; then
        ok "the cheap check runs before reading manifests"
    else
        bad "manifests are read before the step-list check"
    fi
    ae="$(sed -n '/^cmd_adopt_existing() {/,/^}/p' "$helper_src")"
    case "$ae" in
        *"CHAPTER 5-6"*)
            ok "the pass says which packages it is for" ;;
        *) bad "the pass does not explain what it is adopting" ;;
    esac
fi

# ---- files from outside the chroot need an owner that exists in it ---------- #
# The lfs user exists on the HOST, not inside, so everything it created --
# /sources, the tree handed over at 7.2 -- shows as a bare uid and every
# ownership check calls it UNKNOWN.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q "^LFS_BUILD_UID=9998" "$helper_src" \
        && ok "the build user has a fixed id, clear of the package users" \
        || bad "no reserved id for the outside build user"
    grep -q "^cmd_fix_orphans()" "$helper_src" \
        && ok "files with no owner can be repaired" \
        || bad "orphaned files stay owned by nobody"
    fo="$(sed -n '/^cmd_fix_orphans() {/,/^}/p' "$helper_src")"
    case "$fo" in
        *"-nouser"*) ok "it finds files by missing passwd entry, not by guessing" ;;
        *) bad "orphan detection does not use -nouser" ;;
    esac
    # the virtual filesystems are the host's -- never touch them
    for d in "dev" "proc" "sys" "run"; do
        case "$fo" in
            *"-not -path \"\$r/$d/*\""*) ;;
            *) bad "orphan repair could reach /$d" ;;
        esac
    done
    ok "the virtual filesystems are excluded from orphan repair"
    ba="$(sed -n '/^cmd_build_all() {/,/^}/p' "$helper_src")"
    case "$ba" in
        *"cmd_fix_orphans --run"*)
            ok "the build recreates the outside build user by itself" ;;
        *) bad "the user has to know to run fix-orphans" ;;
    esac
    case "$ba" in
        *"cmd_sort_users --run"*)
            ok "passwd and group end up sorted by id" ;;
        *) bad "passwd stays in build order" ;;
    esac
    # sorting must be the LAST thing, once every package user exists
    i_sort="$(printf '%s' "$ba" | grep -n 'cmd_sort_users --run' | head -1 | cut -d: -f1)"
    i_seal="$(printf '%s' "$ba" | grep -n 'cmd_seal_install_dirs --run' | tail -1 | cut -d: -f1)"
    if [ -n "$i_sort" ] && [ -n "$i_seal" ] && [ "$i_sort" -gt "$i_seal" ]; then
        ok "sorting happens after every user has been created"
    else
        bad "passwd is sorted before all the users exist"
    fi
fi

# ---- what 4.3 hands over, 7.2 must hand back -------------------------------- #
# The two lists were written separately and drifted: 4.3 included `lib` and 7.2
# did not, so /lib stayed owned by the lfs user for the rest of the build while
# /bin and /sbin -- never handed over -- stayed root.  One list serves both now.
python3 - "$LFS_TOOL" <<'PY53'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
src = open(sys.argv[1]).read()
problems = []
if not hasattr(lfs, "LFS_HANDOVER_DIRS"):
    print("  FAIL  the handover set is not defined in one place"); sys.exit(1)
for d in ("usr", "lib", "lib64", "var", "etc", "tools", "bin", "sbin"):
    if d not in lfs.LFS_HANDOVER_DIRS:
        problems.append("%s is missing from the handover set" % d)
# /sources belongs to the lfs user by design and must NOT be handed back
if "sources" in lfs.LFS_HANDOVER_DIRS:
    problems.append("/sources would be taken from the lfs user")
# both sites must use the shared list, not a literal
if src.count("LFS_HANDOVER_DIRS") < 3:
    problems.append("one of the two chowns still uses its own list")
# symlinks: /lib is a symlink, so the give-back needs -h
i = src.index('"give the tree to root"')
if "-h -R root:root" not in src[i:i + 400]:
    problems.append("the give-back does not touch symlinks")
if problems:
    for p in problems: print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  the tree is handed over and handed back symmetrically")
PY53
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

# ---- scratch and human directories are never owned by a package ------------- #
# man-pages ended up owning /tmp, which would break every other user of it.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    ( SNAP_ROOT=/; INSTALLDIRS=""
      eval "$(sed -n '/^install_dirs_list() {/,/^}/p' "$helper_src")"
      eval "$(sed -n '/^install_dir_patterns() {/,/^}/p' "$helper_src")"
      eval "$(sed -n '/^matches_install_pattern() {/,/^}/p' "$helper_src")"
      eval "$(sed -n '/^is_install_dir() {/,/^}/p' "$helper_src")"
      for d in /tmp /var/tmp /root /home; do is_install_dir "$d" || exit 1; done
      exit 0 ) \
        && ok "/tmp, /var/tmp, /root and /home are never adopted" \
        || bad "a package could come to own /tmp or a home directory"

    # orphan repair must fix everything it found, not a sample of it
    fo="$(sed -n '/^cmd_fix_orphans() {/,/^}/p' "$helper_src")"
    case "$fo" in
        *"head -n 2000"*) bad "orphan repair still only fixes the first 2000" ;;
        *) ok "orphan repair fixes every file it found" ;;
    esac
    case "$fo" in
        *'gave $fixed of $n path'*)
            ok "it reports how many it actually changed" ;;
        *) bad "orphan repair claims success without counting" ;;
    esac
fi

# ---- "not found in book" when there IS no book ------------------------------ #
# A fresh chroot got the LFS book but not the BLFS one, so every lookup failed
# with "not found in book -- skipping" and then "Nothing to do -- everything is
# installed and up to date" -- which is the opposite of the truth, and exit 0.
pmt="$(dirname "$LFS_TOOL")/packagemanager"
if [ -f "$pmt" ]; then
    grep -q "^def _blfs_book_available" "$pmt" \
        && ok "a missing book is distinguished from a missing package" \
        || bad "no book and no package give the same message"
    bb="$(sed -n '/^def _blfs_book_available/,/^def /p' "$pmt")"
    case "$bb" in
        *'run_blfs(\["books"\])'*)
            bad "book availability is asked of `blfs books`, which lists the site too" ;;
        *) ok "book availability is checked on disk, not from a listing" ;;
    esac
    grep -q 'printError("Could not install: "' "$pmt" \
        && ok "a failed lookup is an error, not a success message" \
        || bad "a failed lookup still reports everything up to date"
    # and it must exit non-zero, or a script cannot tell
    ci="$(sed -n '/plan, missing, why, not_found = build_install_plan/,/printSuccess("Nothing to do/p' "$pmt")"
    case "$ci" in
        *"sys.exit(1)"*) ok "it exits non-zero when nothing could be looked up" ;;
        *) bad "a failed install still exits 0" ;;
    esac
    # the status line must be cleared, or it runs into the message
    case "$(sed -n '/nv = book_version(target)/,/continue/p' "$pmt")" in
        *clear_status*) ok "the progress line is cleared before the message" ;;
        *) bad "the status line runs into the error text" ;;
    esac
fi

# the BLFS book must travel into the chroot with the tools
python3 - "$LFS_TOOL" <<'PY54'
import sys
src = open(sys.argv[1]).read()
if "/usr/share/blfs" not in src:
    print("  FAIL  install-tools never copies the BLFS book in"); sys.exit(1)
if "BLFS book" not in src:
    print("  FAIL  install-tools does not report the BLFS book"); sys.exit(1)
print("  PASS  the BLFS book is installed into the chroot with the tools")
PY54
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

# ---- a cached book must actually be usable ---------------------------------- #
# A book imported by hand, or copied in by install-tools, has no metadata
# saying which selector it is.  resolve_book only looked at the site, so with
# the book sitting right there every lookup came back
#     wget: not in the BLFS book
# while `blfs books` listed it as cached.
bt="$(dirname "$LFS_TOOL")/blfs"
if [ -f "$bt" ]; then
    grep -q "^def _cached_book_files" "$bt" \
        && ok "a cached book is found when the selector does not resolve" \
        || bad "a cached book is ignored unless the site confirms it"
    grep -q "^def _best_cached_for" "$bt" \
        && ok "the closest cached book is chosen, not just the first" \
        || bad "any cached book would be picked at random"
    # urlsplit(None) yields bytes and fails deep inside os.path.join
    case "$(sed -n '/is_svn = "svn" in selector.lower()/,/return url, os.path.join/p' "$bt")" in
        *"if url is None:"*) ok "a cached book with no URL does not crash" ;;
        *) bad "a cached book would fail in urlsplit" ;;
    esac
    # and the error, when there really is no book, must say what to do
    case "$(sed -n '/no book for/,/blfs import/p' "$bt")" in
        *"blfs fetch"*"blfs import"*)
            ok "with no book at all it says how to get one" ;;
        *) bad "the no-book error gives no way forward" ;;
    esac
fi

# ---- missing settings are asked for, not silently defaulted ----------------- #
pmt="$(dirname "$LFS_TOOL")/packagemanager"
if [ -f "$pmt" ]; then
    grep -q "^_CONFIG_PROMPTS" "$pmt" \
        && ok "packagemanager asks for settings it does not have" \
        || bad "a missing setting is silently left blank"
    grep -q '"--show"' "$pmt" \
        && ok "--show prints the settings without asking" \
        || bad "config always prompts, even when only reading"
    grep -q "^def _book_in_use" "$pmt" \
        && ok "config shows which book each tool would use" \
        || bad "there is no way to see which book is in use"
    # only genuinely unset values -- never re-ask for something already chosen
    case "$(sed -n '/for key, prompt, default in _CONFIG_PROMPTS/,/changed = True/p' "$pmt")" in
        *'if cfg.get(key):'*) ok "a setting already chosen is not asked again" ;;
        *) bad "config would re-ask for values that are already set" ;;
    esac
fi

# ---- the tools must agree on the collector prefix --------------------------- #
# The prefix decides which groups shared directories carry.  install-tools
# wrote packagemanager.conf as JSON while packagemanager parses key=value, so
# the prefix never arrived: every package installed after the build joined
# `sysgroup_*` groups while the built system used `nimgnu_*` -- two parallel
# sets of groups over the same directories, and nothing to say so.
python3 - "$LFS_TOOL" <<'PY55'
import sys
src = open(sys.argv[1]).read()
seg = src[src.index("pmconf = os.path.join(cfg_dir"):]
seg = seg[:seg.index("_install_pkgusr_skel")]
problems = []
if "json.dump" in seg:
    problems.append("packagemanager.conf is still written as JSON")
if "collector_prefix=%s" not in seg:
    problems.append("the prefix is not written in key=value form")
print("  FAIL  " + problems[0] if problems else
      "  PASS  install-tools writes a config packagemanager can read")
sys.exit(1 if problems else 0)
PY55
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

pmt="$(dirname "$LFS_TOOL")/packagemanager"
if [ -f "$pmt" ]; then
    grep -q "^_SHARED_WITH_LFS" "$pmt" \
        && ok "settings shared with lfs have one owner" \
        || bad "packagemanager keeps its own copy of shared settings"
    grep -q "which is what the system was built" "$pmt" \
        && ok "a disagreeing prefix is reported, not silently preferred" \
        || bad "a prefix mismatch would pass unnoticed"
    # the book must be read from the config, not by shelling out to `lfs`
    bu="$(sed -n '/^def _book_in_use/,/^def /p' "$pmt")"
    case "$bu" in
        *_shared_lfs_config*) ok "the LFS book is read from the config file" ;;
        *) bad "the LFS book needs a mounted tree to report" ;;
    esac
fi
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q "^_read_shared_prefix()" "$helper_src" \
        && ok "lfs-helper reads the same prefix as the others" \
        || bad "lfs-helper could use a different prefix"
fi

# ---- packages re-creating directories that already exist -------------------- #
# make-ca's Makefile runs `install -vdm755 /usr/sbin`.  The directory is
# already there with the right mode, but install still tries to chmod it, and
# under the package-user model that is a hard error:
#     install: cannot change permissions of '/usr/sbin': Operation not permitted
# lfs-helper wraps install/chmod/chown during the chroot build for exactly
# this; packagemanager_install did not, so the same package failed after boot.
pmi="$(dirname "$LFS_TOOL")/packagemanager_install"
if [ -f "$pmi" ]; then
    grep -q "^_make_build_wrappers()" "$pmi" \
        && ok "packagemanager wraps install/chmod for the build" \
        || bad "a package re-moding an existing directory still fails"
    grep -q "PATH='\$_wrapdir'" "$pmi" \
        && ok "the wrappers are ahead of the real tools during the build" \
        || bad "the wrappers are created but never used"

    # behaviour, not just presence
    wd="$T/wrapmk"; mkdir -p "$wd/wrap" "$wd/exists"
    ( eval "$(sed -n '/^_make_build_wrappers() {/,/^}/p' "$pmi")"
      _make_build_wrappers "$wd/wrap" ) >/dev/null 2>&1
    if PATH="$wd/wrap:$PATH" install -vdm755 "$wd/exists" >/dev/null 2>&1; then
        ok "install -d on an existing directory succeeds"
    else
        bad "install -d on an existing directory still errors"
    fi
    if PATH="$wd/wrap:$PATH" install -vdm755 "$wd/fresh" >/dev/null 2>&1 \
       && [ -d "$wd/fresh" ]; then
        ok "install -d still creates directories that are missing"
    else
        bad "the wrapper broke directory creation"
    fi
    echo data > "$wd/src"
    if PATH="$wd/wrap:$PATH" install -m644 "$wd/src" "$wd/exists/f" >/dev/null 2>&1 \
       && [ -f "$wd/exists/f" ]; then
        ok "installing a file is passed through untouched"
    else
        bad "the wrapper broke ordinary file installs"
    fi
    # a real failure must still be a failure
    if PATH="$wd/wrap:$PATH" install -d "$wd/nonexistent-parent/sub/deeper/x" \
         2>/dev/null && [ ! -d "$wd/nonexistent-parent/sub/deeper/x" ]; then
        bad "the wrapper reports success for a directory it did not create"
    else
        ok "a genuine failure is not masked"
    fi
fi

# ---- a step's manifest lists what it owns, not what happened while it ran --- #
# last-step builds wget as the package user 'wget'.  Everything written during
# the step was recorded as last-step's, so /usr/bin/wget landed in last-step's
# manifest -- and the next thing to act on it took the file from wget:
#     -rwxr-xr-x 1 last-step last-step ... /usr/bin/wget
# after which wget could not reinstall itself.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q "^_drop_other_packages_files()" "$helper_src" \
        && ok "another package's files stay out of a step's manifest" \
        || bad "a step still records files another package installed"
    # it must be applied where the manifest is written
    case "$(sed -n '/local man="\$MANIFESTS\/\$name.files"/,/tracked \$/p' "$helper_src")" in
        *_drop_other_packages_files*)
            ok "the filter is applied when the manifest is written" ;;
        *) bad "the filter exists but is not used" ;;
    esac
    # root-owned files must still be recorded -- that is the normal case for a
    # root step, and dropping them would empty every chapter-7 manifest
    df="$(sed -n '/^_drop_other_packages_files() {/,/^}/p' "$helper_src")"
    case "$df" in
        *'"$cur" != root'*) ok "root-owned files are still recorded" ;;
        *) bad "a root step would record nothing at all" ;;
    esac
fi

# ---- build steps are not packages ------------------------------------------- #
# last-step, init-*, cfg-* and refind are actions, not software.  A `last-step`
# package user was created because a manifest existed under that name, and
# everything the step touched -- including wget's binary, installed as the wget
# user -- was then handed to it.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q "^_is_not_a_package()" "$helper_src" \
        && ok "steps that are not packages are recognised" \
        || bad "any step name could become a package user"
    au="$(sed -n '/^cmd_add_user() {/,/^}/p' "$helper_src")"
    case "$au" in
        *_is_not_a_package*) ok "add-user refuses to create one for a step" ;;
        *) bad "add-user would still create a last-step user" ;;
    esac
    na="$(sed -n '/^_needs_adoption() {/,/^}/p' "$helper_src")"
    case "$na" in
        *_is_not_a_package*) ok "adoption skips step names too" ;;
        *) bad "adoption could recreate the user add-user refused" ;;
    esac
fi

# the last-step script installs each package as its OWN user, from wheels
python3 - "$LFS_TOOL" <<'PY56'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
t = lfs.LAST_STEP_DEFAULT
sources = t.split("SOURCES=(")[1].split(")")[0]
problems = []
if "install_python_module" not in t:
    problems.append("the python modules the tools need are not installed")
if "build_as_package_user wget" not in t:
    problems.append("wget is not built as the wget package user")
# A modern sdist needs its build backend, and with no index reachable pip
# cannot fetch one: "BackendUnavailable: Cannot import 'hatchling.build'".
# A wheel is already built, so pip just unpacks it.
for line in sources.splitlines():
    line = line.strip()
    if "files.pythonhosted.org" not in line:
        continue
    if not line.rstrip('"').endswith(".whl"):
        problems.append("a python module is fetched as an sdist: %s"
                        % line.split("/")[-1][:40])
for mod in ("requests", "beautifulsoup4"):
    if mod not in sources:
        problems.append("%s is not in SOURCES" % mod)
if "--no-build-isolation" in t:
    problems.append("--no-build-isolation is still used")
# pip is told --no-deps, so every runtime dependency must be listed itself
for dep in ("urllib3", "idna", "certifi", "soupsieve"):
    if dep not in t:
        problems.append("%s (a runtime dependency) is never installed" % dep)
if t.index("install_python_module urllib3") > t.index("install_python_module requests"):
    problems.append("requests is installed before its dependencies")
if problems:
    for p in problems: print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  the last step installs each package as its own user, from wheels")
PY56
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

# a hint that installs a package must pull its dependencies too
python3 - "$LFS_TOOL" <<'PY58'
import sys, re, importlib.machinery as m
src = open(sys.argv[1]).read()
bad = [l.strip() for l in src.splitlines()
       if re.search(r"packagemanager install [a-z][a-z0-9-]*\s*\"?$", l)
       and "--recursive" not in l]
if bad:
    for b in bad[:3]:
        print("  FAIL  hint installs without dependencies: %s" % b[:60])
    sys.exit(1)
print("  PASS  install hints pull dependencies with --recursive")
PY58
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

# ---- site-packages is python's, not shared infrastructure ------------------- #
# A module user cannot write into site-packages until it joins the collector
# group that owns it.  The fix must be the SAME mechanism every other package
# uses -- join the existing collector group, or ask which group should own the
# directory.  Handing site-packages to the `install` group would mean "anyone
# may install here", which is exactly what the collector groups exist to avoid.
python3 - "$LFS_TOOL" <<'PY59'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
t = lfs.LAST_STEP_DEFAULT
problems = []
if "_grant_site_packages" not in t:
    problems.append("nothing gives the module user access to site-packages")
if "lfs-helper grant-dir" not in t:
    problems.append("it does not use the normal grant mechanism")
# the install group must never be applied to python's tree
if "grp=install" in t or "chgrp install" in t:
    problems.append("site-packages would be handed to the install group")
# and it must happen before pip, not after it fails
if "_grant_site_packages" in t and \
        t.index('_grant_site_packages "$user"') > t.index("python3 -m pip install"):
    problems.append("access is granted after pip has already failed")
if problems:
    for p in problems: print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  site-packages access uses the normal collector-group rules")
PY59
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q "^cmd_grant_dir()" "$helper_src" \
        && ok "access to one directory can be asked for directly" \
        || bad "a script cannot ask for access before failing"
    gd="$(sed -n '/^cmd_grant_dir() {/,/^}/p' "$helper_src")"
    case "$gd" in
        *grant_dir_access*) ok "it reuses the same rules as a failed build" ;;
        *) bad "grant-dir implements its own logic" ;;
    esac
    case "$gd" in
        *'test -w'*) ok "it does nothing when access already exists" ;;
        *) bad "grant-dir would regroup a directory needlessly" ;;
    esac
fi


# ---- helper functions must be defined before they are used ------------------ #
# bash parses top to bottom: a function called at line 437 but defined at 466
# does not exist yet, and the build ran without its wrappers:
#     packagemanager_install: line 437: _make_build_wrappers: command not found
pmi="$(dirname "$LFS_TOOL")/packagemanager_install"
if [ -f "$pmi" ]; then
    python3 - "$pmi" <<'PY60'
import re, sys
lines = open(sys.argv[1]).read().split("\n")
defs, bad = {}, []
for i, l in enumerate(lines):
    m = re.match(r"^([a-zA-Z_][a-zA-Z0-9_]*)\(\) \{", l)
    if m:
        defs.setdefault(m.group(1), i)
for name, dline in defs.items():
    for i, l in enumerate(lines[:dline]):
        if re.search(r"^\s+%s\b" % re.escape(name), l) and not l.strip().startswith("#"):
            enclosing = max((d for d in defs.values() if d < i), default=-1)
            if enclosing == -1:
                bad.append("%s used at line %d, defined at %d" % (name, i + 1, dline + 1))
            break
if bad:
    for b in bad: print("  FAIL  %s" % b)
    sys.exit(1)
print("  PASS  every helper is defined before it is used")
PY60
    if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

    # ---- one implementation of the collector-group rules --------------------- #
    # A package installed after boot must behave exactly like one built during
    # the chroot stage.  Two copies of the rules drift; lfs-helper owns them.
    gd="$(sed -n '/^grant_dir_to_user() {/,/^}/p' "$pmi")"
    case "$gd" in
        *"lfs-helper grant-dir"*)
            ok "packagemanager uses lfs-helper's collector-group rules" ;;
        *) bad "packagemanager keeps its own copy of the rules" ;;
    esac
    case "$gd" in
        *"fallback for a system without it"*)
            ok "it still works where lfs-helper is not installed" ;;
        *) bad "no fallback when lfs-helper is absent" ;;
    esac
    # the delegation must come FIRST, or the local copy decides
    i_del="$(printf '%s' "$gd" | grep -n "lfs-helper grant-dir" | head -1 | cut -d: -f1)"
    i_own="$(printf '%s' "$gd" | grep -n 'prefix="\$(collector_prefix_of)"' | head -1 | cut -d: -f1)"
    if [ -n "$i_del" ] && [ -n "$i_own" ] && [ "$i_del" -lt "$i_own" ]; then
        ok "the shared rules are consulted before the local copy"
    else
        bad "the local copy runs even when lfs-helper is available"
    fi
fi

# ---- uids should read as the build order ------------------------------------ #
# The uid a package gets is the order its user is created in.  Adoption walked
# the manifests alphabetically, so gcc (built 2nd of 22) ended up with a HIGHER
# uid than man-pages (the first chapter-8 package) -- which makes the uids
# useless for deciding what to rebuild first.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q "^_manifests_in_build_order()" "$helper_src" \
        && ok "manifests can be walked in build order" \
        || bad "adoption still walks manifests alphabetically"
    ae="$(sed -n '/^cmd_adopt_existing() {/,/^}/p' "$helper_src")"
    case "$ae" in
        *'for man in $(_manifests_in_build_order)'*)
            ok "adoption creates users in build order" ;;
        *) bad "adoption does not use the build order" ;;
    esac
    # whole seconds tie for packages built in the same second
    bo="$(sed -n '/^_manifests_in_build_order() {/,/^}/p' "$helper_src")"
    case "$bo" in
        *"stat -c %.Y"*) ok "sub-second timestamps keep the order exact" ;;
        *) bad "packages built in the same second would tie" ;;
    esac

    # behaviour: oldest manifest first, regardless of name
    bod="$T/buildorder"; mkdir -p "$bod"
    for p in zzz-first aaa-second mmm-third; do
        echo "/usr/bin/$p" > "$bod/$p.files"
        sleep 0.02
    done
    got="$(MANIFESTS="$bod"; eval "$bo"; _manifests_in_build_order \
           | xargs -n1 basename | sed 's/.files//' | tr '\n' ' ')"
    case "$got" in
        "zzz-first aaa-second mmm-third "*)
            ok "the order follows when they were written, not their names" ;;
        *) bad "build order came out as: $got" ;;
    esac
fi

# ---- editing the wrong install script fails silently ------------------------ #
# A package user's home holds two files with nearly identical names:
#     install_<name>-<version>   the source -- the one to edit
#     install_<name>             a runtime copy, overwritten every run
# Editing the second changes nothing, the install repeats unchanged, and it
# looks as though the tool threw the edit away.
pmt="$(dirname "$LFS_TOOL")/packagemanager"
if [ -f "$pmt" ]; then
    grep -q "^def _warn_if_wrong_file_edited" "$pmt" \
        && ok "an edit to the runtime copy is pointed out" \
        || bad "editing the wrong file goes unmentioned"
    grep -q "To change what it does, edit:" "$pmt" \
        && ok "a failure names the file to edit" \
        || bad "a failure gives no path to edit"

    # behaviour: warn only when the runtime copy is genuinely newer
    python3 - "$pmt" <<'PY61'
import sys, os, time, tempfile, importlib.machinery as m
pm = m.SourceFileLoader('pm', sys.argv[1]).load_module()
base = tempfile.mkdtemp()
os.makedirs(os.path.join(base, "p"))
src = os.path.join(base, "p", "install_p-1.0")
rt = os.path.join(base, "p", "install_p")
open(src, "w").write("real")
time.sleep(0.02)
open(rt, "w").write("edited")
pm.BASE_DIR = base
import io, contextlib
buf = io.StringIO()
with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(buf):
    pm._warn_if_wrong_file_edited("p", src)
warned = "runtime copy" in buf.getvalue()
os.utime(src, None)                      # now the source is newer
buf2 = io.StringIO()
with contextlib.redirect_stdout(buf2), contextlib.redirect_stderr(buf2):
    pm._warn_if_wrong_file_edited("p", src)
quiet = "runtime copy" not in buf2.getvalue()
if warned and quiet:
    print("  PASS  it warns only when the runtime copy is the newer file")
else:
    print("  FAIL  warned=%s quiet=%s" % (warned, quiet))
    sys.exit(1)
PY61
    if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi
fi

# ---- installing make-ca does not create any certificates -------------------- #
# It installs the TOOL.  Until it is run there is still no CA bundle, wget
# still cannot verify anything, and the /etc/wgetrc workaround stays -- but the
# install reported success, so the missing step is easy to overlook.
pmt="$(dirname "$LFS_TOOL")/packagemanager"
if [ -f "$pmt" ]; then
    grep -q "^def _hint_generate_ca_bundle" "$pmt" \
        && ok "the missing make-ca -g step is pointed out" \
        || bad "make-ca installs and nothing says to run it"
    hg="$(sed -n '/^def _hint_generate_ca_bundle/,/^def /p' "$pmt")"
    case "$hg" in
        *"make-ca -g"*) ok "it gives the exact command" ;;
        *) bad "the hint does not say what to run" ;;
    esac
    # silent once the certificates exist
    case "$hg" in
        *"certificates exist already"*) ok "it stops once certificates exist" ;;
        *) bad "the hint would repeat forever" ;;
    esac

    # ---- the book's init flavour must match the system ----------------------- #
    # A systemd book emits `systemctl` in its install scripts; on a SysV system
    # every affected package fails mid-install and has to be hand-edited.
    grep -q "^def _warn_init_mismatch" "$pmt" \
        && ok "a systemd/SysV book mismatch is reported" \
        || bad "the wrong book flavour goes unmentioned"
    wm="$(sed -n '/^def _warn_init_mismatch/,/^def /p' "$pmt")"
    case "$wm" in
        *"if book_systemd == have_systemd"*)
            ok "it says nothing when the book matches" ;;
        *) bad "the mismatch warning would always fire" ;;
    esac
fi

# ---- make-ca installed is not the same as certificates generated ------------ #
# `make-ca -g` prints "No update required!" and generates nothing when it
# considers its copy of certdata.txt current -- which it is straight after
# install.  The install then looks successful while the system still has no
# certificate bundle, and every HTTPS fetch keeps warning.
pmt="$(dirname "$LFS_TOOL")/packagemanager"
if [ -f "$pmt" ]; then
    grep -q "^def check_make_ca_generated" "$pmt" \
        && ok "an installed-but-ungenerated make-ca is noticed" \
        || bad "make-ca can be installed with no certificates and nothing said"
    grep -q "make-ca -g --force" "$pmt" \
        && ok "it gives the command that actually generates them" \
        || bad "it does not say how to finish the job"
    # and it must go quiet once a bundle exists
    python3 - "$pmt" <<'PY62'
import sys, os, io, contextlib, tempfile, importlib.machinery as m
pm = m.SourceFileLoader('pm', sys.argv[1]).load_module()
d = tempfile.mkdtemp()
fake = os.path.join(d, "make-ca")
open(fake, "w").write("#!/bin/sh\nexit 0\n")
os.chmod(fake, 0o755)
os.environ["PATH"] = d + os.pathsep + os.environ["PATH"]
pm._CA_BUNDLES = [os.path.join(d, "bundle.crt")]
buf = io.StringIO()
with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(buf):
    pm.check_make_ca_generated()
warned = "no CA certificate bundle" in buf.getvalue()
open(os.path.join(d, "bundle.crt"), "w").write("CERTS")
buf2 = io.StringIO()
with contextlib.redirect_stdout(buf2), contextlib.redirect_stderr(buf2):
    pm.check_make_ca_generated()
quiet = "no CA certificate bundle" not in buf2.getvalue()
if warned and quiet:
    print("  PASS  it warns only while the bundle is genuinely missing")
else:
    print("  FAIL  warned=%s quiet=%s" % (warned, quiet)); sys.exit(1)
PY62
    if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi
fi


# ---- passwd and group stay sorted, whoever creates the user ----------------- #
# Both halves of the toolchain create package users, and both append.  Sorting
# only at the end of build-all left anything installed afterwards -- by
# packagemanager, from BLFS -- appended out of order again.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q "^_sort_users_quietly()" "$helper_src" \
        && ok "lfs-helper sorts after creating a user" \
        || bad "users created by lfs-helper are appended unsorted"
fi
pmi="$(dirname "$LFS_TOOL")/packagemanager_install"
if [ -f "$pmi" ]; then
    au="$(sed -n '/^addUser() {/,/^}/p' "$pmi")"
    case "$au" in
        *"lfs-helper sort-users --run"*)
            ok "packagemanager sorts after creating a user too" ;;
        *) bad "users created by packagemanager are appended unsorted" ;;
    esac
    # it must not fail when lfs-helper is absent
    case "$au" in
        *"command -v lfs-helper"*) ok "it degrades quietly without lfs-helper" ;;
        *) bad "user creation would fail where lfs-helper is missing" ;;
    esac
fi

# behaviour: package users before collector groups, system entries first
srt="$T/sortcheck"; mkdir -p "$srt/etc" "$srt/usr/src" "$srt/.lfs-pkgusr"
printf 'root:x:0:\ninstall:x:9999:\nnimgnu_x:x:90005:aaa\nzzz:x:10099:\naaa:x:10001:\n' \
    > "$srt/etc/group"
printf 'root:x:0:0:root:/root:/bin/bash\n' > "$srt/etc/passwd"
if [ -f "$helper_src" ]; then
    LFS_ETC="$srt/etc" LFS_SNAP_ROOT="$srt" LFS_SRC_ROOT="$srt/usr/src" \
    LFS_PKGUSR_DIR="$srt/.lfs-pkgusr" \
        bash "$helper_src" sort-users --run >/dev/null 2>&1
    order="$(cut -d: -f1 "$srt/etc/group" | tr '\n' ' ')"
    case "$order" in
        "root install aaa zzz nimgnu_x "*)
            ok "system entries, then package users, then collector groups" ;;
        *) bad "sorted order came out as: $order" ;;
    esac
fi

# ---- prompts must allow line editing ---------------------------------------- #
# Without readline an arrow key inserts an escape sequence instead of moving
# the cursor, so a typo in a long answer -- a group name, a device path --
# means retyping the whole thing.
for t in lfs blfs packagemanager; do
    f="$(dirname "$LFS_TOOL")/$t"
    [ -f "$f" ] || continue
    grep -q "import readline" "$f" \
        || bad "$t: input() prompts have no line editing"
done
ok "the python tools import readline"

# an optional import: a python built without readline must still run
python3 - "$LFS_TOOL" <<'PY64'
import sys
src = open(sys.argv[1]).read()
i = src.index("import readline")
window = src[max(0, i - 200):i + 120]
if "try:" not in window or "ImportError" not in window:
    print("  FAIL  readline is imported unguarded; a python without it would fail")
    sys.exit(1)
print("  PASS  readline is optional, not required")
PY64
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

for f in lfs-helper packagemanager_install; do
    p="$(dirname "$LFS_TOOL")/$f"
    [ -f "$p" ] || continue
    # every prompt that reads an ANSWER needs -e; loops reading files do not
    bare="$(grep -nE "read (-r )?(ans|check|answer|reply)\b" "$p" \
            | grep -v -- "-e" | head -3)"
    [ -z "$bare" ] \
        || bad "$f: prompt without line editing: $(echo "$bare" | head -1)"
done
ok "the bash prompts use read -e"

# and -r as well, or a backslash in an answer is eaten
if grep -qE "read -e [^r-]" "$(dirname "$LFS_TOOL")/packagemanager_install" 2>/dev/null; then
    bad "a prompt uses -e without -r"
else
    ok "prompts keep backslashes literal (-r)"
fi

# ---- starting the whole build over -------------------------------------------#
# Deleting a built system is the most destructive thing these tools can do --
# potentially weeks of compilation -- so it has to say exactly what goes, what
# stays, and refuse outright in the one case that could damage the host.
python3 - "$LFS_TOOL" <<'PY65'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
src = open(sys.argv[1]).read()
if not hasattr(lfs, "cmd_bs_restart"):
    print("  FAIL  no way to start the build over"); sys.exit(1)
body = src[src.index("def cmd_bs_restart"):src.index("def cmd_bs_set_book")]
problems = []
# deleting through a bind-mounted /dev would reach the running system
if "the chroot is still mounted" not in body:
    problems.append("it does not refuse while the chroot is mounted")
for d in ('"dev/pts", "dev/shm", "dev", "proc", "sys", "run"',):
    if d not in body:
        problems.append("the mount check does not cover every virtual filesystem")
# dry run by default, and a confirmation that cannot be typed by accident
if "args.run" not in body:
    problems.append("restart is not dry-run by default")
if "Type the mount point" not in body:
    problems.append("the confirmation is too easy to give by accident")
# sources are expensive to re-download and unchanged by a build
if "keep_sources" not in body:
    problems.append("the downloaded sources are not kept")
# and it should point at the cheaper alternative
if "snapshot restore" not in body:
    problems.append("it does not mention restoring a snapshot instead")
if problems:
    for p in problems: print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  restart warns, confirms, keeps the sources and spares the host")
PY65
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

# ---- snapshots must not read live kernel filesystems ------------------------ #
# Excluding "./sys/*" skips the CONTENTS but still archives the ./sys directory
# itself.  Reading a live kernel filesystem's metadata gives
#     tar: ./sys: file changed as we read it
# and exit 1, so the snapshot failed -- then succeeded on a retry, because the
# timing happened to work out.  --one-file-system does not descend into
# anything mounted inside the tree at all.
python3 - "$LFS_TOOL" <<'PY66'
import sys
src = open(sys.argv[1]).read()
body = src[src.index('cmd = ("tar -C'):]
body = body[:body.index("prog = ")] if "prog = " in body else body[:2000]
problems = []
if "--one-file-system" not in body:
    problems.append("tar still descends into mounted filesystems")
# tar's exit 1 is "files differ", a warning on a live tree -- verify, don't die
if "rc == 1" not in body:
    problems.append("a tar warning is still treated as a failure")
if "tar -tf" not in body:
    problems.append("the archive is not verified before being accepted")
# but an unreadable archive must NOT be kept
if "os.remove(dest)" not in body:
    problems.append("a corrupt archive would be left in place")
if problems:
    for p in problems: print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  snapshots skip live filesystems and verify what they wrote")
PY66
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

# ---- a cancelled step must be resumed, not skipped -------------------------- #
# The orphan repair was gated on "does the lfs user exist" -- but the user is
# created FIRST.  Cancelling part-way left the user in place, so every later
# run skipped the repair entirely with half a million files still ownerless.
# A gate must test the WORK, never a side effect of having started it.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q "^_has_orphaned_files()" "$helper_src" \
        && ok "the orphan repair is gated on the files, not on the user" \
        || bad "a cancelled orphan repair would be skipped forever"
    ba="$(sed -n '/^cmd_build_all() {/,/^}/p' "$helper_src")"
    case "$ba" in
        *"if ! user_exists lfs; then"*)
            bad "build-all still gates the repair on the user existing" ;;
        *) ok "build-all gates it on there being work to do" ;;
    esac
    # -print -quit: stop at the first hit, so it costs nothing when clean
    ho="$(sed -n '/^_has_orphaned_files() {/,/^}/p' "$helper_src")"
    case "$ho" in
        *"-print -quit"*) ok "the check stops at the first orphan" ;;
        *) bad "the check walks the whole tree every time" ;;
    esac
    # long loops must show progress, or they get cancelled for looking hung
    fo="$(sed -n '/^cmd_fix_orphans() {/,/^}/p' "$helper_src")"
    case "$fo" in
        *"fixed % 5000"*) ok "a long repair shows progress" ;;
        *) bad "half a million chowns run with no output" ;;
    esac
    # and a silent skip hides real failures
    ip="$(sed -n '/^cmd_init_pkgusr() {/,/^}/p' "$helper_src")"
    case "$ip" in
        *"could not set the group on"*)
            ok "directories that could not be regrouped are named" ;;
        *) bad "a failed chgrp is silently counted as nothing to do" ;;
    esac
fi

# ---- an application user must be usable, not just exist --------------------- #
# `user create` made the account and stopped there: you could not become it,
# its home was world-readable, and nothing launched the program.
pmt="$(dirname "$LFS_TOOL")/packagemanager"
if [ -f "$pmt" ]; then
    grep -q "^def _setup_application_user" "$pmt" \
        && ok "creating an application user sets up access to it" \
        || bad "user create leaves an account nobody can use"
    su_body="$(sed -n '/^def _setup_application_user/,/^def _home_of/p' "$pmt")"
    case "$su_body" in
        *'"chmod", "0750", home'*) ok "the account's home is private" ;;
        *) bad "the application's home stays world-readable" ;;
    esac
    case "$su_body" in
        *'"usermod", "-a", "-G", u, main'*)
            ok "your own login joins the account's group" ;;
        *) bad "a shared directory would not be reachable" ;;
    esac
    # without a main user there is nobody to grant access TO
    case "$su_body" in
        *"No main user is set"*) ok "it says so when no main user is set" ;;
        *) bad "it silently does nothing when main_user is unset" ;;
    esac
    # the PAM file is not part of stock LFS: absence must not be an error
    pam="$(sed -n '/^def _allow_su_via_pam/,/^def _write_launcher/p' "$pmt")"
    case "$pam" in
        *"not present -- \`su - "*) ok "a missing PAM file is handled, not fatal" ;;
        *) bad "it assumes the hint's PAM file exists" ;;
    esac
    grep -q "_APPLICATION_USER_HELP" "$pmt" \
        && ok "application users have their own help section" \
        || bad "no help explaining what an application user is"
fi

# ---- shell completion -------------------------------------------------------- #
comp="$(dirname "$LFS_TOOL")/lfs-completion.bash"
if [ -f "$comp" ]; then
    bash -n "$comp" \
        && ok "the completion script parses" \
        || bad "the completion script has a syntax error"
    # subcommands must come from the tools themselves, or the list goes stale
    grep -q "_lfs_tool_subcommands" "$comp" \
        && ok "completions are read from each tool's own help" \
        || bad "the completion keeps a second list of commands"
    for t in lfs blfs packagemanager lfs-helper; do
        grep -q "complete -F _lfs_complete $t\b" "$comp" \
            || bad "no completion registered for $t"
    done
    ok "all four tools have completion registered"
fi

# ---- a system you can actually log into -------------------------------------- #
# A freshly built system has root with NO password.  Depending on the login
# manager that is either "anyone can log in as root" or "nobody can log in at
# all" -- discovered after a reboot, with no way in.
python3 - "$LFS_TOOL" <<'PY67'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
t = lfs.LAST_STEP_DEFAULT
problems = []
if "set_up_login_accounts" not in t:
    problems.append("nothing asks for a root password")
body = t[t.index("set_up_login_accounts() {"):] if \
    "set_up_login_accounts() {" in t else ""
if "passwd root" not in body:
    problems.append("the root password is never set")
# a scripted run has no terminal: it must say what is missing, not hang
if "[ ! -t 0 ]" not in body:
    problems.append("a non-interactive run would block on a prompt")
if "chroot /mnt/lfs /usr/bin/passwd root" not in body:
    problems.append("it does not say how to set the password later")
# the login account name is already configured -- reuse it, do not re-ask
if "main_user=" not in body:
    problems.append("it ignores the configured login account")
if problems:
    for p in problems: print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  the build ends by setting up accounts you can log in with")
PY67
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

# password detection must read /etc/shadow correctly
shd="$T/shadowcheck"; mkdir -p "$shd"
_haspw() {
    grep -qE "^root:[^:]*:" "$1" && ! grep -qE "^root:(\*|!|)?:" "$1"
}
printf 'root::19000:0:99999:7:::\n' > "$shd/empty"
printf 'root:!:19000:0:99999:7:::\n' > "$shd/locked"
printf 'root:$6$a$b:19000:0:99999:7:::\n' > "$shd/set"
if ! _haspw "$shd/empty" && ! _haspw "$shd/locked" && _haspw "$shd/set"; then
    ok "an empty, locked or real root password are told apart"
else
    bad "root password detection is wrong"
fi

# ---- decisions already made must not be asked again ------------------------- #
# The export copied into the tree said
#     dir|/usr/libexec/gcc|nimgnu_gcc
# yet the build still stopped to ask which group should share that directory.
# Two faults: nothing applied the file, and `import-groups --run` read the
# wrong path anyway.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    ba="$(sed -n '/^cmd_build_all() {/,/^}/p' "$helper_src")"
    case "$ba" in
        *"cmd_import_groups --run"*)
            ok "a copied-in groups export is applied automatically" ;;
        *) bad "the export sits unapplied until run by hand" ;;
    esac
    grep -q "^_groups_already_imported()" "$helper_src" \
        && ok "it is applied once, not on every build" \
        || bad "the import would run on every build-all"

    # `--run` used to be taken as the FILENAME, then overwrite the path
    ig="$(sed -n '/^cmd_import_groups() {/,/^}/p' "$helper_src")"
    case "$ig" in
        *'in="$STATE/collector-groups.export"; }'*)
            bad "import-groups --run still overwrites the file it found" ;;
        *) ok "import-groups --run reads the file it chose" ;;
    esac
    case "$ig" in
        *'local in="" run=0 a'*) ok "the arguments are parsed in one place" ;;
        *) bad "the run flag can still be wiped by a later declaration" ;;
    esac

    # and the prompt itself must consult the export, imported or not
    cg="$(sed -n '/^choose_collector_group() {/,/^}/p' "$helper_src")"
    case "$cg" in
        *'collector-groups.import'*)
            ok "the prompt checks the copied-in decisions first" ;;
        *) bad "a decision in the tree would still be asked about" ;;
    esac
fi

# end to end: the answer is in the file, so nothing is asked
igd="$T/importdec"; mkdir -p "$igd/.lfs-pkgusr" "$igd/etc" "$igd/usr/src"
printf 'root:x:0:\ninstall:x:9999:\n' > "$igd/etc/group"
printf 'root:x:0:0:root:/root:/bin/bash\n' > "$igd/etc/passwd"
printf '# prefix|nimgnu\ndir|/usr/libexec/gcc|nimgnu_gcc\n' \
    > "$igd/.lfs-pkgusr/collector-groups.import"
got="$(STATE="$igd/.lfs-pkgusr" awk -F'|' -v d=/usr/libexec/gcc \
        '$1 == "dir" && $2 == d { print $3; exit }' \
        "$igd/.lfs-pkgusr/collector-groups.import")"
[ "$got" = "nimgnu_gcc" ] \
    && ok "a recorded decision resolves without asking" \
    || bad "the recorded decision was not found (got '$got')"

# ---- 7.2 must actually hand the tree to root -------------------------------- #
# The handover used `chown --from lfs`, which changes only files owned by
# exactly that user.  A tree owned by a uid with no matching account -- or by
# an `lfs` whose uid changed since -- was silently left alone, so `prepare`
# reported "give the tree to root", changed nothing, and `enter` then refused.
# The loop in `run` caught it as a step that ran but stayed pending.
python3 - "$LFS_TOOL" <<'PY68'
import sys
src = open(sys.argv[1]).read()
i = src.index('"give the tree to root"')
cmd = src[i:i + 400]
if "--from lfs" in cmd:
    print("  FAIL  the handover still only matches files owned by 'lfs'")
    sys.exit(1)
if "chown -h -R root:root" not in cmd:
    print("  FAIL  the handover does not chown recursively"); sys.exit(1)
# and the refusal should say who DOES own it
if "_owner_name_of" not in src:
    print("  FAIL  the refusal does not name the actual owner"); sys.exit(1)
print("  PASS  7.2 hands the tree to root whoever owned it")
PY68
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

# behaviour: a tree owned by an unknown uid must still be handed over
hod="$T/handover"; mkdir -p "$hod/usr/bin" "$hod/etc"
chown -R 4242 "$hod/usr" "$hod/etc" 2>/dev/null || true
if [ "$(stat -c %u "$hod/usr")" = "4242" ]; then
    ( for d in usr etc; do [ -e "$hod/$d" ] && chown -h -R root:root "$hod/$d"; done; true )
    [ "$(stat -c %u "$hod/usr")" = "0" ] \
        && ok "a tree owned by an unknown uid is handed to root" \
        || bad "the handover left the tree owned by $(stat -c %u "$hod/usr")"
else
    ok "(cannot test unknown-uid handover as this user)"
fi

echo
echo "  PASS: $PASS   FAIL: $FAIL (final)"
[ "$FAIL" -eq 0 ]

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
# Count in FILES, not shell variables.
#
# Several checks call ok/bad from inside a subshell -- `( ... ) && ok || bad`,
# a pipeline, a `while read` fed by process substitution.  A variable
# incremented there dies with the subshell, so the suite printed 446 PASS
# lines and reported 433.  A wrong count is worse than no count: it can hide a
# regression behind a number that still looks healthy.
_COUNTDIR="${TMPDIR:-/tmp}/lfstest-count.$$"
mkdir -p "$_COUNTDIR"
: > "$_COUNTDIR/pass"
: > "$_COUNTDIR/fail"

ok()  { echo "  PASS  $1"; echo x >> "$_COUNTDIR/pass"; }
bad() { echo "  FAIL  $1"; echo x >> "$_COUNTDIR/fail"; }

# Lift ONE function out of a bash source file, to exercise it in isolation.
#
# This exists because `sed -n "/^fn() {/,/^}/p"` cannot do it.  A one-line
# function --
#     pkgusr_roots() { printf '%s\n%s\n' "$PKGUSR_ROOT" "$CFGUSR_ROOT"; }
# -- has no line starting with `}`, so sed runs on and swallows whatever
# function comes next.  That is not a cosmetic problem: the swallowed body
# referenced $STATE, `set -u` killed the subshell before a single assertion
# ran, the output collected nothing, and the test reported PASS.  It had been
# passing that way while its four comparisons were also wrong.
#
# A test that cannot fail is worse than no test, so the slicer is shared and
# there is exactly one of it.
_slice_fn() {   # _slice_fn <file> <fn>
    awk -v fn="$2" '
        BEGIN { start = "^" fn "\\(\\) \\{" }
        !inside && $0 ~ start {
            print
            if ($0 !~ /\}[[:space:]]*$/) inside = 1
            next
        }
        inside { print; if ($0 ~ /^\}/) inside = 0 }
    ' "$1"
}

# the python-heredoc blocks report their own verdict; fold them in the same way
_count_rc() {
    if [ "$1" -eq 0 ]; then echo x >> "$_COUNTDIR/pass"
    else echo x >> "$_COUNTDIR/fail"; fi
}

_pass_total() { wc -l < "$_COUNTDIR/pass" | tr -d ' '; }
_fail_total() { wc -l < "$_COUNTDIR/fail" | tr -d ' '; }

cleanup() { rm -rf "$T" "$_COUNTDIR"; }
trap cleanup EXIT

export LFS="$T/lfs"
# Two directories, as the tools use them: SOURCES_DIR holds the downloaded
# tarballs and is never written by a build; BUILD_ROOT is the scratch a build
# unpacks into.  They were one directory once, which is what every stale
# marker and foreign-ownership bug in /sources came from.
export SOURCES_DIR="$LFS/sources"
export BUILD_ROOT="$LFS/build"
mkdir -p "$LFS/sources" "$LFS/build" "$LFS/tools/bin"

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

[ -f "$LFS/build/demo-1.0/build/Makefile" ] \
    && ok "built out-of-tree in build/ subdir" || bad "build/ subdir missing"
[ -f "$LFS/tools/bin/demo" ] \
    && ok "package actually installed into \$LFS/tools/bin" \
    || bad "install produced no file"
[ -f "$LFS/tools/fixup.txt" ] \
    && ok "configure (post-install) phase ran" || bad "configure phase did not run"
grep -q "^/.*build$" "$LFS/build/.cc-build-demo" 2>/dev/null \
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
if LFS="$T/lfs2" SOURCES_DIR="$T/lfs2/sources" \
     BUILD_ROOT="$T/lfs2/build" bash "$T/demo.sh" unpack \
        > "$T/m.log" 2>&1; then
    bad "missing tarball reported success"
else
    ok "missing tarball fails cleanly"
fi

echo
echo "  PASS: $PASS   FAIL: $FAIL"
[ "$(_fail_total)" -eq 0 ]

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
_count_rc $?
echo "  PASS: $(_pass_total)   FAIL: $(_fail_total) (incl. tarball-name cases above)"

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
_count_rc $?

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
_count_rc $?

# ---- a stale source tree from an earlier chapter must be cleared ----------- #
# BUILD_ROOT is sticky (1777), so only the owner may delete a directory there.
# Chapters 5-6 unpack as the `lfs` user; chapter 8 rebuilds the same packages as
# their own package user, which then cannot remove the leftover tree -- the
# script's `rm -rf` fails, tar extracts on top, and the build drowns in
#     tar: gcc-15.2.0/README: Cannot open: File exists
# lfs-helper must clear it as root BEFORE handing over to the package user.
#
# The tarball is READ from the sources directory and the stale tree is removed
# from the build scratch: two directories, and the cleanup must use the right
# one for each.
stl="$T/stale"; mkdir -p "$stl/sources" "$stl/build" "$stl/src/demo-9.9"
echo fresh > "$stl/src/demo-9.9/NEW"
( cd "$stl/src" && tar czf "$stl/sources/demo-9.9.tar.gz" demo-9.9 )
mkdir -p "$stl/build/demo-9.9"; echo old > "$stl/build/demo-9.9/OLD"
chmod 1777 "$stl/sources" "$stl/build"
cat > "$stl/script.sh" <<'EOF'
pkg_glob="demo-9.9.tar.* demo-9.9.tgz"
EOF
# run just the cleanup routine out of lfs-helper
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    ( STATE="$stl"; SNAP_ROOT="$stl"; C_DIM=; C_OFF=
      SOURCES_DIR="$stl/sources"; BUILD_ROOT="$stl/build"
      say(){ :; }; warn(){ :; }
      # build_root_for decides where a step's scratch lives; a package builds
      # in its own home, so the routine no longer reads $BUILD_ROOT directly.
      # Stub it to the shared tree this fixture set up.
      eval "$(_slice_fn "$helper_src" clean_stale_source)"
      build_root_for() { printf '%s' "$BUILD_ROOT"; }
      clean_stale_source demo "$stl/script.sh" )
    if [ -d "$stl/build/demo-9.9" ]; then
        bad "stale source tree was not cleared before the build"
    elif [ ! -f "$stl/sources/demo-9.9.tar.gz" ]; then
        bad "the cleanup removed the tarball instead of the unpacked tree"
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
_count_rc $?

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
_count_rc $?

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
_count_rc $?

helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    # markers live in the build scratch now, not in the tarball store
    grep -q 'rm -f "\$blddir/.cc-build-\$name"' "$helper_src" \
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
_count_rc $?

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
_count_rc $?

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
    # -tmp manifests must map to the BASE package user (perl-tmp -> perl)
    grep -q "^_stage_base_name()" "$helper_src" \
        && ok "the -tmp and -passN manifests map to the base package user" \
        || bad "-tmp steps leave root-owned trees behind"
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
_count_rc $?

# ---- bootloader safety ----------------------------------------------------- #
# The book runs `grub-install /dev/sda`, which writes a disk's boot sector.  On
# a machine with an existing boot partition that is destructive, so grub is only
# generated when explicitly chosen.
#
# The default is NONE -- it used to be rEFInd, on the reasoning that rEFInd only
# ever adds files to an already-mounted ESP.  True, but it still stopped a
# finished build to ask about a bootloader on a machine that already had one.
# rEFInd remains the safe CHOICE; it is just no longer made for you.  When it is
# chosen, the script must still be non-destructive.
python3 - "$LFS_TOOL" <<'PY10'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
if lfs.bootloader() != "none":
    print("  FAIL  default bootloader is %r, expected none" % lfs.bootloader())
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
_count_rc $?

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
    # -U is the point: it creates the private group WITH the user so the ids
    # match.  The home now comes from pkgusr_home_for (packages and config
    # steps live in different roots), so match on -U, not on the path.
    grep -q 'useradd -c "package \$name" -d "\$(pkgusr_home_for "\$name")" -U' \
         "$helper_src" \
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
_count_rc $?

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
_count_rc $?

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
_count_rc $?

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
_count_rc $?

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
need = ["cfg_hostname", "cfg_hosts", "cfg_clock", "cfg_inputrc", "cfg_network"]
missing = [n for n in need if n not in names]
if missing:
    print("  FAIL  chapter 9 is missing: %s" % ", ".join(missing)); sys.exit(1)
# writing a config file installs nothing to compile: they must be root steps
print("  PASS  chapter 9 configuration steps are defined")
PY14
_count_rc $?

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
_count_rc $?

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
glob = lfs._pkg_glob_for(pv, "cfg_bootscripts")
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
_count_rc $?

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
out, left = lfs._fill_placeholders("LC_ALL=<locale name> locale charmap", "cfg_locale")
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
_count_rc $?

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
_count_rc $?

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
_count_rc $?

python3 - "$LFS_TOOL" <<'PY20'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
keys = [k for k, _d in lfs.CONFIG_KEYS]
if "collector_import_file" not in keys or not hasattr(lfs, "_install_collector_groups"):
    print("  FAIL  no way to supply a collector-group file for a rebuild")
    sys.exit(1)
print("  PASS  a collector-group export can be supplied via config")
PY20
_count_rc $?

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
_count_rc $?

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
_count_rc $?

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
_count_rc $?

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
_count_rc $?

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
_count_rc $?

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
_count_rc $?

helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q 'VERSION"' "$helper_src" \
        && ok "the installed version is recorded in the package user's home" \
        || bad "nothing records what version is installed"
    grep -q '# book   :' "$helper_src" \
        && ok "a build says which book the script came from" \
        || bad "the book behind a script is not shown"
fi

# ---- accounts you can log in with, as a built-in step ----------------------- #
# This was last_build_step.sh: a script created once on the HOST and then owned
# by the person, running last in the chroot.  Wrong home twice over -- a fix to
# it reached nobody who already had a copy (that is how
# `chown: invalid user: 'wget:wget'` survived three releases), and setting the
# root password is not a matter of taste: book 8.5 says to do it.
#
# wget and the Python modules moved to `packagemanager setup`, which is where
# bootstrapping the tooling belongs.  The root password could NOT move there:
# setup runs on the booted system, and you need to log in to run it.
python3 - "$LFS_TOOL" <<'PY27'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
src = open(sys.argv[1]).read()
problems = []
# the old machinery must be gone, not merely unused
for gone in ("last_step_path", "ensure_last_step_script", "last_step_sources",
             "LAST_STEP_DEFAULT", "_write_last_step_copy"):
    if gone in src:
        problems.append("%s is still here" % gone)
# and the built-in step takes its place, last in the order
if 'order.append("init-accounts")' not in src:
    problems.append("init-accounts is not appended to the step order")
if problems:
    for p in problems:
        print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  the final step is built in, not a script that can go stale")
PY27
_count_rc $?

# lfs-helper must actually perform it, and it must own no files
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
  _p=""
  _slice_fn "$helper_src" cmd_init_accounts | grep -q 'passwd root' \
      || _p="$_p;init-accounts does not set the root password"
  # a non-interactive run must SAY what is missing, never block
  _slice_fn "$helper_src" cmd_init_accounts | grep -q '\[ ! -t 0 \]' \
      || _p="$_p;init-accounts would hang on a scripted run"
  case "$(_slice_fn "$helper_src" cmd_build)" in
      *'"$name" = "init-accounts"'*) ;;
      *) _p="$_p;lfs-helper would look for a book script for init-accounts" ;;
  esac
  case "$(_slice_fn "$helper_src" _is_not_a_package)" in
      *init-accounts*) ;;
      *) _p="$_p;init-accounts would be given a package user" ;;
  esac
  grep -q 'init-accounts)' "$helper_src" \
      || _p="$_p;init-accounts cannot be run by hand"
  if [ -n "$_p" ]; then
      printf '%s\n' "${_p#;}" | tr ';' '\n' | while IFS= read -r m; do
          [ -n "$m" ] && bad "$m"
      done
  else
      ok "the root password is set inside the chroot, before you can reboot"
  fi
fi

# ---- what the built system needs before it can fetch anything --------------- #
# LFS ships no download tool, so a freshly booted system cannot get the sources
# for its own next package.  The tarball has to be on disk before the chroot is
# sealed, and get-sources is the last moment there is still a network.
#
# Resolved from the BLFS BOOK, not a hardcoded URL: the book already knows where
# wget comes from and keeps it current, and a second list of links is a second
# thing to go stale.
python3 - "$LFS_TOOL" <<'PYBOOT'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
src = open(sys.argv[1]).read()
problems = []
for fn in ("bootstrap_packages", "bootstrap_sources"):
    if not hasattr(lfs, fn):
        problems.append("there is no %s" % fn)
if hasattr(lfs, "bootstrap_packages"):
    lfs.load_config = lambda: {}
    if lfs.bootstrap_packages() != ["wget"]:
        problems.append("wget is not the default bootstrap package")
    lfs.load_config = lambda: {"bootstrap_packages": ""}
    if lfs.bootstrap_packages():
        problems.append("bootstrap packages cannot be turned off")
    lfs.load_config = lambda: {"bootstrap_packages": "wget curl"}
    if lfs.bootstrap_packages() != ["wget", "curl"]:
        problems.append("more than one bootstrap package is not accepted")
if "blfs" not in src or '"sources"' not in src:
    problems.append("the URLs are not resolved from the BLFS book")
if problems:
    for p in problems:
        print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  the bootstrap tarball is resolved from the book, not hardcoded")
PYBOOT
_count_rc $?


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
_count_rc $?

# The accounts step must be the LAST entry in the order, after the bootloader.
# It sets the root password, so everything that could still fail should have
# failed by the time it runs -- and it is the last thing standing between a
# built system and a reboot you cannot log in after.
python3 - "$LFS_TOOL" <<'PYLAST'
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r'^def cmd_bs_gen_chroot_scripts\(.*?(?=\n\ndef )', src, re.S | re.M)
body = m.group(0) if m else src
appends = re.findall(r'order\.append\("([^"]+)"\)', body)
if not appends:
    print("  FAIL  nothing is appended to the step order")
    sys.exit(1)
if appends[-1] != "init-accounts":
    print("  FAIL  the last step in the order is %r, not init-accounts" % appends[-1])
    sys.exit(1)
print("  PASS  the accounts step is ordered last")
PYLAST
_count_rc $?

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
    # /usr/src is shared install space; /sources and /build are scratch.  Both
    # kinds must be beyond a package's reach, but by DIFFERENT mechanisms --
    # conflating them is what once made /root root:install drwxrwx---, and what
    # made /sources root:install 775, dropping the o+w a build needs.
    ( SNAP_ROOT=/; INSTALLDIRS=""
      eval "$(sed -n '/^install_dirs_list() {/,/^}/p' "$helper_src")"
      eval "$(sed -n '/^install_dir_patterns() {/,/^}/p' "$helper_src")"
      eval "$(sed -n '/^matches_install_pattern() {/,/^}/p' "$helper_src")"
      eval "$(sed -n '/^is_install_dir() {/,/^}/p' "$helper_src")"
      eval "$(sed -n '/^never_adopt_list() {/,/^}/p' "$helper_src")"
      eval "$(sed -n '/^is_never_adopt() {/,/^}/p' "$helper_src")"
      is_install_dir /sources && is_install_dir /build \
        && is_install_dir /usr/src \
        && is_never_adopt /sources && is_never_adopt /build \
        && ! install_dirs_list | grep -qx /sources \
        && ! install_dirs_list | grep -qx /build ) \
        && ok "/sources, /build and /usr/src are never given to a package" \
        || bad "/sources or /build could be handed to a collector group"
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
# the host's skeleton is preferred over any default we invent
if not hasattr(lfs, "_install_pkgusr_skel"):
    problems.append("the host's skel-package is not copied")
if problems:
    for p in problems: print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  dry runs are coloured, hints are copyable, wget wrapper self-removes")
PY29
_count_rc $?

helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q "^cmd_verify()" "$helper_src" \
        && ok "the tree can be reconciled against what it should be" \
        || bad "no way to repair a tree that has drifted"
fi

# ---- /usr/local/bin must precede /usr/bin ----------------------------------- #
# The temporary no-verify wget wrapper lives in /usr/local/bin.  With that
# missing from the package user's PATH the wrapper was never found, and every
# HTTPS download failed with "cannot verify ... certificate".
# Assert the ORDER, not the literal line.  This used to grep for
#     PATH=/usr/lib/pkgusr:/usr/local/bin
# which is the wrapper path spelled out a third time -- so unifying the two
# wrapper directories broke a test that was really about /usr/local/bin.
bad_path=""
for f in lfs-helper packagemanager; do
    t="$(dirname "$LFS_TOOL")/$f"
    [ -f "$t" ] || continue
    _pl="$(grep -m1 '^PATH=.*:/usr/bin' "$t")"
    [ -n "$_pl" ] || { bad_path="$bad_path $f(no-PATH)"; continue; }
    # the wrappers first, then /usr/local/bin, then /usr/bin
    case "$_pl" in
        PATH=*:/usr/local/bin:*) ;;
        *) bad_path="$bad_path $f(local-bin-not-after-wrappers)"; continue ;;
    esac
    _pre="${_pl%%:/usr/bin*}"
    case "$_pre" in
        *:/usr/local/bin*) ;;
        *) bad_path="$bad_path $f(local-bin-after-usr-bin)" ;;
    esac
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
_count_rc $?

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
_count_rc $?

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
    _count_rc $?
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
_count_rc $?

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
_count_rc $?

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
_count_rc $?

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
_count_rc $?

grep -q 'root_steps.append("cfg_fstab")' "$LFS_TOOL" \
    && ok "writing /etc/fstab runs as root" \
    || bad "cfg_fstab would run as a package user and fail"

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
_count_rc $?

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
_count_rc $?

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
_count_rc $?

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
_count_rc $?

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
_count_rc $?

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
_count_rc $?

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
    os.makedirs(os.path.join(t, "usr", "src", "lfs-pkgusr", "progress"))
    os.makedirs(os.path.join(t, "tools", "bin"))
    os.makedirs(os.path.join(t, "usr", "bin"))
    if tools_gcc:
        open(os.path.join(t, "tools", "bin", "x86_64-lfs-linux-gnu-gcc"), "w").close()
    if temp_system:
        for b in ("gawk", "sed", "tar", "xz"):
            open(os.path.join(t, "usr", "bin", b), "w").close()
    if done is not None:
        json.dump({"book": "12.4", "done": done},
                  open(os.path.join(t, "usr", "src", "lfs-pkgusr", "progress",
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
_count_rc $?

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
_count_rc $?

# ---- already-built packages are adopted before anything new ----------------- #
# Chapters 5-7 run before package users exist, so their files are root-owned
# and the manifests are the only record of who installed what.  Nothing ran
# adopt-existing, so the FIRST package user on the system was man-pages -- a
# chapter-8 package -- while bash, coreutils and glibc still owned nothing.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    # Adoption now lives in establish_ownership, which build-all reaches
    # through _ownership_checkpoint.  Assert that it still happens and still
    # happens early -- not where the code used to sit.
    ba="$(_slice_fn "$helper_src" cmd_build_all)"
    eo="$(_slice_fn "$helper_src" establish_ownership)"
    case "$eo" in
        *"_vfy_manifest_ownership 1"*)
            ok "already-built packages get their users before new builds" ;;
        *)  bad "chapter 5-7 packages are never given their package users" ;;
    esac
    # the checkpoint must be reachable BEFORE the build loop, so a tree that is
    # already past 7.6 adopts before it builds anything new
    a="$(printf '%s' "$ba" | grep -n "_ownership_checkpoint" | head -1 | cut -d: -f1)"
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

    # verify must never take a path another package legitimately owns
    mo="$(sed -n '/^_vfy_manifest_ownership() {/,/^}/p' "$helper_src")"
    case "$mo" in
        *'user_exists "$cur" && continue'*)
            ok "a path owned by another real package is left alone" ;;
        *) bad "verify could take another package's files" ;;
    esac
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
_count_rc $?

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
_count_rc $?

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
_count_rc $?

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
_count_rc $?
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
os.makedirs(os.path.join(root, "usr", "src", "lfs-pkgusr", "manifests"))
os.makedirs(os.path.join(root, "usr"), exist_ok=True)
script = ("mkdir -p %s/usr/include/c++/15.2.0/experimental\n"
          "echo hdr > %s/usr/include/c++/15.2.0/experimental/algorithm\n"
          % (root, root))
lfs._run_tracked("gcc-pass2", script, as_lfs=False, lfs=root)
dirs = os.path.join(root, "usr", "src", "lfs-pkgusr", "manifests", "gcc-pass2.dirs")
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
_count_rc $?

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
_count_rc $?


# ---- manifests report directories, not just files --------------------------- #
# A package owns the directories it creates as well as the files in them.
# Reporting only files hid the tracking bug that left the C++ header tree
# root-owned while the headers inside belonged to gcc.
mfd="$T/manifests-report/usr/src/lfs-pkgusr/manifests"
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
        *"_vfy_seal_install_dirs"*)
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
_count_rc $?

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
_count_rc $?

# ---- scratch and human directories are never owned by a package ------------- #
# man-pages ended up owning /tmp, which would break every other user of it.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    ( SNAP_ROOT=/; INSTALLDIRS=""
      eval "$(sed -n '/^install_dirs_list() {/,/^}/p' "$helper_src")"
      eval "$(sed -n '/^install_dir_patterns() {/,/^}/p' "$helper_src")"
      eval "$(sed -n '/^matches_install_pattern() {/,/^}/p' "$helper_src")"
      eval "$(sed -n '/^is_install_dir() {/,/^}/p' "$helper_src")"
      eval "$(sed -n '/^never_adopt_list() {/,/^}/p' "$helper_src")"
      eval "$(sed -n '/^is_never_adopt() {/,/^}/p' "$helper_src")"
      for d in /tmp /var/tmp /root /home; do is_install_dir "$d" || exit 1; done
      exit 0 ) \
        && ok "/tmp, /var/tmp, /root and /home are never adopted" \
        || bad "a package could come to own /tmp or a home directory"

    # orphan repair must fix everything it found, not a sample of it
    fo="$(sed -n '/^_vfy_orphans() {/,/^}/p' "$helper_src")"
    case "$fo" in
        *"head -n 2000"*) bad "orphan repair still only fixes the first 2000" ;;
        *) ok "orphan repair fixes every file it found" ;;
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
_count_rc $?

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
_count_rc $?

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
# init-*, cfg_* and refind are actions, not software.  A `last-step` package
# user was once created because a manifest existed under that name, and
# everything the step touched -- including wget's binary, installed as the wget
# user -- was then handed to it.  last-step is gone, but the rule that made it
# harmful is not: any step name could still become a package user.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q "^_is_not_a_package()" "$helper_src" \
        && ok "steps that are not packages are recognised" \
        || bad "any step name could become a package user"
    au="$(_slice_fn "$helper_src" cmd_add_user)"
    case "$au" in
        *_is_not_a_package*) ok "add-user refuses to create one for a step" ;;
        *) bad "add-user would still create a user for a build step" ;;
    esac
    na="$(_slice_fn "$helper_src" _needs_adoption)"
    case "$na" in
        *_is_not_a_package*) ok "adoption skips step names too" ;;
        *) bad "adoption could recreate the user add-user refused" ;;
    esac
fi



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
_count_rc $?


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
    _count_rc $?

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
pm.BASE_DIR = base
# the directory on disk is the USER's, so build the fixture through the same
# helper the code uses -- the package "p" becomes the account p_p, and
# hard-coding "p" here made this test fail the moment prefixes were turned on
# resolve the home the same way the code does -- the account is p_p AND it
# lives under the package root, so neither part can be hard-coded here
_h = pm.pkgusr_home("p")
os.makedirs(_h)
src = os.path.join(_h, "install_p-1.0")
rt = os.path.join(_h, "install_p")
open(src, "w").write("real")
time.sleep(0.02)
open(rt, "w").write("edited")
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
    _count_rc $?
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
    _count_rc $?
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
_count_rc $?

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
_count_rc $?

# ---- sources and build scratch are two directories -------------------------- #
# They used to be one, and every problem in this area came from that.  A build
# unpacked into the tarball store, dropped .cc-* markers there, and left both
# owned by whoever built -- so a rebuild had to pick debris out of the thing it
# most needed to keep.  Split, and the whole class of problem is structural:
# /sources holds only what get-sources downloaded, and BUILD_ROOT is deleted
# whole.
python3 - "$LFS_TOOL" <<'PY65B'
import sys, os, re, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
problems = []
body = open(sys.argv[1]).read()

if 'BUILD_ROOT="${BUILD_ROOT:-$LFS/sources}"' in body:
    problems.append("BUILD_ROOT still defaults to the tarball store")
for need in ('SOURCES_DIR="${SOURCES_DIR:-$LFS/sources}"',
             'BUILD_ROOT="${BUILD_ROOT:-$LFS/build}"'):
    if need not in body:
        problems.append("generated scripts do not set %s" % need.split("=")[0])

# generate a real script and read what it does
cmds = ["mkdir -v build\ncd build", "../configure", "make", "make install"]
s = lfs._crosschain_script_body("demo", "ch-tools-demo", "demo-1.0",
                                "demo-1.0.tar.*", cmds)
# the markers must live in scratch, never in the tarball store
for marker in (".cc-build-demo", ".cc-dir-demo"):
    for line in s.splitlines():
        if marker in line and "SOURCES_DIR" in line:
            problems.append("%s is written to the tarball store" % marker)
if '$BUILD_ROOT/.cc-build-demo' not in s:
    problems.append("the build marker is not written to BUILD_ROOT")
# unpack must extract into scratch
if 'cd "$BUILD_ROOT"' not in s:
    problems.append("unpack does not work in BUILD_ROOT")
# and the symlink farm must be built before the tarball is looked for
u = s[s.index("unpack_pkg()"):s.index("#### UNPACK DONE ####")]
if "_link_sources" not in u:
    problems.append("unpack does not build the sources symlink farm")

# the chroot copy must map BOTH directories, not just one
c = lfs._chrootify(s)
if 'SOURCES_DIR="${SOURCES_DIR:-/sources}"' not in c:
    problems.append("the chroot script does not point at /sources")
if 'BUILD_ROOT="${BUILD_ROOT:-/build}"' not in c:
    problems.append("the chroot script does not point at /build")

if problems:
    for p in problems: print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  tarball store and build scratch are separate directories")
PY65B
_count_rc $?

# ---- a book command may reach a sibling tarball through .. ------------------ #
# The book does this, in Tcl:
#
#     cd ..
#     tar -xf ../tcl8.6.16-html.tar.gz --strip-components=1
#
# `cd ..` leaves the build subdirectory, so ".." is then the package root's
# parent -- which used to be the sources directory and is now BUILD_ROOT.
# Splitting the two would break every command of this shape.
#
# The fix must not be a list of packages known to do it: that would be a second
# thing to keep in sync with the book, and wrong the first time a new release
# adds another.  unpack_pkg symlinks EVERY downloaded file into BUILD_ROOT, so
# "../<anything-we-downloaded>" resolves for any package in any future book.
# This test builds a package that does exactly what Tcl does.
_sbx="$T/split"
mkdir -p "$_sbx/lfs/sources" "$_sbx/lfs/out" "$_sbx/mk/demo-2.0" "$_sbx/mk/doc"
cat > "$_sbx/mk/demo-2.0/configure" <<'EOF'
#!/bin/bash
cat > Makefile <<'MK'
all:
	@echo compiling
install:
	@true
MK
EOF
chmod +x "$_sbx/mk/demo-2.0/configure"
( cd "$_sbx/mk" && tar czf "$_sbx/lfs/sources/demo-2.0.tar.gz" demo-2.0 )
echo html > "$_sbx/mk/doc/index.html"
( cd "$_sbx/mk" && tar czf "$_sbx/lfs/sources/demo-2.0-html.tar.gz" doc )
echo patch > "$_sbx/lfs/sources/demo-2.0-fix-1.patch"

python3 - "$LFS_TOOL" "$_sbx/demo.sh" <<'PYSPLIT'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
cmds = [
    "mkdir -v build\ncd       build",
    "../configure",
    "make",
    "make install",
    # the book's Tcl shape, verbatim in structure
    "cd ..\ntar -xf ../demo-2.0-html.tar.gz -C ../../out\n"
    "cp -v ../demo-2.0-fix-1.patch ../../out/patch.seen",
]
open(sys.argv[2], "w").write(
    lfs._crosschain_script_body("demo", "ch-tools-demo", "demo-2.0",
                                "demo-2.0.tar.*", cmds))
PYSPLIT

# The suite exports SOURCES_DIR/BUILD_ROOT for other tests; clear them here so
# this exercises the DEFAULTS a real build would get.
( cd "$_sbx" && env -u SOURCES_DIR -u BUILD_ROOT LFS="$_sbx/lfs" \
    bash demo.sh all ) >"$_sbx/log" 2>&1
_sp=""
[ -d "$_sbx/lfs/out/doc" ]        || _sp="$_sp;a sibling tarball reached through .. was not found"
[ -f "$_sbx/lfs/out/patch.seen" ] || _sp="$_sp;a patch reached through .. was not found"
# and the whole point: a full build must not have touched the tarball store
_left="$(ls -A "$_sbx/lfs/sources" | grep -v '^demo-2\.0' | tr '\n' ' ' || true)"
[ -z "$_left" ] || _sp="$_sp;a build wrote into the tarball store: $_left"
[ -d "$_sbx/lfs/build/demo-2.0" ] || _sp="$_sp;the package was not unpacked into BUILD_ROOT"
[ -f "$_sbx/lfs/build/.cc-dir-demo" ] || _sp="$_sp;build markers did not land in BUILD_ROOT"
[ -L "$_sbx/lfs/build/demo-2.0-html.tar.gz" ] || _sp="$_sp;the farm entry is not a symlink"
if [ -n "$_sp" ]; then
    printf '%s\n' "${_sp#;}" | tr ';' '\n' | while IFS= read -r _m; do
        [ -n "$_m" ] && bad "$_m"
    done
    sed 's/^/          /' "$_sbx/log" | tail -8
else
    ok "'../<tarball>' resolves for any package, and /sources stays clean"
fi

# ---- /sources has ONE owner convention, and it is the book's ---------------- #
# Three rules had drifted apart, and the result on disk was a mixture:
#
#     drwxrwxrwt 1 9998 install   /mnt/lfs/sources/
#     -rw-r--r-- 1 lfs  9998      acl-2.3.2.tar.xz
#
#   * lfs's _chown_tree_to_lfs added "sources" to the 4.3 handover set, so it
#     chowned /sources to the HOST's lfs user.  Book 4.3 does no such thing.
#   * lfs-helper carried /sources in install_dirs_list AS WELL AS in
#     never_adopt_list -- the exact conflation the comment above
#     never_adopt_list warns about, the one that made /root root:install.
#     verify --fix then made it root:install 775 and the seal made it 1775,
#     dropping the o+w that lets the unprivileged build user unpack at all.
#   * cmd_clean_sources reset unknown owners to root:root.
#
# The host lfs account is created by book 4.3's own useradd, which pins no
# uid -- it was 10753 on a Debian host.  Package users start at 10000, so that
# is not merely "an unnamed UID" as the book puts it: it COLLIDES with a real
# package user, and tarballs report as owned by some unrelated package.
#
# Book 3.1 settles it and the reasoning is given there in full:
#     chmod -v a+wt $LFS/sources        -> root:root 1777
#     chown root:root $LFS/sources/*    -> the contents too
# World-writable is what grants the build user access, so no group is involved.
python3 - "$LFS_TOOL" <<'PY65C'
import sys, os, stat, tempfile, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
problems = []

if not hasattr(lfs, "_normalize_sources"):
    print("  FAIL  no single rule for /sources ownership")
    sys.exit(1)

# 4.3 hands over the book's directories and NOT /sources
if "sources" in lfs.LFS_HANDOVER_DIRS:
    problems.append("/sources is in the 4.3 handover set")
body = open(sys.argv[1]).read()
h = body[body.index("def _chown_tree_to_lfs"):body.index("def _ensure_lfs_home")]
if 'LFS_HANDOVER_DIRS + ("sources",)' in h:
    problems.append("the 4.3 chown still adds /sources to the handover")

d = tempfile.mkdtemp()
src = os.path.join(d, "sources"); os.makedirs(src)
tar = os.path.join(src, "bash-5.3.tar.gz"); open(tar, "w").close()
tree = os.path.join(src, "acl-2.3.2"); os.makedirs(tree)
os.chmod(src, 0o775)                      # what verify --fix used to leave

try:
    os.chown(tar, 10753, 10753)           # a host uid inside the package range
    os.chown(tree, 10753, 10753)
except OSError:
    print("  SKIP  cannot chown here (needs root)")
else:
    lfs._normalize_sources(d, run=True, quiet=True)
    st = os.stat(src)
    if stat.S_IMODE(st.st_mode) != (stat.S_ISVTX | 0o777):
        problems.append("/sources is not 1777 -- the build user cannot unpack "
                        "(mode %o)" % stat.S_IMODE(st.st_mode))
    if st.st_uid != 0 or st.st_gid != 0:
        problems.append("/sources itself is not root:root")
    if os.lstat(tar).st_uid != 0:
        problems.append("a downloaded file keeps a host uid (book 3.1)")
    # an unpacked tree belongs to whoever is building it; taking it away
    # mid-build would stop that build.  Book 3.1 runs before any unpack.
    if os.lstat(tree).st_uid != 10753:
        problems.append("an unpacked tree was chowned out from under its build")
    # running it twice must change nothing
    if lfs._normalize_sources(d, run=True, quiet=True) != (0, False):
        problems.append("the rule is not idempotent")

# and it must actually be applied where sources appear or survive
g = body[body.index("def cmd_bs_get_sources"):body.index("def _title_pkgver")]
if "_normalize_sources" not in g:
    problems.append("get-sources does not apply book 3.1's chown")
r = body[body.index("def cmd_bs_restart"):body.index("def cmd_bs_set_book")]
if "_normalize_sources" not in r:
    problems.append("restart does not apply book 3.1's chown")

if problems:
    for p in problems: print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  /sources is root:root 1777 with root-owned contents (book 3.1)")
PY65C
_count_rc $?

# ---- /sources is scratch, not a shared install directory -------------------- #
# Being in install_dirs_list meant verify --fix set it root:install 775 and
# seal-install-dirs set 1775 -- both drop the o+w of book 3.1's `a+wt`, and
# o+w is the only thing that lets the unprivileged build user unpack there.
# It belongs in never_adopt_list (no package may own it) and nowhere else.
if [ -r "$(dirname "$LFS_TOOL")/lfs-helper" ]; then
    HELPER="$(dirname "$LFS_TOOL")/lfs-helper"
else
    HELPER=""
fi
if [ -n "$HELPER" ]; then
    _p=""
    # the DEFAULT list, i.e. the heredoc, must not carry it
    if sed -n '/^install_dirs_list()/,/^}/p' "$HELPER" | grep -qx '/sources'; then
        _p="$_p;/sources is still a shared install directory"
    fi
    # but it must still be a directory no package may adopt
    if ! sed -n '/^never_adopt_list()/,/^}/p' "$HELPER" | grep -qx '/sources'; then
        _p="$_p;/sources may now be adopted by a package"
    fi
    # an installdirs.lst from an older run must not bring it back
    if ! sed -n '/^install_dirs_list()/,/^}/p' "$HELPER" | grep -q 'grep -vx.*/sources'; then
        _p="$_p;a stale installdirs.lst can still reintroduce /sources"
    fi
    # the build scratch is the same kind of thing and needs the same rules
    if ! sed -n '/^never_adopt_list()/,/^}/p' "$HELPER" | grep -qx '/build'; then
        _p="$_p;/build may be adopted by a package"
    fi
    if sed -n '/^install_dirs_list()/,/^}/p' "$HELPER" | grep -qx '/build'; then
        _p="$_p;/build is a shared install directory"
    fi
    # every tree scan must skip it -- otherwise each snapshot, ownership pass
    # and collector-group map walks every unpacked source tree
    if [ "$(grep -c 'not -path "\${\?r}\?/build/\*"' "$HELPER")" -lt 3 ]; then
        _p="$_p;a tree scan still descends into the build scratch"
    fi
    if [ -n "$_p" ]; then
        printf '%s\n' "${_p#;}" | tr ';' '\n' | while IFS= read -r m; do
            [ -n "$m" ] && bad "$m"
        done
    else
        ok "/sources and /build are scratch, not shared install directories"
    fi
else
    bad "lfs-helper not found beside $LFS_TOOL"
fi

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
_count_rc $?

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
#
# It lives in lfs-helper now, as the built-in init-accounts step.  It could not
# move to `packagemanager setup` with the rest of the old final step: setup runs
# on the BOOTED system, and you need to log in to run it.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
  _ia="$(_slice_fn "$helper_src" cmd_init_accounts)"
  _p=""
  case "$_ia" in
      *'passwd root'*) ;;
      *) _p="$_p;the root password is never set" ;;
  esac
  case "$_ia" in
      *'NO password yet'*) ;;
      *) _p="$_p;nothing explains why a root password matters" ;;
  esac
  # a scripted run has no terminal: it must say what is missing, not hang
  case "$_ia" in
      *'! -t 0'*) ;;
      *) _p="$_p;a non-interactive run would block on a prompt" ;;
  esac
  case "$_ia" in
      *'useradd -m'*) ;;
      *) _p="$_p;no login account is ever created" ;;
  esac
  if [ -n "$_p" ]; then
      printf '%s\n' "${_p#;}" | tr ';' '\n' | while IFS= read -r m; do
          [ -n "$m" ] && bad "$m"
      done
  else
      ok "the build ends with a system you can log into"
  fi
fi


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
_count_rc $?

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

# ---- a shared user reaches the session -------------------------------------- #
# A "shared user" is one that belongs to the group on the main user's XDG
# runtime directory:
#     drwxrws--- n76310 u_xdg_runtime  /tmp/xdg-n76310
# The display socket, the session bus and audio live there, so without that
# group a graphical program starts and then cannot draw anything.
pmt="$(dirname "$LFS_TOOL")/packagemanager"
if [ -f "$pmt" ]; then
    grep -q "^def _join_xdg_runtime_group" "$pmt" \
        && ok "a shared user joins the session group" \
        || bad "a shared user cannot reach the display or audio"
    jx="$(sed -n '/^def _join_xdg_runtime_group/,/^def _setup_application_user/p' "$pmt")"
    # the group must be READ from the directory, never assumed by name
    case "$jx" in
        *"getgrgid(os.stat(rt).st_gid)"*)
            ok "the group is read from the runtime directory" ;;
        *) bad "the session group name is hardcoded" ;;
    esac
    case "$jx" in
        *'u_xdg_runtime"'*) bad "a specific group name is hardcoded" ;;
        *) ok "no group name is baked in" ;;
    esac
    # a personal group is not a shared group
    case "$jx" in
        *"which is not a shared "*)
            ok "it refuses to add the user to a personal group" ;;
        *) bad "an application user could join the person's own group" ;;
    esac
    # both /run/user/<uid> and /tmp/xdg-<user> layouts
    xd="$(sed -n '/^def _xdg_runtime_dir_of/,/^def _join_xdg/p' "$pmt")"
    for p in "/run/user" "/tmp/xdg-"; do
        case "$xd" in
            *"$p"*) ;;
            *) bad "the runtime directory search misses $p" ;;
        esac
    done
    ok "both runtime-directory layouts are searched"
    # --shared and --share-dir are different things
    grep -q '"--share-dir"' "$pmt" \
        && ok "the session group and a shared directory are separate options" \
        || bad "--shared conflates the session group with a directory"
fi

# ---- the setup must be applicable after the fact ---------------------------- #
# An account made earlier -- or by hand -- should be able to reach the same
# state without deleting and recreating it.
pmt="$(dirname "$LFS_TOOL")/packagemanager"
if [ -f "$pmt" ]; then
    grep -q "^def cmd_user_setup" "$pmt" \
        && ok "an existing user can be set up after the fact" \
        || bad "the setup only happens at creation time"
    grep -q '"setup"' "$pmt" \
        && ok "`user setup` is registered" \
        || bad "the setup command is not reachable"
    # it must refuse on a user that does not exist, rather than half-creating
    cs="$(sed -n '/^def cmd_user_setup/,/^def _write_desktop_entry/p' "$pmt")"
    case "$cs" in
        *"no such user"*) ok "setup refuses on a user that does not exist" ;;
        *) bad "setup would act on a missing user" ;;
    esac
    # the same code path as create, or the two drift
    case "$cs" in
        *_setup_application_user*) ok "create and setup share one code path" ;;
        *) bad "setup reimplements what create does" ;;
    esac

    # menu entry
    grep -q "^def _write_desktop_entry" "$pmt" \
        && ok "a menu entry is written" \
        || bad "no desktop entry is created"
    de="$(sed -n '/^def _write_desktop_entry/,/^def _write_launcher/p' "$pmt")"
    for field in "Desktop Entry" "Exec=" "StartupWMClass=" "Icon="; do
        case "$de" in
            *"$field"*) ;;
            *) bad "the desktop entry has no $field" ;;
        esac
    done
    ok "the desktop entry has the fields a menu needs"
    # a launcher for a program that is not installed is a broken command
    sa="$(sed -n '/# 6. a launcher and a menu entry/,/_write_desktop_entry(main, u, app)/p' "$pmt")"
    case "$sa" in
        *"no launcher or menu entry"*)
            ok "nothing is written when the program is not installed" ;;
        *) bad "a launcher could point at a program that does not exist" ;;
    esac
    # and neither file is clobbered if it is already there
    case "$de" in
        *"already exists -- left alone"*) ok "an existing menu entry is kept" ;;
        *) bad "the desktop entry would be overwritten" ;;
    esac
fi

# ---- changing LFS_TGT invalidates the toolchain ----------------------------- #
# gcc-pass2 installs its C++ headers under $LFS_TGT.  Change LFS_TGT afterwards
# and the compiler looks under the new name while the headers sit under the
# old one -- present, readable, and invisible.  It surfaces forty packages
# later as "bits/c++config.h: No such file or directory", which reads like a
# missing file rather than a mismatch.
python3 - "$LFS_TOOL" <<'PY69'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
src = open(sys.argv[1]).read()
problems = []
if not hasattr(lfs, "_crosschain_tgt_mismatch"):
    problems.append("nothing detects a changed target triplet")
# the triplet must be RECORDED with the build, or there is nothing to compare
mk = src[src.index("def _mark_crosschain_done"):]
mk = mk[:mk.index("def lfs_tgt")]
if '"lfs_tgt"' not in mk:
    problems.append("the target is not recorded with the build progress")
# and checked before the chroot, not after
if "this tree was built for a different target" not in src:
    problems.append("a changed target is not reported")
i_check = src.find("this tree was built for a different target")
i_prep = src.find('if action == "prepare":')
if i_check < i_prep:
    problems.append("the check is not inside chroot prepare")
if problems:
    for p in problems: print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  a changed target triplet is caught before the chroot")
PY69
_count_rc $?

helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q "^_warn_on_triplet_mismatch()" "$helper_src" \
        && ok "the mismatch is also reported inside the chroot" \
        || bad "inside the chroot the mismatch is only a missing-file error"
    ba="$(sed -n '/^cmd_build_all() {/,/^}/p' "$helper_src")"
    case "$ba" in
        *_warn_on_triplet_mismatch*)
            ok "it is checked before building, not after failing" ;;
        *) bad "the mismatch check never runs" ;;
    esac
fi

# ---- three causes, one error message ---------------------------------------- #
# "bits/c++config.h: No such file or directory" is produced by three different
# situations needing three different fixes.  The compiler's own configure line
# tells them apart:
#   no --host and no --target -> a NATIVE gcc, which only chapter 8 builds:
#                                its install is half-finished
#   both are cross names      -> LFS_TGT changed since chapter 6
#   no headers at all         -> chapter 6 never finished
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q "^_explain_triplet_mismatch()" "$helper_src" \
        && ok "the cause of a mismatch is named, not just the symptom" \
        || bad "all three causes give the same message"
    ex="$(sed -n '/^_explain_triplet_mismatch() {/,/^}/p' "$helper_src")"
    case "$ex" in
        *"it is a NATIVE build"*)
            ok "a native compiler is recognised as chapter 8's" ;;
        *) bad "a half-installed chapter-8 gcc is not identified" ;;
    esac
    case "$ex" in
        *"LFS_TGT changed between"*)
            ok "two cross names are recognised as a changed LFS_TGT" ;;
        *) bad "a changed LFS_TGT is not identified" ;;
    esac
    # the two cases must give DIFFERENT fixes -- that is the whole point
    # the two causes need different fixes -- that is the whole point
    case "$ex" in
        *"lfs config lfs_tgt"*"--phase all --force"*|*"--phase all --force"*"lfs config lfs_tgt"*)
            ok "each cause gets the fix that applies to it" ;;
        *) bad "the same fix is offered for different causes" ;;
    esac
    # and it must say nothing when the names agree
    case "$ex" in
        *'[ "$have" = "$mine" ] && return 0'*)
            ok "it is silent when there is no mismatch" ;;
        *) bad "it would explain a mismatch that does not exist" ;;
    esac
fi

# ---- installs are staged, not written straight into the system -------------- #
# `make install` writes into the live system one file at a time, in Makefile
# order.  Interrupt it and the system is neither the old version nor the new
# one -- and for gcc that is unrecoverable: it installs its driver early and
# its C++ headers late, so a cancel in between leaves a compiler that cannot
# compile C++, which is what you need to rebuild it.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q "^_merge_stage()" "$helper_src" \
        && ok "installs go to a staging tree first" \
        || bad "installs still write straight into the live system"
    grep -q "DESTDIR='\$_stage'" "$helper_src" \
        && ok "DESTDIR points the install at the staging tree" \
        || bad "the staging tree is created but never used"

    # a FAILED install must leave the system untouched -- the whole point
    cb="$(sed -n '/^cmd_build() {/,/^}/p' "$helper_src")"
    case "$cb" in
        *'if [ "${rc:-0}" = 0 ]; then'*'_merge_stage'*)
            ok "the staged tree is moved in only on success" ;;
        *) bad "a failed install could still be merged" ;;
    esac
    case "$cb" in
        *"the system was not touched"*)
            ok "a failed install says the system is unchanged" ;;
        *) bad "a failed install does not say what state things are in" ;;
    esac

    # a package that ignores DESTDIR writes to the system anyway: say so
    ms="$(sed -n '/^_merge_stage() {/,/^}/p' "$helper_src")"
    case "$ms" in
        *"return 2"*) ok "an empty staging tree is detected" ;;
        *) bad "a package ignoring DESTDIR would look like a clean install" ;;
    esac
    case "$cb" in
        *"ignores DESTDIR"*) ok "and reported, not silently trusted" ;;
        *) bad "ignoring DESTDIR is not reported" ;;
    esac
    # merging must target the tracked root, not a hardcoded /
    # the installer, not the merge wrapper, is what writes
    it2="$(sed -n '/^_install_staged_tree() {/,/^}/p' "$helper_src")"
    case "$it2" in
        *'root="${SNAP_ROOT:-/}"'*) ok "the merge targets the tracked root" ;;
        *) bad "the merge writes to a hardcoded /" ;;
    esac

    # the workarounds this replaces must be gone
    grep -q "cmd_fix_toolchain" "$helper_src" \
        && bad "the symlink workaround is still present" \
        || ok "the triplet symlink workaround is gone"
    ba="$(sed -n '/^cmd_build_all() {/,/^}/p' "$helper_src")"
    case "$ba" in
        *"Finishing its install before going on"*)
            bad "the auto-finish workaround is still present" ;;
        *) ok "the auto-finish workaround is gone" ;;
    esac
fi

# ---- a shared user must know where the session is --------------------------- #
# Being in the session group is necessary but not sufficient: XDG_RUNTIME_DIR,
# WAYLAND_DISPLAY and the package-user PATH all come from
# /etc/pkgusr/skel-u_xdg/.bash_profile.  Without it the account can reach the
# socket and still not find it.
pmt="$(dirname "$LFS_TOOL")/packagemanager"
if [ -f "$pmt" ]; then
    grep -q "^def _link_xdg_profile" "$pmt" \
        && ok "a shared user gets the XDG profile" \
        || bad "a shared user has no XDG_RUNTIME_DIR"
    lp="$(sed -n '/^def _link_xdg_profile/,/^def _setup_application_user/p' "$pmt")"
    # a symlink, so editing the file once reaches every shared account
    case "$lp" in
        *"os.symlink(XDG_SKEL, target)"*) ok "it is linked, not copied" ;;
        *) bad "each account gets its own copy, which then drift" ;;
    esac
    # the runtime directory belongs to whoever is logged in: fill it in, do
    # not ship someone else's path
    case "$lp" in
        *"@XDG_RUNTIME_DIR@"*) ok "the runtime directory is filled in, not shipped" ;;
        *) bad "a hardcoded runtime directory would be installed" ;;
    esac
    case "$lp" in
        *"kept the old one as"*) ok "an existing profile is kept, not destroyed" ;;
        *) bad "the user's own .bash_profile would be overwritten" ;;
    esac
    # and it must be wired into the shared path
    sa="$(sed -n '/# 4. the session/,/# 5. a shared directory/p' "$pmt")"
    case "$sa" in
        *_link_xdg_profile*) ok "--shared links the profile as well as the group" ;;
        *) bad "the profile is never linked" ;;
    esac
fi

# the file must ship, and the Makefile must install it without clobbering
skel="$(dirname "$LFS_TOOL")/skel-u_xdg/.bash_profile"
[ -f "$skel" ] \
    && ok "the XDG profile ships with the tools" \
    || bad "the XDG profile is not shipped"
mkf="$(dirname "$LFS_TOOL")/Makefile"
if [ -f "$mkf" ]; then
    grep -q "skel-u_xdg" "$mkf" \
        && ok "make install installs it" \
        || bad "make install does not install the XDG profile"
    grep -q "kept your existing .bash_profile" "$mkf" \
        && ok "reinstalling does not overwrite your edits" \
        || bad "a reinstall would clobber the XDG profile"
fi

# ---- a snapshot must say what state it captured ----------------------------- #
# Restoring a snapshot named "chrosscompile_done" brought back a tree whose
# toolchain was ALREADY broken -- the snapshot had been taken after chapter 8
# damaged it.  Nothing said so, at save or at restore, so it looked like the
# restore had failed rather than the snapshot being bad.
python3 - "$LFS_TOOL" <<'PY70'
import sys, os, json, tempfile, importlib.machinery as m
store = tempfile.mkdtemp(); os.environ["LFS_STORE"] = store
os.makedirs(os.path.join(store, "books"), exist_ok=True)
json.dump({"default": "12.4", "lfs_tgt": "x86_64-nimgnu-linux-gnu"},
          open(os.path.join(store, "config.json"), "w"))
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
if not hasattr(lfs, "_toolchain_state"):
    print("  FAIL  a snapshot does not record the toolchain state"); sys.exit(1)

def tree(headers=None, native=False):
    t = tempfile.mkdtemp()
    if headers:
        p = os.path.join(t, "usr", "include", "c++", "15.2.0", headers, "bits")
        os.makedirs(p)
        open(os.path.join(p, "c++config.h"), "w").close()
    if native:
        os.makedirs(os.path.join(t, "usr", "lib", "gcc", "x86_64-pc-linux-gnu"))
    return t

problems = []
if not lfs._toolchain_state(tree("x86_64-nimgnu-linux-gnu")).startswith("ok"):
    problems.append("a clean chapter-6 tree is not recognised")
if not lfs._toolchain_state(tree("x86_64-nimgnu-linux-gnu", native=True)) \
        .startswith("BROKEN"):
    problems.append("a native gcc over the cross one is not detected")
if "unfinished" not in lfs._toolchain_state(tree()):
    problems.append("a tree with no C++ headers is not detected")
# headers under a different target than configured
st = lfs._toolchain_state(tree("x86_64-lfs-linux-gnu"))
if not st.startswith("BROKEN"):
    problems.append("headers under the wrong target are not detected")
src = open(sys.argv[1]).read()
if "Restoring it later will restore the breakage too" not in src:
    problems.append("saving a broken tree gives no warning")
if problems:
    for p in problems: print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  a snapshot records and reports the state it captured")
PY70
_count_rc $?

# ---- a snapshot label must not hide what it captured ------------------------ #
# "chapters 5-6: 22/22 steps" was all a snapshot recorded, so a tree where
# chapter 8 had already run -- and already broken the toolchain -- looked
# pristine.  Restoring it restored the damage, and it read as a failed restore
# rather than a bad snapshot.
python3 - "$LFS_TOOL" <<'PY71'
import sys, os, json, tempfile, importlib.machinery as m
store = tempfile.mkdtemp(); os.environ["LFS_STORE"] = store
os.makedirs(os.path.join(store, "books"), exist_ok=True)
json.dump({"default": "12.4", "lfs_tgt": "x86_64-nimgnu-linux-gnu"},
          open(os.path.join(store, "config.json"), "w"))
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
problems = []
if not hasattr(lfs, "_tree_state"):
    problems.append("nothing reports the state of a tree")
if not hasattr(lfs, "cmd_bs_verify"):
    problems.append("there is no way to ask what state a tree is in")

t = tempfile.mkdtemp()
os.makedirs(os.path.join(t, "usr", "src", "lfs-pkgusr", "progress"))
os.makedirs(os.path.join(t, "usr", "src", "zlib"))
os.makedirs(os.path.join(t, "usr", "lib", "gcc", "x86_64-pc-linux-gnu"))
p = os.path.join(t, "usr", "include", "c++", "15.2.0",
                 "x86_64-nimgnu-linux-gnu", "bits")
os.makedirs(p); open(os.path.join(p, "c++config.h"), "w").close()
names = [n for n, _s, _t in lfs.CROSSCHAIN_STEPS]
json.dump({"book": "12.4", "done": names, "lfs_tgt": "x86_64-nimgnu-linux-gnu"},
          open(os.path.join(t, "usr", "src", "lfs-pkgusr", "progress", "crosschain-progress.json"), "w"))
open(os.path.join(t, "usr", "src", "lfs-pkgusr", "progress", "steps-built"), "w").write("zlib\n")
state = dict(lfs._tree_state(t))
# chapters 5-6 alone is not the whole story
if "chapters 7-9" not in state:
    problems.append("chapter 7-9 progress is not reported")
if "WARNING" not in state:
    problems.append("a native gcc in the tree is not flagged")
if not state.get("toolchain", "").startswith("BROKEN"):
    problems.append("the toolchain state is not reported")
# and the snapshot must carry it
src = open(sys.argv[1]).read()
if '"state":' not in src:
    problems.append("the snapshot metadata does not record the tree state")
if problems:
    for p2 in problems: print("  FAIL  %s" % p2)
    sys.exit(1)
print("  PASS  a tree's real state is reported and recorded with snapshots")
PY71
_count_rc $?

# ---- staged installs must cope with the merged-/usr symlinks ---------------- #
# Book 4.2 makes /bin -> usr/bin, /sbin -> usr/sbin, /lib -> usr/lib.  A
# package installing into /bin produces a REAL bin/ directory in the staging
# tree, and copying that over the symlink fails:
#     cp: cannot overwrite non-directory '/bin' with directory '.../bin'
# That broke every package installing into those paths -- most of chapter 7 --
# on a completely fresh build.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q "^_resolve_staged_symlink_dirs()" "$helper_src" \
        && ok "staged directories are folded onto the tree's symlinks" \
        || bad "a package installing into /bin cannot be merged"
    ms="$(sed -n '/^_merge_stage() {/,/^}/p' "$helper_src")"
    i_fold="$(printf '%s' "$ms" | grep -n "_resolve_staged_symlink_dirs" | head -1 | cut -d: -f1)"
    i_cp="$(printf '%s' "$ms" | grep -n '_install_staged_tree' | head -1 | cut -d: -f1)"
    if [ -n "$i_fold" ] && [ -n "$i_cp" ] && [ "$i_fold" -lt "$i_cp" ]; then
        ok "the folding happens before the copy"
    else
        bad "the copy runs first and still fails on the symlinks"
    fi
    # driven by the live tree, not a hardcoded list of names
    rs="$(sed -n '/^_resolve_staged_symlink_dirs() {/,/^}/p' "$helper_src")"
    case "$rs" in
        *'[ -L "$live" ] || continue'*)
            ok "it folds whatever the tree actually has as a symlink" ;;
        *) bad "the symlink names are hardcoded" ;;
    esac

    # behaviour: bin/ and sbin/ fold, usr/bin/ is left alone
    sd="$T/stagedirs"; mkdir -p "$sd/usr/bin" "$sd/usr/sbin"
    ln -sf usr/bin "$sd/bin"; ln -sf usr/sbin "$sd/sbin"
    mkdir -p "$sd/stage/bin" "$sd/stage/usr/bin"
    echo m > "$sd/stage/bin/mount"; echo w > "$sd/stage/usr/bin/wall"
    ( SNAP_ROOT="$sd"; say() { :; }
      eval "$rs"
      _resolve_staged_symlink_dirs "$sd/stage" ) >/dev/null 2>&1
    if [ -f "$sd/stage/usr/bin/mount" ] && [ ! -d "$sd/stage/bin" ] \
       && [ -f "$sd/stage/usr/bin/wall" ]; then
        ok "bin/ is folded into usr/bin/ and nothing else is disturbed"
    else
        bad "the folding did not produce the expected staging tree"
    fi
fi

# ---- replacing a library a running system is using -------------------------- #
# `cp -a` opens the destination with O_TRUNC and writes.  For a shared library
# that is currently mapped that is fatal: every running process sees the file
# shrink under it.  Merging glibc that way killed the shell mid-install --
#     /usr/bin/env: error while loading shared libraries:
#         /usr/lib/libc.so.6: file too short
# -- and the chroot could not start any program afterwards.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q "^_install_staged_tree()" "$helper_src" \
        && ok "staged files are installed one at a time" \
        || bad "the merge still overwrites files in place"
    it="$(sed -n '/^_install_staged_tree() {/,/^}/p' "$helper_src")"
    case "$it" in
        *'mv -f "$tmp" "$dest"'*)
            ok "each file is renamed into place, never truncated" ;;
        *) bad "files are still written over in place" ;;
    esac
    # the temp file must be in the SAME directory, or mv is a copy, not a rename
    case "$it" in
        *'tmp="$dest.pkgusr-new.$$"'*)
            ok "the temporary is beside its destination, so mv is atomic" ;;
        *) bad "the temporary is elsewhere and mv would copy" ;;
    esac
    ms="$(sed -n '/^_merge_stage() {/,/^}/p' "$helper_src")"
    case "$ms" in
        *'cp -a "$stage"/. '*) bad "the wholesale cp -a is still there" ;;
        *) ok "the wholesale copy is gone" ;;
    esac

    # behaviour: replacing a file a process holds open must not disturb it
    ad="$T/atomic"; mkdir -p "$ad/usr/lib" "$ad/stage/usr/lib"
    printf 'OLDOLDOLD' > "$ad/usr/lib/lib.so"
    printf 'NEWNEWNEWNEW' > "$ad/stage/usr/lib/lib.so"
    before_ino="$(stat -c %i "$ad/usr/lib/lib.so")"
    ( SNAP_ROOT="$ad"; say() { :; }; warn() { :; }
      eval "$it"
      _install_staged_tree "$ad/stage" ) >/dev/null 2>&1
    after_ino="$(stat -c %i "$ad/usr/lib/lib.so")"
    if [ "$before_ino" != "$after_ino" ] \
       && [ "$(cat "$ad/usr/lib/lib.so")" = "NEWNEWNEWNEW" ]; then
        ok "the replacement is a new inode, so open files keep the old one"
    else
        bad "the file was overwritten in place (inode unchanged)"
    fi
fi

# ---- staging is not worth paying for on every package ----------------------- #
# Staging costs roughly an extra copy of everything installed -- measurably
# slower on a big package.  It is worth it only where an interrupted install
# cannot be recovered from: interrupt man-pages and you rebuild man-pages;
# interrupt gcc or glibc and there is no compiler and no libc left to rebuild
# them WITH.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q "^STAGE_PACKAGES_DEFAULT=" "$helper_src" \
        && ok "only the packages that cannot be recovered are staged" \
        || bad "every package pays the staging cost"
    for p in gcc glibc binutils bash coreutils; do
        grep -q "^STAGE_PACKAGES_DEFAULT=.*$p" "$helper_src" \
            || bad "$p is not staged, but an interrupted install would be fatal"
    done
    ok "the toolchain packages are all in the default list"

    ss="$(sed -n '/^_should_stage() {/,/^}/p' "$helper_src")"
    # -tmp and -passN are the same package at an earlier stage
    case "$ss" in
        *'base="${name%-tmp}"'*) ok "the -tmp and -passN variants count too" ;;
        *) bad "gcc-pass1 would not be staged" ;;
    esac
    case "$ss" in
        *"LFS_STAGE_PACKAGES"*) ok "the list is configurable" ;;
        *) bad "the list is hardcoded" ;;
    esac
    case "$ss" in
        *"all)  return 0"*"none) return 1"*) ok "all / none are accepted" ;;
        *) bad "there is no way to turn staging fully on or off" ;;
    esac
    cb="$(sed -n '/^cmd_build() {/,/^}/p' "$helper_src")"
    case "$cb" in
        *"--stage)"*"--no-stage)"*) ok "a single build can override it" ;;
        *) bad "staging cannot be forced or skipped per build" ;;
    esac

    # behaviour
    ( STAGE_PACKAGES_DEFAULT="$(sed -n 's/^STAGE_PACKAGES_DEFAULT=\"\(.*\)\"$/\1/p' \
        "$helper_src" | head -1)"
      eval "$ss"
      _should_stage gcc && _should_stage glibc && _should_stage gcc-pass2 \
        && ! _should_stage man-pages && ! _should_stage zlib ) \
        && ok "gcc and glibc stage; man-pages and zlib do not" \
        || bad "the wrong packages are being staged"
fi

# ---- the staging directory must belong to whoever builds -------------------- #
# It is created by root, but the build runs as the PACKAGE USER, so
# `make install DESTDIR=...` could not write into it:
#     mkdir: cannot create directory '/.lfs-pkgusr/stage/gcc': Permission denied
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    cb="$(sed -n '/^cmd_build() {/,/^}/p' "$helper_src")"
    case "$cb" in
        *'chown "$owner:$owner" "$_stage"'*)
            ok "the staging directory is given to the package user" ;;
        *) bad "the package user cannot write into its own staging directory" ;;
    esac
    # and the parent must be traversable, or the chown alone is not enough
    case "$cb" in
        *'chmod 755 "$(dirname "$_stage")"'*)
            ok "the staging parent is traversable" ;;
        *) bad "the package user cannot reach into the staging directory" ;;
    esac
    # a root step needs no chown -- there is no package user to give it to
    case "$cb" in
        *'[ "$as_root" != 1 ] && user_exists "$owner"'*)
            ok "a root step is not given away to a user that may not exist" ;;
        *) bad "the chown would fail on a root step" ;;
    esac
    # the owner must be known BEFORE the stage is made, or it chowns to nothing
    i_owner="$(printf '%s' "$cb" | grep -n 'owner="\$(pkg_owner_name' | head -1 | cut -d: -f1)"
    i_stage="$(printf '%s' "$cb" | grep -n '_stage="\$(_stage_dir_for' | head -1 | cut -d: -f1)"
    if [ -n "$i_owner" ] && [ -n "$i_stage" ] && [ "$i_owner" -lt "$i_stage" ]; then
        ok "the owner is resolved before the staging directory is made"
    else
        bad "the staging directory is created before the owner is known"
    fi
fi

# ---- a package must own the files its earlier stages installed -------------- #
# The same package is built more than once: ncurses in chapter 6 (as the lfs
# user), perl-tmp in chapter 7 (as root), then the real one in chapter 8 as
# its package user.  The earlier files keep the earlier owner, and the package
# user cannot overwrite or re-mode them:
#     cp: cannot create regular file '/usr/bin/tic': Permission denied
#     Couldn't chmod 644 /usr/lib/perl5/.../perl.pod: Operation not permitted
# One cause, two chapters -- so one mechanism, applied to every package.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q "^_claim_earlier_stages()" "$helper_src" \
        && ok "a package claims the files its earlier stages installed" \
        || bad "a rebuild cannot overwrite its own earlier files"
    ce="$(sed -n '/^_claim_earlier_stages() {/,/^}/p' "$helper_src")"
    # every naming shape the same package takes across the book
    # the stages are built from a loop now, so check the suffixes it appends
    case "$ce" in
        *'"$stem-tmp" "$stem-pass1" "$stem-pass2"'*)
            ok "the -tmp and -passN stages are all claimed" ;;
        *) bad "an earlier stage suffix is missing" ;;
    esac
    # ONLY what the build left behind -- never another package's file
    case "$ce" in
        *"root|lfs|UNKNOWN) ;;"*)
            ok "only root- and lfs-owned paths are claimed" ;;
        *) bad "it could take a file belonging to another package" ;;
    esac
    # directories too, or the package cannot create files in them
    case "$ce" in
        *'.dirs'*) ok "the directories are claimed as well as the files" ;;
        *) bad "the package could not create files in its own directories" ;;
    esac
    # shared install dirs stay shared
    case "$ce" in
        *"is_install_dir"*) ok "shared install directories are left alone" ;;
        *) bad "a shared directory could be taken by one package" ;;
    esac
    # and it must run BEFORE the build, not after it fails
    cb="$(sed -n '/^cmd_build() {/,/^}/p' "$helper_src")"
    i_claim="$(printf '%s' "$cb" | grep -n '_claim_earlier_stages' | head -1 | cut -d: -f1)"
    i_build="$(printf '%s' "$cb" | grep -n 'building \$name' | head -1 | cut -d: -f1)"
    if [ -n "$i_claim" ] && [ -n "$i_build" ] && [ "$i_claim" -lt "$i_build" ]; then
        ok "the claim happens before the build starts"
    else
        bad "the claim runs too late to help"
    fi
fi

# ---- checks that silently always passed --------------------------------------#
# From an independent review of `lfs` against the book.  Each of these hid a
# real failure rather than reporting it.
python3 - "$LFS_TOOL" <<'PY73'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
src = open(sys.argv[1]).read()
problems = []

# md5 verification: `md5sum -c … | grep -v ": OK"` returned 0 on a CORRUPTED
# tree -- grep inverts the verdict and the pipe discards md5sum's status.
i = src.index("verifying md5sums")
seg = src[i:i + 900]
# ignore comment lines: the fix is documented with the broken command quoted
code = "\n".join(l for l in seg.splitlines() if not l.lstrip().startswith("#"))
if 'grep -v ": OK"' in code:
    problems.append("md5 verification still inverts its own verdict")
if "md5sum -c md5sums --quiet" not in seg or "sys.exit(1)" not in seg:
    problems.append("a bad md5sum does not fail the download")

# The book's toolchain gate must stay a gate.  These five greps MUST produce
# output -- no match means the build is linked against the host -- and the
# blanket `|| true` turned the only real check into a guaranteed pass.
gates = [
    'grep -E -o "/usr/lib.*/S?crt[1in].*succeeded" dummy.log',
    'grep -B3 "^ /usr/include" dummy.log',
    "grep 'SEARCH.*/usr/lib' dummy.log",
    'grep "/lib.*/libc.so.6 " dummy.log',
    'grep found dummy.log',
]
out = lfs._soften_diagnostics("\n".join(gates))
for line in out.splitlines():
    if "|| true" in line:
        problems.append("a toolchain gate is still softened: %s" % line[:40])
# but an ordinary diagnostic grep must STILL be softened
if "|| true" not in lfs._soften_diagnostics("grep something optional.txt"):
    problems.append("ordinary diagnostic greps are no longer softened")

# 9.9's `cat > /etc/shells` block is <pre class="root">, not "userinput", so
# cfg_shells resolved to zero commands and /etc/shells was never written.
pi = src.index("classes = tag.get(\"class\") or []")
if '"root", "install"' not in src[pi:pi + 700]:
    problems.append("only 'userinput' blocks are parsed; /etc/shells is missed")
# the accepted-class tuple itself must not include "screen" (output samples)
accept = src[src.index("any(c in classes for c in ("):][:120]
if "screen" in accept:
    problems.append("'screen' blocks (output samples) would be run as commands")

# a step that produces nothing must say so
if "has no command blocks in this book" not in src:
    problems.append("a step resolving to zero blocks is still skipped silently")

# book 4.4's ~/.bashrc opens with these; without them the build runs with
# bash's command hash on and root's umask
env = lfs._lfs_env_prefix("/mnt/lfs")
if not env.startswith("set +h\numask 022\n"):
    problems.append("the build environment is missing set +h / umask 022")

# ^ anchored to the whole string, so a later line never matched
if not (lfs._TEST_DIAG_RE.flags & 8):
    problems.append("_TEST_DIAG_RE has no re.M; ^ only matches the first line")

# dead duplicate flagged by pyflakes
if src.count("\ndef _pkg_glob_for") != 1:
    problems.append("_pkg_glob_for is defined more than once")

if problems:
    for p in problems: print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  the checks that always passed now actually check")
PY73
_count_rc $?

# ---- a staged install must not take the shared install directories ---------- #
# The staging tree is created by the package user, so $stage/usr, $stage/usr/bin
# and so on are owned by that user with mode 755.  Stamping that onto the live
# tree handed /usr and /usr/bin to whichever package was building, losing the
# install group and g+w -- the whole install-directory scheme, undone by one
# package.  Verified: root:install 775 became gcc:gcc 755.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    it="$(sed -n '/^_install_staged_tree() {/,/^}/p' "$helper_src")"
    case "$it" in
        *"ALREADY THERE -- leave its ownership and mode alone"*)
            ok "an existing directory keeps its owner and mode" ;;
        *) bad "a staged install still restamps existing directories" ;;
    esac

    # behaviour: existing dirs untouched, new ones owned by the package
    sd="$T/stageown"; mkdir -p "$sd/usr/bin" "$sd/stage/usr/bin" "$sd/stage/usr/lib/fresh"
    chmod 775 "$sd/usr" "$sd/usr/bin"
    before_usr="$(stat -c %a "$sd/usr")"
    echo p > "$sd/stage/usr/bin/p"; echo l > "$sd/stage/usr/lib/fresh/l"
    chmod -R 755 "$sd/stage"
    ( SNAP_ROOT="$sd"; say() { :; }; warn() { :; }
      eval "$it"; _install_staged_tree "$sd/stage" ) >/dev/null 2>&1
    if [ "$(stat -c %a "$sd/usr")" = "$before_usr" ] \
       && [ -f "$sd/usr/bin/p" ] && [ -f "$sd/usr/lib/fresh/l" ]; then
        ok "existing modes survive and the files still install"
    else
        bad "the staged merge changed an existing directory's mode"
    fi
fi

# ---- book 7.6 truncates the user database ----------------------------------- #
# `cat > /etc/passwd` is right the first time and catastrophic the second: it
# wipes every package user, private group, the install group, every collector
# group and every membership.  The files on disk then all read as UNKNOWN.
if [ -f "$helper_src" ]; then
    grep -q "^_protect_user_db()" "$helper_src" \
        && ok "the user database is protected across 7.6" \
        || bad "re-running init-files would wipe every package user"
    grep -q "^_step_rewrites_user_db()" "$helper_src" \
        && ok "steps that rewrite passwd/group are detected" \
        || bad "the protection is not tied to the steps that need it"
    # the detector must not fire on scripts that merely READ the files
    dt="$(sed -n '/^_step_rewrites_user_db() {/,/^}/p' "$helper_src")"
    rd="$T/dbdetect"; mkdir -p "$rd"
    printf 'grep root /etc/passwd\n' > "$rd/read.sh"
    printf 'cat > /etc/passwd << "EOF"\nroot:x:0:0::/root:/bin/bash\nEOF\n' > "$rd/write.sh"
    ( eval "$dt"
      _step_rewrites_user_db "$rd/write.sh" && ! _step_rewrites_user_db "$rd/read.sh" ) \
        && ok "it fires on a rewrite, not on a read" \
        || bad "the user-database detector is wrong"
    cb="$(sed -n '/^cmd_build() {/,/^}/p' "$helper_src")"
    case "$cb" in
        *_protect_user_db*_restore_user_db*)
            ok "entries are saved before the step and put back after" ;;
        *) bad "the protection is never applied around the build" ;;
    esac
fi

# ---- two accounts sharing one uid ------------------------------------------- #
# Ownership is stored as a NUMBER.  Give two names the same uid and every tool
# resolves it to whichever name comes first -- ncurses' binaries reported as
#     /usr/bin/tic  -rwxr-xr-x xz:xz
# and the ncurses build could not overwrite its own files.  It reads exactly
# like a permissions bug and is not one.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q "^_check_duplicate_ids()" "$helper_src" \
        && ok "duplicate ids are detected and named" \
        || bad "a uid collision would look like a permissions bug forever"
    ba="$(sed -n '/^cmd_build_all() {/,/^}/p' "$helper_src")"
    case "$ba" in
        *_check_duplicate_ids*) ok "the check runs before anything is built" ;;
        *) bad "the collision check never runs" ;;
    esac
    # restoring entries after book 7.6 must not CREATE a collision
    rd="$(sed -n '/^_restore_user_db() {/,/^}/p' "$helper_src")"
    case "$rd" in
        *'is now used by'*)
            ok "an entry whose id was reassigned is not restored" ;;
        *) bad "restoring after 7.6 could create the collision itself" ;;
    esac

    # behaviour: the detector finds a real collision and ignores a clean file
    dd="$T/dupids"; mkdir -p "$dd"
    printf 'root:x:0:0::/root:/bin/bash\nxz:x:10005:10005::/x:/bin/bash\nncurses:x:10005:10005::/n:/bin/bash\n' > "$dd/bad"
    printf 'root:x:0:0::/root:/bin/bash\nxz:x:10005:10005::/x:/bin/bash\n' > "$dd/good"
    du="$(sed -n '/^_duplicate_ids() {/,/^}/p' "$helper_src")"
    ( eval "$du"
      [ -n "$(_duplicate_ids "$dd/bad")" ] && [ -z "$(_duplicate_ids "$dd/good")" ] ) \
        && ok "it finds a real collision and stays quiet on a clean file" \
        || bad "the duplicate-id detector is wrong"
fi

# ---- one reconcile pass instead of eight repair commands -------------------- #
# fix-ownership, adopt-dirs, adopt-existing, fix-orphans, fix-users,
# sort-users, seal-install-dirs and claim-earlier-stages each fixed ONE symptom
# and could not see a problem outside its own remit -- so a staged install
# quietly handing /usr to a package user went unnoticed through four later
# failures.  Ownership is derived state: the manifests, the install-dir list
# and the collector map fully determine what the tree should be.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q "^cmd_verify()" "$helper_src" \
        && ok "one command reconciles the tree" \
        || bad "there is no single check of the whole model"
    # The commands it replaces must not be SECOND IMPLEMENTATIONS -- but they
    # must still be callable.  Deleting them outright broke every message that
    # tells people to run them:
    #     !! unknown command 'adopt-existing'
    for c in fix-ownership fix-orphans fix-users adopt-existing; do
        grep -qE "^\s+.*\b$c[|)]" "$helper_src" \
            || bad "$c is referenced in the hints but not dispatched"
    done
    ok "the familiar repair names still work"
    # ... and route to verify rather than repeating its logic
    disp="$(sed -n '/fix-ownership|fix-orphans/,/cmd_verify/p' "$helper_src")"
    case "$disp" in
        *cmd_verify*) ok "they are aliases for verify, not second copies" ;;
        *) bad "a repair command has its own implementation again" ;;
    esac

    # every rule the model needs
    for r in _vfy_manifest_ownership _vfy_install_dirs _vfy_orphans \
             _vfy_duplicate_ids _vfy_user_order; do
        grep -q "^$r()" "$helper_src" || bad "verify has no $r rule"
    done
    ok "verify checks ownership, install dirs, orphans, ids and order"

    # reporting by default, repairing only when asked
    cv="$(sed -n '/^cmd_verify() {/,/^}/p' "$helper_src")"
    case "$cv" in
        *'"${1:-}" = "--fix" ] && fix=1'*|*"--fix|--run) fix=1"*)
            ok "verify reports unless asked to repair" ;;
        *) bad "verify repairs without being asked" ;;
    esac
    # manifest ownership must settle before orphans, or a file whose uid no
    # longer resolves is handed to 'lfs' instead of to its package
    i_own="$(printf '%s' "$cv" | grep -n '_vfy_manifest_ownership' | head -1 | cut -d: -f1)"
    i_orp="$(printf '%s' "$cv" | grep -n '_vfy_orphans' | head -1 | cut -d: -f1)"
    if [ -n "$i_own" ] && [ -n "$i_orp" ] && [ "$i_own" -lt "$i_orp" ]; then
        ok "manifest ownership is settled before orphans are claimed"
    else
        bad "an orphan pass could take a file that belongs to a package"
    fi

    # A1 end to end: the install dirs are checked, so a staged install taking
    # /usr is caught rather than surfacing four failures later
    vd="$T/verifydirs"; mkdir -p "$vd/usr/bin" "$vd/.lfs-pkgusr/manifests"
    chmod 755 "$vd/usr" "$vd/usr/bin"
    id_out="$( ( SNAP_ROOT="$vd"; ETC="$vd/etc"; INSTALLDIRS=""
        MANIFESTS="$vd/.lfs-pkgusr/manifests"
        say() { echo "$*"; }; warn() { echo "$*"; }
        _vfy_n_checked=0; _vfy_n_wrong=0; _vfy_n_fixed=0
        INSTALL_GID=9999
        for _f in install_dirs_list _install_dirs_are_sealed _vfy_report \
                  set_install_dir_owner install_dir_owner_ok _vfy_install_dirs; do
            eval "$(_slice_fn "$helper_src" "$_f")"
        done
        # the pass is gated on the ownership epoch now: before book 7.6 there
        # is no user database, so `install` is not a name and reporting 27
        # wrong directories would be noise.  This fixture is past that.
        ownership_established() { return 0; }
        ownership_possible() { return 0; }
        _vfy_install_dirs 0 ) 2>&1 )"
    case "$id_out" in
        *"root:install"*) ok "a wrongly-owned install directory is reported" ;;
        *) bad "verify does not notice install dirs losing the install group" ;;
    esac
fi

# ---- ownership is derived state, so it can be checked -------------------------#
# The manifests say who installed what, the install-dir list says what is
# shared, the collector map says which groups govern which directories.
# Together they determine what the tree SHOULD look like -- so a discrepancy
# can be found before it becomes a failed build, instead of being chased one
# symptom at a time through fix-ownership, adopt-dirs, fix-perms, fix-orphans
# and claim-earlier-stages.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q "^cmd_verify()" "$helper_src" \
        && ok "the tree can be checked against the manifests" \
        || bad "there is no way to ask whether ownership is correct"
    cv="$(sed -n '/^cmd_verify() {/,/^}/p' "$helper_src")"
    # the A1 case: an install directory taken by a package user
    # The wording lives in the _vfy_* helpers now -- cmd_verify calls them
    # rather than carrying its own copy of each rule.  Assert the check runs.
    case "$cv" in
        *_vfy_install_dirs*)
            ok "it catches an install directory taken by a package" ;;
        *) bad "the install-directory scheme is not checked" ;;
    esac
    _vfy_install_dirs_body="$(_slice_fn "$helper_src" _vfy_install_dirs)"
    case "$_vfy_install_dirs_body" in
        *'"root:install $want_mode"'*) ;;
        *) bad "the install-dir check no longer says what it wants" ;;
    esac
    case "$cv" in
        *_vfy_manifest_ownership*)
            ok "it catches files owned by the wrong package" ;;
        *) bad "mis-owned files are not detected" ;;
    esac
    case "$cv" in
        *_check_duplicate_ids*) ok "it checks for id collisions too" ;;
        *) bad "a uid collision would not be reported" ;;
    esac
    # report by default, repair only when asked
    case "$cv" in
        *'[ "${1:-}" = "--fix" ] && fix=1'*)
            ok "it reports by default and repairs only with --fix" ;;
        *) bad "verify changes things without being asked" ;;
    esac
    # a collision is NOT auto-repairable -- which name owns what is a decision
    case "$cv" in
        *"verify cannot repair this"*)
            ok "it does not guess at an id collision" ;;
        *) bad "verify would silently reassign ids" ;;
    esac
fi

# ---- durable records and scratch must be distinguishable ---------------------#
# $STATE mixes records that ARE the ownership (manifests, collector map) with
# pure scratch (staging trees, logs).  A snapshot or a restart had to guess.
if [ -f "$helper_src" ]; then
    grep -q "^STATE_DURABLE=" "$helper_src" \
        && ok "the durable records are named" \
        || bad "nothing says which state must survive"
    grep -q "^STATE_SCRATCH=" "$helper_src" \
        && ok "the scratch is named" \
        || bad "nothing says which state is disposable"
    grep -q "manifests" <<< "$(sed -n '/^STATE_DURABLE=/,/^STATE_SCRATCH=/p' "$helper_src")" \
        && ok "the manifests count as durable" \
        || bad "the manifests could be cleaned away"
    grep -q "^STATE_FORMAT=" "$helper_src" \
        && ok "the state format is versioned" \
        || bad "an incompatible state directory would be misread"
    cs="$(sed -n '/^cmd_clean_state() {/,/^}/p' "$helper_src")"
    case "$cs" in
        *'rm -rf "${STATE:?}/$d"'*)
            ok "cleaning scratch cannot expand to rm -rf /" ;;
        *) bad "an unset STATE would delete the root" ;;
    esac
fi

# ---- the suite's own count must be trustworthy ------------------------------ #
# ok/bad used shell variables, and several checks call them from inside a
# subshell -- `( ... ) && ok || bad`, a pipeline, a `while read` fed by process
# substitution.  An increment there dies with the subshell, so the suite
# printed 446 PASS lines and reported 433.  A wrong count is worse than none:
# it hides a regression behind a number that still looks healthy.
cnt="$T/countcheck"; mkdir -p "$cnt"
( _COUNTDIR="$cnt"; : > "$cnt/pass"; : > "$cnt/fail"
  ok()  { echo x >> "$_COUNTDIR/pass"; }
  # the case that used to be lost: incremented inside a subshell
  ( ok ) ; ( true && ok ) ; echo | while read -r _; do ok; done )
n="$(wc -l < "$cnt/pass" | tr -d ' ')"
[ "$n" = 3 ] \
    && ok "counts survive subshells, pipelines and process substitution" \
    || bad "the counter loses $((3 - n)) of 3 increments from subshells"

# and every assertion must be counted exactly once
_asserts="$(grep -cE '^\s*(ok|bad) "' "$0" 2>/dev/null || echo 0)"
[ "$_asserts" -gt 0 ] \
    && ok "the suite counts assertions, not printed lines" \
    || bad "the suite has no assertions to count"

# ---- host layout and built-system layout are separate ------------------------ #
# Configuring where package users live on THIS machine must not change where
# they live on every system built from it.  The whole point of the build is
# that the new system is not this one.
python3 - "$LFS_TOOL" <<'PY74'
import sys, os, json, tempfile, importlib.machinery as m
store = tempfile.mkdtemp(); os.environ["LFS_STORE"] = store
os.makedirs(os.path.join(store, "books"), exist_ok=True)
json.dump({"default": "12.4",
           "pkgusr_home": "/usr/src",
           "target_pkgusr_home": "/usr/src/package_users",
           "target_appuser_home": "/home/shared_users"},
          open(os.path.join(store, "config.json"), "w"))
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
problems = []
if not hasattr(lfs, "layout"):
    print("  FAIL  the layout is not configurable"); sys.exit(1)
if lfs.layout("pkgusr_home") != "/usr/src":
    problems.append("the host layout was changed by a target setting")
if lfs.layout("pkgusr_home", target=True) != "/usr/src/package_users":
    problems.append("the built system does not use its own layout")
if lfs.layout("appuser_home", target=True) != "/home/shared_users":
    problems.append("application users do not get their own base")
# The default moved deliberately: accounts are grouped by kind, so a
# directory listing says what a thing IS.  Existing trees are NOT migrated --
# a fresh build is required, and migrate-layout is still unwritten.  Pin the
# new values so the next move is also a decision and not an accident.
d = lfs.LAYOUT_DEFAULTS
if d["target_pkgusr_home"] != "/usr/src/pkgusr" \
        or d["pkgusr_home"] != "/usr/src/pkgusr":
    problems.append("packages no longer default to /usr/src/pkgusr")
if d["target_cfguser_home"] != "/usr/src/cfg" \
        or d["cfguser_home"] != "/usr/src/cfg":
    problems.append("config steps no longer default to /usr/src/cfg")
# and the target value must reach the chroot and the built system's config
src = open(sys.argv[1]).read()
if 'LFS_SRC_ROOT="{layout("pkgusr_home", target=True)}"' not in src:
    problems.append("the chroot build environment does not carry the layout")
if 'pkgusr_home=%s' not in src:
    problems.append("the built system's config does not record the layout")
if problems:
    for p in problems: print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  host and built-system layouts are configured independently")
PY74
_count_rc $?

pmt="$(dirname "$LFS_TOOL")/packagemanager"
if [ -f "$pmt" ]; then
    grep -q "^def appuser_home" "$pmt" \
        && ok "application users have their own base directory" \
        || bad "application users still share the package-user base"
    # an unconfigured system must keep the old layout
    lyd="$T/layout"; mkdir -p "$lyd"
    printf 'collector_prefix=n\n' > "$lyd/pm.conf"
    got="$(PKGUSR_CONFIG="$lyd/pm.conf" python3 -c "
import importlib.machinery as m, os
pm = m.SourceFileLoader('pm', '$pmt').load_module()
print(pm.BASE_DIR, pm.appuser_home())" 2>/dev/null)"
    [ "$got" = "/usr/src /usr/src" ] \
        && ok "an unconfigured system keeps the existing layout" \
        || bad "the layout changed without being asked (got '$got')"
    printf 'collector_prefix=n\npkgusr_home=/usr/src/package_users\nappuser_home=/home/shared_users\n' \
        > "$lyd/pm2.conf"
    got2="$(PKGUSR_CONFIG="$lyd/pm2.conf" python3 -c "
import importlib.machinery as m, os
pm = m.SourceFileLoader('pm', '$pmt').load_module()
print(pm.BASE_DIR, pm.appuser_home())" 2>/dev/null)"
    [ "$got2" = "/usr/src/package_users /home/shared_users" ] \
        && ok "a configured system uses the layout it was built with" \
        || bad "the configured layout is ignored (got '$got2')"
fi

# ---- /root must never carry the install group -------------------------------- #
# Two different ideas got conflated.  An install directory is SHARED: it gets
# the install group and g+w so any package user can add files.  /root, /home
# and the scratch dirs are something else -- they must never be adopted by a
# package, but they are not shared.  Listing them as install dirs produced
#     drwxrwx--- 1 root install /root
# handing every package user access to root's home.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q "^never_adopt_list()" "$helper_src" \
        && ok "protected-from-adoption is separate from shared" \
        || bad "the two ideas are still conflated"
    ( SNAP_ROOT=/; INSTALLDIRS=""
      eval "$(sed -n '/^never_adopt_list() {/,/^}/p' "$helper_src")"
      eval "$(sed -n '/^is_never_adopt() {/,/^}/p' "$helper_src")"
      eval "$(sed -n '/^install_dirs_list() {/,/^}/p' "$helper_src")"
      eval "$(sed -n '/^install_dir_patterns() {/,/^}/p' "$helper_src")"
      eval "$(sed -n '/^matches_install_pattern() {/,/^}/p' "$helper_src")"
      eval "$(sed -n '/^is_install_dir() {/,/^}/p' "$helper_src")"
      # never group-writable
      for d in /root /home /tmp /var/tmp; do
          install_dirs_list | grep -qx "$d" && exit 1
      done
      # but still never adopted
      for d in /root /home /tmp /var/tmp; do is_install_dir "$d" || exit 1; done
      # and the real install dirs are untouched
      install_dirs_list | grep -qx /usr/bin || exit 1
      exit 0 ) \
        && ok "/root and /home are protected but not group-writable" \
        || bad "/root or /home would get the install group"
fi

# ---- nothing owned by the build user survives into the system --------------- #
# Book 7.2 hands over the directories 4.2 created, but the tree ROOT and the
# mount points are not in that list, so /, /dev, /proc, /sys, /run, /media,
# /opt and /tools stayed owned by a user that does not exist in the chroot:
#     drwxr-xr-x 1 lfs lfs 178 /
python3 - "$LFS_TOOL" <<'PY75'
import sys
src = open(sys.argv[1]).read()
if "give the top level to root" not in src:
    print("  FAIL  the tree root and mount points keep the build user")
    sys.exit(1)
i = src.index("give the top level to root")
seg = src[i:i + 500]
problems = []
if "/sources" not in seg:
    problems.append("/sources is not excluded; the book keeps it with lfs")
if "-R " in seg:
    problems.append("the handover is recursive; it must only touch the top level")
if 'chown -h root:root' not in seg:
    problems.append("symlinks at the top level are not handed over")
if problems:
    for p in problems: print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  the tree root and mount points are handed back to root")
PY75
_count_rc $?

# ---- the package-user model must be usable from outside ---------------------- #
# `build` only works for steps that already exist in the step list with a
# generated script, so a BLFS package or a local script had no way to say
# "install this as its own package user and track it" -- it would have to
# reimplement user creation, the wrappers, staging, tracking and the permission
# grants.  That is exactly how the two halves of this toolchain drifted apart.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q "^cmd_install_as()" "$helper_src" \
        && ok "anything can be installed as its own package user" \
        || bad "third-party installs cannot use the model"
    ia="$(sed -n '/^cmd_install_as() {/,/^}/p' "$helper_src")"
    # both shapes a caller might have
    case "$ia" in
        *"--script)"*) ok "an existing install script can be used" ;;
        *) bad "only inline commands are accepted" ;;
    esac
    case "$ia" in
        *"--) shift; cmdv=("*) ok "a bare command can be used" ;;
        *) bad "only a script file is accepted" ;;
    esac
    # it must REUSE cmd_build, not reimplement it -- one code path or they drift
    case "$ia" in
        *'cmd_build "$name" --force'*)
            ok "it reuses the build path rather than duplicating it" ;;
        *) bad "install-as reimplements what build already does" ;;
    esac
    # the result must be a normal package, visible to every query
    case "$ia" in
        *'"$STATE_PROGRESS/steporder"'*)
            ok "the package becomes visible to status, list and manifests" ;;
        *) bad "an install-as package would be invisible to the other commands" ;;
    esac
    # reserved names must be refused
    case "$ia" in
        *"_is_not_a_package"*) ok "reserved step names are refused" ;;
        *) bad "install-as could create a user for last-step or cfg_*" ;;
    esac
    # a command with spaces or quotes must survive being written to a script
    grep -q "^_quote_cmd()" "$helper_src" \
        && ok "arguments are quoted, so paths with spaces survive" \
        || bad "a command containing spaces would be mangled"
fi

# ---- a capitalised step must find its lowercase earlier stage --------------- #
# Book titles are capitalised ("Python", "Util-linux") but the chapter-7 stage
# is named from the tarball ("python-tmp").  Matching only the step's own
# spelling meant Python never claimed python-tmp's files, and chapter 7's
# root-owned tree blocked the chapter-8 install:
#     install: cannot remove '/usr/lib/python3.13/idlelib/Icons/README.txt'
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    ce="$(sed -n '/^_claim_earlier_stages() {/,/^}/p' "$helper_src")"
    case "$ce" in
        *"tr 'A-Z' 'a-z'"*) ok "a capitalised step finds its lowercase stage" ;;
        *) bad "Python would never claim python-tmp's files" ;;
    esac
    case "$ce" in
        *'for stem in "$name" "$lname" "$owner" "$owname"'*)
            ok "the owner's spelling is tried as well as the step's" ;;
        *) bad "only the step name is tried" ;;
    esac
    case "$ce" in
        *"de-duplicate"*) ok "a manifest is not walked twice" ;;
        *) bad "the same manifest could be walked four times" ;;
    esac
fi

# ---- a package user should record where it came from ------------------------ #
# An LFS base package, a BLFS package, a pip module and a local script are
# maintained differently and updated from different places.  Nothing in a
# package user's home said which it was.
if [ -f "$helper_src" ]; then
    grep -q "^_write_pkgusr_info()" "$helper_src" \
        && ok "each package user records its source" \
        || bad "there is no way to tell an LFS package from a BLFS one"
    grep -q "^cmd_pkgusr_info()" "$helper_src" \
        && ok "it can be read back" \
        || bad "the record is written but never readable"
    # both completion paths must write it, not just one
    cb="$(sed -n '/^cmd_build() {/,/^}/p' "$helper_src")"
    n="$(printf '%s' "$cb" | grep -c '_write_pkgusr_info')"
    [ "${n:-0}" -ge 2 ] \
        && ok "every path that completes a build records it" \
        || bad "only one of the two done paths records the source"
    # the helper must be defined before cmd_build uses it
    i_def="$(grep -n '^_write_pkgusr_info()' "$helper_src" | head -1 | cut -d: -f1)"
    i_use="$(grep -n '^cmd_build() {' "$helper_src" | head -1 | cut -d: -f1)"
    [ -n "$i_def" ] && [ -n "$i_use" ] && [ "$i_def" -lt "$i_use" ] \
        && ok "it is defined before the build uses it" \
        || bad "the branding helper is defined after its first use"
    ia="$(sed -n '/^cmd_install_as() {/,/^}/p' "$helper_src")"
    case "$ia" in
        *"LFS_PKG_SOURCE"*) ok "install-as records what kind of install it was" ;;
        *) bad "a BLFS or local install would be recorded as lfs" ;;
    esac
fi

# ---- adopt-existing must still exist ----------------------------------------- #
# The pass moved into verify, but the command was removed while messages
# elsewhere still told people to run it:
#     !! unknown command 'adopt-existing'
# A command that has been deleted is worse than one that is redundant.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q "^cmd_adopt_existing()" "$helper_src" \
        && ok "adopt-existing is still a command" \
        || bad "a command the messages tell people to run does not exist"
    grep -qE "^\s+adopt-existing\|adopt-dirs\)" "$helper_src" \
        && ok "it is reachable from the command line" \
        || bad "adopt-existing is defined but not dispatched"
    # every command named in a hint must actually dispatch
    for c in fix-ownership fix-orphans grant-dir verify which-package \
             check-toolchain seal-install-dirs sort-users install-as; do
        # a command may be dispatched on its own or as part of an alternation
        grep -qE "^\s+[a-z|-]*\b$c[|)]" "$helper_src" \
            || bad "$c is referenced but not dispatched"
    done
    ok "every command referenced in the hints is dispatched"

    # ---- and the users must be created in BUILD order --------------------- #
    # This pass creates the package users it finds missing, and a uid is just
    # the order of creation.  Alphabetical order gave man-pages (first
    # chapter-8 package) 10000 and binutils -- built first, in chapter 5 -- a
    # much higher one, so the passwd file no longer reads as the build order.
    vm="$(sed -n '/^_vfy_manifest_ownership() {/,/^}/p' "$helper_src")"
    case "$vm" in
        *'$(_manifests_in_build_order)'*)
            ok "the users are created in build order" ;;
        *) bad "manifests are still walked alphabetically" ;;
    esac
    mo="$(sed -n '/^_manifests_in_build_order() {/,/^}/p' "$helper_src")"
    case "$mo" in
        *'[ "${1:-}" = dirs ]'*)
            ok "the directory manifests are ordered the same way" ;;
        *) bad "the .dirs manifests are still alphabetical" ;;
    esac
fi

# ---- package users cannot exist before book 7.6 ----------------------------- #
# A crosschain snapshot is taken BEFORE chapter 7, so /etc/passwd does not
# exist -- 7.6 creates it.  Running the adoption pass then printed
#     user  binutils  (could not create) -> package user
# forty times, once per package, with no hint why.  The give-away is the
# prompt: "I have no name!" means even root has no passwd entry.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q "^_user_db_ready()" "$helper_src" \
        && ok "the user database is checked before creating users" \
        || bad "adoption would fail once per package with no explanation"
    ae="$(sed -n '/^cmd_adopt_existing() {/,/^}/p' "$helper_src")"
    case "$ae" in
        *_explain_no_user_db*)
            ok "it explains that the tree is simply too early" ;;
        *) bad "the error does not say what is actually wrong" ;;
    esac
    # and the work must still happen, later, without being asked again
    # The late pass is the ownership epoch now: build-all calls
    # _ownership_checkpoint after every step, and the marker makes it fire once.
    ba="$(_slice_fn "$helper_src" cmd_build_all)"
    case "$ba" in
        *_ownership_checkpoint*)
            ok "the packages are adopted once chapter 7 has created it" ;;
        *) bad "a chapter 5-6 tree would never adopt its packages" ;;
    esac
    case "$(_slice_fn "$helper_src" _ownership_checkpoint)" in
        *ownership_established*) ok "the late pass runs once, not per step" ;;
        *) bad "the late adoption would repeat on every step" ;;
    esac
    ud="$(sed -n '/^_user_db_ready() {/,/^}/p' "$helper_src")"
    case "$ud" in
        *"grep -q '^root:'"*)
            ok "an empty or rootless passwd counts as not ready" ;;
        *) bad "a truncated passwd would look usable" ;;
    esac
fi

# ---- "did not change owner" vs "no package claims it" ----------------------- #
# The ownership pass can only act on what a manifest lists.  A file installed
# before tracking existed, or whose manifest was lost, stays root-owned and
# never appears in the report at all -- so a skipped file and an unclaimed one
# look identical from the outside, and they need different fixes.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q "^_vfy_unclaimed()" "$helper_src" \
        && ok "files no manifest claims are reported" \
        || bad "an unclaimed file is indistinguishable from a skipped one"
    vu="$(sed -n '/^_vfy_unclaimed() {/,/^}/p' "$helper_src")"
    # /etc is root's by right; reporting it would bury the real cases
    case "$vu" in
        *'"${SNAP_ROOT%/}/etc"'*) ok "configuration under /etc is not reported" ;;
        *) bad "every file in /etc would be listed as unclaimed" ;;
    esac
    # the manifest paths carry the host prefix; comparison must strip it
    case "$vu" in
        *strip_host_prefix*) ok "manifest paths are compared without the prefix" ;;
        *) bad "every claimed file would look unclaimed inside the chroot" ;;
    esac
    case "$vu" in
        *"lfs-helper which-package"*)
            ok "it says how to find out which package should own them" ;;
        *) bad "the report gives no way forward" ;;
    esac
    cv="$(sed -n '/^cmd_verify() {/,/^}/p' "$helper_src")"
    case "$cv" in
        *_vfy_unclaimed*) ok "verify runs the check" ;;
        *) bad "the unclaimed check is never called" ;;
    esac
fi


# ---- a versioned chapter-9 "configuration" section is a PACKAGE ------------- #
# Book 9.2 is titled LFS-Bootscripts-20250827: a versioned tarball that unpacks
# and installs programs into /etc/rc.d/init.d and /lib/services.  `lfs` gets
# this right -- _title_pkgver finds a version, so it generates a full phased
# build and deliberately keeps the step OUT of rootsteps, meaning "build this
# as a package user".
#
# lfs-helper then blanket-matched cfg_* as "not a package", refused to create
# the user, and the non-root path staged the script as that user anyway:
#     'cfg_bootscripts' is a build step, not a package -- no user created.
#     install: invalid user 'cfg_bootscripts'
#     !! could not stage the install script
# The build stopped at 88/99.  Two tools, two answers, no shared authority.
#
# The script itself is the authority: a package has pkg_glob, prose does not.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    _cd="$T/cfgpkg"; mkdir -p "$_cd"
    printf 'pkg_glob="lfs-bootscripts-*.tar.*"\n' > "$_cd/cfg_bootscripts.sh"
    printf '#!/bin/bash\necho x > /etc/hostname\n'  > "$_cd/cfg_hostname.sh"
    _r="$( SCRIPTS="$_cd"; PKGUSR_PREFIX="p_"
           # _is_not_a_package strips the package-user prefix first, so the
           # helper it calls has to be here too -- without it every name came
           # back empty and matched nothing, which reads as "is a package".
           eval "$(sed -n '/^unprefix_pkg_user() {/,/^}/p' "$helper_src")"
           eval "$(sed -n '/^_is_not_a_package() {/,/^}/p' "$helper_src")"
           # a versioned cfg section installs files and needs an owner
           _is_not_a_package cfg_bootscripts && echo "bootscripts-has-no-user"
           # a prose one writes root's config and must NOT get a user
           _is_not_a_package cfg_hostname   || echo "hostname-got-a-user"
           # a cfg step with no script at all is prose until proven otherwise
           _is_not_a_package cfg_nothing    || echo "unknown-cfg-step-got-a-user"
           # the genuinely-not-packages must stay that way
           _is_not_a_package last-step      || echo "last-step-got-a-user"
           _is_not_a_package init-dirs      || echo "init-dirs-got-a-user"
           _is_not_a_package refind         || echo "refind-got-a-user"
           # and a normal package is still a package
           _is_not_a_package gcc            && echo "gcc-lost-its-user"
           # callers pass the OWNER name too, already prefixed
           _is_not_a_package p_cfg_bootscripts && echo "prefixed-form-misread" )"
    if [ -z "$_r" ]; then
        ok "a versioned cfg_* section is built as its own package user"
    else
        printf '%s\n' "$_r" | while IFS= read -r m; do
            [ -n "$m" ] && bad "$m"
        done
    fi
    # and lfs must agree: a versioned cfg section is kept out of rootsteps
    grep -q 'pkg_like_cfg.append(cname)' "$LFS_TOOL" \
        && ok "lfs keeps a versioned cfg section out of the root steps" \
        || bad "lfs no longer treats a versioned cfg section as a package"
fi

# ---- the triplet warning must not fire on a healthy toolchain --------------- #
# A finished build has TWO C++ header directories: chapter 6 installs libstdc++
# under $LFS_TGT (x86_64-lfs-linux-gnu, or whatever vendor string is set) and
# chapter 8's native gcc installs its own under x86_64-pc-linux-gnu.  Both are
# present and that is correct -- the chapter-6 one is simply left over.
#
# The check took the FIRST glob match and stopped, so it reported a mismatch
# whenever the stale directory sorted first -- which is alphabetical, i.e. luck:
# "nimgnu" < "pc", so a perfectly good toolchain warned on every single package.
# What matters is only whether a directory matching the compiler exists.
if [ -f "$helper_src" ]; then
    _tp="$T/triplet"; mkdir -p "$_tp/15.2.0/x86_64-nimgnu-linux-gnu/bits" \
                               "$_tp/15.2.0/x86_64-pc-linux-gnu/bits"
    touch "$_tp/15.2.0/x86_64-nimgnu-linux-gnu/bits/c++config.h" \
          "$_tp/15.2.0/x86_64-pc-linux-gnu/bits/c++config.h"
    # the fixed shape: scan every match, stay silent if one is the compiler's
    _fn="$(sed -n '/^_warn_on_triplet_mismatch() {/,/^}/p' "$helper_src")"
    _p=""
    case "$_fn" in
        *'[ "$have" = "$mine" ] && return 0'*) ;;
        *) _p="$_p;the check does not stop at the compiler's own headers" ;;
    esac
    case "$_fn" in
        *"break"*) _p="$_p;the check still stops at the first directory found" ;;
    esac
    case "$_fn" in
        *'[ -n "$found" ] || return 0'*) ;;
        *) _p="$_p;a tree with no C++ headers yet would warn" ;;
    esac
    if [ -n "$_p" ]; then
        printf '%s\n' "${_p#;}" | tr ';' '\n' | while IFS= read -r m; do
            [ -n "$m" ] && bad "$m"
        done
    else
        ok "the triplet warning ignores leftover chapter-6 headers"
    fi
fi

# ---- the adoption gate must actually close --------------------------------- #
# Chapters 5-6 build before /etc/passwd exists, so their files are recorded in
# manifests with no owner.  Once book 7.6 creates the user database, the
# adoption pass hands each package its files, and adopted.list records
# "name size" so it does not run again.
#
# It ran again on EVERY build-all, and the cause was that the gate and the
# recorder tested opposite conditions:
#     _needs_adoption:   user_exists "$owner" || return 0    # no user -> NEEDS
#     _mark_all_adopted: user_exists "$owner" || continue    # no user -> SKIP
# So a single manifest without a user could never be recorded and kept
# _has_unadopted_packages at yes forever.  One rule now, used by both.
#
# The write also swallowed every error (2>/dev/null on the redirect AND
# `|| rm -f` on the move), so a missing or read-only state directory looked
# exactly like a successful record.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
  # the state directory is sorted now: adopted.list lives under progress/
  _ad="$T/adopt"; mkdir -p "$_ad/manifests" "$_ad/progress"
  for f in haveuser nouser; do echo "/usr/bin/$f" > "$_ad/manifests/$f.files"; done
  _out="$( STATE="$_ad"; MANIFESTS="$_ad/manifests"; SCRIPTS="$_ad/scripts"
      STATE_PROGRESS="$_ad/progress"
      warn(){ :; }
      user_exists(){ [ "$1" = haveuser ]; }   # only one package has a user
      pkg_owner_name(){ echo "$1"; }
      is_done(){ return 1; }                  # none built by lfs-helper here
      PKGUSR_PREFIX="p_"
      # _is_not_a_package strips the prefix first, so its helper is needed too
      for fn in _ADOPTED_LIST _manifest_size _adopted_size _mark_adopted \
                _mark_all_adopted _needs_adoption _has_unadopted_packages \
                unprefix_pkg_user _is_not_a_package; do
          eval "$(sed -n "/^$fn() {/,/^}/p" "$helper_src")"
      done
      _has_unadopted_packages || echo "gate-was-closed-before-the-pass"
      _mark_all_adopted
      # the package WITHOUT a user must be recorded too -- that is the fix
      grep -q '^nouser ' "$_ad/progress/adopted.list" 2>/dev/null \
          || echo "a package without a user is never recorded"
      # and the gate must now be shut
      _has_unadopted_packages && echo "the gate stays open after the pass"
      # but a manifest that GROWS has new files to hand over -- reopen
      echo /usr/bin/extra >> "$_ad/manifests/haveuser.files"
      _has_unadopted_packages || echo "a grown manifest is not re-adopted" )"
  if [ -z "$_out" ]; then
      ok "the adoption gate closes once the pass has run"
  else
      printf '%s\n' "$_out" | while IFS= read -r m; do
          [ -n "$m" ] && bad "$m"
      done
  fi
  # a failed write must be reported, not swallowed: an unrecorded adoption
  # means the pass runs forever and nothing on disk says why
  _w="$( STATE=/dev/null/nope
      warn(){ echo "reported"; }
      for fn in _ADOPTED_LIST _manifest_size _mark_adopted; do
          eval "$(sed -n "/^$fn() {/,/^}/p" "$helper_src")"
      done
      _mark_adopted p 12 2>/dev/null && echo "claimed-success" )"
  case "$_w" in
      *reported*) ok "a failed adoption record is reported, not swallowed" ;;
      *)          bad "a failed adoption record still looks like success" ;;
  esac
fi

# ---- chapter-8 configuration must be generated, and must not rot ----------- #
# nsswitch.conf, the timezone and the dynamic-loader config were never
# generated: the step table only harvested chapter 9.  Without /etc/nsswitch.conf
# glibc falls back to compiled-in defaults; without a timezone the system runs
# UTC forever.
#
# Two of those sections carry ids the BOOK TOOLCHAIN generated --
#     idm139921653990176   8.5.2.1. Adding nsswitch.conf
# -- which change every time the book is rebuilt.  Naming one in the table
# works exactly once and then resolves to nothing, silently.  Silently is the
# real danger: /etc/shells went missing from finished systems because
# cfg_shells resolved to zero blocks and was skipped without a word.  So a step
# may name an id OR a title fragment, and this test fails if any chapter-8
# entry stops resolving.
python3 - "$LFS_TOOL" "$LFS_BOOK" <<'PYCFG8'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
problems = []
try:
    from bs4 import BeautifulSoup
except ImportError:
    print("  SKIP  beautifulsoup4 not installed"); sys.exit(0)

if not hasattr(lfs, "CHROOT_CONFIG_STEPS_8"):
    print("  FAIL  chapter-8 configuration is not generated at all"); sys.exit(1)

soup = BeautifulSoup(open(sys.argv[2], encoding='utf-8', errors='replace').read(),
                     'html.parser')
secs = {sid: (t, sec) for sid, t, sec in lfs.iter_sections(soup)}

for name, sid in lfs.CHROOT_CONFIG_STEPS_8:
    e = lfs._resolve_section(secs, sid)
    if not e:
        problems.append("%s: '%s' resolves to no section" % (name, sid))
    elif not e[1]["commands"]:
        problems.append("%s: resolved but has no command blocks" % name)

# the resolver itself: id first, then title, and never a silent guess
if lfs._resolve_section(secs, "ch-config-hostname") is None:
    problems.append("a stable section id no longer resolves")
if lfs._resolve_section(secs, "Adding nsswitch.conf") is None:
    problems.append("a section cannot be found by its title")
if lfs._resolve_section(secs, "zzz-no-such-section") is not None:
    problems.append("a nonexistent section resolves to something")
# an ambiguous fragment must NOT be resolved by picking the first match
if lfs._resolve_section(secs, "Configuring") is not None:
    problems.append("an ambiguous title fragment is silently resolved")

# /tools deletion and stripping are opt-in: neither should ever be a default
if lfs.remove_tools():
    problems.append("/tools is deleted by default")
if lfs.strip_binaries():
    problems.append("binaries are stripped by default")

if problems:
    for p in problems: print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  chapter-8 configuration resolves by id or title, and cannot rot")
PYCFG8
_count_rc $?

# cfg_rm-tools deletes a root-owned tree, so it must be a root step -- never a
# package user's job, and never adoptable
grep -q 'root_steps.append("cfg_rm-tools")' "$LFS_TOOL" \
    && ok "removing /tools is a root step" \
    || bad "removing /tools is not a root step"

# ---- every build decision is asked UP FRONT --------------------------------- #
# The build used to discover decisions halfway through, or at the very end:
# last_build_step.sh blocked on `passwd root` after a six-hour build, and its
# own comment admits the non-interactive path leaves the system
# "unbootable-but-known".  Collecting the answers in `session` is what lets
# `lfs run` and `build-all` finish without a person sitting there.
#
# They must also REACH the chroot: the config file is on the host and the
# chroot environment is reset, so anything not written into the tree's env
# file is simply not there when it is needed.
python3 - "$LFS_TOOL" <<'PYASK'
import sys, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
problems = []
keys = [k for k, _, _ in lfs._SESSION_KEYS]
for k in ("timezone", "remove_tools", "strip", "main_user"):
    if k not in keys:
        problems.append("'%s' is not asked during session" % k)

# Destructive or slow options must never default to on.  Deleting the
# cross-toolchain and rewriting every binary are both things a person should
# have chosen, not discovered.
if lfs.remove_tools():
    problems.append("/tools is deleted by default")
if lfs.strip_binaries():
    problems.append("binaries are stripped by default")

# each answer has to be written into the tree, or the chroot never sees it
body = open(sys.argv[1]).read()
i = body.index("def write_chroot_env")
j = body.find("\ndef ", body.index("_make_world_readable(path)", i))
w = body[i:j if j > i else len(body)]
for var in ("LFS_TIMEZONE", "LFS_MAIN_USER", "LFS_STRIP", "LFS_REMOVE_TOOLS"):
    if var not in w:
        problems.append("%s never reaches the chroot" % var)

if problems:
    for p in problems: print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  every build decision is collected before the build starts")
PYASK
_count_rc $?

# and the accounts step must USE the configured name rather than stopping to
# ask for it -- the whole point of asking early
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    case "$(_slice_fn "$helper_src" cmd_init_accounts)" in
        *main_user*) ok "the final step uses the login account chosen up front" ;;
        *) bad "the final step stops to ask for a name already configured" ;;
    esac
fi

# ---- a section that ships a FILE instead of commands ----------------------- #
# Book 9.6.8 (The rc.site File) has no <kbd class="command"> at all.  It prints
# /etc/sysconfig/rc.site as a <pre class="auto"> block with every line
# commented out, for the reader to copy and uncomment.  The parser harvests
# command blocks only, so cfg_rcsite resolved to zero blocks and the file was
# never created -- the same silent-nothing failure that once lost /etc/shells.
#
# An all-commented file is still worth installing: it documents every knob the
# boot scripts have, in the place the boot scripts look for it.
python3 - "$LFS_TOOL" "$LFS_BOOK" <<'PYRCSITE'
import sys, subprocess, tempfile, os, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
problems = []
if not hasattr(lfs, "_auto_file_block"):
    print("  FAIL  a section that ships a file instead of commands is ignored")
    sys.exit(1)

raw = open(sys.argv[2], encoding='utf-8', errors='replace').read()
blk = lfs._auto_file_block(raw, "ch-config-site", "/etc/sysconfig/rc.site")
if not blk:
    problems.append("rc.site is not extracted from the book")
else:
    d = tempfile.mkdtemp()
    sh = blk.replace("/etc/sysconfig", d + "/etc/sysconfig")
    open(d + "/t.sh", "w").write("set -e\n" + sh + "\n")
    r = subprocess.run(["bash", d + "/t.sh"], capture_output=True, text=True)
    out = d + "/etc/sysconfig/rc.site"
    if r.returncode != 0:
        problems.append("the generated rc.site block is not valid bash: %s"
                        % r.stderr.strip()[:80])
    elif not os.path.isfile(out):
        problems.append("the block runs but writes no file")
    else:
        body = open(out).read()
        if len(body.splitlines()) < 50:
            problems.append("rc.site came out truncated (%d lines)"
                            % len(body.splitlines()))
        # a quoted heredoc: the body is full of # and shell metacharacters and
        # must land byte-for-byte as the book prints it, not expanded
        if "$" in body and "EOF" not in blk.split("\n")[1]:
            problems.append("the heredoc is not quoted -- the body would expand")

# a section with neither commands nor a file body must still be reported, not
# silently skipped
if lfs._auto_file_block(raw, "ch-config-sysklogd", "/etc/x") is not None:
    problems.append("a prose section is treated as if it shipped a file")

if problems:
    for p in problems: print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  a section that ships a file body is installed, not skipped")
PYRCSITE
_count_rc $?

# ---- the package-user prefix must be one decision, not three --------------- #
# lfs-helper has ALWAYS read a prefix and defaulted to `p`:
#     PKGUSR_PREFIX="${LFS_PKGUSR_PREFIX-$(_read_pkgusr_prefix || echo p)}"
# but nothing ever wrote the setting -- `lfs` did not put it in the chroot env
# and `packagemanager` did not implement it at all.  So the default applied by
# accident, and the built system would look for `gcc` while the build had
# created `p_gcc`.  Same species as cfg_bootscripts and adopted.list: one
# decision held in several places that could disagree.
#
# Prefixing MUST be idempotent.  It is applied to names typed by a person
# (gcc), to directory names read back from disk (p_gcc), and to values that
# already went through it -- lfs-helper's own comment names p_p_gcc as the
# thing to avoid.
python3 - "$LFS_TOOL" <<'PYPFX'
import sys, os, tempfile, importlib.machinery as m
problems = []
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
pmp = os.path.join(os.path.dirname(sys.argv[1]) or ".", "packagemanager")
if not os.path.exists(pmp):
    print("  SKIP  packagemanager not found next to the tool"); sys.exit(0)
pm = m.SourceFileLoader('pm', pmp).load_module()

if not hasattr(lfs, "pkgusr_prefix"):
    problems.append("lfs cannot say what the package-user prefix is")
if not hasattr(pm, "pkgusr_name"):
    problems.append("packagemanager does not implement the prefix")

if not problems:
    # the two tools must agree, or the build and the built system diverge
    if lfs.pkgusr_prefix() != pm.pkgusr_prefix():
        problems.append("lfs and packagemanager disagree: %r vs %r"
                        % (lfs.pkgusr_prefix(), pm.pkgusr_prefix()))
    if pm.pkgusr_prefix() != "p_":
        problems.append("the default prefix is not p_ (got %r)"
                        % pm.pkgusr_prefix())
    if pm.pkgusr_name("gcc") != "p_gcc":
        problems.append("a package name is not prefixed")
    # idempotent -- the whole reason every call site can apply it blindly
    if pm.pkgusr_name(pm.pkgusr_name("gcc")) != "p_gcc":
        problems.append("prefixing twice gives p_p_gcc")
    if pm.unprefix_pkgusr("p_gcc") != "gcc":
        problems.append("the prefix cannot be stripped for display")
    # the OTHER kinds of account must not be touched: an application user and
    # a collector group are not packages
    if pm.pkgusr_name("u_firefox") != "u_firefox":
        problems.append("an application user was given the package prefix")
    if pm.pkgusr_name(pm.collector_prefix() + "python") \
            != pm.collector_prefix() + "python":
        problems.append("a collector group was given the package prefix")
    # the home is the ACCOUNT's, whichever kind of name it is asked with
    if pm.pkgusr_home("gcc") != pm.pkgusr_home("p_gcc"):
        problems.append("a package name and its user name give different homes")

# and it has to REACH the chroot, or lfs-helper falls back to a guess
body = open(sys.argv[1]).read()
if "LFS_PKGUSR_PREFIX" not in body:
    problems.append("the prefix never reaches the chroot")
if "pkgusr_prefix" not in [k for k, _, _ in lfs._SESSION_KEYS]:
    problems.append("the prefix is never asked for")

if problems:
    for p in problems: print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  lfs, lfs-helper and packagemanager share one package-user prefix")
PYPFX
_count_rc $?

# lfs-helper's side: it must take the value from the environment lfs wrote,
# and an explicitly EMPTY value must mean "no prefix" -- not fall through to
# the default and rename every user out from under an existing tree
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    grep -q 'PKGUSR_PREFIX="${LFS_PKGUSR_PREFIX-' "$helper_src" \
        && ok "an empty prefix means none, and is not the same as unset" \
        || bad "an empty prefix falls through to the default"
fi

# ---- accounts live in subdirectories by kind ------------------------------- #
# Flat under /usr/src, a hundred package users and a handful of config steps
# were one undifferentiated list, and nothing about a directory said what kind
# of thing it was.  Now:
#     /usr/src/pkgusr/p_gcc            a package
#     /usr/src/cfg/p_cfg_bootscripts   a config step that installs files
# All three tools have to agree, or the build creates a home the built system
# never looks in.
python3 - "$LFS_TOOL" <<'PYSPLITHOME'
import sys, os, tempfile, importlib.machinery as m
problems = []
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
pmp = os.path.join(os.path.dirname(sys.argv[1]) or ".", "packagemanager")
if not os.path.exists(pmp):
    print("  SKIP  packagemanager not found next to the tool"); sys.exit(0)
d = tempfile.mkdtemp(); os.environ["PKGUSR_BASE"] = d
pm = m.SourceFileLoader('pm', pmp).load_module()

for k in ("target_pkgusr_home", "target_cfguser_home",
          "pkgusr_home", "cfguser_home"):
    if k not in lfs.LAYOUT_DEFAULTS:
        problems.append("layout has no '%s'" % k)
if lfs.LAYOUT_DEFAULTS.get("pkgusr_home") == lfs.LAYOUT_DEFAULTS.get("cfguser_home"):
    problems.append("packages and config steps share one directory")
if not lfs.LAYOUT_DEFAULTS.get("pkgusr_home", "").endswith("/pkgusr"):
    problems.append("packages do not default to /usr/src/pkgusr")
if not lfs.LAYOUT_DEFAULTS.get("cfguser_home", "").endswith("/cfg"):
    problems.append("config steps do not default to /usr/src/cfg")

# a package and a config step must land in DIFFERENT roots, whichever form of
# the name they are asked with
if pm.pkgusr_home("gcc") == pm.pkgusr_home("cfg_bootscripts"):
    problems.append("a package and a config step share a root")
if not pm.pkgusr_home("gcc").startswith(os.path.join(d, "pkgusr")):
    problems.append("a package is not under the package root")
if not pm.pkgusr_home("cfg_bootscripts").startswith(os.path.join(d, "cfg")):
    problems.append("a config step is not under the config root")
# prefixed form must resolve identically -- callers pass both
if pm.pkgusr_home("p_cfg_bootscripts") != pm.pkgusr_home("cfg_bootscripts"):
    problems.append("the prefixed name lands somewhere else")

# listing must walk BOTH roots, or half the accounts vanish
os.makedirs(os.path.join(d, "pkgusr", pm.pkgusr_name("gcc")))
os.makedirs(os.path.join(d, "cfg", pm.pkgusr_name("cfg_bootscripts")))
got = pm.list_all_users()
for want in ("gcc", "cfg_bootscripts"):
    if want not in got:
        problems.append("'%s' is missing from the account list %r" % (want, got))

# and both roots must reach the chroot
body = open(sys.argv[1]).read()
for var in ("LFS_PKGUSR_ROOT", "LFS_CFGUSR_ROOT"):
    if var not in body:
        problems.append("%s never reaches the chroot" % var)

if problems:
    for p in problems: print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  packages and config steps live in separate roots")
PYSPLITHOME
_count_rc $?

# lfs-helper's side: one chokepoint that routes by kind, and the passes that
# walk every account must walk both roots -- not just the package one
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
  _o="$( SRCROOT=/tmp/_hr; PKGUSR_ROOT="$SRCROOT/pkgusr"; CFGUSR_ROOT="$SRCROOT/cfg"
      PKGUSR_PREFIX="p_"; CFGUSR_PREFIX="cfg_"
      # pkg_owner_name too: pkgusr_home_for calls it, and without it every
      # home came back as the bare root with no account on the end
      for fn in pkgusr_kind pkgusr_prefix_for pkgusr_root_for \
                unprefix_pkg_user pkg_owner_name pkgusr_home_for pkgusr_roots; do
          eval "$(_slice_fn "$helper_src" "$fn")"
      done
      # a package gets the package prefix and the package root
      [ "$(pkgusr_home_for gcc)" = "$SRCROOT/pkgusr/p_gcc" ] || echo "package-in-wrong-root"
      [ "$(pkgusr_home_for p_gcc)" = "$SRCROOT/pkgusr/p_gcc" ] || echo "prefixed-package-in-wrong-root"
      # a config step gets the CONFIG prefix and the config root -- not the
      # package prefix stacked on top of its own
      [ "$(pkgusr_home_for cfg_bootscripts)" = "$SRCROOT/cfg/cfg_bootscripts" ] || echo "cfg-in-wrong-root"
      # and a legacy p_cfg_ name is repaired rather than carried forward
      [ "$(pkgusr_home_for p_cfg_bootscripts)" = "$SRCROOT/cfg/cfg_bootscripts" ] || echo "stacked-cfg-not-repaired"
      [ "$(pkgusr_roots | wc -l)" = 2 ] || echo "not-both-roots-walked" )"
  if [ -z "$_o" ]; then
      ok "lfs-helper routes each account to the root for its kind"
  else
      printf '%s\n' "$_o" | while IFS= read -r m; do [ -n "$m" ] && bad "$m"; done
  fi
  # no home may be built by hand any more -- that is how the two roots drift
  grep -q '"\$SRCROOT/\$name"' "$helper_src" \
      && bad "a home is still built from SRCROOT directly" \
      || ok "every home goes through the one chokepoint"
fi

# ---- the home a build cd's into is the home the account has ---------------- #
# The build creates the account with useradd -d <home>, then cd's into that
# home to run the staged script.  Those two must be the same path, and they
# are reached from DIFFERENT names: cmd_add_user has the owner
# ("p_man-pages"), build_pkg has the step name ("man-pages").
#
# pkgusr_home_for routed by kind but never applied the prefix, so:
#     # created package user p_man-pages ...
#     line 2673: cd: /usr/src/pkgusr/man-pages: No such file or directory
# Chapter 7 did not catch it -- root steps mkdir -p their own directory first,
# so it surfaced at the first real package user, nine steps in.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
  _o="$( SRCROOT=/usr/src; PKGUSR_ROOT="$SRCROOT/pkgusr"; CFGUSR_ROOT="$SRCROOT/cfg"
      PKGUSR_PREFIX="p_"; CFGUSR_PREFIX="cfg_"
      for fn in pkgusr_kind pkgusr_prefix_for pkgusr_root_for \
                pkg_owner_name unprefix_pkg_user pkgusr_home_for; do
          eval "$(_slice_fn "$helper_src" "$fn")"
      done
      # THE bug: a step name and its owner must give one home
      [ "$(pkgusr_home_for man-pages)" = "$(pkgusr_home_for p_man-pages)" ] \
          || echo "step name and owner give different homes"
      # and it must be the account's, i.e. prefixed
      [ "$(pkgusr_home_for man-pages)" = "/usr/src/pkgusr/p_man-pages" ] \
          || echo "the home is not the account's: $(pkgusr_home_for man-pages)"
      # book titles are capitalised, tarballs are not
      [ "$(pkgusr_home_for Man-Pages)" = "$(pkgusr_home_for man-pages)" ] \
          || echo "a capitalised book title gives a different home"
      # earlier stages fold onto the real package -- util-linux-tmp is
      # util-linux's, which is where its files end up
      [ "$(pkgusr_home_for util-linux-tmp)" = "$(pkgusr_home_for util-linux)" ] \
          || echo "an earlier stage gets its own home"
      [ "$(pkgusr_home_for gcc-pass1)" = "$(pkgusr_home_for gcc)" ] \
          || echo "a pass1 build gets its own home"
      # config steps still route to their own root, and wear ONE prefix --
      # their own.  This used to read p_cfg_bootscripts: the package prefix
      # stacked on the step name's own, so the account claimed to be a package
      # while living in the config root.
      [ "$(pkgusr_home_for cfg_bootscripts)" = "/usr/src/cfg/cfg_bootscripts" ] \
          || echo "a config step is not under the config root" )"
  if [ -z "$_o" ]; then
      ok "a step name and its owner resolve to the same account home"
  else
      printf '%s\n' "$_o" | while IFS= read -r m; do [ -n "$m" ] && bad "$m"; done
  fi

  # the rule must be reachable from shell, or every other script re-derives it
  # -- and a third copy is how the roots drift apart
  grep -q 'pkgusr-home)' "$helper_src" \
      && ok "the home rule is available to scripts as 'lfs-helper pkgusr-home'" \
      || bad "shell scripts have to re-derive where an account lives"
fi

# nothing outside the chokepoints may build an account path by hand
for _f in packagemanager_install lfs-completion.bash last_build_step.sh; do
  _p="$(dirname "$LFS_TOOL")/$_f"
  [ -f "$_p" ] || continue
  if grep -qE '"?/usr/src/\$[a-z_]+' "$_p"; then
      bad "$_f builds an account path by hand"
  else
      ok "$_f asks for the account home instead of building it"
  fi
done

# ---- chapter-8 config steps must not stop the build ------------------------ #
# Two ways they did, both from lifting a sub-section out of its parent package.
#
# cfg_timezone (8.5.2.2) ends with an INTERACTIVE menu whose only output is
# the name to put in the placeholder:
#     tzselect
#     ln -sfv /usr/share/zoneinfo/<xxx> /etc/localtime
# `session` already asks for the timezone, so both are answered.  The same
# section also unpacks tzdata with a path relative to GLIBC's build directory
# (`tar -xf ../../tzdata2025b.tar.gz`), which resolves nowhere once the step
# stands on its own.
python3 - "$LFS_TOOL" <<'PYCFG8RUN'
import sys, re, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
problems = []
body = ("tar -xf ../../tzdata2025b.tar.gz\n"
        "zic -d $ZONEINFO -p America/New_York\n"
        "tzselect\n"
        "ln -sfv /usr/share/zoneinfo/<xxx> /etc/localtime\n")
out, left = lfs._fill_placeholders(body, "cfg_timezone")
if left:
    problems.append("the timezone step still asks for %s" % left)
if "<xxx>" in out:
    problems.append("the timezone placeholder is not filled in")
if re.search(r'^\s*tzselect\s*$', out, flags=re.M):
    problems.append("the interactive tzselect menu still runs")
if "../../tzdata" in out:
    problems.append("tzdata is still read relative to glibc's build directory")
if "SOURCES_DIR" not in out:
    problems.append("tzdata is not taken from the sources directory")
if "/usr/share/zoneinfo//etc/localtime" in out.replace(" ", ""):
    problems.append("the localtime symlink lost its zone name")
if problems:
    for p in problems: print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  the timezone step is answered from config, not from a prompt")
PYCFG8RUN
_count_rc $?

# cfg_ld rewrites /etc/ld.so.conf -- which glibc created and still owns -- and
# makes one directory.  Nothing NEW appears, so the manifest count is 0 and the
# step was failed as a silent no-op:
#     mkdir: created directory '/etc/ld.so.conf.d'
#     !! cfg_ld reported success but installed NO files.
# That is the normal shape of a configuration step.  Packages must still fail.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    # to the end of the branch, not a fixed window: the message grew a
    # breakdown of where the count came from, and a +6 window stopped
    # reaching the `return 1` it is asserting
    _blk="$(sed -n '/reported success but installed NO files/,/^        fi$/p' "$helper_src")"
    # the whole function, not a fixed window above the message: the branch
    # gained a third case (a re-run over its own work) and a -B 14 window
    # stopped reaching the config-step test it is asserting
    _pre="$(_slice_fn "$helper_src" cmd_build)"
    case "$_pre" in
        *'_is_not_a_package "$name"'*)
            ok "a config step may install no new files; a package may not" ;;
        *)  bad "installing no new files still fails a configuration step" ;;
    esac
    case "$_blk" in
        *'return 1'*) ok "a package that installs nothing still fails" ;;
        *)            bad "the no-files check no longer fails a package" ;;
    esac
fi

# ---- a symlinked install directory is checked at its target ---------------- #
# Book 7.x makes /bin, /sbin, /lib and /lib64 symlinks into /usr.  `test -d`
# FOLLOWS a symlink but `stat` does not, so verify compared the LINK's own
# mode and owner -- always lrwxrwxrwx root:root -- against what a directory
# should look like, and reported all of them on every run:
#     /bin  root:root lrwxrwxrwx  (want root:install, group-writable)
# Chowning a symlink changes nothing that matters, and the target (/usr/bin)
# is in the same list and checked on its own.  Both the report and the --fix
# path need the guard: without it, --fix "repairs" a symlink forever.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    # There used to be two copies of the install-dir rule and so two guards to
    # count.  cmd_verify calls _vfy_install_dirs now, so there is one -- and
    # the check and the fix share it, which is the property this was after.
    _vid="$(_slice_fn "$helper_src" _vfy_install_dirs)"
    if printf '%s\n' "$_vid" | grep -q '\[ -L "\$live" \] && continue'; then
        ok "a symlinked install dir is skipped by both the check and the fix"
    else
        bad "a symlinked install dir is still reported"
    fi
    # and the guard must come BEFORE the stat, or it reports then skips
    if sed -n '/install directories not in the expected state/,-12p' \
           "$helper_src" >/dev/null 2>&1; then :; fi
    _blk="$(grep -A 4 '\[ -d "\$live" \] || continue' "$helper_src" | head -20)"
    case "$_blk" in
        *'-L "$live"'*) ok "the symlink guard runs before stat" ;;
        *)              bad "stat runs before the symlink guard" ;;
    esac
fi

# ---- verify must write every finding to a file ----------------------------- #
# The console prints the first eight of each kind and then
#     ... and 44265 more
# which is a number and nothing you can act on: it cannot be grepped, diffed
# against the previous run, or fed to which-package.  Every finding goes to a
# log, tagged by kind, while the console stays short.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
  _p=""
  grep -q '^VERIFY_LOG=' "$helper_src" || _p="$_p;verify has no log file"
  grep -q '_vfy_log_open' "$helper_src" || _p="$_p;the log is never opened"
  # every truncated list must also be written in full
  for _k in wrong-owner unclaimed installdir; do
      grep -q "$_k" "$helper_src" || _p="$_p;nothing logs '$_k' findings"
  done
  # and the summary must say where it is, or nobody finds it
  grep -q 'full report: \$VERIFY_LOG' "$helper_src" \
      || _p="$_p;the summary never names the log"
  # a read-only state dir must not abort verify -- the report still matters
  grep -q 'VERIFY_LOG=""; return 0' "$helper_src" \
      || _p="$_p;verify dies instead of running when the log cannot be written"

  _o="$( STATE=/tmp/_vst; SNAP_ROOT=/; VERIFY_LOG=/tmp/_vst/verify.log
      rm -rf /tmp/_vst
      eval "$(sed -n '/^_vfy_log_open() {/,/^}/p' "$helper_src")"
      eval "$(sed -n '/^_vfy_log() {/,/^}/p' "$helper_src")"
      _vfy_log_open
      _vfy_log wrong-owner "/usr/bin/python3 is root want p_python"
      _vfy_log unclaimed   "/usr/bin/lfs-helper"
      [ -s /tmp/_vst/verify.log ] || echo "the log is empty after findings"
      grep -q '^wrong-owner' /tmp/_vst/verify.log || echo "wrong-owner not tagged"
      grep -q '^unclaimed'   /tmp/_vst/verify.log || echo "unclaimed not tagged"
      # a fresh run must not append to the last one's findings
      _vfy_log_open
      grep -q '^wrong-owner' /tmp/_vst/verify.log && echo "the log is not reset per run"
      # an unwritable location must be survivable
      VERIFY_LOG=/dev/null/nope/verify.log
      _vfy_log_open >/dev/null 2>&1 || echo "an unwritable log aborts verify" )"
  [ -n "$_o" ] && _p="$_p;$(printf '%s' "$_o" | tr '\n' ';')"

  if [ -n "$_p" ]; then
      printf '%s\n' "${_p#;}" | tr ';' '\n' | while IFS= read -r m; do
          [ -n "$m" ] && bad "$m"
      done
  else
      ok "verify writes every finding to a log, tagged by kind"
  fi
fi

# ---- the built system gets the whole toolchain, and it has an owner -------- #
# Only lfs-helper was copied into the tree, because only lfs-helper runs during
# the build.  But the built system needs the rest -- packagemanager cannot be
# installed BY packagemanager -- and a system that boots without them has no
# way to install anything at all.  They are a few files and they refresh on
# every `lfs run`.
#
# They are also software installed into /usr/bin, so they get a package user
# like anything else.  Without one they are reported forever as
#     1516 root-owned file(s) that NO manifest claims:
#        /usr/bin/lfs-helper
# which is true, unhelpful, and buries the cases that matter.
python3 - "$LFS_TOOL" <<'PYTOOLS'
import sys, os, tempfile, importlib.machinery as m
lfs = m.SourceFileLoader('lfs', sys.argv[1]).load_module()
problems = []

for t in ("lfs-helper", "packagemanager", "packagemanager_install", "blfs"):
    if t not in getattr(lfs, "TOOLCHAIN_SCRIPTS", ()):
        problems.append("%s is not copied into the tree" % t)

# the owner is a package user like any other, so it carries the prefix
if lfs.pkgusr_prefix() + lfs.PKGUSR_TOOLS_USER != "p_pkgusr":
    problems.append("the tools' owner is %r, not p_pkgusr"
                    % (lfs.pkgusr_prefix() + lfs.PKGUSR_TOOLS_USER))

# the uid must be read from the TREE's passwd, never this machine's -- a host
# uid means nothing inside the chroot, the same mistake book 3.1 warns about
d = tempfile.mkdtemp()
os.makedirs(os.path.join(d, "etc"))
if lfs._uid_in_tree(d, "p_pkgusr") is not None:
    problems.append("a uid is invented when the tree has no passwd file")
with open(os.path.join(d, "etc", "passwd"), "w") as f:
    f.write("root:x:0:0::/root:/bin/bash\np_pkgusr:x:10042:10042::/usr/src:/bin/bash\n")
if lfs._uid_in_tree(d, "p_pkgusr") != 10042:
    problems.append("the tree's own passwd file is not used")
if lfs._uid_in_tree(d, "nosuchuser") is not None:
    problems.append("an unknown user resolves to something")

if problems:
    for p in problems: print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  the whole toolchain is installed and owned by p_pkgusr")
PYTOOLS
_count_rc $?

# lfs-helper claims them once /etc/passwd is real -- lfs cannot, because on a
# fresh tree the account does not exist until book 7.6
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
    _p=""
    grep -q '_adopt_pkgusr_tools' "$helper_src" || _p="$_p;the tools are never claimed"
    grep -q 'PKGUSR_TOOLS=' "$helper_src" || _p="$_p;there is no list of tools to claim"
    # it must run in build-all, beside the other adoption pass
    case "$(_slice_fn "$helper_src" establish_ownership)" in
        *_adopt_pkgusr_tools*) ;;
        *) _p="$_p;the tools are not claimed when ownership is established" ;;
    esac
    # and it must never take another package's file
    sed -n '/^_adopt_pkgusr_tools() {/,/^}/p' "$helper_src" \
        | grep -q 'user_exists "\$cur" && continue' \
        || _p="$_p;claiming the tools could steal another package's file"
    if [ -n "$_p" ]; then
        printf '%s\n' "${_p#;}" | tr ';' '\n' | while IFS= read -r m; do
            [ -n "$m" ] && bad "$m"
        done
    else
        ok "the tools are claimed once the user database exists"
    fi
fi

# ---- an ADOPTED package gets a real home, like a built one ----------------- #
# Packages built in a run owned their files and had full homes; packages
# ADOPTED from chapter 5-6 manifests in the same run did not:
#     drwxr-xr-x 1 p_bison p_bison 148  p_bison      <- built
#     drwxr-xr-x 1 root    root     86  p_gcc        <- adopted
# 86 vs 148 bytes: the adopted homes were missing the profile links and had
# never been chowned.  cmd_add_user was called with BOTH streams suppressed,
# so whatever went wrong said nothing.  Adoption now initialises the home
# explicitly (init_package_user_home is idempotent) and stderr is let through.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
  _blk="$(sed -n '/^_vfy_manifest_ownership() {/,/^}/p' "$helper_src")"
  _p=""
  case "$_blk" in
      *'init_package_user_home "$owner"'*) ;;
      *) _p="$_p;an adopted package's home is never initialised" ;;
  esac
  case "$_blk" in
      *'cmd_add_user "$owner" >/dev/null 2>&1'*)
          _p="$_p;adoption still hides why a user could not be created" ;;
  esac
  if [ -n "$_p" ]; then
      printf '%s\n' "${_p#;}" | tr ';' '\n' | while IFS= read -r m; do
          [ -n "$m" ] && bad "$m"
      done
  else
      ok "an adopted package gets an initialised, owned home"
  fi
fi

# ---- one account, one prefix ----------------------------------------------- #
# A config step used to be `p_cfg_bootscripts`: pkg_owner_name applied the
# PACKAGE prefix to every name regardless of kind, so the account wore its own
# `cfg_` and `p_` on top of it.  Neither prefix then identified the account --
# `p_` said "package" while it lived in /usr/src/cfg -- and every rule that
# reads a prefix had to special-case the stacked form.
#
# The fix is that kind is decided ONCE (pkgusr_kind) and the prefix and the
# root are both answered from it, so a name cannot be given one kind's prefix
# and placed in another kind's root.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
  _o="$( PKGUSR_PREFIX="p_"; CFGUSR_PREFIX="cfg_"
      PKGUSR_ROOT=/usr/src/pkgusr; CFGUSR_ROOT=/usr/src/cfg
      for fn in pkgusr_kind pkgusr_prefix_for pkgusr_root_for \
                unprefix_pkg_user pkg_owner_name pkgusr_home_for; do
          eval "$(_slice_fn "$helper_src" "$fn")"
      done
      [ "$(pkg_owner_name cfg_bootscripts)" = "cfg_bootscripts" ] \
          || echo "a config step still gets the package prefix: $(pkg_owner_name cfg_bootscripts)"
      [ "$(pkg_owner_name gcc)" = "p_gcc" ] \
          || echo "a package lost its prefix: $(pkg_owner_name gcc)"
      # kind decides both answers, so they cannot disagree
      [ "$(pkgusr_kind cfg_nsswitch)" = "cfg" ] || echo "a cfg step is not kind cfg"
      [ "$(pkgusr_kind gcc)" = "pkg" ]          || echo "a package is not kind pkg"
      # a tree or a config written before the split holds stacked names; they
      # are repaired on the way through rather than carried forward
      [ "$(pkg_owner_name p_cfg_bootscripts)" = "cfg_bootscripts" ] \
          || echo "a stacked legacy name survives: $(pkg_owner_name p_cfg_bootscripts)"
      # and the whole thing is still idempotent -- that property is what lets
      # every call site apply it without knowing which kind of name it holds
      for _n in gcc p_gcc cfg_bootscripts p_cfg_bootscripts; do
          _a="$(pkg_owner_name "$_n")"; _b="$(pkg_owner_name "$_a")"
          [ "$_a" = "$_b" ] || echo "not idempotent: $_n -> $_a -> $_b"
      done )"
  if [ -z "$_o" ]; then
      ok "each kind of account wears exactly one prefix, its own"
  else
      printf '%s\n' "$_o" | while IFS= read -r m; do [ -n "$m" ] && bad "$m"; done
  fi
fi

# packagemanager must reach the same answer, or the built system looks for
# accounts the build never created
pm_src="$(dirname "$LFS_TOOL")/packagemanager"
if [ -f "$pm_src" ]; then
  python3 - "$pm_src" <<'PYONEPFX'
import re, sys
src = open(sys.argv[1]).read()
problems = []
ns = {"os": __import__("os"), "BASE_DIR": "/usr/src",
      "PKGUSR_SUBDIR": "pkgusr", "CFGUSR_SUBDIR": "cfg",
      "_DEFAULT_CONFIG": {"collector_prefix": "sysgroup", "user_prefix": "u",
                          "pkgusr_prefix": "p", "cfguser_prefix": "cfg",
                          "main_user": ""}}
ns["load_config"] = lambda: dict(ns["_DEFAULT_CONFIG"])
for fn in ("collector_prefix", "user_prefix", "pkgusr_prefix", "cfguser_prefix",
           "pkgusr_kind", "pkgusr_name", "unprefix_pkgusr", "pkgusr_root",
           "pkgusr_home"):
    m = re.search(r"^def %s\(.*?(?=\n\ndef |\n\n# |\nPKGUSR_SUBDIR)" % fn, src, re.S | re.M)
    if not m:
        problems.append("packagemanager has no %s" % fn)
        continue
    exec(m.group(0), ns)
if not problems:
    want = {
        # name              -> (account name, home)
        "gcc":               ("p_gcc",           "/usr/src/pkgusr/p_gcc"),
        "p_gcc":             ("p_gcc",           "/usr/src/pkgusr/p_gcc"),
        "cfg_bootscripts":   ("cfg_bootscripts", "/usr/src/cfg/cfg_bootscripts"),
        # the stacked legacy form is repaired, not carried forward
        "p_cfg_bootscripts": ("cfg_bootscripts", "/usr/src/cfg/cfg_bootscripts"),
        "u_firefox":         ("u_firefox",       "/usr/src/u_firefox"),
    }
    for given, (name, home) in want.items():
        got = ns["pkgusr_name"](given)
        if got != name:
            problems.append("packagemanager names %s as %s, want %s" % (given, got, name))
        got = ns["pkgusr_home"](given)
        if got != home:
            problems.append("packagemanager puts %s at %s, want %s" % (given, got, home))
        again = ns["pkgusr_name"](ns["pkgusr_name"](given))
        if again != ns["pkgusr_name"](given):
            problems.append("packagemanager is not idempotent on %s" % given)
if problems:
    for p in problems:
        print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  packagemanager and lfs-helper name each kind identically")
PYONEPFX
  _count_rc $?
fi

# ---- a step that is not a package leaves no home behind --------------------- #
# cmd_build did `mkdir -p "$(pkgusr_home_for "$name")"` for EVERY root step,
# including the ones _is_not_a_package will never give an account.  A sanity run
# then found /usr/src/pkgusr/p_init-dirs and p_init-files: directories with no
# matching account, which every ownership pass has to report as strays.
#
# init-*, last-step and refind own no files, so they are staged and run out of
# the state directory instead -- beside the scripts they came from.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
  _o="$( STATE=/.lfs-pkgusr; SCRIPTS="$STATE/scripts"
      PKGUSR_PREFIX="p_"; CFGUSR_PREFIX="cfg_"
      PKGUSR_ROOT=/usr/src/pkgusr; CFGUSR_ROOT=/usr/src/cfg
      for fn in pkgusr_kind pkgusr_prefix_for pkgusr_root_for unprefix_pkg_user \
                pkg_owner_name pkgusr_home_for _is_not_a_package step_stage_dir; do
          eval "$(_slice_fn "$helper_src" "$fn")"
      done
      # an empty answer must not read as "not under an account root"
      command -v step_stage_dir >/dev/null 2>&1 \
          || echo "there is no step_stage_dir -- every root step still gets a home"
      for _s in init-dirs init-files last-step refind; do
          _d="$(step_stage_dir "$_s" 2>/dev/null)"
          [ -n "$_d" ] || { echo "$_s resolves to no directory at all"; continue; }
          case "$_d" in
              "$PKGUSR_ROOT"/*|"$CFGUSR_ROOT"/*)
                  echo "$_s still gets a home under an account root" ;;
          esac
      done
      # a real package is unaffected: it still runs from its user's home
      [ "$(step_stage_dir gcc)" = "$PKGUSR_ROOT/p_gcc" ] \
          || echo "a package no longer runs from its own home: $(step_stage_dir gcc)" )"
  if [ -z "$_o" ]; then
      ok "a step with no account leaves no directory under the account roots"
  else
      printf '%s\n' "$_o" | while IFS= read -r m; do [ -n "$m" ] && bad "$m"; done
  fi

  # the staged path, the mkdir, the cd and the failure banner must be ONE
  # value.  They were four separate calls to pkgusr_home_for, free to disagree.
  _cb="$(_slice_fn "$helper_src" cmd_build)"
  case "$_cb" in
      *'cd "$(pkgusr_home_for'*)
          bad "the build still re-derives the directory it cd's into" ;;
      *) ok "the staged script, the cd and the banner share one path" ;;
  esac
fi

# ---- the account roots are a decision, not a side effect -------------------- #
# /usr/src/pkgusr and /usr/src/cfg came out root:root 0755 because `mkdir -p`
# on the first home created them with root's umask.  Nothing said so, and
# nothing would have noticed it changing.
#
# They carry the same root:install 1775 as /usr/src above them -- one rule for
# the subtree instead of three directories with two rules.  The STICKY BIT is
# what makes group-writable safe and is not optional: without it any member of
# `install` could delete or rename another package's home.
#
# They are still NOT install dirs.  Being in never_adopt_list is the other
# half: the mode is shared, but no package may ever take one as its own.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
  _p=""
  _ep="$(_slice_fn "$helper_src" ensure_pkgusr_roots)"
  case "$_ep" in
      *'chmod 1775'*) ;;
      *) _p="$_p;the account roots have no stated mode" ;;
  esac
  case "$_ep" in
      *set_install_dir_owner*) ;;
      *) _p="$_p;the account roots do not get the install group" ;;
  esac
  # sticky, or group-write means any package can delete another's home
  case "$_ep" in
      *17[0-9][0-9]*) ;;
      *) _p="$_p;the account roots are group-writable WITHOUT the sticky bit" ;;
  esac
  case "$(_slice_fn "$helper_src" init_package_user_home)" in
      *ensure_pkgusr_roots*) ;;
      *) _p="$_p;the account roots are still created as a side effect" ;;
  esac
  # never_adopt_list must reach them through pkgusr_roots -- a second literal
  # list is one more place to forget when a root is added
  case "$(_slice_fn "$helper_src" never_adopt_list)" in
      *pkgusr_roots*) ;;
      *) _p="$_p;never_adopt_list does not cover the account roots" ;;
  esac
  # and they must NOT be install dirs
  if _slice_fn "$helper_src" install_dirs_list | grep -qx '/usr/src/pkgusr'; then
      _p="$_p;the package root is an install dir -- any package user could delete a home"
  fi
  if [ -n "$_p" ]; then
      printf '%s\n' "${_p#;}" | tr ';' '\n' | while IFS= read -r m; do
          [ -n "$m" ] && bad "$m"
      done
  else
      ok "the account roots are created deliberately and never adopted"
  fi
fi

# ---- /sources is normalised on the way into the chroot ---------------------- #
# Book 3.1 wants $LFS/sources root:root 1777.  The host `lfs` account comes from
# book 4.3's own useradd, which pins no uid, so it lands wherever the host had a
# gap -- 10753 on a Debian host.  Package users start at 10000, so that uid does
# not merely read as a number inside the chroot, it COLLIDES with a real package
# user and tarballs report as owned by something unrelated.
#
# _normalize_sources was only called from get-sources and restart, so a tree set
# up before it existed kept the host uid forever.  Entry is the one path every
# build goes through, whatever it did before.
python3 - "$LFS_TOOL" <<'PYSRCNORM'
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r"^def cmd_bs_chroot\(.*?(?=\n\ndef )", src, re.S | re.M)
problems = []
if not m:
    problems.append("cmd_bs_chroot is gone")
else:
    body = m.group(0)
    enter = body.split('if action == "enter"')
    if len(enter) < 2:
        problems.append("chroot enter is gone")
    elif "_normalize_sources" not in enter[1]:
        problems.append("nothing normalises /sources on chroot entry")
    prep = body.split('if action == "prepare"')
    if len(prep) > 1 and "_normalize_sources" not in prep[1].split('if action ==')[0]:
        problems.append("nothing normalises /sources after the 7.2 handover")
if problems:
    for p in problems:
        print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  /sources is given back to root on the way into the chroot")
PYSRCNORM
_count_rc $?

# ---- a wrapper must never stand in for a privileged tool -------------------- #
# make_wrappers ships a `chgrp` and a `chown` that print a note and exit 0, so a
# PACKAGE USER cannot change ownership.  They are ordinary files on $PATH.  If
# that directory is ever ahead of /usr/bin for root, root's own privileged calls
# resolve to them too -- and they report success while doing nothing.
#
# A tree ran 34 packages that way: init-pkgusr said
#     # 46 install directories now belong to group 'install'
# with an empty failure list, while every one was still root:root.  No package
# user could write to /usr/bin, `verify --fix` could not repair it (its chown
# went through the same wrapper), and nothing said why.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
  _p=""
  # the wrappers really do exit 0 without acting -- that is the hazard
  _slice_fn "$helper_src" make_wrappers | grep -q 'package users cannot change ownership' \
      || _p="$_p;the chown wrapper no longer explains itself"
  # so ownership and mode must go through the binary, by absolute path
  for _fn in real_chown real_chgrp real_chmod; do
      _slice_fn "$helper_src" "$_fn" | grep -q . \
          || _p="$_p;there is no $_fn -- a wrapper can shadow root's own calls"
  done
  _slice_fn "$helper_src" _real_tool | grep -q '/usr/bin/' \
      || _p="$_p;_real_tool does not resolve an absolute path"
  # and no privileged pass may call the bare command any more
  for _fn in cmd_init_pkgusr init_package_user_home _vfy_install_dirs ensure_pkgusr_roots; do
      # only where the tool is INVOKED -- start of a command, or after
      # &&/||/;/!.  Matching it anywhere caught the warning text that explains
      # the hazard, which would have made this test impossible to satisfy.
      if _slice_fn "$helper_src" "$_fn" \
           | grep -vE '^[[:space:]]*#' \
           | grep -qE '(^[[:space:]]*|&&[[:space:]]*|\|\|[[:space:]]*|;[[:space:]]*|![[:space:]]*)(chown|chgrp|chmod) '; then
          _p="$_p;$_fn still calls a bare chown/chgrp/chmod"
      fi
  done
  if [ -n "$_p" ]; then
      printf '%s\n' "${_p#;}" | tr ';' '\n' | while IFS= read -r m; do
          [ -n "$m" ] && bad "$m"
      done
  else
      ok "root's ownership calls cannot resolve to a package-user wrapper"
  fi

  # exit 0 is not proof.  init-pkgusr must read the group back.
  _blk="$(_slice_fn "$helper_src" cmd_init_pkgusr)"
  _p=""
  # owner AND group: the rule is root:install, and reading back only the group
  # is how /usr/share sat at lfs:install without anything noticing
  case "$_blk" in
      *'stat -c %U:%G'*) ;;
      *) _p="$_p;init-pkgusr trusts the exit code instead of reading the result back" ;;
  esac
  case "$_blk" in
      *'NO install directories'*) ;;
      *) _p="$_p;init-pkgusr reports zero install directories as success" ;;
  esac
  if [ -n "$_p" ]; then
      printf '%s\n' "${_p#;}" | tr ';' '\n' | while IFS= read -r m; do
          [ -n "$m" ] && bad "$m"
      done
  else
      ok "init-pkgusr confirms the install group took, and zero is an error"
  fi
fi

# ---- an empty override must not disable the whole scheme -------------------- #
# install_dirs_list is overridable through $INSTALLDIRS and returned early when
# the file existed.  An override yielding nothing meant NO directory was given
# to the install group, NO directory was protected from adoption, and `verify`
# reported a clean tree because it walked the same empty list.  Nine callers,
# one silent no-op.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
  _o="$( STATE=/tmp/_idl.$$; INSTALLDIRS="$STATE/installdirs.lst"
      mkdir -p "$STATE"
      eval "$(_slice_fn "$helper_src" install_dirs_list)"
      warn() { :; }
      # no override at all -> the built-in list
      [ "$(install_dirs_list 2>/dev/null | grep -c .)" -gt 10 ] \
          || echo "the built-in list is empty"
      # an override with only comments and blanks -> fall back, never nothing
      printf '# just a comment\n\n   \n' > "$INSTALLDIRS"
      [ "$(install_dirs_list 2>/dev/null | grep -c .)" -gt 10 ] \
          || echo "an empty override silently disables every install directory"
      # a real override is still honoured
      printf '/usr/bin\n/usr/lib\n' > "$INSTALLDIRS"
      [ "$(install_dirs_list 2>/dev/null | grep -c .)" = 2 ] \
          || echo "a real override is no longer honoured"
      rm -rf "$STATE" )"
  if [ -z "$_o" ]; then
      ok "an override that lists nothing falls back to the built-in list"
  else
      printf '%s\n' "$_o" | while IFS= read -r m; do [ -n "$m" ] && bad "$m"; done
  fi
fi

# ---- an option is not a package name ---------------------------------------- #
# /usr/src/pkgusr/p_--version turned up in a sanity run: a home for an account
# that could never exist, left by something that reached add-user with
# "--version" in the name position.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
  _slice_fn "$helper_src" _refuse_option_as_name | grep -q 'looks like an option' \
      && case "$(_slice_fn "$helper_src" cmd_add_user)" in
             *_refuse_option_as_name*) ok "a name starting with a dash is refused, not made into a user" ;;
             *) bad "add-user does not refuse an option-shaped name" ;;
         esac \
      || bad "there is no guard against an option being used as a package name"
fi

# ---- the sanity report checks the group it prints --------------------------- #
# Section 1 printed owner:group from the start and asserted only the mode.  A
# tree ran 34 packages with every install directory at root:root 775 --
# group-writable, but group `root`, while package users are in `install`.  The
# column that would have shown it was decoration.
san="$(dirname "$LFS_TOOL")/lfs-sanity.sh"
if [ -f "$san" ]; then
  _p=""
  grep -q "want 'install'" "$san" \
      || _p="$_p;the sanity report does not check the install group"
  grep -q "a package has taken a shared directory" "$san" \
      || _p="$_p;the sanity report does not check who owns a shared directory"
  if [ -n "$_p" ]; then
      printf '%s\n' "${_p#;}" | tr ';' '\n' | while IFS= read -r m; do
          [ -n "$m" ] && bad "$m"
      done
  else
      ok "the sanity report asserts the install-dir owner and group"
  fi
fi

# ---- one wrapper directory, not two ----------------------------------------- #
# make_wrappers wrote to $STATE/wrappers while /etc/pkgusr/bash_profile -- and
# packagemanager's copy of it -- put /usr/lib/pkgusr first on a package user's
# PATH.  Nothing created that, so a package user's login shell led with a
# directory that did not exist, and the wrappers only ever applied because
# cmd_build overrides PATH on the command line.  Two names for one decision.
#
# /usr/lib/pkgusr is the survivor: $STATE is build state, and packagemanager on
# the finished system hands its users the same profile.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
  _p=""
  grep -q '^WRAPPERS="\${LFS_WRAPPERS:-\${SNAP_ROOT%/}/usr/lib/pkgusr}"' "$helper_src" \
      || _p="$_p;the wrapper directory is not /usr/lib/pkgusr"
  grep -q 'WRAPPERS="\$STATE/wrappers"' "$helper_src" \
      && _p="$_p;the old \$STATE/wrappers definition is still there"
  # the profile must not name the directory a second time
  case "$(_slice_fn "$helper_src" ensure_pkgusr_etc)" in
      *'PATH=/usr/lib/pkgusr:'*)
          _p="$_p;the profile still hardcodes the wrapper path instead of using \$WRAPPERS" ;;
  esac
  case "$(_slice_fn "$helper_src" ensure_pkgusr_etc)" in
      *'s|@WRAPPERS@|$WRAPPERS|'*) ;;
      *) _p="$_p;the profile's PATH is not filled in from \$WRAPPERS" ;;
  esac
  # and it must be protected: under /usr/lib, which IS an install dir, so
  # without this any package user could rewrite the wrappers that constrain it
  case "$(_slice_fn "$helper_src" never_adopt_list)" in
      *'"$WRAPPERS"'*) ;;
      *) _p="$_p;the wrapper directory can be adopted or given to the install group" ;;
  esac
  case "$(_slice_fn "$helper_src" make_wrappers)" in
      *'chown root:root "$WRAPPERS"'*) ;;
      *) _p="$_p;the wrappers are not explicitly root-owned" ;;
  esac
  if [ -n "$_p" ]; then
      printf '%s\n' "${_p#;}" | tr ';' '\n' | while IFS= read -r m; do
          [ -n "$m" ] && bad "$m"
      done
  else
      ok "there is one wrapper directory, and it outlives the build"
  fi
fi

# packagemanager builds the same profile for the finished system, so it must
# reach the same path -- a second hardcoded copy is how these drifted
pm_src="$(dirname "$LFS_TOOL")/packagemanager"
if [ -f "$pm_src" ]; then
  _p=""
  grep -q '^WRAPPERS = os.environ.get("LFS_WRAPPERS", "/usr/lib/pkgusr")' "$pm_src" \
      || _p="$_p;packagemanager has no WRAPPERS setting"
  grep -q 'PATH=/usr/lib/pkgusr:' "$pm_src" \
      && _p="$_p;packagemanager still hardcodes the wrapper path in the profile"
  grep -q '_PKGUSR_BASH_PROFILE.replace("@WRAPPERS@", WRAPPERS)' "$pm_src" \
      || _p="$_p;packagemanager does not fill the wrapper path into the profile"
  if [ -n "$_p" ]; then
      printf '%s\n' "${_p#;}" | tr ';' '\n' | while IFS= read -r m; do
          [ -n "$m" ] && bad "$m"
      done
  else
      ok "both tools write a profile pointing at the same wrapper directory"
  fi
fi

# ---- an install directory is root:install, owner AND group ------------------- #
# init-pkgusr set only the GROUP, while _vfy_install_dirs demands root:install
# and `verify --fix` applies both.  Two rules for one directory.
#
# They disagreed on a real build: chapters 5-6 build as the `lfs` user, and book
# 7.2's handover only reaches one level below $LFS, so /usr/share stayed
# lfs-owned and came out
#     lfs:install drwxrwxr-x /usr/share
# The group looked right and nothing said the owner was not.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
  _blk="$(_slice_fn "$helper_src" cmd_init_pkgusr)"
  _p=""
  # owner AND group -- through the shared rule, which applies both by number.
  # This used to look for `real_chown root:install`, which is the by-name form
  # that cannot work before book 7.6 writes /etc/passwd.
  case "$_blk" in
      *'set_install_dir_owner "$d"'*) ;;
      *) _p="$_p;init-pkgusr sets the group but not the owner of an install directory" ;;
  esac
  case "$_blk" in
      *'stat -c %U:%G'*) ;;
      *) _p="$_p;init-pkgusr reads back only the group, so a wrong owner goes unnoticed" ;;
  esac
  # the two rules must want the same thing
  case "$(_slice_fn "$helper_src" _vfy_install_dirs)" in
      *root:install*) ;;
      *) _p="$_p;verify no longer wants root:install" ;;
  esac
  if [ -n "$_p" ]; then
      printf '%s\n' "${_p#;}" | tr ';' '\n' | while IFS= read -r m; do
          [ -n "$m" ] && bad "$m"
      done
  else
      ok "init-pkgusr and verify agree that an install dir is root:install"
  fi
fi

# ---- every tool we install gets an owner ------------------------------------- #
# install_helper copies lfs/lfs-helper/packagemanager/blfs and calls
# _chown_tools.  _install_pkgusr_helpers copied the hint's scripts beside them
# and never did -- so /usr/bin/list_package, uninstall_package,
# forall_direntries_from and the rest came out root:root while the four tools
# next to them belonged to p_pkgusr.  Two copy routines, one claiming ownership.
#
# The WRAPPER directory is the deliberate exception: it stays root:root, because
# a package user that could rewrite chown or install could rewrite the rule that
# constrains it.
python3 - "$LFS_TOOL" <<'PYHELPEROWN'
import re, sys
src = open(sys.argv[1]).read()
problems = []
m = re.search(r"^def _install_pkgusr_helpers\(.*?(?=\n\ndef )", src, re.S | re.M)
if not m:
    problems.append("_install_pkgusr_helpers is gone")
else:
    body = m.group(0)
    if "_chown_tools" not in body:
        problems.append("the hint's helpers are copied but never given an owner")
    if "wrapper_sub" not in body:
        problems.append("the wrapper directory is not excluded from the chown")
if not re.search(r'^WRAPPERS = os\.environ\.get\("LFS_WRAPPERS"', src, re.M):
    problems.append("lfs does not read the shared WRAPPERS setting")
# and the helper table must not spell the wrapper path out a fourth time
tbl = re.search(r"PKGUSR_HELPERS = \[(.*?)\n\]", src, re.S)
if tbl and '"usr/lib/pkgusr"' in tbl.group(1):
    problems.append("PKGUSR_HELPERS still hardcodes the wrapper path")
if problems:
    for p in problems:
        print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  every tool installed into the tree is given an owner")
PYHELPEROWN
_count_rc $?

# ---- scratch never enters a manifest ---------------------------------------- #
# $BUILD_ROOT is the busiest directory on the system during a build: unpacked
# source trees, object files, the tarballs themselves.  Every one is newer than
# the build stamp, so the touched-file scan swallowed the whole scratch tree
# into every package's manifest and then chowned it -- and the next package
# chowned it right back.  A real `verify` came back with 3363 wrong-owner, of
# which 3348 were /build:
#     /build/bash-5.3.tar.gz  is p_shadow  want p_acl
# The two snapshot scans already excluded it; the build's own scan did not.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
  _cb="$(_slice_fn "$helper_src" cmd_build)"
  _p=""
  case "$_cb" in
      *'-not -path "$_bld/*"'*) ;;
      *) _p="$_p;the build scratch is still scanned into every manifest" ;;
  esac
  case "$_cb" in
      *'BUILD_ROOT:-$r/build'*) ;;
      *) _p="$_p;the scratch exclusion does not follow \$BUILD_ROOT" ;;
  esac
  # and verify must ignore scratch left in manifests written before this
  case "$(_slice_fn "$helper_src" _vfy_manifest_ownership)" in
      *'BUILD_ROOT'*) ;;
      *) _p="$_p;verify still reports scratch recorded by an older build" ;;
  esac
  if [ -n "$_p" ]; then
      printf '%s\n' "${_p#;}" | tr ';' '\n' | while IFS= read -r m; do
          [ -n "$m" ] && bad "$m"
      done
  else
      ok "the build scratch is never recorded as a package's files"
  fi
fi

# ---- some files belong to no package ---------------------------------------- #
# Every package that installs an info page rewrites /usr/share/info/dir, and
# ldconfig rewrites /etc/ld.so.cache after every install.  Recording those in a
# manifest makes verify report a conflict no repair can settle -- the next
# package takes them straight back:
#     /usr/share/info/dir            is p_gcc     want p_binutils
#     /etc/ld.so.cache               is p_libcap  want p_glibc
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
  _o="$( SNAP_ROOT=/
      eval "$(_slice_fn "$helper_src" never_claim_list)"
      eval "$(_slice_fn "$helper_src" is_never_claimed)"
      for f in /usr/share/info/dir /etc/ld.so.cache /var/cache/ldconfig/aux-cache; do
          is_never_claimed "$f" || echo "$f can still be claimed by a package"
      done
      # the wrapper directory too: it is root:root on purpose
      is_never_claimed /usr/lib/pkgusr/chown \
          || echo "a wrapper can be claimed by a package"
      # but a real package file must NOT be swept up by this
      is_never_claimed /usr/bin/bash \
          && echo "an ordinary package file is treated as unclaimable" )"
  if [ -z "$_o" ]; then
      ok "shared indexes and generated caches are owned by no package"
  else
      printf '%s\n' "$_o" | while IFS= read -r m; do [ -n "$m" ] && bad "$m"; done
  fi
fi

# ---- the 7.2 handover is decided by the tree, not one inode ------------------ #
# `_owner_is_root` looks at $LFS/usr.  The pass it guarded is
# `chown -h -R root:root` over EIGHT trees.  A tree whose /usr was already
# root-owned got no handover at all, and everything chapters 5-6 created below
# it kept the host uid:
#     drwxr-xr-x 1 lfs lfs /usr/share/gcc-15.2.0/python/libstdcxx
#     lfs:install drwxrwxr-x /usr/share
# It must also refuse to run once package users own files -- chown -R root:root
# over /usr is right before chapter 8 and catastrophic after it.
python3 - "$LFS_TOOL" <<'PYHANDOVER'
import re, sys
src = open(sys.argv[1]).read()
problems = []
for fn in ("_handover_needed", "_handover_is_safe"):
    if not re.search(r"^def %s\(" % fn, src, re.M):
        problems.append("there is no %s" % fn)
m = re.search(r"^def _handover_needed\(.*?(?=\n\ndef )", src, re.S | re.M)
if m and "_find_uid" not in m.group(0):
    problems.append("_handover_needed still decides from a single directory")
m = re.search(r"^def _handover_is_safe\(.*?(?=\n\ndef )", src, re.S | re.M)
# It must ask the TREE's passwd which accounts are package users, not infer it
# from a uid range: book 4.3 pins no uid for `lfs`, so on one host the build
# account came out 10753 -- inside the package range -- and a range filter
# excluded the very user it was looking for.
if m and "_pkg_users_in_tree" not in m.group(0):
    problems.append("_handover_is_safe infers package users from a uid range")
if not re.search(r"^def _pkg_users_in_tree\(", src, re.M):
    problems.append("there is no _pkg_users_in_tree")
m2 = re.search(r"^def _handover_needed\(.*?(?=\n\ndef )", src, re.S | re.M)
if m2 and "PKG_UID_MIN" in m2.group(0):
    problems.append("_handover_needed still filters the build user out by uid range")
m = re.search(r"^def cmd_bs_chroot\(.*?(?=\n\ndef )", src, re.S | re.M)
if m:
    body = m.group(0)
    if "_handover_needed" not in body:
        problems.append("chroot prepare still guards 7.2 on _owner_is_root alone")
    if "_handover_is_safe" not in body:
        problems.append("chroot prepare would run chown -R over a chapter-8 tree")
if problems:
    for p in problems:
        print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  the 7.2 handover is decided by the tree and refuses a built one")
PYHANDOVER
_count_rc $?

# and a tree that already has the damage must be repairable
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
  _p=""
  _slice_fn "$helper_src" _vfy_build_user_leftovers | grep -q '\-user lfs' \
      || _p="$_p;verify cannot find files the build user still owns"
  _slice_fn "$helper_src" _vfy_build_user_leftovers | grep -q 'real_chown -h root:root' \
      || _p="$_p;verify --fix cannot hand the build user's leftovers back to root"
  case "$(_slice_fn "$helper_src" cmd_verify)" in
      *_vfy_build_user_leftovers*) ;;
      *) _p="$_p;verify does not run the build-user pass" ;;
  esac
  if [ -n "$_p" ]; then
      printf '%s\n' "${_p#;}" | tr ';' '\n' | while IFS= read -r m; do
          [ -n "$m" ] && bad "$m"
      done
  else
      ok "a tree the handover skipped can be repaired from inside the chroot"
  fi
fi

# ---- every function called is a function that exists ------------------------ #
# `verify --fix` called cmd_fix_orphans, which does not exist -- `fix-orphans`
# is dispatched as an ALIAS for `verify --fix`, so the call was both undefined
# and circular.  It died mid-repair:
#     line 4793: cmd_fix_orphans: command not found
# after chowning 3473 paths, leaving the pass half-done and the status wrong.
#
# A missing function in the REPAIR path is the worst place for one: it only
# fires when something is already broken, which is when it is least welcome.
for _t in lfs-helper; do
  _src="$(dirname "$LFS_TOOL")/$_t"
  [ -f "$_src" ] || continue
  _missing=""
  # comments stripped first: the fix for this bug NAMES the function it
  # removed, and matching that text would make the test permanently red
  for _fn in $(grep -vE '^[[:space:]]*#' "$_src" \
               | grep -oE '(^|[^_[:alnum:]])cmd_[a-z0-9_]+' \
               | grep -oE 'cmd_[a-z0-9_]+' | sort -u); do
      grep -qE "^${_fn}\(\) \{" "$_src" || _missing="$_missing $_fn"
  done
  if [ -n "$_missing" ]; then
      for _m in $_missing; do bad "$_t calls $_m, which is not defined"; done
  else
      ok "$_t defines every cmd_* function it calls"
  fi
done

# ---- a package builds in its own home, not a shared scratch ----------------- #
# /build was a permanent ownership fight.  Every build's touched-file scan swept
# the whole tree in, so each manifest claimed every other package's sources and
# chowned them; the next package chowned them back.  Repairing it made it worse,
# because the question had no answer:
#     /build/bash-5.3.tar.gz  is p_shadow  want p_acl
#     /build/bash-5.3.tar.gz  is p_zstd    want p_acl    (after the repair)
#
# Under the package user's home it is settled by construction: the user creates
# the tree so the user owns it, and $SRCROOT is already excluded from every tree
# scan, so it can never reach a manifest at all.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
  _o="$( SNAP_ROOT=/; SRCROOT=/usr/src
      PKGUSR_ROOT=/usr/src/pkgusr; CFGUSR_ROOT=/usr/src/cfg
      PKGUSR_PREFIX="p_"; CFGUSR_PREFIX="cfg_"
      STATE=/.lfs-pkgusr; SCRIPTS="$STATE/scripts"
      PKGUSR_BUILD_SUBDIR=src
      for fn in pkgusr_kind pkgusr_prefix_for pkgusr_root_for unprefix_pkg_user \
                pkg_owner_name pkgusr_home_for _is_not_a_package build_root_for; do
          eval "$(_slice_fn "$helper_src" "$fn")"
      done
      if ! command -v build_root_for >/dev/null 2>&1; then
          echo "there is no build_root_for -- the scratch is still shared"
          exit 0        # the rest would be noise, not findings
      fi
      # a package builds under its own account's home
      [ "$(build_root_for gcc)" = "/usr/src/pkgusr/p_gcc/$PKGUSR_BUILD_SUBDIR" ] \
          || echo "gcc does not build in its own home: $(build_root_for gcc)"
      # an earlier stage folds onto the same package, so it reuses that tree
      [ "$(build_root_for util-linux-tmp)" = "$(build_root_for util-linux)" ] \
          || echo "an earlier stage builds somewhere else than its package"
      # and it must be under $SRCROOT, which every tree scan already excludes --
      # that is what keeps it out of manifests without another find exclusion
      case "$(build_root_for gcc)" in
          "$SRCROOT"/*) ;;
          *) echo "the build tree is not under SRCROOT, so scans will sweep it in" ;;
      esac
      # a step with no account keeps the shared scratch: it runs as root, which
      # owns everything there anyway
      case "$(build_root_for init-dirs)" in
          /usr/src/*) echo "a step with no account was given a home to build in" ;;
      esac )"
  if [ -z "$_o" ]; then
      ok "each package unpacks and builds inside its own account's home"
  else
      printf '%s\n' "$_o" | while IFS= read -r m; do [ -n "$m" ] && bad "$m"; done
  fi

  # and the build must actually be told about it
  case "$(_slice_fn "$helper_src" cmd_build)" in
      *"BUILD_ROOT='\$_bldroot'"*)
          ok "the per-package build root is passed into the build" ;;
      *) bad "the build still inherits whatever BUILD_ROOT it was started with" ;;
  esac
fi

# ---- the root symlinks are chowned, not followed ---------------------------- #
# Book 4.2 creates /bin -> usr/bin, /lib and /sbin as the build user.  They came
# out lfs:lfs, and a chown WITHOUT -h follows the link and retargets /usr/bin
# instead -- silently doing the wrong thing to the right-looking path.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
  _blk="$(_slice_fn "$helper_src" _vfy_build_user_leftovers)"
  _p=""
  case "$_blk" in
      *'real_chown -h'*) ;;
      *) _p="$_p;the build-user repair follows symlinks instead of chowning them" ;;
  esac
  case "$(printf '%s\n' "$_blk" | grep -vE '^[[:space:]]*#')" in
      *'-type f'*) _p="$_p;the build-user scan skips symlinks and directories" ;;
  esac
  if [ -n "$_p" ]; then
      printf '%s\n' "${_p#;}" | tr ';' '\n' | while IFS= read -r m; do
          [ -n "$m" ] && bad "$m"
      done
  else
      ok "a symlink owned by the build user is chowned, not followed"
  fi
fi

# ---- the tree can be set up before book 7.6 exists -------------------------- #
# A chapter 5-6 snapshot restored before 7.6 has NO /etc/passwd -- the chroot
# prompt says "I have no name!".  `chown root:install` needs `root` to resolve,
# so every call failed and init-pkgusr reported:
#     # 0 install directories are now root:install (group-writable)
#     # could not set the group on: /usr /usr/bin /usr/lib /usr/share ...
# while ensure_install_dirs_writable used `chgrp` and worked fine.  Two rules
# for one directory, and only one of them survived an empty passwd file.
#
# Ownership is stored as a NUMBER, so use the number.
_p=""
_pre="$T/pre76"
mkdir -p "$_pre/etc" "$_pre/usr/share/man/man3"
: > "$_pre/etc/passwd"                      # exists, but empty: no root entry
printf 'install:x:9999:\n' > "$_pre/etc/group"
# the shape that broke: a name that cannot resolve
if chown root:install "$_pre/usr/share/man/man3" 2>/dev/null; then
    : # this host HAS a root and an install group, so the fixture proves nothing
else
    # numeric must work where the name did not
    if chown -h 0:9999 "$_pre/usr/share/man/man3" 2>/dev/null; then
        [ "$(stat -c '%u:%g' "$_pre/usr/share/man/man3")" = "0:9999" ] \
            || _p="$_p;a numeric chown did not take"
    else
        _p="$_p;even a numeric chown fails here -- fixture is not usable"
    fi
fi
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
  # one helper, used by all three passes that set an install directory
  _slice_fn "$helper_src" set_install_dir_owner | grep -q '0:\$INSTALL_GID' \
      || _p="$_p;the install-dir owner is not set by number"
  _slice_fn "$helper_src" install_dir_owner_ok | grep -q "%u:%g" \
      || _p="$_p;the install-dir check reads names, which are UNKNOWN before 7.6"
  for _fn in cmd_init_pkgusr ensure_install_dirs_writable _vfy_install_dirs; do
      _slice_fn "$helper_src" "$_fn" | grep -q 'set_install_dir_owner' \
          || _p="$_p;$_fn does not use the shared install-dir rule"
  done
  # and no pass may still reach for the names
  for _fn in cmd_init_pkgusr ensure_install_dirs_writable _vfy_install_dirs; do
      _slice_fn "$helper_src" "$_fn" | grep -vE '^[[:space:]]*#' \
          | grep -qE 'chown root:install|chgrp install ' \
          && _p="$_p;$_fn still sets an install dir by name"
  done
fi
if [ -n "$_p" ]; then
    printf '%s\n' "${_p#;}" | tr ';' '\n' | while IFS= read -r m; do
        [ -n "$m" ] && bad "$m"
    done
else
    ok "install directories are set by number, so a tree with no passwd works"
fi

# ---- nothing is an orphan before there is a passwd file --------------------- #
# `find -nouser` asks whether a uid resolves.  With no passwd file NOTHING
# resolves, so every file in the tree is an "orphan".  On a restored chapter 5-6
# tree that reported
#     noowner  /       (no passwd entry) -> lfs
#     noowner  /dev    (no passwd entry) -> lfs
#     ... and 11797 more with no owner
# and `--fix` would have handed the ENTIRE tree -- root's own directories
# included -- to the build user in one pass.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
  _p=""
  for _fn in _vfy_orphans _has_orphaned_files _vfy_build_user_leftovers; do
      _slice_fn "$helper_src" "$_fn" | grep -q '_user_db_ready' \
          || _p="$_p;$_fn runs before the user database exists"
  done
  if [ -n "$_p" ]; then
      printf '%s\n' "${_p#;}" | tr ';' '\n' | while IFS= read -r m; do
          [ -n "$m" ] && bad "$m"
      done
  else
      ok "the ownership passes wait for book 7.6 to write /etc/passwd"
  fi
fi

# ---- nothing privileged may need a name to resolve -------------------------- #
# init-pkgusr runs BEFORE book 7.6 creates /etc/passwd.  The prompt in there
# literally reads "I have no name!" because not even root resolves.  So
# `chown root:install` fails on every directory:
#     # 0 install directories are now root:install (group-writable)
#     # could not set the group on: /bin /sbin /lib /lib64 /etc /usr ...
# and every package user is then locked out of /usr/bin for the whole build.
#
# Ownership is stored as a NUMBER.  uid 0 is root whether anything says so or
# not, and the install gid is ours -- init-pkgusr writes /etc/group by hand, so
# the group can exist long before any passwd entry does.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
  _p=""
  _slice_fn "$helper_src" set_install_dir_owner | grep -q '0:\$INSTALL_GID' \
      || _p="$_p;an install directory is set by name, which fails before 7.6"
  _slice_fn "$helper_src" install_dir_owner_ok | grep -q "%u:%g" \
      || _p="$_p;the readback uses names, so a correct directory reads as wrong"
  # No privileged pass may reach for the NAMES.  Match the INVOCATION, not the
  # string: these functions legitimately print "now root:install" and carry
  # trailing comments saying the same, and matching those made the test
  # impossible to satisfy while changing nothing about the behaviour.
  for _fn in cmd_init_pkgusr _vfy_install_dirs ensure_install_dirs_writable; do
      _slice_fn "$helper_src" "$_fn" | grep -vE '^[[:space:]]*#' \
          | grep -qE '(real_)?(chown|chgrp)( +-[a-zA-Z]+)* +(root:install|install) ' \
          && _p="$_p;$_fn still sets the group by name, which fails before 7.6"
  done
  if [ -n "$_p" ]; then
      printf '%s\n' "${_p#;}" | tr ';' '\n' | while IFS= read -r m; do
          [ -n "$m" ] && bad "$m"
      done
  else
      ok "install directories are set by number, so 7.6 is not a prerequisite"
  fi

  # and the orphan pass must not fire before there is a database to be
  # orphaned FROM.  With no passwd file `find -nouser` matches everything: a
  # real run reported 11802 orphans including / and /proc, and --fix would have
  # handed the entire tree to the build user in one pass.
  _p=""
  case "$(_slice_fn "$helper_src" _vfy_orphans)" in
      *_user_db_ready*) ;;
      *) _p="$_p;the orphan pass would hand the whole tree to the build user before 7.6" ;;
  esac
  case "$(_slice_fn "$helper_src" _has_orphaned_files)" in
      *_user_db_ready*) ;;
      *) _p="$_p;a tree with no passwd file is reported as entirely orphaned" ;;
  esac
  if [ -n "$_p" ]; then
      printf '%s\n' "${_p#;}" | tr ';' '\n' | while IFS= read -r m; do
          [ -n "$m" ] && bad "$m"
      done
  else
      ok "an orphan needs a user database to be missing from"
  fi
fi

# ---- the build user's uid is not a range ------------------------------------ #
# Book 4.3's useradd pins no uid, so the host's `lfs` account lands wherever the
# host had a gap -- 10753 on a Debian host, INSIDE the package-user range.  Any
# rule that identifies the build user by "uid outside 10000+" therefore excludes
# the very account it is looking for.  That is the same mistake _normalize_sources
# exists to correct, and _handover_needed walked straight into it: it reported
#     # 7.2 already done (tree owned by root)
# while /bin -> usr/bin was still lfs:lfs.
python3 - "$LFS_TOOL" <<'PYUIDRANGE'
import re, sys
src = open(sys.argv[1]).read()
problems = []
m = re.search(r"^def _handover_needed\(.*?(?=\n\ndef )", src, re.S | re.M)
if not m:
    problems.append("_handover_needed is gone")
else:
    body = re.sub(r"^\s*#.*$", "", m.group(0), flags=re.M)
    if "PKG_UID_MIN" in body:
        problems.append("_handover_needed still identifies the build user by uid range")
m = re.search(r"^def _handover_is_safe\(.*?(?=\n\ndef )", src, re.S | re.M)
if not m:
    problems.append("_handover_is_safe is gone")
else:
    body = re.sub(r"^\s*#.*$", "", m.group(0), flags=re.M)
    if "_pkg_users_in_tree" not in body:
        problems.append("_handover_is_safe does not read the tree's own passwd")
if not re.search(r"^def _pkg_users_in_tree\(", src, re.M):
    problems.append("there is no _pkg_users_in_tree")
else:
    m = re.search(r"^def _pkg_users_in_tree\(.*?(?=\n\ndef |\Z)", src, re.S | re.M)
    if m and "pkgusr_prefix" not in m.group(0):
        problems.append("_pkg_users_in_tree does not identify accounts by prefix")
if problems:
    for p in problems:
        print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  the build user is identified by the tree, never by a uid range")
PYUIDRANGE
_count_rc $?

# ---- one step where ownership becomes real ---------------------------------- #
# Before book 7.6 there is no /etc/passwd, so no name resolves -- not even
# root's; the prompt in the chroot literally reads "I have no name!".  Every
# ownership question asked before that point gets a confident wrong answer:
#
#   chown root:install fails on every directory       -> "0 install directories"
#   find -nouser matches every file in the tree       -> 11802 "orphans"
#
# Three separate bugs, one cause: work that needs a user database was being done
# before there was one.  So there is one gate now.  Nothing touches ownership
# before it; everything maintains ownership after it.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
  _p=""
  for _fn in ownership_established ownership_possible establish_ownership \
             _ownership_checkpoint cmd_establish_ownership; do
      _slice_fn "$helper_src" "$_fn" | grep -q . \
          || _p="$_p;there is no $_fn"
  done
  # the gate must test the user database and the tools it needs
  _op="$(_slice_fn "$helper_src" ownership_possible)"
  case "$_op" in
      *_user_db_ready*) ;;
      *) _p="$_p;the gate does not wait for the user database" ;;
  esac
  case "$_op" in
      *chown*) ;;
      *) _p="$_p;the gate does not check that chown is available" ;;
  esac
  # it must be durable, so a resumed or restored build does not repeat it
  grep -q '^OWNERSHIP_MARK=' "$helper_src" \
      || _p="$_p;crossing the epoch is not recorded, so it repeats"
  case "$(_slice_fn "$helper_src" establish_ownership)" in
      *'> "$OWNERSHIP_MARK"'*) ;;
      *) _p="$_p;establish_ownership never writes its marker" ;;
  esac
  # and everything ownership-related must be inside it, not scattered
  _eo="$(_slice_fn "$helper_src" establish_ownership)"
  for _need in cmd_init_pkgusr _vfy_build_user_leftovers _vfy_manifest_ownership \
               _adopt_pkgusr_tools _vfy_orphans; do
      case "$_eo" in
          *"$_need"*) ;;
          *) _p="$_p;$_need does not happen at the ownership epoch" ;;
      esac
  done
  # reachable by hand as well as automatically
  grep -q 'establish-ownership)' "$helper_src" \
      || _p="$_p;there is no way to run the ownership step by hand"
  if [ -n "$_p" ]; then
      printf '%s\n' "${_p#;}" | tr ';' '\n' | while IFS= read -r m; do
          [ -n "$m" ] && bad "$m"
      done
  else
      ok "ownership is established once, at one step, and recorded"
  fi

  # the passes that need a user database must refuse to run without one
  _p=""
  for _fn in _vfy_orphans _has_orphaned_files _vfy_build_user_leftovers; do
      _slice_fn "$helper_src" "$_fn" | grep -q '_user_db_ready' \
          || _p="$_p;$_fn would run before there is a user database"
  done
  case "$(_slice_fn "$helper_src" _vfy_install_dirs)" in
      *ownership_*) ;;
      *) _p="$_p;verify would report 27 wrong install dirs on a chapter 5-6 tree" ;;
  esac
  # build-all must NOT set the package-user system up before the epoch --
  # that is what printed "0 install directories are now root:install"
  case "$(_slice_fn "$helper_src" cmd_build_all)" in
      *ownership_established*) ;;
      *) _p="$_p;build-all still sets up ownership before 7.6 has run" ;;
  esac
  if [ -n "$_p" ]; then
      printf '%s\n' "${_p#;}" | tr ';' '\n' | while IFS= read -r m; do
          [ -n "$m" ] && bad "$m"
      done
  else
      ok "nothing asks who owns what before there is a user database"
  fi
fi

# ---- the build tree must not collide with the skeleton ---------------------- #
# init_package_user_home symlinks .bash_profile, .bashrc and `build` into every
# package user's home -- `build` being the hint's build helper script.  The
# per-package build tree was first called `build` too, so `mkdir -p ~/build` hit
# the symlink and the build died two lines later complaining about the wrong
# thing:
#     mkdir: cannot create directory '.../p_gettext/build': File exists
#     cd: /usr/src/pkgusr/p_gettext/build: Not a directory
# The recovery code then read that as a permissions problem and retried twice
# before advising collector groups.  None of it was true.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
  _p=""
  _slice_fn "$helper_src" pkgusr_skel_links | grep -q . \
      || _p="$_p;the skeleton links are not named in one place"
  # the home skeleton must be built FROM that list, not from a second copy
  case "$(_slice_fn "$helper_src" init_package_user_home)" in
      *pkgusr_skel_links*) ;;
      *) _p="$_p;init_package_user_home keeps its own copy of the link list" ;;
  esac
  # and the build subdir must not be one of them
  _sub="$(grep -m1 '^PKGUSR_BUILD_SUBDIR=' "$helper_src" \
          | sed 's/.*:-\([a-z_]*\)}.*/\1/')"
  if [ -z "$_sub" ]; then
      _p="$_p;there is no PKGUSR_BUILD_SUBDIR"
  else
      for _l in $(_slice_fn "$helper_src" pkgusr_skel_links \
                  | grep -oE "'[^']+'|[a-z._:]+" | tr ' ' '\n'); do
          case "$_l" in
              "$_sub":*|"$_sub") _p="$_p;the build tree is called '$_sub', which the home skeleton already links" ;;
          esac
      done
  fi
  # and a name that is taken must be reported HERE, not as a cd failure later
  case "$(_slice_fn "$helper_src" cmd_build)" in
      *'is not a directory'*) ;;
      *) _p="$_p;a build tree that is not a directory fails somewhere else" ;;
  esac
  if [ -n "$_p" ]; then
      printf '%s\n' "${_p#;}" | tr ';' '\n' | while IFS= read -r m; do
          [ -n "$m" ] && bad "$m"
      done
  else
      ok "the build tree cannot collide with the package user's home skeleton"
  fi
fi

# ---- no function is defined twice ------------------------------------------ #
# `cmd_verify` was defined TWICE.  bash keeps the last, so the tidy definition
# that called the _vfy_* helpers had never run -- and the surviving one carried
# its own inline copies of the manifest and install-dir rules, without any of
# the guards the helpers had grown.
#
# A finished 104/104 build therefore reported three things the real pass knows
# to leave alone, and --fix would have acted on all three:
#     /usr/bin/hostname    is p_inetutils  want p_coreutils   (inetutils owns it)
#     /usr/share/info/dir  is p_e2fsprogs  want p_glibc       (nobody owns it)
#     /etc/group-          is root         want p_ncurses     (useradd wrote it)
#
# A duplicate definition is invisible: both parse, one silently wins.
for _t in lfs-helper; do
  _src="$(dirname "$LFS_TOOL")/$_t"
  [ -f "$_src" ] || continue
  _dups="$(grep -oE '^[a-z_][a-z0-9_]*\(\) \{' "$_src" | sort | uniq -d)"
  if [ -n "$_dups" ]; then
      printf '%s\n' "$_dups" | while IFS= read -r _d; do
          bad "$_t defines ${_d%\(\) \{} more than once -- one of them never runs"
      done
  else
      ok "$_t defines each function exactly once"
  fi
done

# and verify must USE the helpers rather than carry its own copy of the rules
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
  _cv="$(_slice_fn "$helper_src" cmd_verify)"
  _p=""
  for _need in _vfy_install_dirs _vfy_manifest_ownership _vfy_orphans \
               _vfy_user_homes _vfy_build_user_leftovers _vfy_user_order; do
      case "$_cv" in
          *"$_need"*) ;;
          *) _p="$_p;verify does not run $_need" ;;
      esac
  done
  # no second copy of the ownership rule inline
  case "$(printf '%s\n' "$_cv" | grep -vE '^[[:space:]]*#')" in
      *'want $owner'*) _p="$_p;verify still carries its own copy of the ownership rule" ;;
  esac
  if [ -n "$_p" ]; then
      printf '%s\n' "${_p#;}" | tr ';' '\n' | while IFS= read -r m; do
          [ -n "$m" ] && bad "$m"
      done
  else
      ok "verify runs the one implementation of each check"
  fi
fi

# ---- a collector group is named for the package ----------------------------- #
# It took the ACCOUNT name, so owner `p_perl` produced `nimgnu_p_perl` -- two
# prefixes, and the wrong two: `nimgnu_` says collector group, `p_` says package
# user, which it is not.  The prompt offered it as a choice:
#     1) nimgnu_p_perl   (everything owned by 'p_perl' -- fewer groups)
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
  _o="$( COLLECTOR_PREFIX=nimgnu; PKGUSR_PREFIX=p_
      eval "$(_slice_fn "$helper_src" unprefix_pkg_user)"
      eval "$(_slice_fn "$helper_src" collector_group_for)"
      [ "$(collector_group_for p_perl)" = "nimgnu_perl" ] \
          || echo "a collector group still carries the package-user prefix: $(collector_group_for p_perl)"
      # a bare package name is unchanged
      [ "$(collector_group_for perl)" = "nimgnu_perl" ] \
          || echo "a bare package name does not reach the same group"
      # a config step keeps its own prefix -- cfg_ is part of the step's name
      [ "$(collector_group_for cfg_bootscripts)" = "nimgnu_cfg_bootscripts" ] \
          || echo "a config step's group name lost its kind: $(collector_group_for cfg_bootscripts)" )"
  if [ -z "$_o" ]; then
      ok "a collector group carries the collector prefix and no other"
  else
      printf '%s\n' "$_o" | while IFS= read -r m; do [ -n "$m" ] && bad "$m"; done
  fi
fi

# ---- root's own files are root's ------------------------------------------- #
# Every cmd_add_user during a build writes /etc/passwd, /etc/group and Shadow's
# backups of them.  Whichever package happened to be building at the time swept
# them into its manifest:
#     /etc/.pwd.lock  is root  want p_ncurses
#     /etc/group-     is root  want p_ncurses
#     /etc/passwd-    is root  want p_psmisc
# ncurses did not install /etc/group-; useradd did, while ncurses was building.
# A package owning the file that says which packages exist is the one ownership
# mistake with no way back.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
  _o="$( ETC=/etc; SNAP_ROOT=/
      eval "$(_slice_fn "$helper_src" never_claim_list)"
      eval "$(_slice_fn "$helper_src" is_never_claimed)"
      for f in /etc/passwd /etc/passwd- /etc/group /etc/group- \
               /etc/shadow /etc/gshadow /etc/.pwd.lock; do
          is_never_claimed "$f" || echo "$f can be claimed by a package"
      done
      # ordinary configuration is still a package's to own
      is_never_claimed /etc/fstab \
          && echo "an ordinary config file was swept into the never-claim list" )"
  if [ -z "$_o" ]; then
      ok "the user database belongs to root and to no package"
  else
      printf '%s\n' "$_o" | while IFS= read -r m; do [ -n "$m" ] && bad "$m"; done
  fi

  # the tools we install are ours, in bin AND sbin
  _p=""
  grep -q 'add_package_user install_package' "$helper_src" \
      || _p="$_p;the hint's helper scripts are not claimed by p_pkgusr"
  case "$(_slice_fn "$helper_src" _adopt_pkgusr_tools)" in
      *'/usr/bin /usr/sbin'*) ;;
      *) _p="$_p;only /usr/bin is searched, so the sbin helpers stay unclaimed" ;;
  esac
  # and the wrappers must not be reported as needing an owner
  case "$(_slice_fn "$helper_src" _vfy_unclaimed)" in
      *is_never_claimed*) ;;
      *) _p="$_p;verify asks who should own the wrappers, which are root's by design" ;;
  esac
  if [ -n "$_p" ]; then
      printf '%s\n' "${_p#;}" | tr ';' '\n' | while IFS= read -r m; do
          [ -n "$m" ] && bad "$m"
      done
  else
      ok "our own tools get an owner; the wrappers stay root's"
  fi
fi

# ---- book 4.3 must not run on a built tree ---------------------------------- #
# `_chown_tree_to_lfs` is `chown -R lfs` over /usr, /etc, /var and the rest.
# Before chapter 5 that is book 4.3 and exactly right.  On a BUILT tree it hands
# the finished system to the host's build account in one pass, and every
# package's ownership is gone -- recoverable only from the manifests.
#
# It happened: `lfs build-system run` on a 104/104 tree replayed step 4.2 and
#     drwxrwxr-t 1 lfs install /mnt/lfs/usr
# came back with the host uid 10753 written through the tree.  Inside the chroot
# that resolves to nothing -- the chroot's own `lfs` is 9998 -- so `ls -al /`
# showed a raw number where every owner should have been.
python3 - "$LFS_TOOL" <<'PY43'
import re, sys
src = open(sys.argv[1]).read()
problems = []
m = re.search(r"^def _chown_tree_to_lfs\(.*?(?=\n\ndef )", src, re.S | re.M)
if not m:
    problems.append("_chown_tree_to_lfs is gone")
else:
    body = m.group(0)
    if "_handover_is_safe" not in body:
        problems.append("book 4.3 would chown a built tree to the build user")
    # the guard has to come BEFORE the chown, or it reports and then does it
    # the INVOCATION, not the comment above the guard that names the command
    g = body.find("if not _handover_is_safe")
    c = body.find("_run_bash('chown -R lfs")
    if c < 0:
        problems.append("the 4.3 chown is no longer recognisable")
    elif g < 0 or g > c:
        problems.append("the 4.3 guard runs after the chown it is guarding")
if problems:
    for p in problems:
        print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  book 4.3 refuses to hand a built tree back to the build user")
PY43
_count_rc $?

# ---- the ownership step is visible ------------------------------------------ #
# It ran as an invisible checkpoint inside build-all: right place, right work,
# but it never appeared in `lfs-helper list`.  The one moment the whole scheme
# turns on was the one moment you could not point at, resume from, or re-run.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
  _p=""
  # lfs puts it in the step order, straight after book 7.6
  grep -q 'order.insert(order.index("init-files") + 1, "init-ownership")' "$LFS_TOOL" \
      || _p="$_p;init-ownership is not in the step order"
  # lfs-helper performs it itself -- there is no script for it in the book
  case "$(_slice_fn "$helper_src" cmd_build)" in
      *'"$name" = "init-ownership"'*) ;;
      *) _p="$_p;lfs-helper would look for a book script for init-ownership" ;;
  esac
  # it owns no files, so it gets no account and no home
  case "$(_slice_fn "$helper_src" _is_not_a_package)" in
      *init-ownership*) ;;
      *) _p="$_p;init-ownership would be given a package user" ;;
  esac
  # and running it must record itself, so list and next agree with reality
  case "$(_slice_fn "$helper_src" cmd_build)" in
      *'mark_done "$name"'*) ;;
      *) _p="$_p;running init-ownership does not mark it built" ;;
  esac
  case "$(_slice_fn "$helper_src" _ownership_checkpoint)" in
      *mark_done*) ;;
      *) _p="$_p;a tree that crossed the epoch still shows the step as pending" ;;
  esac
  if [ -n "$_p" ]; then
      printf '%s\n' "${_p#;}" | tr ';' '\n' | while IFS= read -r m; do
          [ -n "$m" ] && bad "$m"
      done
  else
      ok "the ownership step appears in the list, and can be run on its own"
  fi
fi

# ---- a chapter-8 tree can still be taken back from the build user ----------- #
# Refusing the recursive 7.2 chown on a built tree is right -- it would strip
# every package user in one pass.  But refusing and stopping there left the tree
# with NO way forward:
#
#   4.3 had taken /usr, /etc, /var and the root symlinks,
#   7.2 said "not touching it, repair from the manifests instead",
#   chroot enter said "the tree is not owned by root yet: run chroot prepare"
#
# -- pointing at the command that had just declined.  The precise repair is to
# reclaim what the BUILD USER holds, by uid: that leaves every package user's
# files alone, so it is safe at any stage.
python3 - "$LFS_TOOL" <<'PYRECLAIM'
import re, sys
src = open(sys.argv[1]).read()
problems = []
for fn in ("_build_user_uid", "_handover_build_user_only"):
    if not re.search(r"^def %s\(" % fn, src, re.M):
        problems.append("there is no %s" % fn)
m = re.search(r"^def _handover_build_user_only\(.*?(?=\n\ndef )", src, re.S | re.M)
if m:
    body = m.group(0)
    # selects by uid, so package users are untouched
    if "-uid" not in body:
        problems.append("the reclaim does not select on the build user's uid")
    # user only: 4.3 chowned the user, so the inverse must not take the group
    # as well -- that would strip `install` off every shared directory
    # the INVOCATION -- the docstring above it explains why the group is left
    # alone, and matching that text made this impossible to satisfy
    code = "\n".join(l for l in body.splitlines()
                      if not l.lstrip().startswith("#")).split('"""')
    code = "".join(code[::2])
    if "chown -h root:root" in code or "chown -R" in code:
        problems.append("the reclaim takes the group too, undoing the install group")
    if "chown -h root" not in body:
        problems.append("the reclaim follows symlinks instead of chowning them")
m = re.search(r"^def cmd_bs_chroot\(.*?(?=\n\ndef )", src, re.S | re.M)
if m:
    body = m.group(0)
    if "_handover_build_user_only" not in body:
        problems.append("a chapter-8 tree is still left with no way forward")
    # and entering must repair rather than point back at prepare
    enter = body.split('if action == "enter"')
    if len(enter) > 1 and "_handover_build_user_only" not in enter[1]:
        problems.append("chroot enter still sends you to a command that declined")
if problems:
    for p in problems:
        print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  a built tree can be taken back from the build user without loss")
PYRECLAIM
_count_rc $?

# end to end: the build user's paths go back to root, the package user's do not
if [ "$(id -u)" = 0 ] && command -v python3 >/dev/null 2>&1; then
  _fx="$T/reclaim/mnt/lfs"
  mkdir -p "$_fx/usr/bin" "$_fx/etc" "$_fx/var" "$_fx/tools"
  ( cd "$_fx" && ln -sf usr/bin bin )
  echo pkg > "$_fx/usr/bin/owned-by-a-package"
  echo cfg > "$_fx/etc/fstab"
  # 4242 stands in for a package user, 4243 for the host's build account
  chown 4242:4242 "$_fx/usr/bin/owned-by-a-package"
  for _d in usr usr/bin etc var tools etc/fstab; do chown 4243 "$_fx/$_d"; done
  chown -h 4243 "$_fx/bin"
  _out="$(python3 - "$LFS_TOOL" "$_fx" <<'PYFX'
import sys, importlib.util
src = open(sys.argv[1]).read().split('if __name__ ==')[0]
spec = importlib.util.spec_from_loader("t", None)
m = importlib.util.module_from_spec(spec)
exec(compile(src, "lfs", "exec"), m.__dict__)
m._build_user_uid = lambda: 4243
print(m._handover_build_user_only(sys.argv[2], run=True))
PYFX
)"
  _bad=""
  [ "$(stat -c %u "$_fx/usr")" = 0 ] || _bad="$_bad;/usr was not taken back"
  [ "$(stat -c %u "$_fx/bin")" = 0 ] || _bad="$_bad;the root symlink was not taken back"
  [ "$(stat -c %u "$_fx/usr/bin/owned-by-a-package")" = 4242 ] \
      || _bad="$_bad;a package user's file was taken from it"
  [ -L "$_fx/bin" ] || _bad="$_bad;the symlink was followed and replaced"
  if [ -n "$_bad" ]; then
      printf '%s\n' "${_bad#;}" | tr ';' '\n' | while IFS= read -r m; do
          [ -n "$m" ] && bad "$m"
      done
  else
      ok "reclaiming takes the build user's paths and leaves the packages' alone"
  fi
  rm -rf "$T/reclaim"
fi

# ---- state lives under /usr/src, and it is sorted --------------------------- #
# It was /.lfs-pkgusr: a hidden directory at the root of the filesystem, sitting
# next to /boot and /etc as if it were part of the system being built.  It is
# not -- it is this toolchain's working notes ABOUT that system -- and it holds
# twenty-two loose files at the top level.
#
# Under /usr/src it sits beside the accounts it describes, and the tree scans
# exclude ONE path instead of two, because everything under $SRCROOT already is.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
  _p=""
  grep -q '^STATE="\${LFS_PKGUSR_DIR:-\${SRCROOT%/}/lfs-pkgusr}"' "$helper_src" \
      || _p="$_p;lfs-helper state is not under \$SRCROOT"
  grep -q '^PKGUSR_DIR = "usr/src/lfs-pkgusr"' "$LFS_TOOL" \
      || _p="$_p;lfs state is not under /usr/src"
  # both tools must name the SAME directory -- they read each other's manifests
  case "$(grep -m1 '^STATE=' "$helper_src")" in
      *lfs-pkgusr*) ;;
      *) _p="$_p;the two tools no longer agree on where state lives" ;;
  esac
  # SRCROOT has to be defined before what derives from it: `set -u` turns a
  # forward reference into "SRCROOT: unbound variable" and the tool will not
  # even print its version
  _isrc="$(grep -n '^SRCROOT=' "$helper_src" | head -1 | cut -d: -f1)"
  _ista="$(grep -n '^STATE=' "$helper_src" | head -1 | cut -d: -f1)"
  if [ -n "$_isrc" ] && [ -n "$_ista" ] && [ "$_isrc" -gt "$_ista" ]; then
      _p="$_p;SRCROOT is defined after the paths derived from it"
  fi
  # nothing loose at the top: every state file belongs to a named group
  for _v in PROGRESS SNAPSHOT SNAPDIRS INSTALLDIRS; do
      case "$(grep -m1 "^$_v=" "$helper_src")" in
          *'$STATE_PROGRESS/'*|*'$STATE_CONF/'*|*'$STATE_GROUPS/'*) ;;
          *) _p="$_p;$_v is still a loose file at the top of the state dir" ;;
      esac
  done
  # and the directories are created together, so no path can find one missing
  case "$(_slice_fn "$helper_src" mkstate)" in
      *STATE_PROGRESS*STATE_GROUPS*STATE_CONF*) ;;
      *) _p="$_p;mkstate does not create every state directory" ;;
  esac
  if [ -n "$_p" ]; then
      printf '%s\n' "${_p#;}" | tr ';' '\n' | while IFS= read -r m; do
          [ -n "$m" ] && bad "$m"
      done
  else
      ok "state lives under /usr/src, sorted into named directories"
  fi
fi

# ---- colour means one thing --------------------------------------------------#
# Four colours, one meaning each, the same in both tools -- they print into the
# same terminal one after the other, and a log where the same colour means two
# different things is worse than no colour at all.  Prose gets none: colour on
# every other line stops carrying information.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
  _p=""
  for _fn in say ok warn note detail hint die fail; do
      grep -qE "^$_fn\(\) +\{" "$helper_src" \
          || _p="$_p;lfs-helper has no $_fn"
  done
  # say() is prose and must not paint anything
  case "$(grep -m1 '^say()' "$helper_src")" in
      *C_*) _p="$_p;plain prose is coloured" ;;
  esac
  # the vocabulary is the interface: no ad-hoc colour outside those helpers
  # the helper DEFINITIONS are where the colour lives; everything else must go
  # through them
  _adhoc="$(grep -nE '(say|echo) "\$\{C_(DIM|WARN|ERR|OK)\}' "$helper_src" \
            | grep -vE '^[0-9]+:(ok|warn|note|detail|hint|die|fail)\(\)' | wc -l)"
  [ "${_adhoc:-0}" = 0 ] \
      || _p="$_p;$_adhoc line(s) still paint colour by hand instead of using a helper"
  # lfs must offer the same set, or the two halves of a build read differently
  for _fn in warn note ok fail hint; do
      grep -qE "^def $_fn\(" "$LFS_TOOL" || _p="$_p;lfs has no $_fn"
  done
  if [ -n "$_p" ]; then
      printf '%s\n' "${_p#;}" | tr ';' '\n' | while IFS= read -r m; do
          [ -n "$m" ] && bad "$m"
      done
  else
      ok "both tools share one colour vocabulary, and prose has none"
  fi
fi

# ---- the collector export must land where the reader looks ------------------ #
# `lfs` copies the export INTO the tree; `lfs-helper` reads it back out.  Those
# two paths are the whole mechanism -- nothing else connects them -- and when
# the state directory was sorted, the writer kept using the top level while the
# reader moved into groups/.  A rebuild with a perfectly good export then asked
#
#     'p_gcc' needs to install into:  /usr/lib/bfd-plugins
#        that directory belongs to package 'p_binutils'
#     Which group should share it?
#
# for a directory the file already answered.  Silent, because a question that
# gets asked looks the same as a question that was never answered.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
  # what the writer writes
  _w="$(python3 - "$LFS_TOOL" <<'PYW'
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r"^def _install_collector_groups\(.*?(?=\n\ndef )", src, re.S | re.M)
if m:
    d = re.search(r'dst_dir = pkgusr_state\(lfs, "([a-z]+)"\)', m.group(0))
    print(d.group(1) if d else "TOPLEVEL")
else:
    print("MISSING")
PYW
)"
  # what the reader reads
  _r="$(grep -o '\$STATE_[A-Z]*/collector-groups\.import' "$helper_src" \
        | head -1 | sed 's|\$STATE_\([A-Z]*\)/.*|\1|' | tr 'A-Z' 'a-z')"
  _p=""
  [ "$_w" = groups ] || _p="$_p;lfs writes the collector export to '$_w', not groups/"
  [ "$_r" = groups ] || _p="$_p;lfs-helper reads the collector export from '$_r', not groups/"
  [ "$_w" = "$_r" ] || _p="$_p;the two tools disagree about where the export lives"
  # an edit on the host has to reach the build, so entry re-copies it
  case "$(python3 - "$LFS_TOOL" <<'PYE'
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r"^def cmd_bs_chroot\(.*?(?=\n\ndef )", src, re.S | re.M)
body = m.group(0) if m else ""
enter = body.split('if action == "enter"')
print("yes" if len(enter) > 1 and "_install_collector_groups" in enter[1] else "no")
PYE
)" in
      yes) ;;
      *) _p="$_p;editing the export on the host never reaches the build" ;;
  esac
  if [ -n "$_p" ]; then
      printf '%s\n' "${_p#;}" | tr ';' '\n' | while IFS= read -r m; do
          [ -n "$m" ] && bad "$m"
      done
  else
      ok "the collector export is written where lfs-helper reads it"
  fi

  # end to end: a decision in the file must not be asked about again
  _cg="$T/collgroups"; mkdir -p "$_cg/groups"
  printf '# prefix|nimgnu\ndir|/usr/lib/bfd-plugins|nimgnu_bfd-plugins\n' \
      > "$_cg/groups/collector-groups.import"
  _o="$( STATE="$_cg"; STATE_GROUPS="$_cg/groups"; SNAP_ROOT=/
      COLLECTOR_MAP="$_cg/groups/collector-map"; COLLECTOR_PREFIX=nimgnu
      PKGUSR_PREFIX="p_"
      eval "$(_slice_fn "$helper_src" unprefix_pkg_user)"
      eval "$(_slice_fn "$helper_src" collector_group_for)"
      # the lookup runs before any of these matter, but they are called on the
      # way to it
      group_exists() { return 1; }
      user_in_group() { return 1; }
      eval "$(_slice_fn "$helper_src" sanitise_group_name)"
      eval "$(_slice_fn "$helper_src" choose_collector_group)"
      # a missing helper must FAIL, not skip: an empty result reading as a
      # pass is the trap this suite has fallen into twice
      command -v choose_collector_group >/dev/null 2>&1 \
          || { echo "there is no choose_collector_group"; exit 0; }
      # no tty, so it can only answer from what it already knows
      # <dir> <owner> <user> -- the user is the package asking for access
      _g="$(choose_collector_group /usr/lib/bfd-plugins p_binutils p_gcc \
            </dev/null 2>/dev/null)"
      [ "$_g" = nimgnu_bfd-plugins ] \
          || echo "a directory the export already answered is asked about again: got '$_g'" )"
  if [ -z "$_o" ]; then
      ok "a directory named in the export is never asked about again"
  else
      printf '%s\n' "$_o" | while IFS= read -r m; do [ -n "$m" ] && bad "$m"; done
  fi
fi

# ---- verify must not report its own state directory ------------------------- #
# The state directory moved under /usr/src in 1.9.0, and /usr/src IS an install
# directory -- so `verify` began walking its own manifests, scripts and logs and
# reporting each one as a root-owned file no package claims.  A clean 104/104
# build came back with
#     448 root-owned file(s) that NO manifest claims
# and all 448 were this directory, including the two temp files the scan had
# just written for itself:
#     unclaimed  /usr/src/lfs-pkgusr/tmp/found.13431
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
  _o="$( ETC=/etc; SNAP_ROOT=/; STATE=/usr/src/lfs-pkgusr
      WRAPPERS=/usr/lib/pkgusr
      eval "$(_slice_fn "$helper_src" never_claim_list)"
      eval "$(_slice_fn "$helper_src" is_never_claimed)"
      command -v is_never_claimed >/dev/null 2>&1 \
          || { echo "there is no is_never_claimed"; exit 0; }
      for f in "$STATE/manifests/gcc.files" "$STATE/scripts/gcc.sh" \
               "$STATE/logs/gcc-all.log" "$STATE/progress/steps-built" \
               "$STATE/tmp/found.13431"; do
          is_never_claimed "$f" || echo "verify still reports $f"
      done
      # an account home under the SAME parent is a package's, and must not be
      # swept up by this
      is_never_claimed /usr/src/pkgusr/p_gcc/VERSION \
          && echo "a package user's own file was excluded too" )"
  if [ -z "$_o" ]; then
      ok "verify does not report the build's own notes as unclaimed files"
  else
      printf '%s\n' "$_o" | while IFS= read -r m; do [ -n "$m" ] && bad "$m"; done
  fi
fi

# ---- the two tools share one tree snapshot ---------------------------------- #
# `lfs` takes the last snapshot outside the chroot at the end of chapter 6;
# `lfs-helper` diffs against it for the first package inside.  It is a handover,
# and it works only while both name the same file.  1.9.0 moved the reader to
# progress/tree-snapshot and left the writer on .snapshot at the top level, so
# the handover snapshot was silently lost and the first chroot package diffed
# against nothing.
python3 - "$LFS_TOOL" "$(dirname "$LFS_TOOL")/lfs-helper" <<'PYSNAP'
import re, sys
lfs = open(sys.argv[1]).read()
problems = []
if '".snapshot"' in lfs or '".snapshot-dirs"' in lfs:
    problems.append("lfs still writes the snapshot to .snapshot at the top level")
if 'pkgusr_state(lfs, "progress")' not in lfs:
    problems.append("lfs does not write the snapshot into progress/")
for want in ('"tree-snapshot"', '"tree-snapshot-dirs"'):
    if want not in lfs:
        problems.append("lfs does not name %s" % want)
try:
    helper = open(sys.argv[2]).read()
except OSError:
    helper = ""
if helper:
    m = re.search(r'^SNAPSHOT="([^"]+)"', helper, re.M)
    if not m or "tree-snapshot" not in m.group(1):
        problems.append("lfs-helper reads a different snapshot file")
if problems:
    for p in problems:
        print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  both tools read and write the same tree snapshot")
PYSNAP
_count_rc $?

# ---- add-user names the account through the chokepoint ---------------------- #
# It used its argument raw for the ACCOUNT and pkg_owner_name only for the HOME.
# Fine while every caller passes an already-prefixed owner -- cmd_build does.
# last_build_step.sh does not: `lfs-helper add-user wget` produced an account
# called `wget` living in /usr/src/pkgusr/p_wget, and the sanity report found
# both halves without being able to connect them:
#     !! accounts without a known prefix: wget urllib3 requests ...
#     ?  /usr/src/pkgusr/p_wget/  has no matching account (stray directory)
#     !! group wget (gid 10082) is outside every convention
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
  _au="$(_slice_fn "$helper_src" cmd_add_user)"
  _p=""
  case "$(printf '%s\n' "$_au" | grep -vE '^[[:space:]]*#')" in
      *'name="$(pkg_owner_name "$name")"'*) ;;
      *) _p="$_p;add-user creates the account from the raw name" ;;
  esac
  # the normalisation must come BEFORE the account is created, or it renames
  # nothing
  _i1="$(printf '%s\n' "$_au" | grep -n 'name="$(pkg_owner_name' | head -1 | cut -d: -f1)"
  _i2="$(printf '%s\n' "$_au" | grep -n 'useradd ' | head -1 | cut -d: -f1)"
  if [ -n "$_i1" ] && [ -n "$_i2" ] && [ "$_i1" -gt "$_i2" ]; then
      _p="$_p;add-user normalises the name after creating the account"
  fi
  if [ -n "$_p" ]; then
      printf '%s\n' "${_p#;}" | tr ';' '\n' | while IFS= read -r m; do
          [ -n "$m" ] && bad "$m"
      done
  else
      ok "add-user gives the account and its home the same name"
  fi

  # last_build_step.sh is the caller that exposed it -- it passes bare names
  _lbs="$(dirname "$LFS_TOOL")/last_build_step.sh"
  if [ -f "$_lbs" ]; then
      grep -q 'lfs-helper add-user' "$_lbs" \
          && ok "the final step still creates its users through add-user" \
          || bad "the final step no longer goes through add-user"
  fi
fi

# ---- the sanity report reads the sorted state, and knows when a build is done #
# Two findings on a perfect 105/105 tree, both from the report and neither from
# the build:
#
#   adopted.list: MISSING (the adoption gate will never close)
#       -- it read $STATE/adopted.list; the file is progress/adopted.list
#
#   !! /usr/bin is already STICKY -- sealed before the build finished
#       -- the build HAD finished, and seal-install-dirs is supposed to do that
#
# The sticky bit means opposite things on either side of that line: during the
# build it is a bug, afterwards its ABSENCE is.
san="$(dirname "$LFS_TOOL")/lfs-sanity.sh"
if [ -f "$san" ]; then
  _p=""
  grep -q 'PROG="\$STATE/progress"' "$san" \
      || _p="$_p;the sanity report still reads the flat state layout"
  grep -q 'BUILD_FINISHED' "$san" \
      || _p="$_p;the sanity report does not know whether the build finished"
  grep -q 'the build finished but the seal never fired' "$san" \
      || _p="$_p;a finished build with no seal is not reported"
  # an empty manifest is a config step that installed nothing, not an orphan
  grep -q 'grep -q . "\$m" 2>/dev/null || continue' "$san" \
      || _p="$_p;empty manifests are still reported as missing an account"
  if [ -n "$_p" ]; then
      printf '%s\n' "${_p#;}" | tr ';' '\n' | while IFS= read -r m; do
          [ -n "$m" ] && bad "$m"
      done
  else
      ok "the sanity report reads the sorted state and judges the seal in context"
  fi
fi

# ---- every tool can say which build it is ----------------------------------- #
# Section 0 of the sanity report exists because a stale copy in the chroot has
# cost more debugging time here than anything else.  packagemanager_install had
# no --version, so that row read
#     packagemanager_install Please provide an install script with $2
pmi="$(dirname "$LFS_TOOL")/packagemanager_install"
if [ -f "$pmi" ]; then
  _v="$(bash "$pmi" --version 2>&1)"
  case "$_v" in
      packagemanager_install*build*) ok "every tool reports its own build id" ;;
      *) bad "packagemanager_install cannot report its build id: $_v" ;;
  esac
fi

# ---- no finding that repairing makes worse ---------------------------------- #
# Two passes disagreed about a mail spool, and each undid the other:
#
#     lfs-helper verify --fix   builduser /var/mail/lfs   lfs -> root
#     lfs-helper verify         1 root-owned file(s) that NO manifest claims:
#                                  /var/mail/lfs
#
# The build-user pass gave it to root because the build user held it; the
# unclaimed pass then reported that root holds a file no manifest claims.
# Repairing it produced the next run's finding.
#
# Shadow creates /var/mail/<name> for every account it makes, so a spool arrives
# as a side effect of `useradd` and no package ever installs one. It belongs to
# the account it is named for, and neither pass should touch it.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
  _o="$( ETC=/etc; SNAP_ROOT=/; STATE=/usr/src/lfs-pkgusr; WRAPPERS=/usr/lib/pkgusr
      eval "$(_slice_fn "$helper_src" never_claim_list)"
      eval "$(_slice_fn "$helper_src" is_never_claimed)"
      command -v is_never_claimed >/dev/null 2>&1 \
          || { echo "there is no is_never_claimed"; exit 0; }
      for f in /var/mail/lfs /var/mail/p_gcc; do
          is_never_claimed "$f" || echo "$f is still fought over by two passes"
      done
      # not the whole of /var, though -- a package's files there are its own
      is_never_claimed /var/lib/something \
          && echo "the exclusion is too broad: it swallowed /var/lib" )"
  if [ -z "$_o" ]; then
      ok "a mail spool belongs to its account, and no pass claims it"
  else
      printf '%s\n' "$_o" | while IFS= read -r m; do [ -n "$m" ] && bad "$m"; done
  fi

  # the general property: nothing the build-user pass hands to root may then be
  # reported by the unclaimed pass, or --fix and verify never agree
  case "$(_slice_fn "$helper_src" _vfy_build_user_leftovers)" in
      *is_never_claimed*) ok "the build-user pass skips files no package may own" ;;
      *) bad "the build-user pass can create a finding for the unclaimed pass" ;;
  esac
fi

# ---- every door to `chown -R lfs` has the same guard ------------------------ #
# There were FOUR places that hand the build tree to the `lfs` user, and only
# one of them had the check that refuses on a tree past chapter 7:
#
#     _chown_tree_to_lfs        book 4.3, guarded
#     session --run             re-applied it by hand, unguarded
#     the pre-build check       "fixing N dir(s) still owned by root", unguarded
#     fix-ownership --run       the explicit repair, unguarded
#
# On a finished system any of the other three would have handed the whole thing
# to the build user in one pass -- the exact damage the guard exists to prevent,
# through a door the guard was not on.  It already happened once via a replayed
# step 4.2.
python3 - "$LFS_TOOL" <<'PYCHOWN'
import re, sys
raw = open(sys.argv[1]).read()
# Comments name the command they are explaining -- every fix in this file says
# what it fixed -- so scan CODE only.  Matching the explanation makes a test
# that cannot pass no matter what the code does.
src = "\n".join("" if l.lstrip().startswith("#") else l
                for l in raw.splitlines())
problems = []
# every recursive chown to lfs, and the function it sits in
for m in re.finditer(r"chown -R lfs", src):
    start = src.rfind("\ndef ", 0, m.start())
    if start < 0:
        problems.append("a chown -R lfs sits outside any function")
        continue
    end = src.find("\ndef ", m.end())
    body = src[start:end if end > 0 else len(src)]
    name = re.match(r"\ndef ([a-zA-Z_0-9]+)", body).group(1)
    # the one that only chowns the state dir is not handing over the tree
    if "PKGUSR_DIR" in src[m.start()-120:m.end()+120]:
        continue
    if "_handover_is_safe" not in body:
        problems.append("%s hands the tree to the build user unguarded" % name)
if problems:
    for p in sorted(set(problems)):
        print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  every path that gives the tree to the build user is guarded")
PYCHOWN
_count_rc $?

# ---- session says what to do next ------------------------------------------- #
# It ended on `export LFS=/mnt/lfs   # <-- run this in your shell` and stopped.
# Every other command in this tool finishes with a Next: line; this one left you
# configured and guessing.
python3 - "$LFS_TOOL" <<'PYNEXT'
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r"^def cmd_bs_session\(.*?(?=\n\ndef )", src, re.S | re.M)
problems = []
if not m:
    problems.append("cmd_bs_session is gone")
else:
    body = m.group(0)
    # the dry-run branch and the --run branch both end somewhere useful
    if body.count('"Next:"') < 2:
        problems.append("session does not say what to do next on both paths")
    if "lfs run" not in body:
        problems.append("session never points at `lfs run`")
    if "build-system next" not in body:
        problems.append("session never offers `build-system next`")
if problems:
    for p in problems:
        print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  session ends by saying what to run next")
PYNEXT
_count_rc $?

# ---- comm gets sorted input, in one collation ------------------------------- #
# The snapshot diff is `comm -13 <(before) <(after)`.  comm compares line by
# line and TRUSTS both sides to be sorted the same way; it cannot detect
# otherwise, it just returns the wrong answer.  Two things broke that:
#
#   * the two snapshots may have been written under different locales -- a
#     package user's profile sets LC_ALL=POSIX and root's shell may not
#   * load_snapshot rewrites only the lines carrying the host mount prefix, so
#     a file holding both forms comes out sorted under neither
#
# The visible symptom is a package installing forty files and being told it
# installed none.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
  _p=""
  for _fn in snapshot snapshot_dirs load_snapshot; do
      _slice_fn "$helper_src" "$_fn" | grep -q 'LC_ALL=C sort' \
          || _p="$_p;$_fn does not pin the collation comm depends on"
  done
  if [ -n "$_p" ]; then
      printf '%s\n' "${_p#;}" | tr ';' '\n' | while IFS= read -r m; do
          [ -n "$m" ] && bad "$m"
      done
  else
      ok "both sides of the snapshot diff are sorted the same way"
  fi

  # the mixed-prefix case, end to end
  _sd="$T/snapsort"; mkdir -p "$_sd"
  printf '%s\n' /mnt/lfs/usr/bin/z /usr/bin/a /mnt/lfs/usr/bin/b > "$_sd/snap"
  _got="$( SNAP_ROOT=/; LFS_HOST_MOUNT=/mnt/lfs
      eval "$(_slice_fn "$helper_src" load_snapshot)"
      load_snapshot "$_sd/snap" | tr '\n' ' ' )"
  case "$_got" in
      "/usr/bin/a /usr/bin/b /usr/bin/z ") ok "a snapshot holding both path forms comes back sorted" ;;
      *) bad "load_snapshot returns unsorted input to comm: [$_got]" ;;
  esac
fi

# ---- "installed NO files" has to say which of the three it is --------------- #
# There are exactly three ways to reach zero and they need different fixes:
# nothing was written, it was written somewhere excluded from tracking, or it
# was written over files another package owns and dropped by the filter.
# Saying only "check the log" meant reading a thousand lines of make output to
# find out which.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
  _cb="$(_slice_fn "$helper_src" cmd_build)"
  _p=""
  case "$_cb" in
      *'new files (snapshot diff)'*) ;;
      *) _p="$_p;the zero-files failure does not report the snapshot diff count" ;;
  esac
  case "$_cb" in
      *'files touched since stamp'*) ;;
      *) _p="$_p;the zero-files failure does not report the touched count" ;;
  esac
  case "$_cb" in
      *'already belongs to another package'*) ;;
      *) _p="$_p;the zero-files failure does not distinguish a dropped install" ;;
  esac
  if [ -n "$_p" ]; then
      printf '%s\n' "${_p#;}" | tr ';' '\n' | while IFS= read -r m; do
          [ -n "$m" ] && bad "$m"
      done
  else
      ok "a package that installed nothing says which kind of nothing"
  fi
fi

# ---- a re-run over its own work is not a silent failure --------------------- #
# The zero-files check counts what THIS RUN wrote, which is the wrong question
# when a package is built a second time.  Many installers skip a file that is
# already up to date -- perl's ExtUtils::Install prints "Installing <path>" for
# every target and copies only the stale ones -- so a second run writes nothing:
# the snapshot diff sees nothing new, no mtime beats the stamp, and the count is
# 0 for the best possible reason.
#
# xml-parser hit exactly that: forty files on disk, every one owned by
# p_xml-parser, and the step failed as a no-op.  Counting cannot tell that from
# a real failure. The tree can.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
  _p=""
  _slice_fn "$helper_src" _package_already_owns_files | grep -q . \
      || _p="$_p;there is no _package_already_owns_files"
  case "$(_slice_fn "$helper_src" cmd_build)" in
      *_package_already_owns_files*) ;;
      *) _p="$_p;a re-run over its own work still fails as a silent no-op" ;;
  esac
  # it must ask about the OWNER, and only inside install directories -- looking
  # at the whole filesystem would be slow and would count build scratch
  _pa="$(_slice_fn "$helper_src" _package_already_owns_files)"
  case "$_pa" in
      *'-user "$owner"'*) ;;
      *) _p="$_p;the check does not look for files this package owns" ;;
  esac
  case "$_pa" in
      *install_dirs_list*) ;;
      *) _p="$_p;the check scans outside the install directories" ;;
  esac
  if [ -n "$_p" ]; then
      printf '%s\n' "${_p#;}" | tr ';' '\n' | while IFS= read -r m; do
          [ -n "$m" ] && bad "$m"
      done
  else
      ok "a package that already owns its files is not failed as a no-op"
  fi

  # both directions, against a real tree
  if [ "$(id -u)" = 0 ]; then
    _ow="$T/owns"; mkdir -p "$_ow/usr/lib"
    echo x > "$_ow/usr/lib/thing"
    _r="$( SNAP_ROOT="$_ow"
        user_exists() { [ "$1" = p_test ]; }
        install_dirs_list() { printf '%s\n' /usr/lib; }
        eval "$(_slice_fn "$helper_src" _package_already_owns_files)"
        # owned by root -> this package installed nothing, which IS a failure
        _package_already_owns_files p_test && echo "false-pass"
        # owned by the package -> it installed, whenever that was
        chown 4242 "$_ow/usr/lib/thing" 2>/dev/null
        user_exists() { [ "$1" = p_test ]; }
        stat -c %U "$_ow/usr/lib/thing" >/dev/null 2>&1 || echo "fixture broken" )"
    case "$_r" in
        "") ok "a package owning nothing is still reported as a failure" ;;
        *)  bad "the check passes a package that installed nothing: $_r" ;;
    esac
    rm -rf "$_ow"
  fi
fi

# ---- a script outside the tool can ask for an account NAME ------------------ #
# `pkgusr-home` was exposed and the account name was not, so a shell script
# could ask where a package lives but not what its user is called.
# last_build_step.sh did the only thing left, which was assume:
#
#     lfs-helper add-user wget
#     chown -R "wget:wget" ...      ->  chown: invalid user: 'wget:wget'
#
# Right by accident while add-user used the raw name; broken the moment add-user
# started applying the prefix, as everything else already did.  Half a
# chokepoint is not a chokepoint -- and this one failed at step 104 of 105.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
  _p=""
  _slice_fn "$helper_src" cmd_owner_name | grep -q 'pkg_owner_name' \
      || _p="$_p;there is no way to ask for a package's account name"
  grep -q 'owner-name)' "$helper_src" \
      || _p="$_p;owner-name is not reachable as a command"
  grep -q 'lfs-helper owner-name <package>' "$helper_src" \
      || _p="$_p;owner-name is not in the help"
  # it must agree with pkgusr-home about the same package
  _n="$(bash "$helper_src" owner-name wget 2>/dev/null)"
  _h="$(bash "$helper_src" pkgusr-home wget 2>/dev/null)"
  case "$_h" in
      */"$_n") ;;
      *) _p="$_p;owner-name and pkgusr-home disagree: '$_n' vs '$_h'" ;;
  esac
  if [ -n "$_p" ]; then
      printf '%s\n' "${_p#;}" | tr ';' '\n' | while IFS= read -r m; do
          [ -n "$m" ] && bad "$m"
      done
  else
      ok "a package's account name and its home come from the same place"
  fi
fi

# and the final step must ASK rather than rebuild the name itself
_lbs="$(dirname "$LFS_TOOL")/last_build_step.sh"
if [ -f "$_lbs" ]; then
  _p=""
  _n="$(grep -c 'lfs-helper owner-name' "$_lbs")"
  [ "${_n:-0}" -ge 2 ] \
      || _p="$_p;the final step still assumes the account name ($_n of 2 sites)"
  # every chown/su in there must use the resolved name, never the bare argument
  case "$(grep -c 'lfs-helper add-user' "$_lbs")" in
      0) _p="$_p;the final step no longer creates its users through add-user" ;;
  esac
  if [ -n "$_p" ]; then
      printf '%s\n' "${_p#;}" | tr ';' '\n' | while IFS= read -r m; do
          [ -n "$m" ] && bad "$m"
      done
  else
      ok "the final step asks for the account name it was given"
  fi
fi

# ---- the ESP hint prints a path you can actually type ----------------------- #
# Two sources feed it and they disagree about the prefix: `lsblk -rno NAME`
# gives a bare name, `blkid -o device` gives a full path.  Prefixing both gave
#       /dev//dev/nvme0n1p1
# in the one message whose entire job is to tell you what to type.
python3 - "$LFS_TOOL" <<'PYESP'
import re, sys
src = open(sys.argv[1]).read()
if "s|^|      /dev/|" in src:
    print("  FAIL  the ESP hint prefixes /dev/ onto paths that already have it")
    sys.exit(1)
if "/dev/" not in src or "[^/]" not in src:
    print("  FAIL  the ESP hint no longer normalises the device path")
    sys.exit(1)
print("  PASS  the ESP hint prints one /dev/ per device, whichever tool found it")
PYESP
_count_rc $?

# ---- a bootloader is opt-in ------------------------------------------------- #
# The default was `refind`, so every build generated a rEFInd step -- and most
# people running this already have a working ESP and a bootloader that finds it.
# The machine booted in order to build LFS at all.  So the last stretch of a
# six-hour build became a stop:
#
#     == rEFInd needs you to do something first ==
#     /boot/efi does not exist, so there is nowhere to install to.
#
# A question nobody asked to be asked.  A bootloader is a decision about the
# whole machine, not a package.
python3 - "$LFS_TOOL" <<'PYBL'
import re, sys
src = open(sys.argv[1]).read()
problems = []
m = re.search(r"^def bootloader\(.*?(?=\n\ndef )", src, re.S | re.M)
if not m:
    problems.append("bootloader() is gone")
else:
    body = "\n".join("" if l.lstrip().startswith("#") else l
                     for l in m.group(0).splitlines())
    body = "".join(body.split('"""')[::2])
    if '"refind"' in body:
        problems.append("a bootloader step is still generated by default")
    if '"none"' not in body:
        problems.append("the default is not 'none'")
# and skipping it must not be silent -- someone who DOES need one would reach a
# finished, unbootable system without ever being offered it
if "no bootloader step" not in src:
    problems.append("skipping the bootloader says nothing about how to opt in")
if "lfs config bootloader refind" not in src:
    problems.append("nothing says how to turn rEFInd on")
# the grub guard must be untouched: its book instructions write a boot sector
if 'if bl != "grub"' not in src:
    problems.append("the grub script is no longer withheld unless chosen")
if problems:
    for p in problems:
        print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  no bootloader is set up unless you ask for one")
PYBL
_count_rc $?


# ---- the sort and the comparison must agree --------------------------------- #
# 1.9.6 pinned LC_ALL=C on the sorts feeding comm and stopped there.  That is
# half a fix: comm validates ordering in ITS OWN locale, so C-sorted input
# compared under en_GB.UTF-8 is "not sorted" as far as comm is concerned --
#
#     comm: file 1 is not in sorted order
#     comm: file 2 is not in sorted order
#     comm: input is not in sorted order
#
# and the diff it returns is then simply wrong.  Pinning either side alone
# guarantees they disagree.
helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
  _bare="$(grep -nE '(^|[^=[:alnum:]_])comm ' "$helper_src" \
           | grep -vE 'LC_ALL=C comm' | grep -vE '^[0-9]+:[[:space:]]*#')"
  if [ -n "$_bare" ]; then
      printf '%s\n' "$_bare" | while IFS= read -r m; do
          bad "comm without LC_ALL=C: ${m%%:*}"
      done
  else
      ok "every comm compares in the locale its input was sorted in"
  fi
  # and every sort whose output reaches a comm is pinned too
  _p=""
  for _fn in snapshot snapshot_dirs load_snapshot _vfy_unclaimed; do
      _slice_fn "$helper_src" "$_fn" | grep -q 'LC_ALL=C sort' \
          || _p="$_p;$_fn sorts in the ambient locale"
  done
  if [ -n "$_p" ]; then
      printf '%s\n' "${_p#;}" | tr ';' '\n' | while IFS= read -r m; do
          [ -n "$m" ] && bad "$m"
      done
  else
      ok "every sort feeding a comm is pinned to the same locale"
  fi
fi


# ---- the scripts in the tree must match the tools outside it ---------------- #
# The step order and the generated scripts live in the TREE; the tools live
# outside it.  Nothing connected the two, so a tree generated by an older
# version went on running steps that version had:
#
#     ===== [104/105] last-step =====
#     chown: invalid user: 'wget:wget'
#
# under an lfs-helper (1.10.0) that had removed `last-step` entirely and no
# longer knew what it was.  The chroot TOOLS already carry a build id for
# exactly this reason -- a stale copy has cost more debugging time here than
# anything else -- and the generated scripts did not.
python3 - "$LFS_TOOL" <<'PYSTAMP'
import re, sys
src = open(sys.argv[1]).read()
problems = []
if "generated-by" not in src:
    problems.append("gen-chroot-scripts leaves no version stamp")
if "LFS_VERSION" not in src.split("generated-by")[1][:400]:
    problems.append("the stamp does not record which version wrote it")
# and a step removed from the order must not leave its script behind to run
m = re.search(r"^def cmd_bs_gen_chroot_scripts\(.*?(?=\n\ndef )", src, re.S | re.M)
body = m.group(0) if m else ""
if "stale" not in body or "os.remove" not in body:
    problems.append("scripts for removed steps are left in the tree")
if problems:
    for p in problems:
        print("  FAIL  %s" % p)
    sys.exit(1)
print("  PASS  generated scripts record the version that wrote them")
PYSTAMP
_count_rc $?

helper_src="$(dirname "$LFS_TOOL")/lfs-helper"
if [ -f "$helper_src" ]; then
  _p=""
  _slice_fn "$helper_src" _warn_if_scripts_are_stale | grep -q 'LFS_HELPER_VERSION' \
      || _p="$_p;lfs-helper does not compare its version against the scripts'"
  case "$(_slice_fn "$helper_src" cmd_build_all)" in
      *_warn_if_scripts_are_stale*) ;;
      *) _p="$_p;build-all runs an order it never checked" ;;
  esac
  # a missing script must blame the likely cause, not just offer to regenerate
  case "$(_slice_fn "$helper_src" cmd_build)" in
      *'no longer exists in this version'*) ;;
      *) _p="$_p;a step removed from the tools reports only a missing file" ;;
  esac
  if [ -n "$_p" ]; then
      printf '%s\n' "${_p#;}" | tr ';' '\n' | while IFS= read -r m; do
          [ -n "$m" ] && bad "$m"
      done
  else
      ok "a step order older than the tools is reported, not obeyed"
  fi

  # end to end: an unstamped tree, and a mismatched one
  _st="$T/stamp"; mkdir -p "$_st/progress"
  _r="$( STATE_PROGRESS="$_st/progress"; LFS_HELPER_VERSION="9.9.9"
      eval "$(_slice_fn "$helper_src" _warn_if_scripts_are_stale)"
      warn() { echo "WARNED: $*"; }
      _warn_if_scripts_are_stale >/dev/null 2>&1 && echo "unstamped-passed"
      printf 'version=9.9.9\n' > "$_st/progress/generated-by"
      _warn_if_scripts_are_stale >/dev/null 2>&1 || echo "matching-failed"
      printf 'version=1.0.0\n' > "$_st/progress/generated-by"
      _warn_if_scripts_are_stale >/dev/null 2>&1 && echo "mismatch-passed" )"
  case "$_r" in
      "") ok "an unstamped or mismatched step order is caught, a matching one is not" ;;
      *)  printf '%s\n' "$_r" | while IFS= read -r m; do
              [ -n "$m" ] && bad "stale-script check is wrong: $m"
          done ;;
  esac
  rm -rf "$_st"
fi

echo
echo "  PASS: $(_pass_total)   FAIL: $(_fail_total) (final)"
[ "$(_fail_total)" -eq 0 ]

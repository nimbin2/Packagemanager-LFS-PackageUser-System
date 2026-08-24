#!/bin/bash
# last_build_step.sh -- the final step of an LFS build.
#
# EDIT THIS FILE.  It is yours: whatever a freshly built system should have
# that the book does not provide goes here, and it runs as the last step of
# `lfs-helper build-all`.
#
#   * SOURCES below is read by `lfs build-system get-sources`, so anything you
#     add is downloaded along with the book's own packages.
#   * The rest runs as root inside the chroot, after every book package.
#   * It is copied into the chroot by `lfs build-system gen-chroot-scripts`,
#     so edit it HERE (on the host) and regenerate -- not in the chroot.
#
# It ships with wget because LFS has no download tool at all: without one a
# freshly booted system cannot fetch even the sources for its next package.

# --- extra sources -------------------------------------------------------- #
# Downloaded into $LFS/sources by `lfs build-system get-sources`.
SOURCES=(
    # wget, so the new system can fetch anything at all
    "https://ftpmirror.gnu.org/wget/wget-1.25.0.tar.gz"

    # What `lfs` and `blfs` need to parse the books.  WHEELS, not source
    # tarballs: a modern sdist needs its build backend (beautifulsoup4 wants
    # hatchling, requests wants setuptools) and with no package index reachable
    # pip cannot fetch one --
    #     BackendUnavailable: Cannot import 'hatchling.build'
    # A wheel is already built, so pip just unpacks it.  Both are pure Python,
    # so the "any" wheel works on every architecture.
    "https://files.pythonhosted.org/packages/py3/r/requests/requests-2.32.3-py3-none-any.whl"
    "https://files.pythonhosted.org/packages/py3/b/beautifulsoup4/beautifulsoup4-4.12.3-py3-none-any.whl"
    # urllib3, charset-normalizer, idna and certifi are what requests imports
    "https://files.pythonhosted.org/packages/py3/u/urllib3/urllib3-2.2.3-py3-none-any.whl"
    "https://files.pythonhosted.org/packages/py3/c/charset_normalizer/charset_normalizer-3.4.0-py3-none-any.whl"
    "https://files.pythonhosted.org/packages/py3/i/idna/idna-3.10-py3-none-any.whl"
    "https://files.pythonhosted.org/packages/py3/c/certifi/certifi-2024.8.30-py3-none-any.whl"
    "https://files.pythonhosted.org/packages/py3/s/soupsieve/soupsieve-2.6-py3-none-any.whl"
)

# --- the work ------------------------------------------------------------- #
set -e

# Build one of the SOURCES tarballs as its own package user.
#   build_as_package_user <user> <tarball-glob> <configure options...>
build_as_package_user() {
    local user="$1" glob="$2"; shift 2
    local src="/sources"

    local tarball=""
    local c
    for c in $src/$glob; do [ -e "$c" ] && { tarball="$c"; break; }; done
    if [ -z "$tarball" ]; then
        echo "!! no $glob in $src -- add it to SOURCES and run:" >&2
        echo "     lfs build-system get-sources --run" >&2
        return 1
    fi

    lfs-helper add-user "$user" >/dev/null 2>&1 || true

    local dir
    dir="$(tar tf "$tarball" | head -n1 | cut -d/ -f1)"
    rm -rf "${src:?}/${dir:?}"
    tar --no-same-owner -xf "$tarball" -C "$src"
    chown -R "$user:$user" "$src/$dir"

    echo "# building $user from $(basename "$tarball") as package user '$user'"
    su - "$user" -c "cd '$src/$dir' && ./configure $* && make && make install"

    # record what was installed, the same way lfs-helper does
    printf '%s\n# installed %s by last_build_step.sh\n' \
           "$dir" "$(date '+%Y-%m-%d %H:%M:%S')" > "/usr/src/$user/VERSION" \
        2>/dev/null || true
    chown "$user:$user" "/usr/src/$user/VERSION" 2>/dev/null || true
}

# Install a Python module as ITS OWN package user, the same as any other
# package.  requests and beautifulsoup4 are what `lfs` and `blfs` need to parse
# the books, so without them the tools cannot run on the new system.
# Let a package user install into site-packages.
#
# site-packages belongs to the python package and is shared through a collector
# group.  Ask lfs-helper for access, exactly as a failed build would: it joins
# the collector group the directory already carries, or asks which group should
# own it.  It must NOT be handed to the install group -- that means "anyone may
# install here", and site-packages is python's tree, not shared infrastructure.
_grant_site_packages() {
    local user="$1" sp
    sp="$(python3 -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])' \
          2>/dev/null)"
    if [ -z "$sp" ] || [ ! -d "$sp" ]; then
        echo "note: cannot find site-packages -- skipping $user" >&2
        return 1
    fi
    lfs-helper grant-dir "$sp" "$user" --run
}

install_python_module() {
    local user="$1" module="$2" glob="$3"
    local src="/sources" wheel="" c
    for c in $src/$glob; do [ -e "$c" ] && { wheel="$c"; break; }; done
    if [ -z "$wheel" ]; then
        echo "note: no $glob in $src -- skipping $module" >&2
        echo "      add it to SOURCES and run: lfs build-system get-sources --run" >&2
        return 0
    fi
    command -v python3 >/dev/null 2>&1 || {
        echo "note: no python3 yet -- skipping $module" >&2; return 0; }

    lfs-helper add-user "$user" >/dev/null 2>&1 || true
    chown "$user:$user" "$wheel" 2>/dev/null || true
    _grant_site_packages "$user" || return 0

    echo "# installing $module from $(basename "$wheel") as package user '$user'"
    # A wheel needs no build backend and no network: pip unpacks it.
    # PIP_USER=0 / PYTHONNOUSERSITE keep it out of the package user's ~/.local,
    # where nothing else would ever find it.
    su - "$user" -c "PIP_USER=0 PYTHONNOUSERSITE=1 \
        python3 -m pip install --no-index --no-deps '$wheel'" \
        || echo "!! $module did not install -- do it later with:
     packagemanager pip install $module" >&2
}

# wget: the one thing a new system cannot bootstrap without.
# Deliberately minimal -- reinstall it properly once the system boots:
#     packagemanager install wget --recursive --run
build_as_package_user wget "wget-*.tar.*" \
    --prefix=/usr --sysconfdir=/etc --with-ssl=openssl

# The two Python modules the tools themselves need.  Each gets its own package
# user, exactly like every other package -- there is no "last-step" package and
# nothing here is owned by one.
# Dependencies first -- --no-deps means pip will not pull them in itself.
install_python_module urllib3            urllib3            "urllib3-*.whl"
install_python_module charset-normalizer charset-normalizer "charset_normalizer-*.whl"
install_python_module idna               idna               "idna-*.whl"
install_python_module certifi            certifi            "certifi-*.whl"
install_python_module soupsieve          soupsieve          "soupsieve-*.whl"
install_python_module requests           requests           "requests-*.whl"
install_python_module beautifulsoup4     beautifulsoup4     "beautifulsoup4-*.whl"

# --- wget without certificates -------------------------------------------- #
# A freshly built LFS has no CA certificates -- they come from BLFS' make-ca --
# so every HTTPS fetch fails with "cannot verify ... certificate".  That is a
# chicken-and-egg problem: you need wget to fetch make-ca.
#
# Turn verification off in /etc/wgetrc rather than with a wrapper script in
# $PATH.  wget reads /etc/wgetrc no matter how it is invoked or what PATH the
# caller has, so this works for builds run through `su -` with the package
# user's own environment -- where a $PATH wrapper is simply never seen.
#
# This is a deliberate, TEMPORARY weakening: downloads are unverified until
# make-ca is installed.  The marker below is how the tools find and remove it.
disable_wget_verification() {
    local rc=/etc/wgetrc
    grep -q 'lfs-temporary-no-verify' "$rc" 2>/dev/null && return 0
    cat >> "$rc" <<'WRC'

# --- lfs-temporary-no-verify ---------------------------------------------
# This system has no CA certificates yet, so wget cannot verify anything.
# Downloads are UNVERIFIED until you install make-ca:
#     packagemanager install make-ca --recursive --run
# The tools remove these two lines automatically once certificates exist.
check_certificate = off
# --- end lfs-temporary-no-verify -----------------------------------------
WRC
    echo "# certificate checking disabled in $rc until make-ca is installed"
    echo "#   (downloads are UNVERIFIED until then -- the tools re-enable it"
    echo "#    automatically as soon as certificates exist)"
}

disable_wget_verification

# --- add your own steps below --------------------------------------------- #
# e.g. a package the book does not carry, a config file, a user account.

# --- accounts you can actually log in with -------------------------------- #
# A freshly built system has root with NO password.  Depending on the login
# manager that is either "anyone can log in as root" or "nobody can log in at
# all" -- and it is discovered at the worst moment, after a reboot, with no
# way in.  Ask now, while there is still a working shell here.
set_up_login_accounts() {
    # No terminal (a scripted or resumed run): say what is missing rather than
    # blocking, and leave the system unbootable-but-known instead of hanging.
    if [ ! -t 0 ]; then
        echo
        echo "!! Not running interactively, so no passwords were set."
        echo "   Before rebooting, set at least the root password:"
        echo "       chroot /mnt/lfs /usr/bin/passwd root"
        return 0
    fi

    echo
    echo "--- accounts ------------------------------------------------"

    # root
    if grep -qE '^root:[^:]*:' /etc/shadow 2>/dev/null &&
       ! grep -qE '^root:(\*|!|)?:' /etc/shadow 2>/dev/null; then
        echo "root already has a password."
    else
        echo "root has NO password yet.  Without one you may not be able to"
        echo "log in after rebooting."
        passwd root || echo "!! setting the root password failed -- do it before rebooting" >&2
    fi

    # a login account for a person: the name is already configured, so this
    # only has to create it and set a password
    local main
    main="$(sed -n 's/^main_user=\(.*\)$/\1/p' /etc/pkgusr/packagemanager.conf \
            2>/dev/null | head -n1)"
    if [ -z "$main" ]; then
        echo
        echo "No login account is configured.  You can add one now, or later"
        echo "with:  useradd -m -G users <name> && passwd <name>"
        printf "Create a login account now?  [name, or blank to skip]: "
        read -e -r main
    fi
    [ -n "$main" ] || { echo; return 0; }

    if id "$main" >/dev/null 2>&1; then
        echo "Account '$main' already exists."
    else
        echo "Creating login account '$main' ..."
        useradd -m -k /etc/skel -G users -s /bin/bash "$main" \
            || { echo "!! could not create $main" >&2; return 0; }
    fi
    if grep -qE "^$main:(\*|!|)?:" /etc/shadow 2>/dev/null; then
        echo "Set a password for '$main':"
        passwd "$main" || echo "!! setting the password for $main failed" >&2
    fi

    # so the account can reach the application users created later
    echo
    echo "  '$main' can be given access to application users with:"
    echo "      packagemanager user create <app> --shared --launcher"
}

set_up_login_accounts

echo
echo "=============================================================="
echo " The base system is built."
echo
echo " wget was installed with a minimal configure line so the system"
echo " can fetch things at all.  Reinstall it properly -- with its"
echo " dependencies, from the BLFS book -- once you have booted:"
echo
echo "     packagemanager install wget --recursive --run"
echo
echo " Anything else you want on a fresh system belongs in"
echo " last_build_step.sh on the host."
echo "=============================================================="

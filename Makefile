# lfs-pkgusr -- install the package-user toolchain.
#
#   make install                    -> /usr
#   make install PREFIX=/usr/local  -> /usr/local
#   make uninstall
#   make clean                   -> scratch files, not installed ones
#   make check                   -> run the regression tests
#
# DESTDIR is honoured, so this works for staged installs and for installing
# into a tree that is not the running system:
#   make install DESTDIR=/mnt/lfs PREFIX=/usr

# /usr, not /usr/local: these tools ARE the system's package management -- the
# chroot invokes them by name, and packagemanager runs lfs-helper pm-install
# off $PATH, which does not include /usr/local everywhere.
PREFIX      ?= /usr
DESTDIR     ?=
BINDIR      := $(DESTDIR)$(PREFIX)/bin
SHAREDIR    := $(DESTDIR)$(PREFIX)/share/lfs-pkgusr
COMPDIR     := $(DESTDIR)$(PREFIX)/share/bash-completion/completions
SYSCONFDIR  ?= $(DESTDIR)/etc

# The four tools, the book merger, and the phase runner every generated
# install script sources (it goes in bin so `. lfs-phases` finds it on PATH,
# on the host, in the chroot and on the built system alike).
TOOLS       := lfs lfs-helper packagemanager blfs lfs-sysvbook lfs-phases lfs-kernel
COMPLETION  := lfs-completion.bash
TESTS       := test_lfs_crosschain.sh

INSTALL     ?= install

# Directories are created with mkdir -p, NEVER `install -d`.
#
# `install -d` applies its mode to a directory that ALREADY EXISTS, so
# installing the tools re-moded /usr/bin from 775 to 755 and silently broke
# the package-user system: package users are in group install and need
# group-write on the install directories.  The next build then failed with
# permission errors that had nothing to do with the package.
# mkdir -p leaves an existing directory exactly as it is.
MKDIR       ?= mkdir -p

.PHONY: all install uninstall check clean help

all: help

help:
	@echo "make install [PREFIX=...] [DESTDIR=...]   install the tools"
	@echo "make uninstall [PREFIX=...]               remove them"
	@echo "make check                                 run the tests"
	@echo "make clean                                 remove scratch files"
	@echo ""
	@echo "installs into: $(PREFIX)/bin"

install:
	@echo "==> tools -> $(BINDIR)"
	$(MKDIR) $(BINDIR)
	@# packagemanager_install is retired (1.12.0, folded into lfs-helper
	@# pm-install) -- sweep a previously installed copy off the system.
	@if [ -e "$(BINDIR)/packagemanager_install" ]; then \
	    rm -f "$(BINDIR)/packagemanager_install" \
	        && echo "    removed retired packagemanager_install"; \
	fi
	@for t in $(TOOLS); do \
	    if [ -f "$$t" ]; then \
	        $(INSTALL) -m 755 "$$t" "$(BINDIR)/$$t" && echo "    $$t"; \
	    else \
	        echo "    !! missing: $$t" >&2; exit 1; \
	    fi; \
	done
	@echo "==> stacks -> $(DESTDIR)/etc/pkgusr/stacks"
	$(MKDIR) $(DESTDIR)/etc/pkgusr/stacks
	@# A STACK FILE IS THE USER'S.  This overwrote it unconditionally, so
	@# `make install` silently undid every edit -- and the edits are the
	@# point of the file: which packages to avoid, which refs to pin.  A
	@# user who had just removed `avoid ruby` would have had it back, and
	@# the build would have failed the same way again with no explanation.
	@# Install it when it is missing; otherwise keep theirs and leave the
	@# new one alongside for comparison.
	@# ...but only a file the user has ACTUALLY edited.  Keeping every
	@# installed stack forever meant a shipped fix -- new entries, a
	@# corrected have= -- waited in a .new file for a manual merge, even
	@# when the user had never touched the file.  `packagemanager stack
	@# services` then ran three entries while the new one had six, and
	@# nothing said why.  So record what we shipped: if the installed copy
	@# still matches the last shipped copy, it is ours to update.
	@$(MKDIR) $(DESTDIR)/etc/pkgusr/stacks/.shipped
	@for f in stacks/*; do \
	    [ -f "$$f" ] || continue; \
	    b="$$(basename $$f)"; \
	    d="$(DESTDIR)/etc/pkgusr/stacks/$$b"; \
	    r="$(DESTDIR)/etc/pkgusr/stacks/.shipped/$$b"; \
	    if [ ! -e "$$d" ]; then \
	        $(INSTALL) -m 644 "$$f" "$$d" && cp -f "$$f" "$$r" \
	        && echo "    $$f"; \
	    elif cmp -s "$$f" "$$d"; then \
	        cp -f "$$f" "$$r"; echo "    $$b (unchanged)"; \
	    elif [ -f "$$r" ] && cmp -s "$$r" "$$d"; then \
	        $(INSTALL) -m 644 "$$f" "$$d" && cp -f "$$f" "$$r" \
	        && rm -f "$$d.new" \
	        && echo "    $$b (updated -- you had not edited it)"; \
	    else \
	        $(INSTALL) -m 644 "$$f" "$$d.new" \
	        && echo "    $$b -> KEPT YOURS; new version saved as $$d.new"; \
	    fi; \
	done; true
	@# kernel.conf is a file to EDIT BEFORE building, so it is installed
	@# rather than written on first run -- and, like a stack file, an
	@# edited one is kept and the new one lands beside it.
	@if [ -f kernel.conf ]; then \
	    d="$(DESTDIR)/etc/pkgusr/kernel.conf"; \
	    if [ ! -e "$$d" ] || cmp -s kernel.conf "$$d"; then \
	        $(INSTALL) -m 644 kernel.conf "$$d" && echo "    kernel.conf"; \
	    else \
	        $(INSTALL) -m 644 kernel.conf "$$d.new" \
	        && echo "    kernel.conf -> KEPT YOURS ($$d.new)"; \
	    fi; \
	fi
	@# A STACK ENTRY MAY HAVE A DIRECTORY.  The loop above takes files
	@# only, so stacks/mytools/install_mytools -- the package-user script
	@# the mytools step runs -- was never installed, and the step would
	@# have failed with "missing .../mytools/install_mytools".  Copy the
	@# subdirectories too, without clobbering a script the user edited.
	@for d in stacks/*/; do \
	    [ -d "$$d" ] || continue; \
	    b="$$(basename $$d)"; \
	    $(MKDIR) "$(DESTDIR)/etc/pkgusr/stacks/$$b"; \
	    for f in "$$d"*; do \
	        [ -f "$$f" ] || continue; \
	        t="$(DESTDIR)/etc/pkgusr/stacks/$$b/$$(basename $$f)"; \
	        if [ ! -e "$$t" ] || cmp -s "$$f" "$$t"; then \
	            $(INSTALL) -m 755 "$$f" "$$t"; \
	        else \
	            $(INSTALL) -m 755 "$$f" "$$t.new" \
	            && echo "    $$b/$$(basename $$f) -> KEPT YOURS ($$t.new)"; \
	        fi; \
	    done; \
	    echo "    $$b/ ($$(ls -1 $$d | wc -l) file(s))"; \
	done; true
	@chmod 755 $(DESTDIR)/etc/pkgusr/stacks/*.sh 2>/dev/null || true
	@echo "==> bash completion -> $(COMPDIR)"
	@# Optional, and a missing one must not take the tools down with it:
	@# `install: cannot stat 'lfs-completion.bash'` aborted the whole target
	@# after the tools were already in place, so the run looked failed while
	@# most of it had succeeded.
	@if [ -f "$(COMPLETION)" ]; then \
	    $(MKDIR) $(COMPDIR); \
	    $(INSTALL) -m 644 $(COMPLETION) $(COMPDIR)/lfs; \
	    for t in blfs packagemanager lfs-helper; do \
	        ln -sf lfs "$(COMPDIR)/$$t"; \
	    done; \
	else \
	    echo "    skipped: $(COMPLETION) is not in this checkout"; \
	fi
	@echo "==> XDG profile for shared users -> $(SYSCONFDIR)/pkgusr/skel-u_xdg"
	$(MKDIR) $(SYSCONFDIR)/pkgusr/skel-u_xdg
	@if [ -f "$(SYSCONFDIR)/pkgusr/skel-u_xdg/.bash_profile" ]; then \
	    echo "    kept your existing .bash_profile"; \
	else \
	    $(INSTALL) -m 644 skel-u_xdg/.bash_profile \
	        "$(SYSCONFDIR)/pkgusr/skel-u_xdg/.bash_profile"; \
	    echo "    installed (XDG_RUNTIME_DIR is filled in on first use)"; \
	fi
	@echo "==> tests -> $(SHAREDIR)"
	$(MKDIR) $(SHAREDIR)
# The tests are optional -- say so when they are absent, rather than hiding a
# real failure.  `2>/dev/null || true` hid both cases alike.
	@if [ -f "$(TESTS)" ]; then \
	    $(INSTALL) -m 644 $(TESTS) $(SHAREDIR)/ && echo "    $(TESTS)"; \
	else \
	    echo "    (not shipped: $(TESTS))"; \
	fi
	@echo ""
	@echo "Installed.  Check with:"
	@echo "    $(PREFIX)/bin/lfs --version"
	@echo "    $(PREFIX)/bin/lfs --help"

uninstall:
	@for t in $(TOOLS); do rm -fv "$(BINDIR)/$$t"; done
	@for t in lfs blfs packagemanager lfs-helper; do \
	    rm -fv "$(COMPDIR)/$$t"; \
	done
	rm -rfv $(SHAREDIR)
	@echo ""
	@echo "Left alone (they are yours):"
	@echo "    $(SYSCONFDIR)/pkgusr/skel-u_xdg/.bash_profile"
	@echo "    /usr/share/lfs        books, settings, snapshots"
	@echo "    /etc/pkgusr           packagemanager settings"

check:
	@bash $(TESTS) ./lfs

# Nothing here is compiled, so clean removes only what running the tools here
# leaves behind: Python bytecode and the test suite's scratch directories.
# It never touches an installed tree -- that is what uninstall is for.
clean:
	rm -rf __pycache__ *.pyc
	rm -rf /tmp/lfstest.* /tmp/lfstest-count.*
	@echo "clean.  (installed files are untouched -- use 'make uninstall')"

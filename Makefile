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
# chroot invokes them by name, and packagemanager runs packagemanager_install
# off $PATH, which does not include /usr/local everywhere.
PREFIX      ?= /usr
DESTDIR     ?=
BINDIR      := $(DESTDIR)$(PREFIX)/bin
SHAREDIR    := $(DESTDIR)$(PREFIX)/share/lfs-pkgusr
COMPDIR     := $(DESTDIR)$(PREFIX)/share/bash-completion/completions
SYSCONFDIR  ?= $(DESTDIR)/etc

# The four tools, plus the bash engine packagemanager calls.
TOOLS       := lfs lfs-helper packagemanager packagemanager_install blfs
COMPLETION  := lfs-completion.bash
TESTS       := test_lfs_crosschain.sh

INSTALL     ?= install

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
	$(INSTALL) -d $(BINDIR)
	@for t in $(TOOLS); do \
	    if [ -f "$$t" ]; then \
	        $(INSTALL) -m 755 "$$t" "$(BINDIR)/$$t" && echo "    $$t"; \
	    else \
	        echo "    !! missing: $$t" >&2; exit 1; \
	    fi; \
	done
	@echo "==> bash completion -> $(COMPDIR)"
	$(INSTALL) -d $(COMPDIR)
	$(INSTALL) -m 644 $(COMPLETION) $(COMPDIR)/lfs
	@for t in blfs packagemanager lfs-helper; do \
	    ln -sf lfs "$(COMPDIR)/$$t"; \
	done
	@echo "==> XDG profile for shared users -> $(SYSCONFDIR)/pkgusr/skel-u_xdg"
	$(INSTALL) -d $(SYSCONFDIR)/pkgusr/skel-u_xdg
	@if [ -f "$(SYSCONFDIR)/pkgusr/skel-u_xdg/.bash_profile" ]; then \
	    echo "    kept your existing .bash_profile"; \
	else \
	    $(INSTALL) -m 644 skel-u_xdg/.bash_profile \
	        "$(SYSCONFDIR)/pkgusr/skel-u_xdg/.bash_profile"; \
	    echo "    installed (XDG_RUNTIME_DIR is filled in on first use)"; \
	fi
	@echo "==> tests -> $(SHAREDIR)"
	$(INSTALL) -d $(SHAREDIR)
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

# lfs-pkgusr -- install the package-user toolchain.
#
#   make install                 -> /usr/local
#   make install PREFIX=/usr     -> /usr
#   make uninstall
#   make check                   -> run the regression tests
#
# DESTDIR is honoured, so this works for staged installs and for installing
# into a tree that is not the running system:
#   make install DESTDIR=/mnt/lfs PREFIX=/usr

PREFIX      ?= /usr/local
DESTDIR     ?=
BINDIR      := $(DESTDIR)$(PREFIX)/bin
SHAREDIR    := $(DESTDIR)$(PREFIX)/share/lfs-pkgusr
COMPDIR     := $(DESTDIR)$(PREFIX)/share/bash-completion/completions
SYSCONFDIR  ?= $(DESTDIR)/etc

# The four tools, plus the bash engine packagemanager calls.
TOOLS       := lfs lfs-helper packagemanager packagemanager_install blfs
COMPLETION  := lfs-completion.bash
LAST_STEP   := last_build_step.sh
TESTS       := test_lfs_crosschain.sh

INSTALL     ?= install

.PHONY: all install uninstall check help

all: help

help:
	@echo "make install [PREFIX=/usr] [DESTDIR=...]   install the tools"
	@echo "make uninstall [PREFIX=/usr]               remove them"
	@echo "make check                                 run the tests"
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
	@echo "==> last build step -> $(SYSCONFDIR)/lfs"
	$(INSTALL) -d $(SYSCONFDIR)/lfs
	@if [ -f "$(SYSCONFDIR)/lfs/$(LAST_STEP)" ]; then \
	    echo "    kept your existing $(SYSCONFDIR)/lfs/$(LAST_STEP)"; \
	    $(INSTALL) -m 644 $(LAST_STEP) "$(SYSCONFDIR)/lfs/$(LAST_STEP).new"; \
	    echo "    new version alongside it as $(LAST_STEP).new"; \
	else \
	    $(INSTALL) -m 755 $(LAST_STEP) "$(SYSCONFDIR)/lfs/$(LAST_STEP)"; \
	fi
	@echo "==> tests -> $(SHAREDIR)"
	$(INSTALL) -d $(SHAREDIR)
	$(INSTALL) -m 644 $(TESTS) $(SHAREDIR)/ 2>/dev/null || true
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
	@echo "    $(SYSCONFDIR)/lfs/$(LAST_STEP)"
	@echo "    /usr/share/lfs        books, settings, snapshots"
	@echo "    /etc/pkgusr           packagemanager settings"

check:
	@bash $(TESTS) ./lfs

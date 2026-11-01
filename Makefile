# EllesmereMetrics development tasks. Run `make help` for the list.
#
# Needs a Lua 5.1 interpreter (lua5.1 preferred, LuaJIT works), luacheck, zip
# and unzip. Override the tools on the command line, e.g. `make test LUA=luajit`.

ADDON := EllesmereMetrics
TOC := $(ADDON).toc

# A literal "#" that GNU make 3.81 (macOS) and 4.x both accept in $(shell).
HASH := \#

# The TOC is the only list of runtime Lua files; these lines read it.
LUA_SOURCES := $(shell sed -e '/^$(HASH)/d' -e '/^[[:space:]]*$$/d' $(TOC) | tr -d '\r' | tr '\\' '/')
VERSION := $(shell sed -n 's/^$(HASH)$(HASH) Version:[[:space:]]*//p' $(TOC) | tr -d '\r')
RUNTIME_FILES := $(TOC) $(LUA_SOURCES) LICENSE

TEST_SOURCES := $(sort $(wildcard tests/*.lua))
TEST_FILES := $(sort $(wildcard tests/test_*.lua))

BUILD_DIR := build
DIST_DIR := dist
ZIP := $(DIST_DIR)/$(ADDON)-$(VERSION).zip

LUA ?= $(shell for lua in lua5.1 luajit lua; do command -v $$lua && break; done)
LUACHECK ?= luacheck
NO_LUA := error: no Lua interpreter found; install lua5.1 or LuaJIT, or pass LUA=<interpreter>

.DEFAULT_GOAL := help
.PHONY: help all check syntax lint test pack verify clean

help: ## List the available targets
	@echo "Usage: make <target> [LUA=lua5.1] [LUACHECK=luacheck]"
	@echo
	@awk -F ':.*## ' '/^[a-z]+:.*## / { printf "  %-7s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

all: check pack verify ## Run every check, then build and verify the archive

check: syntax lint test ## Run the syntax check, luacheck and the tests

syntax: ## Check that every Lua file parses
	@test -n "$(LUA)" || { echo "$(NO_LUA)" >&2; exit 1; }
	@for file in $(LUA_SOURCES) $(TEST_SOURCES); do \
		$(LUA) -e "assert(loadfile('$$file'))" || exit 1; \
	done
	@echo "Syntax OK: $(words $(LUA_SOURCES) $(TEST_SOURCES)) files parsed by $(LUA)"

lint: ## Run luacheck on the addon and the tests
	@command -v $(LUACHECK) >/dev/null 2>&1 || { echo "error: $(LUACHECK) not found; see README.md, Development" >&2; exit 1; }
	$(LUACHECK) $(LUA_SOURCES) $(TEST_SOURCES)

test: ## Run the automated tests
	@test -n "$(LUA)" || { echo "$(NO_LUA)" >&2; exit 1; }
	$(LUA) tests/run.lua $(TEST_FILES)

pack: $(RUNTIME_FILES) ## Build dist/EllesmereMetrics-<version>.zip
	@test -n "$(VERSION)" || { echo "error: $(TOC) has no '## Version:' line" >&2; exit 1; }
	@rm -rf "$(BUILD_DIR)/$(ADDON)" "$(ZIP)"
	@mkdir -p "$(BUILD_DIR)/$(ADDON)" "$(DIST_DIR)"
	@for file in $(RUNTIME_FILES); do \
		mkdir -p "$(BUILD_DIR)/$(ADDON)/$$(dirname "$$file")" && \
		cp "$$file" "$(BUILD_DIR)/$(ADDON)/$$file" || exit 1; \
	done
	@cd "$(BUILD_DIR)" && zip -q -r -X "$(abspath $(ZIP))" "$(ADDON)"
	@echo "Created $(ZIP)"

verify: ## Check the archive's contents (after make pack)
	@sh scripts/verify-archive.sh "$(ZIP)" "$(ADDON)"

clean: ## Delete the build and dist directories
	rm -rf "$(BUILD_DIR)" "$(DIST_DIR)"

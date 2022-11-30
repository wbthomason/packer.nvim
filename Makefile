# test:
# 	nvim --headless --noplugin -u tests/minimal.vim -c "PlenaryBustedDirectory tests/ { minimal_init = './tests/minimal.vim' }"
# run:
# 	docker build . -t neovim-stable:latest && docker run --rm -it --entrypoint bash neovim-stable:latest
# run-test:
# 	docker build . -t neovim-stable:latest && docker run --rm neovim-stable:latest

export PJ_ROOT=$(PWD)

FILTER ?= .*

LUA_VERSION   := 5.1
TL_VERSION    := 0.14.1
NEOVIM_BRANCH ?= master

DEPS_DIR := $(PWD)/deps/nvim-$(NEOVIM_BRANCH)

LUAROCKS       := luarocks --lua-version=$(LUA_VERSION)
LUAROCKS_TREE  := $(DEPS_DIR)/luarocks/usr
LUAROCKS_LPATH := $(LUAROCKS_TREE)/share/lua/$(LUA_VERSION)
LUAROCKS_INIT  := eval $$($(LUAROCKS) --tree $(LUAROCKS_TREE) path) &&

.DEFAULT_GOAL := build

$(DEPS_DIR)/neovim:
	@mkdir -p $(DEPS_DIR)
	git clone --depth 1 https://github.com/neovim/neovim --branch $(NEOVIM_BRANCH) $@
	@# disable LTO to reduce compile time
	make -C $@ \
		DEPS_BUILD_DIR=$(dir $(LUAROCKS_TREE)) \
		CMAKE_BUILD_TYPE=RelWithDebInfo \
		CMAKE_EXTRA_FLAGS=-DENABLE_LTO=OFF

TL := $(LUAROCKS_TREE)/bin/tl

$(TL):
	@mkdir -p $@
	$(LUAROCKS) --tree $(LUAROCKS_TREE) install tl $(TL_VERSION)

INSPECT := $(LUAROCKS_LPATH)/inspect.lua

$(INSPECT):
	@mkdir -p $@
	$(LUAROCKS) --tree $(LUAROCKS_TREE) install inspect

.PHONY: lua_deps
lua_deps: $(TL) $(INSPECT)

.PHONY: test_deps
test_deps: $(DEPS_DIR)/neovim

export VIMRUNTIME=$(DEPS_DIR)/neovim/runtime
export TEST_COLORS=1

.PHONY: test
test: $(DEPS_DIR)/neovim
	$(LUAROCKS_INIT) busted \
		-v \
		--lazy \
		--helper=$(PWD)/test/preload.lua \
		--output test.busted.outputHandlers.nvim \
		--lpath=$(DEPS_DIR)/neovim/?.lua \
		--lpath=$(DEPS_DIR)/neovim/build/?.lua \
		--lpath=$(DEPS_DIR)/neovim/runtime/lua/?.lua \
		--lpath=$(DEPS_DIR)/?.lua \
		--lpath=$(PWD)/lua/?.lua \
		--filter="$(FILTER)" \
		$(PWD)/test

	-@stty sane

.PHONY: tl-check
tl-check: $(TL)
	$(TL) check teal/*.tl teal/**/*.tl

# TODO(lewis6991): migrate to cyan
.PHONY: tl-build
tl-build: tlconfig.lua $(TL)
	@$(TL) build
	@echo Updated lua files

.PHONY: build
build: tl-build

.PHONY: tl-ensure
tl-ensure: tl-build
	git diff --exit-code -- lua

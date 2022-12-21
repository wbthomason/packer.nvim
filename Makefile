
.PHONY: build
build:
	rm -rf lua
	cyan check teal/**/*.tl
	cyan build

test:
	nvim --headless --noplugin -u tests/minimal.vim -c "PlenaryBustedDirectory tests/ { minimal_init = './tests/minimal.vim' }"
run:
	docker build . -t neovim-stable:latest && docker run --rm -it --entrypoint bash neovim-stable:latest
run-test:
	docker build . -t neovim-stable:latest && docker run --rm neovim-stable:latest

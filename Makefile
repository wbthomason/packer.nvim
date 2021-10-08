FILTER=.*
.DEFAULT_GOAL := build
.PHONY: check
check:
	tl check teal/**/*.tl

.PHONY: build
build: tlconfig.lua
	tl build
	@echo Updated lua files

.PHONY: test serve build lint fmt check install pesde-install

install:
	wally install
	rojo sourcemap dev.project.json --output sourcemap.json
	mkdir -p Packages
	wally-package-types --sourcemap sourcemap.json Packages/

pesde-install:
	pesde install

test:
	lune run tests/run

serve:
	rojo serve dev.project.json

build:
	rojo build default.project.json -o starknet-luau.rbxm

lint:
	selene src/

fmt:
	stylua src/

check:
	$(MAKE) lint
	stylua --check src/
	$(MAKE) test

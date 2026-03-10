.PHONY: test serve build lint fmt check install pesde-install clean test-one build-and-test

install:
	wally install
	rojo sourcemap dev.project.json --output sourcemap.json
	mkdir -p Packages
	wally-package-types --sourcemap sourcemap.json Packages/

pesde-install:
	pesde install

test:
	lune run tests/run

test-one:
	@if [ -z "$(FILE)" ]; then echo "Usage: make test-one FILE=tests/crypto/BigInt.spec.luau"; exit 1; fi
	lune run tests/run -- --file $(FILE)

serve:
	rojo serve dev.project.json

build: install
	rojo build default.project.json -o starknet-luau.rbxm

lint:
	selene src/

fmt:
	stylua src/

check:
	selene src/ && stylua --check src/ && lune run tests/run

clean:
	rm -f starknet-luau.rbxm sourcemap.json roblox.yml
	rm -rf Packages/ ServerPackages/ DevPackages/
	rm -rf roblox_packages/ .pesde/

build-and-test: build test

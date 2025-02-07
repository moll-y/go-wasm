SHELL := /usr/bin/env bash
GO_VERSION = 1.16
GOROOT =
PATH := ${PWD}/cache/go/bin:${PWD}/cache/go/misc/wasm:${PATH}
GOOS = js
GOARCH = wasm
export
LINT_VERSION=1.27.0

.PHONY: serve
serve:
	go run ./server

.PHONY: lint-deps
lint-deps: go
	@if ! which golangci-lint >/dev/null || [[ "$$(golangci-lint version 2>&1)" != *${LINT_VERSION}* ]]; then \
		curl -sfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b $$(go env GOPATH)/bin v${LINT_VERSION}; \
	fi

.PHONY: lint
lint: lint-deps
	golangci-lint run

.PHONY: lint-fix
lint-fix: lint-deps
	golangci-lint run --fix

.PHONY: test-native
test-native:
	GOARCH= GOOS= go test \
		-race \
		-coverprofile=cover.out \
		./...

.PHONY: test-js
test-js: go
	go test \
		-coverprofile=cover_js.out \
		./...

.PHONY: test
test: test-native #test-js  # TODO restore when this is resolved: https://travis-ci.community/t/goos-js-goarch-wasm-go-run-fails-panic-newosproc-not-implemented/1651

.PHONY: static
static: server/public/wasm/go.tar.gz commands

server/public/wasm:
	mkdir -p server/public/wasm

server/public/wasm/go.tar.gz: server/public/wasm go
	GOARCH=$$(go env GOHOSTARCH) GOOS=$$(go env GOHOSTOS) \
		go run ./internal/cmd/gozip cache/go > server/public/wasm/go.tar.gz

.PHONY: clean
clean:
	rm -rf ./out ./server/public/wasm

cache:
	mkdir -p cache

.PHONY: commands
commands: server/public/wasm/wasm_exec.js server/public/wasm/main.wasm $(patsubst cmd/%,server/public/wasm/%.wasm,$(wildcard cmd/*))

.PHONY: go
go: cache/go${GO_VERSION}

cache/go${GO_VERSION}: cache
	if [[ ! -e cache/go${GO_VERSION} ]]; then \
		set -ex; \
		TMP=$$(mktemp -d); trap 'rm -rf "$$TMP"' EXIT; \
		git clone \
			--depth 1 \
			--single-branch \
			--branch go${GO_VERSION} \
			https://github.com/golang/go.git \
			"$$TMP"; \
		$(MAKE) -e TMP_GO="$$TMP" go-ext; \
		pushd "$$TMP/src"; \
		./make.bash; \
		export PATH="$$TMP/bin:$$PATH"; \
		go version; \
		mkdir -p ../bin/js_wasm; \
		go build -o ../bin/js_wasm/ std cmd/go cmd/gofmt; \
		go tool dist test -rebuild -list; \
		go build -o ../pkg/tool/js_wasm/ std cmd/buildid cmd/pack; \
		go install ./...; \
		popd; \
		mv "$$TMP" cache/go${GO_VERSION}; \
		ln -sfn go${GO_VERSION} cache/go; \
	fi
	touch cache/go${GO_VERSION}
	touch cache/go.mod  # Makes it so linters will ignore this dir

server/public/wasm/%.wasm: server/public/wasm go
	go build -o $@ ./cmd/$*

server/public/wasm/main.wasm: server/public/wasm go
	go build -o server/public/wasm/main.wasm .

server/public/wasm/wasm_exec.js: go
	cp cache/go/misc/wasm/wasm_exec.js server/public/wasm/wasm_exec.js

.PHONY: go-ext
go-ext:
	[[ -d "${TMP_GO}" ]]
	sed -i'' -e '/^func Pipe(/,/^}/d' "${TMP_GO}"/src/syscall/fs_js.go
	sed -i'' -e '/^func StartProcess(/,/^}/d' "${TMP_GO}"/src/syscall/syscall_js.go
	sed -i'' -e '/^func Wait4(/,/^}/d' "${TMP_GO}"/src/syscall/syscall_js.go
	sed -i'' -e '/^func (w WaitStatus) ExitStatus() int/d' "${TMP_GO}"/src/syscall/syscall_js.go
	sed -i'' -e '/^func (w WaitStatus) Exited() bool/d' "${TMP_GO}"/src/syscall/syscall_js.go
	cp internal/testdata/fs_* "${TMP_GO}"/src/syscall/
	cp internal/testdata/syscall_* "${TMP_GO}"/src/syscall/
	cp internal/testdata/filelock_* "${TMP_GO}"/src/cmd/go/internal/lockedfile/internal/filelock/
	sed -i'' -e 's/+build\( [^j].*\)*$$/+build\1 js,wasm/' "${TMP_GO}"/src/os/exec/lp_unix.go
	rm "${TMP_GO}"/src/os/exec/lp_js.go

.PHONY: watch
watch:
	@if [[ ! -d server/node_modules ]]; then \
		npm --prefix=server ci; \
	fi
	npm --prefix=server run start-go & \
	npm --prefix=server start

.PHONY: build
build: static
	npm --prefix=server ci
	npm --prefix=server run build
	mkdir -p out
	cp -r server/build/* out/

.PHONY: docker
docker:
	docker build -t go-wasm .

.PHONY: docker-run
docker-run: docker
	docker run -it --rm \
		--name go-wasm \
		-p 8080:80 \
		go-wasm:latest

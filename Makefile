CONFIG ?= config/example.gateway.json

.PHONY: toolchain build test run client

toolchain:
	./scripts/bootstrap_local_toolchain.sh

build:
	./scripts/with_local_toolchain.sh dune build @install

test:
	./scripts/with_local_toolchain.sh dune runtest --no-buffer

run:
	./scripts/with_local_toolchain.sh dune exec bulkhead-lm -- --config $(CONFIG)

client:
	./scripts/with_local_toolchain.sh dune exec bulkhead-lm-client -- --config $(CONFIG)

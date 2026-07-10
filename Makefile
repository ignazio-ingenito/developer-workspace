IMAGE ?= developer-workspace:dev

.PHONY: build smoke lint
build:
	docker build -t $(IMAGE) .

smoke:
	docker run --rm --entrypoint /usr/local/lib/developer-workspace/smoke-test.sh $(IMAGE)

lint:
	shellcheck scripts/*.sh

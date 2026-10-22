PROJECT = concourse-helm3
ID = artielabs/${PROJECT}
VERSION = $(shell cat VERSION)


all: build push

.PHONY: build push test-integration run

PLATFORMS = linux/amd64,linux/arm64

# Loads the image for this machine's platform only, for local testing
build:
	docker buildx build --load --tag ${ID}:$(VERSION) .

# Builds every platform and pushes them under one multi-arch tag
push:
	docker buildx build --platform $(PLATFORMS) --push --tag ${ID}:$(VERSION) .

test-integration:
	test/integration/run.sh

run:
	docker run \
		--volume $(shell pwd):/opt/helm-3 \
		--workdir /opt/helm-3 \
		--interactive \
		--tty \
		${ID}:latest \
		bash

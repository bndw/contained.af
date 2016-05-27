# Set an output prefix, which is the local directory if not specified
PREFIX?=$(shell pwd)
BUILDTAGS=

.PHONY: clean all dbuild dev devbuild run fmt vet lint build test install static

DIND_CONTAINER=contained-dind
DIND_DOCKER_IMAGE=r.j3ss.co/docker:userns
DOCKER_IMAGE=r.j3ss.co/contained


all: clean build fmt lint test vet

build:
	@echo "+ $@"
	@go build -tags "$(BUILDTAGS) cgo" -o contained .

static:
	@echo "+ $@"
	CGO_ENABLED=1 go build -tags "$(BUILDTAGS) cgo static_build" -ldflags "-w -extldflags -static" -o contained .

fmt:
	@echo "+ $@"
	@gofmt -s -l . | grep -v vendor | tee /dev/stderr

lint:
	@echo "+ $@"
	@golint ./... | grep -v vendor | tee /dev/stderr

test: fmt lint vet
	@echo "+ $@"
	@go test -v -tags "$(BUILDTAGS) cgo" $(shell go list ./... | grep -v vendor)

vet:
	@echo "+ $@"
	@go vet $(shell go list ./... | grep -v vendor)

clean:
	@echo "+ $@"
	@rm -rf contained

dbuild:
	docker build --rm --force-rm -t $(DOCKER_IMAGE) .

dind:
	docker build --rm --force-rm -f Dockerfile.dind -t $(DIND_DOCKER_IMAGE) .
	docker run -d \
		--name $(DIND_CONTAINER) \
		--privileged \
		-p 1234:10000 \
		$(DIND_DOCKER_IMAGE) \
		docker daemon -D --storage-driver overlay \
		-H tcp://127.0.0.1:2375 \
		--host=unix:///var/run/docker.sock \
		--disable-legacy-registry=true \
		--userns-remap default \
		--log-driver=none \
		--exec-opt=native.cgroupdriver=cgroupfs

run: dbuild
	docker run --rm -it \
		--net container:$(DIND_CONTAINER) \
		$(DOCKER_IMAGE) -d

devbuild:
	docker build --rm --force-rm -f Dockerfile.dev -t $(DOCKER_IMAGE):dev .

static/js/contained.min.js: devbuild
	docker run --rm -it \
		-v $(CURDIR)/:/usr/src/contained.af \
		--workdir /usr/src/contained.af \
		$(DOCKER_IMAGE):dev \
			uglifyjs --output $@ --compress --mangle -- \
			static/js/jquery-2.2.4.min.js static/js/term.js \
			static/js/questions.js static/js/main.js

static/css/contained.min.css: devbuild
	docker run --rm -it \
		-v $(CURDIR)/:/usr/src/contained.af \
		--workdir /usr/src/contained.af \
		$(DOCKER_IMAGE):dev \
			bash -c 'cat static/css/normalize.css static/css/bootstrap.min.css static/css/custom.css | cleancss -o $@'

dev: static/js/contained.min.js static/css/contained.min.css

DOCKER ?= docker
IMAGE ?= oski
VERSION ?= 8.0
PROGRESS ?= plain
BUILD_ARGS ?=
PLATFORM ?=
NO_CACHE ?= 0
PULL ?= 0

BIN_TAG ?= $(IMAGE):$(VERSION)
DEV_TAG ?= $(IMAGE):$(VERSION)-dev
SHARED_TAG ?= $(IMAGE):$(VERSION)-shared
OPENH264_TAG ?= $(IMAGE):$(VERSION)-openh264
AMR_TAG ?= $(IMAGE):$(VERSION)-amr
DIST_DIR ?= dist
EXPORT_DIR ?= $(DIST_DIR)/export
PACKAGE_DIR ?= $(DIST_DIR)/packages
PACKAGE_PREFIX ?= oski-$(VERSION)
MACOS_DIR ?= platforms/macos
MACOS_ARCHS ?= $(shell uname -m 2>/dev/null || printf unknown)
MACOS_DEPLOYMENT_TARGET ?= 12.0
MACOS_BUILD_ROOT ?= $(DIST_DIR)/macos/build
MACOS_PREFIX ?= $(DIST_DIR)/macos/oski-$(VERSION)-macos-shared
MACOS_PACKAGE ?= $(PACKAGE_DIR)/oski-$(VERSION)-macos-shared.tar.gz

PLATFORM_FLAG = $(if $(PLATFORM),--platform $(PLATFORM),)
NO_CACHE_FLAG = $(if $(filter 1 true yes,$(NO_CACHE)),--no-cache,)
PULL_FLAG = $(if $(filter 1 true yes,$(PULL)),--pull,)
BUILD_FLAGS = --progress=$(PROGRESS) $(PLATFORM_FLAG) $(NO_CACHE_FLAG) $(PULL_FLAG) $(BUILD_ARGS)

define EXPORT_ROOTFS
	@set -eu; \
	target="$(1)"; \
	tag="$(2)"; \
	out="$(EXPORT_DIR)/$(1)"; \
	cid="$$($(DOCKER) create "$(2)" /oski-export-placeholder)"; \
	trap '$(DOCKER) rm -f "$$cid" >/dev/null' EXIT; \
	rm -rf "$$out"; \
	mkdir -p "$$out"; \
	$(DOCKER) export "$$cid" | tar -C "$$out" -xf -; \
	printf 'Exported %s (%s) to %s\n' "$$target" "$$tag" "$$out"
endef

define PACKAGE_ROOTFS
	@set -eu; \
	target="$(1)"; \
	src="$(EXPORT_DIR)/$(1)"; \
	archive="$(PACKAGE_DIR)/$(PACKAGE_PREFIX)-$(1).tar.gz"; \
	mkdir -p "$(PACKAGE_DIR)"; \
	tar -C "$$src" -czf "$$archive" .; \
	printf 'Packaged %s as %s\n' "$$target" "$$archive"
endef

.DEFAULT_GOAL := help

.PHONY: help
help:
	@printf '%s\n' 'Oski build targets'
	@printf '%s\n' ''
	@printf '%s\n' 'Default LGPL/GPL-free targets:'
	@printf '  %-20s %s\n' 'make ffmpeg-bin' 'build $(BIN_TAG)'
	@printf '  %-20s %s\n' 'make ffmpeg-dev' 'build $(DEV_TAG)'
	@printf '  %-20s %s\n' 'make ffmpeg-shared' 'build $(SHARED_TAG)'
	@printf '  %-20s %s\n' 'make all' 'build all default targets'
	@printf '%s\n' ''
	@printf '%s\n' 'Artifact export/package targets:'
	@printf '  %-20s %s\n' 'make package' 'build, export, and package default targets'
	@printf '  %-20s %s\n' 'make package-all' 'build, export, and package every target'
	@printf '  %-20s %s\n' 'make export-shared' 'export $(SHARED_TAG) rootfs to $(EXPORT_DIR)/ffmpeg-shared'
	@printf '  %-20s %s\n' 'make clean-artifacts' 'remove $(DIST_DIR)'
	@printf '%s\n' ''
	@printf '%s\n' 'Opt-in patent-encumbered targets:'
	@printf '  %-20s %s\n' 'make openh264-runtime' 'build $(OPENH264_TAG), without Cisco binary baked in'
	@printf '  %-20s %s\n' 'make amr-runtime' 'build $(AMR_TAG)'
	@printf '  %-20s %s\n' 'make opt-in' 'build both opt-in targets'
	@printf '%s\n' ''
	@printf '%s\n' 'Checks and smokes:'
	@printf '  %-20s %s\n' 'make docker-check' 'run Dockerfile static checks'
	@printf '  %-20s %s\n' 'make smoke-openh264' 'download sidecar and test libopenh264 encode'
	@printf '  %-20s %s\n' 'make smoke-amr' 'test AMR encode/decode in $(AMR_TAG)'
	@printf '  %-20s %s\n' 'make smoke-opt-in' 'run both opt-in smokes'
	@printf '%s\n' ''
	@printf '%s\n' 'Native macOS shared target:'
	@printf '  %-20s %s\n' 'make macos-deps' 'check Homebrew dependencies for macOS builds'
	@printf '  %-20s %s\n' 'make macos-shared' 'build native macOS shared artifact at $(MACOS_PREFIX)'
	@printf '  %-20s %s\n' 'make verify-macos-shared' 'run macOS license gate'
	@printf '  %-20s %s\n' 'make package-macos-shared' 'build, verify, and package macOS shared artifact'
	@printf '%s\n' ''
	@printf '%s\n' 'Useful overrides: IMAGE=repo/oski VERSION=8.0 PLATFORM=linux/amd64 NO_CACHE=1 PULL=1'
	@printf '%s\n' 'Native macOS overrides: MACOS_ARCHS="arm64 x86_64" MACOS_DEPLOYMENT_TARGET=12.0'

.PHONY: all defaults
all defaults: ffmpeg-bin ffmpeg-dev ffmpeg-shared

.PHONY: opt-in
opt-in: openh264-runtime amr-runtime

.PHONY: release-local
release-local: all opt-in

.PHONY: compile compile-defaults compile-opt-in compile-all
compile compile-defaults: all
compile-opt-in: opt-in
compile-all: release-local

.PHONY: docker-check
docker-check:
	$(DOCKER) build --check $(PLATFORM_FLAG) $(BUILD_ARGS) .

.PHONY: macos-deps macos-deps-install
macos-deps:
	"$(MACOS_DIR)/homebrew-deps.sh" check

macos-deps-install:
	"$(MACOS_DIR)/homebrew-deps.sh" install

.PHONY: macos-shared verify-macos-shared package-macos-shared clean-macos
macos-shared:
	OSKI_VERSION="$(VERSION)" \
	OSKI_MACOS_ARCHS="$(MACOS_ARCHS)" \
	OSKI_MACOS_DEPLOYMENT_TARGET="$(MACOS_DEPLOYMENT_TARGET)" \
	OSKI_MACOS_BUILD_ROOT="$(MACOS_BUILD_ROOT)" \
	OSKI_MACOS_PREFIX="$(MACOS_PREFIX)" \
	"$(MACOS_DIR)/build-shared.sh"

verify-macos-shared:
	"$(MACOS_DIR)/verify-license.sh" "$(MACOS_PREFIX)"

package-macos-shared: macos-shared verify-macos-shared
	mkdir -p "$(PACKAGE_DIR)"
	tar -C "$(MACOS_PREFIX)" -czf "$(MACOS_PACKAGE)" .
	@printf 'Packaged macos-shared as %s\n' "$(MACOS_PACKAGE)"

clean-macos:
	rm -rf "$(DIST_DIR)/macos" "$(MACOS_PACKAGE)"

.PHONY: ffmpeg-bin bin
ffmpeg-bin bin:
	$(DOCKER) build $(BUILD_FLAGS) --target ffmpeg-bin --tag $(BIN_TAG) .

.PHONY: ffmpeg-dev dev
ffmpeg-dev dev:
	$(DOCKER) build $(BUILD_FLAGS) --target ffmpeg-dev --tag $(DEV_TAG) .

.PHONY: ffmpeg-shared shared
ffmpeg-shared shared:
	$(DOCKER) build $(BUILD_FLAGS) --target ffmpeg-shared --tag $(SHARED_TAG) .

.PHONY: openh264-runtime openh264
openh264-runtime openh264:
	$(DOCKER) build $(BUILD_FLAGS) --target openh264-runtime --tag $(OPENH264_TAG) .

.PHONY: amr-runtime amr
amr-runtime amr:
	$(DOCKER) build $(BUILD_FLAGS) --target amr-runtime --tag $(AMR_TAG) .

.PHONY: export-defaults export-opt-in export-all
export-defaults: export-ffmpeg-bin export-ffmpeg-dev export-ffmpeg-shared
export-opt-in: export-openh264-runtime export-amr-runtime
export-all: export-defaults export-opt-in

.PHONY: export-ffmpeg-bin export-bin
export-ffmpeg-bin export-bin: ffmpeg-bin
	$(call EXPORT_ROOTFS,ffmpeg-bin,$(BIN_TAG))

.PHONY: export-ffmpeg-dev export-dev
export-ffmpeg-dev export-dev: ffmpeg-dev
	$(call EXPORT_ROOTFS,ffmpeg-dev,$(DEV_TAG))

.PHONY: export-ffmpeg-shared export-shared
export-ffmpeg-shared export-shared: ffmpeg-shared
	$(call EXPORT_ROOTFS,ffmpeg-shared,$(SHARED_TAG))

.PHONY: export-openh264-runtime export-openh264
export-openh264-runtime export-openh264: openh264-runtime
	$(call EXPORT_ROOTFS,openh264-runtime,$(OPENH264_TAG))

.PHONY: export-amr-runtime export-amr
export-amr-runtime export-amr: amr-runtime
	$(call EXPORT_ROOTFS,amr-runtime,$(AMR_TAG))

.PHONY: package package-defaults package-opt-in package-all
package package-defaults: package-ffmpeg-bin package-ffmpeg-dev package-ffmpeg-shared
package-opt-in: package-openh264-runtime package-amr-runtime
package-all: package-defaults package-opt-in

.PHONY: package-ffmpeg-bin package-bin
package-ffmpeg-bin package-bin: export-ffmpeg-bin
	$(call PACKAGE_ROOTFS,ffmpeg-bin)

.PHONY: package-ffmpeg-dev package-dev
package-ffmpeg-dev package-dev: export-ffmpeg-dev
	$(call PACKAGE_ROOTFS,ffmpeg-dev)

.PHONY: package-ffmpeg-shared package-shared
package-ffmpeg-shared package-shared: export-ffmpeg-shared
	$(call PACKAGE_ROOTFS,ffmpeg-shared)

.PHONY: package-openh264-runtime package-openh264
package-openh264-runtime package-openh264: export-openh264-runtime
	$(call PACKAGE_ROOTFS,openh264-runtime)

.PHONY: package-amr-runtime package-amr
package-amr-runtime package-amr: export-amr-runtime
	$(call PACKAGE_ROOTFS,amr-runtime)

.PHONY: clean-artifacts
clean-artifacts:
	rm -rf "$(DIST_DIR)"

.PHONY: smoke-openh264
smoke-openh264: openh264-runtime
	$(DOCKER) run --rm --entrypoint /bin/sh $(OPENH264_TAG) -c 'oski-openh264 enable --accept-license && /ffmpeg -f lavfi -i testsrc=duration=0.1 -c:v libopenh264 -profile:v constrained_baseline -f null - && oski-openh264 status && oski-openh264 disable'

.PHONY: smoke-amr
smoke-amr: amr-runtime
	$(DOCKER) run --rm --entrypoint /bin/sh $(AMR_TAG) -c '/ffmpeg -f lavfi -i sine=frequency=440:duration=0.1 -c:a libopencore_amrnb -ar 8000 -ac 1 -f amr -y /tmp/out.amr && /ffmpeg -i /tmp/out.amr -f null -'

.PHONY: smoke-opt-in
smoke-opt-in: smoke-openh264 smoke-amr

.PHONY: inspect-license inspect-buildconf inspect-tags
inspect-license:
	$(DOCKER) run --rm --entrypoint /ffmpeg $(BIN_TAG) -hide_banner -L

inspect-buildconf:
	$(DOCKER) run --rm --entrypoint /ffmpeg $(BIN_TAG) -hide_banner -buildconf

inspect-tags:
	@printf '%s\n' '$(BIN_TAG)'
	@printf '%s\n' '$(DEV_TAG)'
	@printf '%s\n' '$(SHARED_TAG)'
	@printf '%s\n' '$(OPENH264_TAG)'
	@printf '%s\n' '$(AMR_TAG)'

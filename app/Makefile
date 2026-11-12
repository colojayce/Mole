# MoleUI build helpers. Recipe lines must start with a TAB.
SWIFT ?= swift
CONFIG ?= debug
APP_NAME := MoleUI
BUILD_DIR := build
APP_DIR := $(BUILD_DIR)/$(APP_NAME).app
REPO_ROOT := $(abspath $(CURDIR)/..)

.PHONY: build test bundle run clean

build:
	$(SWIFT) build -c $(CONFIG)

test:
	$(SWIFT) test

bundle: build
	@bin_dir="$$($(SWIFT) build -c $(CONFIG) --show-bin-path)"; \
	mkdir -p "$(APP_DIR)/Contents/MacOS"; \
	cp "$$bin_dir/$(APP_NAME)" "$(APP_DIR)/Contents/MacOS/$(APP_NAME)"; \
	sed "s|@MOLE_REPO_PATH@|$(REPO_ROOT)|g" Info.plist.in > "$(APP_DIR)/Contents/Info.plist"; \
	codesign --force --sign - "$(APP_DIR)" > /dev/null; \
	echo "Bundled $(APP_DIR) (mole repo: $(REPO_ROOT))"

run: bundle
	open "$(APP_DIR)"

clean:
	rm -rf "$(BUILD_DIR)"

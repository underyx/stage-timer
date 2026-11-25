# Stage Screen. The laptop and CI both build through here, so they run the same commands.
#
#   make test      generate the project, build for a simulator, run Tests/ inside the app
#   make core      swift test: Tests/Core with no simulator (needs the root Package.swift)
#   make build     Release build for a device, unsigned: compiles what an archive would
#   make archive   signed Release archive in build/ (the Mac only)
#   make upload    archive, upload to App Store Connect, tag the build (the Mac only)
#   make version   the version and build that project.yml would upload next
#   make gen       just regenerate StageTimer.xcodeproj and Sources/Info.plist
#   make clean     remove build/ and everything generated
#
# macOS ships GNU make 3.81: no .ONESHELL and no .SHELLFLAGS. Every recipe that pipes xcodebuild
# sets pipefail itself; without it a failed build piped into xcbeautify exits 0.
SHELL := /bin/bash

PROJECT := StageTimer.xcodeproj
SCHEME := StageTimer
BUILD_DIR := build
DERIVED := $(BUILD_DIR)/DerivedData
ARCHIVE := $(BUILD_DIR)/StageTimer.xcarchive

VERSION := $(shell sed -n 's/^ *MARKETING_VERSION: *"\(.*\)" *$$/\1/p' project.yml)
BUILD := $(shell sed -n 's/^ *CURRENT_PROJECT_VERSION: *"\(.*\)" *$$/\1/p' project.yml)
TAG := v$(VERSION)-$(BUILD)

# Extra xcodebuild flags for the signed steps, e.g. an App Store Connect API key instead of the
# account Xcode is signed in to:
#   make upload AUTH="-authenticationKeyPath /path/AuthKey_X.p8 -authenticationKeyID X -authenticationKeyIssuerID Y"
AUTH ?=

# Readable logs where xcbeautify is installed (it is on GitHub's images); raw xcodebuild otherwise.
PRETTY := $(shell command -v xcbeautify >/dev/null 2>&1 && echo "| xcbeautify $(if $(GITHUB_ACTIONS),--renderer github-actions,)")

XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME)

.PHONY: gen test core build archive upload check-release version clean

gen:
	@command -v xcodegen >/dev/null || { echo "error: xcodegen isn't installed (brew install xcodegen)"; exit 1; }
	xcodegen generate

# Unsigned, and with an empty PostHog key: the tests run inside the app, and a test run must not
# start the SDK and report a simulator as a user.
test: gen
	@rm -rf $(BUILD_DIR)/test.xcresult
	set -o pipefail; destination=$$(scripts/sim-destination.sh) && \
	$(XCODEBUILD) test -destination "$$destination" -derivedDataPath $(DERIVED) \
		-resultBundlePath $(BUILD_DIR)/test.xcresult \
		CODE_SIGNING_ALLOWED=NO POSTHOG_API_KEY= $(PRETTY)

core:
	@[ -f Package.swift ] || { echo "error: no Package.swift here, so there is no SwiftPM test target to run"; exit 1; }
	swift test

build: gen
	set -o pipefail; $(XCODEBUILD) build -configuration Release -destination 'generic/platform=iOS' \
		-derivedDataPath $(DERIVED) CODE_SIGNING_ALLOWED=NO $(PRETTY)

archive: gen
	set -o pipefail; $(XCODEBUILD) archive -configuration Release -destination 'generic/platform=iOS' \
		-archivePath $(ARCHIVE) -allowProvisioningUpdates $(AUTH) $(PRETTY)

# App Store Connect refuses a build number it has seen, after the whole archive and upload. The
# tag each upload leaves behind is how that is caught here first, and how anyone later knows
# which commit a build was.
check-release:
	@if [ -n "$$(git status --porcelain)" ] && [ -z "$(ALLOW_DIRTY)" ]; then \
		echo "error: uncommitted changes. Commit them, so the build can be traced to a commit (ALLOW_DIRTY=1 overrides)."; exit 1; fi
	@if git rev-parse -q --verify "refs/tags/$(TAG)" >/dev/null; then \
		echo "error: the tag $(TAG) exists, so build $(BUILD) was already uploaded. Raise CURRENT_PROJECT_VERSION in project.yml."; exit 1; fi

upload: check-release archive
	xcodebuild -exportArchive -archivePath $(ARCHIVE) -exportOptionsPlist scripts/export-testflight.plist \
		-exportPath $(BUILD_DIR)/export -allowProvisioningUpdates $(AUTH)
	git tag $(TAG)
	@echo "Uploaded Stage Screen $(VERSION) ($(BUILD)) and tagged it $(TAG). Now: git push origin $(TAG)"

version:
	@echo "Stage Screen $(VERSION) ($(BUILD))"

clean:
	rm -rf $(BUILD_DIR) $(PROJECT) Sources/Info.plist

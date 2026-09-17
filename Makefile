# Convenience targets for building Lithe from the command line.
#
# xcodebuild honors compiler/linker environment variables (LD, CC, SDKROOT, …).
# A conda-activated shell exports its own toolchain through those variables,
# which breaks the link step, so they are cleared before invoking xcodebuild.

PROJECT   := Lithe.xcodeproj
SCHEME    := Lithe
DERIVED   := build/DerivedData
DIST      := dist
CLEAN_ENV := env -u LD -u CC -u CXX -u CPP -u CLANG -u AR -u NM -u RANLIB -u LIBTOOL -u STRIP \
             -u CFLAGS -u CXXFLAGS -u LDFLAGS -u SDKROOT -u MACOSX_DEPLOYMENT_TARGET
XCODEBUILD := $(CLEAN_ENV) xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(DERIVED)
SIGNING   := CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO
VERSION   := $(shell sed -n 's/^ *MARKETING_VERSION: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/p' project.yml)

.PHONY: all project build release test run install clean lint icon hooks

all: build

## Regenerate Lithe.xcodeproj from project.yml (requires `brew install xcodegen`).
## The project file is generated and gitignored; edit project.yml instead.
project: $(PROJECT)

$(PROJECT): project.yml
	xcodegen generate

## Debug build into build/DerivedData.
build: $(PROJECT)
	$(XCODEBUILD) -configuration Debug -destination 'platform=macOS' $(SIGNING) build 2>&1 | $(FILTER)

## Universal (Apple silicon + Intel) Release build.
release: $(PROJECT)
	$(XCODEBUILD) -configuration Release -destination 'generic/platform=macOS' $(SIGNING) build 2>&1 | $(FILTER)
	@mkdir -p $(DIST)
	rm -rf $(DIST)/Lithe.app
	cp -R $(DERIVED)/Build/Products/Release/Lithe.app $(DIST)/Lithe.app
	cd $(DIST) && rm -f Lithe-$(VERSION).zip && ditto -c -k --keepParent Lithe.app Lithe-$(VERSION).zip
	@echo "Built $(DIST)/Lithe-$(VERSION).zip"

## Run the unit tests.
test: $(PROJECT)
	$(XCODEBUILD) -configuration Debug -destination 'platform=macOS' $(SIGNING) test 2>&1 | $(FILTER)

## Build and launch the debug app.
run: build
	open $(DERIVED)/Build/Products/Debug/Lithe.app

## Release build copied to /Applications.
install: release
	rm -rf /Applications/Lithe.app
	cp -R $(DIST)/Lithe.app /Applications/Lithe.app
	@echo "Installed /Applications/Lithe.app"

lint:
	swiftlint lint --strict

## Regenerate the app icon PNGs from Scripts/make-icon.swift.
icon:
	$(CLEAN_ENV) swift Scripts/make-icon.swift

## Install the git pre-commit hook (SwiftLint on staged Swift files).
hooks:
	cp Scripts/pre-commit .git/hooks/pre-commit
	chmod +x .git/hooks/pre-commit
	@echo "Installed .git/hooks/pre-commit"

clean:
	rm -rf build $(DIST) $(PROJECT)

# Keep xcodebuild's output readable: show errors, warnings from our sources,
# test results and the final status line.
FILTER := grep -E --line-buffered 'error:|warning: .*/Lithe/|Test (Case|Suite)|passed|failed|BUILD|TEST|Executed' | grep -v -E 'DVT|CoreSimulator|plug-in|Symbol not found|CoreDevice' || true

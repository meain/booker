BIN := ./.build/debug/booker
APP := Booker.app
SHOT := .claude/skills/screenshot-test/shot.sh

# Query for `run`/`rank`/`shot`, e.g. `make rank Q=github`
Q ?=

.PHONY: build release app run list rank shot lint format install link clean help

help:
	@echo "Targets:"
	@echo "  build     Debug build (default)"
	@echo "  release   Release build"
	@echo "  app       Build Booker.app bundle"
	@echo "  run       Launch the picker GUI (Q=<query> pre-fills search)"
	@echo "  list      Headless: dump parsed bookmarks"
	@echo "  rank      Headless: rank results for Q=<query>"
	@echo "  shot      Render GUI to PNG for Q=<query> (see screenshot-test skill)"
	@echo "  lint      Check formatting (swift-format, as CI does)"
	@echo "  format    Auto-format sources in place"
	@echo "  install   Copy Booker.app to /Applications"
	@echo "  link      Symlink Booker.app to /Applications"
	@echo "  clean     Remove build artifacts"

lint:
	swift format lint --strict --recursive --configuration .swift-format Sources

format:
	swift format --in-place --recursive --configuration .swift-format Sources

build:
	swift build

release:
	swift build -c release

app:
	./build-app.sh

run: build
	$(BIN) $(Q)

list: build
	$(BIN) list

rank: build
	$(BIN) rank $(Q)

shot: build
	@$(SHOT) '$(Q)'

install: app
	rm -rf /Applications/$(APP)
	cp -R $(APP) /Applications/
	@echo "Installed to /Applications/$(APP)"

link: app
	rm -f /Applications/$(APP)
	ln -s $(CURDIR)/$(APP) /Applications/$(APP)
	@echo "Linked $(CURDIR)/$(APP) -> /Applications/$(APP)"

clean:
	rm -rf .build $(APP)

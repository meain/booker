BIN := ./.build/debug/booker
APP := Booker.app
SHOT := .claude/skills/screenshot-test/shot.sh

# Query for `run`/`rank`/`shot`, e.g. `make rank Q=github`
Q ?=

.PHONY: build release app run list rank shot install clean help

help:
	@echo "Targets:"
	@echo "  build     Debug build (default)"
	@echo "  release   Release build"
	@echo "  app       Build Booker.app bundle"
	@echo "  run       Launch the picker GUI (Q=<query> pre-fills search)"
	@echo "  list      Headless: dump parsed bookmarks"
	@echo "  rank      Headless: rank results for Q=<query>"
	@echo "  shot      Render GUI to PNG for Q=<query> (see screenshot-test skill)"
	@echo "  install   Copy Booker.app to /Applications"
	@echo "  clean     Remove build artifacts"

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

clean:
	rm -rf .build $(APP)

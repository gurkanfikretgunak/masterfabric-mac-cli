.PHONY: build release install uninstall test-info clean screenshot version-sync version-check

PREFIX ?= $(HOME)/.local
BIN_DIR := $(PREFIX)/bin
APP_DIR := $(PREFIX)/MasterFabricMenuBar.app
VERSION := $(shell tr -d '[:space:]' < VERSION 2>/dev/null || echo 0.0.0)

build: version-sync
	swift build

release: version-sync
	swift build -c release

install: release
	mkdir -p "$(BIN_DIR)"
	mkdir -p "$(APP_DIR)/Contents/MacOS"
	mkdir -p "$(APP_DIR)/Contents/Resources"
	cp -f .build/release/mf "$(BIN_DIR)/mf"
	cp -f .build/release/MasterFabricMenuBar "$(APP_DIR)/Contents/MacOS/MasterFabricMenuBar"
	cp -f .build/release/MasterFabricMenuBar "$(BIN_DIR)/MasterFabricMenuBar"
	chmod +x "$(BIN_DIR)/mf" "$(BIN_DIR)/MasterFabricMenuBar" "$(APP_DIR)/Contents/MacOS/MasterFabricMenuBar"
	# Bundle official Slack / Telegram logos into the .app Resources
	cp -f Sources/MasterFabricMenuBar/Resources/brand-slack.png "$(APP_DIR)/Contents/Resources/brand-slack.png"
	cp -f Sources/MasterFabricMenuBar/Resources/brand-telegram.png "$(APP_DIR)/Contents/Resources/brand-telegram.png"
	# SPM resource bundle (optional) — prefer Contents/Resources PNGs; keep bundle for bin launch
	@bundle=$$(ls -d .build/*/release/MasterFabric_MasterFabricMenuBar.bundle .build/release/MasterFabric_MasterFabricMenuBar.bundle 2>/dev/null | head -1); \
	if [ -n "$$bundle" ]; then \
		rm -rf "$(BIN_DIR)/MasterFabric_MasterFabricMenuBar.bundle"; \
		cp -R "$$bundle" "$(BIN_DIR)/"; \
		rm -rf "$(APP_DIR)/Contents/Resources/MasterFabric_MasterFabricMenuBar.bundle"; \
		cp -R "$$bundle" "$(APP_DIR)/Contents/Resources/"; \
	fi
	# macOS (esp. Tahoe+) kills unsigned binaries with SIGKILL — ad-hoc sign after copy
	xattr -cr "$(BIN_DIR)/mf" "$(BIN_DIR)/MasterFabricMenuBar" "$(APP_DIR)" 2>/dev/null || true
	codesign --force --sign - "$(BIN_DIR)/mf"
	codesign --force --sign - "$(BIN_DIR)/MasterFabricMenuBar"
	codesign --force --sign - "$(APP_DIR)/Contents/MacOS/MasterFabricMenuBar"
	codesign --force --deep --sign - "$(APP_DIR)"
	@printf '%s\n' \
	'<?xml version="1.0" encoding="UTF-8"?>' \
	'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
	'<plist version="1.0"><dict>' \
	'<key>CFBundleName</key><string>MasterFabric</string>' \
	'<key>CFBundleDisplayName</key><string>MasterFabric</string>' \
	'<key>CFBundleIdentifier</key><string>com.masterfabric.menubar</string>' \
	'<key>CFBundleVersion</key><string>$(VERSION)</string>' \
	'<key>CFBundleShortVersionString</key><string>$(VERSION)</string>' \
	'<key>CFBundleExecutable</key><string>MasterFabricMenuBar</string>' \
	'<key>CFBundlePackageType</key><string>APPL</string>' \
	'<key>LSMinimumSystemVersion</key><string>13.0</string>' \
	'<key>LSUIElement</key><true/>' \
	'<key>NSHighResolutionCapable</key><true/>' \
	'<key>NSUserNotificationAlertStyle</key><string>alert</string>' \
	'</dict></plist>' > "$(APP_DIR)/Contents/Info.plist"
	@echo "Installed mf v$(VERSION) → $(BIN_DIR)/mf"
	@echo "Installed menu bar app → $(APP_DIR)"
	@echo "Ensure $(BIN_DIR) is on your PATH."

# Keep Sources/.../Version.swift `current` equal to root VERSION file.
version-sync:
	@test -f VERSION || (echo "missing VERSION file" >&2; exit 1)
	@perl -0pi -e 's/public static let current = "[^"]*"/public static let current = "$(VERSION)"/' \
		Sources/MasterFabricCore/Version.swift
	@grep -q 'current = "$(VERSION)"' Sources/MasterFabricCore/Version.swift \
		|| (echo "version-sync failed" >&2; exit 1)
	@echo "Version synced: $(VERSION)"

version-check: release
	.build/release/mf version --check

screenshot:
	swift run GenerateScreenshot

uninstall:
	rm -f "$(BIN_DIR)/mf" "$(BIN_DIR)/MasterFabricMenuBar"
	rm -rf "$(APP_DIR)"
	rm -rf "$(BIN_DIR)/MasterFabric_MasterFabricMenuBar.bundle"

test-info:
	swift run mf info
	swift run mf status
	swift run mf version

clean:
	swift package clean
	rm -rf .build

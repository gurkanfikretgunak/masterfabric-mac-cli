.PHONY: build release install uninstall test-info clean screenshot

PREFIX ?= $(HOME)/.local
BIN_DIR := $(PREFIX)/bin
APP_DIR := $(PREFIX)/MasterFabricMenuBar.app

build:
	swift build

release:
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
	# Also copy SPM resource bundle next to the naked binary (dev / bin launch)
	@bundle=$$(ls -d .build/*/release/MasterFabric_MasterFabricMenuBar.bundle .build/release/MasterFabric_MasterFabricMenuBar.bundle 2>/dev/null | head -1); \
	if [ -n "$$bundle" ]; then \
		rm -rf "$(BIN_DIR)/MasterFabric_MasterFabricMenuBar.bundle"; \
		cp -R "$$bundle" "$(BIN_DIR)/"; \
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
	'<key>CFBundleVersion</key><string>0.2.0</string>' \
	'<key>CFBundleShortVersionString</key><string>0.2.0</string>' \
	'<key>CFBundleExecutable</key><string>MasterFabricMenuBar</string>' \
	'<key>CFBundlePackageType</key><string>APPL</string>' \
	'<key>LSMinimumSystemVersion</key><string>13.0</string>' \
	'<key>LSUIElement</key><true/>' \
	'<key>NSHighResolutionCapable</key><true/>' \
	'</dict></plist>' > "$(APP_DIR)/Contents/Info.plist"
	@echo "Installed mf → $(BIN_DIR)/mf"
	@echo "Installed menu bar app → $(APP_DIR)"
	@echo "Ensure $(BIN_DIR) is on your PATH."

screenshot:
	swift run GenerateScreenshot

uninstall:
	rm -f "$(BIN_DIR)/mf" "$(BIN_DIR)/MasterFabricMenuBar"
	rm -rf "$(APP_DIR)"

test-info:
	swift run mf info
	swift run mf status

clean:
	swift package clean
	rm -rf .build

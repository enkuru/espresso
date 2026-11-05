SWIFT ?= swift
TESTING := /Library/Developer/CommandLineTools/Library/Developer
TEST_FLAGS := -Xswiftc -F -Xswiftc $(TESTING)/Frameworks \
	-Xlinker -rpath -Xlinker $(TESTING)/Frameworks \
	-Xlinker -rpath -Xlinker $(TESTING)/usr/lib
RELEASE := .build/release
APP := build/Espresso.app

.PHONY: app build bundle test install previews clean

app: build bundle

build:
	$(SWIFT) build -c release

# Assembles the .app from an existing release build.
bundle:
	rm -rf $(APP) build/AppIcon.iconset
	$(RELEASE)/espresso-render app-icon build/AppIcon.iconset
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(RELEASE)/Espresso $(APP)/Contents/MacOS/Espresso
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	iconutil -c icns build/AppIcon.iconset -o $(APP)/Contents/Resources/AppIcon.icns
	codesign --force --sign - $(APP)

test:
	$(SWIFT) test $(TEST_FLAGS)

previews: build
	$(RELEASE)/espresso-render previews build/previews

install: app
	-pkill -x Espresso
	mkdir -p $(HOME)/Applications
	rm -rf $(HOME)/Applications/Espresso.app
	ditto $(APP) $(HOME)/Applications/Espresso.app
	open $(HOME)/Applications/Espresso.app

clean:
	rm -rf .build build

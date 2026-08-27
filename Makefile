.PHONY: build test app icon run clean

build:
	swift build

test:
	swift test

icon:
	./Scripts/make-icon.sh

app:
	./Scripts/make-app.sh

run: app
	open build/Wave.app

clean:
	swift package clean
	rm -rf build

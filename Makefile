.PHONY: build test app run clean

build:
	swift build

test:
	swift test

app:
	./Scripts/make-app.sh

run: app
	open build/Wave.app

clean:
	swift package clean
	rm -rf build

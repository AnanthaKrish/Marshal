.PHONY: build run test app open clean readme-art release-preview release

build:
	swift build

run:
	swift run Marshal

test:
	swift test
	python3 Scripts/test-release.py

readme-art: build
	.build/debug/Marshal --readme-art docs/media

app:
	Scripts/build-app.sh release

open: app
	open build/Marshal.app

release-preview:
	Scripts/package-release.sh --preview "v$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"

release:
	Scripts/package-release.sh "$(TAG)"

clean:
	rm -rf .build build

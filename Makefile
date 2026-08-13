.PHONY: build app run clean

build:
	swift build -c release

app: build
	bash Scripts/make_app.sh

run: app
	open build/AvilaVoice.app

clean:
	rm -rf .build build

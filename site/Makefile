.PHONY: build lint images indexnow
build:
	python3 scripts/build.py

lint: build
	python3 scripts/check.py

images:
	bash scripts/render-images.sh

# After a production deploy from main only. ALL=1 pings every URL.
indexnow: build
	python3 scripts/indexnow.py

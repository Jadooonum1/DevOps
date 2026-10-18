IMAGE ?= catalog-api
TAG   ?= local
VENV  ?= .venv
PY    := $(VENV)/bin/python

.PHONY: venv lint test build run smoke clean

venv:
	python3 -m venv $(VENV)
	$(PY) -m pip install -q -r requirements-dev.txt

lint:
	$(PY) -m flake8 catalog tests

test:
	$(PY) -m pytest

build:
	docker build --build-arg GIT_SHA=$$(git rev-parse --short HEAD 2>/dev/null || echo dev) -t $(IMAGE):$(TAG) .

run: build
	docker run -d --rm --name $(IMAGE) -p 8000:8000 $(IMAGE):$(TAG)

smoke:
	curl -fsS http://localhost:8000/healthz && echo
	curl -fsS http://localhost:8000/books && echo

clean:
	-docker rm -f $(IMAGE)
	-docker rmi $(IMAGE):$(TAG)
	rm -rf .pytest_cache

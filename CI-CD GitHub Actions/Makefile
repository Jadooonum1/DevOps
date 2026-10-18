IMAGE ?= catalog-api
TAG   ?= local
VENV  ?= .venv
PORT  ?= 8000
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
	docker run -d --rm --name $(IMAGE) -p $(PORT):8000 $(IMAGE):$(TAG)

smoke:
	curl -fsS http://localhost:$(PORT)/healthz && echo
	curl -fsS http://localhost:$(PORT)/books && echo

clean:
	-docker rm -f $(IMAGE)
	-docker rmi $(IMAGE):$(TAG)
	rm -rf .pytest_cache

.PHONY: help all setup deps build fmt fmt-check lint test coverage ci dialyzer e2e

MIX ?= mix

UNAME_S := $(shell uname -s)
UNAME_M := $(shell uname -m)

ifeq ($(UNAME_S),Darwin)
    ifeq ($(UNAME_M),arm64)
        BURRITO_TARGET ?= macos_silicon
    else
        BURRITO_TARGET ?= macos
    endif
else ifeq ($(UNAME_S),Linux)
    BURRITO_TARGET ?= linux
else
    BURRITO_TARGET ?= windows
endif

help:
	@echo "Targets: setup, deps, fmt, fmt-check, lint, test, coverage, dialyzer, e2e, ci"

setup:
	$(MIX) setup

deps:
	$(MIX) deps.get

build:
	$(MIX) build

fmt:
	$(MIX) format

fmt-check:
	$(MIX) format --check-formatted

lint:
	$(MIX) lint

coverage:
	$(MIX) test --cover

test:
	$(MIX) test

dialyzer:
	$(MIX) deps.get
	$(MIX) dialyzer --format short

e2e:
	SYMPHONY_RUN_LIVE_E2E=1 $(MIX) test test/symphony_elixir/live_e2e_test.exs

ci:
	$(MAKE) setup
	$(MAKE) build
	$(MAKE) fmt-check
	$(MAKE) lint
	$(MAKE) coverage
	$(MAKE) dialyzer

all: ci

release:
	BURRITO_TARGET=$(BURRITO_TARGET) MIX_ENV=prod $(MIX) release

install: release
	mkdir -p ~/.local/bin
	cp burrito_out/symphony_$(BURRITO_TARGET) ~/.local/bin/symphony

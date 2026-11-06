GO ?= go
GOLANGCI_LINT_VERSION := v2.7.0
GITLEAKS_VERSION := 8.30.1
export PATH := $(CURDIR)/bin:$(PATH)

.PHONY: test lint lint-go lint-artifacts build install-tools

test:
	$(GO) test -race ./cmd/... ./internal/...

lint: lint-go lint-artifacts

lint-go:
	@test "$$(golangci-lint version | sed -n 's/.* version \([^ ]*\).*/v\1/p')" = "$(GOLANGCI_LINT_VERSION)" || { echo "Install golangci-lint $(GOLANGCI_LINT_VERSION); see docs/validation.md"; exit 2; }
	golangci-lint run ./cmd/... ./internal/...
	@test -z "$$(gofmt -l cmd internal)" || { echo "Run gofmt on cmd/ and internal/"; exit 1; }

lint-artifacts:
	$(GO) run ./cmd/verify-artifacts --secrets

build:
	$(GO) build -o bin/verify-artifacts ./cmd/verify-artifacts

# Explicit opt-in bootstrap; lint targets never install tools automatically.
install-tools:
	GOBIN="$(CURDIR)/bin" $(GO) install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@$(GOLANGCI_LINT_VERSION)
	GOBIN="$(CURDIR)/bin" $(GO) install -ldflags '-X github.com/zricethezav/gitleaks/v8/version.Version=$(GITLEAKS_VERSION)' github.com/zricethezav/gitleaks/v8@v$(GITLEAKS_VERSION)

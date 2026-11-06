# HyperShift Test Results & Verification

Centralized repository for HyperShift test plans and pre-merge verification
reports. Replaces the previous pattern of self-hosting these artifacts in
individual personal GitHub repositories.

## Repository Structure

```
.
├── plans/                  # Test plans (Markdown; IEEE 829 for new plans)
│   ├── <jira-key>.md       # Plan linked to a Jira issue (e.g. ocpstrat-3298.md)
│   └── <slug>.md           # Plan without a Jira issue (e.g. csi-snapshot-validation.md)
├── reports/                # Verification reports (HTML bundle or Markdown)
│   └── <jira-key>/         # Reports grouped by Jira issue
│       ├── metadata.yaml   # Required report metadata
│       ├── index.html      # HTML bundle entry-point (preferred format)
│       ├── scenario-N.html # Per-scenario detail pages
│       ├── appendices.html # Supplementary evidence
│       ├── automated-tests.html  # CI / automated-test results
│       ├── assets/         # Screenshots, diagrams
│       ├── scripts/        # Helper scripts used in testing
│       ├── derived/        # Optional IEEE 829 Markdown derived from HTML
│       │   └── report.md
│       └── <pr-number>.md  # OR: lightweight Markdown report per PR
├── docs/                   # Repository documentation
│   ├── format.md           # Metadata model, format specification, relationships
│   └── migration.md        # Migration guide and inventory
├── AGENTS.md               # Non-negotiable rules for AI agents
├── CONTRIBUTING.md         # How to add plans and reports
└── README.md               # This file
```

### Plans (`plans/`)

Each test plan is a single Markdown file with YAML front-matter metadata.
**New and materially rewritten plans must declare `ieee_829: true`** and
cover the content areas in the [format specification](docs/format.md#plan-body-structure).
Equivalent headings and numbering are supported. Structural validation does
not certify compliance with the IEEE standard or assess test quality.

Legacy lightweight/incomplete plans can be preserved through
[explicit reviewed exceptions](docs/validation.md#legacy-and-adaptation-exceptions).
Missing metadata must not be fabricated, and minor metadata-only updates do
not force a rewrite.

A single plan can reference multiple Jira issues and PRs to support backport
workflows. See [docs/format.md](docs/format.md#naming-conventions) for naming
conventions and the metadata model.

### Reports (`reports/`)

Verification reports capture the results of executing a test plan against a
specific PR. Reports are grouped into subdirectories named by Jira issue key.

Reports support **two formats**:

- **HTML bundle (preferred)** — a self-contained directory with `index.html`,
  per-scenario pages (`scenario-N.html`), appendices, automated-test results,
  images, and helper scripts. This is the existing format used by OCPBUGS and
  CNTRLPLANE verification reports.
- **Markdown** — a lightweight single-file report (`<pr-number>.md`) following
  the template in [docs/format.md](docs/format.md#markdown-report-template).

> **Format policy:** HTML bundles are stored as-is; they must **not** be
> converted to Markdown during migration. An IEEE 829 Markdown summary _may_
> optionally be derived from an HTML bundle (placed in `derived/report.md`),
> but derivation must not replace or discard the original HTML.

### Documentation (`docs/`)

- **[docs/format.md](docs/format.md)** — Metadata model, naming conventions,
  format specification, and relationship model (1-to-N Jira/PR support).
- **[docs/migration.md](docs/migration.md)** — Guide for migrating existing
  test plans from personal repositories, including a migration inventory.

## Quick Start

1. Read the [contribution guide](CONTRIBUTING.md).
2. Review the [format specification](docs/format.md) for metadata requirements.
3. Copy an existing plan from `plans/` or use the template in
   [docs/format.md](docs/format.md#plan-template).
4. Open a PR adding your plan or report.

## Validation

Run `make install-tools` once, then `make test lint build` before submitting.
`make lint-go` runs golangci-lint on the Go implementation;
`make lint-artifacts` validates plans, reports, local navigation, and sanitization.
The same checks run in GitHub Actions. See [validation](docs/validation.md) for
prerequisites, diagnostics, security limitations, and legacy handling.
CI uses the shared ARM64 self-hosted runners and requires the
[repository-scoped ARC registration](docs/runners.md).

## Automation Integration

This repository is designed for integration with
[Chai Bot](https://github.com/openshift/ai-helpers) and the `ai-helpers`
skill library. The target workflow:

```
@chai-bot make a test plan for JIRA-1234 and add it to test-results-verification
```

See [docs/format.md](docs/format.md#automation-integration-contract) for the
integration contract that automation must follow when generating or updating
plans.

> **Status:** Automation integration is tracked in
> [CNTRLPLANE-4323](https://issues.redhat.com/browse/CNTRLPLANE-4323).
> The contract is documented; implementation in the `ai-helpers` skill
> library is a follow-up.

## Related Links

- [openshift/hypershift](https://github.com/openshift/hypershift) — main
  HyperShift repository
- [Jira: CNTRLPLANE-4323](https://issues.redhat.com/browse/CNTRLPLANE-4323) —
  tracking issue for this repository's structure

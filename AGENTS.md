# Agent Guide

This repository stores HyperShift **test plans** and **verification reports**.
For full details see [CONTRIBUTING.md](CONTRIBUTING.md),
[docs/format.md](docs/format.md), and [docs/migration.md](docs/migration.md).

## Non-Negotiable Rules

1. **Plans (`plans/`)** — Markdown with YAML front-matter, one file per feature.
   New and materially rewritten plans require `ieee_829: true` and the content
   areas in [docs/format.md](docs/format.md#plan-body-structure); equivalent
   headings and numbering are supported.
   Required metadata (discoverability core): `id`, `title`, `date`, `status`.
   Recommended when applicable: `version`, `jira_issues`, `pull_requests`.
   Legacy/incomplete artifacts need explicit reviewed exceptions as described
   in [docs/validation.md](docs/validation.md#legacy-and-adaptation-exceptions).
   Preserve source content and document gaps without fabricating facts.

2. **Reports (`reports/`)** — HTML bundles are the preferred and authoritative
   format. A bundle directory must contain `metadata.yaml` and `index.html`;
   it may also include `scenario-N.html` pages, `appendices.html`,
   `automated-tests.html`, an `assets/` folder, and a `scripts/` folder.
   Markdown reports (`<pr-number>.md`) are also supported.

3. **Derived Markdown is optional** — `derived/report.md` is a convenience
   copy; the HTML bundle is always authoritative. Never delete HTML files
   after generating a Markdown summary.

4. **Content sanitization** — never commit secrets, credentials, bearer
   tokens, private keys, PII, customer data, or private/internal URLs.
   Replace real identifiers with placeholders.

5. **Preserve existing scope** — do not convert HTML bundles to Markdown
   during migration. Validate the complete diff before pushing.

## Development Checks

Run `make test lint build` before committing. Tool setup and rule/exception
reference: [docs/validation.md](docs/validation.md). Test the public validator
and CLI boundaries with offline, behavior-focused tests. Keep report scripts
and embedded JavaScript as data: validation must never execute them.

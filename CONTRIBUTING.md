# Contributing

This guide covers how to add test plans and verification reports to this
repository.

## Before You Start

- Read the [format specification](docs/format.md) for metadata requirements
  and the relationship model.
- Check `plans/` for an existing plan that covers your feature — you may only
  need to add a report, not a new plan.

## Adding a Test Plan

### 1. Choose a filename

Use the naming conventions in [docs/format.md](docs/format.md#naming-conventions):
lowercase Jira key (e.g. `plans/ocpstrat-3298.md`) or descriptive slug
(e.g. `plans/csi-snapshot-validation.md`).

### 2. Write the plan

Start from the [plan template](docs/format.md#plan-template) or copy an
existing plan from `plans/`. Every plan **must** include the YAML front-matter
metadata block with the required core fields (`id`, `title`, `date`,
`status`). Relationship fields (`version`, `jira_issues`, `pull_requests`)
are recommended when applicable — see
[docs/format.md](docs/format.md#metadata-block) for the full field reference.

**New and materially rewritten plans must set `ieee_829: true`.** Cover the
seven content areas in [docs/format.md](docs/format.md#plan-body-structure).
Equivalent headings and different numbering are valid. Reviewers still assess
whether the strategy, steps, acceptance criteria, and evidence are sufficient.

Preserve incomplete historical content through the
[reviewed-exception process](docs/validation.md#legacy-and-adaptation-exceptions),
not by filling gaps with invented facts. A `draft` status alone is not an exemption.

### 3. Open a pull request

- Branch from `main`.
- Add your file under `plans/`.
- Use a descriptive PR title: `<JIRA-KEY>: Add test plan for <feature>`.
- Request review from at least one team member.

## Adding a Verification Report

Reports support two formats. Choose based on your content:

### Option A: HTML-Bundle Report (Preferred)

Use this when your report was generated as a multi-page HTML bundle
(the standard `test-verification-report-*` pattern).

#### 1. Create the report directory

```
reports/<jira-key>/
```

#### 2. Copy the HTML bundle

Copy the generated bundle files into the directory:

```bash
cp -r /path/to/generated-report/* reports/<jira-key>/
```

The directory should contain:

- `index.html` — dashboard / entry-point
- `scenario-N.html` — per-scenario detail pages
- `appendices.html` — environment details, config evidence (optional)
- `automated-tests.html` — CI results (optional)
- `assets/` — screenshots, diagrams (optional)
- `scripts/` — helper scripts (optional)

#### 3. Add metadata

Create `reports/<jira-key>/metadata.yaml` using the schema in
[docs/format.md](docs/format.md#html-bundle-metadata). Set
`format: html-bundle`.

#### 4. Optionally derive a Markdown summary

If a Markdown version is needed, place it in `derived/report.md` and
set `has_derived_markdown: true` in `metadata.yaml`. The HTML bundle
remains the authoritative artifact — never delete HTML files after
generating a Markdown summary.

#### 5. Open a pull request

Use title format: `<JIRA-KEY>: Add verification report`.

### Option B: Markdown Report

Use this for lightweight, single-PR verification results.

#### 1. Create the report directory (if needed)

```
reports/<jira-key>/
```

#### 2. Write the report

Name the file by the PR number it verifies:

```
reports/<jira-key>/<pr-number>.md
```

Include:

- **Header** — PR link, plan reference, date, tester
- **Environment** — cluster type, OCP version, platform
- **Results** — pass/fail per test case from the plan
- **Evidence** — links to CI runs, logs, screenshots
- **Verdict** — overall pass/fail and any caveats

The overall verdict is required in YAML metadata; repeating it in a body
header or dedicated section is optional. If you include explicit pass/fail/skip
totals, keep them consistent with the test-case results; see the
[Markdown count-check contract](docs/format.md#explicit-markdown-result-counts).

#### 3. Open a pull request

Use title format: `<JIRA-KEY>: Add verification report for PR #<number>`.

## Backports and One-to-Many Relationships

A single test plan often applies to multiple Jira issues (e.g. a feature
issue plus its backport issues) and multiple PRs. The metadata block in
each plan supports this via the `jira_issues` and `pull_requests` lists.
See [docs/format.md](docs/format.md#one-to-many-relationships) for details.

Do **not** duplicate a plan file for each backport. Instead, add the
additional Jira issue keys and PR links to the existing plan's metadata.

## Content Rules

Do not include secrets, customer data, or private links. Sanitize all
examples by replacing real identifiers with placeholders. See the
[automation integration contract](docs/format.md#automation-integration-contract)
for the full list of content prohibitions.

**HTML-specific rules:** When committing HTML reports, also sanitize:

- Bearer tokens and authorization headers embedded in log output
- Azure subscription/tenant IDs in URLs or config dumps
- Real cluster names and account identifiers in dashboard data
- Customer names or personal information in report titles or headers

## Style Guidelines

- Use Markdown with standard GitHub-Flavored Markdown (GFM) extensions.
- Wrap lines at a reasonable length for readability in diffs (no strict limit).
- Use ATX-style headers (`#`, `##`, etc.).
- Use fenced code blocks with language identifiers.
- Prefer tables for structured data (acceptance criteria mappings, test
  matrices).

## Validation Before Submission

With Go 1.26 installed, run:

```sh
make install-tools
make test lint build
```

Tool installation is explicit; lint never downloads tool executables on its own.
Use `make lint-go` for Go code and `make lint-artifacts` for artifact validation
including the pinned secret scanner. A failed or conditional test verdict is
valid report content and does not itself fail lint.

See [docs/validation.md](docs/validation.md) for rule IDs, local-link checks,
legacy exceptions, CI enforcement, and security review that automation cannot perform.

## Questions

If anything is unclear, open an issue on this repository or ask in the
HyperShift team channel.

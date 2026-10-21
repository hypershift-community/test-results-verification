# Format Specification

This document defines the metadata model, naming conventions, file format, and
relationship model for test plans and verification reports in this repository.

## Naming Conventions

### Plans

| Situation | Pattern | Example |
|-----------|---------|---------|
| Linked to a Jira issue | `plans/<jira-key>.md` | `plans/ocpstrat-3298.md` |
| No Jira issue | `plans/<descriptive-slug>.md` | `plans/csi-snapshot-validation.md` |

Rules:

- Filenames are **lowercase**.
- Jira keys use the original project prefix and number (e.g. `ocpstrat-3298`,
  `cntrlplane-1234`, `ocpbugs-5678`).
- Slugs for plans without a Jira issue use lowercase words separated by
  hyphens. Keep them short and descriptive.
- Files prefixed with `_` (e.g. `_example.md`) are reserved for templates
  and reference examples. They are not production plans.
- One plan per file. Do not combine unrelated features.

### Reports

Reports support two formats. Choose based on the report content:

#### HTML-bundle reports (preferred)

```
reports/<jira-key>/
├── index.html              # Dashboard / entry-point
├── scenario-1.html         # Per-scenario detail pages
├── scenario-2.html
├── ...
├── appendices.html          # Environment details, config evidence
├── automated-tests.html     # CI / automated-test results
├── assets/                  # Screenshots, diagrams
│   └── img-scenario-1.png
├── scripts/                 # Helper scripts used in testing
│   └── setup-env.sh
└── derived/                 # Optional IEEE 829 Markdown summary
    └── report.md
```

Example: `reports/ocpbugs-100054/index.html` is the entry-point for the
OCPBUGS-100054 verification report.

HTML bundles are self-contained directories mirroring the existing
`test-verification-report-*` pattern from the source repository. Each
bundle typically includes:

| File | Purpose |
|------|---------|
| `index.html` | Dashboard with navigation, summary statistics, and links to scenario pages |
| `scenario-N.html` | Detailed steps, evidence, and pass/fail status for each test scenario |
| `appendices.html` | Environment details, configuration dumps, supplementary evidence |
| `automated-tests.html` | CI pipeline results, automated-test logs, coverage data |
| `assets/` | Screenshots, topology diagrams, and other images referenced by HTML pages |
| `scripts/` | Helper shell scripts, OIDC token scripts, setup utilities used during testing |
| `derived/report.md` | Optional IEEE 829 Markdown generated from the HTML (see [Derived Markdown](#derived-markdown-from-html-reports)) |

#### Markdown reports

```
reports/<jira-key>/<pr-number>.md
```

Example: `reports/ocpstrat-3298/8698.md` verifies PR #8698 against the
test plan for OCPSTRAT-3298.

Use Markdown reports for lightweight, single-PR verification results that
do not require the full HTML bundle structure.

## Metadata Block

Every plan file **must** begin with a YAML front-matter block. This block
enables automation to discover, index, and link plans.

Fields are divided into three tiers:

- **Required (discoverability core)** — must be present in every indexed plan.
- **Recommended** — include when applicable; omit rather than use placeholders.
- **Optional** — useful for discovery and tooling but not required.

> **Legacy/incomplete artifacts:** Migrated plans that lack certain metadata
> are preserved as-is. Document gaps with a note (e.g. "Missing: Jira issue —
> pre-dates Jira tracking") rather than fabricating facts.

### Required Fields (Discoverability Core)

Every new or materially updated plan must include these four fields:

```yaml
---
id: TP-OCPSTRAT-3298-001        # Unique plan identifier
date: 2026-09-07                 # Last-updated date (ISO 8601)
title: "Predictable NodePool Rollout Control"
status: draft                    # "draft", "active", "superseded", or "archived"
ieee_829: true                    # Required policy declaration for new plans
---
```

The discoverability core remains `id`, `title`, `date`, and `status`.
In addition, new and materially rewritten plans require the boolean
`ieee_829: true`. Core text fields must be nonempty strings; dates are real
calendar dates in `YYYY-MM-DD` format (quoted or unquoted). Quoted booleans,
null required values, duplicate YAML keys, aliases, anchors, merge keys, and
custom YAML tags are rejected. See [reviewed exceptions](validation.md#legacy-and-adaptation-exceptions)
for unavailable historical metadata.

### Recommended Fields

Include these when the information is available. Omit the field entirely
rather than using empty lists or placeholders:

```yaml
---
version: "1.0"                   # Plan version (semver-style)
jira_issues:                     # Primary + backport Jira issues
  - key: OCPSTRAT-3298
    role: primary                # "primary" or "backport"
    url: https://issues.redhat.com/browse/OCPSTRAT-3298
pull_requests:                   # Associated PRs
  - repo: openshift/hypershift
    number: 8698
    url: https://github.com/openshift/hypershift/pull/8698
    role: implementation         # "implementation", "backport", or "test"
---
```

### Optional Fields

```yaml
---
superseded_by: ocpstrat-3298-v2  # Filename (without .md) of the replacement plan
tags:                            # Freeform tags for discovery
  - nodepool
  - rollout
  - machine-config
author: ""                       # Plan author (name or GitHub handle)
---
```

### Field Reference

| Field | Type | Tier | Description |
|-------|------|------|-------------|
| `id` | string | **required** | Unique identifier. Convention: `TP-<JIRA-KEY>-<seq>` or `TP-<SLUG>-<seq>`. |
| `date` | date | **required** | Last-updated date in ISO 8601 format. |
| `title` | string | **required** | Human-readable plan title. |
| `status` | string | **required** | Plan lifecycle status (see below). |
| `version` | string | recommended | Plan revision. Increment on substantive changes. |
| `jira_issues` | list | recommended | List of associated Jira issues. Include when the plan tracks Jira work. |
| `jira_issues[].key` | string | (child) | Jira issue key (e.g. `OCPSTRAT-3298`). |
| `jira_issues[].role` | string | (child) | `primary` or `backport`. Exactly one issue should be `primary`. |
| `jira_issues[].url` | string | (child) | Full URL to the Jira issue. |
| `pull_requests` | list | recommended | List of associated PRs. Include when PRs exist. |
| `pull_requests[].repo` | string | (child) | GitHub repository in `org/repo` format. |
| `pull_requests[].number` | integer | (child) | PR number. |
| `pull_requests[].url` | string | (child) | Full URL to the PR. |
| `pull_requests[].role` | string | (child) | `implementation`, `backport`, or `test`. |
| `superseded_by` | string | optional | Filename stem of the replacement plan. |
| `tags` | list | optional | Freeform tags for search and filtering. |
| `ieee_829` | boolean | **required for new plans** | Must be `true`; legacy gaps require reviewed exceptions. |
| `author` | string | optional | Plan author identifier. |

### Status Lifecycle

> **Note:** The `status` field and its lifecycle values are **repository
> metadata conventions** used for workflow and discoverability — they are
> _not_ part of the IEEE 829-2008 standard. Everything in the
> [Metadata Block](#metadata-block) (the YAML front-matter) is repository
> housekeeping; the IEEE 829 content begins in the
> [Plan Body Structure](#plan-body-structure) section below.

```
draft → active → superseded
                → archived
```

- **draft** — plan is under review or incomplete.
- **active** — plan is approved and in use for verification.
- **superseded** — replaced by a newer plan (set `superseded_by`).
- **archived** — no longer relevant (feature removed, etc.).

## One-to-Many Relationships

### One Plan, Many Jira Issues (Backports)

> **Why this matters:** In practice, a feature lands on the main branch and
> is then cherry-picked to one or more release branches. Each backport
> carries its own Jira issue and PR, yet the verification logic is
> identical. Maintaining a single authoritative test plan — instead of
> copying it per-backport — prevents duplicated plans from drifting out of
> sync and gives reviewers one place to check. The metadata lists below let
> automation and reviewers trace every related Jira issue and PR back to
> that single plan.

A feature implemented in a main-branch PR often gets backported to one or
more release branches. Each backport has its own Jira issue and PR, but the
test plan is the same. Rather than duplicating the plan file, list all
related Jira issues and PRs in the metadata:

```yaml
jira_issues:
  - key: OCPSTRAT-3298
    role: primary
    url: https://issues.redhat.com/browse/OCPSTRAT-3298
  - key: OCPBUGS-45678
    role: backport
    url: https://issues.redhat.com/browse/OCPBUGS-45678
  - key: OCPBUGS-45679
    role: backport
    url: https://issues.redhat.com/browse/OCPBUGS-45679

pull_requests:
  - repo: openshift/hypershift
    number: 8698
    url: https://github.com/openshift/hypershift/pull/8698
    role: implementation
  - repo: openshift/hypershift
    number: 8750
    url: https://github.com/openshift/hypershift/pull/8750
    role: backport
```

The plan file is named after the **primary** Jira issue key.

### One Plan, Many PRs (Same Feature)

Some features span multiple PRs (e.g. API change + controller + tests).
List all PRs in the `pull_requests` field.

### Plans Without a Jira Issue

If there is no Jira issue, omit the `jira_issues` field (or leave it as an
empty list for backward compatibility) and name the file with a descriptive
slug:

```yaml
pull_requests:
  - repo: openshift/hypershift
    number: 9100
    url: https://github.com/openshift/hypershift/pull/9100
    role: implementation
```

## Plan Body Structure

New and materially rewritten plans must use the IEEE 829 profile. The
lightweight profile is retained only for reviewed legacy artifacts.

### IEEE 829 Profile (`ieee_829: true`)

Declare `ieee_829: true` and cover these seven content areas, based on the
repository's IEEE 829-2008-style template:

1. **Test Plan Identifier** — ID, version, date, IEEE 829 reference
2. **Introduction and Objectives** — purpose, objectives, acceptance criteria
   mapping, automation-first principle
3. **Test Items and References** — implementation PRs, code paths, API
   changes, related documentation
4. **Test Environment** — cluster types, platforms, prerequisites
5. **Test Cases** — numbered cases with preconditions, steps, expected results,
   and automation references
6. **Risks and Mitigations** — known risks and contingency plans
7. **Approvals** — sign-off section

Each area needs a heading and content, but exact numbering and heading text
are not required. Equivalent headings include **Purpose and Objectives**,
**References**, **Prerequisites**, **Test Approach and Design**, **Risks and
Contingencies**, and **Approval and Exit Criteria**. Combined headings may
cover multiple areas. Code-fenced headings do not satisfy a content area.
Explain an inapplicable area rather than silently omitting it; substantial
adaptations can use an explicitly reviewed `STRUCTURE` exception.

These are machine-checkable **repository requirements**, not a claim that
lint certifies IEEE compliance. Reviewers assess meaningful steps, expected
results, acceptance coverage, and adequate evidence.

<a id="lightweight-profile-default"></a>

### Lightweight Profile (legacy only)

An explicitly registered legacy plan may retain absent/false `ieee_829`
metadata and a free-form Markdown body. Preserve available coverage of:

- **Scope** — what feature or behavior is being tested and why.
- **Test cases** — what will be verified, with steps or references.
- **Acceptance criteria** — what constitutes a pass.

Record known gaps and the original source in the migration inventory and
[exception configuration](validation.md#legacy-and-adaptation-exceptions).
Absence of `ieee_829` is not an automatic opt-out for new plans.

## Plan Template

Use the IEEE 829 template for new plans. The lightweight template is retained
as a reference for preserving historical artifacts, not for new submissions.

### IEEE 829 Template (`ieee_829: true`)

Use this template for plans that follow the IEEE 829-2008 standard.
See also [`plans/_example.md`](../plans/_example.md) for a complete example.

````markdown
---
id: TP-<JIRA-KEY>-001
version: "1.0"
date: YYYY-MM-DD
title: "<Feature Name>"
jira_issues:
  - key: <JIRA-KEY>
    role: primary
    url: https://issues.redhat.com/browse/<JIRA-KEY>
pull_requests:
  - repo: openshift/hypershift
    number: <PR-NUMBER>
    url: https://github.com/openshift/hypershift/pull/<PR-NUMBER>
    role: implementation
status: draft
tags: []
ieee_829: true
---

# Test Plan: <Feature Name>

## 1. Test Plan Identifier

**ID:** TP-<JIRA-KEY>-001
**Version:** 1.0
**Date:** YYYY-MM-DD
**IEEE 829 Compliance:** This document follows the IEEE 829-2008 Standard
for Software and System Test Documentation.

---

## 2. Introduction and Objectives

### 2.1 Purpose

Describe the feature under test and the purpose of this plan.

### 2.2 Objectives

1. Objective 1
2. Objective 2

### 2.3 Acceptance Criteria Mapping

| Acceptance Criterion | Test Case |
|----------------------|-----------|
| AC #1 — description | TC-001 (Section 5.1) |

---

## 3. Test Items and References

| Item | Reference |
|------|-----------|
| Implementation PR | [openshift/hypershift#NNNN](https://github.com/openshift/hypershift/pull/NNNN) |
| Feature Jira | [JIRA-KEY](https://issues.redhat.com/browse/JIRA-KEY) |

---

## 4. Test Environment

| Property | Value |
|----------|-------|
| Cluster type | HostedCluster on AWS |
| OCP version | 4.x |
| Management cluster | ... |

---

## 5. Test Cases

### 5.1 TC-001: <Test Case Title>

**Objective:** What this test verifies.

**Preconditions:**
- Precondition 1

**Primary method (automated):**
- Test file: `test/e2e/...`
- Run with: `make e2e TEST_NAME=...`

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | ... | ... |

---

## 6. Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| ... | ... |

---

## 7. Approvals

| Role | Name | Date |
|------|------|------|
| Author | | |
| Reviewer | | |
````

<a id="lightweight-template-default"></a>

### Lightweight Template (legacy only)

Historical reference only; preservation requires a reviewed legacy exception:

````markdown
---
id: TP-<SLUG>-001
date: YYYY-MM-DD
title: "<Feature Name>"
status: draft
---

# Test Plan: <Feature Name>

## Scope

Describe the feature under test, why it needs verification, and any
relevant context.

## Test Cases

### TC-001: <Test Case Title>

**Steps:**
1. Step 1
2. Step 2

**Expected result:** Describe the expected outcome.

### TC-002: <Test Case Title>

...

## Acceptance Criteria

| Criterion | Verified by |
|-----------|-------------|
| AC #1 — description | TC-001 |
````

## Report Formats

Verification reports support two formats depending on the complexity and
origin of the report content.

### HTML-Bundle Reports (Preferred)

HTML bundles are the **default and preferred** format for verification
reports. They preserve the rich, navigable structure of generated test
reports — including dashboards, per-scenario evidence pages, embedded
screenshots, and CI result summaries.

#### HTML-bundle metadata

HTML-bundle reports use a `metadata.yaml` file (not YAML front-matter)
placed at the root of the report directory:

Required fields are `jira_key`, `format`, `date`, `verdict`, `scenario_count`,
`pass_count`, `ci_verified`, and `has_derived_markdown`. `plan` is optional
(omit or use `""` when no plan exists). `tags`, `pr`, and `tester` are optional;
when supplied, `pr` follows the Markdown-report PR mapping below.

- `jira_key` must match the lowercase directory's Jira key.
- `format` is `html-bundle`; `verdict` is `pass`, `fail`, or `conditional`.
- Counts are nonnegative decimal integers, not booleans or quoted numbers.
  `scenario_count` equals the number of root-level `scenario-N.html` pages
  (positive decimal numbers without leading zeroes); it is not a count of
  test cases. `pass_count` cannot exceed `scenario_count`.
- The two flags are YAML booleans. `ci_verified: true` requires
  `automated-tests.html`; file presence alone does not prove CI passed.
  `has_derived_markdown` must exactly match `derived/report.md` presence.
- A supplied nonempty `plan` references an existing production plan filename
  stem. If that plan lists Jira issues, it must include this report's Jira key,
  whether primary or backport. Reports without an available plan are valid.

```yaml
# reports/ocpbugs-100054/metadata.yaml
plan: ""                             # Filename stem of the test plan (if any)
jira_key: OCPBUGS-100054
format: html-bundle                  # "html-bundle" or "markdown"
date: 2026-08-05
verdict: pass                        # "pass", "fail", or "conditional"
scenario_count: 8                    # Total test scenarios
pass_count: 8                        # Scenarios that passed
ci_verified: true                    # automated-tests.html present?
has_derived_markdown: false          # derived/report.md present?
tags:
  - authentication
  - hypershift
```

#### Sanitized HTML-bundle layout example

Below is a representative directory layout for an HTML-bundle report.
All names, data, and identifiers are fictional.

```
reports/ocpbugs-99999/
├── metadata.yaml             # Required report metadata
├── index.html                # Dashboard: 6 scenarios, 6/6 pass
├── scenario-1.html           # Cluster provisioning validation
├── scenario-2.html           # Network-policy enforcement
├── scenario-3.html           # Ingress-controller health
├── scenario-4.html           # Node scaling operations
├── scenario-5.html           # Upgrade rollout verification
├── scenario-6.html           # Teardown and cleanup
├── appendices.html           # Environment config, cluster version
├── automated-tests.html      # CI job results, e2e pass rates
├── assets/
│   ├── img-s1-cluster.png    # Screenshot: cluster overview
│   └── img-s3-ingress.png    # Screenshot: ingress status
└── scripts/
    └── setup-env.sh           # Cluster environment bootstrap
```

#### `index.html` conventions

The index page serves as the report dashboard. It typically includes:

- **Navigation bar** linking to all scenario pages, appendices, and
  automated-test results.
- **Summary statistics** (total scenarios, pass/fail counts, coverage).
- **Test-environment overview** (cluster version, platform, topology).
- **Jira-key reference** in the page title or header.

HTML reports may reference external CDN resources (e.g. Bootstrap CSS/JS)
for styling but must not depend on resources outside the bundle for
_content_ (evidence, logs, screenshots).

#### Scenario pages

Each `scenario-N.html` page documents a single test scenario:

- **Objective** — what is being verified.
- **Pre-conditions** — cluster state, configuration, prerequisites.
- **Steps** — numbered test steps with expected vs. actual results.
- **Evidence** — embedded or linked screenshots, log snippets.
- **Verdict** — PASS / FAIL / SKIP with notes.

#### Assets and scripts

- Store images in `assets/` and reference them with relative paths.
- Store helper scripts in `scripts/`. Scripts must be sanitized
  (no embedded credentials, tokens, or customer identifiers).
- Large binary assets (> 5 MB per file) should be avoided; link to
  external storage if necessary.

### Derived Markdown from HTML Reports

When an IEEE 829 Markdown version of an HTML report is needed (e.g. for
downstream tooling or cross-referencing with plans), place it in
`derived/report.md` inside the report directory.

Rules:

1. The HTML bundle remains the **authoritative** artifact.
2. `derived/report.md` is a convenience copy — it may be AI-generated
   or hand-written.
3. Set `has_derived_markdown: true` in `metadata.yaml` when present.
4. Derivation **must not** replace or remove the original HTML files.

### Markdown Report Template

Markdown reports are lightweight, single-file reports for simpler
verification results. Use this format when the report does not require
a full HTML bundle.

Required front-matter fields are `jira_key`, `format: markdown`, `pr`, `date`,
and `verdict`. The `pr` mapping requires `repo`, a positive integer `number`,
and a matching HTTPS GitHub PR `url`; the filename is `<number>.md`.
`plan` is optional as above, and `tester` is recommended when known (a string,
possibly empty for compatibility). Include headings for environment, results,
and evidence; additional text may appear in the headings. The required
`verdict` metadata supplies the overall outcome. A body verdict heading or
header such as `**Verdict:** **PASS**` is optional, not a second requirement.

Both report formats accept well-documented `fail` and `conditional` verdicts.
Lint checks structure and consistency, not the success of the tested change.
Markdown reports may keep local screenshots/logs and other evidence in the
same Jira directory without becoming HTML bundles. Root-level HTML pages or
`metadata.yaml` or `derived/report.md` indicate an HTML bundle; otherwise a
directory with only supporting files and no Markdown report is an incomplete
bundle.

#### Explicit Markdown result counts

Optional report-wide summaries may state counts, for example:

```markdown
**Verdict:** **CONDITIONAL** (2 pass, 1 fail, 1 skip [environment])
```

When there is exactly one top-level test-case results table, lint compares
each explicit `N pass`, `N fail`, or `N skip` count in a top-level `Verdict:`
or `Summary:` paragraph line against that table's rows. The label can follow
other header fields in the same paragraph. The table needs a `Test Case`
column and one `Result` or `Status` column whose cells are `PASS`, `FAIL`, or
`SKIP`. Labels/statuses are case-insensitive and may use inline formatting.
Omitted summary counts are not assumed to be zero. A mismatch is a `COUNTS`
error at the summary line; consistent failed/skipped results remain valid.

This is a deliberately bounded consistency check, not a natural-language
audit. It does not infer totals from prose, inspect fenced/quoted examples or
inline-code summary examples, or choose between multiple results tables.
Empty tables, ambiguous columns, other status vocabularies, HTML dashboards,
and differently scoped summaries still need human review.

````markdown
---
plan: ocpstrat-3298              # Filename stem of the test plan
jira_key: OCPSTRAT-3298
format: markdown                 # "html-bundle" or "markdown"
pr:
  repo: openshift/hypershift
  number: 8698
  url: https://github.com/openshift/hypershift/pull/8698
date: YYYY-MM-DD
tester: ""
verdict: pass                    # "pass", "fail", or "conditional"
---

# Verification Report: PR #8698

## Environment

| Property | Value |
|----------|-------|
| Cluster type | HostedCluster on AWS |
| OCP version | 4.18 |
| Platform | AWS us-east-1 |

## Results

| Test Case | Result | Notes |
|-----------|--------|-------|
| TC-001 | Pass | Ran via CI: [link] |
| TC-002 | Pass | |

## Evidence

- CI job: [link to Prow job]
- Logs: [link or summary]

## Verdict

**Pass** — all test cases passed.
````

## Automation Integration Contract

This section defines the contract that automation tools (e.g. Chai Bot,
ai-helpers skills) must follow when creating or updating plans and reports
in this repository.

### Creating a Plan

Automation **must**:

1. Generate a valid Markdown file with the required YAML front-matter
   metadata block (at minimum the discoverability core: `id`, `title`,
   `date`, `status`). Include `version`, `jira_issues`, and
   `pull_requests` when the information is available.
2. Use the correct filename convention (`plans/<jira-key>.md` or
   `plans/<slug>.md`).
3. Set `ieee_829: true` for new and materially rewritten plans and cover the
   content areas in [Plan Body Structure](#plan-body-structure). Preserve
   historical exceptions explicitly; do not generate new lightweight plans.
4. Set `status: draft` for newly generated plans.
5. Include all known Jira issues and PRs in the metadata when available.
6. Open a PR against `main` with title format
   `<JIRA-KEY>: Add test plan for <feature>`.

Automation **must not**:

- Commit directly to `main` — always use a PR.
- Include secrets, credentials, customer data, or private links.
- Overwrite an existing plan without incrementing the `version` field (if
  present) and updating the `date`.
- Create duplicate plan files for backport Jira issues — instead, update
  the existing plan's `jira_issues` list.
- Fabricate metadata (Jira keys, PR numbers) that does not exist.

### Updating a Plan

When adding a backport Jira issue or PR to an existing plan, automation
should:

1. Read the existing plan file.
2. Append the new Jira issue or PR to the appropriate list.
3. Increment the `version` field.
4. Update the `date` field.
5. Open a PR with the changes.

### Creating a Report

For **HTML-bundle reports**, automation should:

1. Create the directory `reports/<jira-key>/`.
2. Copy the HTML bundle files (`index.html`, `scenario-*.html`,
   `appendices.html`, `automated-tests.html`, assets, scripts) into
   the directory.
3. Generate a `metadata.yaml` file with required fields (see
   [HTML-bundle metadata](#html-bundle-metadata)).
4. Set `format: html-bundle` in the metadata.

For **Markdown reports**, automation should follow the Markdown report
template defined above and place the file at
`reports/<jira-key>/<pr-number>.md`.

### File Validation

Automation should validate before committing:

- YAML front-matter is parseable.
- Required core metadata fields (`id`, `title`, `date`, `status`) are present.
- All URLs in metadata are well-formed.
- New plans declare `ieee_829: true` and cover the required content areas.
- Filename matches the primary Jira key or slug.
- No secrets or private content patterns detected.

Run `make lint-artifacts` to perform these checks plus report, relationship,
local-link, and redacted secret scanning. See [validation](validation.md) for
rule IDs, operational limits, and requirements that need human review.

> **Note:** Implementation of these automation capabilities in the
> `ai-helpers` skill library is tracked as a follow-up to
> [CNTRLPLANE-4323](https://issues.redhat.com/browse/CNTRLPLANE-4323).
> The contract above is stable and ready for implementation.

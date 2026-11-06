# Migration Guide

This document provides guidance for migrating existing test plans from
personal repositories to this centralized repository.

## Overview

HyperShift team members have been self-hosting test plans and verification
reports in personal GitHub repositories. This centralized repository replaces
that pattern. All existing plans should be migrated here following the
conventions in [format.md](format.md) and [CONTRIBUTING.md](../CONTRIBUTING.md).

### Purpose and Longevity

This guide — and the [Migration Inventory](#migration-inventory) table below
— is a **durable, incrementally maintained record**, not a one-time
throwaway. It serves as the onboarding reference for anyone moving artifacts
into this repository, whether manually or with LLM-assisted tooling.

**Handling incomplete legacy artifacts:**

- **Preserve source content.** Migrate what exists without inventing
  missing facts. If the original plan lacks sections required by the
  current format, do _not_ fabricate content to fill them.
- **Set `status: draft` and document gaps.** Mark incomplete plans as
  `draft` in their front-matter and add a brief note (e.g.
  "Missing: test-environment details — to be supplied by author") so
  follow-up work is visible.
- **New and materially rewritten plans require IEEE 829.**
  Any plan written from scratch or substantially rewritten must include
  the required core metadata (`id`, `title`, `date`, `status`) and select
  `ieee_829: true`, covering the content areas in
  [format.md](format.md#plan-body-structure).
  Minor metadata-only updates to a migrated plan do not trigger a full
  rewrite.
- **Register preserved gaps explicitly.** Add a reviewed path/rule-specific
  exception with the original source, reason, remaining gaps, and a hash of
  the preserved body. Migrated HTML bundles whose `metadata.yaml` lacks
  unrecorded fields, or that have no metadata at all, use the same process
  instead of inventing counts or verdicts. See
  [validation.md](validation.md#legacy-and-adaptation-exceptions).
  A new file can be migrated historical content, but `draft` or a new filename
  alone does not establish that history. Body changes invalidate the hash;
  metadata-only edits do not. Security checks always apply.
- **HTML bundles are preserved as-is.** Do not convert HTML report bundles
  to Markdown during migration (see [What NOT to Do](#what-not-to-do)).
  They are relocated intact and given a `metadata.yaml` sidecar.

## Migration Steps

### 1. Inventory Your Plans

List all test plans and verification reports in your personal repository.
For each artifact, note:

- The Jira issue key (if any)
- The associated PRs
- Whether it is a plan, report, or both
- The current format (Markdown, HTML, etc.)

### 2. Convert to the Standard Format

**For plans (Markdown):**

1. **Add YAML front-matter** — include the required core fields (`id`,
   `title`, `date`, `status`). Add `version`, `jira_issues`, and
   `pull_requests` when the information is available — see
   [format.md](format.md#metadata-block).
2. **Rename the file** — use the naming convention
   (`<jira-key>.md` or `<slug>.md`).
3. **Conform or preserve explicitly:** use `ieee_829: true` and the current
   content areas for new or materially rewritten plans. When relocating
   incomplete historical content, preserve its body and record reviewed
   exceptions for specific unavailable metadata or structure. Do not invent
   sections or facts to make lint pass.
4. **Sanitize content** — remove any secrets, customer data, private links,
   or real cluster identifiers. Replace with placeholders.

**For HTML verification-report bundles:**

HTML reports (e.g. the `test-verification-report-*` directories) are migrated
**as-is** — do **not** convert them to Markdown.

1. **Create the target directory** — `reports/<jira-key>/`.
2. **Move the HTML bundle** — copy all HTML files (`index.html`,
   `scenario-*.html`, `appendices.html`, `automated-tests.html`),
   images, and scripts into the target directory.
3. **Add `metadata.yaml`** — see [format.md](format.md#html-bundle-metadata)
   for the schema. Set `format: html-bundle`.
4. **Organize assets** — move images to `assets/` and scripts to `scripts/`
   within the report directory. If HTML pages reference images with flat
   relative paths (e.g. `src="img-foo.png"`), either update the paths to
   `assets/img-foo.png` (preferred) or keep images alongside the HTML files
   for backward compatibility.
5. **Sanitize content** — remove any secrets, customer data, private links,
   or real identifiers.

> **Optional:** If downstream tooling requires an IEEE 829 Markdown artifact,
> you may generate one in `derived/report.md` within the report directory.
> Set `has_derived_markdown: true` in `metadata.yaml`. The HTML bundle
> remains the authoritative artifact — never delete HTML files after
> generating a Markdown summary.

### 3. Open a Pull Request

- Branch from `main`.
- Add your converted files under `plans/` and/or `reports/`.
- Title: `Migrate test plan(s) from <source>`.
- In the PR description, note the source repository and any changes made
  during conversion.

### 4. Archive or Remove the Original

Once the PR is merged, archive or remove the plan from your personal
repository to avoid confusion. Consider adding a note or redirect pointing
to this repository.

## Migration Inventory

The table below tracks known existing test plans and their migration status.
Add entries as you discover plans in personal repos or other locations.

| Source | Jira Key | Description | Format | Target Path | Status |
|--------|----------|-------------|--------|-------------|--------|
| [bryan-cox.github.io/architectural-artifact-sharing](https://bryan-cox.github.io/architectural-artifact-sharing/) | Various | Hosted verification reports (HTML bundles) | html-bundle | `reports/<jira-key>/` | Not started |
| PR #1 in this repo | OCPSTRAT-3298 | NodePool rollout control test plan | markdown | `plans/ocpstrat-3298.md` | In progress (PR open) |
| PR #2 in this repo | OCPSTRAT-3150 | Etcd sharding test plan | markdown | `plans/ocpstrat-3150.md` | In progress (PR open) |

### Adding to the Inventory

When you discover existing test plans that should be migrated, add a row to
the table above via PR. Include:

- **Source** — link to the current location
- **Jira Key** — the associated Jira issue, if any
- **Description** — brief description of what the plan covers
- **Target Path** — the expected path in this repo
- **Status** — one of: `Not started`, `In progress`, `Migrated`, `Skipped`

## What NOT to Do

- **Do not convert HTML reports to Markdown as a migration step.**
  HTML bundles contain structured navigation, styling, embedded evidence,
  and interactive elements that Markdown cannot represent faithfully.
  Migration means _relocating_ the HTML bundle, not _replacing_ it.

- **Do not discard assets or scripts.** Images, shell scripts, and other
  supporting files are part of the report evidence and must be preserved.

- **Do not flatten the bundle.** Keep the multi-file structure
  (`index.html` + `scenario-N.html` + appendices) intact.

## Validation Checklist

After migrating an artifact, verify:

- [ ] Metadata (`metadata.yaml` or YAML front-matter) is present and valid
- [ ] `format` field matches actual content (`html-bundle` vs `markdown`)
- [ ] All internal links resolve (scenario pages, images, scripts)
- [ ] No secrets, customer data, or personal information in any file
- [ ] Git history preserves authorship (`git mv` where possible)

## Tips

- **Don't migrate everything at once.** Start with active plans that are
  referenced by in-flight PRs.
- **Preserve authorship.** Use `git commit --author` if you are migrating
  someone else's plan and want to preserve their attribution.
- **Link back.** After migration, update any Jira issues that reference the
  old location to point to the new file in this repository.
- **Ask for help.** If a plan is in a format you are unsure how to convert,
  open an issue and the team can assist — or use Chai Bot's test plan
  generation skill to create a fresh plan from the Jira issue.

# Validation

The repository has two complementary linters:

- **golangci-lint** checks the Go implementation.
- **verify-artifacts** checks plans, reports, relationships, navigation, and
  sanitization. It reads files as data and never executes report scripts,
  embedded JavaScript, or test scenarios.

The format contract is [format.md](format.md). A failing or conditional test
verdict is valid report data; lint does not decide whether a feature passed.

## Setup and Commands

Install Go 1.26, then explicitly bootstrap the pinned tools:

```sh
make install-tools
make test lint build
```

The bootstrap installs golangci-lint v2.7.0 and Gitleaks v8.30.1 under the
gitignored `bin/` directory. Go modules are pinned in `go.mod`/`go.sum`.
Installation needs registry access; validation and unit tests do not fetch
evidence or check remote URL availability. Download modules/tools before
running in an offline environment. Lint never installs tools automatically.

- `make test`: offline behavior tests with the Go race detector.
- `make lint-go`: golangci-lint and formatting checks.
- `make lint-artifacts`: artifact checks **and** the pinned Gitleaks scanner.
- `make lint`: both linters.
- `make build`: compile `bin/verify-artifacts`.

Go tests, formatting, and golangci-lint are scoped to `cmd/` and `internal/`.
Go reproduction kits stored under `reports/` are evidence, not packages to
compile or execute as part of this repository's checks.
When the pinned scanner is installed, the suite also runs offline regressions
against its real executable for commonly exempted evidence filenames. Those
tests explicitly skip when the pinned executable is unavailable; CI installs
it before testing, so they run there.

For faster structural checks or machine-readable output:

```sh
go run ./cmd/verify-artifacts --root .
bin/verify-artifacts --root . --format json
PATH="$PWD/bin:$PATH" bin/verify-artifacts --root . --secrets --format github
```

Without `--secrets`, the CLI still applies targeted sanitization rules, but
does **not** run the maintained secret scanner. Use `make lint-artifacts` for
the complete security check. Exit codes are **0** (valid), **1** (artifact
violations), and **2** (usage, I/O, scanner version/failure, or other tool error).
With `go run`, Go itself reports a failed subprocess as a nonzero status;
invoke the built binary when consuming the exact exit code.

## Diagnostics and Rules

Diagnostics include relative file, line, severity, stable rule ID, and a
suggested action. YAML parse failures intentionally omit raw parser messages,
which can contain source values. Secret findings omit the match and value.
GitHub annotations escape control characters in paths and messages.

- `FRONTMATTER`, `YAML`: missing/unterminated front matter, invalid YAML,
  duplicate keys, aliases/anchors/merges/custom tags, or multiple documents.
- `MISSING_<FIELD>`: an absent required field, for example `MISSING_ID`,
  `MISSING_TITLE`, `MISSING_DATE`, and `MISSING_STATUS` for plans;
  `MISSING_JIRA_KEY`, `MISSING_FORMAT`, `MISSING_PR`, and `MISSING_VERDICT` for
  Markdown reports; and `MISSING_SCENARIO_COUNT`, `MISSING_PASS_COUNT`,
  `MISSING_CI_VERIFIED`, and `MISSING_HAS_DERIVED_MARKDOWN` for bundle
  metadata. Malformed supplied values are instead `META` errors.
- `META`: invalid scalar/container types, dates, lifecycle/verdict values,
  and relationship entry shapes.
- `PROFILE`, `STRUCTURE`: new-plan IEEE declaration and the seven content
  areas defined in [format.md](format.md#plan-body-structure).
- `NAME`, `IDENTITY`, `RELATIONSHIP`: lowercase artifact paths, unique
  production plan IDs, primary/backport traceability, matching PR
  URLs/numbers, and valid noncyclic replacement-plan references.
- `BUNDLE`, `REPORT`, `REPORT_BODY`, `COUNTS`: missing bundle entry points or
  metadata, Markdown report body/metadata, scenario counts, explicit Markdown
  summary/result-table counts, and file/flag consistency. Markdown reports
  require verdict metadata, not a redundant body verdict heading. See the
  [bounded count-check contract](format.md#explicit-markdown-result-counts)
  for recognized summary/table forms and cases that require human review.
  Evidence Markdown and script runbooks are not standalone reports;
  `derived/report.md` is not a plan.
- `LINK`, `FRAGMENT`, `PATH`: broken local destinations/anchors, unsupported
  schemes, unsafe paths, symlinks, and out-of-bundle evidence dependencies.
- `SECURITY`: likely bearer credentials, credential-bearing URLs, private
  addresses/domains, or cloud-account/subscription/tenant identifiers.
  Literal loopback endpoints and the AWS documentation/dummy accounts
  `000000000000`, `111111111111`, and `123456789012` are recognized placeholders;
  credentials in their URLs are still rejected.
- `SECRET`: maintained Gitleaks detection; remove the value and rotate any
  real credential. Scanner failures are operational errors, not a clean scan.
- `SIZE`: assets over 5 MiB produce a warning. Files over 32 MiB block
  validation rather than silently bypassing inspection; split or relocate them.
- `ENCODING`: text evidence with NUL bytes or malformed UTF-8 is rejected,
  rather than silently treated as binary and exempted from sanitization.
- `EXCEPTION`, `EXCEPTION_APPLIED`: invalid/stale exception configuration or a
  warning identifying an applied reviewed exception.

Optional extensions to metadata are permitted. Recommended version/Jira/PR
fields are not universally required. Templates prefixed with `_` still receive
format/security checks, but fictional identifiers do not enter the production
identity index.

## Local Links and Resources

Markdown links, reference-style links, images, HTML links/resources/anchors,
CSS `url()`/imports, and HTML `srcset` candidates are checked. Markdown
autolinks use the same URL-scheme rules as explicit links. CSS tokenization
supports quoted paths with spaces and escaped URL characters; escaped function
names must be rewritten using their plain spelling rather than silently skipped.
Markdown fragments use GitHub-style heading slugs and duplicate suffixes. Fenced code
examples are not navigation. Public citations are checked syntactically,
without contacting the target. Absolute filesystem paths, traversal outside
the repository, symlinks, and HTML `base` elements are rejected.

Report-owned images, evidence files of any type, scripts, and styles must
remain inside their report directory. This applies to Markdown reports with
local assets as well as HTML bundles. Outside that directory, local citations
are limited to Markdown under `plans/`, `docs/`, or the repository root;
other evidence dependencies must be copied into the report. External embedded
evidence is rejected. HTTPS presentation resources
may use `cdn.jsdelivr.net`, `cdnjs.cloudflare.com`, `unpkg.com`,
`maxcdn.bootstrapcdn.com`, or `stackpath.bootstrapcdn.com`; local styling is
preferred. Inline PNG/JPEG data images are permitted. Relative CSS fragment
references are left to browser/human review.

Only root `.git/`, `.work/`, `bin/`, and `vendor/` directories are omitted
from artifact traversal. Nested evidence directories with these names are
still inspected. Binary image/document contents are not text-parsed; review
them for sensitive information before submission.

## Legacy and Adaptation Exceptions

New files are not automatically new authorship: a migration can preserve an
older lightweight or incomplete plan. Conversely, `status: draft`, old dates,
or missing metadata do not automatically grandfather a file.

For preserved historical content:

1. Add the source, destination, status, and known gaps to the
   [migration inventory](migration.md#migration-inventory).
2. Preserve available facts and document missing information. Set `draft`
   when possible; do not fabricate identifiers, dates, results, or sections.
3. Compute the body hash:

   ```sh
   go run ./cmd/verify-artifacts --body-hash plans/legacy.md
   ```

4. Add an exact-path exception to root `.artifactlint.yaml` and obtain review:

   ```yaml
   version: 1
   exceptions:
     - path: plans/legacy.md
       kind: legacy
       source: https://github.com/example/source/blob/main/plan.md
       reason: Preserved historical plan; IEEE declaration and sections unavailable
       body_sha256: "<hash printed by the command>"
       gaps:
         - No IEEE 829 declaration in the original
         - Environment and approvals sections were never written
       rules: [PROFILE, STRUCTURE]
   ```

Permitted rules depend on the pinned artifact:

| Exception `path` | Permitted rules |
|------------------|-----------------|
| Markdown plan or report | `FRONTMATTER`, plan/report `MISSING_*` core-field rules, `PROFILE`, `STRUCTURE`, `REPORT_BODY` |
| `reports/<key>/metadata.yaml` | Bundle-metadata `MISSING_*` rules, such as `MISSING_SCENARIO_COUNT` |
| `reports/<key>/index.html` | `BUNDLE`, for a migrated bundle with no `metadata.yaml`; the entry point is pinned because the absent file cannot be hashed |

Name every actual rule explicitly. For example, a plan without front matter
also needs its missing-core and profile/body rules listed. `META`, `YAML`,
security, naming, relationships, paths, links, and report-count/file-consistency
rules cannot be disabled, and a missing `index.html` cannot be excepted.

Use `kind: adaptation` only for reviewed body-structure adaptations, with
`STRUCTURE` or `REPORT_BODY`. Exceptions have no globs and require an existing
artifact, a nonempty reason, a public HTTPS source, a body hash, and a
nonempty `gaps` list recording what remains missing. Removing or renaming a
file requires updating its exception. Adding `metadata.yaml` to a bundle makes
its `BUNDLE` exception invalid, so remove it.

The hash covers the body after any Markdown front matter (the whole file for
YAML and HTML) with CRLF normalized to LF.
Metadata-only changes retain the hash. A body change invalidates it and
requires conformity to current policy or renewed, explicit exception review.
Reviewers—not heuristics—decide whether a rewrite has become material.
Every exception still receives sanitization and secret checks.

## Security Review

The full check uses the pinned Gitleaks module's maintained detectors plus
targeted checks. Its configuration is generated from that module's embedded
default, removing global/rule allowlist path exemptions that would otherwise
skip report evidence such as `bootstrap.js`, SVGs, or `node_modules/` scripts.
Positive detector path conditions and ordinary placeholder-value filters are
preserved. Keep the module pin, executable pin, and Makefile version aligned.
It runs the scanner with an explicit configuration, ignores inline suppression
comments and submitted `.gitleaksignore` files, redacts matches, and fails
closed on errors/timeouts. Its only content-specific false-positive allowance
is an **exact Jira metadata assignment** for the generic API-key detector;
other detectors still apply. Root Git internals/local build output are omitted.

Automated scanning cannot guarantee absence of PII, customer information,
private cluster names, secrets in images, novel identifiers, or obfuscated
content. Review every artifact, including screenshots, logs, scripts, and
configuration snippets. Remove sensitive values rather than weakening a rule.
Also review evidence authenticity/completeness, expected-versus-actual results,
test coverage, and any external styling or embedded active content.

## CI and Required-Check Activation

### Compatibility Evaluation

The repository's sanitized `plans/_example.md` passes. Representative open
contributions were evaluated as artifact-only snapshots without executing
their reproduction kits:

- [PR #6 at a3b2ddc](https://github.com/hypershift-community/test-results-verification/pull/6):
  the plan and three-scenario HTML bundle pass, including local evidence,
  styles, scripts, and a standard AWS documentation-account placeholder.
- [PR #8 at 37dd156](https://github.com/hypershift-community/test-results-verification/pull/8):
  the plan and one-scenario HTML bundle pass, including literal loopback
  development endpoints in sanitized evidence.
- [PR #9 at fd72d1e](https://github.com/hypershift-community/test-results-verification/pull/9):
  the Markdown report fails for a plan link escaping the repository, a missing
  evidence heading, and a header claiming 11 passes while 12 test-case rows
  pass. Its verdict metadata/header does not require a duplicate verdict
  section. This snapshot was evaluated without changing the report.
- [PR #1 at 1424179](https://github.com/hypershift-community/test-results-verification/pull/1):
  the body is recognized despite its different section layout, but YAML
  front matter, the four core fields, and the IEEE policy declaration are
  missing. Its author must add verified metadata or request an explicit
  reviewed legacy exception before the required check is enabled for it.

### Enforcement

GitHub Actions runs `make install-tools`, `make test`, `make lint`, and
`make build` in the **Validate artifacts and Go** job on the shared ARM64
**`arc-runner-set`** self-hosted runners, registered for this repository as
described in [runner onboarding](runners.md). Existing OpenShift repo runners
are not automatically available to this community repo. The workflow runs on
every `pull_request` targeting any branch, on pushes to `main`, and on manual
dispatch, with read-only contents permission, no secrets, no persisted
checkout credentials, and a time limit.

Pull requests execute their own Makefile and Go code on the shared pool, so
fork PRs must not run without maintainer review. Keep the repository's
**Actions → General → Fork pull request workflows** setting at **Require
approval for all external contributors**, and review a fork PR's Makefile,
workflow, and Go changes before approving its run. Live infrastructure/App changes
require separate operator approval; CI does not provision its own runners.

After the workflow lands and produces a successful check on `main`, a
repository administrator must add **Validate artifacts and Go** to the
applicable branch protection/ruleset's required status checks. Preserve all
existing rules and confirm a deliberately invalid artifact blocks a test PR.
At implementation time, the active `main` ruleset (ID **22805904**) contains
pull-request review, deletion, and non-fast-forward protections, but no
required-status-check rule. Add the new check there without replacing those
protections; CNTRLPLANE-4798 tracks this post-merge activation. In the same
change, confirm the fork pull request approval setting described above.
This post-merge activation is intentionally not performed by the linter or by
adding a required check that does not exist yet. Track the activation and any
pre-existing contribution incompatibilities in CNTRLPLANE-4798 or a follow-up.

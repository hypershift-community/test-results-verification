package artifactlint_test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	. "github.com/onsi/gomega"

	"github.com/hypershift-community/test-results-verification/internal/artifactlint"
)

func writeFiles(t *testing.T, files map[string]string) string {
	t.Helper()
	root := t.TempDir()
	for name, contents := range files {
		p := filepath.Join(root, filepath.FromSlash(name))
		g := NewWithT(t)
		g.Expect(os.MkdirAll(filepath.Dir(p), 0o755)).To(Succeed())
		g.Expect(os.WriteFile(p, []byte(contents), 0o600)).To(Succeed())
	}
	return root
}

const planBody = `
# Example
## Test Plan Identifier
TP-EXAMPLE-001
## Introduction and Objectives
Verify the behavior and acceptance criteria.
## Test Items and References
The example controller.
## Test Environment
A test cluster.
## Test Cases
Run the operation; expect success.
## Risks and Mitigations
Use an isolated namespace.
## Approvals
Review pending.
`

const planMetadata = `---
id: TP-EXAMPLE-001
title: Example plan
date: 2026-10-20
status: draft
ieee_829: true
---
`

func TestPlanMetadata(t *testing.T) {
	t.Parallel()
	t.Run("When a new IEEE plan has valid metadata, it should pass validation", func(t *testing.T) {
		g := NewWithT(t)
		result, err := artifactlint.Validate(writeFiles(t, map[string]string{
			"plans/example.md": planMetadata + planBody,
		}))
		g.Expect(err).NotTo(HaveOccurred())
		g.Expect(result.HasErrors()).To(BeFalse(), "%+v", result.Findings)
	})
	tests := []struct {
		name    string
		content string
		rule    string
	}{
		{"When a plan lacks front matter, it should report missing metadata", planBody, "FRONTMATTER"},
		{"When a title is null, it should reject the missing value", strings.ReplaceAll(planMetadata, "title: Example plan", "title: null") + planBody, "META"},
		{"When a date is impossible, it should reject the date", strings.ReplaceAll(planMetadata, "2026-10-20", "2026-02-30") + planBody, "META"},
		{"When a status is unknown, it should reject the status", strings.ReplaceAll(planMetadata, "status: draft", "status: done") + planBody, "META"},
		{"When a boolean is quoted, it should reject the scalar type", strings.ReplaceAll(planMetadata, "ieee_829: true", "ieee_829: \"true\"") + planBody, "META"},
		{"When IEEE is disabled on a new plan, it should reject the profile", strings.ReplaceAll(planMetadata, "ieee_829: true", "ieee_829: false") + planBody, "PROFILE"},
		{"When a date is an unquoted out-of-range month, it should reject the date", strings.ReplaceAll(planMetadata, "2026-10-20", "2026-13-01") + planBody, "META"},
		{"When a status uses a YAML 1.1 boolean word, it should reject the status", strings.ReplaceAll(planMetadata, "status: draft", "status: yes") + planBody, "META"},
		{"When the IEEE flag uses a YAML 1.1 boolean word, it should reject the scalar type", strings.ReplaceAll(planMetadata, "ieee_829: true", "ieee_829: yes") + planBody, "META"},
		{"When a version is an unquoted float, it should require a string", strings.ReplaceAll(planMetadata, "status: draft", "status: draft\nversion: 4.18") + planBody, "META"},
		{"When a core field is absent, it should name the missing field", strings.ReplaceAll(planMetadata, "title: Example plan\n", "") + planBody, "MISSING_TITLE"},
		{"When YAML repeats a key, it should reject ambiguous metadata", strings.ReplaceAll(planMetadata, "status: draft", "status: draft\nstatus: active") + planBody, "YAML"},
		{"When YAML contains an alias, it should reject indirection", strings.ReplaceAll(planMetadata, "title: Example plan", "title: &title Example plan\nauthor: *title") + planBody, "YAML"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			g := NewWithT(t)
			result, err := artifactlint.Validate(writeFiles(t, map[string]string{"plans/example.md": tt.content}))
			g.Expect(err).NotTo(HaveOccurred())
			g.Expect(result.Findings).To(ContainElement(HaveField("Rule", tt.rule)))
		})
	}
}

func TestPlanDiscovery(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name  string
		files map[string]string
	}{
		{"When a plan uses an uppercase extension, it should reject rather than ignore it", map[string]string{"plans/example.MD": planMetadata + planBody}},
		{"When a plan is a text file, it should report unsupported artifact naming", map[string]string{"plans/example.txt": planMetadata + planBody}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			g := NewWithT(t)
			result, err := artifactlint.Validate(writeFiles(t, tt.files))
			g.Expect(err).NotTo(HaveOccurred())
			g.Expect(result.Findings).To(ContainElement(HaveField("Rule", "NAME")))
		})
	}
}

func TestPlanStructure(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name      string
		body      string
		wantError bool
	}{
		{"When equivalent headings are used, it should accept the content areas", strings.NewReplacer("Introduction and Objectives", "Purpose and Objectives", "Test Items and References", "References", "Test Cases", "Test Approach", "Risks and Mitigations", "Risks and Contingencies", "Approvals", "Approval and Exit Criteria").Replace(planBody), false},
		{"When a required section exists only in a fence, it should report missing structure", strings.ReplaceAll(planBody, "## Test Environment\nA test cluster.", "```markdown\n## Test Environment\nA test cluster.\n```"), true},
		{"When a section is empty, it should request useful content", strings.ReplaceAll(planBody, "A test cluster.", ""), true},
		{"When numbering differs from the template, it should accept equivalent structure", strings.ReplaceAll(planBody, "## ", "## 12. "), false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			g := NewWithT(t)
			result, err := artifactlint.Validate(writeFiles(t, map[string]string{"plans/example.md": planMetadata + tt.body}))
			g.Expect(err).NotTo(HaveOccurred())
			g.Expect(result.HasErrors()).To(Equal(tt.wantError), "%+v", result.Findings)
		})
	}
}

func TestPlanRelationships(t *testing.T) {
	t.Parallel()
	jira := "jira_issues:\n  - key: CNTRLPLANE-7\n    role: primary\n    url: https://redhat.atlassian.net/browse/CNTRLPLANE-7\n"
	pr := "pull_requests:\n  - repo: openshift/hypershift\n    number: 42\n    role: implementation\n    url: https://github.com/openshift/hypershift/pull/42\n"
	withFields := func(fields string) string {
		return strings.Replace(planMetadata, "status: draft", fields+"status: draft", 1) + planBody
	}
	tests := []struct {
		name      string
		files     map[string]string
		wantError bool
	}{
		{"When one plan lists primary and backport issues, it should preserve a single plan", map[string]string{"plans/cntrlplane-7.md": withFields(jira + pr + "  - repo: openshift/hypershift\n    number: 43\n    role: backport\n    url: https://github.com/openshift/hypershift/pull/43\n")}, false},
		{"When the primary issue differs from the filename, it should reject the mismatch", map[string]string{"plans/example.md": withFields(jira)}, true},
		{"When the PR URL points to another number, it should reject the relationship", map[string]string{"plans/example.md": withFields(strings.ReplaceAll(pr, "pull/42", "pull/43"))}, true},
		{"When a relationship list has the wrong type, it should reject it", map[string]string{"plans/example.md": withFields("jira_issues: null\n")}, true},
		{"When two production plans share an ID, it should reject ambiguous identity", map[string]string{"plans/one.md": planMetadata + planBody, "plans/two.md": planMetadata + planBody}, true},
		{"When a superseded plan and its replacement list the same Jira issue, it should accept the shared history", map[string]string{"plans/cntrlplane-7.md": strings.Replace(planMetadata, "status: draft", jira+"status: superseded\nsuperseded_by: cntrlplane-8", 1) + planBody, "plans/cntrlplane-8.md": strings.Replace(strings.Replace(planMetadata, "TP-EXAMPLE-001", "TP-EXAMPLE-002", 1), "status: draft", "jira_issues:\n  - key: CNTRLPLANE-8\n    role: primary\n    url: https://redhat.atlassian.net/browse/CNTRLPLANE-8\n  - key: CNTRLPLANE-7\n    role: backport\n    url: https://redhat.atlassian.net/browse/CNTRLPLANE-7\nstatus: active", 1) + planBody}, false},
		{"When an example shares an ID with a production plan, it should not create a production conflict", map[string]string{"plans/_example.md": planMetadata + planBody, "plans/example.md": planMetadata + planBody}, false},
		{"When a superseded plan has no replacement, it should report the missing reference", map[string]string{"plans/example.md": strings.ReplaceAll(planMetadata, "status: draft", "status: superseded") + planBody}, true},
		{"When a replacement was deleted, it should report the dangling reference", map[string]string{"plans/example.md": withFields("superseded_by: missing\n")}, true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			g := NewWithT(t)
			result, err := artifactlint.Validate(writeFiles(t, tt.files))
			g.Expect(err).NotTo(HaveOccurred())
			g.Expect(result.HasErrors()).To(Equal(tt.wantError), "%+v", result.Findings)
		})
	}
}

const htmlMetadata = `jira_key: CNTRLPLANE-7
format: html-bundle
date: 2026-10-20
verdict: fail
scenario_count: 1
pass_count: 0
ci_verified: false
has_derived_markdown: false
`

const markdownReport = `---
jira_key: CNTRLPLANE-7
format: markdown
date: 2026-10-20
verdict: conditional
pr:
  repo: openshift/hypershift
  number: 42
  url: https://github.com/openshift/hypershift/pull/42
---
# Verification report
## Environment
A test cluster.
## Results
One scenario failed.
## Evidence
Sanitized log excerpt.
## Verdict
Conditional: follow-up required.
`

func TestReports(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name      string
		files     map[string]string
		wantError bool
	}{
		{"When a valid HTML report records failed tests, it should pass artifact lint", map[string]string{"reports/cntrlplane-7/metadata.yaml": htmlMetadata, "reports/cntrlplane-7/index.html": "<h1>Results</h1>", "reports/cntrlplane-7/scenario-1.html": "<h1>Failed scenario</h1>"}, false},
		{"When a Markdown report records a conditional verdict, it should pass artifact lint", map[string]string{"reports/cntrlplane-7/42.md": markdownReport}, false},
		{"When a Markdown report links local evidence, it should not require an HTML bundle", map[string]string{"reports/cntrlplane-7/42.md": markdownReport + "\n[Log](assets/result.csv)\n", "reports/cntrlplane-7/assets/result.csv": "case,result\nTC-1,fail\n"}, false},
		{"When bundle metadata is absent, it should discover and reject the partial bundle", map[string]string{"reports/cntrlplane-7/index.html": "<h1>Results</h1>"}, true},
		{"When only supporting assets remain, it should discover the partial bundle", map[string]string{"reports/cntrlplane-7/assets/log.txt": "sanitized evidence"}, true},
		{"When a Markdown filename disagrees with its PR, it should report the mismatch", map[string]string{"reports/cntrlplane-7/43.md": markdownReport}, true},
		{"When a report references a missing plan, it should report the dangling reference", map[string]string{"reports/cntrlplane-7/42.md": strings.Replace(markdownReport, "format: markdown", "plan: missing\nformat: markdown", 1)}, true},
		{"When a scenario count disagrees with the files, it should reject the count", map[string]string{"reports/cntrlplane-7/metadata.yaml": strings.Replace(htmlMetadata, "scenario_count: 1", "scenario_count: 2", 1), "reports/cntrlplane-7/index.html": "<h1>Results</h1>"}, true},
		{"When a count is a boolean, it should reject the scalar type", map[string]string{"reports/cntrlplane-7/metadata.yaml": strings.Replace(htmlMetadata, "pass_count: 0", "pass_count: true", 1), "reports/cntrlplane-7/index.html": "<h1>Results</h1>", "reports/cntrlplane-7/scenario-1.html": "<h1>Scenario</h1>"}, true},
		{"When derived Markdown exists without an HTML entry point, it should preserve the authoritative-format requirement", map[string]string{"reports/cntrlplane-7/derived/report.md": "# Summary"}, true},
		{"When a standalone report accompanies orphaned derived Markdown, it should still require authoritative HTML", map[string]string{"reports/cntrlplane-7/42.md": markdownReport, "reports/cntrlplane-7/derived/report.md": "# Derived summary"}, true},
		{"When a bundle includes a top-level README, it should treat it as bundle documentation", map[string]string{"reports/cntrlplane-7/metadata.yaml": htmlMetadata, "reports/cntrlplane-7/index.html": "<h1>Results</h1>", "reports/cntrlplane-7/scenario-1.html": "<h1>Scenario</h1>", "reports/cntrlplane-7/README.md": "# How to read this bundle"}, false},
		{"When a Markdown-only directory has a non-PR filename, it should report the naming error", map[string]string{"reports/cntrlplane-7/report.md": markdownReport}, true},
		{"When a scenario count is an unquoted float, it should reject the scalar type", map[string]string{"reports/cntrlplane-7/metadata.yaml": strings.Replace(htmlMetadata, "scenario_count: 1", "scenario_count: 1.0", 1), "reports/cntrlplane-7/index.html": "<h1>Results</h1>", "reports/cntrlplane-7/scenario-1.html": "<h1>Scenario</h1>"}, true},
		{"When evidence Markdown has no front matter, it should not mistake it for a standalone report", map[string]string{"reports/cntrlplane-7/metadata.yaml": htmlMetadata, "reports/cntrlplane-7/index.html": "<h1>Results</h1>", "reports/cntrlplane-7/scenario-1.html": "<h1>Scenario</h1>", "reports/cntrlplane-7/assets/evidence.md": "# Raw results"}, false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			g := NewWithT(t)
			result, err := artifactlint.Validate(writeFiles(t, tt.files))
			g.Expect(err).NotTo(HaveOccurred())
			g.Expect(result.HasErrors()).To(Equal(tt.wantError), "%+v", result.Findings)
		})
	}
}

func TestReportConsistency(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name     string
		metadata string
		extra    map[string]string
		rule     string
	}{
		{"When passed scenarios exceed the total, it should reject inconsistent counts", strings.Replace(htmlMetadata, "pass_count: 0", "pass_count: 2", 1), nil, "COUNTS"},
		{"When a count is boolean but scenario files agree, it should reject the type", strings.Replace(htmlMetadata, "pass_count: 0", "pass_count: true", 1), nil, "META"},
		{"When CI is declared verified without evidence, it should request the CI results page", strings.Replace(htmlMetadata, "ci_verified: false", "ci_verified: true", 1), nil, "REPORT"},
		{"When the derived flag is true without a summary, it should reject the declaration", strings.Replace(htmlMetadata, "has_derived_markdown: false", "has_derived_markdown: true", 1), nil, "REPORT"},
		{"When a derived summary exists but the flag is false, it should reject the declaration", htmlMetadata, map[string]string{"reports/cntrlplane-7/derived/report.md": "# Summary"}, "REPORT"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			g := NewWithT(t)
			files := map[string]string{"reports/cntrlplane-7/metadata.yaml": tt.metadata, "reports/cntrlplane-7/index.html": "<h1>Report</h1>", "reports/cntrlplane-7/scenario-1.html": "<h1>Scenario</h1>"}
			for k, v := range tt.extra {
				files[k] = v
			}
			result, err := artifactlint.Validate(writeFiles(t, files))
			g.Expect(err).NotTo(HaveOccurred())
			g.Expect(result.Findings).To(ContainElement(HaveField("Rule", tt.rule)))
		})
	}
}

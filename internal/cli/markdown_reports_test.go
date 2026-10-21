package cli_test

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	. "github.com/onsi/gomega"

	"github.com/hypershift-community/test-results-verification/internal/artifactlint"
	"github.com/hypershift-community/test-results-verification/internal/cli"
)

const countReport = `---
jira_key: CNTRLPLANE-7
format: markdown
date: 2026-10-20
verdict: pass
pr:
  repo: openshift/hypershift
  number: 42
  url: https://github.com/openshift/hypershift/pull/42
---
# Verification report

**Verdict:** **PASS** (11 pass, 1 skip [environment], 0 fail)

## Environment
An isolated test cluster.

## Results
| # | Test Case | Result | Notes |
|---|---|---|---|
| TC-001 | First case | PASS | Verified. |
| TC-002 | Second case | PASS | Verified. |
| TC-003 | Third case | PASS | Verified. |
| TC-004 | Fourth case | PASS | Verified. |
| TC-005 | Fifth case | PASS | Verified. |
| TC-006 | Sixth case | PASS | Verified. |
| TC-007 | Seventh case | PASS | Verified. |
| TC-008 | Eighth case | PASS | Verified. |
| TC-009 | Ninth case | PASS | Verified. |
| TC-010 | Tenth case | PASS | Verified. |
| TC-011 | Eleventh case | PASS | Verified. |
| TC-012 | Twelfth case | PASS | Verified. |
| TC-013 | Thirteenth case | SKIP | Environment unavailable. |

## Evidence
Sanitized observations accompany each result.
`

func TestMarkdownReportCLI(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name   string
		report string
		format string
		code   int
	}{
		{"When the summary claims eleven passes but twelve rows pass, it should return a validation error in JSON", countReport, "json", 1},
		{"When counts disagree, it should annotate the summary line for GitHub Actions", countReport, "github", 1},
		{"When an unrelated table has both Result and Status columns, it should not bypass count validation", countReport + "\n| Component | Result | Status |\n|---|---|---|\n| Controller | Healthy | Ready |\n", "json", 1},
		{"When counts are corrected without adding a verdict section, it should succeed", strings.Replace(countReport, "11 pass", "12 pass", 1), "json", 0},
		{"When failed tests agree with a fail summary, it should not confuse the outcome with a lint failure", strings.NewReplacer("verdict: pass", "verdict: fail", "**PASS** (11 pass", "**FAIL** (11 pass", "| TC-012 | Twelfth case | PASS", "| TC-012 | Twelfth case | FAIL", "0 fail", "1 fail").Replace(countReport), "json", 0},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			g := NewWithT(t)
			root := t.TempDir()
			directory := filepath.Join(root, "reports", "cntrlplane-7")
			g.Expect(os.MkdirAll(directory, 0o755)).To(Succeed())
			g.Expect(os.WriteFile(filepath.Join(directory, "42.md"), []byte(tt.report), 0o600)).To(Succeed())
			var out, errs bytes.Buffer
			g.Expect(cli.Run([]string{"--root", root, "--format", tt.format}, &out, &errs)).To(Equal(tt.code), out.String()+errs.String())
			g.Expect(errs.String()).To(BeEmpty())
			if tt.format == "json" {
				var result artifactlint.Result
				g.Expect(json.Unmarshal(out.Bytes(), &result)).To(Succeed())
				if tt.code == 0 {
					g.Expect(result.Findings).To(BeEmpty())
				} else {
					g.Expect(result.Findings).To(ConsistOf(And(
						HaveField("Path", "reports/cntrlplane-7/42.md"),
						HaveField("Line", 13),
						HaveField("Rule", "COUNTS"),
						HaveField("Severity", artifactlint.SeverityError),
						HaveField("Message", "summary pass count must equal the number of matching test-case results"),
					)))
				}
			} else {
				g.Expect(out.String()).To(Equal("::error file=reports/cntrlplane-7/42.md,line=13,title=COUNTS::summary pass count must equal the number of matching test-case results\n"))
			}
		})
	}
}

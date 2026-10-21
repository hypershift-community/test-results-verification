package artifactlint_test

import (
	"strings"
	"testing"

	. "github.com/onsi/gomega"

	"github.com/hypershift-community/test-results-verification/internal/artifactlint"
)

func TestMarkdownReportVerdict(t *testing.T) {
	t.Parallel()
	withoutHeading := strings.Replace(markdownReport, "## Verdict\nConditional: follow-up required.\n", "", 1)
	tests := []struct {
		name    string
		report  string
		wantErr bool
	}{
		{"When metadata supplies the verdict without a body heading, it should accept the report", withoutHeading, false},
		{"When a header repeats the metadata verdict, it should not require a redundant section", withoutHeading + "\n**Verdict:** **CONDITIONAL** — follow-up required.\n", false},
		{"When metadata records failure without a verdict section, it should accept the failed test outcome", strings.Replace(withoutHeading, "verdict: conditional", "verdict: fail", 1), false},
		{"When a body header supplies a verdict but metadata omits it, it should still require discoverable metadata", strings.Replace(withoutHeading, "verdict: conditional\n", "", 1) + "\n**Verdict:** CONDITIONAL\n", true},
		{"When a verdict value is invalid, it should not accept it merely because the body heading exists", strings.Replace(markdownReport, "verdict: conditional", "verdict: unknown", 1), true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			g := NewWithT(t)
			result, err := artifactlint.Validate(writeFiles(t, map[string]string{"reports/cntrlplane-7/42.md": tt.report}))
			g.Expect(err).NotTo(HaveOccurred())
			g.Expect(result.HasErrors()).To(Equal(tt.wantErr), "%+v", result.Findings)
			g.Expect(result.Findings).NotTo(ContainElement(HaveField("Message", "include a verdict section")))
		})
	}
}

func TestMarkdownReportCounts(t *testing.T) {
	t.Parallel()
	t.Run("When a verdict summary disagrees with the test-case results, it should report the inconsistency at the summary", func(t *testing.T) {
		g := NewWithT(t)
		report := strings.Replace(markdownReport, "# Verification report", "# Verification report\n\n**Verdict:** **CONDITIONAL** (1 pass, 1 skip [environment], 0 fail)\n", 1)
		report = strings.Replace(report, "One scenario failed.", "| Test Case | Result | Notes |\n|---|---|---|\n| TC-001 | PASS | Verified. |\n| TC-002 | PASS | Verified. |\n| TC-003 | SKIP | Unavailable. |", 1)
		result, err := artifactlint.Validate(writeFiles(t, map[string]string{"reports/cntrlplane-7/42.md": report}))
		g.Expect(err).NotTo(HaveOccurred())
		g.Expect(result.Findings).To(ConsistOf(And(
			HaveField("Path", "reports/cntrlplane-7/42.md"),
			HaveField("Line", 13),
			HaveField("Rule", "COUNTS"),
			HaveField("Severity", artifactlint.SeverityError),
			HaveField("Message", "summary pass count must equal the number of matching test-case results"),
		)))
	})
	t.Run("When a verdict follows other fields in the same header paragraph, it should still diagnose the summary line", func(t *testing.T) {
		g := NewWithT(t)
		report := strings.Replace(markdownReport, "# Verification report", "# Verification report\n\n**Date:** 2026-10-20\n**Executor:** example\n**Verdict:** **CONDITIONAL** (1 pass, 1 skip [environment], 0 fail)\n", 1)
		report = strings.Replace(report, "One scenario failed.", "| # | Test Case | Result | Notes |\n|---|---|---|---|\n| TC-001 | First case | PASS | Verified. |\n| TC-002 | Second case | PASS | Verified. |\n| TC-003 | Third case | SKIP | Unavailable. |", 1)
		result, err := artifactlint.Validate(writeFiles(t, map[string]string{"reports/cntrlplane-7/42.md": report}))
		g.Expect(err).NotTo(HaveOccurred())
		g.Expect(result.Findings).To(ConsistOf(And(HaveField("Rule", "COUNTS"), HaveField("Line", 15))))
	})
}

const testCaseResults = `| Test Case | Result | Notes |
|---|---|---|
| TC-001 | PASS | Verified. |
| TC-002 | PASS | Verified. |
| TC-003 | FAIL | Regression found. |
| TC-004 | SKIP | Environment unavailable. |
`

func TestMarkdownReportCountBoundaries(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name    string
		summary string
		table   string
		wantErr bool
	}{
		{"When explicit counts match all outcomes, it should accept a conditional report", "**Verdict:** CONDITIONAL (2 pass, 1 fail, 1 skip)", testCaseResults, false},
		{"When failed results match the summary, it should accept a failed report", "**Summary:** 2 pass, 1 fail, 1 skip", testCaseResults, false},
		{"When the fail count disagrees, it should reject the summary", "**Summary:** 2 pass, 0 fail, 1 skip", testCaseResults, true},
		{"When the skip count disagrees, it should reject the summary", "**Summary:** 2 pass, 1 fail, 0 skip", testCaseResults, true},
		{"When only one count is supplied, it should not assume omitted outcomes are zero", "**Summary:** 2 pass", testCaseResults, false},
		{"When zero counts match the results, it should accept them", "**Summary:** 0 pass, 0 fail, 4 skip", strings.NewReplacer("PASS", "SKIP", "FAIL", "SKIP").Replace(testCaseResults), false},
		{"When a count exceeds the integer range, it should reject it rather than wrap", "**Summary:** 99999999999999999999999999999 pass", testCaseResults, true},
		{"When status cells have formatting and mixed case, it should count their rendered values", "**Summary:** 2 PASS, 1 FAIL, 1 SKIP", strings.NewReplacer("PASS", "**Pass**", "FAIL", "`fail`", "SKIP", "*Skip*").Replace(testCaseResults), false},
		{"When notes contain escaped pipes, it should still use the result column", "**Summary:** 2 pass, 1 fail, 1 skip", strings.ReplaceAll(testCaseResults, "Verified.", `Verified A\|B.`), false},
		{"When the status column comes first, it should identify the header rather than assume a position", "**Summary:** 1 pass", "| Status | Test Case |\n|---|---|\n| PASS | TC-001 |\n", false},
		{"When there are no explicit counts, it should not infer them from narrative", "**Verdict:** CONDITIONAL — follow-up required.", testCaseResults, false},
		{"When numbers occur in unrelated prose, it should not interpret them as a report summary", "A previous run had 8 pass, 0 fail, 0 skip.", testCaseResults, false},
		{"When there is no results table, it should not guess counts from prose", "**Summary:** 2 pass, 1 fail, 1 skip", "Results are described in linked evidence.", false},
		{"When a summary is in a fenced example, it should ignore that example", "```markdown\nSummary: 99 pass\n```", testCaseResults, false},
		{"When a summary is in a blockquote, it should not treat it as the current report", "> Summary: 99 pass", testCaseResults, false},
		{"When a table is only a fenced example, it should not treat it as actual results", "**Summary:** 99 pass", "```markdown\n" + testCaseResults + "```", false},
		{"When only environment data has a result column, it should not count it as test cases", "**Summary:** 99 pass", strings.Replace(testCaseResults, "Test Case", "Property", 1), false},
		{"When an unrelated table has both Result and Status columns, it should still reject an inconsistent report summary", "**Summary:** 99 pass", testCaseResults + "\n| Component | Result | Status |\n|---|---|---|\n| Controller | Healthy | Ready |\n", true},
		{"When a test-case table has ambiguous result columns, it should leave the counts to review", "**Summary:** 99 pass", strings.Replace(testCaseResults, "Test Case | Result | Notes", "Test Case | Result | Status", 1), false},
		{"When multiple results tables could represent different runs, it should leave their scope to review", "**Summary:** 2 pass", testCaseResults + "\n" + testCaseResults, false},
		{"When another results table has unsupported outcomes, it should not compare a partial run to the summary", "**Summary:** 99 pass", testCaseResults + "\n" + strings.Replace(testCaseResults, "SKIP", "BLOCKED", 1), false},
		{"When result cells have unrecognized outcomes, it should not invent their meaning", "**Summary:** 99 pass", strings.Replace(testCaseResults, "SKIP", "BLOCKED", 1), false},
		{"When repeated summary declarations disagree, it should validate each one", "**Summary:** 2 pass\n\n**Verdict:** CONDITIONAL (1 pass)", testCaseResults, true},
		{"When an inline code example resembles a summary, it should ignore it", "`Summary: 99 pass`", testCaseResults, false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			g := NewWithT(t)
			report := strings.Replace(markdownReport, "# Verification report", "# Verification report\n\n"+tt.summary+"\n", 1)
			report = strings.Replace(report, "One scenario failed.", tt.table, 1)
			result, err := artifactlint.Validate(writeFiles(t, map[string]string{"reports/cntrlplane-7/42.md": report}))
			g.Expect(err).NotTo(HaveOccurred())
			g.Expect(result.HasErrors()).To(Equal(tt.wantErr), "%+v", result.Findings)
			if tt.wantErr {
				g.Expect(result.Findings).To(ContainElement(HaveField("Rule", "COUNTS")))
			}
		})
	}
}

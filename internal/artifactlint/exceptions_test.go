package artifactlint_test

import (
	"crypto/sha256"
	"fmt"
	"strings"
	"testing"

	. "github.com/onsi/gomega"

	"github.com/hypershift-community/test-results-verification/internal/artifactlint"
)

func TestReviewedExceptions(t *testing.T) {
	t.Parallel()
	body := "# Legacy plan\n\nPreserved test procedure.\n"
	config := fmt.Sprintf("version: 1\nexceptions:\n  - path: plans/legacy.md\n    kind: legacy\n    source: https://github.com/example/legacy/blob/main/plan.md\n    reason: Preserved original with documented gaps\n    body_sha256: %x\n    gaps: [Original lacks current sections]\n    rules: [PROFILE, STRUCTURE]\n", sha256.Sum256([]byte(body)))
	metadata := strings.Replace(planMetadata, "ieee_829: true\n", "", 1)
	config += fmt.Sprintf("    file_sha256: %x\n", sha256.Sum256([]byte(metadata+body)))
	tests := []struct {
		name      string
		content   string
		config    string
		wantError bool
	}{
		{"When an explicitly registered legacy body is unchanged, it should accept documented gaps", metadata + body, config, false},
		{"When metadata changes under a profile waiver, it should require renewed review", strings.Replace(metadata, "title: Example plan", "title: Preserved plan", 1) + body, config, true},
		{"When only metadata changes under a body-only waiver, it should retain the exception", strings.Replace(planMetadata, "title: Example plan", "title: Preserved plan", 1) + body, strings.Replace(strings.Split(config, "    file_sha256:")[0], "[PROFILE, STRUCTURE]", "[STRUCTURE]", 1), false},
		{"When legacy body content changes, it should require renewed review", metadata + body + "New test strategy.\n", config, true},
		{"When draft content has no exception, it should enforce the new-plan policy", metadata + body, "", true},
		{"When an exception tries to disable security, it should reject the configuration", metadata + body, strings.Replace(config, "[PROFILE, STRUCTURE]", "[SECURITY]", 1), true},
		{"When an exception tries to suppress malformed metadata, it should reject the configuration", metadata + body, strings.Replace(config, "[PROFILE, STRUCTURE]", "[META]", 1), true},
		{"When an exception omits remaining gaps, it should reject the configuration", metadata + body, strings.Replace(config, "    gaps: [Original lacks current sections]\n", "", 1), true},
		{"When an exception lists an empty gap, it should reject the configuration", metadata + body, strings.Replace(config, "[Original lacks current sections]", "[\"\"]", 1), true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			g := NewWithT(t)
			files := map[string]string{"plans/legacy.md": tt.content}
			if tt.config != "" {
				files[".artifactlint.yaml"] = tt.config
			}
			result, err := artifactlint.Validate(writeFiles(t, files))
			g.Expect(err).NotTo(HaveOccurred())
			g.Expect(result.HasErrors()).To(Equal(tt.wantError), "%+v", result.Findings)
		})
	}
	t.Run("When an excepted plan supplies an invalid date, it should retain the applied exception and reject the date", func(t *testing.T) {
		g := NewWithT(t)
		content := strings.Replace(metadata, "2026-10-20", "2026-02-30", 1) + body
		pinned := strings.Replace(config, fmt.Sprintf("%x", sha256.Sum256([]byte(metadata+body))), fmt.Sprintf("%x", sha256.Sum256([]byte(content))), 1)
		result, err := artifactlint.Validate(writeFiles(t, map[string]string{"plans/legacy.md": content, ".artifactlint.yaml": pinned}))
		g.Expect(err).NotTo(HaveOccurred())
		g.Expect(result.Findings).To(ConsistOf(
			HaveField("Rule", "EXCEPTION_APPLIED"),
			And(HaveField("Rule", "META"), HaveField("Message", "date must be a real calendar date")),
		))
	})
}

func TestLegacyWithoutMetadata(t *testing.T) {
	t.Parallel()
	t.Run("When a preserved plan has no metadata, it should remain a valid report-reference target with explicit gaps", func(t *testing.T) {
		g := NewWithT(t)
		body := "# Historical procedure\n\nPreserved source.\n"
		config := fmt.Sprintf("version: 1\nexceptions:\n  - path: plans/legacy.md\n    kind: legacy\n    source: https://github.com/example/source/blob/main/plan.md\n    reason: Historical source has no metadata\n    body_sha256: %x\n    gaps: [Original lacks current sections]\n    rules: [FRONTMATTER, MISSING_ID, MISSING_TITLE, MISSING_DATE, MISSING_STATUS, PROFILE, STRUCTURE]\n", sha256.Sum256([]byte(body)))
		config += fmt.Sprintf("    file_sha256: %x\n", sha256.Sum256([]byte(body)))
		result, err := artifactlint.Validate(writeFiles(t, map[string]string{"plans/legacy.md": body, ".artifactlint.yaml": config, "reports/cntrlplane-7/42.md": strings.Replace(markdownReport, "format: markdown", "plan: legacy\nformat: markdown", 1)}))
		g.Expect(err).NotTo(HaveOccurred())
		g.Expect(result.HasErrors()).To(BeFalse(), "%+v", result.Findings)
	})
}

func TestReportExceptions(t *testing.T) {
	t.Parallel()
	t.Run("When a report only excepts front matter, it should still enforce missing metadata and body rules", func(t *testing.T) {
		g := NewWithT(t)
		body := "# Historical result\n\nIncomplete source.\n"
		config := fmt.Sprintf("version: 1\nexceptions:\n  - path: reports/cntrlplane-7/42.md\n    kind: legacy\n    source: https://github.com/example/source/blob/main/result.md\n    reason: Historical source\n    body_sha256: %x\n    gaps: [Original lacks current sections]\n    rules: [FRONTMATTER]\n", sha256.Sum256([]byte(body)))
		config += fmt.Sprintf("    file_sha256: %x\n", sha256.Sum256([]byte(body)))
		result, err := artifactlint.Validate(writeFiles(t, map[string]string{"reports/cntrlplane-7/42.md": body, ".artifactlint.yaml": config}))
		g.Expect(err).NotTo(HaveOccurred())
		g.Expect(result.Findings).To(ContainElement(HaveField("Rule", "REPORT_BODY")))
		g.Expect(result.Findings).To(ContainElement(HaveField("Rule", "MISSING_JIRA_KEY")))
	})
}

func TestForbiddenExceptionRules(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name    string
		content string
		body    string
		rule    string
	}{
		{"When an otherwise valid plan contains sensitive content, it should reject the security waiver and retain the violation", planMetadata + planBody + "\nhttps://api." + "corp.internal" + "/logs\n", planBody + "\nhttps://api." + "corp.internal" + "/logs\n", "SECURITY"},
		{"When a supplied value is malformed, it should reject the metadata waiver and retain the violation", strings.Replace(planMetadata, "status: draft", "status: invalid", 1) + planBody, planBody, "META"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			g := NewWithT(t)
			config := fmt.Sprintf("version: 1\nexceptions:\n  - path: plans/legacy.md\n    kind: legacy\n    source: https://github.com/example/source/blob/main/plan.md\n    reason: Invalid suppression attempt\n    body_sha256: %x\n    gaps: [Original lacks current sections]\n    rules: [%s]\n", sha256.Sum256([]byte(tt.body)), tt.rule)
			result, err := artifactlint.Validate(writeFiles(t, map[string]string{"plans/legacy.md": tt.content, ".artifactlint.yaml": config}))
			g.Expect(err).NotTo(HaveOccurred())
			g.Expect(result.Findings).To(ContainElement(HaveField("Rule", "EXCEPTION")))
			g.Expect(result.Findings).To(ContainElement(HaveField("Rule", tt.rule)))
		})
	}
}

func TestBundleExceptions(t *testing.T) {
	t.Parallel()
	const index = "<h1>Historical results</h1>"
	partial := "jira_key: CNTRLPLANE-7\nformat: html-bundle\ndate: 2026-10-20\nverdict: pass\nci_verified: false\nhas_derived_markdown: false\n"
	exception := func(name, content, rules string) string {
		return fmt.Sprintf("version: 1\nexceptions:\n  - path: %s\n    kind: legacy\n    source: https://github.com/example/source/tree/main/report\n    reason: Migrated bundle predates count metadata\n    body_sha256: %x\n    gaps: [Scenario counts were never recorded]\n    rules: [%s]\n", name, sha256.Sum256([]byte(content)), rules)
	}
	tests := []struct {
		name      string
		files     map[string]string
		wantError bool
	}{
		{"When migrated bundle metadata lacks counts, it should accept explicitly excepted missing fields", map[string]string{"reports/cntrlplane-7/metadata.yaml": partial, "reports/cntrlplane-7/index.html": index, ".artifactlint.yaml": exception("reports/cntrlplane-7/metadata.yaml", partial, "MISSING_SCENARIO_COUNT, MISSING_PASS_COUNT")}, false},
		{"When migrated bundle metadata lacks counts without an exception, it should report the missing fields", map[string]string{"reports/cntrlplane-7/metadata.yaml": partial, "reports/cntrlplane-7/index.html": index}, true},
		{"When a bundle exception tries to suppress malformed metadata, it should reject the configuration", map[string]string{"reports/cntrlplane-7/metadata.yaml": partial, "reports/cntrlplane-7/index.html": index, ".artifactlint.yaml": exception("reports/cntrlplane-7/metadata.yaml", partial, "META")}, true},
		{"When a migrated bundle has no metadata, it should accept an exception pinned to its entry point", map[string]string{"reports/cntrlplane-7/index.html": index, ".artifactlint.yaml": exception("reports/cntrlplane-7/index.html", index, "BUNDLE")}, false},
		{"When the pinned entry point changes, it should require renewed review", map[string]string{"reports/cntrlplane-7/index.html": index + "<p>Edited</p>", ".artifactlint.yaml": exception("reports/cntrlplane-7/index.html", index, "BUNDLE")}, true},
		{"When bundle metadata is later added, it should reject the stale missing-metadata exception", map[string]string{"reports/cntrlplane-7/metadata.yaml": strings.Replace(htmlMetadata, "scenario_count: 1", "scenario_count: 0", 1), "reports/cntrlplane-7/index.html": index, ".artifactlint.yaml": exception("reports/cntrlplane-7/index.html", index, "BUNDLE")}, true},
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

func TestMetadataExceptionPin(t *testing.T) {
	t.Parallel()
	original := strings.Replace(planMetadata, "status: draft\n", "", 1) + completePlanBody
	config := fmt.Sprintf("version: 1\nexceptions:\n  - path: plans/example.md\n    kind: legacy\n    source: https://github.com/example/source/blob/main/plan.md\n    reason: Preserve missing status metadata\n    body_sha256: %s\n    gaps: [Status was not recorded]\n    rules: [MISSING_STATUS]\n", artifactlint.BodySHA256([]byte(original)))
	for _, tt := range []struct {
		name, content, pin string
		valid              bool
	}{
		{"When a metadata waiver has no file hash, it should require a reviewed metadata snapshot", original, "", false},
		{"When a metadata waiver matches the complete reviewed file, it should preserve the gap", original, fmt.Sprintf("    file_sha256: %x\n", sha256.Sum256([]byte(original))), true},
		{"When metadata changes under a missing-status waiver, it should require renewed review", strings.Replace(original, "title: Example plan", "title: Changed plan", 1), fmt.Sprintf("    file_sha256: %x\n", sha256.Sum256([]byte(original))), false},
	} {
		t.Run(tt.name, func(t *testing.T) {
			g := NewWithT(t)
			result, err := artifactlint.Validate(writeFiles(t, map[string]string{"plans/example.md": tt.content, ".artifactlint.yaml": config + tt.pin}))
			g.Expect(err).NotTo(HaveOccurred())
			if tt.valid {
				g.Expect(result.HasErrors()).To(BeFalse(), "%+v", result.Findings)
			} else {
				g.Expect(result.Findings).To(ContainElement(HaveField("Rule", "EXCEPTION")))
				g.Expect(result.Findings).NotTo(ContainElement(HaveField("Rule", "EXCEPTION_APPLIED")))
			}
		})
	}
}

package artifactlint_test

import (
	"crypto/sha256"
	"fmt"
	"strings"
	"testing"

	. "github.com/onsi/gomega"

	"github.com/hypershift-community/test-results-verification/internal/artifactlint"
)

const completePlanBody = `
# Example
## Test Plan Identifier
**ID:** TP-EXAMPLE-001
**Version:** 1.0
**Date:** 2026-10-20
IEEE 829-2008.
## Introduction and Objectives
Verify that scaling creates the requested number of workers.
### Acceptance Criteria Mapping
| Acceptance Criterion | Test Case |
|---|---|
| AC-1: The requested worker joins the cluster | TC-001 |
## Test Items and References
[Implementation](https://github.com/openshift/hypershift/pull/42).
## Test Environment
| Property | Value |
|---|---|
| Cluster type | HostedCluster |
| Platform | AWS |
| OCP version | 4.18+ |
| Prerequisites | A management cluster and the oc CLI |
## Test Cases
### TC-001: Scale a NodePool
**Objective:** Verify that the requested worker joins.
**Preconditions:** A Ready HostedCluster with one worker.
**Steps:**
| Step | Action | Expected Result |
|---|---|---|
| 1 | Scale the NodePool to two replicas | Two workers become Ready |
## Risks and Mitigations
| Risk | Mitigation |
|---|---|
| Unrelated workloads are affected | Use an isolated test cluster |
## Approvals
| Role | Name | Date |
|---|---|---|
| Author | example-author | 2026-10-20 |
| Reviewer | example-reviewer | 2026-10-21 |
`

func TestPlanContent(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name    string
		body    string
		rule    string
		message string
	}{
		{"When every area contains only TBD, it should reject the incomplete plan", "# Example\n## Test Plan Identifier\nTBD\n## Introduction and Objectives\nTBD\n## Test Items and References\nTBD\n## Test Environment\nTBD\n## Test Cases\nTBD\n## Risks and Mitigations\nTBD\n## Approvals\nTBD\n", "PLAN_CONTENT", "define at least one test case under a heading with a unique TC-<number> identifier"},
		{"When the test-case area has no identified cases, it should reject the empty strategy", strings.Replace(completePlanBody, "### TC-001: Scale a NodePool", "### Scale coverage", 1), "PLAN_CONTENT", "define at least one test case under a heading with a unique TC-<number> identifier"},
		{"When a case has no objective, it should request its purpose", strings.Replace(completePlanBody, "**Objective:** Verify that the requested worker joins.\n", "", 1), "PLAN_CONTENT", "test case must specify a non-placeholder objective"},
		{"When a case has no preconditions, it should request its starting state", strings.Replace(completePlanBody, "**Preconditions:** A Ready HostedCluster with one worker.\n", "", 1), "PLAN_CONTENT", "test case must specify preconditions, or explain why none apply"},
		{"When a precondition is a placeholder, it should reject the missing starting state", strings.Replace(completePlanBody, "A Ready HostedCluster with one worker.", "TODO", 1), "PLAN_CONTENT", "test case must specify preconditions, or explain why none apply"},
		{"When a precondition contains an unfinished instruction, it should reject the placeholder", strings.Replace(completePlanBody, "A Ready HostedCluster with one worker.", "TODO: describe the starting state", 1), "PLAN_CONTENT", "test case must specify preconditions, or explain why none apply"},
		{"When inherited preconditions reference an undefined case, it should reject the missing setup reference", strings.Replace(completePlanBody, "A Ready HostedCluster with one worker.", "TC-999 preconditions apply.", 1), "RELATIONSHIP", "test-case setup or execution references an undefined test case"},
		{"When a nested case has setup but its parent does not, it should not borrow the nested case's fields", strings.Replace(completePlanBody, "### TC-001: Scale a NodePool", "### TC-001: Unspecified parent case\n#### TC-002: Scale a NodePool", 1), "PLAN_CONTENT", "test case must specify preconditions, or explain why none apply"},
		{"When a step has no action, it should reject the incomplete procedure", strings.Replace(completePlanBody, "Scale the NodePool to two replicas", "", 1), "PLAN_CONTENT", "test case must include actions and expected results for every step, or an automated test reference, run command, and expected outcome"},
		{"When a step has no expected result, it should reject the incomplete assertion", strings.Replace(completePlanBody, "Two workers become Ready", "", 1), "PLAN_CONTENT", "test case must include actions and expected results for every step, or an automated test reference, run command, and expected outcome"},
		{"When one of multiple steps has no expected result, it should check every row", strings.Replace(completePlanBody, "## Risks", "| 2 | Scale to three replicas | TBD |\n## Risks", 1), "PLAN_CONTENT", "test case must include actions and expected results for every step, or an automated test reference, run command, and expected outcome"},
		{"When expected results exist only in a fenced example, it should not count the example as a procedure", strings.Replace(strings.Replace(completePlanBody, "**Steps:**\n| Step", "```markdown\n**Steps:**\n| Step", 1), "## Risks", "```\n## Risks", 1), "PLAN_CONTENT", "test case must include actions and expected results for every step, or an automated test reference, run command, and expected outcome"},
		{"When an acceptance mapping is absent, it should request traceability", strings.Replace(completePlanBody, "| Acceptance Criterion | Test Case |\n|---|---|\n| AC-1: The requested worker joins the cluster | TC-001 |\n", "", 1), "PLAN_CONTENT", "include a populated acceptance-criteria mapping table with criterion and test-case columns"},
		{"When a criterion maps to an undefined case, it should reject the dangling reference", strings.Replace(completePlanBody, "cluster | TC-001 |", "cluster | TC-999 |", 1), "RELATIONSHIP", "acceptance criterion references an undefined test case"},
		{"When a criterion has no mapped case, it should reject the uncovered criterion", strings.Replace(completePlanBody, "cluster | TC-001 |", "cluster | |", 1), "PLAN_CONTENT", "each acceptance criterion must have a description and map to at least one defined test case"},
		{"When a criterion is a placeholder, it should reject the incomplete mapping", strings.Replace(completePlanBody, "AC-1: The requested worker joins the cluster", "TBD", 1), "PLAN_CONTENT", "each acceptance criterion must have a description and map to at least one defined test case"},
		{"When a cluster context is absent, it should request the test target", strings.Replace(completePlanBody, "| Cluster type | HostedCluster |\n", "", 1), "PLAN_CONTENT", "test environment must specify non-placeholder cluster type or test target"},
		{"When the platform is absent, it should request the deployment context", strings.Replace(completePlanBody, "| Platform | AWS |\n", "", 1), "PLAN_CONTENT", "test environment must specify non-placeholder platform or provider"},
		{"When the version is absent, it should request the tested build or version", strings.Replace(completePlanBody, "| OCP version | 4.18+ |\n", "", 1), "PLAN_CONTENT", "test environment must specify non-placeholder version or build"},
		{"When prerequisites are absent, it should request the environment dependencies", strings.Replace(completePlanBody, "| Prerequisites | A management cluster and the oc CLI |\n", "", 1), "PLAN_CONTENT", "test environment must specify non-placeholder prerequisites or tooling"},
		{"When objectives contain only a labelled placeholder, it should reject the incomplete purpose", strings.Replace(completePlanBody, "Verify that scaling creates the requested number of workers.", "**Purpose:** TBD", 1), "PLAN_CONTENT", "describe the plan's purpose and objectives with non-placeholder content"},
		{"When a risk has no mitigation, it should reject the unaddressed risk", strings.Replace(completePlanBody, "Use an isolated test cluster", "", 1), "PLAN_CONTENT", "each risk must have a non-placeholder description and mitigation"},
		{"When a second risk has no mitigation, it should validate every risk", strings.Replace(completePlanBody, "## Approvals", "| Slow reconciliation | TBD |\n## Approvals", 1), "PLAN_CONTENT", "each risk must have a non-placeholder description and mitigation"},
		{"When approval roles are absent, it should request an author and reviewer", strings.Replace(completePlanBody, "| Role | Name | Date |\n|---|---|---|\n| Author | example-author | 2026-10-20 |\n| Reviewer | example-reviewer | 2026-10-21 |", "Review pending.", 1), "PLAN_CONTENT", "approvals must identify an author with a date and a reviewer role; active plans also require a named reviewer and approval date"},
		{"When the author is unspecified, it should reject the incomplete approval information", strings.Replace(completePlanBody, "example-author", "", 1), "PLAN_CONTENT", "author approval entry must identify the author and a real calendar date"},
		{"When case IDs are duplicated, it should reject the ambiguous definition", strings.Replace(completePlanBody, "## Risks", "### TC-001: Duplicate\n**Objective:** Verify cleanup.\n**Preconditions:** A test cluster.\n**Steps:** Delete the NodePool.\n**Expected result:** All workers are removed.\n## Risks", 1), "IDENTITY", "test-case identifiers must be unique within a plan"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			g := NewWithT(t)
			result, err := artifactlint.Validate(writeFiles(t, map[string]string{"plans/example.md": planMetadata + tt.body}))
			g.Expect(err).NotTo(HaveOccurred())
			g.Expect(result.Findings).To(ContainElement(And(HaveField("Rule", tt.rule), HaveField("Severity", artifactlint.SeverityError), HaveField("Message", tt.message))), "%+v", result.Findings)
		})
	}
}

func TestPlanContentLocation(t *testing.T) {
	t.Parallel()
	for _, tt := range []struct{ name, body, target, message string }{
		{"When a mitigation is missing, it should identify the incomplete risk row", strings.Replace(completePlanBody, "Use an isolated test cluster", "", 1), "| Unrelated workloads", "each risk must have a non-placeholder description and mitigation"},
		{"When a later row lacks its first cell, it should identify that row", strings.Replace(completePlanBody, "## Approvals", "| | Restart the test |\n## Approvals", 1), "| | Restart", "each risk must have a non-placeholder description and mitigation"},
		{"When many headings precede an incomplete case, it should preserve its source line", strings.Replace(strings.Replace(completePlanBody, "**Preconditions:** A Ready HostedCluster with one worker.\n", "", 1), "## Test Environment", strings.Repeat("### Supporting note\nDetails.\n", 500)+"## Test Environment", 1), "### TC-001", "test case must specify preconditions, or explain why none apply"},
	} {
		t.Run(tt.name, func(t *testing.T) {
			g := NewWithT(t)
			plan := planMetadata + tt.body
			prefix, _, found := strings.Cut(plan, tt.target)
			g.Expect(found).To(BeTrue())
			result, err := artifactlint.Validate(writeFiles(t, map[string]string{"plans/example.md": plan}))
			g.Expect(err).NotTo(HaveOccurred())
			g.Expect(result.Findings).To(ConsistOf(And(
				HaveField("Path", "plans/example.md"), HaveField("Line", strings.Count(prefix, "\n")+1),
				HaveField("Rule", "PLAN_CONTENT"), HaveField("Message", tt.message),
			)))
		})
	}
}

func TestPlanExampleFields(t *testing.T) {
	t.Parallel()
	for _, tt := range []struct{ name, original, replacement, message string }{
		{"When an objective only contains a fenced example, it should remain missing", "**Objective:** Verify that the requested worker joins.", "**Objective:**\n\n```text\nVerify that the requested worker joins.\n```", "test case must specify a non-placeholder objective"},
		{"When preconditions only contain a fenced example, it should report the missing setup", "**Preconditions:** A Ready HostedCluster with one worker.", "**Preconditions:**\n\n```text\nA Ready HostedCluster with one worker.\n```", "test case must specify preconditions, or explain why none apply"},
		{"When preconditions only contain an indented example, it should report the missing setup", "**Preconditions:** A Ready HostedCluster with one worker.", "**Preconditions:**\n\n    A Ready HostedCluster with one worker.\n", "test case must specify preconditions, or explain why none apply"},
		{"When a precondition list only contains a fenced example, it should remain missing", "**Preconditions:** A Ready HostedCluster with one worker.", "**Preconditions:**\n\n- ```text\n  A Ready HostedCluster with one worker.\n  ```", "test case must specify preconditions, or explain why none apply"},
	} {
		t.Run(tt.name, func(t *testing.T) {
			g := NewWithT(t)
			body := strings.Replace(completePlanBody, tt.original, tt.replacement, 1)
			result, err := artifactlint.Validate(writeFiles(t, map[string]string{"plans/example.md": planMetadata + body}))
			g.Expect(err).NotTo(HaveOccurred())
			g.Expect(result.Findings).To(ContainElement(And(HaveField("Rule", "PLAN_CONTENT"), HaveField("Message", tt.message))))
		})
	}
}

func TestPlanAreaSelection(t *testing.T) {
	t.Parallel()
	beforeEnvironment, environmentAndRest, _ := strings.Cut(completePlanBody, "## Test Environment")
	environment, casesAndRest, _ := strings.Cut(environmentAndRest, "## Test Cases")
	cases, risksAndRest, _ := strings.Cut(casesAndRest, "## Risks and Mitigations")
	reordered := beforeEnvironment + "## Test Cases" + strings.Replace(cases, "**Preconditions:**", "#### Prerequisites\n", 1) + "## Test Environment" + environment + "## Risks and Mitigations" + risksAndRest
	borrowed := strings.Replace(completePlanBody, "# Example", "# Test Plan: Environment scaling", 1)
	borrowed = strings.Replace(borrowed, "| Platform | AWS |\n", "", 1)
	borrowed = strings.Replace(borrowed, "## Test Environment", "**Platform:** AWS\n## Test Environment", 1)
	for _, tt := range []struct {
		name string
		body string
		rule string
	}{
		{"When case prerequisites precede the environment area, it should validate the actual environment", reordered, ""},
		{"When the document title mentions environment, it should not borrow platform information from references", borrowed, "PLAN_CONTENT"},
		{"When a title mentions environment and the real area is absent, it should report the missing area", strings.Replace(strings.Replace(completePlanBody, "# Example", "# Environment scaling", 1), "## Test Environment", "## Deployment details", 1), "STRUCTURE"},
		{"When area headings are combined, it should retain their supported content", strings.Replace(completePlanBody, "## Test Environment", "## Test Environment and Prerequisites", 1), ""},
		{"When content areas use H1 headings without a document title, it should retain the first area", strings.ReplaceAll(strings.TrimPrefix(completePlanBody, "\n# Example\n"), "## ", "# "), ""},
		{"When content areas are under a wrapper heading, it should accept that hierarchy", strings.ReplaceAll(completePlanBody, "## ", "### "), ""},
	} {
		t.Run(tt.name, func(t *testing.T) {
			g := NewWithT(t)
			result, err := artifactlint.Validate(writeFiles(t, map[string]string{"plans/example.md": planMetadata + tt.body}))
			g.Expect(err).NotTo(HaveOccurred())
			g.Expect(result.HasErrors()).To(Equal(tt.rule != ""), "%+v", result.Findings)
			if tt.rule != "" {
				g.Expect(result.Findings).To(ContainElement(HaveField("Rule", tt.rule)))
			}
		})
	}
}

func TestHistoricalPlanContentException(t *testing.T) {
	t.Parallel()
	body := strings.Replace(completePlanBody, "**Preconditions:** A Ready HostedCluster with one worker.\n", "", 1)
	config := fmt.Sprintf("version: 1\nexceptions:\n  - path: plans/example.md\n    kind: legacy\n    source: https://github.com/example/source/blob/main/plan.md\n    reason: Preserve published plan pending author clarification\n    body_sha256: %s\n    gaps: [TC-001 has no preconditions]\n    rules: [PLAN_CONTENT]\n", artifactlint.BodySHA256([]byte(body)))
	prefix, _, _ := strings.Cut(body, "### TC-001")
	config += fmt.Sprintf("    findings:\n      - rule: PLAN_CONTENT\n        line: %d\n        message: test case must specify preconditions, or explain why none apply\n", strings.Count(prefix, "\n")+1)
	undefined := strings.Replace(body, "cluster | TC-001 |", "cluster | TC-999 |", 1)
	forbidden := strings.Replace(config, artifactlint.BodySHA256([]byte(body)), artifactlint.BodySHA256([]byte(undefined)), 1)
	for _, tt := range []struct {
		name      string
		body      string
		config    string
		wantError bool
	}{
		{"When a historical body has an explicit content-gap exception, it should preserve the source and warn", body, config, false},
		{"When an excepted body changes, it should require renewed review", body + "\nChanged strategy.\n", config, true},
		{"When a layout adaptation tries to waive missing content, it should reject the waiver", body, strings.Replace(config, "kind: legacy", "kind: adaptation", 1), true},
		{"When a legacy exception tries to waive an undefined mapped case, it should retain the relationship failure", undefined, strings.Replace(forbidden, "[PLAN_CONTENT]", "[PLAN_CONTENT, RELATIONSHIP]", 1), true},
	} {
		t.Run(tt.name, func(t *testing.T) {
			g := NewWithT(t)
			result, err := artifactlint.Validate(writeFiles(t, map[string]string{"plans/example.md": planMetadata + tt.body, ".artifactlint.yaml": tt.config}))
			g.Expect(err).NotTo(HaveOccurred())
			g.Expect(result.HasErrors()).To(Equal(tt.wantError), "%+v", result.Findings)
			if !tt.wantError {
				g.Expect(result.Findings).To(ConsistOf(And(HaveField("Rule", "EXCEPTION_APPLIED"), HaveField("Severity", artifactlint.SeverityWarning))))
			} else {
				g.Expect(result.Findings).To(ContainElement(HaveField("Rule", "EXCEPTION")))
				g.Expect(result.Findings).NotTo(ContainElement(HaveField("Rule", "EXCEPTION_APPLIED")))
				if tt.body == undefined {
					g.Expect(result.Findings).To(ContainElement(And(HaveField("Rule", "RELATIONSHIP"), HaveField("Message", "acceptance criterion references an undefined test case"))))
				}
			}
		})
	}
}

func TestHistoricalPlanApproval(t *testing.T) {
	t.Parallel()
	t.Run("When a historical draft becomes active, it should require approval despite an unchanged body and content exception", func(t *testing.T) {
		g := NewWithT(t)
		body := strings.Replace(completePlanBody, "| Reviewer | example-reviewer | 2026-10-21 |", "| Reviewer | | |", 1)
		config := fmt.Sprintf("version: 1\nexceptions:\n  - path: plans/example.md\n    kind: legacy\n    source: https://github.com/example/source/blob/main/plan.md\n    reason: Preserve draft approval state\n    body_sha256: %s\n    gaps: [Reviewer approval is pending]\n    rules: [PLAN_CONTENT]\n", artifactlint.BodySHA256([]byte(body)))
		prefix, _, _ := strings.Cut(body, "| Reviewer")
		config += fmt.Sprintf("    findings:\n      - rule: PLAN_CONTENT\n        line: %d\n        message: reviewer approval entry must identify the reviewer and a real calendar date; active plans cannot leave approval pending\n", strings.Count(prefix, "\n")+1)
		metadata := strings.Replace(planMetadata, "status: draft", "status: active", 1)
		result, err := artifactlint.Validate(writeFiles(t, map[string]string{"plans/example.md": metadata + body, ".artifactlint.yaml": config}))
		g.Expect(err).NotTo(HaveOccurred())
		g.Expect(result.Findings).To(ContainElement(And(HaveField("Rule", "PLAN_APPROVAL"), HaveField("Severity", artifactlint.SeverityError))))
		g.Expect(result.Findings).NotTo(ContainElement(HaveField("Rule", "EXCEPTION")))
	})
}

func TestCompletePlans(t *testing.T) {
	t.Parallel()
	manualProcedure := "**Steps:**\n| Step | Action | Expected Result |\n|---|---|---|\n| 1 | Scale the NodePool to two replicas | Two workers become Ready |"
	tests := []struct {
		name string
		body string
	}{
		{"When a draft specifies a complete case and pending reviewer, it should pass", strings.Replace(completePlanBody, "| Reviewer | example-reviewer | 2026-10-21 |", "| Reviewer | | |", 1)},
		{"When steps and expected results use labelled prose, it should accept the procedure", strings.Replace(completePlanBody, manualProcedure, "**Steps:**\n1. Scale the NodePool to two replicas.\n\n**Expected result:** Two workers become Ready.", 1)},
		{"When case fields use headings, it should accept the equivalent layout", strings.NewReplacer("**Objective:**", "#### Objective\n", "**Preconditions:**", "#### Prerequisites\n", "**Steps:**", "#### Procedure\n").Replace(completePlanBody)},
		{"When a case labels its objective as purpose and preconditions as setup, it should accept the equivalent fields", strings.NewReplacer("**Objective:**", "**Purpose:**", "**Preconditions:**", "**Setup:**").Replace(completePlanBody)},
		{"When an automated case has a test reference, run command and expected outcome, it should accept the procedure", strings.Replace(completePlanBody, manualProcedure, "**Primary method (automated):**\n- Test: `TestScaleNodePool` in `test/e2e/scale_test.go`\n- Run: `go test ./test/e2e -run TestScaleNodePool`\n\n**Expected result:** Two workers become Ready.", 1)},
		{"When automated execution uses separate test and command fields, it should accept the equivalent instructions", strings.Replace(completePlanBody, manualProcedure, "**Test:** `TestScaleNodePool` in `test/e2e/scale_test.go`\n\n#### Run\n`go test ./test/e2e -run TestScaleNodePool`\n\n#### Expected outcome\nTwo workers become Ready.", 1)},
		{"When an explicit run field contains a fenced command, it should retain the execution instructions", strings.Replace(completePlanBody, manualProcedure, "**Test:** `TestScaleNodePool` in `test/e2e/scale_test.go`\n\n**Run:**\n\n```sh\ngo test ./test/e2e -run TestScaleNodePool\n```\n\n**Expected result:** Two workers become Ready.", 1)},
		{"When an explicit expected-result field contains a fenced output, it should retain the expected outcome", strings.Replace(completePlanBody, manualProcedure, "**Steps:** Scale the NodePool to two replicas.\n\n**Expected result:**\n\n```text\nTwo workers become Ready\n```", 1)},
		{"When an automated case specifies a build and test selector, it should accept the execution instructions", strings.Replace(completePlanBody, manualProcedure, "**Primary method (automated):**\n- Test: `test/e2e/scale_test.go`\n- Build: `make e2ev2`\n- Select with the Ginkgo label filter `scale-nodepool`.\n\n**Expected result:** Two workers become Ready.", 1)},
		{"When prerequisites are explicitly inapplicable with a reason, it should accept the explanation", strings.Replace(completePlanBody, "A management cluster and the oc CLI", "Not applicable: unit tests use a fake client and need no cluster", 1)},
		{"When a real expected result contains the word TBD, it should not reject technical content", strings.Replace(completePlanBody, "Two workers become Ready", "The status message no longer contains the literal word TBD", 1)},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			g := NewWithT(t)
			result, err := artifactlint.Validate(writeFiles(t, map[string]string{"plans/example.md": planMetadata + tt.body}))
			g.Expect(err).NotTo(HaveOccurred())
			g.Expect(result.HasErrors()).To(BeFalse(), "%+v", result.Findings)
		})
	}
}

func TestAutomatedPlanInstructions(t *testing.T) {
	t.Parallel()
	for _, tt := range []struct{ name, method string }{
		{"When automation names a test but no run instruction, it should reject the incomplete execution method", "Test: TestScaleNodePool in test/e2e/scale_test.go"},
		{"When a build has no test selector, it should not mistake compilation for test execution", "Test: TestScaleNodePool\nBuild: make e2ev2"},
		{"When a run command is a placeholder, it should reject the incomplete execution method", "Test: TestScaleNodePool\nRun: TBD"},
		{"When automation only has a command and no test reference, it should request the test to execute", "Run: make test"},
	} {
		t.Run(tt.name, func(t *testing.T) {
			g := NewWithT(t)
			start := strings.Index(completePlanBody, "**Steps:**")
			stop := strings.Index(completePlanBody, "## Risks")
			body := completePlanBody[:start] + "**Primary method (automated):**\n" + tt.method + "\n\n**Expected result:** Two workers become Ready.\n" + completePlanBody[stop:]
			result, err := artifactlint.Validate(writeFiles(t, map[string]string{"plans/example.md": planMetadata + body}))
			g.Expect(err).NotTo(HaveOccurred())
			g.Expect(result.Findings).To(ContainElement(HaveField("Rule", "PLAN_CONTENT")))
		})
	}
}

func TestPlanApprovalState(t *testing.T) {
	t.Parallel()
	for _, tt := range []struct {
		name      string
		row       string
		wantError bool
	}{
		{"When an active plan has no reviewer, it should reject the missing approval", "| Reviewer | | |", true},
		{"When an active plan has a reviewer but no approval date, it should reject the incomplete approval", "| Reviewer | example-reviewer | |", true},
		{"When an active plan has an impossible approval date, it should reject the date", "| Reviewer | example-reviewer | 2026-02-30 |", true},
		{"When an active plan has a named reviewer and calendar date, it should accept the approval record", "| Reviewer | example-reviewer | 2026-10-21 |", false},
	} {
		t.Run(tt.name, func(t *testing.T) {
			g := NewWithT(t)
			report := strings.Replace(planMetadata, "status: draft", "status: active", 1) + strings.Replace(completePlanBody, "| Reviewer | example-reviewer | 2026-10-21 |", tt.row, 1)
			result, err := artifactlint.Validate(writeFiles(t, map[string]string{"plans/example.md": report}))
			g.Expect(err).NotTo(HaveOccurred())
			g.Expect(result.HasErrors()).To(Equal(tt.wantError), "%+v", result.Findings)
		})
	}
}

func TestPlanCaseRegions(t *testing.T) {
	t.Parallel()
	laterCase := "### TC-002: Remove a worker\n**Objective:** Verify worker removal.\n**Preconditions:** A cluster with two workers.\n**Steps:** Scale to one worker.\n**Expected result:** One worker remains.\n"
	for _, tt := range []struct {
		name    string
		body    string
		message string
	}{
		{"When approach prose precedes same-level test cases, it should validate the cases", strings.Replace(completePlanBody, "## Test Cases", "## Test Approach\nUse an isolated test cluster.\n## Test Cases", 1), ""},
		{"When an empty approach precedes complete test cases, it should accept the populated region", strings.Replace(completePlanBody, "## Test Cases", "## Test Approach\n## Test Cases", 1), ""},
		{"When cases are directly under test approach, it should accept the alias", strings.Replace(completePlanBody, "## Test Cases", "## Test Approach", 1), ""},
		{"When cases are in multiple same-level regions, it should validate all regions", strings.Replace(completePlanBody, "## Risks", "## Test Design\n"+laterCase+"## Risks", 1), ""},
		{"When a later case region contains an incomplete case, it should report the missing setup", strings.Replace(completePlanBody, "## Risks", "## Test Design\n"+strings.Replace(laterCase, "**Preconditions:** A cluster with two workers.\n", "", 1)+"## Risks", 1), "test case must specify preconditions, or explain why none apply"},
		{"When a nested case region follows another case, it should validate the later case", strings.Replace(completePlanBody, "## Risks", "### Test Design\n"+strings.ReplaceAll(strings.Replace(laterCase, "**Preconditions:** A cluster with two workers.\n", "", 1), "### TC", "#### TC")+"## Risks", 1), "test case must specify preconditions, or explain why none apply"},
	} {
		t.Run(tt.name, func(t *testing.T) {
			g := NewWithT(t)
			result, err := artifactlint.Validate(writeFiles(t, map[string]string{"plans/example.md": planMetadata + tt.body}))
			g.Expect(err).NotTo(HaveOccurred())
			if tt.message == "" {
				g.Expect(result.HasErrors()).To(BeFalse(), "%+v", result.Findings)
			} else {
				prefix, _, _ := strings.Cut(planMetadata+tt.body, "### TC-002")
				if strings.Contains(tt.body, "#### TC-002") {
					prefix, _, _ = strings.Cut(planMetadata+tt.body, "#### TC-002")
				}
				g.Expect(result.Findings).To(ContainElement(And(HaveField("Rule", "PLAN_CONTENT"), HaveField("Message", tt.message), HaveField("Line", strings.Count(prefix, "\n")+1))))
			}
		})
	}
}

func TestPlanProcedureHeaders(t *testing.T) {
	t.Parallel()
	for _, action := range []string{"Action", "Actions", "Procedure", "Step Description", "Description"} {
		for _, step := range []bool{false, true} {
			for _, complete := range []bool{false, true} {
				t.Run(fmt.Sprintf("When a procedure uses %s with step=%t and complete=%t, it should validate every row", action, step, complete), func(t *testing.T) {
					g := NewWithT(t)
					table := "| " + action + " | Expected Result |\n|---|---|\n| Scale to two replicas | Two workers become Ready |\n| Scale to three replicas | "
					if complete {
						table += "Three workers become Ready"
					}
					table += " |"
					if step {
						table = strings.NewReplacer("| "+action, "| Step | "+action, "|---|---|", "|---|---|---|", "| Scale", "| 1 | Scale").Replace(table)
					}
					start := strings.Index(completePlanBody, "| Step | Action")
					stop := strings.Index(completePlanBody, "## Risks")
					body := completePlanBody[:start] + table + "\n" + completePlanBody[stop:]
					result, err := artifactlint.Validate(writeFiles(t, map[string]string{"plans/example.md": planMetadata + body}))
					g.Expect(err).NotTo(HaveOccurred())
					if complete {
						g.Expect(result.HasErrors()).To(BeFalse(), "%+v", result.Findings)
					} else {
						g.Expect(result.Findings).To(ContainElement(And(HaveField("Rule", "PLAN_CONTENT"), HaveField("Message", "test case must include actions and expected results for every step, or an automated test reference, run command, and expected outcome"))))
					}
				})
			}
		}
	}
	t.Run("When an unrelated metadata table has a description column, it should retain a valid procedure", func(t *testing.T) {
		g := NewWithT(t)
		body := strings.Replace(completePlanBody, "**Steps:**", "| Property | Description |\n|---|---|\n| Target | HostedCluster |\n\n**Steps:**", 1)
		result, err := artifactlint.Validate(writeFiles(t, map[string]string{"plans/example.md": planMetadata + body}))
		g.Expect(err).NotTo(HaveOccurred())
		g.Expect(result.HasErrors()).To(BeFalse(), "%+v", result.Findings)
	})
}

func TestSeparateBuildInstructions(t *testing.T) {
	t.Parallel()
	for _, tt := range []struct {
		name      string
		field     string
		command   string
		selection string
		valid     bool
	}{
		{"When a Run field only builds, it should require test selection", "Run", "make build", "", false},
		{"When a Command field only builds Go code, it should require test selection", "Command", "go build ./test/e2e", "", false},
		{"When a Run field builds the test binary, it should require test selection", "Run", "make e2ev2", "", false},
		{"When a Run field builds with an explicit selector, it should accept the instructions", "Run", "make build", "\n- Select with the Ginkgo label filter `scale-nodepool`.", true},
		{"When an Execute field runs tests, it should accept execution without a build selector", "Execute", "go test ./test/e2e -run TestScaleNodePool", "", true},
		{"When a Build field uses a custom builder without selection, it should require test selection", "Build", "./compile-tests.sh", "", false},
		{"When a Run field compiles a Go test binary, it should require test selection", "Run", "go test -c ./test/e2e", "", false},
	} {
		t.Run(tt.name, func(t *testing.T) {
			g := NewWithT(t)
			start := strings.Index(completePlanBody, "**Steps:**")
			stop := strings.Index(completePlanBody, "## Risks")
			body := completePlanBody[:start] + "**Test file:** test/e2e/scale_test.go\n\n**" + tt.field + ":** " + tt.command + tt.selection + "\n\n**Expected result:** Two workers become Ready.\n" + completePlanBody[stop:]
			result, err := artifactlint.Validate(writeFiles(t, map[string]string{"plans/example.md": planMetadata + body}))
			g.Expect(err).NotTo(HaveOccurred())
			if tt.valid {
				g.Expect(result.HasErrors()).To(BeFalse(), "%+v", result.Findings)
			} else {
				g.Expect(result.Findings).To(ContainElement(And(HaveField("Rule", "PLAN_CONTENT"), HaveField("Message", "test case must include actions and expected results for every step, or an automated test reference, run command, and expected outcome"))))
			}
		})
	}
}

func TestPlanAdaptationContentBoundary(t *testing.T) {
	t.Parallel()
	start := strings.Index(completePlanBody, "## Test Environment")
	stop := strings.Index(completePlanBody, "## Test Cases")
	for _, tt := range []struct {
		name  string
		body  string
		kind  string
		valid bool
	}{
		{"When an adaptation omits a required area, it should retain the missing-content error", completePlanBody[:start] + completePlanBody[stop:], "adaptation", false},
		{"When an adaptation empties a required area, it should retain the missing-content error", completePlanBody[:start] + "## Test Environment\n" + completePlanBody[stop:], "adaptation", false},
		{"When a reviewed legacy exception preserves a missing area, it should warn", completePlanBody[:start] + completePlanBody[stop:], "legacy", true},
		{"When an adaptation uses a supported combined heading, it should accept the content", strings.Replace(completePlanBody, "## Test Environment", "## Test Environment and Prerequisites", 1), "adaptation", true},
	} {
		t.Run(tt.name, func(t *testing.T) {
			g := NewWithT(t)
			config := fmt.Sprintf("version: 1\nexceptions:\n  - path: plans/example.md\n    kind: %s\n    source: https://github.com/example/source/blob/main/plan.md\n    reason: Reviewed layout\n    body_sha256: %s\n    gaps: [Environment layout]\n    rules: [STRUCTURE]\n", tt.kind, artifactlint.BodySHA256([]byte(tt.body)))
			result, err := artifactlint.Validate(writeFiles(t, map[string]string{"plans/example.md": planMetadata + tt.body, ".artifactlint.yaml": config}))
			g.Expect(err).NotTo(HaveOccurred())
			if tt.valid {
				g.Expect(result.HasErrors()).To(BeFalse(), "%+v", result.Findings)
			} else {
				g.Expect(result.Findings).To(ContainElement(And(HaveField("Rule", "STRUCTURE"), HaveField("Message", "include a nonempty environment section using supported headings"))))
				g.Expect(result.Findings).To(ContainElement(HaveField("Rule", "EXCEPTION")))
				g.Expect(result.Findings).NotTo(ContainElement(HaveField("Rule", "EXCEPTION_APPLIED")))
			}
		})
	}
}

func TestReviewedPlanLayouts(t *testing.T) {
	t.Parallel()
	for _, tt := range []struct{ name, body, message string }{
		{"When a quoted environment heading precedes the real section, it should use the document section", strings.Replace(completePlanBody, "## Test Environment", "> ## Test Environment\n> Example only.\n\n## Test Environment", 1), ""},
		{"When a list contains an environment heading, it should ignore the nested heading", strings.Replace(completePlanBody, "## Test Environment", "- ## Test Environment\n  Example only.\n\n## Test Environment", 1), ""},
		{"When a link targets a quoted heading, it should preserve that anchor", strings.Replace(completePlanBody, "## Test Environment", "> ## Quoted example\n\n[Quoted anchor](#quoted-example)\n\n## Test Environment", 1), ""},
		{"When a case definition appears only in a quote, it should not define the case", strings.Replace(completePlanBody, "### TC-001: Scale a NodePool", "> ### TC-001: Example case\n\n### Scale coverage", 1), "define at least one test case under a heading with a unique TC-<number> identifier"},
		{"When an objective describes Todo items, it should accept substantive text", strings.Replace(completePlanBody, "Verify that the requested worker joins.", "Todo items persist after restart", 1), ""},
		{"When an objective starts with an unresolved TBD instruction, it should remain incomplete", strings.Replace(completePlanBody, "Verify that the requested worker joins.", "TBD after review", 1), "test case must specify a non-placeholder objective"},
		{"When an objective uses a TODO marker, it should reject the placeholder", strings.Replace(completePlanBody, "Verify that the requested worker joins.", "TODO: describe persistence", 1), "test case must specify a non-placeholder objective"},
		{"When categorized case IDs are defined and mapped, it should accept the identifiers", strings.ReplaceAll(completePlanBody, "TC-001", "TC-REG-001"), ""},
		{"When identifier fields use equivalent labels, it should accept the values", strings.NewReplacer("**ID:**", "**Identifier:**", "**Date:**", "**Updated:**").Replace(completePlanBody), ""},
	} {
		t.Run(tt.name, func(t *testing.T) {
			g := NewWithT(t)
			result, err := artifactlint.Validate(writeFiles(t, map[string]string{"plans/example.md": planMetadata + tt.body}))
			g.Expect(err).NotTo(HaveOccurred())
			if tt.message == "" {
				g.Expect(result.HasErrors()).To(BeFalse(), "%+v", result.Findings)
			} else {
				g.Expect(result.Findings).To(ContainElement(HaveField("Message", tt.message)))
			}
		})
	}
	t.Run("When setext objectives contain only TBD, it should exclude the underline from content", func(t *testing.T) {
		g := NewWithT(t)
		body := strings.ReplaceAll(strings.TrimPrefix(completePlanBody, "\n# Example\n"), "## ", "# ")
		body = strings.Replace(body, "# Introduction and Objectives", "Introduction and Objectives\n===========================", 1)
		body = strings.Replace(body, "Verify that scaling creates the requested number of workers.", "TBD", 1)
		result, err := artifactlint.Validate(writeFiles(t, map[string]string{"plans/example.md": planMetadata + body}))
		g.Expect(err).NotTo(HaveOccurred())
		g.Expect(result.Findings).To(ContainElement(And(HaveField("Rule", "PLAN_CONTENT"), HaveField("Message", "describe the plan's purpose and objectives with non-placeholder content"))))
	})
	t.Run("When a duplicate case hides incomplete setup, it should report both errors", func(t *testing.T) {
		g := NewWithT(t)
		body := strings.Replace(completePlanBody, "**Preconditions:** A Ready HostedCluster with one worker.\n", "", 1)
		body = strings.Replace(body, "## Risks", "### TC-001: Duplicate\n**Objective:** Verify cleanup.\n**Preconditions:** A test cluster.\n**Steps:** Delete the NodePool.\n**Expected result:** All workers are removed.\n## Risks", 1)
		result, err := artifactlint.Validate(writeFiles(t, map[string]string{"plans/example.md": planMetadata + body}))
		g.Expect(err).NotTo(HaveOccurred())
		g.Expect(result.Findings).To(ContainElement(HaveField("Rule", "IDENTITY")))
		prefix, _, _ := strings.Cut(planMetadata+body, "### TC-001: Scale")
		g.Expect(result.Findings).To(ContainElement(And(HaveField("Rule", "PLAN_CONTENT"), HaveField("Message", "test case must specify preconditions, or explain why none apply"), HaveField("Line", strings.Count(prefix, "\n")+1))))
	})
}

func TestUnpunctuatedAuthoringInstructions(t *testing.T) {
	t.Parallel()
	for _, tt := range []struct{ name, original, replacement, message string }{
		{"When an objective is an unpunctuated TODO instruction, it should require its actual purpose", "Verify that the requested worker joins.", "TODO describe persistence", "test case must specify a non-placeholder objective"},
		{"When setup is an unpunctuated TODO instruction, it should require the starting state", "A Ready HostedCluster with one worker.", "TODO document required setup", "test case must specify preconditions, or explain why none apply"},
	} {
		t.Run(tt.name, func(t *testing.T) {
			g := NewWithT(t)
			body := strings.Replace(completePlanBody, tt.original, tt.replacement, 1)
			result, err := artifactlint.Validate(writeFiles(t, map[string]string{"plans/example.md": planMetadata + body}))
			g.Expect(err).NotTo(HaveOccurred())
			g.Expect(result.Findings).To(ContainElement(And(HaveField("Rule", "PLAN_CONTENT"), HaveField("Message", tt.message))))
		})
	}
}

func TestSeparateAcceptanceMapping(t *testing.T) {
	t.Parallel()
	mapping := "### Acceptance Criteria Mapping\n| Acceptance Criterion | Test Case |\n|---|---|\n| AC-1: The requested worker joins the cluster | TC-001 |\n"
	body := strings.Replace(completePlanBody, mapping, "", 1)
	body = strings.Replace(body, "## Risks", "## Coverage and requirement mapping\n| Requirement | Evidence to retain |\n|---|---|\n| AC-1: The requested worker joins | TC-001 |\n\n## Risks", 1)
	for _, tt := range []struct {
		name   string
		body   string
		waived bool
		valid  bool
	}{
		{"When acceptance mappings have a separate section, it should validate the mapping", body, false, true},
		{"When a separate mapping references an undefined case, it should report the reference", strings.Replace(body, "joins | TC-001 |", "joins | TC-999 |", 1), false, false},
		{"When a legacy content waiver covers a separate mapping, it should retain undefined-case errors", strings.Replace(strings.Replace(body, "joins | TC-001 |", "joins | TC-999 |", 1), "**Preconditions:** A Ready HostedCluster with one worker.\n", "", 1), true, false},
	} {
		t.Run(tt.name, func(t *testing.T) {
			g := NewWithT(t)
			files := map[string]string{"plans/example.md": planMetadata + tt.body}
			if tt.waived {
				prefix, _, _ := strings.Cut(tt.body, "### TC-001")
				files[".artifactlint.yaml"] = fmt.Sprintf("version: 1\nexceptions:\n  - path: plans/example.md\n    kind: legacy\n    source: https://github.com/example/source/blob/main/plan.md\n    reason: Preserve published setup gap\n    body_sha256: %s\n    gaps: [TC-001 preconditions are missing]\n    rules: [PLAN_CONTENT]\n    findings:\n      - rule: PLAN_CONTENT\n        line: %d\n        message: test case must specify preconditions, or explain why none apply\n", artifactlint.BodySHA256([]byte(tt.body)), strings.Count(prefix, "\n")+1)
			}
			result, err := artifactlint.Validate(writeFiles(t, files))
			g.Expect(err).NotTo(HaveOccurred())
			if tt.waived {
				g.Expect(result.Findings).To(ConsistOf(
					HaveField("Rule", "EXCEPTION_APPLIED"),
					And(HaveField("Rule", "RELATIONSHIP"), HaveField("Message", "acceptance criterion references an undefined test case")),
				))
			}
			if tt.valid {
				g.Expect(result.HasErrors()).To(BeFalse(), "%+v", result.Findings)
			} else {
				prefix, _, _ := strings.Cut(planMetadata+tt.body, "| AC-1: The requested worker joins |")
				g.Expect(result.Findings).To(ContainElement(And(HaveField("Rule", "RELATIONSHIP"), HaveField("Message", "acceptance criterion references an undefined test case"), HaveField("Line", strings.Count(prefix, "\n")+1))))
			}
		})
	}
}

func TestEmptyPlanTableLocations(t *testing.T) {
	t.Parallel()
	for _, tt := range []struct{ name, before, target, message string }{
		{"When a risk row has no text, it should identify the empty row", "## Approvals", "| | |", "each risk must have a non-placeholder description and mitigation"},
		{"When an acceptance row has no text, it should identify the empty row", "## Test Items", "| | |", "each acceptance criterion must have a description and map to at least one defined test case"},
	} {
		t.Run(tt.name, func(t *testing.T) {
			g := NewWithT(t)
			body := strings.Replace(completePlanBody, tt.before, tt.target+"\n"+tt.before, 1)
			prefix, _, _ := strings.Cut(planMetadata+body, tt.target)
			result, err := artifactlint.Validate(writeFiles(t, map[string]string{"plans/example.md": planMetadata + body}))
			g.Expect(err).NotTo(HaveOccurred())
			g.Expect(result.Findings).To(ContainElement(And(HaveField("Rule", "PLAN_CONTENT"), HaveField("Message", tt.message), HaveField("Line", strings.Count(prefix, "\n")+1))))
		})
	}
}

func TestContentExceptionFindings(t *testing.T) {
	t.Parallel()
	body := strings.Replace(completePlanBody, "**Preconditions:** A Ready HostedCluster with one worker.\n", "", 1)
	body = strings.Replace(body, "**Objective:** Verify that the requested worker joins.\n", "", 1)
	prefix, _, _ := strings.Cut(body, "### TC-001")
	config := fmt.Sprintf("version: 1\nexceptions:\n  - path: plans/example.md\n    kind: legacy\n    source: https://github.com/example/source/blob/main/plan.md\n    reason: Preserve reviewed setup gap\n    body_sha256: %s\n    gaps: [TC-001 preconditions are missing]\n    rules: [PLAN_CONTENT]\n", artifactlint.BodySHA256([]byte(body)))
	t.Run("When a content exception lists one reviewed finding, it should retain other content errors", func(t *testing.T) {
		g := NewWithT(t)
		pin := fmt.Sprintf("    findings:\n      - rule: PLAN_CONTENT\n        line: %d\n        message: test case must specify preconditions, or explain why none apply\n", strings.Count(prefix, "\n")+1)
		result, err := artifactlint.Validate(writeFiles(t, map[string]string{"plans/example.md": planMetadata + body, ".artifactlint.yaml": config + pin}))
		g.Expect(err).NotTo(HaveOccurred())
		g.Expect(result.Findings).To(ContainElement(And(HaveField("Rule", "PLAN_CONTENT"), HaveField("Message", "test case must specify a non-placeholder objective"))))
		g.Expect(result.Findings).NotTo(ContainElement(HaveField("Message", "test case must specify preconditions, or explain why none apply")))
	})
	t.Run("When metadata adds a line under a content-only waiver, it should retain the exact body finding", func(t *testing.T) {
		g := NewWithT(t)
		pin := fmt.Sprintf("    findings:\n      - rule: PLAN_CONTENT\n        line: %d\n        message: test case must specify preconditions, or explain why none apply\n", strings.Count(prefix, "\n")+1)
		metadata := strings.Replace(planMetadata, "title: Example plan", "title: Example plan\nversion: 2", 1)
		result, err := artifactlint.Validate(writeFiles(t, map[string]string{"plans/example.md": metadata + body, ".artifactlint.yaml": config + pin}))
		g.Expect(err).NotTo(HaveOccurred())
		g.Expect(result.Findings).To(ContainElement(HaveField("Message", "test case must specify a non-placeholder objective")))
		g.Expect(result.Findings).NotTo(ContainElement(HaveField("Message", "test case must specify preconditions, or explain why none apply")))
		g.Expect(result.Findings).NotTo(ContainElement(HaveField("Rule", "EXCEPTION")))
	})
	t.Run("When a content exception omits reviewed findings, it should reject the blanket waiver", func(t *testing.T) {
		g := NewWithT(t)
		result, err := artifactlint.Validate(writeFiles(t, map[string]string{"plans/example.md": planMetadata + body, ".artifactlint.yaml": config}))
		g.Expect(err).NotTo(HaveOccurred())
		g.Expect(result.Findings).To(ContainElement(HaveField("Rule", "EXCEPTION")))
		g.Expect(result.Findings).NotTo(ContainElement(HaveField("Rule", "EXCEPTION_APPLIED")))
	})
}

func TestAutomatedCaseMatrices(t *testing.T) {
	t.Parallel()
	for _, table := range []string{
		"| Input | Expected |\n|---|---|\n| Two replicas | Two workers |",
		"| Step | Assertion |\n|---|---|\n| 1 | Two workers are Ready |",
	} {
		t.Run("When an automated case has an input or assertion matrix, it should retain its execution method "+strings.Split(table, "\n")[0], func(t *testing.T) {
			g := NewWithT(t)
			start := strings.Index(completePlanBody, "**Steps:**")
			stop := strings.Index(completePlanBody, "## Risks")
			body := completePlanBody[:start] + "**Primary method (automated):**\n- Test: TestScaleNodePool in test/e2e/scale_test.go\n- Run: go test ./test/e2e -run TestScaleNodePool\n\n" + table + "\n\n**Expected result:** Two workers become Ready.\n" + completePlanBody[stop:]
			result, err := artifactlint.Validate(writeFiles(t, map[string]string{"plans/example.md": planMetadata + body}))
			g.Expect(err).NotTo(HaveOccurred())
			g.Expect(result.HasErrors()).To(BeFalse(), "%+v", result.Findings)
		})
	}
}

func TestMixedExceptionScopes(t *testing.T) {
	t.Parallel()
	t.Run("When metadata and content waivers share an entry, it should pin each to its reviewed scope", func(t *testing.T) {
		g := NewWithT(t)
		body := strings.Replace(completePlanBody, "**Preconditions:** A Ready HostedCluster with one worker.\n", "", 1)
		body = strings.Replace(body, "**Objective:** Verify that the requested worker joins.\n", "", 1)
		metadata := strings.Replace(planMetadata, "ieee_829: true\n", "", 1)
		file := metadata + body
		prefix, _, _ := strings.Cut(body, "### TC-001")
		config := fmt.Sprintf("version: 1\nexceptions:\n  - path: plans/example.md\n    kind: legacy\n    source: https://github.com/example/source/blob/main/plan.md\n    reason: Preserve reviewed metadata and setup gaps\n    body_sha256: %s\n    file_sha256: %x\n    gaps: [IEEE declaration and explicit preconditions are missing]\n    rules: [PROFILE, PLAN_CONTENT]\n    findings:\n      - rule: PLAN_CONTENT\n        line: %d\n        message: test case must specify preconditions, or explain why none apply\n", artifactlint.BodySHA256([]byte(file)), sha256.Sum256([]byte(file)), strings.Count(prefix, "\n")+1)
		unwaived, err := artifactlint.Validate(writeFiles(t, map[string]string{"plans/example.md": file}))
		g.Expect(err).NotTo(HaveOccurred())
		g.Expect(unwaived.Findings).To(ContainElement(And(HaveField("Rule", "PLAN_CONTENT"), HaveField("Message", "test case must specify preconditions, or explain why none apply"))))
		result, err := artifactlint.Validate(writeFiles(t, map[string]string{"plans/example.md": file, ".artifactlint.yaml": config}))
		g.Expect(err).NotTo(HaveOccurred())
		g.Expect(result.Findings).To(ConsistOf(
			HaveField("Rule", "EXCEPTION_APPLIED"),
			And(HaveField("Rule", "PLAN_CONTENT"), HaveField("Message", "test case must specify a non-placeholder objective")),
		))
	})
}

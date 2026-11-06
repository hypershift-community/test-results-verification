package artifactlint_test

import (
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
	t.Run("When a mitigation is missing, it should identify the incomplete risk row", func(t *testing.T) {
		g := NewWithT(t)
		plan := planMetadata + strings.Replace(completePlanBody, "Use an isolated test cluster", "", 1)
		prefix, _, found := strings.Cut(plan, "| Unrelated workloads")
		g.Expect(found).To(BeTrue())
		line := strings.Count(prefix, "\n") + 1
		result, err := artifactlint.Validate(writeFiles(t, map[string]string{"plans/example.md": plan}))
		g.Expect(err).NotTo(HaveOccurred())
		g.Expect(result.Findings).To(ConsistOf(And(
			HaveField("Path", "plans/example.md"), HaveField("Line", line),
			HaveField("Rule", "PLAN_CONTENT"), HaveField("Message", "each risk must have a non-placeholder description and mitigation"),
		)))
	})
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
		metadata := strings.Replace(planMetadata, "status: draft", "status: active", 1)
		result, err := artifactlint.Validate(writeFiles(t, map[string]string{"plans/example.md": metadata + body, ".artifactlint.yaml": config}))
		g.Expect(err).NotTo(HaveOccurred())
		g.Expect(result.Findings).To(ContainElement(And(HaveField("Rule", "PLAN_APPROVAL"), HaveField("Severity", artifactlint.SeverityError))))
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

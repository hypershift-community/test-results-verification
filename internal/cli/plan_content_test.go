package cli_test

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	. "github.com/onsi/gomega"

	"github.com/hypershift-community/test-results-verification/internal/artifactlint"
	"github.com/hypershift-community/test-results-verification/internal/cli"
)

func TestIncompletePlanCLI(t *testing.T) {
	t.Parallel()
	const plan = `---
id: TP-EXAMPLE-001
title: Incomplete plan
date: 2026-11-06
status: draft
ieee_829: true
---
## Test Plan Identifier
TBD
## Introduction and Objectives
TBD
## Test Items and References
TBD
## Test Environment
TBD
## Test Cases
TBD
## Risks and Mitigations
TBD
## Approvals
TBD
`
	for _, format := range []string{"text", "json", "github"} {
		t.Run("When a plan only declares IEEE sections, it should reject the missing content in "+format, func(t *testing.T) {
			g := NewWithT(t)
			root := t.TempDir()
			g.Expect(os.MkdirAll(filepath.Join(root, "plans"), 0o700)).To(Succeed())
			g.Expect(os.WriteFile(filepath.Join(root, "plans/example.md"), []byte(plan), 0o600)).To(Succeed())
			var out, stderr bytes.Buffer
			g.Expect(cli.Run([]string{"--root", root, "--format", format}, &out, &stderr)).To(Equal(1))
			g.Expect(stderr.String()).To(BeEmpty())
			prefix, _, found := strings.Cut(plan, "## Test Cases")
			g.Expect(found).To(BeTrue())
			line := strings.Count(prefix, "\n") + 1
			switch format {
			case "json":
				var result artifactlint.Result
				g.Expect(json.Unmarshal(out.Bytes(), &result)).To(Succeed())
				g.Expect(result.Findings).To(ContainElement(And(
					HaveField("Path", "plans/example.md"), HaveField("Line", line),
					HaveField("Rule", "PLAN_CONTENT"), HaveField("Severity", artifactlint.SeverityError),
				)))
			case "github":
				g.Expect(out.String()).To(ContainSubstring(fmt.Sprintf("::error file=plans/example.md,line=%d,title=PLAN_CONTENT::", line)))
			default:
				g.Expect(out.String()).To(ContainSubstring(fmt.Sprintf("plans/example.md:%d: error PLAN_CONTENT:", line)))
			}
		})
	}
}

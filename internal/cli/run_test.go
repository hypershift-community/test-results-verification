package cli_test

import (
	"bytes"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	. "github.com/onsi/gomega"

	"github.com/hypershift-community/test-results-verification/internal/cli"
)

func TestCLI(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name    string
		file    string
		content string
		args    []string
		code    int
	}{
		{"When the repository is valid, it should return success", "README.md", "# Repository", nil, 0},
		{"When navigation is broken, it should return a validation exit code", "README.md", "[missing](missing.md)", nil, 1},
		{"When an argument is unknown, it should return a usage exit code", "README.md", "# Repository", []string{"--unknown"}, 2},
		{"When GitHub output is selected, it should emit annotations", "README.md", "[missing](missing.md)", []string{"--format", "github"}, 1},
		{"When JSON output is selected, it should emit machine-readable diagnostics", "README.md", "[missing](missing.md)", []string{"--format", "json"}, 1},
		{"When a source value is sensitive, it should not echo the source", "evidence.log", "Authorization: Bearer " + strings.Repeat("sensitive", 8), nil, 1},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			g := NewWithT(t)
			root := t.TempDir()
			g.Expect(os.WriteFile(filepath.Join(root, tt.file), []byte(tt.content), 0o600)).To(Succeed())
			var out, errs bytes.Buffer
			code := cli.Run(append([]string{"--root", root}, tt.args...), &out, &errs)
			g.Expect(code).To(Equal(tt.code), out.String()+errs.String())
			g.Expect(out.String() + errs.String()).NotTo(ContainSubstring(strings.Repeat("sensitive", 8)))
			if len(tt.args) > 1 && tt.args[1] == "json" {
				var value struct {
					Findings []struct {
						Path     string
						Line     int
						Rule     string
						Severity string
						Message  string
					}
				}
				g.Expect(json.Unmarshal(out.Bytes(), &value)).To(Succeed())
				g.Expect(value.Findings).To(HaveLen(1))
				g.Expect(value.Findings[0].Path).To(Equal("README.md"))
				g.Expect(value.Findings[0].Line).To(Equal(1))
				g.Expect(value.Findings[0].Rule).To(Equal("LINK"))
				g.Expect(value.Findings[0].Severity).To(Equal("error"))
				g.Expect(value.Findings[0].Message).To(Equal("local link target is missing"))
			}
			if len(tt.args) > 1 && tt.args[1] == "github" {
				g.Expect(out.String()).To(ContainSubstring("::error file=README.md"))
			}
		})
	}
	t.Run("When the repository is missing, it should distinguish tool failure from invalid artifacts", func(t *testing.T) {
		g := NewWithT(t)
		var out, errs bytes.Buffer
		g.Expect(cli.Run([]string{"--root", filepath.Join(t.TempDir(), "missing")}, &out, &errs)).To(Equal(2))
	})
	t.Run("When a legacy hash is requested, it should hash only the normalized body", func(t *testing.T) {
		g := NewWithT(t)
		root := t.TempDir()
		g.Expect(os.WriteFile(filepath.Join(root, "plan.md"), []byte("---\r\ntitle: Example\r\n---\r\nhello\r\n"), 0o600)).To(Succeed())
		var out, errs bytes.Buffer
		g.Expect(cli.Run([]string{"--root", root, "--body-hash", "plan.md"}, &out, &errs)).To(Equal(0))
		g.Expect(strings.TrimSpace(out.String())).To(Equal("5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03"))
	})
	t.Run("When front matter ends at EOF, it should hash the empty body rather than metadata", func(t *testing.T) {
		g := NewWithT(t)
		root := t.TempDir()
		g.Expect(os.WriteFile(filepath.Join(root, "plan.md"), []byte("---\ntitle: Example\n---"), 0o600)).To(Succeed())
		var out, errs bytes.Buffer
		g.Expect(cli.Run([]string{"--root", root, "--body-hash", "plan.md"}, &out, &errs)).To(Equal(0))
		g.Expect(strings.TrimSpace(out.String())).To(Equal("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"))
	})
}

func TestScannerFailures(t *testing.T) {
	t.Run("When the required scanner is missing, it should fail closed without a network request", func(t *testing.T) {
		g := NewWithT(t)
		root := t.TempDir()
		t.Setenv("PATH", root)
		var out, errs bytes.Buffer
		g.Expect(cli.Run([]string{"--root", root, "--secrets"}, &out, &errs)).To(Equal(2))
		g.Expect(errs.String()).To(ContainSubstring("gitleaks"))
	})
	t.Run("When the scanner crashes, it should not mistake the failure for a clean scan", func(t *testing.T) {
		g := NewWithT(t)
		root := t.TempDir()
		tools := t.TempDir()
		script := "#!/bin/sh\nif [ \"$1\" = version ]; then echo 8.30.1; exit 0; fi\necho sensitive-scanner-output >&2\nexit 2\n"
		g.Expect(os.WriteFile(filepath.Join(tools, "gitleaks"), []byte(script), 0o700)).To(Succeed())
		t.Setenv("PATH", tools)
		var out, errs bytes.Buffer
		g.Expect(cli.Run([]string{"--root", root, "--secrets"}, &out, &errs)).To(Equal(2))
		g.Expect(out.String() + errs.String()).NotTo(ContainSubstring("sensitive-scanner-output"))
	})
	t.Run("When a scanner reports a secret, it should emit only location and remediation", func(t *testing.T) {
		g := NewWithT(t)
		root := t.TempDir()
		tools := t.TempDir()
		script := "#!/bin/sh\nif [ \"$1\" = version ]; then echo 8.30.1; exit 0; fi\nwhile [ \"$#\" -gt 0 ]; do if [ \"$1\" = --report-path ]; then shift; report=$1; fi; shift; done\nprintf '%s' '[{\"File\":\"evidence.log\",\"StartLine\":7,\"RuleID\":\"example\",\"Secret\":\"sensitive-scanner-value\"}]' > \"$report\"\nexit 3\n"
		g.Expect(os.WriteFile(filepath.Join(tools, "gitleaks"), []byte(script), 0o700)).To(Succeed())
		t.Setenv("PATH", tools)
		var out, errs bytes.Buffer
		g.Expect(cli.Run([]string{"--root", root, "--secrets"}, &out, &errs)).To(Equal(1))
		g.Expect(out.String()).To(ContainSubstring("evidence.log:7: error SECRET"))
		g.Expect(out.String() + errs.String()).NotTo(ContainSubstring("sensitive-scanner-value"))
	})
	t.Run("When the scanner version is wrong, it should refuse an unpinned result", func(t *testing.T) {
		g := NewWithT(t)
		root := t.TempDir()
		tools := t.TempDir()
		g.Expect(os.WriteFile(filepath.Join(tools, "gitleaks"), []byte("#!/bin/sh\necho 0.0.0\n"), 0o700)).To(Succeed())
		t.Setenv("PATH", tools)
		var out, errs bytes.Buffer
		g.Expect(cli.Run([]string{"--root", root, "--secrets"}, &out, &errs)).To(Equal(2))
		g.Expect(errs.String()).To(ContainSubstring("version must be"))
	})
}

func TestAnnotationEscaping(t *testing.T) {
	t.Parallel()
	t.Run("When a filename contains annotation delimiters, it should not inject a workflow command", func(t *testing.T) {
		g := NewWithT(t)
		root := t.TempDir()
		name := "note,one\n::notice::injected.md"
		g.Expect(os.WriteFile(filepath.Join(root, name), []byte("[missing](missing.md)"), 0o600)).To(Succeed())
		var out, errs bytes.Buffer
		g.Expect(cli.Run([]string{"--root", root, "--format", "github"}, &out, &errs)).To(Equal(1))
		g.Expect(out.String()).To(ContainSubstring("%2C"))
		g.Expect(out.String()).To(ContainSubstring("%0A"))
		g.Expect(out.String()).NotTo(ContainSubstring("\n::notice::"))
	})
}

type unwritableOutput struct{}

func (unwritableOutput) Write(_ []byte) (int, error) { return 0, errors.New("output unavailable") }

func TestOutputFailure(t *testing.T) {
	t.Parallel()
	t.Run("When help output cannot be written, it should return an I/O failure", func(t *testing.T) {
		g := NewWithT(t)
		var stderr bytes.Buffer
		g.Expect(cli.Run([]string{"--help"}, unwritableOutput{}, &stderr)).To(Equal(2))
	})
}

package cli

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/hypershift-community/test-results-verification/internal/artifactlint"
)

// GitleaksVersion is the pinned scanner release. A test keeps Makefile's
// GITLEAKS_VERSION in sync with it.
const GitleaksVersion = "8.30.1"

func scanSecrets(root string) ([]artifactlint.Finding, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	scanner, err := exec.LookPath("gitleaks")
	if err != nil {
		return nil, fmt.Errorf("gitleaks %s is required; install the pinned tool before running the full check", GitleaksVersion)
	}
	version, err := exec.CommandContext(ctx, scanner, "version").Output()
	if err != nil || strings.TrimSpace(string(version)) != GitleaksVersion {
		return nil, fmt.Errorf("gitleaks version must be %s", GitleaksVersion)
	}
	tmp, err := os.MkdirTemp("", "artifactlint-secrets-")
	if err != nil {
		return nil, errors.New("cannot prepare secret scanner")
	}
	defer func() { _ = os.RemoveAll(tmp) }()
	config := filepath.Join(tmp, "config.toml")
	report := filepath.Join(tmp, "report.json")
	configuration, err := scannerConfiguration()
	if err != nil {
		return nil, errors.New("cannot prepare pinned secret detector configuration")
	}
	if err := os.WriteFile(config, configuration, 0o600); err != nil {
		return nil, errors.New("cannot prepare secret scanner configuration")
	}
	abs, err := filepath.Abs(root)
	if err != nil {
		return nil, errors.New("cannot resolve secret scanner root")
	}
	cmd := exec.CommandContext(ctx, scanner, "dir", ".", "--config", config, "--gitleaks-ignore-path", tmp, "--ignore-gitleaks-allow", "--no-banner", "--no-color", "--redact=100", "--report-format", "json", "--report-path", report, "--exit-code", "3", "--log-level", "error", "--max-decode-depth", "2")
	cmd.Dir = abs
	// Scanner output can contain evidence. Only emit sanitized diagnostics parsed
	// from its redacted report, never its stdout, stderr, matches, or secrets.
	err = cmd.Run()
	if err == nil {
		return nil, nil
	}
	var exit *exec.ExitError
	if !errors.As(err, &exit) || exit.ExitCode() != 3 {
		return nil, errors.New("gitleaks scan failed or timed out; no clean security result is available")
	}
	data, err := os.ReadFile(report)
	if err != nil {
		return nil, errors.New("cannot read gitleaks report")
	}
	var matches []struct {
		File      string
		StartLine int
		RuleID    string
	}
	if json.Unmarshal(data, &matches) != nil || len(matches) == 0 {
		return nil, errors.New("gitleaks returned an invalid findings report")
	}
	findings := make([]artifactlint.Finding, 0, len(matches))
	for _, m := range matches {
		name := filepath.ToSlash(m.File)
		if filepath.IsAbs(m.File) {
			relative, relErr := filepath.Rel(abs, m.File)
			if relErr != nil {
				return nil, errors.New("invalid gitleaks finding path")
			}
			name = filepath.ToSlash(relative)
		}
		if name == ".." || strings.HasPrefix(name, "../") {
			return nil, errors.New("invalid gitleaks finding path")
		}
		line := m.StartLine
		if line < 1 {
			line = 1
		}
		findings = append(findings, artifactlint.Finding{Path: name, Line: line, Rule: "SECRET", Severity: artifactlint.SeverityError, Message: "possible secret detected by gitleaks; remove the value and rotate any real credential"})
	}
	return findings, nil
}

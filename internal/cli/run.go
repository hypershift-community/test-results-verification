// Package cli provides the command's argument, output, and exit-code contract.
package cli

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/hypershift-community/test-results-verification/internal/artifactlint"
)

// Run implements the command without terminating its caller. Exit codes are
// 0 (valid), 1 (invalid artifact), and 2 (usage, I/O, or scanner failure).
func Run(args []string, out, stderr io.Writer) int {
	flags := flag.NewFlagSet("verify-artifacts", flag.ContinueOnError)
	flags.SetOutput(io.Discard)
	root := flags.String("root", ".", "repository directory")
	format := flags.String("format", "text", "text, json, or github")
	secrets := flags.Bool("secrets", false, "also run the pinned gitleaks scanner")
	bodyHash := flags.String("body-hash", "", "print a Markdown body's SHA-256 for a reviewed exception")
	if err := flags.Parse(args); err != nil {
		if err == flag.ErrHelp {
			if _, writeErr := fmt.Fprintln(out, "Usage: verify-artifacts [--root DIR] [--format text|json|github] [--secrets] [--body-hash FILE]"); writeErr != nil {
				return 2
			}
			return 0
		}
		_, _ = fmt.Fprintln(stderr, "invalid arguments; use --help")
		return 2
	}
	if flags.NArg() != 0 || (*format != "text" && *format != "json" && *format != "github") {
		_, _ = fmt.Fprintln(stderr, "invalid arguments; use --help")
		return 2
	}
	if *bodyHash != "" {
		return printBodyHash(*root, *bodyHash, out, stderr)
	}
	result, err := artifactlint.Validate(*root)
	if err != nil {
		_, _ = fmt.Fprintln(stderr, "cannot validate repository; check the directory, file permissions, and file types")
		return 2
	}
	if *secrets {
		findings, scanErr := scanSecrets(*root)
		if scanErr != nil {
			_, _ = fmt.Fprintln(stderr, scanErr.Error())
			return 2
		}
		result.Findings = append(result.Findings, findings...)
	}
	result.Sort()
	if err := render(out, result, *format); err != nil {
		_, _ = fmt.Fprintln(stderr, "cannot write validation diagnostics")
		return 2
	}
	if result.HasErrors() {
		return 1
	}
	return 0
}

func render(out io.Writer, result artifactlint.Result, format string) error {
	if format == "json" {
		return json.NewEncoder(out).Encode(result)
	}
	for _, f := range result.Findings {
		var err error
		if format == "github" {
			errKind := artifactlint.SeverityError
			if f.Severity == artifactlint.SeverityWarning {
				errKind = artifactlint.SeverityWarning
			}
			_, err = fmt.Fprintf(out, "::%s file=%s,line=%d,title=%s::%s\n", errKind, annotation(f.Path, true), f.Line, f.Rule, annotation(f.Message, false))
		} else {
			_, err = fmt.Fprintf(out, "%s:%d: %s %s: %s\n", safeText(f.Path), f.Line, f.Severity, f.Rule, safeText(f.Message))
		}
		if err != nil {
			return err
		}
	}
	if format == "text" && !result.HasErrors() {
		_, err := fmt.Fprintln(out, "Artifact validation passed.")
		return err
	}
	return nil
}

func annotation(s string, property bool) string {
	s = strings.NewReplacer("%", "%25", "\r", "%0D", "\n", "%0A").Replace(s)
	if property {
		s = strings.NewReplacer(":", "%3A", ",", "%2C").Replace(s)
	}
	return s
}

func safeText(s string) string {
	return strings.NewReplacer("\r", "\\r", "\n", "\\n", "\x1b", "\\x1b").Replace(s)
}

func printBodyHash(root, name string, out, stderr io.Writer) int {
	abs, err := filepath.Abs(root)
	if err != nil {
		_, _ = fmt.Fprintln(stderr, "cannot resolve body-hash repository")
		return 2
	}
	abs, err = filepath.EvalSymlinks(abs)
	if err != nil {
		_, _ = fmt.Fprintln(stderr, "cannot resolve body-hash repository")
		return 2
	}
	file := filepath.Join(abs, name)
	resolved, err := filepath.EvalSymlinks(file)
	if err != nil {
		_, _ = fmt.Fprintln(stderr, "cannot read body-hash target")
		return 2
	}
	rel, err := filepath.Rel(abs, resolved)
	if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) || filepath.IsAbs(name) {
		_, _ = fmt.Fprintln(stderr, "body-hash target must stay inside the repository")
		return 2
	}
	info, err := os.Stat(resolved)
	if err != nil || !info.Mode().IsRegular() || info.Size() > artifactlint.MaxFileSize {
		_, _ = fmt.Fprintln(stderr, "body-hash target must be a regular file no larger than 32 MiB")
		return 2
	}
	data, err := os.ReadFile(resolved)
	if err != nil {
		_, _ = fmt.Fprintln(stderr, "cannot read body-hash target")
		return 2
	}
	_, err = fmt.Fprintln(out, artifactlint.BodySHA256(data))
	if err != nil {
		return 2
	}
	return 0
}

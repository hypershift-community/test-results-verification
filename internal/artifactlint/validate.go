// Package artifactlint validates repository artifacts without executing their content.
package artifactlint

import (
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"unicode/utf8"
)

// Severity distinguishes blocking diagnostics from advisory ones.
type Severity string

const (
	SeverityError   Severity = "error"
	SeverityWarning Severity = "warning"
)

// MaxFileSize is the largest file the validator and body-hash helper will read.
const MaxFileSize = 32 * 1024 * 1024

// Finding is a redacted, stable diagnostic. Messages never include source values.
type Finding struct {
	Path     string   `json:"path"`
	Line     int      `json:"line"`
	Rule     string   `json:"rule"`
	Severity Severity `json:"severity"`
	Message  string   `json:"message"`
}

// Result contains diagnostics in deterministic path/line/rule order.
type Result struct {
	Findings []Finding `json:"findings"`
}

// HasErrors reports whether validation found a blocking problem.
func (r Result) HasErrors() bool {
	for _, f := range r.Findings {
		if f.Severity == SeverityError {
			return true
		}
	}
	return false
}

// Sort keeps library and CLI diagnostics in the same deterministic order.
func (r *Result) Sort() {
	sort.SliceStable(r.Findings, func(i, j int) bool {
		a, b := r.Findings[i], r.Findings[j]
		if a.Path != b.Path {
			return a.Path < b.Path
		}
		if a.Line != b.Line {
			return a.Line < b.Line
		}
		if a.Rule != b.Rule {
			return a.Rule < b.Rule
		}
		return a.Message < b.Message
	})
}

type source struct {
	path string
	data []byte
}

type validator struct {
	root   string
	files  map[string]*source
	plans  map[string]*planRecord
	result Result
}

// Validate checks an entire repository, including references to unchanged files.
// Operational failures are returned separately from invalid artifact diagnostics.
func Validate(root string) (Result, error) {
	abs, err := filepath.Abs(root)
	if err != nil {
		return Result{}, fmt.Errorf("resolve repository: %w", err)
	}
	info, err := os.Stat(abs)
	if err != nil || !info.IsDir() {
		return Result{}, fmt.Errorf("repository must be an accessible directory")
	}
	v := &validator{root: abs, files: map[string]*source{}, plans: map[string]*planRecord{}, result: Result{Findings: []Finding{}}}
	// Wrapped errors carry OS path context only, never file contents.
	err = filepath.WalkDir(abs, func(p string, d fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return fmt.Errorf("read repository entry: %w", walkErr)
		}
		if d.IsDir() {
			if p == abs {
				return nil
			}
			if filepath.Dir(p) != abs {
				return nil
			}
			switch d.Name() {
			case ".git", ".work", "bin", "vendor":
				return filepath.SkipDir
			}
			return nil
		}
		rel, relErr := filepath.Rel(abs, p)
		if relErr != nil {
			return fmt.Errorf("resolve repository entry: %w", relErr)
		}
		rel = filepath.ToSlash(rel)
		if d.Type()&os.ModeSymlink != 0 {
			v.add(rel, 1, "PATH", "symbolic links are not supported; store the file inside the repository")
			return nil
		}
		info, statErr := d.Info()
		if statErr != nil {
			return fmt.Errorf("inspect repository file: %w", statErr)
		}
		if !info.Mode().IsRegular() {
			v.add(rel, 1, "PATH", "store regular files only; special files are not supported")
			return nil
		}
		if info.Size() > MaxFileSize {
			v.add(rel, 1, "SIZE", "file exceeds the 32 MiB validation limit; split or relocate it before linting")
			return nil
		}
		data, readErr := os.ReadFile(p)
		if readErr != nil {
			return fmt.Errorf("read repository file: %w", readErr)
		}
		v.files[rel] = &source{path: rel, data: data}
		if info.Size() > 5*1024*1024 {
			v.result.Findings = append(v.result.Findings, Finding{Path: rel, Line: 1, Rule: "SIZE", Severity: SeverityWarning, Message: "avoid assets larger than 5 MiB; review storage and retention"})
		}
		if !utf8.Valid(data) || bytesContainNUL(data) {
			if binaryArtifact(rel) {
				v.files[rel].data = nil
			} else {
				v.add(rel, 1, "ENCODING", "text artifacts must use valid UTF-8 without NUL bytes; sanitize or convert the file before submission")
			}
		}
		return nil
	})
	if err != nil {
		return Result{}, err
	}
	for _, name := range sortedKeys(v.files) {
		f := v.files[name]
		if !strings.HasPrefix(f.path, "plans/") || f.path == "plans/.gitkeep" {
			continue
		}
		if strings.EqualFold(filepath.Ext(f.path), ".md") {
			v.plan(f)
		} else {
			v.add(f.path, 1, "NAME", "production plans must be Markdown files directly under plans/")
		}
	}
	v.planReferences()
	v.reports()
	v.links()
	v.sanitization()
	v.exceptions()
	v.result.Sort()
	return v.result, nil
}

func binaryArtifact(name string) bool {
	switch strings.ToLower(filepath.Ext(name)) {
	case ".png", ".jpg", ".jpeg", ".gif", ".webp", ".ico", ".pdf", ".zip", ".gz", ".tgz", ".tar", ".woff", ".woff2", ".ttf", ".otf", ".mp4", ".mov", ".webm":
		return true
	}
	return false
}

func (v *validator) add(path string, line int, rule, message string) {
	v.result.Findings = append(v.result.Findings, Finding{
		Path: path, Line: line, Rule: rule, Severity: SeverityError, Message: message,
	})
}

func sortedKeys[V any](m map[string]V) []string {
	keys := make([]string, 0, len(m))
	for key := range m {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	return keys
}

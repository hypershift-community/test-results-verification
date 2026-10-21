package artifactlint

import (
	"crypto/sha256"
	"encoding/hex"
	"path"
	"strings"
)

// Rules a reviewed exception may waive, by the kind of artifact it pins.
var (
	markdownExceptionRules       = ruleSet([]string{"FRONTMATTER", "PROFILE", "STRUCTURE", "REPORT_BODY"}, planCoreFields, reportCoreFields)
	bundleMetadataExceptionRules = ruleSet(nil, bundleFields)
	bundleEntryExceptionRules    = ruleSet([]string{"BUNDLE"})
	adaptationRules              = ruleSet([]string{"STRUCTURE", "REPORT_BODY"})
)

func ruleSet(rules []string, missingFields ...[]string) map[string]bool {
	set := map[string]bool{}
	for _, rule := range rules {
		set[rule] = true
	}
	for _, fields := range missingFields {
		for _, field := range fields {
			set[missingRule(field)] = true
		}
	}
	return set
}

// exceptionScope returns the rules an exception for name may waive and the
// path whose findings it covers. Missing bundle metadata cannot be hashed, so
// that gap is pinned to the bundle's surviving index.html instead.
func exceptionScope(name string) (map[string]bool, string) {
	parts := strings.Split(name, "/")
	switch {
	case strings.HasSuffix(name, ".md") && (parts[0] == "plans" || parts[0] == "reports"):
		return markdownExceptionRules, name
	case len(parts) == 3 && parts[0] == "reports" && parts[2] == "metadata.yaml":
		return bundleMetadataExceptionRules, name
	case len(parts) == 3 && parts[0] == "reports" && parts[2] == "index.html":
		return bundleEntryExceptionRules, path.Dir(name) + "/metadata.yaml"
	}
	return nil, ""
}

// BodySHA256 fingerprints normalized artifact content, excluding any Markdown
// front matter. The CLI and reviewed-exception checks share this hash contract.
func BodySHA256(data []byte) string {
	_, body, _, _, _ := splitFrontMatter(data)
	digest := sha256.Sum256(body)
	return hex.EncodeToString(digest[:])
}

func (v *validator) exceptions() {
	f := v.files[".artifactlint.yaml"]
	if f == nil {
		return
	}
	m := v.parseMetadata(f, f.data, 0)
	if m == nil {
		return
	}
	version, ok := m.integer("version", true)
	if !ok || version != 1 {
		m.issue(m.get("version"), "EXCEPTION", "configuration version must be 1")
		return
	}
	seen := map[string]bool{}
	for _, n := range m.list("exceptions") {
		e := m.child(n)
		if e == nil {
			continue
		}
		name := e.text("path", true)
		kind := e.enum("kind", "legacy", "adaptation")
		reason := e.text("reason", true)
		sourceURL := canonicalURL(e.text("source", true))
		allowed, target := exceptionScope(name)
		file := v.files[name]
		if file == nil || seen[name] || allowed == nil || sourceURL == nil {
			e.issue(n, "EXCEPTION", "exceptions require a unique existing plan, report, or bundle artifact and a public HTTPS source URL")
			continue
		}
		seen[name] = true
		if target != name && v.files[target] != nil {
			e.issue(n, "EXCEPTION", "bundle metadata now exists; remove the missing-metadata exception")
			continue
		}
		if e.text("body_sha256", true) != BodySHA256(file.data) {
			e.issue(e.get("body_sha256"), "EXCEPTION", "artifact body changed; conform to the current policy or renew the reviewed exception")
			continue
		}
		valid := kind != "" && strings.TrimSpace(reason) != ""
		gaps := e.list("gaps")
		if len(gaps) == 0 {
			e.issue(n, "EXCEPTION", "list the remaining gaps the exception preserves")
			valid = false
		}
		for _, gap := range gaps {
			if gap.Tag != "!!str" || strings.TrimSpace(gap.Value) == "" {
				e.issue(gap, "EXCEPTION", "gaps must contain nonempty strings")
				valid = false
			}
		}
		rules := map[string]bool{}
		for _, rule := range e.list("rules") {
			if rule.Tag != "!!str" || !allowed[rule.Value] || rules[rule.Value] || (kind == "adaptation" && !adaptationRules[rule.Value]) {
				e.issue(rule, "EXCEPTION", "only specific legacy missing-field/profile/body rules or body adaptations can be excepted")
				valid = false
			}
			rules[rule.Value] = true
		}
		if !valid || len(rules) == 0 {
			e.issue(n, "EXCEPTION", "provide at least one permitted explicit rule")
			continue
		}
		kept := make([]Finding, 0, len(v.result.Findings))
		for _, finding := range v.result.Findings {
			if finding.Path != target || !rules[finding.Rule] {
				kept = append(kept, finding)
			}
		}
		v.result.Findings = kept
		v.result.Findings = append(v.result.Findings, Finding{Path: name, Line: 1, Rule: "EXCEPTION_APPLIED", Severity: SeverityWarning, Message: "reviewed body-pinned exception applies; see .artifactlint.yaml"})
	}
}

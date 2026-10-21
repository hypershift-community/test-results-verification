package artifactlint

import (
	"fmt"
	"path"
	"regexp"
	"strings"
)

var (
	prFilename       = regexp.MustCompile(`^[1-9][0-9]*\.md$`)
	scenarioFilename = regexp.MustCompile(`^scenario-[1-9][0-9]*\.html$`)
)

func (v *validator) reports() {
	directories := map[string]bool{}
	markdownReports := map[string][]string{}
	htmlMarkers := map[string]bool{}
	for _, name := range sortedKeys(v.files) {
		if !strings.HasPrefix(name, "reports/") || name == "reports/.gitkeep" {
			continue
		}
		parts := strings.Split(name, "/")
		if len(parts) < 3 {
			v.add(name, 1, "NAME", "store reports under reports/<lowercase-jira-key>/")
			continue
		}
		dir := strings.Join(parts[:2], "/")
		directories[dir] = true
		if name == dir+"/derived/report.md" {
			htmlMarkers[dir] = true
		}
		if strings.ToLower(parts[1]) != parts[1] || !jiraKey.MatchString(strings.ToUpper(parts[1])) {
			v.add(name, 1, "NAME", "report directories must use a lowercase Jira key")
		}
		if len(parts) == 3 && strings.HasSuffix(name, ".md") {
			markdownReports[dir] = append(markdownReports[dir], name)
		} else if len(parts) == 3 && (parts[2] == "metadata.yaml" || strings.EqualFold(path.Ext(name), ".html")) {
			htmlMarkers[dir] = true
		}
	}
	for _, dir := range sortedKeys(markdownReports) {
		for _, name := range markdownReports[dir] {
			base := path.Base(name)
			// Top-level notes such as README.md document an HTML bundle; only
			// PR-numbered files there are standalone reports.
			if htmlMarkers[dir] && !prFilename.MatchString(base) {
				continue
			}
			if !prFilename.MatchString(base) {
				v.add(name, 1, "NAME", "name Markdown reports with their positive PR number")
			}
			v.markdownReport(v.files[name], path.Base(dir))
		}
	}
	for _, dir := range sortedKeys(directories) {
		if htmlMarkers[dir] || len(markdownReports[dir]) == 0 {
			v.htmlReport(dir)
		}
	}
}

func (v *validator) reportMetadata(m *metadata, key, format string) {
	if actual := m.text("jira_key", true); actual != "" && (!jiraKey.MatchString(actual) || strings.ToLower(actual) != key) {
		m.issue(m.get("jira_key"), "RELATIONSHIP", "jira_key must match the report directory")
	}
	if actual := m.enum("format", "html-bundle", "markdown"); actual != "" && actual != format {
		m.issue(m.get("format"), "REPORT", "format must match the artifact's actual format")
	}
	m.date()
	m.enum("verdict", "pass", "fail", "conditional")
	if n := m.get("plan"); n != nil {
		if n.Tag != "!!str" {
			m.issue(n, "META", "plan must be a filename stem or an empty string")
		} else if n.Value != "" {
			p := v.plans[n.Value]
			if !stemName.MatchString(n.Value) || p == nil || p.template {
				m.issue(n, "RELATIONSHIP", "plan must reference an existing production plan filename stem")
			} else if len(p.issues) > 0 && !p.issues[strings.ToUpper(key)] {
				m.issue(n, "RELATIONSHIP", "report Jira issue must appear in the referenced plan's Jira relationships")
			}
		}
	}
	if n := m.get("pr"); n != nil {
		if child := m.child(n); child != nil {
			child.pullRequest()
		}
	}
	if n := m.get("tester"); n != nil && n.Tag != "!!str" {
		m.issue(n, "META", "tester must be a string")
	}
	for _, n := range m.list("tags") {
		if n.Tag != "!!str" || strings.TrimSpace(n.Value) == "" {
			m.issue(n, "META", "tags must contain nonempty strings")
		}
	}
}

func (v *validator) markdownReport(f *source, key string) {
	m, body, offset := v.frontMatter(f)
	v.markdownReportBody(f, body, offset)
	if m == nil {
		for _, field := range reportCoreFields {
			v.add(f.path, 1, missingRule(field), "include required report metadata or explicitly register the legacy gap")
		}
		return
	}
	v.reportMetadata(m, key, "markdown")
	n := m.get("pr")
	if n == nil {
		m.missing("pr")
	} else if child := m.child(n); child != nil {
		number, ok := child.integer("number", true)
		if ok && path.Base(f.path) != fmt.Sprintf("%d.md", number) {
			child.issue(n, "NAME", "Markdown report filename must match its PR number")
		}
	}
}

func (v *validator) markdownReportBody(f *source, body []byte, offset int) {
	_, headings := parseMarkdown(body)
	// The required verdict metadata already supplies the overall outcome.
	for _, area := range []string{"environment", "results", "evidence"} {
		found := false
		for _, h := range headings {
			if strings.Contains(strings.ToLower(h.name), area) {
				found = true
			}
		}
		if !found {
			v.add(f.path, offset+1, "REPORT_BODY", "include a "+area+" section")
		}
	}
	v.markdownReportCounts(f, body, offset)
}

func (v *validator) htmlReport(dir string) {
	if v.files[dir+"/index.html"] == nil {
		v.add(dir+"/index.html", 1, "BUNDLE", "HTML bundles must retain index.html as their authoritative entry point")
	}
	f := v.files[dir+"/metadata.yaml"]
	if f == nil {
		v.add(dir+"/metadata.yaml", 1, "BUNDLE", "HTML bundles must include metadata.yaml")
		return
	}
	m := v.parseMetadata(f, f.data, 0)
	if m == nil {
		return
	}
	v.reportMetadata(m, path.Base(dir), "html-bundle")
	scenarios, validScenarios := m.integer("scenario_count", true)
	passed, validPassed := m.integer("pass_count", true)
	count := 0
	for name := range v.files {
		if path.Dir(name) != dir {
			continue
		}
		base := path.Base(name)
		if scenarioFilename.MatchString(base) {
			count++
		} else if strings.HasPrefix(base, "scenario-") && strings.HasSuffix(base, ".html") {
			v.add(name, 1, "NAME", "scenario pages must be named scenario-<positive-integer>.html")
		}
	}
	if validScenarios && scenarios != count {
		m.issue(m.get("scenario_count"), "COUNTS", "scenario_count must equal the number of scenario-N.html pages, not test cases")
	}
	if validScenarios && validPassed && passed > scenarios {
		m.issue(m.get("pass_count"), "COUNTS", "pass_count cannot exceed scenario_count")
	}
	if m.boolean("ci_verified", true) && v.files[dir+"/automated-tests.html"] == nil {
		m.issue(m.get("ci_verified"), "REPORT", "ci_verified: true requires automated-tests.html evidence")
	}
	derived := m.boolean("has_derived_markdown", true)
	if derived != (v.files[dir+"/derived/report.md"] != nil) {
		m.issue(m.get("has_derived_markdown"), "REPORT", "has_derived_markdown must agree with derived/report.md presence")
	}
}

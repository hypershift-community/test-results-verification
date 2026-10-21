package artifactlint

import (
	"fmt"
	"net/url"
	"path"
	"regexp"
	"strings"

	"go.yaml.in/yaml/v3"
)

var (
	jiraKey  = regexp.MustCompile(`^[A-Z][A-Z0-9_]*-[0-9]+$`)
	repoName = regexp.MustCompile(`^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$`)
	stemName = regexp.MustCompile(`^[a-z0-9]+(-[a-z0-9]+)*$`)
)

type planRecord struct {
	meta        *metadata
	id          string
	issues      map[string]bool
	replacement string
	template    bool
}

func canonicalURL(raw string) *url.URL {
	u, err := url.Parse(raw)
	if err != nil || u.Scheme != "https" || u.Host == "" || u.User != nil || u.RawQuery != "" || u.Fragment != "" || u.Opaque != "" {
		return nil
	}
	return u
}

func (v *validator) planRelationships(m *metadata, id string) {
	stem := strings.TrimSuffix(path.Base(m.f.path), ".md")
	p := &planRecord{meta: m, id: id, issues: map[string]bool{}, template: strings.HasPrefix(stem, "_")}
	v.plans[stem] = p
	primaries := 0
	for _, n := range m.list("jira_issues") {
		child := m.child(n)
		if child == nil {
			continue
		}
		key := child.text("key", true)
		role := child.enum("role", "primary", "backport")
		u := canonicalURL(child.text("url", true))
		if !jiraKey.MatchString(key) || u == nil || (u.Host != "issues.redhat.com" && u.Host != "redhat.atlassian.net") || strings.TrimSuffix(u.Path, "/") != "/browse/"+key {
			child.issue(n, "RELATIONSHIP", "Jira key and HTTPS browse URL must identify the same issue")
		}
		if p.issues[key] {
			child.issue(n, "RELATIONSHIP", "list each Jira issue only once")
		}
		p.issues[key] = true
		if role == "primary" {
			primaries++
			if !p.template && stem != strings.ToLower(key) {
				child.issue(n, "NAME", "name the plan after its primary Jira issue")
			}
		}
	}
	if len(p.issues) > 0 && primaries != 1 {
		m.issue(m.get("jira_issues"), "RELATIONSHIP", "a nonempty Jira list must have exactly one primary issue")
	}
	seenPRs := map[string]bool{}
	for _, n := range m.list("pull_requests") {
		if child := m.child(n); child != nil {
			pr := child.pullRequest()
			child.enum("role", "implementation", "backport", "test")
			if seenPRs[pr] {
				child.issue(n, "RELATIONSHIP", "list each pull request only once")
			}
			seenPRs[pr] = true
		}
	}
	p.replacement = m.text("superseded_by", false)
	if n := m.get("status"); n != nil && n.Value == "superseded" && p.replacement == "" {
		m.issue(n, "RELATIONSHIP", "superseded plans must name a replacement with superseded_by")
	}
	m.text("version", false)
	for _, n := range m.list("tags") {
		if n.Kind != yaml.ScalarNode || n.Tag != "!!str" || strings.TrimSpace(n.Value) == "" {
			m.issue(n, "META", "tags must contain nonempty strings")
		}
	}
	if n := m.get("author"); n != nil && (n.Kind != yaml.ScalarNode || n.Tag != "!!str") {
		m.issue(n, "META", "author must be a string")
	}
}

func (m *metadata) pullRequest() string {
	repo := m.text("repo", true)
	number, ok := m.integer("number", true)
	u := canonicalURL(m.text("url", true))
	if !repoName.MatchString(repo) || !ok || number < 1 || u == nil || u.Host != "github.com" || strings.TrimSuffix(u.Path, "/") != fmt.Sprintf("/%s/pull/%d", repo, number) {
		m.issue(m.node, "RELATIONSHIP", "PR repo, positive number, and HTTPS GitHub URL must agree")
	}
	return fmt.Sprintf("%s#%d", repo, number)
}

func (v *validator) planReferences() {
	ids := map[string]string{}
	// Sort traversal so duplicate diagnostics are reproducible.
	for _, stem := range sortedKeys(v.plans) {
		p := v.plans[stem]
		if p.template || p.meta == nil {
			continue
		}
		if p.id != "" {
			if ids[p.id] != "" {
				p.meta.issue(p.meta.get("id"), "IDENTITY", "plan IDs must be unique across production plans")
			}
			ids[p.id] = stem
		}
		if p.replacement != "" {
			target := v.plans[p.replacement]
			if !stemName.MatchString(p.replacement) || target == nil || target.template || p.replacement == stem {
				p.meta.issue(p.meta.get("superseded_by"), "RELATIONSHIP", "replacement must reference another production plan filename stem")
			}
		}
		seen := map[string]bool{stem: true}
		for next := p.replacement; next != "" && v.plans[next] != nil; next = v.plans[next].replacement {
			if seen[next] {
				p.meta.issue(p.meta.get("superseded_by"), "RELATIONSHIP", "replacement relationships must not form a cycle")
				break
			}
			seen[next] = true
		}
	}
}

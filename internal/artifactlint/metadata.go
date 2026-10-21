package artifactlint

import (
	"bytes"
	"io"
	"path"
	"regexp"
	"strconv"
	"strings"
	"time"

	"go.yaml.in/yaml/v3"
)

var (
	slugName     = regexp.MustCompile(`^[a-z0-9]+(-[a-z0-9]+)*\.md$`)
	dateValue    = regexp.MustCompile(`^[0-9]{4}-[0-9]{2}-[0-9]{2}$`)
	integerValue = regexp.MustCompile(`^(0|[1-9][0-9]*)$`)
)

// Required core fields per artifact kind. Their absence is reported as
// missingRule(field) so reviewed legacy exceptions can name the gap.
var (
	planCoreFields   = []string{"id", "title", "date", "status"}
	reportCoreFields = []string{"jira_key", "format", "pr", "date", "verdict"}
	bundleFields     = []string{"jira_key", "format", "date", "verdict", "scenario_count", "pass_count", "ci_verified", "has_derived_markdown"}
)

func missingRule(field string) string { return "MISSING_" + strings.ToUpper(field) }

type metadata struct {
	v      *validator
	f      *source
	node   *yaml.Node
	offset int
}

// splitFrontMatter is the single definition of where a Markdown body starts,
// shared by validation and BodySHA256. Without a complete leading --- block,
// the whole normalized input is the body.
func splitFrontMatter(data []byte) (block, body []byte, offset int, opened, closed bool) {
	data = bytes.ReplaceAll(data, []byte("\r\n"), []byte("\n"))
	if !bytes.HasPrefix(data, []byte("---\n")) {
		return nil, data, 0, false, false
	}
	lines := bytes.Split(data, []byte("\n"))
	for i := 1; i < len(lines); i++ {
		if string(lines[i]) == "---" {
			return bytes.Join(lines[1:i], []byte("\n")), bytes.Join(lines[i+1:], []byte("\n")), i + 1, true, true
		}
	}
	return nil, data, 0, true, false
}

func (v *validator) frontMatter(f *source) (*metadata, []byte, int) {
	block, body, offset, opened, closed := splitFrontMatter(f.data)
	switch {
	case !opened:
		v.add(f.path, 1, "FRONTMATTER", "begin the artifact with a YAML front-matter block")
		return nil, body, offset
	case !closed:
		v.add(f.path, 1, "FRONTMATTER", "close the YAML front-matter block with ---")
		return nil, body, offset
	}
	return v.parseMetadata(f, block, 1), body, offset
}

func (v *validator) parseMetadata(f *source, data []byte, offset int) *metadata {
	decoder := yaml.NewDecoder(bytes.NewReader(data))
	var doc, extra yaml.Node
	if decoder.Decode(&doc) != nil || len(doc.Content) != 1 || doc.Content[0].Kind != yaml.MappingNode {
		v.add(f.path, offset+1, "YAML", "metadata must be one valid YAML mapping")
		return nil
	}
	if decoder.Decode(&extra) != io.EOF {
		v.add(f.path, offset+1, "YAML", "metadata must contain exactly one YAML document")
		return nil
	}
	if line := invalidYAML(doc.Content[0]); line != 0 {
		v.add(f.path, offset+line, "YAML", "use unique string keys without aliases, anchors, merges, or custom tags")
		return nil
	}
	return &metadata{v: v, f: f, node: doc.Content[0], offset: offset}
}

func invalidYAML(n *yaml.Node) int {
	if n.Kind == yaml.AliasNode || n.Anchor != "" || (!strings.HasPrefix(n.Tag, "!!") && n.Tag != "") {
		return n.Line
	}
	if n.Kind == yaml.MappingNode {
		seen := map[string]bool{}
		for i := 0; i < len(n.Content); i += 2 {
			key := n.Content[i]
			if key.Kind != yaml.ScalarNode || key.Tag != "!!str" || seen[key.Value] {
				return key.Line
			}
			seen[key.Value] = true
		}
	}
	for _, c := range n.Content {
		if line := invalidYAML(c); line != 0 {
			return line
		}
	}
	return 0
}

func (m *metadata) get(key string) *yaml.Node {
	for i := 0; i < len(m.node.Content); i += 2 {
		if m.node.Content[i].Value == key {
			return m.node.Content[i+1]
		}
	}
	return nil
}

func (m *metadata) issue(n *yaml.Node, rule, message string) {
	line := m.offset + 1
	if n != nil {
		line = m.offset + n.Line
	}
	m.v.add(m.f.path, line, rule, message)
}

func (m *metadata) missing(key string) {
	m.issue(nil, missingRule(key), "include the required "+key+" field")
}

func (m *metadata) text(key string, required bool) string {
	n := m.get(key)
	if n == nil {
		if required {
			m.missing(key)
		}
		return ""
	}
	if n.Kind != yaml.ScalarNode || n.Tag != "!!str" || strings.TrimSpace(n.Value) == "" {
		m.issue(n, "META", key+" must be a nonempty string")
		return ""
	}
	return n.Value
}

func (m *metadata) boolean(key string, required bool) bool {
	n := m.get(key)
	if n == nil {
		if required {
			m.missing(key)
		}
		return false
	}
	if n.Kind != yaml.ScalarNode || n.Tag != "!!bool" || (n.Value != "true" && n.Value != "false") {
		m.issue(n, "META", key+" must be a YAML boolean (true or false)")
		return false
	}
	return n.Value == "true"
}

func (m *metadata) date() {
	n := m.get("date")
	if n == nil {
		m.missing("date")
		return
	}
	if n.Kind != yaml.ScalarNode || (n.Tag != "!!str" && n.Tag != "!!timestamp") || !dateValue.MatchString(n.Value) {
		m.issue(n, "META", "date must be a calendar date in YYYY-MM-DD format")
		return
	}
	if _, err := time.Parse(time.DateOnly, n.Value); err != nil {
		m.issue(n, "META", "date must be a real calendar date")
	}
}

func (m *metadata) enum(key string, allowed ...string) string {
	value := m.text(key, true)
	if value == "" {
		return value
	}
	for _, a := range allowed {
		if value == a {
			return value
		}
	}
	m.issue(m.get(key), "META", key+" must be one of: "+strings.Join(allowed, ", "))
	return ""
}

func (m *metadata) list(key string) []*yaml.Node {
	n := m.get(key)
	if n == nil {
		return nil
	}
	if n.Kind != yaml.SequenceNode {
		m.issue(n, "META", key+" must be a list")
		return nil
	}
	return n.Content
}

func (m *metadata) child(n *yaml.Node) *metadata {
	if n.Kind != yaml.MappingNode {
		m.issue(n, "META", "relationship entries must be mappings")
		return nil
	}
	return &metadata{v: m.v, f: m.f, node: n, offset: m.offset}
}

func (m *metadata) integer(key string, required bool) (int, bool) {
	n := m.get(key)
	if n == nil {
		if required {
			m.missing(key)
		}
		return 0, false
	}
	if n.Kind != yaml.ScalarNode || n.Tag != "!!int" || !integerValue.MatchString(n.Value) {
		m.issue(n, "META", key+" must be a nonnegative decimal integer")
		return 0, false
	}
	number, err := strconv.Atoi(n.Value)
	if err != nil {
		m.issue(n, "META", key+" is outside the supported integer range")
		return 0, false
	}
	return number, true
}

func (v *validator) plan(f *source) {
	name := path.Base(f.path)
	template := strings.HasPrefix(name, "_")
	if path.Dir(f.path) != "plans" || (!template && !slugName.MatchString(name)) || path.Ext(name) != ".md" {
		v.add(f.path, 1, "NAME", "store one plan directly under plans/ using a lowercase hyphenated filename")
	}
	m, body, offset := v.frontMatter(f)
	if m == nil {
		stem := strings.TrimSuffix(name, ".md")
		v.plans[stem] = &planRecord{template: template, issues: map[string]bool{}}
		for _, field := range planCoreFields {
			v.add(f.path, 1, missingRule(field), "include required core metadata or register the legacy gap")
		}
		v.add(f.path, 1, "PROFILE", "new plans must declare ieee_829: true")
		v.planStructure(f, body, offset)
		return
	}
	id := m.text("id", true)
	m.text("title", true)
	m.date()
	m.enum("status", "draft", "active", "superseded", "archived")
	if !m.boolean("ieee_829", false) {
		m.issue(m.get("ieee_829"), "PROFILE", "new plans must declare ieee_829: true; register legacy exceptions explicitly")
	}
	v.planStructure(f, body, offset)
	v.planRelationships(m, id)
}

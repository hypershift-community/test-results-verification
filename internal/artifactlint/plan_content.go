package artifactlint

import (
	"regexp"
	"strings"
	"time"

	"github.com/yuin/goldmark/ast"
	tableast "github.com/yuin/goldmark/extension/ast"
)

var (
	caseIdentifier = regexp.MustCompile(`(?i)\bTC-[0-9]+\b`)
	caseDefinition = regexp.MustCompile(`(?i)^(?:test case\s+)?TC-[0-9]+\b`)
	contentLabel   = regexp.MustCompile(`^([A-Za-z][^:\n]{0,80}):\s*(.*)$`)
	unfinished     = regexp.MustCompile(`(?i)^(?:(?:tbd|todo)(?:\b.*)?|pending|review pending|to be (?:defined|determined|provided)|not specified|placeholder|n/?a|none|[-._?…—–]+|<[^>]+>)[.!]?$`)
	runInstruction = regexp.MustCompile(`(?im)^\s*(run(?: with)?|command|execute|build):\s*(.+)$`)
	selectTest     = regexp.MustCompile(`(?i)\bselect\b[^\n]*\b(?:filter|suite|test)\b`)
	testReference  = regexp.MustCompile(`(?:\bTest[A-Z][A-Za-z0-9_]*\b|[A-Za-z0-9_/-]+\.(?:go|ya?ml|sh|py)\b)`)
	inheritMethod  = regexp.MustCompile(`(?i)\b(?:same|inherit|see)\b`)
	wordCharacter  = regexp.MustCompile(`[\pL]`)
	areaConnectors = regexp.MustCompile(`\b(?:and|design|mitigations|contingencies|exit criteria)\b|[&/,]`)
	executionField = regexp.MustCompile(`^(?:steps?|procedure|actions?|run(?: with)?|command|execute|build|test(?: reference| file| suite)?|expected(?: results?| outcomes?)?|assertions?)$|(?:automated|automation|primary method)`)
)

type planField struct {
	name  string
	value string
}

type planRow struct {
	cells []string
	line  int
}

type planTable struct {
	header []string
	rows   []planRow
}

type planPart struct {
	heading heading
	data    []byte
	doc     ast.Node
	fields  []planField
	tables  []planTable
}

func meaningful(value string) bool {
	for _, line := range strings.Split(value, "\n") {
		line = strings.TrimSpace(line)
		if line != "" && !unfinished.MatchString(line) {
			return true
		}
	}
	return false
}

func label(value string) string {
	return strings.ToLower(strings.TrimSpace(sectionNumber.ReplaceAllString(strings.TrimSuffix(value, ":"), "")))
}

// Code blocks can document execution instructions, but cannot fill other fields.
func planText(node ast.Node, data []byte, includeCode bool) string {
	var out strings.Builder
	_ = ast.Walk(node, func(n ast.Node, entering bool) (ast.WalkStatus, error) {
		if !entering {
			if n.Kind() == ast.KindParagraph || n.Kind() == ast.KindTextBlock {
				out.WriteByte('\n')
			}
			return ast.WalkContinue, nil
		}
		switch typed := n.(type) {
		case *ast.Text:
			out.Write(typed.Segment.Value(data))
			if typed.SoftLineBreak() || typed.HardLineBreak() {
				out.WriteByte('\n')
			}
		case *ast.String:
			out.Write(typed.Value)
		case *ast.FencedCodeBlock:
			if includeCode {
				out.Write(typed.Lines().Value(data))
			}
			return ast.WalkSkipChildren, nil
		case *ast.CodeBlock:
			if includeCode {
				out.Write(typed.Lines().Value(data))
			}
			return ast.WalkSkipChildren, nil
		case *ast.HTMLBlock, *ast.RawHTML, *ast.Blockquote:
			return ast.WalkSkipChildren, nil
		}
		return ast.WalkContinue, nil
	})
	return strings.TrimSpace(out.String())
}

func readPlanPart(body []byte, h heading, headings []heading) planPart {
	stop := len(body)
	for _, next := range headings {
		if next.start > h.start && (next.level <= h.level || (caseDefinition.MatchString(label(h.name)) && caseDefinition.MatchString(label(next.name)))) {
			stop = next.start
			break
		}
	}
	p := planPart{heading: h, data: body[h.stop:stop]}
	p.doc, _ = parseMarkdown(p.data)
	current := -1
	for n := p.doc.FirstChild(); n != nil; n = n.NextSibling() {
		switch typed := n.(type) {
		case *ast.Heading:
			p.fields = append(p.fields, planField{name: label(nodeText(typed, p.data))})
			current = len(p.fields) - 1
		case *tableast.Table:
			table := planTable{}
			for row := typed.FirstChild(); row != nil; row = row.NextSibling() {
				var cells []string
				line := h.line
				for cell := row.FirstChild(); cell != nil; cell = cell.NextSibling() {
					cells = append(cells, planText(cell, p.data, false))
					_ = ast.Walk(cell, func(child ast.Node, entering bool) (ast.WalkStatus, error) {
						if text, ok := child.(*ast.Text); entering && ok {
							line = lineAt(body, h.stop) + lineAt(p.data, text.Segment.Start) - 1
							return ast.WalkStop, nil
						}
						return ast.WalkContinue, nil
					})
				}
				if row == typed.FirstChild() {
					table.header = cells
				} else {
					table.rows = append(table.rows, planRow{cells: cells, line: line})
					if len(cells) == 2 {
						p.fields = append(p.fields, planField{name: label(cells[0]), value: cells[1]})
					}
				}
			}
			p.tables = append(p.tables, table)
			current = -1
		case *ast.Paragraph:
			for _, line := range strings.Split(planText(n, p.data, false), "\n") {
				if match := contentLabel.FindStringSubmatch(line); match != nil {
					p.fields = append(p.fields, planField{name: label(match[1]), value: match[2]})
					current = len(p.fields) - 1
				} else if current >= 0 {
					p.fields[current].value += "\n" + line
				}
			}
		case *ast.List, *ast.FencedCodeBlock, *ast.CodeBlock:
			if current >= 0 {
				p.fields[current].value += "\n" + planText(n, p.data, executionField.MatchString(p.fields[current].name))
			}
		}
	}
	return p
}

func (p planPart) field(pattern string) string {
	match := regexp.MustCompile(pattern)
	for _, f := range p.fields {
		if match.MatchString(f.name) && meaningful(f.value) {
			return f.value
		}
	}
	return ""
}

func (t planTable) column(pattern string) int {
	match := regexp.MustCompile(pattern)
	for i, name := range t.header {
		if match.MatchString(label(name)) {
			return i
		}
	}
	return -1
}

func (r planRow) cell(column int) string {
	if column < 0 || column >= len(r.cells) {
		return ""
	}
	return r.cells[column]
}

func selectPlanParts(body []byte, headings []heading, title string) map[string]planPart {
	selected := map[string]heading{}
	caseLevel := 0
	for i, h := range headings {
		name := label(h.name)
		if i == 0 && h.level == 1 {
			remainder := name
			for _, definition := range planSections {
				remainder = definition.aliases.ReplaceAllString(remainder, " ")
			}
			if name == label(title) || strings.TrimSpace(areaConnectors.ReplaceAllString(remainder, "")) != "" {
				continue
			}
		}
		if caseLevel > 0 {
			if h.level > caseLevel {
				continue
			}
			caseLevel = 0
		}
		if caseDefinition.MatchString(name) {
			caseLevel = h.level
			continue
		}
		for _, definition := range planSections {
			if !definition.aliases.MatchString(name) {
				continue
			}
			if previous, ok := selected[definition.name]; !ok || h.level < previous.level {
				selected[definition.name] = h
			}
			if definition.name == "test cases" {
				caseLevel = h.level
			}
		}
	}
	parts := make(map[string]planPart, len(selected))
	for name, h := range selected {
		parts[name] = readPlanPart(body, h, headings)
	}
	return parts
}

func (v *validator) planContent(f *source, body []byte, headings []heading, parts map[string]planPart, offset int, status string) {
	issue := func(p planPart, message string) { v.add(f.path, offset+p.heading.line, "PLAN_CONTENT", message) }
	if p, ok := parts["identifier"]; ok {
		for _, field := range []string{"id", "version", "date"} {
			if p.field("^"+field+"$") == "" {
				issue(p, "plan identifier section must include a non-placeholder "+field)
			}
		}
		if date, _, _ := strings.Cut(p.field(`^date$`), "\n"); date != "" && !validCalendarDate(date) {
			issue(p, "plan identifier date must be a real calendar date in YYYY-MM-DD format")
		}
		if !strings.Contains(planText(p.doc, p.data, false), "829") {
			issue(p, "plan identifier section must reference IEEE 829")
		}
	}
	if p, ok := parts["objectives"]; ok {
		found := false
		for n := p.doc.FirstChild(); n != nil; n = n.NextSibling() {
			if h, ok := n.(*ast.Heading); ok && strings.Contains(label(nodeText(h, p.data)), "acceptance") {
				break
			}
			if n.Kind() == ast.KindParagraph || n.Kind() == ast.KindList {
				for _, line := range strings.Split(planText(n, p.data, false), "\n") {
					if match := contentLabel.FindStringSubmatch(line); match != nil {
						line = match[2]
					}
					found = found || meaningful(line)
				}
			}
		}
		if !found {
			issue(p, "describe the plan's purpose and objectives with non-placeholder content")
		}
	}
	if p, ok := parts["references"]; ok {
		found := false
		_ = ast.Walk(p.doc, func(n ast.Node, entering bool) (ast.WalkStatus, error) {
			if entering && (n.Kind() == ast.KindLink || n.Kind() == ast.KindAutoLink || (n.Kind() == ast.KindCodeSpan && strings.ContainsAny(planText(n, p.data, false), "/."))) {
				found = true
			}
			return ast.WalkContinue, nil
		})
		if !found {
			issue(p, "reference at least one implementation, test, code path, or document using a link or inline code path")
		}
	}
	if p, ok := parts["environment"]; ok {
		for _, requirement := range []struct{ name, pattern string }{
			{"cluster type or test target", `(?:cluster type|topology|test target|bare.metal simulation)`},
			{"platform or provider", `(?:platform|cloud provider)`},
			{"version or build", `(?:version|build|release image)`},
			{"prerequisites or tooling", `(?:prerequisites?|tooling|dependencies)`},
		} {
			if p.field(requirement.pattern) == "" {
				issue(p, "test environment must specify non-placeholder "+requirement.name)
			}
		}
	}
	cases := map[string]planPart{}
	if p, ok := parts["test cases"]; ok {
		for _, h := range headings {
			if h.start <= p.heading.start || h.start >= p.heading.stop+len(p.data) {
				continue
			}
			ids := caseIdentifier.FindAllString(h.name, -1)
			if len(ids) != 1 || !caseDefinition.MatchString(label(h.name)) {
				continue
			}
			id := strings.ToUpper(ids[0])
			c := readPlanPart(body, h, headings)
			if _, exists := cases[id]; exists {
				v.add(f.path, offset+h.line, "IDENTITY", "test-case identifiers must be unique within a plan")
			}
			cases[id] = c
		}
		if len(cases) == 0 {
			issue(p, "define at least one test case under a heading with a unique TC-<number> identifier")
		}
	}
	for _, id := range sortedKeys(cases) {
		c := cases[id]
		if c.field(`^(?:objective|purpose)$`) == "" {
			issue(c, "test case must specify a non-placeholder objective")
		}
		preconditions := c.field(`^(?:preconditions?|prerequisites?|setup)$`)
		if preconditions == "" {
			issue(c, "test case must specify preconditions, or explain why none apply")
		}
		for _, value := range []string{preconditions, c.field(`(?:automated|automation|primary method)`)} {
			for _, target := range caseIdentifier.FindAllString(value, -1) {
				if _, exists := cases[strings.ToUpper(target)]; !exists {
					v.add(f.path, offset+c.heading.line, "RELATIONSHIP", "test-case setup or execution references an undefined test case")
				}
			}
		}
		if !caseProcedure(c, cases, map[string]bool{id: true}) {
			issue(c, "test case must include actions and expected results for every step, or an automated test reference, run command, and expected outcome")
		}
	}
	if p, ok := parts["objectives"]; ok {
		mapped := false
		for _, t := range p.tables {
			criterion, test := t.column(`(?:acceptance criteri|criterion)`), t.column(`test cases?`)
			if criterion < 0 || test < 0 {
				continue
			}
			for _, row := range t.rows {
				mapped = true
				ids := caseIdentifier.FindAllString(row.cell(test), -1)
				if !meaningful(row.cell(criterion)) || len(ids) == 0 {
					v.add(f.path, offset+row.line, "PLAN_CONTENT", "each acceptance criterion must have a description and map to at least one defined test case")
				}
				for _, id := range ids {
					if _, exists := cases[strings.ToUpper(id)]; !exists {
						v.add(f.path, offset+row.line, "RELATIONSHIP", "acceptance criterion references an undefined test case")
					}
				}
			}
		}
		if !mapped {
			issue(p, "include a populated acceptance-criteria mapping table with criterion and test-case columns")
		}
	}
	if p, ok := parts["risks"]; ok {
		paired := false
		for _, t := range p.tables {
			risk, mitigation := t.column(`^risk$`), t.column(`^(?:mitigation|contingency|response)s?$`)
			if risk < 0 || mitigation < 0 {
				continue
			}
			for _, row := range t.rows {
				paired = true
				if !meaningful(row.cell(risk)) || !meaningful(row.cell(mitigation)) {
					v.add(f.path, offset+row.line, "PLAN_CONTENT", "each risk must have a non-placeholder description and mitigation")
				}
			}
		}
		if !paired {
			issue(p, "include a populated risk-and-mitigation table")
		}
	}
	if p, ok := parts["approvals"]; ok {
		rule := "PLAN_CONTENT"
		if status == "active" {
			rule = "PLAN_APPROVAL"
		}
		author, reviewer := false, false
		for _, t := range p.tables {
			role, name, date := t.column(`^role$`), t.column(`^(?:name|person|owner)$`), t.column(`^date$`)
			if role < 0 || name < 0 || date < 0 {
				continue
			}
			for _, row := range t.rows {
				switch label(row.cell(role)) {
				case "author":
					author = true
					if !meaningful(row.cell(name)) || !validCalendarDate(row.cell(date)) {
						v.add(f.path, offset+row.line, rule, "author approval entry must identify the author and a real calendar date")
					}
				case "reviewer", "approver":
					reviewer = true
					if (status == "active" || meaningful(row.cell(date))) && (!meaningful(row.cell(name)) || !validCalendarDate(row.cell(date))) {
						v.add(f.path, offset+row.line, rule, "reviewer approval entry must identify the reviewer and a real calendar date; active plans cannot leave approval pending")
					}
				}
			}
		}
		if !author || !reviewer {
			v.add(f.path, offset+p.heading.line, rule, "approvals must identify an author with a date and a reviewer role; active plans also require a named reviewer and approval date")
		}
	} else if status == "active" {
		v.add(f.path, offset+1, "PLAN_APPROVAL", "active plans require an author and reviewer approval record")
	}
}

func validCalendarDate(value string) bool {
	_, err := time.Parse(time.DateOnly, strings.TrimSpace(value))
	return err == nil
}

func caseProcedure(p planPart, cases map[string]planPart, seen map[string]bool) bool {
	stepTable, complete := false, true
	for _, t := range p.tables {
		action, expected := t.column(`^(?:action|procedure)$`), t.column(`^expected(?: results?| outcomes?)?$`)
		if action < 0 && (t.column(`^step$`) < 0 || t.column(`^expected results?$`) < 0) {
			continue
		}
		stepTable = true
		complete = complete && len(t.rows) > 0 && action >= 0 && expected >= 0
		for _, row := range t.rows {
			complete = complete && meaningful(row.cell(action)) && meaningful(row.cell(expected))
		}
	}
	if stepTable {
		return complete
	}
	if p.field(`^expected(?: results?| outcomes?)?$`) == "" {
		return false
	}
	if p.field(`^(?:steps?|procedure|actions?)$`) != "" {
		return true
	}
	method := p.field(`(?:automated|automation|primary method)`)
	method += "\n" + p.field(`^test(?: reference| file| suite)?$`)
	if command := p.field(`^(?:run(?: with)?|command|execute)$`); command != "" && testReference.MatchString(method) && wordCharacter.MatchString(command) {
		return true
	}
	for _, match := range runInstruction.FindAllStringSubmatch(method, -1) {
		if strings.EqualFold(match[1], "build") && !selectTest.MatchString(method) {
			continue
		}
		if meaningful(match[2]) && wordCharacter.MatchString(match[2]) && testReference.MatchString(method) {
			return true
		}
	}
	if inheritMethod.MatchString(method) {
		for _, id := range caseIdentifier.FindAllString(method, -1) {
			id = strings.ToUpper(id)
			if target, ok := cases[id]; ok && !seen[id] {
				seen[id] = true
				if caseProcedure(target, cases, seen) {
					return true
				}
			}
		}
	}
	return false
}

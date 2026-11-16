package artifactlint

import (
	"bytes"
	"regexp"
	"strings"

	"github.com/yuin/goldmark"
	"github.com/yuin/goldmark/ast"
	"github.com/yuin/goldmark/extension"
	tableast "github.com/yuin/goldmark/extension/ast"
	"github.com/yuin/goldmark/text"
)

type heading struct {
	name          string
	level         int
	start         int
	stop          int
	line          int
	documentLevel bool
}

var sectionNumber = regexp.MustCompile(`^[0-9]+(?:\.[0-9]+)*[.)]?\s+`)

var planSections = []struct {
	name    string
	aliases *regexp.Regexp
}{
	{"identifier", regexp.MustCompile(`\b(?:test )?plan identifier\b`)},
	{"objectives", regexp.MustCompile(`\b(?:objectives|introduction|purpose)\b`)},
	{"references", regexp.MustCompile(`\b(?:test items|references)\b`)},
	{"environment", regexp.MustCompile(`\b(?:test environment|environment|prerequisites)\b`)},
	{"test cases", regexp.MustCompile(`\b(?:test cases|test approach|test design)\b`)},
	{"risks", regexp.MustCompile(`\brisks\b`)},
	{"approvals", regexp.MustCompile(`\b(?:approvals?|sign.off)\b`)},
}

func parseMarkdown(data []byte) (ast.Node, []heading) {
	doc := goldmark.New(goldmark.WithExtensions(extension.Table)).Parser().Parse(text.NewReader(data))
	var headings []heading
	positions := sourceLines{data: data, line: 1}
	// ast.Walk only returns errors supplied by the callback, which always returns nil.
	_ = ast.Walk(doc, func(n ast.Node, entering bool) (ast.WalkStatus, error) {
		if h, ok := n.(*ast.Heading); entering && ok && h.Lines().Len() > 0 {
			first := h.Lines().At(0)
			last := h.Lines().At(h.Lines().Len() - 1)
			start := bytes.LastIndexByte(data[:first.Start], '\n') + 1
			stop := lineEnd(data, last.Stop)
			if !bytes.Contains(data[start:first.Start], []byte("#")) && stop < len(data) {
				end := lineEnd(data, stop)
				underline := bytes.TrimSpace(data[stop:end])
				marker := byte('-')
				if h.Level == 1 {
					marker = '='
				}
				if len(underline) > 0 && bytes.Count(underline, []byte{marker}) == len(underline) {
					stop = end
				}
			}
			headings = append(headings, heading{
				name: nodeText(h, data), level: h.Level,
				start: start, stop: stop,
				line: positions.at(first.Start), documentLevel: h.Parent() == doc,
			})
		}
		return ast.WalkContinue, nil
	})
	return doc, headings
}

func nodeText(node ast.Node, data []byte) string {
	var out strings.Builder
	_ = ast.Walk(node, func(n ast.Node, entering bool) (ast.WalkStatus, error) {
		if entering {
			switch typed := n.(type) {
			case *ast.Text:
				out.Write(typed.Segment.Value(data))
			case *ast.String:
				out.Write(typed.Value)
			}
		}
		return ast.WalkContinue, nil
	})
	return out.String()
}

func (v *validator) planStructure(f *source, body []byte, offset int, status, title string) {
	doc, headings := parseMarkdown(body)
	planHeadings := make([]heading, 0, len(headings))
	for _, h := range headings {
		if h.documentLevel {
			planHeadings = append(planHeadings, h)
		}
	}
	headings = planHeadings
	var tables []planTable
	positions := sourceLines{data: body, line: 1}
	for n := doc.FirstChild(); n != nil; n = n.NextSibling() {
		if n.Kind() == tableast.KindTable {
			tables = append(tables, readPlanTable(n, body, &positions))
		}
	}
	parts, caseRegions := selectPlanParts(body, headings, title)
	for _, section := range planSections {
		part, found := parts[section.name]
		if section.name == "test cases" {
			for _, region := range caseRegions {
				if strings.Trim(string(region.data), " \t\r\n#-_*=") != "" {
					part = region
					break
				}
			}
		}
		if !found || strings.Trim(string(part.data), " \t\r\n#-_*=") == "" {
			v.add(f.path, offset+1, "STRUCTURE", "include a nonempty "+section.name+" section using supported headings")
		}
	}
	v.planContent(f, body, headings, parts, caseRegions, tables, offset, status)
}

// sourceLines counts newlines once as a parser visits positions in source order.
type sourceLines struct {
	data         []byte
	cursor, line int
}

func (s *sourceLines) at(position int) int {
	s.line += bytes.Count(s.data[s.cursor:position], []byte("\n"))
	s.cursor = position
	return s.line
}

func lineEnd(data []byte, position int) int {
	if next := bytes.IndexByte(data[position:], '\n'); next >= 0 {
		return position + next + 1
	}
	return len(data)
}

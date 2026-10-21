package artifactlint

import (
	"bytes"
	"regexp"
	"strings"

	"github.com/yuin/goldmark"
	"github.com/yuin/goldmark/ast"
	"github.com/yuin/goldmark/text"
)

type heading struct {
	name  string
	level int
	start int
	stop  int
	line  int
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
	doc := goldmark.DefaultParser().Parse(text.NewReader(data))
	var headings []heading
	// ast.Walk only returns errors supplied by the callback, which always returns nil.
	_ = ast.Walk(doc, func(n ast.Node, entering bool) (ast.WalkStatus, error) {
		if h, ok := n.(*ast.Heading); entering && ok && h.Lines().Len() > 0 {
			first := h.Lines().At(0)
			last := h.Lines().At(h.Lines().Len() - 1)
			headings = append(headings, heading{
				name: nodeText(h, data), level: h.Level,
				start: first.Start, stop: last.Stop,
				line: bytes.Count(data[:first.Start], []byte("\n")) + 1,
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

func (v *validator) planStructure(f *source, body []byte, offset int) {
	_, headings := parseMarkdown(body)
	for _, section := range planSections {
		found := false
		for i, h := range headings {
			name := sectionNumber.ReplaceAllString(strings.ToLower(h.name), "")
			if !section.aliases.MatchString(name) {
				continue
			}
			stop := len(body)
			for _, next := range headings[i+1:] {
				if next.level <= h.level {
					stop = next.start
					break
				}
			}
			// Heading markers and thematic separators do not count as section content.
			if strings.Trim(string(body[h.stop:stop]), " \t\r\n#-_*=") != "" {
				found = true
				break
			}
		}
		if !found {
			v.add(f.path, offset+1, "STRUCTURE", "include a nonempty "+section.name+" section or document a reviewed adaptation")
		}
	}
}

package artifactlint

import (
	"bytes"
	"regexp"
	"strconv"
	"strings"

	"github.com/yuin/goldmark"
	"github.com/yuin/goldmark/ast"
	"github.com/yuin/goldmark/extension"
	tableast "github.com/yuin/goldmark/extension/ast"
	"github.com/yuin/goldmark/text"
)

var (
	reportSummary = regexp.MustCompile(`(?i)^(?:verdict|summary):\s*`)
	resultCount   = regexp.MustCompile(`(?i)\b([0-9]+)\s+(pass|fail|skip)\b`)
)

func (v *validator) markdownReportCounts(f *source, body []byte, offset int) {
	doc := goldmark.New(goldmark.WithExtensions(extension.Table)).Parser().Parse(text.NewReader(body))
	var counts map[string]int
	tables := 0
	for n := doc.FirstChild(); n != nil; n = n.NextSibling() {
		if table, ok := n.(*tableast.Table); ok {
			if results, candidate := testCaseCounts(table, body); candidate {
				counts = results
				tables++
			}
		}
	}
	// Multiple tables may repeat cases or describe different runs. Do not guess
	// which one a report-wide summary describes, or infer totals from prose.
	if tables != 1 || counts == nil {
		return
	}
	for n := doc.FirstChild(); n != nil; n = n.NextSibling() {
		p, ok := n.(*ast.Paragraph)
		if !ok {
			continue
		}
		for i, line := range strings.Split(reportSummaryText(p, body), "\n") {
			if !reportSummary.MatchString(line) {
				continue
			}
			for _, match := range resultCount.FindAllStringSubmatch(line, -1) {
				count, err := strconv.Atoi(match[1])
				status := strings.ToLower(match[2])
				if err != nil || count != counts[status] {
					lineNumber := offset + bytes.Count(body[:p.Lines().At(0).Start], []byte("\n")) + i + 1
					v.add(f.path, lineNumber, "COUNTS", "summary "+status+" count must equal the number of matching test-case results")
				}
			}
		}
	}
}

// Preserve header line boundaries, but do not interpret inline code examples
// as summary declarations. Tables use nodeText so code-formatted statuses work.
func reportSummaryText(p *ast.Paragraph, body []byte) string {
	var out strings.Builder
	_ = ast.Walk(p, func(n ast.Node, entering bool) (ast.WalkStatus, error) {
		if !entering {
			return ast.WalkContinue, nil
		}
		switch typed := n.(type) {
		case *ast.CodeSpan:
			out.WriteByte(' ')
			return ast.WalkSkipChildren, nil
		case *ast.Text:
			out.Write(typed.Segment.Value(body))
			if typed.SoftLineBreak() || typed.HardLineBreak() {
				out.WriteByte('\n')
			}
		case *ast.String:
			out.Write(typed.Value)
		}
		return ast.WalkContinue, nil
	})
	return out.String()
}

func testCaseCounts(table *tableast.Table, body []byte) (map[string]int, bool) {
	header := table.FirstChild()
	if header == nil {
		return nil, false
	}
	resultColumn, hasCases := -1, false
	column, resultColumns := 0, 0
	for cell := header.FirstChild(); cell != nil; cell = cell.NextSibling() {
		switch strings.ToLower(strings.TrimSpace(nodeText(cell, body))) {
		case "test case":
			hasCases = true
		case "result", "status":
			resultColumns++
			resultColumn = column
		}
		column++
	}
	if !hasCases || resultColumn < 0 {
		return nil, false
	}
	if resultColumns != 1 || header.NextSibling() == nil {
		return nil, true
	}
	counts := map[string]int{"pass": 0, "fail": 0, "skip": 0}
	for row := header.NextSibling(); row != nil; row = row.NextSibling() {
		cell := row.FirstChild()
		for i := 0; i < resultColumn && cell != nil; i++ {
			cell = cell.NextSibling()
		}
		if cell == nil {
			return nil, true
		}
		status := strings.ToLower(strings.TrimSpace(nodeText(cell, body)))
		if _, known := counts[status]; !known {
			return nil, true
		}
		counts[status]++
	}
	return counts, true
}

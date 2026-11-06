package artifactlint

import (
	"bytes"
	"io"
	"strconv"
	"strings"
	"unicode/utf8"

	"github.com/tdewolff/parse/v2"
	"github.com/tdewolff/parse/v2/css"
)

func (v *validator) cssReferences(f *source, d *document, data []byte, offset int) {
	lexer := css.NewLexer(parse.NewInput(bytes.NewReader(data)))
	line := offset + 1
	importPending := false
	// Strings directly inside image-set() are image URLs; deeper strings, such
	// as type("image/avif"), are not.
	imageSetDepth := 0
	for {
		kind, raw := lexer.Next()
		if kind == css.ErrorToken {
			if lexer.Err() != io.EOF {
				v.add(f.path, line, "LINK", "CSS could not be tokenized")
			}
			return
		}
		tokenLine := line
		line += bytes.Count(raw, []byte("\n"))
		value := string(raw)
		target := ""
		switch kind {
		case css.AtKeywordToken:
			importPending = strings.EqualFold(cssUnescape(value), "@import")
		case css.URLToken:
			open := strings.IndexByte(value, '(')
			if open >= 0 && strings.Contains(value[:open], "\\") {
				v.add(f.path, tokenLine, "LINK", "spell CSS url() without escaped function names")
				continue
			}
			if open >= 0 && strings.HasSuffix(value, ")") {
				target = strings.TrimSpace(value[open+1 : len(value)-1])
			}
			importPending = false
		case css.StringToken:
			if importPending || imageSetDepth == 1 {
				target = value
				importPending = false
			}
		case css.FunctionToken:
			if strings.Contains(value, "\\") {
				v.add(f.path, tokenLine, "LINK", "escaped CSS function names are unsupported; use plain function spellings")
			}
			if name := strings.ToLower(value); imageSetDepth > 0 || name == "image-set(" || name == "-webkit-image-set(" {
				imageSetDepth++
			}
		case css.BadURLToken, css.BadStringToken:
			v.add(f.path, tokenLine, "LINK", "repair malformed CSS URL or string syntax")
		case css.WhitespaceToken, css.CommentToken:
			continue
		default:
			importPending = false
			if imageSetDepth > 0 && kind == css.LeftParenthesisToken {
				imageSetDepth++
			} else if imageSetDepth > 0 && kind == css.RightParenthesisToken {
				imageSetDepth--
			}
		}
		if target == "" {
			continue
		}
		if len(target) >= 2 && (target[0] == '\'' || target[0] == '"') && target[len(target)-1] == target[0] {
			target = target[1 : len(target)-1]
		}
		target = cssUnescape(target)
		if strings.HasPrefix(target, "#") {
			continue
		}
		d.links = append(d.links, reference{target: target, line: tokenLine, resource: true, presentation: true})
	}
}

func cssUnescape(s string) string {
	var out strings.Builder
	for i := 0; i < len(s); i++ {
		if s[i] != '\\' {
			out.WriteByte(s[i])
			continue
		}
		i++
		if i == len(s) {
			break
		}
		if strings.ContainsRune("\n\r\f", rune(s[i])) {
			if s[i] == '\r' && i+1 < len(s) && s[i+1] == '\n' {
				i++
			}
			continue
		}
		end := i
		for end < len(s) && end-i < 6 && strings.ContainsRune("0123456789abcdefABCDEF", rune(s[end])) {
			end++
		}
		if end == i {
			out.WriteByte(s[i])
			continue
		}
		value, err := strconv.ParseUint(s[i:end], 16, 32)
		if err != nil || value == 0 || !utf8.ValidRune(rune(value)) {
			out.WriteRune(utf8.RuneError)
		} else {
			out.WriteRune(rune(value))
		}
		i = end - 1
		if end < len(s) && strings.ContainsRune(" \t\n\r\f", rune(s[end])) {
			i++
			if s[end] == '\r' && end+1 < len(s) && s[end+1] == '\n' {
				i++
			}
		}
	}
	return out.String()
}

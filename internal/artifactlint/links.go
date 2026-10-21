package artifactlint

import (
	"bytes"
	"io"
	"net/url"
	"path"
	"strconv"
	"strings"
	"unicode"

	"github.com/yuin/goldmark/ast"
	"golang.org/x/net/html"
)

type reference struct {
	target       string
	line         int
	resource     bool
	presentation bool
}

type document struct {
	anchors map[string]bool
	links   []reference
}

func (v *validator) links() {
	docs := map[string]*document{}
	for _, name := range sortedKeys(v.files) {
		f := v.files[name]
		d := &document{anchors: map[string]bool{}}
		switch strings.ToLower(path.Ext(name)) {
		case ".md":
			_, data, offset, _, _ := splitFrontMatter(f.data)
			node, headings := parseMarkdown(data)
			for _, h := range headings {
				base := githubSlug(h.name)
				slug := base
				for i := 1; d.anchors[slug]; i++ {
					slug = base + "-" + strconv.Itoa(i)
				}
				d.anchors[slug] = true
			}
			_ = ast.Walk(node, func(n ast.Node, entering bool) (ast.WalkStatus, error) {
				if !entering {
					return ast.WalkContinue, nil
				}
				switch typed := n.(type) {
				case *ast.Link:
					d.links = append(d.links, reference{target: string(typed.Destination), line: offset + lineOf(data, typed.Destination)})
				case *ast.Image:
					d.links = append(d.links, reference{target: string(typed.Destination), line: offset + lineOf(data, typed.Destination), resource: true})
				case *ast.AutoLink:
					target := string(typed.URL(data))
					if typed.AutoLinkType == ast.AutoLinkEmail && !strings.HasPrefix(target, "mailto:") {
						target = "mailto:" + target
					}
					d.links = append(d.links, reference{target: target, line: offset + lineOf(data, typed.Label(data))})
				case *ast.RawHTML:
					for i := 0; i < typed.Segments.Len(); i++ {
						s := typed.Segments.At(i)
						v.htmlReferences(f, d, s.Value(data), offset+lineAt(data, s.Start)-1)
					}
				case *ast.HTMLBlock:
					var raw []byte
					for i := 0; i < typed.Lines().Len(); i++ {
						s := typed.Lines().At(i)
						raw = append(raw, s.Value(data)...)
					}
					if typed.HasClosure() {
						raw = append(raw, typed.ClosureLine.Value(data)...)
					}
					line := offset
					if typed.Lines().Len() > 0 {
						line += lineAt(data, typed.Lines().At(0).Start) - 1
					}
					v.htmlReferences(f, d, raw, line)
				}
				return ast.WalkContinue, nil
			})
		case ".html", ".htm":
			v.htmlReferences(f, d, f.data, 0)
		case ".css":
			v.cssReferences(f, d, f.data, 0)
		default:
			continue
		}
		docs[name] = d
	}
	for _, name := range sortedKeys(docs) {
		for _, ref := range docs[name].links {
			v.resolveLink(name, ref, docs)
		}
	}
}

func lineOf(data, target []byte) int {
	i := bytes.Index(data, target)
	if i < 0 {
		return 1
	}
	return lineAt(data, i)
}

// lineAt returns the 1-based line containing byte offset i.
func lineAt(data []byte, i int) int {
	return bytes.Count(data[:i], []byte("\n")) + 1
}

func githubSlug(s string) string {
	var out strings.Builder
	for _, r := range strings.ToLower(s) {
		switch {
		case unicode.IsLetter(r) || unicode.IsNumber(r) || unicode.IsMark(r) || r == '-' || r == '_':
			out.WriteRune(r)
		case unicode.IsSpace(r):
			out.WriteByte('-')
		}
	}
	return out.String()
}

func (v *validator) htmlReferences(f *source, d *document, data []byte, offset int) {
	z := html.NewTokenizer(bytes.NewReader(data))
	line := offset + 1
	inStyle := false
	for {
		typeOf := z.Next()
		if typeOf == html.ErrorToken {
			if z.Err() != io.EOF {
				v.add(f.path, line, "LINK", "HTML could not be tokenized")
			}
			return
		}
		token := z.Token()
		if typeOf == html.StartTagToken || typeOf == html.SelfClosingTagToken {
			if token.Data == "style" {
				inStyle = true
			}
			attrs := map[string]string{}
			for _, a := range token.Attr {
				attrs[a.Key] = a.Val
				if a.Key == "id" || (token.Data == "a" && a.Key == "name") {
					d.anchors[a.Val] = true
				}
			}
			if token.Data == "base" {
				v.add(f.path, line, "LINK", "base elements are not supported; use explicit relative links")
			}
			for _, a := range token.Attr {
				switch a.Key {
				case "href", "src", "poster", "data", "action":
					if token.Data == "base" {
						continue
					}
					presentation := (token.Data == "link" && strings.Contains(attrs["rel"], "stylesheet")) || token.Data == "script"
					_, download := attrs["download"]
					resource := a.Key != "href" || token.Data == "link" || download
					d.links = append(d.links, reference{target: a.Val, line: line, resource: resource, presentation: presentation})
				case "srcset":
					for _, target := range srcsetURLs(a.Val) {
						d.links = append(d.links, reference{target: target, line: line, resource: true})
					}
				case "style":
					v.cssReferences(f, d, []byte(a.Val), line-1)
				}
			}
		}
		if typeOf == html.TextToken && inStyle {
			v.cssReferences(f, d, []byte(token.Data), line-1)
		}
		if typeOf == html.EndTagToken && token.Data == "style" {
			inStyle = false
		}
		line += bytes.Count(z.Raw(), []byte("\n"))
	}
}

func (v *validator) resolveLink(from string, ref reference, docs map[string]*document) {
	u, err := url.Parse(ref.target)
	if err != nil || u.User != nil || strings.ContainsAny(ref.target, "\x00\r\n\\") {
		v.add(from, ref.line, "LINK", "use a well-formed URL without credentials or unsafe characters")
		return
	}
	if u.Scheme != "" || u.Host != "" {
		if (u.Scheme == "https" || u.Scheme == "http" || u.Scheme == "") && u.Host != "" {
			if privateHost(u.Hostname()) {
				v.add(from, ref.line, "SECURITY", "remove private/internal URLs, including encoded addresses; use sanitized placeholders")
			}
			if ref.resource && (!ref.presentation || !allowedCDN(u.Hostname()) || u.Scheme != "https") {
				v.add(from, ref.line, "LINK", "keep evidence inside the repository; only approved HTTPS CDNs may supply presentation resources")
			}
			return
		}
		if u.Scheme == "mailto" && !ref.resource {
			return
		}
		if u.Scheme == "data" && ref.resource && (strings.HasPrefix(ref.target, "data:image/png;") || strings.HasPrefix(ref.target, "data:image/jpeg;")) {
			return
		}
		v.add(from, ref.line, "LINK", "unsupported URL scheme; use local paths or public HTTP(S) citations")
		return
	}
	if strings.HasPrefix(u.Path, "/") {
		v.add(from, ref.line, "PATH", "use repository-relative links, not absolute filesystem paths")
		return
	}
	target := from
	if u.Path != "" {
		target = path.Clean(path.Join(path.Dir(from), u.Path))
	}
	if target == ".." || strings.HasPrefix(target, "../") || strings.ContainsAny(target, "\x00\\") {
		v.add(from, ref.line, "PATH", "link escapes the repository")
		return
	}
	parts := strings.Split(from, "/")
	if len(parts) >= 3 && parts[0] == "reports" && (ref.resource || !artifactCitation(target)) && !strings.HasPrefix(target, strings.Join(parts[:2], "/")+"/") {
		v.add(from, ref.line, "PATH", "bundle evidence and resources must remain inside their report directory")
		return
	}
	if v.files[target] == nil {
		for name := range v.files {
			if strings.HasPrefix(name, strings.TrimSuffix(target, "/")+"/") && u.Fragment == "" {
				return
			}
		}
		v.add(from, ref.line, "LINK", "local link target is missing")
		return
	}
	if u.Fragment != "" {
		d := docs[target]
		if d == nil || !d.anchors[u.Fragment] {
			v.add(from, ref.line, "FRAGMENT", "local link fragment does not identify an existing heading or HTML anchor")
		}
	}
}

func allowedCDN(host string) bool {
	switch host {
	case "cdn.jsdelivr.net", "cdnjs.cloudflare.com", "unpkg.com", "maxcdn.bootstrapcdn.com", "stackpath.bootstrapcdn.com":
		return true
	}
	return false
}

func artifactCitation(target string) bool {
	if target == "plans" || target == "docs" {
		return true
	}
	return path.Ext(target) == ".md" && (strings.HasPrefix(target, "plans/") || strings.HasPrefix(target, "docs/") || path.Dir(target) == ".")
}

func srcsetURLs(value string) []string {
	var urls []string
	space := func(r rune) bool { return r == ' ' || r == '\t' || r == '\n' || r == '\r' || r == '\f' }
	for value != "" {
		value = strings.TrimLeftFunc(value, func(r rune) bool { return r == ',' || space(r) })
		if value == "" {
			break
		}
		end := strings.IndexFunc(value, space)
		if end < 0 {
			end = len(value)
		}
		candidate := value[:end]
		value = value[end:]
		if strings.HasSuffix(candidate, ",") {
			urls = append(urls, strings.TrimRight(candidate, ","))
			continue
		}
		urls = append(urls, candidate)
		// Descriptors end at the next comma outside parentheses. Commas in
		// the URL itself (notably data:image URLs) are not separators.
		depth := 0
		for len(value) > 0 {
			c := value[0]
			value = value[1:]
			if c == '(' {
				depth++
			}
			if c == ')' && depth > 0 {
				depth--
			}
			if c == ',' && depth == 0 {
				break
			}
		}
	}
	return urls
}

package artifactlint

import (
	"bytes"
	"net"
	"net/url"
	"regexp"
	"strings"
)

var (
	urlPattern         = regexp.MustCompile(`(?i)https?://[^\s<>"'` + "`" + `]+`)
	bearerPattern      = regexp.MustCompile(`(?i)\bbearer\s+([A-Za-z0-9_.$<>{}-]+)`)
	identifierPatterns = []*regexp.Regexp{
		regexp.MustCompile(`(?i)/subscriptions/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}`),
		regexp.MustCompile(`(?i)(?:tenant[_ -]?id|subscription[_ -]?id)\s*[=:]\s*["']?[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}`),
	}
	accountPattern = regexp.MustCompile(`arn:aws[a-z-]*:[^\s:]+:[^\s:]*:([0-9]{12}):`)
)

func bytesContainNUL(data []byte) bool { return bytes.IndexByte(data, 0) >= 0 }

func (v *validator) sanitization() {
	for _, name := range sortedKeys(v.files) {
		f := v.files[name]
		for _, match := range urlPattern.FindAllIndex(f.data, -1) {
			raw := strings.TrimRight(string(f.data[match[0]:match[1]]), ".,);]}")
			u, err := url.Parse(raw)
			if err == nil && (u.User != nil || privateHost(u.Hostname())) {
				v.add(name, lineOf(f.data, []byte(raw)), "SECURITY", "remove embedded credentials or private/internal URL; replace sensitive values with placeholders")
			}
		}
		for _, match := range bearerPattern.FindAllSubmatchIndex(f.data, -1) {
			value := string(f.data[match[2]:match[3]])
			upper := strings.ToUpper(value)
			// Short prose such as "bearer tokens" is not a token value. The
			// maintained scanner supplies additional credential-specific rules.
			if len(value) < 20 {
				continue
			}
			if upper == "TOKEN" || upper == "REDACTED" || upper == "<REDACTED>" || upper == "<TOKEN>" || upper == "YOUR_TOKEN" || strings.HasPrefix(value, "${") {
				continue
			}
			v.add(name, lineAt(f.data, match[0]), "SECURITY", "remove bearer token values; use a redacted placeholder")
		}
		for _, pattern := range identifierPatterns {
			for _, match := range pattern.FindAllIndex(f.data, -1) {
				v.add(name, lineAt(f.data, match[0]), "SECURITY", "replace cloud account, subscription, or tenant identifiers with placeholders")
			}
		}
		for _, match := range accountPattern.FindAllSubmatchIndex(f.data, -1) {
			account := string(f.data[match[2]:match[3]])
			if account == "000000000000" || account == "111111111111" || account == "123456789012" {
				continue
			}
			v.add(name, lineAt(f.data, match[0]), "SECURITY", "replace cloud account identifiers with placeholders")
		}
	}
}

func privateHost(host string) bool {
	host = strings.TrimSuffix(strings.ToLower(host), ".")
	if host == "localhost" || host == "127.0.0.1" || host == "::1" {
		return false
	}
	if host == "redhat-internal.slack.com" {
		return true
	}
	for _, suffix := range []string{".internal", ".local", ".localhost", ".corp", ".svc", ".corp.redhat.com", ".redhat-internal.com"} {
		if strings.HasSuffix(host, suffix) {
			return true
		}
	}
	if ip := net.ParseIP(host); ip != nil {
		return ip.IsPrivate() || ip.IsLoopback() || ip.IsLinkLocalUnicast() || ip.IsLinkLocalMulticast() || ip.IsUnspecified()
	}
	return false
}

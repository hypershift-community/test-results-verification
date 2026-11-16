package artifactlint_test

import (
	"strings"
	"testing"

	. "github.com/onsi/gomega"

	"github.com/hypershift-community/test-results-verification/internal/artifactlint"
)

func TestSanitization(t *testing.T) {
	t.Parallel()
	privateURL := "https://api." + "corp.internal" + "/logs"
	bearer := "Authorization: Bearer " + strings.Repeat("sensitive", 8)
	account := "arn:aws:iam::" + "9276" + "3048" + "1529" + ":role/test"
	tenant := "/subscriptions/" + "12345678-1234-1234-1234-123456789abc" + "/resources"
	tests := []struct {
		name      string
		file      string
		contents  string
		wantError bool
	}{
		{"When evidence includes a private URL, it should require sanitization", "evidence.log", privateURL, true},
		{"When a helper script embeds a bearer token, it should redact the finding", "scripts/helper.sh", bearer, true},
		{"When an AWS account identifier appears in evidence, it should require a placeholder", "evidence.log", account, true},
		{"When a subscription URL includes an identifier, it should require a placeholder", "evidence.log", tenant, true},
		{"When evidence uses a redacted token placeholder, it should accept the example", "evidence.log", "Authorization: Bearer <REDACTED>", false},
		{"When a citation uses a public Jira URL, it should accept the reference", "README.md", "https://redhat.atlassian.net/browse/CNTRLPLANE-7", false},
		{"When a URL uses a private IP, it should require sanitization", "evidence.log", "https://" + "10.0.0.1" + "/logs", true},
		{"When a URL embeds credentials, it should reject them without echoing the value", "evidence.log", "https://user:" + "sensitive-password" + "@example.org/", true},
		{"When evidence is under a nested bin directory, it should still scan it", "assets/bin/evidence.log", privateURL, true},
		{"When an AWS documentation placeholder is used, it should not mistake it for a real account", "evidence.log", "arn:aws:iam::" + "123456789012" + ":role/example", false},
		{"When a loopback development endpoint is shown, it should not disclose an internal instance", "evidence.log", "https://" + "localhost" + ":6443/healthz", false},
		{"When an HTML link encodes a private address, it should inspect the decoded URL", "guide.html", "<a href='https://10&#46;0&#46;0&#46;1/logs'>Logs</a>", true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			g := NewWithT(t)
			result, err := artifactlint.Validate(writeFiles(t, map[string]string{tt.file: tt.contents}))
			g.Expect(err).NotTo(HaveOccurred())
			g.Expect(result.HasErrors()).To(Equal(tt.wantError), "%+v", result.Findings)
			for _, f := range result.Findings {
				g.Expect(f.Message).NotTo(ContainSubstring(tt.contents))
				g.Expect(f.Message).NotTo(ContainSubstring("sensitive-password"))
			}
		})
	}
}

func TestMalformedTextEvidence(t *testing.T) {
	t.Parallel()
	for name, content := range map[string]string{"When evidence contains NUL, it should reject malformed text": "log\x00data", "When evidence contains invalid UTF-8, it should reject malformed text": "log" + string([]byte{0xff})} {
		t.Run(name, func(t *testing.T) {
			g := NewWithT(t)
			result, err := artifactlint.Validate(writeFiles(t, map[string]string{"evidence.log": content}))
			g.Expect(err).NotTo(HaveOccurred())
			g.Expect(result.Findings).To(ContainElement(HaveField("Rule", "ENCODING")))
		})
	}
	t.Run("When a binary image has non-text bytes, it should retain the documented human-review boundary", func(t *testing.T) {
		g := NewWithT(t)
		result, err := artifactlint.Validate(writeFiles(t, map[string]string{"image.png": string([]byte{0x89, 0, 0xff})}))
		g.Expect(err).NotTo(HaveOccurred())
		g.Expect(result.HasErrors()).To(BeFalse())
	})
}

package artifactlint_test

import (
	"os"
	"path/filepath"
	"testing"

	. "github.com/onsi/gomega"

	"github.com/hypershift-community/test-results-verification/internal/artifactlint"
)

func TestLocalLinks(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name      string
		files     map[string]string
		wantError bool
	}{
		{"When a Markdown link references an existing heading, it should resolve the fragment", map[string]string{"README.md": "[Guide](docs/guide.md#setup-and-use)", "docs/guide.md": "# Setup and Use"}, false},
		{"When a reference-style link is broken, it should report the destination", map[string]string{"README.md": "[Guide][g]\n\n[g]: missing.md"}, true},
		{"When a heading fragment is missing, it should report the broken fragment", map[string]string{"README.md": "[Guide](guide.md#missing)", "guide.md": "# Setup"}, true},
		{"When duplicate headings use GitHub suffixes, it should resolve the second heading", map[string]string{"README.md": "[Second](guide.md#setup-1)", "guide.md": "# Setup\n\n# Setup"}, false},
		{"When a fenced example contains a fake link, it should not treat it as navigation", map[string]string{"README.md": "```markdown\n[fake](missing.md)\n```"}, false},
		{"When a URL contains a query, it should still check its local target", map[string]string{"README.md": "[Guide](missing.md?download=1)"}, true},
		{"When a link uses URL-encoded traversal, it should reject repository escape", map[string]string{"README.md": "[outside](%2e%2e/secret.txt)"}, true},
		{"When HTML references a missing image, it should report the missing asset", map[string]string{"guide.html": "<img src='assets/missing.png'>"}, true},
		{"When inline HTML supplies an anchor, it should resolve that anchor", map[string]string{"README.md": "<a id='custom'></a>\n\n[here](#custom)"}, false},
		{"When CSS references a missing image, it should report the missing asset", map[string]string{"assets/style.css": "body { background: url(missing.png); }"}, true},
		{"When a quoted CSS URL contains spaces, it should check the entire path", map[string]string{"style.css": "body { background: url(\"missing image.png\"); }"}, true},
		{"When a quoted CSS asset with spaces exists, it should resolve it", map[string]string{"style.css": "body { background: url(\"image one.png\"); }", "image one.png": "image"}, false},
		{"When a CSS URL escapes a character, it should resolve the decoded path", map[string]string{"style.css": "body { background: url(\"missing\\20 image.png\"); }"}, true},
		{"When an escaped CSS asset exists, it should resolve the decoded filename", map[string]string{"style.css": "body { background: url(\"image\\20 one.png\"); }", "image one.png": "image"}, false},
		{"When an import keyword is escaped, it should still validate its asset", map[string]string{"style.css": "@\\69mport \"missing style.css\";"}, true},
		{"When CSS image-set references a missing image, it should report the missing asset", map[string]string{"style.css": "body { background: image-set(\"one.png\" 1x, \"missing.png\" 2x); }", "one.png": "image"}, true},
		{"When a prefixed CSS image-set references a missing image, it should report the missing asset", map[string]string{"style.css": "body { background: -webkit-image-set(\"missing.png\" 1x); }"}, true},
		{"When CSS image-set candidates exist, it should resolve them without treating type() as a path", map[string]string{"style.css": "body { background: image-set(\"one.avif\" type(\"image/avif\") 1x, url(two.png) 2x); }", "one.avif": "image", "two.png": "image"}, false},
		{"When CSS image-set embeds an image from another website, it should reject external evidence", map[string]string{"style.css": "body { background: image-set(\"https://example.org/evidence.png\" 1x); }"}, true},
		{"When CSS url() embeds an image from another website, it should reject external evidence", map[string]string{"style.css": "body { background: url(\"https://example.org/evidence.png\"); }"}, true},
		{"When a string follows a closed image-set, it should not mistake it for an asset", map[string]string{"style.css": "p { background: image-set(\"one.png\" 1x); } p::after { content: \"missing.png\"; }", "one.png": "image"}, false},
		{"When a content string resembles a URL, it should not mistake prose for an asset", map[string]string{"style.css": "p::after { content: \"url(missing.png)\"; }"}, false},
		{"When a Markdown autolink is an email address, it should accept the mail reference", map[string]string{"README.md": "<team@example.org>"}, false},
		{"When a Markdown autolink uses a filesystem scheme, it should reject it", map[string]string{"README.md": "<file:///etc/passwd>"}, true},
		{"When a Markdown autolink uses an active scheme, it should reject it", map[string]string{"README.md": "<javascript:alert(1)>"}, true},
		{"When HTML srcset includes a missing image, it should check every candidate", map[string]string{"guide.html": "<img srcset='one.png 1x, missing.png 2x'>", "one.png": "image"}, true},
		{"When srcset contains an inline data image, it should preserve the comma inside its URL", map[string]string{"guide.html": "<img srcset='data:image/png;base64,aGVsbG8= 1x, two.png 2x'>", "two.png": "image"}, false},
		{"When an external citation is unavailable, it should not make a network request", map[string]string{"README.md": "[citation](https://unreachable.example.org/context)"}, false},
		{"When a bundle links to its plan, it should allow that cross-artifact citation", map[string]string{"reports/cntrlplane-7/metadata.yaml": htmlMetadata, "reports/cntrlplane-7/index.html": "<a href='../../plans/example.md'>Plan</a>", "reports/cntrlplane-7/scenario-1.html": "<h1>Scenario</h1>", "plans/example.md": planMetadata + planBody}, false},
		{"When a bundle embeds evidence outside its directory, it should reject the dependency", map[string]string{"reports/cntrlplane-7/metadata.yaml": htmlMetadata, "reports/cntrlplane-7/index.html": "<img src='../../shared.png'>", "reports/cntrlplane-7/scenario-1.html": "<h1>Scenario</h1>", "shared.png": "image"}, true},
		{"When a bundle links CSV evidence outside its directory, it should reject the dependency", map[string]string{"reports/cntrlplane-7/metadata.yaml": htmlMetadata, "reports/cntrlplane-7/index.html": "<a href='../../shared/results.csv'>Evidence</a>", "reports/cntrlplane-7/scenario-1.html": "<h1>Scenario</h1>", "shared/results.csv": "case,result"}, true},
		{"When an image is embedded from another website, it should reject external evidence", map[string]string{"guide.html": "<img src='https://example.org/evidence.png'>"}, true},
		{"When presentation resources use an allowed CDN, it should permit them", map[string]string{"guide.html": "<link rel='stylesheet' href='https://cdn.jsdelivr.net/style.css'>"}, false},
		{"When an HTML base tag changes resolution, it should reject ambiguous navigation", map[string]string{"guide.html": "<base href='https://example.org/'>"}, true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			g := NewWithT(t)
			result, err := artifactlint.Validate(writeFiles(t, tt.files))
			g.Expect(err).NotTo(HaveOccurred())
			g.Expect(result.HasErrors()).To(Equal(tt.wantError), "%+v", result.Findings)
		})
	}
	t.Run("When a symlink could escape the repository, it should refuse to follow it", func(t *testing.T) {
		g := NewWithT(t)
		root := writeFiles(t, map[string]string{"README.md": "[outside](outside.md)"})
		g.Expect(os.Symlink(filepath.Join(t.TempDir(), "outside.md"), filepath.Join(root, "outside.md"))).To(Succeed())
		result, err := artifactlint.Validate(root)
		g.Expect(err).NotTo(HaveOccurred())
		g.Expect(result.Findings).To(ContainElement(HaveField("Rule", "PATH")))
	})
}

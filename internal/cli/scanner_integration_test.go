package cli_test

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	. "github.com/onsi/gomega"

	"github.com/hypershift-community/test-results-verification/internal/cli"
)

func TestPinnedScannerEvidencePaths(t *testing.T) {
	tool, err := exec.LookPath("gitleaks")
	if err != nil {
		t.Skip("pinned scanner integration requires make install-tools")
	}
	version, err := exec.CommandContext(t.Context(), tool, "version").Output()
	if err != nil || strings.TrimSpace(string(version)) != cli.GitleaksVersion {
		t.Skip("pinned scanner integration requires Gitleaks " + cli.GitleaksVersion + " on PATH")
	}
	for _, name := range []string{"assets/evidence.js", "assets/bootstrap.js", "scripts/node_modules/helper.js"} {
		t.Run("When evidence uses an upstream-exempt filename, it should still detect credentials in "+name, func(t *testing.T) {
			g := NewWithT(t)
			root := t.TempDir()
			base := filepath.Join(root, "reports/cntrlplane-7")
			g.Expect(os.MkdirAll(filepath.Dir(filepath.Join(base, name)), 0o755)).To(Succeed())
			g.Expect(os.WriteFile(filepath.Join(base, "metadata.yaml"), []byte("jira_key: CNTRLPLANE-7\nformat: html-bundle\ndate: 2026-10-20\nverdict: fail\nscenario_count: 0\npass_count: 0\nci_verified: false\nhas_derived_markdown: false\n"), 0o600)).To(Succeed())
			g.Expect(os.WriteFile(filepath.Join(base, "index.html"), []byte("<h1>Evidence</h1>"), 0o600)).To(Succeed())
			alphabet := "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
			value := make([]byte, 36)
			for i := range value {
				value[i] = alphabet[(i*11+7)%len(alphabet)]
			}
			token := "ghp_" + string(value)
			g.Expect(os.WriteFile(filepath.Join(base, name), []byte("throw new Error('Report code must not execute');\nconst token = \""+token+"\"; // gitleaks:allow\n"), 0o600)).To(Succeed())
			var out, stderr bytes.Buffer
			g.Expect(cli.Run([]string{"--root", root, "--secrets"}, &out, &stderr)).To(Equal(1), stderr.String())
			g.Expect(out.String()).To(ContainSubstring("error SECRET"))
			g.Expect(out.String()).To(ContainSubstring("reports/cntrlplane-7/" + name + ":2: error SECRET"))
			g.Expect(out.String() + stderr.String()).NotTo(ContainSubstring(token))
		})
	}
}

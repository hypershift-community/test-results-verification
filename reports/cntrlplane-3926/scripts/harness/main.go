// Throwaway T6 harness for test/e2e/v2/util/mirrorregistry. Never committed (.work/ is gitignored).
//
//	go run ./.work/cntrlplane-3926/harness setup    -out DIR [-ca-cert F -ca-key F] [-timeout 20m]
//	go run ./.work/cntrlplane-3926/harness teardown [-timeout 15m]
//
// setup writes DIR/result.json (Result without the CA), DIR/ics.yaml (image content sources) and
// DIR/ca-only/ca.crt (CA only, usable as a skopeo --cert-dir). Only the kubeconfig context in $CTX
// (default "mgmt", set by env.sh) is used.
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"github.com/openshift/hypershift/test/e2e/v2/util/mirrorregistry"

	configv1 "github.com/openshift/api/config/v1"
	imagev1 "github.com/openshift/api/image/v1"
	routev1 "github.com/openshift/api/route/v1"

	appsv1 "k8s.io/api/apps/v1"
	batchv1 "k8s.io/api/batch/v1"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/client-go/tools/clientcmd"

	crclient "sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/yaml"
)

const (
	testImage    = "quay.io/libpod/registry@sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f"
	virtualRepo  = "mirror-source.hypershift-e2e.invalid/libpod/registry"
	cliNamespace = "openshift"
	cliStream    = "cli"
)

func main() {
	if len(os.Args) < 2 {
		fail(fmt.Errorf("usage: harness setup|teardown [flags]"))
	}
	fs := flag.NewFlagSet(os.Args[1], flag.ExitOnError)
	out := fs.String("out", "", "output directory (setup)")
	caCert := fs.String("ca-cert", "", "caller-supplied CA certificate PEM (setup, optional)")
	caKey := fs.String("ca-key", "", "caller-supplied CA private key PEM (setup, optional)")
	timeout := fs.Duration("timeout", 20*time.Minute, "overall deadline")
	_ = fs.Parse(os.Args[2:])

	ctx, cancel := context.WithTimeout(context.Background(), *timeout)
	defer cancel()
	client, err := newClient()
	if err != nil {
		fail(err)
	}

	start := time.Now()
	switch os.Args[1] {
	case "setup":
		err = setup(ctx, client, *out, *caCert, *caKey)
	case "teardown":
		var r *mirrorregistry.Registry
		// Teardown does not use the copier; any non-empty image passes validation.
		if r, err = mirrorregistry.New(client, mirrorregistry.Options{CopierImage: "unused"}); err == nil {
			err = r.Teardown(ctx)
		}
	default:
		err = fmt.Errorf("unknown command %q", os.Args[1])
	}
	log("%s finished in %s", os.Args[1], time.Since(start).Round(time.Second))
	if err != nil {
		fail(err)
	}
}

func setup(ctx context.Context, client crclient.Client, out, caCert, caKey string) error {
	if out == "" {
		return fmt.Errorf("-out is required")
	}
	if (caCert == "") != (caKey == "") {
		return fmt.Errorf("-ca-cert and -ca-key must be set together")
	}
	copierImage, err := cliImage(ctx, client)
	if err != nil {
		return err
	}
	log("copier image: %s", copierImage)
	opts := mirrorregistry.Options{CopierImage: copierImage}
	if caCert != "" {
		pair := &mirrorregistry.KeyPair{}
		if pair.CertPEM, err = os.ReadFile(caCert); err != nil {
			return err
		}
		if pair.KeyPEM, err = os.ReadFile(caKey); err != nil {
			return err
		}
		opts.CA = pair
		log("using caller-supplied CA %s", caCert)
	}
	r, err := mirrorregistry.New(client, opts)
	if err != nil {
		return err
	}
	log("Setup started")
	res, err := r.Setup(ctx, mirrorregistry.MirrorRequest{Images: []mirrorregistry.ImageMapping{
		{From: testImage},
		{From: testImage, SourceRepository: virtualRepo},
	}})
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Join(out, "ca-only"), 0o700); err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(out, "ca-only", "ca.crt"), res.CABundlePEM, 0o600); err != nil {
		return err
	}
	ics, err := yaml.Marshal(res.ImageContentSources)
	if err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(out, "ics.yaml"), ics, 0o600); err != nil {
		return err
	}
	printable := *res
	printable.CABundlePEM = nil
	data, err := json.MarshalIndent(printable, "", "  ")
	if err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(out, "result.json"), append(data, '\n'), 0o600); err != nil {
		return err
	}
	fmt.Println(string(data))
	return nil
}

// cliImage resolves the openshift/cli ImageStream "latest" tag by digest (the approach planned for T7).
func cliImage(ctx context.Context, client crclient.Client) (string, error) {
	is := &imagev1.ImageStream{}
	if err := client.Get(ctx, crclient.ObjectKey{Namespace: cliNamespace, Name: cliStream}, is); err != nil {
		return "", fmt.Errorf("read ImageStream %s/%s: %w", cliNamespace, cliStream, err)
	}
	for _, tag := range is.Status.Tags {
		if tag.Tag == "latest" && len(tag.Items) > 0 && tag.Items[0].DockerImageReference != "" {
			return tag.Items[0].DockerImageReference, nil
		}
	}
	return "", fmt.Errorf("ImageStream %s/%s has no resolved latest tag", cliNamespace, cliStream)
}

// kubeContext returns the only kubeconfig context the harness talks to ($CTX, as exported by env.sh).
func kubeContext() string {
	if ctx := os.Getenv("CTX"); ctx != "" {
		return ctx
	}
	return "mgmt"
}

func newClient() (crclient.Client, error) {
	cfg, err := clientcmd.NewNonInteractiveDeferredLoadingClientConfig(
		clientcmd.NewDefaultClientConfigLoadingRules(),
		&clientcmd.ConfigOverrides{CurrentContext: kubeContext()},
	).ClientConfig()
	if err != nil {
		return nil, fmt.Errorf("load kubeconfig context %s: %w", kubeContext(), err)
	}
	scheme := runtime.NewScheme()
	for _, add := range []func(*runtime.Scheme) error{
		corev1.AddToScheme, appsv1.AddToScheme, batchv1.AddToScheme,
		routev1.AddToScheme, configv1.AddToScheme, imagev1.AddToScheme,
	} {
		if err := add(scheme); err != nil {
			return nil, err
		}
	}
	log("context %s → %s", kubeContext(), cfg.Host)
	return crclient.New(cfg, crclient.Options{Scheme: scheme})
}

func log(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "%s harness: %s\n", time.Now().Format("15:04:05"), fmt.Sprintf(format, args...))
}

func fail(err error) {
	log("ERROR: %v", err)
	os.Exit(1)
}

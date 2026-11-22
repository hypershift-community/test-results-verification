# T6 — Live validation results

Date: 2026/10/13  Cluster: mgmt (OCP 4.20.0, nested hosted cluster)  Branch/commit: `CNTRLPLANE-3926` @ `2432ffc8af`  Run by: @Nirshal

Keep table cells to one line. Put command output in the **Evidence** section below, under the matching step,
inside a fenced code block. Bugs: one row per bug in "Bugs found", with the fix commit.

**Verdict: PASS** — every check matched the expected results; no bugs found, no code changes needed.

| Step | Item | Result | Notes / exact values |
|------|------|--------|----------------------|
| 1 | Setup succeeds on a fresh namespace | OK | 55s (16:18:02 → 16:18:57), exit 0 |
| 1 | Copier image from `openshift/cli` ImageStream | OK | `quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:0a9d58f9…b39a5` (T7 lookup approach works) |
| 1 | `Result` fields (Host, InternalHost, Images, ICS) as expected | OK | Host = `$HOST`, InternalHost `mirror-registry.test-mirror-registry.svc:5000`, 2 Images (real + virtual SourceRef), 2 ICS sorted, 1 mirror each |
| 1 | Order: copy while writable → read-only → Route; no VIOLATION | OK | writable 16:18:10 → Job Complete 16:18:48 → readonly=true 16:18:52 → admitted 16:18:59; no VIOLATION |
| 2 | verify.sh (4 checks) | OK | 5/5 PASS (200 `{}` with CA, curl exit 60 without, both digests = source, push 405) |
| 2 | Serving cert SANs / issuer / CN | OK | CN `mirror-registry`; SANs Route host + 4 Service names; issuer = CA `hypershift-e2e-mirror-registry-ca` (valid 1 year) |
| 2 | Stored CA Secret == Result CA | OK | `cmp` equal |
| 2 | No leftover copy Job/Secret; config read-only; SCC restricted-v2 | OK | no Job, only `-ca`/`-tls` Secrets (+ OpenShift SA `*-dockercfg-*`, not ours); `enabled: true`; `restricted-v2`; PVC 20Gi `gp3-csi` |
| 3 | Second Setup succeeds | OK | 28s (16:59:32 → 17:00:00) |
| 3 | Route withdrawn before writes re-enabled; no VIOLATION | OK | route=none 16:59:37 while readonly=true; readonly=false only at 16:59:40; re-admitted 17:00:01 after read-only rollout |
| 3 | CA unchanged, Result unchanged | OK | `cmp` / `diff` equal |
| 3 | verify.sh after re-run | OK | 5/5 PASS (content served after a 2nd write/read-only cycle on the same PVC) |
| 4 | Teardown: namespace NotFound, PV gone | OK | 21s; ns NotFound; PV deleted. Post-teardown curl gives exit 60, not 503 (see Surprises) |
| 4 | Second Teardown returns nil | OK | 1s, no `ERROR:` line (namespace absent → nil) |
| 6 | Caller CAs generated (PKCS#8 keys) | OK | both `[PKCS#8 key header line]`, CN `hypershift-e2e-caller-ca{,2}` |
| 7 | Setup with caller CA: Result CA == stored CA == caller CA; verify | OK | 41s; both `cmp` equal; 5/5 PASS (PKCS#8 path accepted) |
| 8 | Setup without CA reuses stored caller CA; verify | OK | 42s; Result CA == caller CA; 5/5 PASS |
| 9 | Setup with different caller CA: rotation works, no VIOLATION, old CA rejected | OK | 36s; withdrawal under old CA OK; Result/stored CA == CA2; 5/5 PASS; old CA → curl exit 60 |
| 10 | Teardown | OK | 21s; ns NotFound; PV gone |

## Bugs found

None.

| # | Step | Symptom | Root cause | Fix commit |
|---|------|---------|------------|------------|

## Surprises / follow-ups (T7, T8, consuming stories)

- Step 4: after Teardown, `curl --cacert <our CA>` fails with exit 60 instead of returning 503. With no
  passthrough Route matching the SNI, the OpenShift router terminates TLS itself with the default ingress
  certificate, which our CA does not sign. 503 would only be visible with `-k`. Not a defect: the runbook
  expectation was wrong (now corrected). It is also how `waitEndpoint(exposed=false)` sees withdrawal (TLS
  failure → not OK).
- Step 3: the old registry pod shows `Failed(terminating)` during the read-only restart (phase Failed: the
  registry exits non-zero on SIGTERM). Harmless with `Recreate` + PVC; content survived (verify passed).
- Step 9: the old-CA curl line had a typo (`\;` made `echo` part of curl's arguments). The first curl error
  (exit 60 on `/v2/` with the old CA) is still the evidence needed; the extra `curl: (6)/(3)` lines are from the typo.
- Timings (small image, 2 copies): Setup 28–55s, Route withdrawal ~2s, read-only restart ~5–10s, Teardown 21s.
  Useful for budgeting T7 `PreCreate`; the 20-min harness deadline is generous for single images.
- The copy Job name is deterministic (`mirror-registry-copy-95da31410c`) and identical across re-runs; the
  previous Job is deleted first and resources are cleaned on success, so no leftovers.
- Harness prints `"CABundlePEM": null` (the field is nulled on purpose). Cosmetic, harness only.

## Evidence

### Step 1 — harness output and watch log

```text
From Terminal 1:
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) harness setup -out "$OUT/run1" 2>&1 | tee "$OUT/run1.log"
16:18:02 harness: context mgmt → https://api.mgmt.hypershift.example.com:6443
16:18:07 harness: copier image: quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:0a9d58f9d8dd969c7bd107319a2498a674fe4e6477185a44558f168d994b39a5
16:18:07 harness: Setup started
{
  "Host": "mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com",
  "InternalHost": "mirror-registry.test-mirror-registry.svc:5000",
  "CABundlePEM": null,
  "ImageContentSources": [
    {
      "source": "mirror-source.hypershift-e2e.invalid/libpod/registry",
      "mirrors": [
        "mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com/mirror-source.hypershift-e2e.invalid/libpod/registry"
      ]
    },
    {
      "source": "quay.io/libpod/registry",
      "mirrors": [
        "mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com/quay.io/libpod/registry"
      ]
    }
  ],
  "Images": [
    {
      "From": "quay.io/libpod/registry@sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f",
      "SourceRef": "quay.io/libpod/registry@sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f",
      "MirrorRef": "mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com/quay.io/libpod/registry@sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f"
    },
    {
      "From": "quay.io/libpod/registry@sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f",
      "SourceRef": "mirror-source.hypershift-e2e.invalid/libpod/registry@sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f",
      "MirrorRef": "mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com/mirror-source.hypershift-e2e.invalid/libpod/registry@sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f"
    }
  ]
}
16:18:57 harness: setup finished in 55s

From terminal 2:
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) .work/cntrlplane-3926/harness/watch.sh "$OUT/watch-run1.log"
16:17:33 route=none readonly=- deploy=none pods=[] jobs=[]
16:18:10 route=none readonly=false deploy=gen1/obs1/avail0 pods=[d5k44:Pending] jobs=[]
16:18:25 route=none readonly=false deploy=gen1/obs1/avail1 pods=[d5k44:Running] jobs=[]
16:18:31 route=none readonly=false deploy=gen1/obs1/avail1 pods=[d5k44:Running] jobs=[mirror-registry-copy-95da31410c:Running]
16:18:48 route=none readonly=false deploy=gen1/obs1/avail1 pods=[d5k44:Running] jobs=[mirror-registry-copy-95da31410c:SuccessCriteriaMet,Complete]
16:18:52 route=none readonly=true deploy=gen2/obs2/avail0 pods=[2jd2d:Pending] jobs=[]
16:18:54 route=none readonly=true deploy=gen2/obs2/avail1 pods=[2jd2d:Running] jobs=[]
16:18:59 route=admitted readonly=true deploy=gen2/obs2/avail1 pods=[2jd2d:Running] jobs=[]
^C
```

### Step 2 — verify and cluster checks

```text
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) .work/cntrlplane-3926/harness/verify.sh "$OUT/run1"
PASS  anonymous /v2/ with CA → {} 200
PASS  TLS refused without CA (curl exit 60)
PASS  digest preserved quay.io/libpod/registry
PASS  digest preserved mirror-source.hypershift-e2e.invalid/libpod/registry
PASS  push via Route rejected (405)
verify: 0 failure(s)
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) cat "$OUT/run1/ics.yaml"
- mirrors:
  - mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com/mirror-source.hypershift-e2e.invalid/libpod/registry
  source: mirror-source.hypershift-e2e.invalid/libpod/registry
- mirrors:
  - mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com/quay.io/libpod/registry
  source: quay.io/libpod/registry
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) openssl x509 -in "$OUT/run1/ca-only/ca.crt" -noout -subject -enddate
subject=OU=hypershift-e2e-mirror-registry, CN=hypershift-e2e-mirror-registry-ca
notAfter=Oct 13 14:18:07 2027 GMT
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) openssl s_client -connect "${HOST}:443" -servername "$HOST" -CAfile "$OUT/run1/ca-only/ca.crt" </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer -ext subjectAltName
subject=OU=hypershift-e2e-mirror-registry, CN=mirror-registry
issuer=OU=hypershift-e2e-mirror-registry, CN=hypershift-e2e-mirror-registry-ca
X509v3 Subject Alternative Name:
    DNS:mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com, DNS:mirror-registry, DNS:mirror-registry.test-mirror-registry, DNS:mirror-registry.test-mirror-registry.svc, DNS:mirror-registry.test-mirror-registry.svc.cluster.local
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) k -n "$NS" get secret "${NAME}-ca" -o jsonpath='{.data.ca\.crt}' | base64 -d | cmp - "$OUT/run1/ca-only/ca.crt" && echo "stored CA == Result CA"
stored CA == Result CA
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) k -n "$NS" get job,secret,route,pvc
NAME                              TYPE                      DATA   AGE
secret/builder-dockercfg-pgpcg    kubernetes.io/dockercfg   1      35m
secret/default-dockercfg-z4qm6    kubernetes.io/dockercfg   1      35m
secret/deployer-dockercfg-2lhd7   kubernetes.io/dockercfg   1      35m
secret/mirror-registry-ca         Opaque                    2      35m
secret/mirror-registry-tls        kubernetes.io/tls         2      35m

NAME                                       HOST/PORT                                                                                            PATH   SERVICES          PORT    TERMINATION        WILDCARD
route.route.openshift.io/mirror-registry   mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com          mirror-registry   https   passthrough/None   None

NAME                                    STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
persistentvolumeclaim/mirror-registry   Bound    pvc-00ea6683-83e6-41a1-bdf9-338b9f10fe55   20Gi       RWO            gp3-csi        <unset>                 35m
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) k -n "$NS" get cm "${NAME}-config" -o jsonpath='{.data.config\.yml}' | grep -A1 'readonly:'
    readonly:
      enabled: true
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) k -n "$NS" get pod -l app.kubernetes.io/name="$NAME" -o jsonpath='{.items[0].metadata.annotations.openshift\.io/scc}{"\n"}'
restricted-v2
```

### Step 3 — second Setup, watch log, comparisons

```text
From terminal 1:
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) harness setup -out "$OUT/run2" 2>&1 | tee "$OUT/run2.log"
16:59:32 harness: context mgmt → https://api.mgmt.hypershift.example.com:6443
16:59:35 harness: copier image: quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:0a9d58f9d8dd969c7bd107319a2498a674fe4e6477185a44558f168d994b39a5
16:59:35 harness: Setup started
{
  "Host": "mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com",
  "InternalHost": "mirror-registry.test-mirror-registry.svc:5000",
  "CABundlePEM": null,
  "ImageContentSources": [
    {
      "source": "mirror-source.hypershift-e2e.invalid/libpod/registry",
      "mirrors": [
        "mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com/mirror-source.hypershift-e2e.invalid/libpod/registry"
      ]
    },
    {
      "source": "quay.io/libpod/registry",
      "mirrors": [
        "mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com/quay.io/libpod/registry"
      ]
    }
  ],
  "Images": [
    {
      "From": "quay.io/libpod/registry@sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f",
      "SourceRef": "quay.io/libpod/registry@sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f",
      "MirrorRef": "mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com/quay.io/libpod/registry@sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f"
    },
    {
      "From": "quay.io/libpod/registry@sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f",
      "SourceRef": "mirror-source.hypershift-e2e.invalid/libpod/registry@sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f",
      "MirrorRef": "mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com/mirror-source.hypershift-e2e.invalid/libpod/registry@sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f"
    }
  ]
}
17:00:00 harness: setup finished in 28s
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) cmp "$OUT/run1/ca-only/ca.crt" "$OUT/run2/ca-only/ca.crt" && echo "CA unchanged"
CA unchanged
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) diff "$OUT/run1/result.json" "$OUT/run2/result.json" && echo "Result unchanged"
Result unchanged
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) .work/cntrlplane-3926/harness/verify.sh "$OUT/run2"
PASS  anonymous /v2/ with CA → {} 200
PASS  TLS refused without CA (curl exit 60)
PASS  digest preserved quay.io/libpod/registry
PASS  digest preserved mirror-source.hypershift-e2e.invalid/libpod/registry
PASS  push via Route rejected (405)
verify: 0 failure(s)

From terminal 2:
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) .work/cntrlplane-3926/harness/watch.sh "$OUT/watch-run2.log"
16:59:16 route=admitted readonly=true deploy=gen2/obs2/avail1 pods=[2jd2d:Running] jobs=[]
16:59:37 route=none readonly=true deploy=gen2/obs2/avail1 pods=[2jd2d:Running] jobs=[]
16:59:40 route=none readonly=false deploy=gen3/obs3/avail0 pods=[pm2q2:Running] jobs=[]
16:59:42 route=none readonly=false deploy=gen3/obs3/avail1 pods=[pm2q2:Running] jobs=[]
16:59:44 route=none readonly=false deploy=gen3/obs3/avail1 pods=[pm2q2:Running] jobs=[mirror-registry-copy-95da31410c:Running]
16:59:48 route=none readonly=false deploy=gen3/obs3/avail1 pods=[pm2q2:Running] jobs=[mirror-registry-copy-95da31410c:SuccessCriteriaMet,Complete]
16:59:50 route=none readonly=true deploy=gen4/obs4/avail0 pods=[pm2q2:Failed(terminating)] jobs=[]
16:59:52 route=none readonly=true deploy=gen4/obs4/avail0 pods=[wcrcf:Pending] jobs=[]
16:59:58 route=none readonly=true deploy=gen4/obs4/avail1 pods=[wcrcf:Running] jobs=[]
17:00:01 route=admitted readonly=true deploy=gen4/obs4/avail1 pods=[wcrcf:Running] jobs=[]
^C
```

### Step 4 — teardown

```text
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) k -n "$NS" get events --sort-by=.lastTimestamp | tail -30
46m         Normal   SuccessfulCreate         replicaset/mirror-registry-7b568df84        Created pod: mirror-registry-7b568df84-2jd2d
46m         Normal   ScalingReplicaSet        deployment/mirror-registry                  Scaled up replica set mirror-registry-7b568df84 from 0 to 1
46m         Normal   Started                  pod/mirror-registry-7b568df84-2jd2d         Started container registry
46m         Normal   Created                  pod/mirror-registry-7b568df84-2jd2d         Created container: registry
46m         Normal   AddedInterface           pod/mirror-registry-7b568df84-2jd2d         Add eth0 [10.132.0.155/23] from ovn-kubernetes
46m         Normal   Pulled                   pod/mirror-registry-7b568df84-2jd2d         Container image "quay.io/libpod/registry@sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f" already present on machine
6m13s       Normal   ScalingReplicaSet        deployment/mirror-registry                  Scaled up replica set mirror-registry-6588996598 from 0 to 1
6m13s       Normal   SuccessfulCreate         replicaset/mirror-registry-6588996598       Created pod: mirror-registry-6588996598-pm2q2
6m13s       Normal   ScalingReplicaSet        deployment/mirror-registry                  Scaled down replica set mirror-registry-7b568df84 from 1 to 0
6m13s       Normal   Killing                  pod/mirror-registry-7b568df84-2jd2d         Stopping container registry
6m13s       Normal   SuccessfulDelete         replicaset/mirror-registry-7b568df84        Deleted pod: mirror-registry-7b568df84-2jd2d
6m12s       Normal   Started                  pod/mirror-registry-6588996598-pm2q2        Started container registry
6m12s       Normal   Created                  pod/mirror-registry-6588996598-pm2q2        Created container: registry
6m12s       Normal   AddedInterface           pod/mirror-registry-6588996598-pm2q2        Add eth0 [10.132.0.156/23] from ovn-kubernetes
6m12s       Normal   Pulled                   pod/mirror-registry-6588996598-pm2q2        Container image "quay.io/libpod/registry@sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f" already present on machine
6m8s        Normal   SuccessfulCreate         job/mirror-registry-copy-95da31410c         Created pod: mirror-registry-copy-95da31410c-srfz9
6m7s        Normal   Created                  pod/mirror-registry-copy-95da31410c-srfz9   Created container: copy
6m7s        Normal   Started                  pod/mirror-registry-copy-95da31410c-srfz9   Started container copy
6m7s        Normal   Pulled                   pod/mirror-registry-copy-95da31410c-srfz9   Container image "quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:0a9d58f9d8dd969c7bd107319a2498a674fe4e6477185a44558f168d994b39a5" already present on machine
6m7s        Normal   AddedInterface           pod/mirror-registry-copy-95da31410c-srfz9   Add eth0 [10.133.0.19/23] from ovn-kubernetes
6m3s        Normal   Completed                job/mirror-registry-copy-95da31410c         Job completed
6m2s        Normal   ScalingReplicaSet        deployment/mirror-registry                  Scaled down replica set mirror-registry-6588996598 from 1 to 0
6m1s        Normal   Killing                  pod/mirror-registry-6588996598-pm2q2        Stopping container registry
6m1s        Normal   SuccessfulDelete         replicaset/mirror-registry-6588996598       Deleted pod: mirror-registry-6588996598-pm2q2
6m          Normal   SuccessfulCreate         replicaset/mirror-registry-5c7c797f76       Created pod: mirror-registry-5c7c797f76-wcrcf
6m          Normal   ScalingReplicaSet        deployment/mirror-registry                  Scaled up replica set mirror-registry-5c7c797f76 from 0 to 1
5m55s       Normal   Started                  pod/mirror-registry-5c7c797f76-wcrcf        Started container registry
5m55s       Normal   AddedInterface           pod/mirror-registry-5c7c797f76-wcrcf        Add eth0 [10.132.0.157/23] from ovn-kubernetes
5m55s       Normal   Pulled                   pod/mirror-registry-5c7c797f76-wcrcf        Container image "quay.io/libpod/registry@sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f" already present on machine
5m55s       Normal   Created                  pod/mirror-registry-5c7c797f76-wcrcf        Created container: registry
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) harness teardown 2>&1 | tee "$OUT/teardown1.log"
17:06:11 harness: context mgmt → https://api.mgmt.hypershift.example.com:6443
17:06:32 harness: teardown finished in 21s
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) k get ns "$NS"
Error from server (NotFound): namespaces "test-mirror-registry" not found
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) k get pv | grep "${NS}/${NAME}" || echo "PV gone (reclaimPolicy Delete)"
No resources found
PV gone (reclaimPolicy Delete)
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) curl -sS -o /dev/null -w '%{http_code}\n' --cacert "$OUT/run1/ca-only/ca.crt" "https://${HOST}/v2/"
curl: (60) SSL certificate problem: unable to get local issuer certificate
More details here: https://curl.se/docs/sslcerts.html

curl failed to verify the legitimacy of the server and therefore could not
establish a secure connection to it. To learn more about this situation and
how to fix it, please visit the web page mentioned above.
000
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) harness teardown 2>&1 | tee "$OUT/teardown2.log"
17:07:40 harness: context mgmt → https://api.mgmt.hypershift.example.com:6443
17:07:41 harness: teardown finished in 1s
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926)
```

### Steps 6–9 — caller-supplied CA

```text
From Terminal 1:
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) for ca in caller-ca caller-ca2; do
  mkdir -p "$OUT/$ca" && (
    cd "$OUT/$ca"
    openssl genrsa -out ca.key 4096 2>/dev/null
    openssl req -x509 -new -key ca.key -days 30 -subj "/CN=hypershift-e2e-${ca}" \
      -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign" -out ca.crt
    head -1 ca.key; openssl x509 -in ca.crt -noout -subject
  )
done
[PKCS#8 key header line]
subject=CN=hypershift-e2e-caller-ca
[PKCS#8 key header line]
subject=CN=hypershift-e2e-caller-ca2
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) harness setup -out "$OUT/runB1" -ca-cert "$OUT/caller-ca/ca.crt" -ca-key "$OUT/caller-ca/ca.key" 2>&1 | tee "$OUT/runB1.log"
17:12:21 harness: context mgmt → https://api.mgmt.hypershift.example.com:6443
17:12:22 harness: copier image: quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:0a9d58f9d8dd969c7bd107319a2498a674fe4e6477185a44558f168d994b39a5
17:12:22 harness: using caller-supplied CA ~/hypershift/.work/cntrlplane-3926/harness/out/caller-ca/ca.crt
17:12:22 harness: Setup started
{
  "Host": "mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com",
  "InternalHost": "mirror-registry.test-mirror-registry.svc:5000",
  "CABundlePEM": null,
  "ImageContentSources": [
    {
      "source": "mirror-source.hypershift-e2e.invalid/libpod/registry",
      "mirrors": [
        "mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com/mirror-source.hypershift-e2e.invalid/libpod/registry"
      ]
    },
    {
      "source": "quay.io/libpod/registry",
      "mirrors": [
        "mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com/quay.io/libpod/registry"
      ]
    }
  ],
  "Images": [
    {
      "From": "quay.io/libpod/registry@sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f",
      "SourceRef": "quay.io/libpod/registry@sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f",
      "MirrorRef": "mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com/quay.io/libpod/registry@sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f"
    },
    {
      "From": "quay.io/libpod/registry@sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f",
      "SourceRef": "mirror-source.hypershift-e2e.invalid/libpod/registry@sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f",
      "MirrorRef": "mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com/mirror-source.hypershift-e2e.invalid/libpod/registry@sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f"
    }
  ]
}
17:13:02 harness: setup finished in 41s
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) cmp "$OUT/caller-ca/ca.crt" "$OUT/runB1/ca-only/ca.crt" && echo "Result CA == caller CA"
Result CA == caller CA
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) k -n "$NS" get secret "${NAME}-ca" -o jsonpath='{.data.ca\.crt}' | base64 -d | cmp - "$OUT/caller-ca/ca.crt" && echo "stored CA == caller CA"
stored CA == caller CA
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) .work/cntrlplane-3926/harness/verify.sh "$OUT/runB1"
PASS  anonymous /v2/ with CA → {} 200
PASS  TLS refused without CA (curl exit 60)
PASS  digest preserved quay.io/libpod/registry
PASS  digest preserved mirror-source.hypershift-e2e.invalid/libpod/registry
PASS  push via Route rejected (405)
verify: 0 failure(s)
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) harness setup -out "$OUT/runB2" 2>&1 | tee "$OUT/runB2.log"
17:14:07 harness: context mgmt → https://api.mgmt.hypershift.example.com:6443
17:14:08 harness: copier image: quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:0a9d58f9d8dd969c7bd107319a2498a674fe4e6477185a44558f168d994b39a5
17:14:08 harness: Setup started
{
  "Host": "mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com",
  "InternalHost": "mirror-registry.test-mirror-registry.svc:5000",
  "CABundlePEM": null,
  "ImageContentSources": [
    {
      "source": "mirror-source.hypershift-e2e.invalid/libpod/registry",
      "mirrors": [
        "mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com/mirror-source.hypershift-e2e.invalid/libpod/registry"
      ]
    },
    {
      "source": "quay.io/libpod/registry",
      "mirrors": [
        "mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com/quay.io/libpod/registry"
      ]
    }
  ],
  "Images": [
    {
      "From": "quay.io/libpod/registry@sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f",
      "SourceRef": "quay.io/libpod/registry@sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f",
      "MirrorRef": "mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com/quay.io/libpod/registry@sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f"
    },
    {
      "From": "quay.io/libpod/registry@sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f",
      "SourceRef": "mirror-source.hypershift-e2e.invalid/libpod/registry@sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f",
      "MirrorRef": "mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com/mirror-source.hypershift-e2e.invalid/libpod/registry@sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f"
    }
  ]
}
17:14:49 harness: setup finished in 42s
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) cmp "$OUT/caller-ca/ca.crt" "$OUT/runB2/ca-only/ca.crt" && echo "stored caller CA reused"
stored caller CA reused
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) .work/cntrlplane-3926/harness/verify.sh "$OUT/runB2"
PASS  anonymous /v2/ with CA → {} 200
PASS  TLS refused without CA (curl exit 60)
PASS  digest preserved quay.io/libpod/registry
PASS  digest preserved mirror-source.hypershift-e2e.invalid/libpod/registry
PASS  push via Route rejected (405)
verify: 0 failure(s)
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) harness setup -out "$OUT/runB3" -ca-cert "$OUT/caller-ca2/ca.crt" -ca-key "$OUT/caller-ca2/ca.key" 2>&1 | tee "$OUT/runB3.log"
17:16:32 harness: context mgmt → https://api.mgmt.hypershift.example.com:6443
17:16:33 harness: copier image: quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:0a9d58f9d8dd969c7bd107319a2498a674fe4e6477185a44558f168d994b39a5
17:16:33 harness: using caller-supplied CA ~/hypershift/.work/cntrlplane-3926/harness/out/caller-ca2/ca.crt
17:16:33 harness: Setup started
{
  "Host": "mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com",
  "InternalHost": "mirror-registry.test-mirror-registry.svc:5000",
  "CABundlePEM": null,
  "ImageContentSources": [
    {
      "source": "mirror-source.hypershift-e2e.invalid/libpod/registry",
      "mirrors": [
        "mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com/mirror-source.hypershift-e2e.invalid/libpod/registry"
      ]
    },
    {
      "source": "quay.io/libpod/registry",
      "mirrors": [
        "mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com/quay.io/libpod/registry"
      ]
    }
  ],
  "Images": [
    {
      "From": "quay.io/libpod/registry@sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f",
      "SourceRef": "quay.io/libpod/registry@sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f",
      "MirrorRef": "mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com/quay.io/libpod/registry@sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f"
    },
    {
      "From": "quay.io/libpod/registry@sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f",
      "SourceRef": "mirror-source.hypershift-e2e.invalid/libpod/registry@sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f",
      "MirrorRef": "mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com/mirror-source.hypershift-e2e.invalid/libpod/registry@sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f"
    }
  ]
}
17:17:09 harness: setup finished in 36s
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) cmp "$OUT/caller-ca2/ca.crt" "$OUT/runB3/ca-only/ca.crt" && echo "Result CA == caller CA2"
Result CA == caller CA2
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) k -n "$NS" get secret "${NAME}-ca" -o jsonpath='{.data.ca\.crt}' | base64 -d | cmp - "$OUT/caller-ca2/ca.crt" && echo "stored CA replaced by CA2"
stored CA replaced by CA2
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) .work/cntrlplane-3926/harness/verify.sh "$OUT/runB3"
PASS  anonymous /v2/ with CA → {} 200
PASS  TLS refused without CA (curl exit 60)
PASS  digest preserved quay.io/libpod/registry
PASS  digest preserved mirror-source.hypershift-e2e.invalid/libpod/registry
PASS  push via Route rejected (405)
verify: 0 failure(s)
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) curl -sS -o /dev/null --cacert "$OUT/caller-ca/ca.crt" "https://${HOST}/v2/"\; echo "exit=$? (expected 60: old CA no longer trusted)"
curl: (60) SSL certificate problem: unable to get local issuer certificate
More details here: https://curl.se/docs/sslcerts.html

curl failed to verify the legitimacy of the server and therefore could not
establish a secure connection to it. To learn more about this situation and
how to fix it, please visit the web page mentioned above.
curl: (6) Could not resolve host: echo
curl: (3) URL rejected: Malformed input to a URL function

From Terminal 2:
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) .work/cntrlplane-3926/harness/watch.sh "$OUT/watch-runB3.log"
17:16:23 route=admitted readonly=true deploy=gen4/obs4/avail1 pods=[68cb6:Running] jobs=[]
17:16:36 route=none readonly=true deploy=gen4/obs4/avail1 pods=[68cb6:Running] jobs=[]
17:16:38 route=none readonly=false deploy=gen5/obs5/avail0 pods=[g7lbd:Pending] jobs=[]
17:16:46 route=none readonly=false deploy=gen5/obs5/avail1 pods=[g7lbd:Running] jobs=[]
17:16:49 route=none readonly=false deploy=gen5/obs5/avail1 pods=[g7lbd:Running] jobs=[mirror-registry-copy-95da31410c:Running]
17:16:53 route=none readonly=false deploy=gen5/obs5/avail1 pods=[g7lbd:Running] jobs=[mirror-registry-copy-95da31410c:SuccessCriteriaMet,Complete]
17:16:59 route=none readonly=true deploy=gen6/obs6/avail0 pods=[l2jb8:Pending] jobs=[]
17:17:07 route=none readonly=true deploy=gen6/obs6/avail1 pods=[l2jb8:Running] jobs=[]
17:17:10 route=admitted readonly=true deploy=gen6/obs6/avail1 pods=[l2jb8:Running] jobs=[]
^C
```

### Step 10 — teardown

```text
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) harness teardown 2>&1 | tee "$OUT/teardownB.log"
17:19:46 harness: context mgmt → https://api.mgmt.hypershift.example.com:6443
17:20:07 harness: teardown finished in 21s
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) k get ns "$NS"
Error from server (NotFound): namespaces "test-mirror-registry" not found
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) k get pv | grep "${NS}/${NAME}" || echo "PV gone"
No resources found
PV gone
```

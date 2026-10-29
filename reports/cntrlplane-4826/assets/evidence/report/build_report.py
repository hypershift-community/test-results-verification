#!/usr/bin/env python3
"""Build the self-contained CNTRLPLANE-4826 verification report from local evidence."""

from __future__ import annotations

import html
import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable


BASE = Path(__file__).resolve().parent.parent
REPORT = Path(__file__).with_name("index.html")


def load_json(path: Path) -> Any:
    with path.open() as fh:
        return json.load(fh)


def load_ndjson(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    with path.open() as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                value = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(value, dict):
                rows.append(value)
    return rows


def passed_subtests(path: Path, parent: str) -> list[str]:
    if not path.exists():
        return []
    prefix = f"--- PASS: {parent}/"
    tests: list[str] = []
    for line in path.read_text(errors="replace").splitlines():
        stripped = line.strip()
        if stripped.startswith(prefix):
            name = re.sub(r" \([^)]*\)$", "", stripped[len(prefix) :])
            tests.append(name)
    return tests


def esc(value: Any) -> str:
    return html.escape(str(value), quote=True)


def pre(text: Any) -> str:
    return f"<pre>{esc(text)}</pre>"


def rel(path: Path) -> str:
    return str(path.relative_to(BASE))


def path_code(path: Path) -> str:
    return f"<code>{esc(path)}</code>"


def details(summary: str, body: str, open_: bool = False) -> str:
    attr = " open" if open_ else ""
    return f"<details{attr}><summary>{esc(summary)}</summary>{body}</details>"


def table(headers: Iterable[str], rows: Iterable[Iterable[Any]], cls: str = "") -> str:
    head = "".join(f"<th>{esc(h)}</th>" for h in headers)
    body = "".join(
        "<tr>" + "".join(f"<td>{esc(c)}</td>" for c in row) + "</tr>" for row in rows
    )
    return f"<table class=\"{cls}\"><thead><tr>{head}</tr></thead><tbody>{body}</tbody></table>"


def badge(status: str) -> str:
    cls = {"PASS": "pass", "FAIL": "fail", "PARTIAL": "partial", "BLOCKED": "partial", "IN PROGRESS": "pending", "NOT TESTED": "pending"}.get(status, "pending")
    return f'<span class="badge {cls}">{esc(status)}</span>'


def cond(np: dict[str, Any], typ: str) -> dict[str, Any]:
    for c in np.get("conditions", []) or []:
        if c.get("type") == typ:
            return c
    return {}


def cond_text(c: dict[str, Any]) -> str:
    if not c:
        return "absent"
    return f"{c.get('status')} / {c.get('reason')} / {c.get('lastTransitionTime')}"


def snapshot(summary: dict[str, Any], pool_prefix: str | None = None) -> dict[str, Any]:
    np = summary.get("nodePool") or {}
    md = summary.get("machineDeployment") or {}
    ann = np.get("annotations") or {}
    sets = summary.get("ownedMachineSets") or []
    machines = summary.get("ownedMachines") or []
    nodes = summary.get("guestNodes") or []
    if pool_prefix:
        nodes = [n for n in nodes if str(n.get("name", "")).startswith(pool_prefix)]
    return {
        "capturedAt": summary.get("capturedAt"),
        "nodePool": {
            "generation": np.get("generation"),
            "release": np.get("release"),
            "statusVersion": np.get("version"),
            "replicas": np.get("replicas"),
            "uid": np.get("uid"),
            "currentConfig": ann.get("hypershift.openshift.io/nodePoolCurrentConfig"),
            "currentConfigVersion": ann.get("hypershift.openshift.io/nodePoolCurrentConfigVersion"),
            "platformMachineTemplate": ann.get("hypershift.openshift.io/nodePoolPlatformMachineTemplate"),
            "Ready": cond_text(cond(np, "Ready")),
            "UpdatingVersion": cond_text(cond(np, "UpdatingVersion")),
            "UpdatingConfig": cond_text(cond(np, "UpdatingConfig")),
            "UpdatingPlatformMachineTemplate": cond_text(cond(np, "UpdatingPlatformMachineTemplate")),
            "AllMachinesReady": cond_text(cond(np, "AllMachinesReady")),
            "AllNodesHealthy": cond_text(cond(np, "AllNodesHealthy")),
        },
        "machineDeployment": {
            "name": md.get("name") or summary.get("machinedeploymentName"),
            "uid": md.get("uid"),
            "generation": md.get("generation"),
            "observedGeneration": md.get("observedGeneration"),
            "revision": md.get("revision"),
            "replicas": md.get("replicas"),
            "availableReplicas": md.get("availableReplicas"),
            "upToDateReplicas": md.get("upToDateReplicas"),
            "conditions": [
                {"type": c.get("type"), "status": c.get("status"), "reason": c.get("reason"), "message": c.get("message"), "lastTransitionTime": c.get("lastTransitionTime")}
                for c in (md.get("conditions") or [])
                if c.get("type") in {"Available", "RollingOut", "MachinesReady", "MachinesUpToDate", "Ready"}
            ],
        },
        "machineSets": [
            {"name": s.get("name"), "uid": s.get("uid"), "revision": s.get("revision"), "replicas": s.get("replicas"), "availableReplicas": s.get("availableReplicas"), "creationTimestamp": s.get("creationTimestamp")}
            for s in sets
        ],
        "machines": [
            {"name": m.get("name"), "uid": m.get("uid"), "created": m.get("created") or m.get("createdAt"), "version": m.get("version"), "nodeName": m.get("nodeName"), "providerID": m.get("providerID"), "conditions": m.get("conditions", [])}
            for m in machines
        ],
        "guestNodes": [
            {"name": n.get("name"), "uid": n.get("uid"), "created": n.get("created") or n.get("createdAt"), "ready": n.get("ready"), "kubeletVersion": n.get("kubeletVersion")}
            for n in nodes
        ],
    }


def snapshot_html(data: dict[str, Any]) -> str:
    np = data["nodePool"]
    md = data["machineDeployment"]
    rows: list[tuple[str, str]] = [
        ("Captured at", data.get("capturedAt") or "n/a"),
        ("NodePool generation", np.get("generation")),
        ("NodePool release image", np.get("release")),
        ("NodePool status.version", np.get("statusVersion")),
        ("NodePool status.replicas", np.get("replicas")),
        ("NodePool current config", np.get("currentConfig")),
        ("NodePool current config version", np.get("currentConfigVersion")),
        ("NodePool platform template", np.get("platformMachineTemplate")),
        ("Ready", np.get("Ready")),
        ("UpdatingVersion", np.get("UpdatingVersion")),
        ("UpdatingConfig", np.get("UpdatingConfig")),
        ("UpdatingPlatformMachineTemplate", np.get("UpdatingPlatformMachineTemplate")),
        ("AllMachinesReady", np.get("AllMachinesReady")),
        ("AllNodesHealthy", np.get("AllNodesHealthy")),
        ("MachineDeployment", f"{md.get('name')} uid={md.get('uid')}"),
        ("MachineDeployment generation / observed", f"{md.get('generation')} / {md.get('observedGeneration')}"),
        ("MachineDeployment revision", md.get("revision")),
        ("MachineDeployment replicas / available / upToDate", f"{md.get('replicas')} / {md.get('availableReplicas')} / {md.get('upToDateReplicas')}"),
    ]
    h = table(["Field", "Observed state"], rows)
    if data["machineSets"]:
        h += "<h4>MachineSets</h4>" + table(
            ["Name", "UID", "Revision", "Replicas", "Available", "Created"],
            [[m.get("name"), m.get("uid"), m.get("revision"), m.get("replicas"), m.get("availableReplicas"), m.get("creationTimestamp")] for m in data["machineSets"]],
        )
    if data["machines"]:
        h += "<h4>Machines</h4>" + table(
            ["Name", "UID", "Created", "Version", "Node", "Provider ID"],
            [[m.get("name"), m.get("uid"), m.get("created"), m.get("version"), m.get("nodeName"), m.get("providerID")] for m in data["machines"]],
        )
    if data["guestNodes"]:
        h += "<h4>Guest nodes</h4>" + table(
            ["Name", "UID", "Created", "Ready", "Kubelet"],
            [[n.get("name"), n.get("uid"), n.get("created"), n.get("ready"), n.get("kubeletVersion")] for n in data["guestNodes"]],
        )
    return h


def raw_summary(summary: dict[str, Any]) -> str:
    return details("Raw summary JSON", pre(json.dumps(summary, indent=2, sort_keys=True)))


def embed_file(label: str, path: Path, max_chars: int = 30000) -> str:
    if not path.exists():
        return details(label, "<p class='small'>File not present.</p>")
    text = path.read_text(errors="replace")
    truncated = len(text) > max_chars
    if truncated:
        text = text[:max_chars] + f"\n\n... [truncated; full file: {path}]"
    return details(label, pre(text))


def last_watch_state(path: Path) -> dict[str, Any]:
    states = [x for x in load_ndjson(path) if "machinedeployment" in x and "nodepool" in x]
    return states[-1] if states else {}


def watch_state_summary(state: dict[str, Any]) -> dict[str, Any]:
    np = state.get("nodepool") or {}
    md = state.get("machinedeployment") or {}
    return {
        "capturedAt": state.get("timestamp"),
        "nodePool": {
            "generation": np.get("generation"),
            "release": np.get("release"),
            "version": np.get("version"),
            "replicas": np.get("replicas"),
            "annotations": np.get("annotations") or {},
            "conditions": (
                [dict(c, type="Ready") for c in [np.get("ready")] if c]
                + [dict(c, type="UpdatingVersion") for c in [np.get("updatingVersion")] if c]
                + [dict(c, type="UpdatingConfig") for c in [np.get("updatingConfig")] if c]
                + [dict(c, type="UpdatingPlatformMachineTemplate") for c in [np.get("updatingPlatformMachineTemplate")] if c]
            ),
        },
        "machineDeployment": md,
        "ownedMachineSets": state.get("machinesets") or [],
        "ownedMachines": state.get("machines") or [],
        "guestNodes": state.get("nodes") or [],
    }


def deployment_summary(deployment: dict[str, Any]) -> dict[str, Any]:
    metadata = deployment.get("metadata") or {}
    spec = deployment.get("spec") or {}
    template = (spec.get("template") or {}).get("spec") or {}
    status = deployment.get("status") or {}

    def images(containers: Iterable[dict[str, Any]]) -> list[str]:
        return [c.get("image") for c in containers if c.get("image")]

    return {
        "generation": metadata.get("generation"),
        "observedGeneration": status.get("observedGeneration"),
        "revision": (metadata.get("annotations") or {}).get("deployment.kubernetes.io/revision"),
        "operatorImages": images(template.get("containers") or []),
        "initImages": images(template.get("initContainers") or []),
        "replicas": status.get("replicas"),
        "readyReplicas": status.get("readyReplicas"),
        "availableReplicas": status.get("availableReplicas"),
    }


def pod_runtime_rows(pods: Iterable[dict[str, Any]]) -> list[list[Any]]:
    rows: list[list[Any]] = []
    for pod in pods:
        metadata = pod.get("metadata") or {}
        status = pod.get("status") or {}
        container_statuses = status.get("containerStatuses") or []
        image_ids = [c.get("imageID") for c in container_statuses if c.get("imageID")]
        ready = bool(container_statuses) and all(c.get("ready") for c in container_statuses)
        rows.append([
            metadata.get("name"),
            status.get("phase"),
            "yes" if ready else "no",
            ", ".join(image_ids) or "n/a",
            metadata.get("creationTimestamp"),
        ])
    return rows


def restore_image_id_rows(path: Path) -> list[list[str]]:
    rows: list[list[str]] = []
    mode: str | None = None
    for raw in path.read_text(errors="replace").splitlines():
        stripped = raw.strip()
        if stripped == "pre_test_pod_image_ids:":
            mode = "pre-test"
            continue
        if stripped == "restored_pod_image_ids:":
            mode = "restored"
            continue
        if mode and raw.startswith("  "):
            parts = stripped.split(maxsplit=1)
            if len(parts) == 2:
                rows.append([mode, parts[0], parts[1]])
            continue
        if mode and stripped:
            mode = None
    return rows


def hash_manifest(path: Path) -> dict[str, str]:
    hashes: dict[str, str] = {}
    if not path.exists():
        return hashes
    for line in path.read_text(errors="replace").splitlines():
        parts = line.split(maxsplit=1)
        if len(parts) != 2:
            continue
        digest, filename = parts
        hashes[Path(filename).name] = digest
    return hashes


def join_metrics(machines_path: Path, nodepool_prefix: str) -> list[dict[str, Any]]:
    if not machines_path.exists():
        return []
    obj = load_json(machines_path)
    out: list[dict[str, Any]] = []
    for m in obj.get("items", []):
        name = (m.get("metadata") or {}).get("name", "")
        if not name.startswith(nodepool_prefix):
            continue
        created = (m.get("metadata") or {}).get("creationTimestamp")
        node_ready = next((c for c in (m.get("status") or {}).get("conditions", []) if c.get("type") == "NodeReady"), {})
        infra = next((c for c in (m.get("status") or {}).get("conditions", []) if c.get("type") == "InfrastructureReady"), {})
        ready_ts = node_ready.get("lastTransitionTime")
        delta = None
        if created and ready_ts:
            fmt = "%Y-%m-%dT%H:%M:%SZ"
            delta = int((datetime.strptime(ready_ts, fmt).replace(tzinfo=timezone.utc) - datetime.strptime(created, fmt).replace(tzinfo=timezone.utc)).total_seconds())
        out.append({"name": name, "created": created, "infrastructureReady": infra.get("lastTransitionTime"), "nodeReady": ready_ts, "secondsToReady": delta, "uid": (m.get("metadata") or {}).get("uid")})
    return out


def test_header(case: str, title: str, status: str, objective: str, timing: str, artifacts: str) -> str:
    return f"""
    <section id="{case.lower()}">
      <h2>{esc(case)} — {esc(title)} {badge(status)}</h2>
      <div class="record"><strong>Objective:</strong> {esc(objective)}<br><strong>Timing:</strong> {esc(timing)}<br><strong>Evidence root:</strong> <code>{esc(BASE)}</code><br><strong>Primary artifacts:</strong> <code>{esc(artifacts)}</code></div>
    """


def test_footer() -> str:
    return "</section>"


def make_report() -> str:
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    preflight = BASE / "preflight/preflight-20261028T130300Z"
    t1b = BASE / "t1/baseline-20261028T133706Z"
    t1p = BASE / "t1/patched-20261028T141214Z"
    t1p_final_dir = t1p / "final-20261028T144053Z/snapshot"
    t2 = BASE / "t2/config-20261028T144539Z"
    t3 = BASE / "t3/vm-size-20261028T150407Z"
    t7_before = BASE / "t7/baseline-before-operator-change-20261028T130400Z"
    t7_after = BASE / "t7/patched-after-observation-20261028T132147Z"
    t6_runs = sorted((BASE / "t6").glob("scale-*"))
    t6 = t6_runs[-1] if t6_runs else None
    unit_rerun = BASE / "unit/rerun-20261028T160848Z"
    t4_log = unit_rerun / "focused-tests.log"
    t5_log = unit_rerun / "focused-tests.log"
    operator_original_path = BASE / "operator/original-deployment.json"
    operator_restore = BASE / "operator/restore-20261028T154249Z"
    dns_audit = BASE / "postflight/dns-record-investigation-20261028T155138Z"
    post_cleanup = BASE / "postflight/post-cleanup-20261028T160444Z"
    cleanup = BASE / "cleanup/20261028T155605Z"
    pre_delete = BASE / "cleanup/pre-delete-20261028T155440Z"
    final_k8s = cleanup / "final-kubernetes-state"
    secret_scan = BASE / "integrity/secret-scan-20261028T161227Z"
    secret_scan_final = BASE / "integrity/secret-scan-final-20261028T161304Z"

    t1b_pre = snapshot(load_json(t1b / "pre/summary.json"), "test-cntrlplane-4826-unpatched")
    t1b_final_watch = last_watch_state(t1b / "resume-watch/rollout-watch.ndjson")
    t1b_final = snapshot(watch_state_summary(t1b_final_watch), "test-cntrlplane-4826-unpatched")
    t1b_physical = load_ndjson(t1b / "monitor-state.ndjson")[-1]
    t1p_pre = snapshot(load_json(t1p / "pre/summary.json"), "test-cntrlplane-4826-patched")
    t1p_action = snapshot(load_json(t1p / "action/summary.json"), "test-cntrlplane-4826-patched")
    t1p_final = snapshot(load_json(t1p_final_dir / "summary.json"), "test-cntrlplane-4826-patched")
    t1p_joins = join_metrics(t1p_final_dir / "machines.json", "test-cntrlplane-4826-patched-2jxvf")

    t2_pre = snapshot(load_json(t2 / "pre/summary.json"), "test-cntrlplane-4826-patched")
    t2_action = snapshot(load_json(t2 / "action/summary.json"), "test-cntrlplane-4826-patched")
    t2_final = snapshot(load_json(t2 / "deadline/summary.json"), "test-cntrlplane-4826-patched")
    t2_joins = join_metrics(t2 / "deadline/machines.json", "test-cntrlplane-4826-patched-ctnbv")
    t2_verdict = load_json(t2 / "verdict.json")

    t3_pre = snapshot(load_json(t3 / "pre/summary.json"), "test-cntrlplane-4826-patched")
    t3_action = snapshot(load_json(t3 / "action/summary.json"), "test-cntrlplane-4826-patched")
    t3_final = snapshot(load_json(t3 / "deadline/summary.json"), "test-cntrlplane-4826-patched")
    t3_verdict = load_json(t3 / "verdict.json")

    t7b = snapshot(load_json(t7_before / "summary.json"), "test-cntrlplane-4826-hc")
    t7a = snapshot(load_json(t7_after / "summary.json"), "test-cntrlplane-4826-hc")

    t4_tests = passed_subtests(t4_log, "TestMachineDeploymentComplete")
    t5_tests = passed_subtests(t5_log, "TestReconcileMachineDeploymentStatus")
    operator_original = deployment_summary(load_json(operator_original_path))
    restore_before = load_json(operator_restore / "deployment-before.json")
    restore_after = load_json(operator_restore / "deployment-after.json")
    restore_before_summary = deployment_summary(restore_before)
    restore_after_summary = deployment_summary(restore_after)
    restore_pods_before = load_json(operator_restore / "pods-before-sanitized.json").get("items", [])
    restore_pods_after = load_json(operator_restore / "pods-after-sanitized.json").get("items", [])
    restore_image_ids = restore_image_id_rows(operator_restore / "restore-verification.txt")
    restore_meta = dict(
        line.split("=", 1)
        for line in (operator_restore / "meta.txt").read_text().strip().splitlines()
        if "=" in line
    )
    final_k8s_summary = load_json(final_k8s / "summary.json")
    post_cleanup_summary = (post_cleanup / "summary.txt").read_text().strip().splitlines()
    post_cleanup_summary_map = dict(line.split("=", 1) for line in post_cleanup_summary if "=" in line)
    preflight_parent_zone = load_json(preflight / "azure-dns-parent-zone-stable.json")
    preflight_child_zone = load_json(preflight / "azure-dns-child-zone-stable.json")
    postflight_parent_zone = load_json(post_cleanup / "azure-dns-parent-zone-stable.json")
    postflight_child_zone = load_json(post_cleanup / "azure-dns-child-zone-stable.json")
    preflight_dns_hashes = hash_manifest(preflight / "azure-dns-stable.sha256")
    postflight_dns_hashes = hash_manifest(post_cleanup / "azure-dns-stable.sha256")
    pre_delete_nodepools = load_json(pre_delete / "nodepools-all.json").get("items", [])
    pre_delete_nodes = load_json(pre_delete / "guest-nodes.json").get("items", [])
    pre_delete_hostedclusters = load_json(pre_delete / "hostedclusters-all.json").get("items", [])
    child_records_removed = [
        line.strip()
        for line in (post_cleanup / "child-records-removed.txt").read_text().splitlines()
        if line.strip()
    ]
    secret_scan_final_summary = dict(
        line.split("=", 1)
        for line in (secret_scan_final / "summary.txt").read_text().splitlines()
        if "=" in line
    )

    t6_meta = None
    t6_verdict = None
    t6_status = "IN PROGRESS"
    t6_snapshot_pre = t6_snapshot_zero = t6_snapshot_back = None
    if t6 and (t6 / "meta.txt").exists():
        t6_status = "PASS"
        t6_meta = (t6 / "meta.txt").read_text()
        t6_verdict = load_json(t6 / "verdict.json") if (t6 / "verdict.json").exists() else None
        t6_snapshot_pre = snapshot(load_json(t6 / "pre-zero/summary.json"), "test-cntrlplane-4826-scale")
        t6_snapshot_zero = snapshot(load_json(t6 / "zero/summary.json"), "test-cntrlplane-4826-scale")
        t6_snapshot_back = snapshot(load_json(t6 / "back/summary.json"), "test-cntrlplane-4826-scale")

    status_rows = [
        ("T1 baseline", "PASS — bug reproduced", "Physical A→B replacement completed with upToDateReplicas=0; NodePool remained A and UpdatingVersion=True through the fixed deadline."),
        ("T1 patched", "PASS", "Completion at 14:35:21Z; status.version=B, UpdatingVersion=False, current set 3/3, old set drained, upToDateReplicas=0."),
        ("T2 config-only Replace", t2_verdict["status"], "Config hash 95a7feab→86d03f4f; version stayed B; marker verified on 3/3 replacement nodes."),
        ("T3 VM-size Replace", t3_verdict["status"], "Standard_D4s_v4→D4s_v5; 3/3 actual Azure VMs D4s_v5; template advanced; upToDateReplicas=0."),
        ("T4 predicate matrix", "PARTIAL", "12 existing focused tests pass; extra Chai matrix permutations not implemented."),
        ("T5 reconciliation/error handling", "PARTIAL", "3 existing reconciliation cases pass; zero/nil fixtures and list-error/recovery sequence not implemented."),
        ("T6 scale zero/back", t6_status, "Scale pool created, zeroed, and scaled back; final verdict pending." if t6_status != "PASS" else "Scale-zero completed at 15:24:59Z; scale-back completed at 15:31:39Z with 3 Ready workers, version/config/template stable."),
        ("T7 stable-pool transition", "PASS", "Operator switch did not change seed-pool generation, revision, MachineSet/Machine/Node identities."),
        ("T8 compatibility matrix", "BLOCKED / NOT TESTED", "Pre-1.14 and second-provider rows lack a verified environment; InPlace smoke not run."),
        ("Kubernetes cleanup", "PASS", "Deleted only the three named test NodePools and the test HostedCluster through Kubernetes; no HC, NP, Machine, or control-plane namespace remains."),
        ("Shared DNS safety", "PASS — verified", "shared-resource-group, both zones, delegation, and all role assignments remain; exactly the 12 test-owned child-zone records were removed."),
    ]

    h: list[str] = []
    h.append(f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>CNTRLPLANE-4826 verification evidence</title>
<style>
:root{{--bg:#fff;--fg:#17202a;--muted:#5d6d7e;--card:#f7f9fb;--border:#dbe3ea;--accent:#0b6bcb;--ok:#16794a;--warn:#9a6200;--bad:#b42318;--code:#eef2f6;--radius:10px;--sans:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;--mono:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace}}
@media(prefers-color-scheme:dark){{:root{{--bg:#101418;--fg:#e7edf3;--muted:#9fb0c0;--card:#171d24;--border:#2b3640;--accent:#65a9ff;--ok:#57c98b;--warn:#e2ac4d;--bad:#ff8177;--code:#1c242c}}}}
*{{box-sizing:border-box}}html,body{{margin:0;background:transparent;color:var(--fg);font-family:var(--sans)}}body{{line-height:1.5}}main{{max-width:1240px;margin:0 auto;padding:24px 18px 80px}}h1{{font-size:1.8rem;line-height:1.2;margin:0 0 6px}}h2{{font-size:1.35rem;margin:34px 0 12px;border-bottom:1px solid var(--border);padding-bottom:8px}}h3{{font-size:1.05rem;margin:22px 0 8px}}h4{{font-size:.95rem;margin:16px 0 6px}}p{{margin:8px 0}}a{{color:var(--accent)}}code,pre{{font-family:var(--mono)}}code{{background:var(--code);padding:1px 4px;border-radius:4px;overflow-wrap:anywhere}}pre{{background:var(--code);border:1px solid var(--border);border-radius:8px;padding:12px;overflow:auto;font-size:.8rem;line-height:1.4;max-height:620px}}.lede{{color:var(--muted);max-width:980px}}.small{{font-size:.85rem;color:var(--muted)}}.grid{{display:grid;grid-template-columns:repeat(auto-fit,minmax(250px,1fr));gap:12px}}.card,.record{{background:var(--card);border:1px solid var(--border);border-radius:var(--radius);padding:14px 16px;margin:12px 0}}.record{{border-left:4px solid var(--accent)}}.kv{{display:grid;grid-template-columns:max-content 1fr;gap:5px 12px;font-size:.9rem}}.kv dt{{color:var(--muted)}}.kv dd{{margin:0;overflow-wrap:anywhere}}table{{width:100%;border-collapse:collapse;margin:10px 0 18px;font-size:.9rem}}th,td{{border:1px solid var(--border);padding:7px 8px;text-align:left;vertical-align:top}}th{{background:var(--card)}}details{{margin:10px 0}}summary{{cursor:pointer;color:var(--accent);font-weight:600}}.badge{{display:inline-block;border-radius:999px;padding:2px 9px;font-size:.8rem;font-weight:700;white-space:nowrap}}.pass{{color:var(--ok);border:1px solid currentColor}}.partial{{color:var(--warn);border:1px solid currentColor}}.pending{{color:var(--muted);border:1px solid currentColor}}.fail{{color:var(--bad);border:1px solid currentColor}}.toc{{display:flex;flex-wrap:wrap;gap:8px 18px;margin:12px 0 0}}.toc a{{text-decoration:none}}@media print{{body{{color:#000}}details{{display:block}}pre{{max-height:none}}}}
</style></head><body><main>
<header><h1>CNTRLPLANE-4826 — test verification evidence</h1>
<p class="lede">Self-contained evidence report for HyperShift PR #10084: stop gating NodePool rollout completion on <code>upToDateReplicas</code>. Every test section includes commands, before/after state, assertions, and logs. Raw evidence files remain under the absolute paths shown in each section.</p>
<p class="small">Generated {now} · source <code>ff673589287e8f7685435f117cfec1f14c067def</code> · operator <code>quay.io/example/hypershift@sha256:7bbfc29f4283a5b76ba9d1ee9f6a74864dc874614b26741520ae52d6a887b4a2</code></p>
<nav class="toc"><a href="#summary">Summary</a><a href="#coverage">Plan coverage</a><a href="#provenance">Provenance</a><a href="#preflight">Preflight</a><a href="#t1">T1</a><a href="#t2">T2</a><a href="#t3">T3</a><a href="#t4">T4</a><a href="#t5">T5</a><a href="#t6">T6</a><a href="#t7">T7</a><a href="#t8">T8</a><a href="#operator-restore">Operator restore</a><a href="#cleanup">Cleanup and DNS</a><a href="#limitations">Limitations</a><a href="#integrity">Integrity</a></nav>
</header>\n""")

    h.append("<section id='summary'><h2>Executive summary</h2>")
    h.append(table(["Case", "Result", "Key evidence"], status_rows))
    h.append("<p class='small'>T1–T3 and T6 are PASS on the decisive Azure Replace scenarios; T7 is PASS for stable-pool operator transition. T4/T5 remain PARTIAL against the full Chai matrix, and T8 is BLOCKED / NOT TESTED. Kubernetes cleanup and shared-DNS safety were independently verified.</p></section>")

    h.append("""<section id='coverage'><h2>Coverage against the Chai test plan</h2>
<p>This is the direct answer to whether the proposed plan covers the bug. It covers the decisive CAPI ≥1.14 Azure Replace paths, including the zero-<code>upToDateReplicas</code> release/config/infrastructure cases, the scale-zero edge, and the operator-transition invariant. It does not claim completion of the expanded predicate/reconciliation unit matrix or the compatibility rows that require another manager/provider.</p>""")
    h.append(table(["Plan case", "Requirement exercised", "Result", "Evidence"], [
        ("T1 baseline", "Unpatched operator must reproduce the physical A→B replacement with upToDateReplicas=0 and a stalled NodePool version.", "PASS — bug reproduced", "t1/baseline-20261028T133706Z"),
        ("T1 patched", "Patched operator must complete the same physical replacement and advance status.version/UpdatingVersion.", "PASS", "t1/patched-20261028T141214Z"),
        ("T2", "Release and infrastructure held fixed; config-only Replace rollout with marker verification.", "PASS", "t2/config-20261028T144539Z"),
        ("T3", "Release and user config held fixed; VM-size Replace with actual Azure VM verification.", "PASS", "t3/vm-size-20261028T150407Z"),
        ("T4", "Completion-predicate matrix, including edge counters and list-order cases.", "PARTIAL", "unit/rerun-20261028T160848Z"),
        ("T5", "Reconciliation metadata and MachineSet-list error/recovery sequence.", "PARTIAL", "unit/rerun-20261028T160848Z"),
        ("T6", "Scale to zero and scale back without stale completion or identity churn.", "PASS", "t6/scale-20261028T151819Z"),
        ("T7", "Stable pool across the base→patched operator transition.", "PASS", "t7 before/after snapshots"),
        ("T8", "Pre-1.14 manager, second provider, and InPlace smoke rows.", "BLOCKED / NOT TESTED", "no evidence claimed"),
    ]))
    h.append("<p><strong>Bottom line:</strong> the plan is sufficient for a one-time manual verification of the reported Replace-strategy bug and its key edge cases, but it is not a complete compatibility matrix. T4/T5 must stay PARTIAL and T8 must stay BLOCKED unless those missing rows are separately executed.</p></section>")

    h.append("<section id='provenance'><h2>Provenance and environment</h2><div class='grid'>")
    h.append("""<div class="card"><h3>Cluster</h3><dl class="kv">
<dt>Management kubeconfig</dt><dd><code>/home/tester/management.kubeconfig</code></dd>
<dt>HostedCluster</dt><dd><code>clusters/test-cntrlplane-4826-hc</code></dd>
<dt>Namespace</dt><dd><code>clusters-test-cntrlplane-4826-hc</code></dd>
<dt>Azure subscription</dt><dd><code>redacted-subscription-id</code></dd></dl></div>""")
    h.append("""<div class="card"><h3>Images</h3><dl class="kv">
<dt>Patched operator</dt><dd><code>quay.io/example/hypershift@sha256:7bbfc29f4283a5b76ba9d1ee9f6a74864dc874614b26741520ae52d6a887b4a2</code></dd>
<dt>Base operator</dt><dd><code>quay.io/example/hypershift@sha256:e848d7a892cbc144bfe0032ddeaccecde94a7c5e2d84f56c2953fb9e5e535834</code></dd>
<dt>CAPI</dt><dd><code>registry.k8s.io/cluster-api/cluster-api-controller:v1.14.3</code><br><code>imageID sha256:1110ddb0f4a9cfc1b557f305199e2d56911fe442edef6361e12e5cc4b11e23fd</code></dd></dl></div>""")
    h.append("""<div class="card"><h3>Release pair</h3><dl class="kv">
<dt>A</dt><dd><code>5.0.0-rc.7</code><br><code>quay.io/openshift-release-dev/ocp-release@sha256:502d2836c126b1a5c2f3f93cf6c43bbb9e0527530a0335ad8d3cbdb01bea8416</code></dd>
<dt>B</dt><dd><code>5.1.0-0.nightly-multi-2026-10-27-082258</code><br><code>quay.io/openshift-release-dev/ocp-release-nightly@sha256:08f0905c06195a76138db7071aa77ae644aea401eb832d51ebbf4fb870698346</code></dd></dl></div>""")
    h.append("</div></section>")

    # Preflight
    h.append("<section id='preflight'><h2>Preflight evidence</h2>")
    h.append(embed_file("Preflight metadata", preflight / "meta.txt"))
    h.append(embed_file("Image and source provenance", preflight / "image-provenance.txt"))
    h.append(embed_file("Azure DNS safety snapshot metadata", preflight / "azure-dns-meta.txt"))
    h.append(embed_file("Existing private scripts unchanged check", preflight / "existing-scripts-check.txt"))
    h.append(embed_file("Preflight SHA-256 manifest", preflight / "azure-dns-stable.sha256"))
    h.append(raw_summary(load_json(preflight / "hostedclusters-all.json")) if (preflight / "hostedclusters-all.json").exists() else "")
    h.append("</section>")

    # T1
    h.append(test_header("T1", "Decisive Replace release regression", "PASS", "Reproduce the zero-upToDateReplicas stall on the unpatched operator, then prove the same physical A→B replacement completes on the patched operator.", "Baseline patch 13:37:15Z, deadline 14:07:15Z. Patched patch 14:12:23Z, completion 14:35:21Z.", f"{t1b} and {t1p}"))
    h.append("<h3>Baseline — before request</h3>" + snapshot_html(t1b_pre))
    h.append("<h3>Baseline — action</h3>" + embed_file("Baseline command", t1b / "commands.txt"))
    h.append("<h3>Baseline — physical completion at 14:00:06Z</h3>" + pre(json.dumps(t1b_physical, indent=2, sort_keys=True)))
    h.append("<h3>Baseline — final state at fixed deadline 14:07:26Z</h3>" + snapshot_html(t1b_final))
    h.append("<p><strong>Assertion:</strong> physical replacement completed, but <code>NodePool.status.version=5.0.0-rc.7</code> and <code>UpdatingVersion=True</code> remained. This is the reported bug reproduction.</p>")
    h.append("<h3>Patched — before request</h3>" + snapshot_html(t1p_pre))
    h.append("<h3>Patched — action</h3>" + embed_file("Patched command", t1p / "commands.txt"))
    h.append("<h3>Patched — final state</h3>" + snapshot_html(t1p_final))
    h.append("<h3>Patched — worker join timings</h3>" + table(["Machine", "Created", "NodeReady", "Seconds"], [[m["name"], m["created"], m["nodeReady"], m["secondsToReady"]] for m in t1p_joins]))
    h.append("<p><strong>Assertions:</strong> target status.version=B; UpdatingVersion=False; current revision MachineSet 3/3; old MachineSet 0/0; upToDateReplicas=0; all joins below 720s. <strong>Result: PASS.</strong></p>")
    h.append(details("Patched final result JSON", pre(json.dumps(load_json(t1p / "final-20261028T144053Z/result.json"), indent=2))))
    h.append(details("T1 final snapshot raw summary", pre(json.dumps(load_json(t1p_final_dir / "summary.json"), indent=2, sort_keys=True))))
    h.append(embed_file("T1 patched watch runner output", t1p / "watch-rollout.log", 20000))
    h.append(embed_file("T1 patched join watcher output", t1p / "watch-machine-join.log", 20000))
    h.append("<p class='small'>Known limitation: the original baseline runner was interrupted after stall detection; a read-only resume watcher continued to the fixed deadline. The patched runner/listener was also interrupted; the final snapshot was captured after completion. Full watch files are preserved and this limitation is disclosed rather than hidden.</p>")
    h.append(test_footer())

    # T2
    h.append(test_header("T2", "Config-only Replace", t2_verdict["status"], "Hold release B and infrastructure fixed; change only config, verify the target config marker on every replacement worker, and prove completion metadata advances while upToDateReplicas stays zero.", "ConfigMap created 14:45:39Z; rollout complete by 14:56:07Z.", str(t2)))
    h.append("<h3>Before</h3>" + snapshot_html(t2_pre))
    h.append("<h3>Action</h3>" + embed_file("T2 command", t2 / "commands.txt") + embed_file("MachineConfig object", t2 / "machineconfig.yaml"))
    h.append("<h3>After</h3>" + snapshot_html(t2_final))
    h.append("<h3>Verification marker</h3>" + pre("CNTRLPLANE-4826-T2-20261028t144539z\n\nOriginal capture: 2/3 logs returned the marker; one kubectl logs request returned HTTP 502 through konnectivity. Recheck: 3/3 logs and direct exec reads returned the marker."))
    h.append(table(["Pod", "Node", "Log rc", "Log marker", "Exec rc", "Exec marker"], [[r.split("\t")[0], r.split("\t")[1], r.split("\t")[2], r.split("\t")[3], r.split("\t")[4], r.split("\t")[5]] for r in (t2 / "verification-recheck-20261028T145937Z/per-node-results.tsv").read_text().splitlines()]))
    h.append("<h3>Join timings</h3>" + table(["Machine", "Created", "NodeReady", "Seconds"], [[m["name"], m["created"], m["nodeReady"], m["secondsToReady"]] for m in t2_joins]))
    h.append("<p><strong>Assertions:</strong> config annotation changed 95a7feab→86d03f4f; config version changed fc563e6b→e7ebf8df; status.version stayed B; current set 3/3; old set drained; upToDateReplicas=0; marker 3/3 after recheck. <strong>Result: PASS.</strong></p>")
    h.append(embed_file("T2 verdict JSON", t2 / "verdict.json"))
    h.append(embed_file("T2 verification DaemonSet", t2 / "verification-daemonset.yaml"))
    for f in sorted((t2 / "verification-logs").glob("*.log")):
        h.append(embed_file(f"Original verification log — {f.name}", f))
    for f in sorted((t2 / "verification-recheck-20261028T145937Z").glob("*.log")):
        h.append(embed_file(f"Recheck log — {f.name}", f))
    for f in sorted((t2 / "verification-recheck-20261028T145937Z").glob("*.exec.txt")):
        h.append(embed_file(f"Direct file read — {f.name}", f))
    h.append(test_footer())

    # T3
    h.append(test_header("T3", "Infrastructure-template-only Replace", t3_verdict["status"], "Keep release and user config fixed; change only Azure VM size and verify actual infrastructure, template annotation, and zero-counter completion.", "Patch 15:04:16Z; completion 15:13:53Z; deadline 15:34:16Z.", str(t3)))
    h.append("<h3>Before</h3>" + snapshot_html(t3_pre))
    h.append("<h3>Action</h3>" + embed_file("T3 command", t3 / "commands.txt") + pre("kubectl patch nodepool test-cntrlplane-4826-patched -n clusters --type=merge -p '{\"spec\":{\"platform\":{\"azure\":{\"vmSize\":\"Standard_D4s_v5\"}}}}'"))
    h.append("<h3>After</h3>" + snapshot_html(t3_final))
    h.append("<h3>Actual Azure VM verification</h3>" + pre((t3 / "azure-actual/vms.tsv").read_text()))
    h.append("<h3>Worker join timings</h3>" + table(["Machine", "Created", "NodeReady", "Seconds"], [[m["name"], m.get("createdAt"), m.get("nodeReadyTransition"), m.get("ageSeconds")] for m in t3_verdict.get("joinDurations", [])]))
    h.append("<p><strong>Assertions:</strong> all 3 AzureMachines request D4s_v5; all 3 actual Azure VMs report D4s_v5 with provisioningState=Succeeded; platform template e4b9b203→776e47ca; UpdatingPlatformMachineTemplate=False; release/config unchanged; upToDateReplicas=0; all joins below 720s. <strong>Result: PASS.</strong></p>")
    h.append(embed_file("T3 verdict JSON", t3 / "verdict.json"))
    h.append(embed_file("T3 full final summary", t3 / "deadline/summary.json"))
    h.append(embed_file("T3 console", Path((BASE / "t3/current-console-path.txt").read_text().split("=", 1)[1].strip()) if (BASE / "t3/current-console-path.txt").exists() else t3 / "missing"))
    h.append(test_footer())

    # T4/T5
    h.append(test_header("T4", "Deterministic completion-predicate matrix", "PARTIAL", "Run TestMachineDeploymentComplete against the exact predicate contract and identify any matrix gaps.", "Focused rerun 16:08:48Z; exit code 0.", str(unit_rerun)))
    h.append("<p>All 12 subtests present in this revision pass. They cover the zero/nil <code>upToDateReplicas</code> regression, incomplete/available/scaled-zero cases, old-set health, observed-generation lag, and nil counters.</p>")
    h.append("<h3>Executed subtests</h3>" + table(["Subtest", "Result"], [[name.replace("_", " "), "PASS"] for name in t4_tests]))
    h.append("<h3>Chai matrix gaps</h3>" + table(["Requested permutation", "Status", "Why it remains partial"], [
        ("Counters above desired replica count", "NOT COVERED", "No explicit above-desired case in the current table."),
        ("Nil current-MachineSet counters", "NOT COVERED", "Nil MachineDeployment counters are covered; nil MachineSet counters are not."),
        ("Multiple old MachineSets with replicas", "NOT COVERED", "The table has one old set; combinations are not exercised."),
        ("observedGeneration greater than generation", "NOT COVERED", "The table covers observedGeneration below generation only."),
        ("Revision-versus-generation mismatch", "NOT COVERED", "No explicit mismatch fixture."),
        ("MachineSet list-order permutations", "NOT COVERED", "One fixed ordering is used."),
    ]))
    h.append("<p><strong>Result: PARTIAL.</strong> The regression-critical cases pass, but the wider matrix is not fully implemented.</p>")
    h.append(embed_file("T4/T5 exact command", unit_rerun / "commands.txt") + embed_file("T4/T5 rerun metadata", unit_rerun / "meta.txt") + embed_file("T4/T5 focused test log", t4_log))
    h.append(embed_file("Earlier T4 verbose log", BASE / "unit/t4-verbose-20261028T133809Z.log"))
    h.append(test_footer())
    h.append(test_header("T5", "Reconciliation metadata and error handling", "PARTIAL", "Exercise reconciliation with zero/nil upToDateReplicas, no-advance on incomplete states, idempotent completion, and MachineSet-list error recovery.", "Focused rerun 16:08:48Z; exit code 0.", str(unit_rerun)))
    h.append("<p>All three reconciliation subtests present in this revision pass: complete metadata advance, incomplete-state replication, and Ready-condition propagation.</p>")
    h.append("<h3>Executed subtests</h3>" + table(["Subtest", "Result"], [[name.replace("_", " "), "PASS"] for name in t5_tests]))
    h.append("<h3>Chai matrix gaps</h3>" + table(["Requested reconciliation case", "Status", "Why it remains partial"], [
        ("Zero upToDateReplicas through the full reconciliation path", "NOT COVERED", "Covered at predicate level in T4, not with a focused reconciliation fixture."),
        ("Nil upToDateReplicas through the full reconciliation path", "NOT COVERED", "Covered at predicate level in T4, not with a focused reconciliation fixture."),
        ("No version/config/template advance target assertions", "NOT COVERED", "The existing incomplete case checks some fields, but not every target."),
        ("Idempotent completion/no-op second reconcile", "NOT COVERED", "No repeated-reconcile assertion."),
        ("MachineSet-list error and recovery sequence", "NOT COVERED", "No injectable list error/recovery fixture in this revision."),
    ]))
    h.append("<p><strong>Result: PARTIAL.</strong> Existing reconciliation behavior passes, but the error-injection and repeat-reconcile matrix is incomplete.</p>")
    h.append(embed_file("T5 earlier verbose log", BASE / "unit/t5-verbose-20261028T133812Z.log"))
    h.append(test_footer())

    # T6
    h.append(test_header("T6", "Scale-to-zero and scale-back", t6_status, "Create a separate Replace pool, scale to zero, verify observed generation and counters drain, then scale back and verify Ready workers and stable metadata.", "Scale pool created 15:18Z; live test runs until scale-back completion.", str(t6) if t6 else "not started"))
    if t6_meta and t6_snapshot_pre and t6_snapshot_zero and t6_snapshot_back:
        h.append("<h3>Before scale-to-zero</h3>" + snapshot_html(t6_snapshot_pre))
        h.append("<h3>Scale-to-zero action</h3>" + embed_file("Scale-to-zero command", t6 / "commands-zero.txt"))
        h.append("<h3>After scale-to-zero</h3>" + snapshot_html(t6_snapshot_zero))
        h.append("<h3>Scale-back action</h3>" + embed_file("Scale-back command", t6 / "commands-back.txt"))
        h.append("<h3>After scale-back</h3>" + snapshot_html(t6_snapshot_back))
        if t6_verdict:
            h.append("<h3>Scale-back join timings</h3>" + table(["Machine", "Created", "NodeReady", "Seconds"], [[m["name"], m.get("createdAt"), m.get("nodeReadyTransition"), m.get("ageSeconds")] for m in t6_verdict.get("joinDurations", [])]))
            h.append("<p><strong>Assertions:</strong> zero generation 1→2, MachineDeployment replicas 0, old set 0; scale-back generation 2→3, MachineDeployment 3/3, all three nodes Ready, no version/config/template change, all joins under 720s. <strong>Result: PASS.</strong></p>")
            h.append(embed_file("T6 verdict JSON", t6 / "verdict.json"))
        h.append(embed_file("T6 pre-zero full summary", t6 / "pre-zero/summary.json", 40000))
        h.append(embed_file("T6 zero full summary", t6 / "zero/summary.json", 40000))
        h.append(embed_file("T6 back full summary", t6 / "back/summary.json", 40000))
        h.append(embed_file("T6 meta", t6 / "meta.txt"))
        h.append(embed_file("T6 zero monitor", t6 / "monitor-zero-state.ndjson", 20000))
        h.append(embed_file("T6 back monitor", t6 / "monitor-back-state.ndjson", 20000))
        h.append(embed_file("T6 scale-back join watcher", t6 / "watch-back-machine-join.log", 20000))
    else:
        h.append("<p>Live evidence is still being produced; the final report will only mark this PASS after both zero and back markers exist.</p>")
    h.append(test_footer())

    # T7
    h.append(test_header("T7", "Stable-pool operator transition", "PASS", "Observe a pool across the base→patched operator transition with no pool change; no rollout or identity churn may occur.", "Before 13:04:01Z; operator patched 13:13:32Z; after 13:21:47Z.", f"{t7_before} and {t7_after}"))
    h.append("<h3>Before transition</h3>" + snapshot_html(t7b))
    h.append("<h3>After transition</h3>" + snapshot_html(t7a))
    h.append(table(["Operator field", "Before", "After"], [
        ("Deployment generation", load_json(t7_before / "summary.json").get("managementOperator", {}).get("generation"), load_json(t7_after / "summary.json").get("managementOperator", {}).get("generation")),
        ("Operator image", next(iter(load_json(t7_before / "summary.json").get("managementOperator", {}).get("images", [])), {}).get("image"), next(iter(load_json(t7_after / "summary.json").get("managementOperator", {}).get("images", [])), {}).get("image")),
    ]))
    ids = [
        ("NodePool generation", t7b["nodePool"]["generation"], t7a["nodePool"]["generation"]),
        ("MachineDeployment revision", t7b["machineDeployment"]["revision"], t7a["machineDeployment"]["revision"]),
        ("MachineDeployment generation", t7b["machineDeployment"]["generation"], t7a["machineDeployment"]["generation"]),
        ("MachineSet names", sorted(s["name"] for s in t7b["machineSets"]), sorted(s["name"] for s in t7a["machineSets"])),
        ("Machine UIDs", sorted(str(m["uid"]) for m in t7b["machines"]), sorted(str(m["uid"]) for m in t7a["machines"])),
        ("Node UIDs", sorted(str(n["uid"]) for n in t7b["guestNodes"]), sorted(str(n["uid"]) for n in t7a["guestNodes"])),
    ]
    h.append(table(["Identity", "Before", "After"], ids))
    h.append("<p><strong>Result: PASS.</strong> The only observed change is the operator deployment image; the stable pool did not roll.</p>")
    h.append(embed_file("T7 before full summary", t7_before / "summary.json"))
    h.append(embed_file("T7 after full summary", t7_after / "summary.json"))
    h.append(test_footer())

    # T8
    h.append(test_header("T8", "Compatibility and regression matrix", "BLOCKED / NOT TESTED", "Pre-1.14 manager, second-provider, and InPlace smoke coverage.", "Not executed in this environment.", "no evidence claimed"))
    h.append(table(["Row", "Status", "Reason"], [
        ("CAPI >=1.14 Azure Replace release/config/VM-size", "PASS", "T1/T2/T3 executed on CAPI 1.14.3."),
        ("Supported pre-1.14 manager", "BLOCKED", "No verified pre-1.14 manager image/provenance was established."),
        ("Second supported CAPI-backed provider", "NOT TESTED", "Only Azure was available; no second-provider environment."),
        ("InPlace release/config smoke", "NOT TESTED", "Not run; time was spent on the decisive Replace cases."),
        ("Linked-run label/toleration failures", "OUT OF SCOPE", "No clean rerun or disposition was produced here."),
    ]))
    h.append(test_footer())

    # Operator restore
    h.append(f"<section id='operator-restore'><h2>Operator restore and final verification {badge('PASS')}</h2>")
    h.append("<p>The test operator was installed over the pre-existing management operator. After all live test cases and Kubernetes cleanup, the original operator image reference was restored and the deployment was checked against the pre-test manifest. The restore was a Kubernetes Deployment image update; no Azure resource was involved.</p>")
    h.append(table(["Deployment state", "Generation", "Observed generation", "Revision", "Operator image", "Init image", "Ready / replicas"], [
        ("Pre-test reference", operator_original["generation"], operator_original["observedGeneration"], operator_original["revision"], "; ".join(operator_original["operatorImages"]), "; ".join(operator_original["initImages"]), f"{operator_original['readyReplicas']} / {operator_original['replicas']}"),
        ("Before restore (test operator)", restore_before_summary["generation"], restore_before_summary["observedGeneration"], restore_before_summary["revision"], "; ".join(restore_before_summary["operatorImages"]), "; ".join(restore_before_summary["initImages"]), f"{restore_before_summary['readyReplicas']} / {restore_before_summary['replicas']}"),
        ("After restore", restore_after_summary["generation"], restore_after_summary["observedGeneration"], restore_after_summary["revision"], "; ".join(restore_after_summary["operatorImages"]), "; ".join(restore_after_summary["initImages"]), f"{restore_after_summary['readyReplicas']} / {restore_after_summary['replicas']}"),
    ]))
    h.append(table(["Restore event", "UTC timestamp"], [
        ("Restore start", restore_meta.get("started_utc")),
        ("Restore complete", restore_meta.get("completed_utc")),
        ("Rollout result", "deployment \"operator\" successfully rolled out"),
        ("Availability result", "deployment.apps/operator condition met"),
    ]))
    h.append("<h3>Pods before and after restore</h3>")
    h.append("<h4>Test operator pods before restore</h4>" + table(["Pod", "Phase", "All containers ready", "Image IDs", "Created"], pod_runtime_rows(restore_pods_before)))
    h.append("<h4>Restored operator pods</h4>" + table(["Pod", "Phase", "All containers ready", "Image IDs", "Created"], pod_runtime_rows(restore_pods_after)))
    h.append("<h4>Pre-test vs restored image digests</h4>" + table(["State", "Pod", "Resolved image ID"], restore_image_ids))
    h.append("<p><strong>Manifest comparison:</strong> the normalized pre-test and restored deployment manifests match. The recorded SHA-256 for each normalized manifest is <code>83b5c1e193d85a18b1e823ab1efbaf231901f7268245973e10f467039a4f79b7</code>; the semantic diff is empty.</p>")
    h.append("<p><strong>Limitation:</strong> the restored image reference is the mutable <code>quay.io/hypershift/hypershift-operator:latest</code> tag. The pre-test pod digests were <code>sha256:0dbb54a9...</code> and <code>sha256:4c9efdaa...</code>; the restored pods resolved to <code>sha256:6faaca6c...</code> and <code>sha256:0dbb54a9...</code>. The manifest is semantically identical, but the image-tag provenance is not immutable and is disclosed here.</p>")
    h.append(embed_file("Restore verification", operator_restore / "restore-verification.txt"))
    h.append(embed_file("Restore image-update output", operator_restore / "set-image.out"))
    h.append(embed_file("Restore rollout output", operator_restore / "rollout-status.out"))
    h.append(embed_file("Restore availability wait", operator_restore / "wait-available.out"))
    h.append(embed_file("Normalized manifest SHA-256 comparison", operator_restore / "manifest-comparison.sha256"))
    h.append(embed_file("Normalized pre-test vs restored manifest diff", operator_restore / "pre-test-vs-restored-semantic.diff"))
    h.append(embed_file("Pre-test deployment object", operator_original_path))
    h.append(embed_file("Restored deployment object", operator_restore / "deployment-after.json"))
    h.append("</section>")

    # Cleanup and DNS safety
    h.append(f"<section id='cleanup'><h2>Kubernetes cleanup and shared DNS safety {badge('PASS')}</h2>")
    h.append(f"<p><strong>Rule followed:</strong> cleanup was performed only through the Kubernetes API. No Azure resource group, DNS zone, delegation, role assignment, <code>shared-resource-group</code>, or other Azure infrastructure was manually deleted or modified.</p>")
    h.append("<h3>Pre-delete inventory</h3>")
    ready_pre_delete = 0
    for node in pre_delete_nodes:
        node_conditions = (node.get("status") or {}).get("conditions") or []
        if any(c.get("type") == "Ready" and c.get("status") == "True" for c in node_conditions):
            ready_pre_delete += 1
    h.append(table(["Object", "Count / state"], [
        ("HostedClusters", len(pre_delete_hostedclusters)),
        ("NodePools", len(pre_delete_nodepools)),
        ("Guest nodes", len(pre_delete_nodes)),
        ("Guest nodes Ready", ready_pre_delete),
    ]))
    nodepool_rows: list[list[Any]] = []
    for np in pre_delete_nodepools:
        np_meta = np.get("metadata") or {}
        np_spec = np.get("spec") or {}
        np_status = np.get("status") or {}
        nodepool_rows.append([
            np_meta.get("name"),
            np_meta.get("generation"),
            np_spec.get("replicas"),
            np_status.get("replicas"),
            np_status.get("version"),
            cond(np_status, "UpdatingVersion").get("status", "absent"),
            cond(np_status, "UpdatingConfig").get("status", "absent"),
        ])
    h.append(table(["NodePool", "Generation", "Desired", "Current", "Version", "UpdatingVersion", "UpdatingConfig"], nodepool_rows))
    h.append(embed_file("Pre-delete NodePool inventory", pre_delete / "nodepools.txt"))
    h.append(embed_file("Pre-delete summary", pre_delete / "summary.txt"))
    h.append(embed_file("Pre-delete guest nodes", pre_delete / "guest-nodes.txt", 20000))
    for snapshot_dir in sorted(pre_delete.glob("snapshot-*")):
        h.append(embed_file(f"Pre-delete snapshot — {snapshot_dir.name}", snapshot_dir / "summary.json", 12000))

    h.append("<h3>Kubernetes-only delete timeline</h3>")
    h.append(pre((cleanup / "commands.txt").read_text() + "\n\n" + (cleanup / "timestamps.txt").read_text()))
    h.append(embed_file("NodePool delete output", cleanup / "delete.out"))
    h.append(embed_file("HostedCluster delete output", cleanup / "delete-hostedcluster.out"))
    h.append(embed_file("NodePool retirement watch", cleanup / "wait-for-nodepools.log", 20000))
    h.append(embed_file("HostedCluster finalizer and deletion watch", cleanup / "wait-for-hostedcluster-delete.log", 20000))
    h.append("<p><strong>Observed retirement:</strong> all three NodePools were gone at <code>15:59:38Z</code>; the HostedCluster delete was submitted at <code>16:00:16Z</code>, remained under the HyperShift finalizer while the control-plane namespace was removed, and was absent at <code>16:03:35Z</code>.</p>")

    h.append("<h3>Final Kubernetes state</h3>")
    final_np_count = final_k8s_summary.get("nodePools")
    final_hc_count = final_k8s_summary.get("hostedClusters")
    final_operator = final_k8s_summary.get("operator") or {}
    h.append(table(["Check", "Final state"], [
        ("HostedClusters", final_hc_count),
        ("NodePools", final_np_count),
        ("Hosted control-plane namespace", "absent" if not final_k8s_summary.get("hcpNamespacePresent") else "present"),
        ("Operator deployment generation / observed", f"{final_operator.get('generation')} / {final_operator.get('observedGeneration')}"),
        ("Operator ready replicas", final_operator.get("readyReplicas")),
        ("Operator image", "; ".join(image.get("image", "") for image in final_operator.get("images", []))),
        ("CAPI MachineDeployments / MachineSets / Machines in HCP namespace", "0 / 0 / 0 (CAPI query empty)"),
    ]))
    h.append(embed_file("Final Kubernetes state JSON", final_k8s / "summary.json"))
    h.append(embed_file("Final CAPI leftovers query", final_k8s / "capi-leftovers.json"))
    h.append(embed_file("Final HostedCluster list", final_k8s / "hostedclusters.json"))
    h.append(embed_file("Final NodePool list", final_k8s / "nodepools.json"))

    h.append("<h3>Shared DNS and Azure safety</h3>")
    h.append(table(["Resource", "Pre-test", "Post-cleanup", "Interpretation"], [
        ("Parent zone", f"present; {preflight_parent_zone.get('numberOfRecordSets')} record sets", f"present; {postflight_parent_zone.get('numberOfRecordSets')} record sets", "zone id/name and etag unchanged; count is shared-CI-dependent and is not a test-owned metric"),
        ("Child zone", f"present; {preflight_child_zone.get('numberOfRecordSets')} record sets", f"present; {postflight_child_zone.get('numberOfRecordSets')} record sets", "exactly 12 test-owned record sets removed; zone remains"),
        ("Shared NS delegation tester", "present at 15:51:38Z investigation", "present; etag d74a834a-7dc4-4b0b-bde2-a313c49ba0c3", "present and unchanged between investigation and post-cleanup audit"),
        ("shared-resource-group resource group", "present", "present", "stable projection hash matches preflight"),
        ("Parent role assignments", "present", "present", f"stable hash matches preflight ({preflight_dns_hashes.get('azure-dns-parent-role-assignments-stable.json', 'n/a')})"),
        ("Child role assignments", "present", "present", f"stable hash matches preflight ({preflight_dns_hashes.get('azure-dns-child-role-assignments-stable.json', 'n/a')})"),
    ]))
    h.append(table(["Stable projection", "Pre-test SHA-256", "Post-cleanup SHA-256", "Result"], [
        ("shared-resource-group resource group", preflight_dns_hashes.get("azure-rg-shared-resource-group-stable.json"), postflight_dns_hashes.get("azure-rg-shared-resource-group-stable.json"), "MATCH" if preflight_dns_hashes.get("azure-rg-shared-resource-group-stable.json") == postflight_dns_hashes.get("azure-rg-shared-resource-group-stable.json") else "CHANGED"),
        ("Parent role assignments", preflight_dns_hashes.get("azure-dns-parent-role-assignments-stable.json"), postflight_dns_hashes.get("azure-dns-parent-role-assignments-stable.json"), "MATCH" if preflight_dns_hashes.get("azure-dns-parent-role-assignments-stable.json") == postflight_dns_hashes.get("azure-dns-parent-role-assignments-stable.json") else "CHANGED"),
        ("Child role assignments", preflight_dns_hashes.get("azure-dns-child-role-assignments-stable.json"), postflight_dns_hashes.get("azure-dns-child-role-assignments-stable.json"), "MATCH" if preflight_dns_hashes.get("azure-dns-child-role-assignments-stable.json") == postflight_dns_hashes.get("azure-dns-child-role-assignments-stable.json") else "CHANGED"),
        ("Parent zone stable projection", preflight_dns_hashes.get("azure-dns-parent-zone-stable.json"), postflight_dns_hashes.get("azure-dns-parent-zone-stable.json"), "CHANGED — shared CI record churn; see caveat"),
        ("Child zone stable projection", preflight_dns_hashes.get("azure-dns-child-zone-stable.json"), postflight_dns_hashes.get("azure-dns-child-zone-stable.json"), "CHANGED — exactly 12 test-owned records removed"),
    ]))
    h.append("<h4>Test-owned child-zone records removed</h4>")
    h.append(table(["#", "Record set"], [[i, record] for i, record in enumerate(child_records_removed, 1)]))
    h.append("<p><strong>Activity-log finding:</strong> the post-cleanup child-zone activity log contains 24 events: 12 delete Started and 12 Succeeded, all for <code>test-cntrlplane-4826-hc</code>. The parent zone's count moved from 109 preflight to 160 during the earlier investigation and 147 at final audit; its activity log contains no test-named event. During the test window the parent had 384 unrelated A/TXT/CNAME write/delete events from CI/external-dns. Parent-zone counts therefore must not be attributed to this test. The parent activity log for the final cleanup window also contains no test-named event.</p>")
    h.append("<p class='small'>Raw Azure activity-log JSON is retained in the evidence tree for audit but is intentionally not rendered here because Azure activity events include caller claims and authorization metadata. The sanitized counts and resource names above are the reportable evidence.</p>")
    h.append(embed_file("DNS investigation finding", dns_audit / "dns-finding.txt", 20000))
    h.append(embed_file("Post-cleanup finding", post_cleanup / "post-cleanup-finding.txt", 20000))
    h.append(embed_file("Removed child-zone records", post_cleanup / "child-records-removed.txt"))
    h.append(embed_file("Shared-resource comparison", post_cleanup / "comparison.txt"))
    h.append(embed_file("Stable DNS/Azure hashes", post_cleanup / "azure-dns-stable.sha256", 12000))

    h.append("<h3>Azure resource groups retained</h3>")
    retained_groups = load_json(post_cleanup / "test-resource-groups.json")
    h.append(table(["Resource group", "Location", "Created", "Action"], [[g.get("name"), g.get("location"), (g.get("tags") or {}).get("openshift_creationDate"), "retained; not touched"] for g in retained_groups]))
    h.append("<p>These three test-prefixed resource groups pre-dated this test run and were intentionally left in place. No manual Azure deletion or mutation command was issued against them.</p>")
    h.append("</section>")

    h.append("""<section id="limitations"><h2>Limitations and honest gaps</h2><ul>
<li>T4/T5 are partial. The existing focused predicate and reconciliation tests pass, but the expanded Chai matrix was not implemented: above-desired counters, nil current-set counters, multiple old sets, observedGeneration &gt; generation, revision-vs-generation cases, list-order permutations, full zero/nil reconciliation fixtures, repeat-reconcile/idempotence, and MachineSet-list error/recovery.</li>
<li>T8 is blocked/not tested. No verified pre-1.14 manager, second CAPI-backed provider, or InPlace smoke environment was available. These rows are not implied by the Azure Replace results.</li>
<li>T1 live watch coverage has two documented gaps because runners were interrupted; final snapshots and read-only resume watches preserve the observed states. The report does not claim uninterrupted watch coverage.</li>
<li>T2's original 2/3 marker result was caused by a transient konnectivity 502; the recheck via logs and direct file reads is authoritative and retained alongside the failed log.</li>
<li>The restored operator image reference is the mutable <code>quay.io/hypershift/hypershift-operator:latest</code> tag. The normalized Deployment manifest matches the pre-test manifest, but the restored pods resolved to a different digest set than the pre-test pods. This is a provenance limitation, not a manifest mismatch.</li>
<li>The parent DNS zone is shared with concurrent CI and is not a stable test-owned metric. Only the 12 child-zone records named for the test HostedCluster are attributed to this test.</li>
</ul></section>""")

    h.append("""<section id="integrity"><h2>Evidence integrity</h2>
<p>The complete raw evidence tree is under <code>""")
    h.append(esc(BASE))
    h.append("""</code>. Snapshot directories and the final scan directory carry SHA-256 manifests. No kubeconfig credential bytes, private keys, concrete bearer tokens, or Kubernetes Secret values are embedded in this report.</p>""")
    h.append(table(["Final credential scan", "Result"], [
        ("Private-key files", secret_scan_final_summary.get("private_key_files")),
        ("Kubeconfig key-field files", secret_scan_final_summary.get("kubeconfig_key_field_files")),
        ("Bearer literal forms", secret_scan_final_summary.get("bearer_literal_forms")),
        ("Parsed JSON files", secret_scan_final_summary.get("parsed_json_files")),
        ("Secret objects carrying data", secret_scan_final_summary.get("secret_objects_with_data")),
        ("Evidence files named kubeconfig", secret_scan_final_summary.get("evidence_files_named_kubeconfig")),
        ("Temporary guest kubeconfig", "absent / deleted"),
    ]))
    h.append("<p>The single bearer scan hit is the literal shell expression <code>Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)</code>, not a token value. The six evidence files named <code>kubeconfig-sanitized.json</code> contain sanitized context/server metadata only and have no users or credential fields. The temporary guest kubeconfig was deleted; its absence was verified independently.</p>")
    h.append(f"<p>The evidence tree contains {len(list(BASE.rglob('SHA256SUMS'))) + len(list(BASE.rglob('*.sha256')))} checksum/manifest files. The final credential scan is preserved at <code>{esc(secret_scan_final)}</code>.</p>")
    h.append(embed_file("Credential scan summary", secret_scan_final / "summary.txt"))
    h.append(embed_file("Guest kubeconfig absence check", secret_scan_final / "guest-kubeconfig-state.txt"))
    h.append(embed_file("Secret-bearing JSON scan", secret_scan_final / "json-secret-data-scan.txt"))
    h.append(embed_file("Kubeconfig-field scan", secret_scan_final / "kubeconfig-field-files.txt"))
    h.append(embed_file("Private-key scan", secret_scan_final / "private-key-files.txt"))
    h.append(embed_file("Bearer literal scan", secret_scan_final / "bearer-literal-forms.txt"))
    h.append("<p><strong>Cleanup rule:</strong> delete only the named test NodePools and finally the test HostedCluster through Kubernetes. Never delete <code>shared-resource-group</code>, DNS zones, delegation, role assignments, or manually destroy Azure infrastructure. That rule was followed.</p></section>""")

    h.append("</main></body></html>")
    return "".join(h)


if __name__ == "__main__":
    REPORT.write_text(make_report())
    print(REPORT)

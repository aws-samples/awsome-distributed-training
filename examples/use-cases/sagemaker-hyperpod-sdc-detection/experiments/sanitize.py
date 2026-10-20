#!/usr/bin/env python3
"""Prepare a fetched run for publishing, with example IDs instead of real ones.

    python3 sanitize.py runs/<job> <out dir> [--cluster-nodes nodes.json]

Replaces node names, instance IDs, and GPU UUIDs with example values everywhere, checks that
PyTorch's GPU UUIDs match nvidia-smi's, optionally checks the node names against the output of
`aws sagemaker list-cluster-nodes ... --output json`, refuses to write a file that still contains
a real identifier, and writes MANIFEST.sha256 over the published files and the source code.
"""
import argparse
import hashlib
import json
import os
import re
import shutil

NODE_RE = re.compile(r"hyperpod-(i-[0-9a-f]{17})")
UUID_RE = re.compile(r"GPU-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")
ACCOUNT_RE = re.compile(r"(?<![\w-])(?!763104351884)\d{12}(?![\w-])")  # 763104351884: public DLC registry


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("run")
    ap.add_argument("out")
    ap.add_argument("--cluster-nodes")
    a = ap.parse_args()
    files = os.path.join(a.run, "files")
    rank_map = json.load(open(os.path.join(files, "rank_map.json")))
    logs = sorted(f for f in os.listdir(a.run) if f.endswith(".log"))

    nodes = []
    for r in rank_map:
        if r["node"] not in nodes:
            nodes.append(r["node"])
    node_ex = {n: f"hyperpod-i-0123456789abcdef{k}" for k, n in enumerate(nodes)}
    inst_ex = {n.removeprefix("hyperpod-"): v.removeprefix("hyperpod-") for n, v in node_ex.items()}

    smi = {}  # (node, index) -> uuid, from "GPU <node> <index>, <uuid>, <driver>" log lines
    drivers = set()
    for fn in logs:
        for line in open(os.path.join(a.run, fn)):
            m = re.match(r"GPU (\S+) (\d+), (\S+), (\S+)", line)
            if m:
                smi[(m[1], int(m[2]))] = m[3]
                drivers.add(m[4])
    uuid_ex, matched = {}, 0
    for r in rank_map:
        k = nodes.index(r["node"])
        uuid_ex[r["gpu_uuid"]] = f"GPU-00000000-0000-0000-0000-00000000{k:02d}{r['cuda_device']:02d}"
        matched += smi.get((r["node"], r["cuda_device"])) == r["gpu_uuid"]

    loc = {"ranks": len(rank_map), "nodes": len(nodes),
           "node_name_format_hyperpod_instance_id": all(NODE_RE.fullmatch(n) for n in nodes),
           "rank_equals_node_rank_x_8_plus_local_rank":
               all(r["rank"] == nodes.index(r["node"]) * 8 + r["local_rank"] for r in rank_map),
           "torch_uuid_matches_nvidia_smi": f"{matched} of {len(rank_map)}",
           "nvidia_driver": sorted(drivers)}
    if a.cluster_nodes:
        listed = {s["InstanceId"] for s in json.load(open(a.cluster_nodes))["ClusterNodeSummaries"]}
        loc["node_names_match_list_cluster_nodes"] = all(n.removeprefix("hyperpod-") in listed for n in nodes)

    def scrub(text):
        for real, ex in {**node_ex, **inst_ex, **uuid_ex}.items():
            text = text.replace(real, ex)
        return text

    def check(name, text):
        left = NODE_RE.findall(text) + UUID_RE.findall(text) + ACCOUNT_RE.findall(text)
        left = [x for x in left if not x.startswith("i-0123456789abcdef") and "-00000000" not in x]
        if left:
            raise SystemExit(f"{name}: real identifiers remain, e.g. {left[:3]}")

    os.makedirs(a.out, exist_ok=True)
    outputs = {"rank_map.json": json.dumps(json.loads(scrub(json.dumps(rank_map))), indent=1),
               "localization.json": json.dumps(loc, indent=1)}
    for fn in logs:
        role = re.sub(r"^.*-(master|worker)-(\d+)\.log$", r"\1-\2.log", fn).replace("master", "rank0")
        outputs[f"logs/{role}"] = scrub(open(os.path.join(a.run, fn)).read())
    for fn in ("job.yaml", "images.txt"):
        outputs[fn] = scrub(open(os.path.join(a.run, fn)).read())
    outputs["order.json"] = scrub(open(os.path.join(files, "order.json")).read())
    for name, text in outputs.items():
        check(name, text)
        path = os.path.join(a.out, name)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f:
            f.write(text if text.endswith("\n") else text + "\n")
    shutil.copy(os.path.join(files, "norms.json.gz"), os.path.join(a.out, "norms.json.gz"))

    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    srcs = [os.path.join(repo, "sdc_order.py")] + sorted(
        os.path.join(repo, "experiments", f) for f in os.listdir(os.path.join(repo, "experiments"))
        if f.endswith((".py", ".sh")))
    lines = []
    for p in srcs + sorted(os.path.join(dp, f) for dp, _, fs in os.walk(a.out) for f in fs
                           if f != "MANIFEST.sha256"):
        with open(p, "rb") as f:
            lines.append(f"{hashlib.sha256(f.read()).hexdigest()}  {os.path.relpath(p, repo)}")
    with open(os.path.join(a.out, "MANIFEST.sha256"), "w") as f:
        f.write("\n".join(lines) + "\n")
    print(json.dumps(loc, indent=1))


if __name__ == "__main__":
    main()

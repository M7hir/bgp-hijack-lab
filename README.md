# BGP Hijacking Attack & Mitigation Lab
**FRRouting v9.1 + Containerlab | Ubuntu 22.04**

A controlled simulation of BGP prefix hijacking attacks and RPKI-based
mitigations across a four-AS topology. Built for reproducibility on any
Ubuntu 22.04 machine.

---

## Workspace Organization (Simple View)

Use the repository as it is currently organized:

- `bgp-hijack-lab/` -> **v1 (base lab)**
- `bgp-hijack-lab-rpki-v2/` -> **v2 (RPKI-enabled lab)**
- `bgp-beyond-extensions-v3/` -> **v3 (advanced extensions)**

You do not need to rename or move folders to run the project.

### Which folder should I use?

| Goal | Folder | Topology used |
|------|--------|---------------|
| Run validated baseline lab | `bgp-hijack-lab/` | `bgp-hijack-lab/topology.yaml` |
| Test RPKI lab (still being validated) | `bgp-hijack-lab-rpki-v2/` | `bgp-hijack-lab-rpki-v2/topology.yaml` |
| Run advanced extension scripts | `bgp-beyond-extensions-v3/` | Uses **v1 topology** (`bgp-hijack-lab/topology.yaml`) |

This file is the main overview. Scenario-specific commands stay in each scenario README.

### Optional future cleanup (not required)

If you want a cleaner naming scheme later, this is a good target:

- `labs/base/` -> v1
- `labs/rpki/v2/` -> v2
- `labs/rpki/v3/` -> v3
- `docs/results/evaluations/` -> CSV outputs
- `docs/sessions/` -> session notes/transcripts

---

## Validation Status

| Version | Folder | Status | Notes |
|--------|--------|--------|------|
| v1 | `bgp-hijack-lab/` | Validated | Baseline attacks, mitigation flow, and evaluation are complete and reproducible. |
| v2 (RPKI) | `bgp-hijack-lab-rpki-v2/` | Needs full validation | RPKI workflow exists, but full end-to-end validation is still pending. |
| v3 (Beyond Extensions) | `bgp-beyond-extensions-v3/` | Not validated | Scripts and scenarios are present, but no full validation has been completed yet. |

Validation priority for ongoing work:

1. Fully validate v2 RPKI path first (baseline -> attack -> mitigation -> evaluation).
2. For v3, validate each script on v1 first (current integration path).
3. Port each validated v3 script to v2 and re-validate on v2.

---

## Topology Per Scenario

- v1 (`bgp-hijack-lab/`) uses `bgp-hijack-lab/topology.yaml` (`name: bgp-hijack`).
- v2 (`bgp-hijack-lab-rpki-v2/`) uses `bgp-hijack-lab-rpki-v2/topology.yaml` (`name: bgp-hijack-rpki`) and adds the `rpki` validator node.
- v3 (`bgp-beyond-extensions-v3/`) does not contain its own `topology.yaml`; extension scripts are intended to run on the deployed **v1 topology**.

### v3 Validation and Migration Policy

- Current implementation path: v3 scripts run on v1 topology.
- Validation order for v3 scripts:
     1. Validate each script on v1 first.
     2. After it is confirmed working, port and validate the same script on v2.
- Long-term target: make v2 the primary baseline for v3 extensions once script parity is achieved.

---

## What Changed Beyond README

Between v1 and v2, non-README changes include:

- Added v2-only files:
     - `configs/rpki/slurm.json`
     - `configs/rpki/run-routinator.sh`
     - `scripts/validator_status.sh`
     - `scripts/full_deployment_demo.sh`
     - `session.txt`
     - v2 evaluation outputs (`evaluation_20260317_150013.log`, `evaluation_20260317_150013.csv`)
- Modified shared filenames (content differs from v1):
     - `bootstrap.sh`, `topology.yaml`
     - `configs/r1/daemons`, `configs/r2/daemons`
     - `scripts/apply_mitigation.sh`, `scripts/remove_mitigation.sh`
     - `scripts/verify.sh`, `scripts/evaluate.sh`
     - `scripts/capture_bgp.sh`, `scripts/partial_deployment_demo.sh`
     - `scripts/start_exact_hijack.sh`, `scripts/start_subprefix_hijack.sh`, `scripts/stop_attack.sh`

v3 contributes extension scripts and GoRTR VRP JSONs in its own folder; it does not ship a separate topology file.

---

## Evaluation Artifact Provenance

- Root-level `evaluation_20260316_205110.csv` is from the **v1** workflow.
- `bgp-hijack-lab-rpki-v2/evaluation_20260317_150013.csv` and `.log` are from **v2** runs.
- v3 currently has no fully validated evaluation artifact set yet.

---

## Topology

```
        AS300 (Victim)     13.0.0.0/24
             |
        AS200 (Transit)    12.0.0.0/24
             |
        AS100 (Observer)   11.0.0.0/24
             |
        AS400 (Attacker)   14.0.0.0/24
```

| Link | Subnet |
|------|--------|
| AS100 ↔ AS200 | 10.12.0.0/30 |
| AS200 ↔ AS300 | 10.23.0.0/30 |
| AS100 ↔ AS400 | 10.14.0.0/30 |

---

## Quick Start (Fresh Ubuntu 22.04 VM)

```bash
# 1. Run the bootstrap installer (installs Docker, Containerlab, FRR image)
sudo bash bootstrap.sh

# 2. Deploy the lab
cd ~/bgp-hijack-lab
sudo containerlab deploy -t topology.yaml

# 3. Verify BGP converged (wait 30 seconds first)
bash scripts/verify.sh
```

**Expected baseline:** R1 shows `13.0.0.0/24` via `AS path: 200 300`

---

## Running the Attacks

### Attack 1 — Exact Prefix Hijack
AS400 announces the same prefix as the victim. Shorter AS path wins.

```bash
bash scripts/start_exact_hijack.sh
```

**Expected:** R1 routes to AS400 (path: 400) instead of AS300 (path: 200 300)

```bash
bash scripts/stop_attack.sh
```

---

### Attack 2 — Subprefix Hijack
AS400 announces a more specific /25. BGP longest-prefix-match always prefers it.

```bash
bash scripts/start_subprefix_hijack.sh
```

**Expected:** Both /24 (legitimate) and /25 (attacker) coexist in R1's BGP table.
Traffic to `13.0.0.0–13.0.0.127` goes to attacker. Traffic to `13.0.0.128–13.0.0.255` still reaches victim.

```bash
bash scripts/stop_attack.sh
```

---

## Running the Mitigation

Apply a ROV-style route-map filter on R1 that rejects AS400's announcements:

```bash
bash scripts/apply_mitigation.sh
```

Verify it is active:
```bash
docker exec clab-bgp-hijack-r1 vtysh -c "show route-map"
# Look for: deny, sequence 20 Invoked N  (N > 0 means filter is firing)
```

Test it blocks the attack:
```bash
bash scripts/start_exact_hijack.sh
# R1 should show only the legitimate path (200 300) — AS400 blocked
bash scripts/stop_attack.sh
bash scripts/remove_mitigation.sh
```

---

## Partial Deployment

Shows that ROV only at R1 (AS100) is insufficient when transit AS200 has no protection:

```bash
bash scripts/partial_deployment_demo.sh
```

**Expected:**
- R1 (protected): rejects AS400 hijack ✓
- R2 (unprotected): still accepts AS400 hijack ✗

This empirically confirms the partial deployment finding from ROV++ (Morillo et al., NDSS 2021).

---

## Evaluation

Automated measurement of attack timing and mitigation effectiveness:

```bash
bash scripts/evaluate.sh
```

Runs for approximately 15–20 minutes. Produces:
- `evaluation_<timestamp>.log` — full output
- `evaluation_<timestamp>.csv` — data for charts

**Results from this lab:**

| Metric | Result |
|--------|--------|
| Attack propagation time | <1s (sub-second in emulated environment) |
| Recovery after withdrawal | <1s |
| Hijack success (no defense) | 100% |
| Hijack success (with ROV) | 0% |
| Mitigation block rate | 100% |

> Note: Sub-second convergence is expected in containerized topologies
> where all nodes share physical hardware. Real-world BGP convergence
> takes 5–15 seconds (Sermpezis et al., ARTEMIS 2018).

---

## Capturing Evidence

Capture BGP UPDATE packets for Wireshark analysis:

```bash
# Terminal 1
bash scripts/capture_bgp.sh

# Terminal 2 — trigger attack while capture is running
bash scripts/start_exact_hijack.sh
```

Open the `.pcap` file in Wireshark and filter: `bgp.type == 2`

---

## Topology Diagram

```bash
sudo containerlab graph -t topology.yaml
# Open browser: http://localhost:3000
```

---

## Manual Router Access

```bash
docker exec -it clab-bgp-hijack-r1 vtysh   # AS100 Observer
docker exec -it clab-bgp-hijack-r2 vtysh   # AS200 Transit
docker exec -it clab-bgp-hijack-r3 vtysh   # AS300 Victim
docker exec -it clab-bgp-hijack-r4 vtysh   # AS400 Attacker
```

Useful commands inside vtysh:
```
show bgp ipv4 unicast              # full BGP table
show bgp ipv4 unicast 13.0.0.0/24  # specific prefix detail
show bgp summary                   # neighbor session status
show ip route                      # kernel routing table
show route-map                     # active filters and invocation counts
show ip prefix-list                # active prefix-lists
```

---

## Full Demo Sequence

Run in this order for a complete presentation:

```bash
# Baseline
bash scripts/verify.sh

# Attack 1
bash scripts/start_exact_hijack.sh
bash scripts/stop_attack.sh

# Attack 2
bash scripts/start_subprefix_hijack.sh
bash scripts/stop_attack.sh

# Mitigation
bash scripts/apply_mitigation.sh
bash scripts/start_exact_hijack.sh   # should be blocked
bash scripts/stop_attack.sh
bash scripts/remove_mitigation.sh

# demo
bash scripts/partial_deployment_demo.sh

# Evaluation
bash scripts/evaluate.sh
```

---

## Troubleshooting

**R4 neighbor stuck in "Active" state after deploy:**
```bash
sudo containerlab deploy -t topology.yaml --reconfigure
```

**BGP not converging after deploy:**
Wait 30–60 seconds then rerun `bash scripts/verify.sh`.

**Route-map not blocking attacks:**
```bash
bash scripts/remove_mitigation.sh
bash scripts/apply_mitigation.sh
```

**`Error renaming frr.conf: Resource busy`:**
Safe to ignore — cosmetic warning, config was saved successfully.

**`% Can't find static route specified`:**
Safe to ignore — route was already removed.

---

## Teardown

```bash
sudo containerlab destroy -t topology.yaml
```

---

## File Structure

```
bgp-hijack-lab/
├── bootstrap.sh                    ← one-command full install
├── topology.yaml                   ← 4-AS Containerlab topology
├── configs/
│   ├── r1/  (AS100 — Observer)
│   ├── r2/  (AS200 — Transit)
│   ├── r3/  (AS300 — Victim)
│   └── r4/  (AS400 — Attacker)
└── scripts/
    ├── verify.sh
    ├── start_exact_hijack.sh
    ├── start_subprefix_hijack.sh
    ├── stop_attack.sh
    ├── apply_mitigation.sh
    ├── remove_mitigation.sh
    ├── partial_deployment_demo.sh
    ├── evaluate.sh
    └── capture_bgp.sh
```

---

## Environment

- OS: Ubuntu 22.04
- FRRouting: v9.1.0 (`quay.io/frrouting/frr:9.1.0`)
- Containerlab: v0.54.2
- Docker: CE 28.x

---

## References

- RFC 4271 — BGP-4
- RFC 6811 — BGP Prefix Origin Validation
- Sermpezis et al., ARTEMIS (IEEE/ACM ToN 2018)
- Chung et al., RPKI is Coming of Age (ACM IMC 2019)
- Morillo et al., ROV++ (NDSS 2021)
- Kowalski & Mazurczyk, Routing Security Survey (Computer Networks 2023)

## Acknowledgements
Built using FRRouting (https://frrouting.org) and 
Containerlab (https://containerlab.dev).

Topology concept inspired by the BGP hijacking demonstration originally
described in the Mininet project wiki (2014). This implementation uses
FRRouting 9.1 and Containerlab — entirely different tooling with
original attack scripts, ROV mitigation, and automated evaluation.

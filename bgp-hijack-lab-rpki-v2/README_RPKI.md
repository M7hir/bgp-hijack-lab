# RPKI-Enabled Duplicate Lab

This folder is a duplicated version of the original lab with validator-backed RPKI/ROV controls.

## Current status

- Validation state: **needs full validation**.
- Topology ownership: this version uses its own `topology.yaml` (`name: bgp-hijack-rpki`) and includes an `rpki` validator node.
- It is independent from the v1 topology file.

## What changed

- Topology name changed to `bgp-hijack-rpki` to avoid collision.
- Added validator node `rpki` in `topology.yaml` using `nlnetlabs/routinator:latest`.
- Added deterministic VRPs via `configs/rpki/slurm.json`.
- Added validator launcher `configs/rpki/run-routinator.sh`.
- Replaced static mitigation logic with RPKI validation policy in:
  - `scripts/apply_mitigation.sh`
  - `scripts/remove_mitigation.sh`
- Added validator health helper:
  - `scripts/validator_status.sh`
- Updated verification and evaluation scripts to include RPKI context.

## Quick flow

1. Deploy
   - `sudo containerlab deploy -t topology.yaml`
2. Verify baseline and validator status
   - `bash scripts/verify.sh`
   - `bash scripts/validator_status.sh`
3. Attack
   - `bash scripts/start_exact_hijack.sh`
4. Enable RPKI-backed mitigation
   - `bash scripts/apply_mitigation.sh r1`
5. Test partial deployment
   - `bash scripts/partial_deployment_demo.sh`
6. Teardown
   - `sudo containerlab destroy -t topology.yaml`

## Notes

- `apply_mitigation.sh` supports targets:
  - `r1` (default): only AS100 validates
  - `all`: AS100 and AS200 validate
- The duplicate bootstrap script was rewritten to install dependencies and images only; it does not regenerate lab files.

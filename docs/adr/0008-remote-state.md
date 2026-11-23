# ADR-0008: Keep the Terraform state in a versioned Cloud Storage bucket and import what already exists

- **Status:** accepted
- **Date:** 2026-11-09
- **Author:** Lucas
- **Lesson:** L08

## Context

Step 8 puts the platform under Terraform. The resources already exist, created
by hand in steps 2 to 4: the bucket `albert-de-msc2-26-g03-bronze` and the
datasets `g03_bronze`, `g03_warehouse`, `g03_analytics`, in the shared project
`data-engineering-i1`. They hold our data, so recreating them is not an option.

Four people run Terraform from four Macs. Terraform needs one state file that
all of them read and lock. We cannot create service accounts or IAM in the
project (`iam.serviceAccounts.create` refused).

## Options considered

| Option | For | Against |
|---|---|---|
| **Remote state in a versioned GCS bucket, import blocks** (ours) | Shared by the 4 of us, locked during apply, each write keeps a previous version | One bucket created by hand that Terraform cannot manage |
| Local state on one laptop | Nothing to set up | Only one person can apply; lost if the laptop is lost |
| State committed to git | Shared and versioned | Can hold secrets; two people applying create conflicts; no lock |
| Recreate the resources from code | Clean start | Destroys the data in the bucket and datasets |

## Criteria

Sharing between four people, protection against two applies at once, recovery
if the state is damaged, and no change to the live resources.

## Decision

Store the state in `gs://albert-de-msc2-26-g03-tfstate` (versioned, public
access blocked) and adopt the 4 existing resources with import blocks, applied
from a saved plan.

## Consequences

- Proof: "Plan: 4 to import, 0 to add, 0 to change, 0 to destroy", then "Apply
  complete! Resources: 4 imported", then plan gives "No changes".
- No tfstate in git history; provider pinned (`~> 8.3`, locked at 8.10.0), lock
  file with hashes for `linux_amd64`, `darwin_arm64` and `darwin_amd64`.
- CI runs `fmt -check`, `init` and `validate` on every PR touching `infra/`:
  green on PR #8, red on purpose on PR #9.
- Surprise: since google provider 5.0, labels are not authoritative. A label
  added by hand (`drift-test=mathilde`) is invisible to plan; only
  `plan -refresh-only` shows it. A clean plan does not prove there are no
  hand-made labels.
- The state bucket itself is managed by hand (labelled `managed_by=manual` in
  step 9).

## What would change our mind

- If the professor grants `iam.serviceAccounts.create`, declare the Airbyte
  service account and its bucket grant in Terraform.
- If the platform gets a second environment, split the state by environment
  (one prefix each).

## Sources

- `notes/step8.md`
- `notes/step8-no-changes.txt`
- `notes/step8-drift-refresh-only.txt`
- `infra/terraform/`

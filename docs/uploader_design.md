# Uploader — Design Proposal

**Status:** Proposal (not yet implemented)
**Date:** 2026-05-28
**Depends on:** the evidence envelope ([`envelope_design.md`](envelope_design.md), built).
**Decisions baked in (with the user, 2026-05-28):** 1 fetcher = 1 evidence set;
evidence-set identity ships in `fetcher.yaml`, customer-overridable; the uploader
get-or-creates sets; control linkage stays manual/Paramify-side for now.

---

## Where it sits

The uploader is a **separate stage** (per `design.md`): it reads a completed run
directory of enveloped evidence and pushes to Paramify. It never runs fetchers,
never needs a fetcher's source credentials, and can be pointed at an *old* run
directory to re-upload. Two uploaders, mirroring the existing scaffold dirs:

- **`uploaders/paramify_evidence/`** — the main path: evidence files → evidence
  sets as artifacts.
- **`uploaders/paramify_issues/`** — the Wiz-style writeback: a CSV/findings file
  → an assessment intake endpoint. Same auth, different endpoint.

Each uploader self-describes in an `uploader.yaml` (mirrors `fetcher.yaml`):
runtime, the secret it needs (`PARAMIFY_UPLOAD_API_TOKEN`), and config.

---

## The Paramify API contract (reused from the upstream pusher)

Paramify REST API v0. Auth `Authorization: Bearer $PARAMIFY_UPLOAD_API_TOKEN`,
base `https://app.paramify.com/api/v0` (override via `PARAMIFY_API_BASE_URL`).

- **Evidence set (the container, keyed by `referenceId`):**
  - `GET /evidence` → find by `referenceId`
  - `POST /evidence` `{referenceId, name, description, instructions, automated}` →
    create; on `400 "Reference ID already exists"`, fall back to find. = **get-or-create**.
- **Artifact (the evidence, attached to a set):**
  - `POST /evidence/{id}/artifacts/upload` — multipart: `file` (the evidence) +
    `artifact` (JSON `{title, note, effectiveDate}`).
  - `GET /evidence/{id}/artifacts?originalFileName=…` — for optional dedup.
- **Issues / vulnerability intake (paramify_issues):**
  `POST /assessment/{assessmentId}/intake` — multipart file + artifact JSON.

The evidence-set object has **no control field** (`referenceId, name, description,
instructions, remarks, automated` only). Tying a set to controls is done in
Paramify, manually, today — see "Control linkage" below.

---

## Evidence-set identity lives in `fetcher.yaml`

A new optional block. It is *fetcher-knowledge* — what this fetcher's evidence is
and how it's collected — identical across customers, so it ships with the fetcher
and replaces the upstream monolithic `evidence_fetchers_catalog.json`.

```yaml
# fetcher.yaml
evidence_set:
  reference_id: EVD-OKTA-PHISHING-MFA     # idempotency key; the shipped default
  name: Okta Phishing-Resistant MFA        # display name (create / verify)
  instructions: >                          # how this evidence is collected
    Collected via the Okta API: GET /api/v1/authenticators and
    GET /api/v1/policies?type=MFA_ENROLL …
  # description: reuses the fetcher's existing top-level `description` unless set here
```

Added to `fetcher_schema.json` as an optional object (`reference_id` + `name`
required when the block is present; `instructions`/`description` optional). v0.x:
optional overall, backfilled across fetchers (defaults regenerated from the old
catalog's evidence-set fields). A fetcher with no block is skipped by the uploader
with a warning.

**Do NOT add `controls` / `solution_capabilities` here** — that's the coupling
`design.md` cut, and it stays out.

### Carried into the envelope at wrap time — DONE (2026-05-28)

The runner copies the fetcher's `evidence_set` block into the envelope
`metadata.evidence_set` at wrap time (`framework/envelope.py`; declared in
`envelope_schema.json`). This makes each evidence file **fully self-describing for
upload** — the uploader needs only the run directory (plus the customer override
config), not the `fetchers/` tree, and an *old* run re-uploads correctly even if
the fetcher later changed. Present only when the fetcher declares the block.

---

## Customer-side override (reconciles "shipped default, overridable")

Customers never edit `fetcher.yaml`. A customer who needs a different `referenceId`
in their program supplies an uploader config:

```yaml
# upload.yaml (customer-side; like a run manifest, lives in their environment)
paramify:
  base_url: https://app.paramify.com/api/v0   # optional
  # token via env PARAMIFY_UPLOAD_API_TOKEN (source-agnostic, like fetcher secrets)
overrides:
  okta_phishing_resistant_mfa:
    reference_id: CUST-OKTA-MFA-01            # override just the ID for this program
# skip_failed: false   # upload evidence even when the run's status was "failed"
```

Resolution: envelope default ← customer override. Only `reference_id` is the
common override; name/instructions can be overridable too if needed.

---

## Upload flow (`uploaders/paramify_evidence/uploader.py`)

1. **Locate the run dir** — an explicit path arg, or the latest `run-*` under a
   given `output_dir`.
2. **Walk the enveloped evidence files** (every `*.json` except `_run_metadata.json`).
3. **Per file** — read `metadata`:
   - Resolve the evidence set: `metadata.evidence_set` ← customer override.
     No evidence-set info → skip with a warning (counted).
   - Optionally skip if `metadata.status == "failed"` (config `skip_failed`);
     default is to upload (partial evidence is still evidence) with the failure
     noted on the artifact.
   - **Get-or-create** the evidence set by `reference_id` (name/description/
     instructions from the envelope).
   - **Attach the artifact**: upload the *enveloped* file (self-describing in
     Paramify too). Artifact `title` = evidence-set name (+ `target` when fanout),
     `note` carries run_id / target / status / collected_at from the envelope,
     `effectiveDate` = collected_at.
4. **Record** an `upload_log.json` in the run dir (what uploaded, to which set,
   success/fail). **Exit non-zero** if any upload failed or any file was skipped
   for missing evidence-set info.

### Idempotency
- Evidence sets: get-or-create by `referenceId` — safe to re-run.
- Artifacts: deduped by `(originalFileName, run_id)` — **always on**. Re-running
  the uploader on the *same* run dir is a no-op (won't double-post), while a
  *different* run (different `run_id`) still adds a new versioned artifact. The
  `run_id` is matched as an exact token in the artifact note, not a substring.
- Optional, off by default: upload the fetcher's entry script as a one-time
  artifact (deduped by filename) to document how evidence was collected.

---

## Control linkage (deferred, clean seam)

Evidence sets are tied to **solution capabilities → controls manually in Paramify**
today; the app can't do this programmatically yet. The uploader's job ends at
"evidence set exists and the artifact is attached." When a programmatic linking
API lands, it plugs in here without touching fetchers or the evidence-upload path —
the link mapping would live customer/program-side (same place as the override
config), never in `fetcher.yaml`. We deliberately do not contort the design around
the current manual gap.

---

## What it retires / unblocks

- **Retires** the monolithic `evidence_fetchers_catalog.json` / `evidence_sets.json`
  (edit one fetcher dir, not a giant file) — realizing `design.md`'s "catalog as a
  derived artifact."
- **Unblocks** the Wiz fetcher (needs `paramify_issues`) and completes the
  `tool → evidence → Paramify` value chain.

## Non-goals (this pass)
- No programmatic control / solution-capability linking (manual in Paramify).
- No new evidence-set object fields beyond what the v0 API accepts.
- `paramify_issues` (assessment intake) is a thin second uploader; specify after
  the evidence path lands.

## Open questions
- **Run selection / batching:** one run dir per upload invocation (assume yes);
  one Paramify program per `PARAMIFY_UPLOAD_API_TOKEN` (assume yes).
- **Failed-run policy:** default upload-with-note vs `skip_failed` — confirm the default.
- **Artifact = enveloped file vs raw payload:** proposal uploads the enveloped
  file (self-describing); confirm Paramify ingestion is fine with the wrapper.

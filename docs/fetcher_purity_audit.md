# Fetcher Purity Audit

**Status:** Snapshot review, not blocking any work
**Date:** 2026-05-27
**Scope:** the first 26 v0.x fetchers across 6 categories (okta, gitlab,
sentinelone, knowbe4, k8s, rippling) as of 2026-05-27. **Not re-run since.**
The 15 AWS fetchers ported afterward are *not* covered here — re-audit or
extend this doc before treating it as complete.

The framework rule: **fetchers collect data from a single source; cross-source comparison lives in comparators.** This document audits those 26 ported fetchers against that rule.

For rationale see [`design.md`](design.md) § "Fetcher scope: pure data collection, separate comparison layer".

---

## Headline

**None of the 26 fetchers do cross-source comparison.** All collect from a single external source (no fetcher reads another fetcher's output, no fetcher joins across categories, no fetcher writes back to a third-party system). The strict design boundary is intact.

There are three places where compliance *interpretation* leaked into a fetcher from the upstream source — these aren't cross-source comparison, but they muddy the "fetcher = facts only" framing.

---

## What was checked and confirmed clean

- No fetcher reads from another fetcher's output ✓
- No fetcher reads from `EVIDENCE_DIR` to pick up prior outputs ✓
- No fetcher joins data across categories (no Okta-vs-Rippling, no GitLab-vs-anyone) ✓
- No fetcher writes back to a third-party system (the Wiz case stays deferred for this reason) ✓

---

## Strictly compliant (24 of 26)

Pure data collection — raw API responses, counts, lists, percentages, single-source aggregation:

| Category | Fetchers | Notes |
|---|---|---|
| Okta python | 7 | `okta_iam_core` summaries are derived metrics (counts, percentages) — single source |
| GitLab | 2 | `ci_cd_pipeline_config` and `project_summary` emit factual booleans (`has_test_stage`, `has_security_scan`, etc.) |
| SentinelOne | 5 | All return raw records + groupings/counts — facts |
| KnowBe4 | 1 | `module_based_summary` — per-module pass/assigned ratios, single-source aggregation |
| K8s | 3 | Counts of clusters/containers meeting observable properties — facts |
| Rippling | 3 | Raw records + counts — facts |

---

## Three exceptions worth knowing about

### `okta_authenticators` — hardcoded `"status": "PASS"`

The analysis block emits:

```json
"analysis": {
    "status": "PASS",
    "checks": { ... }
}
```

`status` is **hardcoded to "PASS"** regardless of whether the individual `checks` actually pass. That's a compliance verdict ignoring the underlying data. The individual checks (booleans on observable settings) are fine; the PASS framing is not.

**Surgical fix:** drop the `status` field. The `checks` already convey the facts.

---

### `gitlab_merge_request_summary` — compliance interpretation baked in

The output has a `compliance_summary` block:

```json
"compliance_summary": {
    "change_management_active": (merged_count > 0),
    "approval_process_enabled": (approval_rate > 0),
    "review_process_active": (mrs_with_discussion > 0),
    "meets_minimum_review": (approval_rate >= 80),        // hardcoded threshold
    "findings": [
        { "severity": "warning",
          "message": "Only X% of MRs have approvals",
          "recommendation": "Ensure all merge requests..." }
    ]
}
```

Three problems:

1. `meets_minimum_review` hardcodes 80% as the pass threshold — that's *policy*, not data
2. `findings[]` carries severity labels and recommendation strings — those are *judgments and prescriptions*
3. The thresholds aren't customer-configurable

design.md treats compliance mapping as a Paramify-side configuration concern (§ "Two concerns to revisit later"). It's not cross-source comparison, so it doesn't strictly violate the comparator boundary — but it puts policy inside the fetcher.

**Surgical fix:** drop `compliance_summary.meets_minimum_review` and `compliance_summary.findings`. Keep `metrics` (approval_rate, compliance_rate, time-to-merge, etc.) — those are facts. Interpretation moves to a Paramify-side configuration or a separate analyzer.

---

### KnowBe4 training fetchers (3 of 4) — heavy single-source aggregation

`developer_specific_training`, `high_risk_training`, `security_awareness_training` all:

- Fetch from 4 KnowBe4 endpoints (users, groups, campaigns, enrollments)
- Match users to groups by hardcoded group-name substring (e.g. `"Engineering"`, `"Cloud Ops"`)
- Match users to enrollments for hardcoded campaign names
- Compute per-user `user_training_status` (`completed | in_progress | past_due | not_started`) via a state machine on enrollment statuses

This is **internal cross-endpoint correlation, not cross-source comparison** — everything comes from KnowBe4. The state machine is interpretation of KnowBe4's own statuses, which lean fact-like. So:

- ✓ Not a comparator concern (single source)
- ⚠️ Group names (`"Engineering"`, `"Cloud Ops"`, `"DevOps"`) and campaign names (`"Developers Training"`, `"Privileged Users Training (Before CloudOps Access)"`) are hardcoded — that's customer-specific policy embedded in the fetcher

**No immediate fix needed.** If per-customer group/campaign names become a requirement, those move into `config_schema` (or `target_schema` if multi-tenant). The state-machine logic itself can stay.

---

## Options for cleanup

| Option | Action | Cost | When |
|---|---|---|---|
| 1. Accept as-is | Leave all three flagged cases | 0 lines | Default — matches CLAUDE.md's port-as-is principle |
| 2. Surgical cleanup | Drop `"status": "PASS"` in okta_authenticators; drop `compliance_summary` block in gitlab_mr_summary | ~15 lines changed across 2 files | Recommended if compliance interpretation in fetchers becomes a quality concern |
| 3. Full split | Pull all compliance interpretation into a separate "analyzer" layer (similar contract to comparators) | Significant; touches ≥3 fetchers + adds a new framework concept | Not warranted before `depends_on` runner support lands |

---

## Future-proofing — questions for the contract

These came up during the review and should be settled as the contract matures:

- **Is `status: "PASS" | "FAIL"` a fetcher concern or a Paramify-side concern?** Today it's inconsistently applied (only `okta_authenticators` has it, and it's hardcoded). The contract should pick one stance.
- **Are compliance thresholds (e.g. 80% approval rate) customer-configurable?** If yes, they belong in the manifest's `config` block, not the fetcher. If no, they belong on the Paramify side, not the fetcher.
- **Is "analyzer" a distinct framework concept** (between fetcher and comparator), or does the comparator pattern absorb it?

The Rippling cross-reference scripts (`vs_okta_users`, `vs_knowbe4_training`) — currently deferred — are the canonical comparator shape and will help settle the boundary when they're built.

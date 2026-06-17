# KSI → Prowler → Fetcher Mapping (AWS)

**Status:** AWS gaps BUILT on branch `feat/aws-ksi-fetchers` (v0.x — schema +
syntax + discovery validated, smoke-tested with fake creds; pending a real-tenant run)
**Created:** 2026-06-16
**Updated:** 2026-06-16 — all 49 AWS gap fetchers generated (see 🆕 rows)
**Sources of truth:**
- FedRAMP 20x Key Security Indicators, release **25.05C** (Phase One) —
  [github.com/FedRAMP/docs](https://github.com/FedRAMP/docs/blob/main/tools/site/content/20x/phase1/key-security-indicators.md)
- Prowler service collectors (`prowler/providers/aws/services/<svc>/<svc>_service.py`)
- Existing fetchers in this repo (`fetchers/aws/`)

## Purpose

Use Prowler's **service collectors** (NOT its checks) as the spec for *what
cloud-config data to collect*, then build/own fetchers that obey this repo's
manifest contract. This worksheet answers: **for each evidenceable KSI, which
Prowler service supplies the data, what's the fetcher called, and do we already
have it?**

Prowler collects cloud configuration only, so it can evidence the *technical*
KSIs (CNA, SVC, MLA, IAM strongly; CMT/RPL/PIY/TPR partially) and **cannot**
evidence the organizational KSIs (CED training, INR incident reports, most of
PIY policy/staffing, RPL recovery-plan docs, TPR vendor vetting). Those are
served by other integrations (KnowBe4, Rippling, GitLab/GitHub, manual evidence).

## Legend

- ✅ **exists** — original, battle-tested fetcher in `fetchers/aws/`
- 🆕 **built** — generated 2026-06-16 on branch `feat/aws-ksi-fetchers`; passes
  schema + `bash -n` + `paramify list`, smoke-tested with fake creds; **not yet
  run against a real account** (jq field paths verified vs the Prowler spec only)
- 🔲 **gap** — proposed; not yet built
- ⚪ **n/a** — KSI not config-evidenceable; needs a non-cloud source

## Summary

| KSI family | Evidenceable | Existing | 🆕 Built | Remaining gap | Notes |
|---|---|---|---|---|---|
| **CNA** Cloud Native Architecture | ✅ Strong | 7 | 8 | 0 | network, DoS, HA |
| **SVC** Service Configuration | ✅ Strong | 6 | 26 | 0 | 21 at-rest encryption + 5 transit/keys/patch |
| **MLA** Monitoring/Logging/Auditing | ✅ Strong | 3 | 3 | 0 | securityhub, inspector, macie |
| **IAM** Identity & Access | ✅ Strong | 4 | 4 | 0 | password policy, MFA, access analyzer, SCPs |
| **CMT** Change Management | ⚠️ Partial | 2 | 3 | 0 | only CMT-01 (logging), CMT-03 (CI/CD) |
| **RPL** Recovery Planning | ⚠️ Partial | 2 | 3 | 0 | only RPL-03 (backups) |
| **PIY** Policy & Inventory | ⚠️ Partial | 1 | 1 | 0 | only PIY-01 (inventory) |
| **TPR** Third-Party Resources | ⚠️ Partial | 0 | 1 | 0 | TPR-04 (ecr; inspector counted under MLA) |
| **CED** Cyber Education | ⚪ n/a | — | — | — | KnowBe4, training records |
| **INR** Incident Reporting | ⚪ n/a | — | — | — | incident docs / process |

**AWS totals: ~30 original + 49 newly built = 79 AWS fetchers; 0 remaining
config-evidenceable AWS gaps.** (Some fetchers map to more than one KSI, so the
per-family counts overlap slightly — e.g. `aws_inspector_vulnerability_scanning`
serves both MLA and TPR.)

---

## KSI-CNA — Cloud Native Architecture

> Limit traffic (01), minimize attack surface/lateral movement (02), logical
> traffic-flow controls (03), immutable infra (04), DoS protection (05), HA &
> rapid recovery (06), host best-practices (07).

| KSI | Prowler service(s) | Proposed fetcher | Status |
|---|---|---|---|
| CNA-01/02/03 | ec2 (SecurityGroup) | `aws_security_groups` | ✅ exists |
| CNA-01/03 | ec2 (NetworkACL) | `aws_network_acls` | 🆕 built |
| CNA-02 | ec2 (Instance: public_ip, http_tokens) | `aws_ec2_public_exposure` | 🆕 built |
| CNA-03 | vpc (Vpc, Subnet, peering, endpoints) | `aws_vpc_network_segmentation` | 🆕 built |
| CNA-03 / MLA-01 | vpc (FlowLog) | `aws_vpc_flow_logs` | 🆕 built |
| CNA-01/03 | networkfirewall | `aws_network_firewall_rules` | 🆕 built |
| CNA-05 | wafv2 / waf | `aws_waf_all_rules`, `aws_waf_dos_rules` | ✅ exists |
| CNA-05 | shield | `aws_shield_dos_protection` | 🆕 built |
| CNA-05 / SVC-02 | cloudfront | `aws_cloudfront_distribution_security` | 🆕 built |
| CNA-06 | autoscaling | `aws_auto_scaling_high_availability` | ✅ exists |
| CNA-06 | elb / elbv2 | `aws_load_balancer_high_availability` | ✅ exists |
| CNA-06 | rds (multi-AZ) | `aws_database_high_availability` | ✅ exists |
| CNA-06 | efs | `aws_efs_high_availability` | ✅ exists |
| CNA-06 | eks | `aws_eks_high_availability` | ✅ exists |
| CNA-06 | route53 | `aws_route53_high_availability` | ✅ exists |
| CNA-06 | (cross: ec2/vpc/natgw) | `aws_network_resilience_high_availability` | ✅ exists |
| CNA-06 | globalaccelerator | `aws_global_accelerator_ha` | 🆕 built |

---

## KSI-SVC — Service Configuration

> Harden config (01), encrypt traffic (02), encrypt at rest (03), central config
> mgmt (04), integrity via crypto (05), automated key mgmt/rotation (06),
> risk-informed patching (07).

### Encryption in transit (SVC-02) & key management (SVC-06)

| KSI | Prowler service(s) | Proposed fetcher | Status |
|---|---|---|---|
| SVC-02 | elb / elbv2 | `aws_load_balancer_encryption_status` | ✅ exists |
| SVC-02 | rds (TLS) | `aws_rds_tls_configuration` | ✅ exists |
| SVC-02 | (cross: elb/cf/rds/es) | `aws_component_ssl_enforcement_status` | ✅ exists |
| SVC-02 | apigateway / apigatewayv2 | `aws_apigateway_tls_enforcement` | 🆕 built |
| SVC-02 | transfer | `aws_transfer_tls_enforcement` | 🆕 built |
| SVC-06 | kms | `aws_kms_key_rotation` | ✅ exists |
| SVC-06 | acm | `aws_acm_certificate_status` | 🆕 built |
| SVC-06 / IAM-03 | secretsmanager | `aws_secrets_manager_rotation` | 🆕 built |
| SVC-04 / MLA-05 | config | `aws_config_monitoring`, `aws_config_conformance_packs` | ✅ exists |
| SVC-01/07 | ssm | `aws_ssm_patch_compliance` | 🆕 built |

### Encryption at rest (SVC-03) — bulk template opportunity

All of these are the same `describe → read encryption config` shape. The 21
below were cloned from the three original templates — `aws_s3_encryption_status`,
`aws_rds_encryption_status`, `aws_block_storage_encryption_status` (EBS) — and
mirror their `results: {<items>:[], summary:{...}}` object shape.

| Prowler service | Proposed fetcher | Status |
|---|---|---|
| s3 | `aws_s3_encryption_status` | ✅ exists |
| rds | `aws_rds_encryption_status` | ✅ exists |
| ec2 (EBS volumes/default) | `aws_block_storage_encryption_status` | ✅ exists |
| dynamodb | `aws_dynamodb_encryption_status` | 🆕 built |
| efs | `aws_efs_encryption_status` | 🆕 built |
| elasticache | `aws_elasticache_encryption_status` | 🆕 built |
| memorydb | `aws_memorydb_encryption_status` | 🆕 built |
| redshift | `aws_redshift_encryption_status` | 🆕 built |
| opensearch | `aws_opensearch_encryption_status` | 🆕 built |
| documentdb | `aws_documentdb_encryption_status` | 🆕 built |
| neptune | `aws_neptune_encryption_status` | 🆕 built |
| athena | `aws_athena_encryption_status` | 🆕 built |
| sns | `aws_sns_encryption_status` | 🆕 built |
| sqs | `aws_sqs_encryption_status` | 🆕 built |
| kinesis | `aws_kinesis_encryption_status` | 🆕 built |
| firehose | `aws_firehose_encryption_status` | 🆕 built |
| glue | `aws_glue_encryption_status` | 🆕 built |
| sagemaker | `aws_sagemaker_encryption_status` | 🆕 built |
| fsx | `aws_fsx_encryption_status` | 🆕 built |
| glacier | `aws_glacier_encryption_status` | 🆕 built |
| emr | `aws_emr_encryption_status` | 🆕 built |
| kafka (MSK) | `aws_kafka_encryption_status` | 🆕 built |
| dms | `aws_dms_encryption_status` | 🆕 built |
| codeartifact | `aws_codeartifact_encryption_status` | 🆕 built |

---

## KSI-MLA — Monitoring, Logging, and Auditing

> Centralized tamper-resistant logging/SIEM (01), review/audit logs (02), detect
> & remediate vulns (03), authenticated vuln scanning (04), IaC/config eval (05),
> central vuln tracking (06).

| KSI | Prowler service(s) | Proposed fetcher | Status |
|---|---|---|---|
| MLA-01 / CMT-01 | cloudtrail | `aws_cloudtrail_configuration` | ✅ exists |
| MLA-01/05 / CMT-01 | config | `aws_config_monitoring` | ✅ exists |
| MLA-01 | cloudwatch (alarms/log groups) | `aws_cloudwatch_high_availability` | ✅ exists (HA angle) |
| MLA-03 / IAM-06 | guardduty | `aws_guard_duty` | ✅ exists |
| MLA-01/06 | securityhub | `aws_securityhub_status` | 🆕 built |
| MLA-03/04 / TPR-04 / SVC-07 | inspector2 | `aws_inspector_vulnerability_scanning` | 🆕 built |
| MLA-03 | macie | `aws_macie_data_discovery` | 🆕 built |

---

## KSI-IAM — Identity and Access Management

> Phishing-resistant MFA (01), passwordless/strong-password+MFA (02), secure
> non-user/service auth (03), least-privilege RBAC/ABAC/JIT (04), zero trust
> (05), auto-disable privileged accounts on suspicious activity (06).

| KSI | Prowler service(s) | Proposed fetcher | Status |
|---|---|---|---|
| IAM-01/02/04 | iam (users, groups, MFA) | `aws_iam_users_groups` | ✅ exists |
| IAM-03/04 | iam (roles) | `aws_iam_roles` | ✅ exists |
| IAM-04 | iam (policies) | `aws_iam_policies` | ✅ exists |
| IAM-01/04 | (Identity Center / SSO) | `aws_iam_identity_center` | ✅ exists |
| IAM-04 | eks (RBAC) | `aws_eks_least_privilege` | ✅ exists |
| IAM-02 | iam (account password policy) | `aws_iam_password_policy` | 🆕 built |
| IAM-01 | iam (root/user MFA, hardware MFA) | `aws_iam_mfa_status` | 🆕 built |
| IAM-04 | accessanalyzer | `aws_access_analyzer_findings` | 🆕 built |
| IAM-04 | organizations (SCPs) | `aws_organizations_scp` | 🆕 built |

---

## KSI-CMT — Change Management (partial)

> Only CMT-01 (log/monitor modifications) and CMT-03 (automated test/validation
> of changes) are config-evidenceable. CMT-02/04/05 are process/policy.

| KSI | Prowler service(s) | Proposed fetcher | Status |
|---|---|---|---|
| CMT-01 | cloudtrail / config | `aws_cloudtrail_configuration`, `aws_config_monitoring` | ✅ exists |
| CMT-01 / PIY-01 | config (resource changes) | `aws_detect_new_aws_resource` | ✅ exists |
| CMT-02 / MLA-05 | cloudformation (drift) | `aws_cloudformation_drift` | 🆕 built |
| CMT-03 | codebuild | `aws_codebuild_pipeline_config` | 🆕 built |
| CMT-03 | codepipeline | `aws_codepipeline_config` | 🆕 built |

---

## KSI-RPL — Recovery Planning (partial)

> Only RPL-03 (system backups) is config-evidenceable. RPL-01/02/04 are
> objectives/plans/test-records.

| KSI | Prowler service(s) | Proposed fetcher | Status |
|---|---|---|---|
| RPL-03 | backup (plans/coverage) | `aws_backup_validation` | ✅ exists |
| RPL-03 / CNA-06 | backup (recovery points) | `aws_backup_recovery_high_availability` | ✅ exists |
| RPL-03 | dynamodb (PITR) | `aws_dynamodb_pitr_status` | 🆕 built |
| RPL-03 | ec2 (EBS snapshots) | `aws_ebs_snapshot_status` | 🆕 built |
| RPL-03 | dlm (snapshot lifecycle) | `aws_dlm_lifecycle_policies` | 🆕 built |

---

## KSI-PIY — Policy & Inventory (partial)

> Only PIY-01 (up-to-date asset inventory or code) is config-evidenceable.
> PIY-02..07 are policies/SDLC/staffing/supply-chain decisions.

| KSI | Prowler service(s) | Proposed fetcher | Status |
|---|---|---|---|
| PIY-01 / CMT-01 | config (resource changes) | `aws_detect_new_aws_resource` | ✅ exists |
| PIY-01 | resourceexplorer2 / config | `aws_resource_inventory` | 🆕 built |

---

## KSI-TPR — Third-Party Information Resources (partial)

> Only TPR-04 (monitor third-party software for upstream vulns) is
> config-evidenceable. TPR-01/02/03 are identification/vetting/process.

| KSI | Prowler service(s) | Proposed fetcher | Status |
|---|---|---|---|
| TPR-04 | ecr (image scan findings) | `aws_ecr_image_scanning` | 🆕 built |
| TPR-04 / MLA-03 | inspector2 (SBOM/CVE) | `aws_inspector_vulnerability_scanning` | 🆕 built (shared w/ MLA) |

---

## Not config-evidenceable (no Prowler mapping)

| KSI family | Why | Paramify source instead |
|---|---|---|
| **CED** Cyber Education (01–02) | training completion records | KnowBe4 fetchers (`fetchers/knowbe4/`) |
| **INR** Incident Reporting (01–03) | incident docs, after-action reports | manual evidence / ticketing |
| **CMT-04/05**, **PIY-02..07**, **RPL-01/02/04**, **TPR-01/02/03** | policies, plans, staffing, vendor vetting | manual / GRC evidence |

---

## Cross-provider note

This worksheet is AWS-only (largest surface, most existing fetchers). The same
KSI families map to every other Prowler provider — full per-service tables for
Azure, GCP, Kubernetes, M365/Entra, GitHub, Google Workspace, Cloudflare, Okta,
and the niche clouds live in the companion doc:
[`ksi_prowler_mapping_other_providers.md`](ksi_prowler_mapping_other_providers.md).

Build per the CSO's actual stack, not all 14 Prowler providers.

## Status & next steps

All 49 AWS gaps in this worksheet are now built (the 🆕 rows), on branch
`feat/aws-ksi-fetchers` — **79 AWS fetchers total, 0 remaining config-evidenceable
AWS gaps.** They pass schema + `bash -n` + `paramify list` discovery and were
smoke-tested with fake creds (correct `{metadata, results}` envelope, failure
tracking → non-zero exit, regional/global filename split). The outstanding step:

1. **Real-tenant run** — execute against a real AWS profile (read-only
   describe/list/get) to validate jq field paths against live API responses; the
   exit-non-zero-on-failure contract surfaces any path mismatches fast.
2. **Extend to other clouds** — same method, against
   [`ksi_prowler_mapping_other_providers.md`](ksi_prowler_mapping_other_providers.md):
   pick a row → read the Prowler service's pydantic models → port per
   [`porting_playbook.md`](porting_playbook.md) (discard Prowler's region-threading,
   Provider/auth stack, and silent error-swallowing; add failure-tracking + retry).

Each fetcher's `evidence_set.reference_id` uses the repo's `EVD-*` convention,
with the mapped FedRAMP KSI recorded in its `instructions`.

# KSI → Prowler → Fetcher Mapping (non-AWS providers)

**Status:** Planning worksheet / build backlog
**Created:** 2026-06-16
**Companion to:** [`ksi_prowler_mapping.md`](ksi_prowler_mapping.md) (AWS)
**Sources of truth:**
- FedRAMP 20x KSIs, release **25.05C** (Phase One) —
  [github.com/FedRAMP/docs](https://github.com/FedRAMP/docs/blob/main/tools/site/content/20x/phase1/key-security-indicators.md)
- Prowler service collectors (`prowler/providers/<provider>/services/<svc>/<svc>_service.py`)

## Scope

Same method as the AWS worksheet: Prowler service collectors are the **spec for
what cloud-config data to collect**; build fetchers that obey this repo's
manifest contract. Only the *technically-observable* KSIs are listed
(CNA/SVC/MLA/IAM strong; CMT/RPL/PIY/TPR partial). CED + INR are never
config-evidenceable.

**Build per the CSO's actual stack — not all 14 providers.** A real FedRAMP
authorization runs on one primary cloud + identity + code tooling. The niche
clouds (Oracle, Alibaba, OpenStack, NHN, Vercel, MongoDB Atlas) are included for
completeness but only matter if a customer actually uses them.

## Legend

- ✅ **exists** — fetcher already in this repo
- 🔲 **gap** — proposed; Prowler service exists as the spec
- ⚪ **marginal** — Prowler service exists but evidence value is thin; defer

## Per-provider summary

| Provider | Prowler svcs | KSI-mappable | Existing fetchers | Est. fetchers | Priority |
|---|---|---|---|---|---|
| **Azure** | 22 | ~18 | 0 (stub category) | ~25–30 | High (if Azure CSO) |
| **GCP** | 15 | ~13 | 0 | ~20–25 | High (if GCP CSO) |
| **Kubernetes** | 7 | 7 | 3 | ~10–12 | High (containers) |
| **M365 / Entra** | 10 | ~9 | 0 | ~20–25 | High (corp identity) |
| **GitHub** | 3 | 3 | 0 (GitLab built instead) | ~6–8 | Medium (CMT/SDLC) |
| **Google Workspace** | 4 | ~3 | 0 | ~5–6 | Medium (identity) |
| **Cloudflare** | 3 | 3 | 0 | ~4–5 | Medium (edge/DoS) |
| **Okta** | 1 (signon) | 1 → IAM-01..06 | 8 | 8 | ✅ done |
| **Oracle Cloud** | 14 | ~11 | 0 | ~18–22 | Low (stack-dependent) |
| **Alibaba Cloud** | 9 | ~8 | 0 | ~12–15 | Low |
| **OpenStack** | 5 | 5 | 0 | ~8–10 | Low |
| **NHN** | 2 | 2 | 0 | ~3–4 | Low |
| **Vercel** | 6 | ~5 | 0 | ~6–8 | Low |
| **MongoDB Atlas** | 3 | 3 | 0 | ~5–6 | Low (if used) |

---

## Azure (22 services)

| Prowler service | KSI(s) | Proposed fetcher | Status |
|---|---|---|---|
| network | CNA-01/02/03 | `azure_network_security_groups` | 🔲 gap |
| vm | CNA-02, SVC-03, SVC-07 | `azure_vm_disk_encryption`, `azure_vm_public_exposure` | 🔲 gap |
| storage | SVC-03, SVC-02, CNA-01 | `azure_storage_encryption_status` | 🔲 gap |
| keyvault | SVC-06 | `azure_keyvault_key_rotation` | 🔲 gap |
| sqlserver | SVC-02/03, MLA-02 | `azure_sql_encryption_tls`, `azure_sql_auditing` | 🔲 gap |
| mysql | SVC-02/03 | `azure_mysql_encryption_tls` | 🔲 gap |
| postgresql | SVC-02/03 | `azure_postgresql_encryption_tls` | 🔲 gap |
| cosmosdb | SVC-03, CNA-01 | `azure_cosmosdb_encryption_status` | 🔲 gap |
| storage/app | SVC-02 | `azure_app_service_https_enforcement` | 🔲 gap |
| apim | SVC-02, CNA | `azure_apim_tls_enforcement` | 🔲 gap |
| entra | IAM-01/02/04/06 | `azure_entra_mfa_conditional_access` | 🔲 gap |
| iam | IAM-04 | `azure_rbac_role_assignments` | 🔲 gap |
| defender | MLA-01/03 | `azure_defender_for_cloud_status` | 🔲 gap |
| monitor | MLA-01, CMT-01 | `azure_monitor_diagnostic_settings` | 🔲 gap |
| logs | MLA-01/02 | `azure_log_analytics_config` | 🔲 gap |
| policy | SVC-04, MLA-05 | `azure_policy_compliance` | 🔲 gap |
| recovery | RPL-03 | `azure_backup_recovery_status` | 🔲 gap |
| containerregistry | TPR-04, SVC-03 | `azure_acr_image_scanning` | 🔲 gap |
| aks | CNA-06, IAM-04 | `azure_aks_security_config` | 🔲 gap |
| databricks | SVC-03, CNA | `azure_databricks_encryption` | ⚪ marginal |
| aisearch | SVC-03 | — | ⚪ marginal |
| appinsights | MLA-01 | (folds into monitor) | ⚪ marginal |

---

## GCP (15 services)

| Prowler service | KSI(s) | Proposed fetcher | Status |
|---|---|---|---|
| compute | CNA-01/02, SVC-03 | `gcp_compute_firewall`, `gcp_compute_disk_encryption` | 🔲 gap |
| cloudstorage | SVC-03, CNA-01 | `gcp_storage_encryption_status` | 🔲 gap |
| cloudsql | SVC-02/03 | `gcp_cloudsql_encryption_tls` | 🔲 gap |
| bigquery | SVC-03 | `gcp_bigquery_encryption_status` | 🔲 gap |
| kms | SVC-06 | `gcp_kms_key_rotation` | 🔲 gap |
| iam | IAM-03/04 | `gcp_iam_service_accounts`, `gcp_iam_policies` | 🔲 gap |
| cloudresourcemanager | IAM-04, PIY-01 | `gcp_org_iam_policy` | 🔲 gap |
| accesscontextmanager | IAM-05 | `gcp_vpc_service_controls` | 🔲 gap |
| apikeys | IAM-03 | `gcp_api_keys_audit` | 🔲 gap |
| logging | MLA-01 | `gcp_audit_logging_config` | 🔲 gap |
| monitoring | MLA-01 | `gcp_monitoring_config` | 🔲 gap |
| gke | CNA-06, IAM-04 | `gcp_gke_security_config` | 🔲 gap |
| artifacts / gcr | TPR-04 | `gcp_artifact_registry_scanning` | 🔲 gap |
| dns | CNA-06, MLA-01 | `gcp_dns_security` | 🔲 gap |
| serviceusage | PIY-01, TPR-01 | `gcp_enabled_services_inventory` | ⚪ marginal |
| dataproc | SVC-03 | `gcp_dataproc_encryption` | ⚪ marginal |
| gemini | — | — | ⚪ marginal |

---

## Kubernetes (7 control-plane services)

CIS-Kubernetes-style control-plane + workload posture. The repo already has 3
k8s fetchers.

| Prowler service | KSI(s) | Proposed fetcher | Status |
|---|---|---|---|
| rbac | IAM-04 | `k8s_eks_microservice_segmentation` / RBAC | ✅ exists (segmentation) |
| core | CNA-01/03, SVC-03 (secrets) | `k8s_kubectl_security`, `k8s_eks_pod_inventory` | ✅ exists |
| apiserver | MLA-01 (audit), IAM, SVC-01 | `k8s_apiserver_hardening` | 🔲 gap |
| etcd | SVC-03 (encryption at rest), SVC-05 | `k8s_etcd_encryption` | 🔲 gap |
| kubelet | SVC-01, CNA-02 | `k8s_kubelet_hardening` | 🔲 gap |
| controllermanager | SVC-01 | `k8s_controlplane_hardening` | 🔲 gap |
| scheduler | SVC-01 | (folds into controlplane hardening) | 🔲 gap |

---

## M365 / Entra (10 services)

| Prowler service | KSI(s) | Proposed fetcher | Status |
|---|---|---|---|
| entra | IAM-01/02/04/06 | `m365_entra_mfa_conditional_access` | 🔲 gap |
| defender | MLA-03 | `m365_defender_for_office_status` | 🔲 gap |
| defenderidentity | MLA-03, IAM-06 | `m365_defender_identity_status` | 🔲 gap |
| defenderxdr | MLA-01/03 | `m365_defender_xdr_status` | 🔲 gap |
| exchange | SVC-02, MLA-02 | `m365_exchange_mail_security` | 🔲 gap |
| intune | CMT-01, SVC-01, PIY-01 | `m365_intune_device_compliance` | 🔲 gap |
| purview | SVC-03, MLA-02 | `m365_purview_dlp_audit` | 🔲 gap |
| sharepoint | SVC-03, IAM-04 | `m365_sharepoint_sharing_controls` | 🔲 gap |
| teams | IAM-04, SVC-02 | `m365_teams_external_access` | 🔲 gap |
| admincenter | PIY-01, IAM-04 | `m365_admin_security_settings` | 🔲 gap |

---

## GitHub (3 services)

Prowler covers GitHub; this repo built **GitLab** fetchers instead. Map these if
the CSO uses GitHub for source/CI.

| Prowler service | KSI(s) | Proposed fetcher | Status |
|---|---|---|---|
| repository | CMT-02 (branch protection), PIY-04 (SDLC), TPR-04 | `github_repository_security` | 🔲 gap |
| githubactions | CMT-03 (CI/CD validation), TPR | `github_actions_cicd_config` | 🔲 gap |
| organization | IAM-04, PIY-01 | `github_org_access_inventory` | 🔲 gap |

> Equivalent GitLab evidence already exists: `gitlab_ci_cd_pipeline_config`,
> `gitlab_project_summary`, `gitlab_merge_request_summary`.

---

## Google Workspace (4 services)

| Prowler service | KSI(s) | Proposed fetcher | Status |
|---|---|---|---|
| directory | IAM-01/02, PIY-01 | `gworkspace_user_mfa_status` | 🔲 gap |
| drive | SVC-03, IAM-04 | `gworkspace_drive_sharing_controls` | 🔲 gap |
| gmail | SVC-02 | `gworkspace_gmail_tls_enforcement` | 🔲 gap |
| calendar | — | — | ⚪ marginal |

---

## Cloudflare (3 services)

| Prowler service | KSI(s) | Proposed fetcher | Status |
|---|---|---|---|
| firewall | CNA-01/05 | `cloudflare_waf_ddos_rules` | 🔲 gap |
| zone | SVC-02, CNA-05 | `cloudflare_tls_settings` | 🔲 gap |
| dns | CNA-06, MLA-01 | `cloudflare_dns_security` | 🔲 gap |

---

## Okta (1 service: `signon`) — already built

Prowler exposes one `signon` collector. This repo already has full IAM coverage
mapped to KSI-IAM sub-indicators:

| KSI | Existing fetcher | Status |
|---|---|---|
| IAM-01 | `okta_phishing_resistant_mfa` | ✅ exists |
| IAM-02 | `okta_passwordless_authentication` | ✅ exists |
| IAM-03 | `okta_non_user_accounts_authentication` | ✅ exists |
| IAM-04 | `okta_least_privilege`, `okta_just_in_time_authorization` | ✅ exists |
| IAM-06 | `okta_suspicious_activity_management`, `okta_automated_account_management` | ✅ exists |
| (auth methods) | `okta_authenticators` | ✅ exists |

---

## Niche clouds — include only if the CSO uses them

### Oracle Cloud (14 services)

| Prowler service | KSI(s) | Proposed fetcher |
|---|---|---|
| network | CNA-01/03 | `oraclecloud_network_security` |
| compute | CNA-02, SVC-03 | `oraclecloud_compute_security` |
| blockstorage / filestorage | SVC-03 | `oraclecloud_storage_encryption` |
| objectstorage | SVC-03, CNA-01 | `oraclecloud_object_storage_security` |
| database | SVC-02/03 | `oraclecloud_database_encryption` |
| kms | SVC-06 | `oraclecloud_kms_key_rotation` |
| identity | IAM-04 | `oraclecloud_iam_policies` |
| cloudguard | MLA-03 | `oraclecloud_cloudguard_status` |
| audit / logging / events | MLA-01 | `oraclecloud_audit_logging` |
| analytics / integration | ⚪ marginal | — |

### Alibaba Cloud (9 services)

| Prowler service | KSI(s) | Proposed fetcher |
|---|---|---|
| vpc | CNA-01/03 | `alibaba_vpc_security` |
| ecs | CNA-02, SVC-03 | `alibaba_ecs_security` |
| oss | SVC-03, CNA-01 | `alibaba_oss_encryption` |
| rds | SVC-02/03 | `alibaba_rds_encryption` |
| ram | IAM-04 | `alibaba_ram_policies` |
| actiontrail / sls | MLA-01 | `alibaba_audit_logging` |
| securitycenter | MLA-03 | `alibaba_security_center_status` |
| cs (container) | CNA, IAM | `alibaba_container_security` |

### OpenStack (5 services)

| Prowler service | KSI(s) | Proposed fetcher |
|---|---|---|
| networking | CNA-01/03 | `openstack_network_security` |
| compute | CNA-02, SVC-03 | `openstack_compute_security` |
| blockstorage | SVC-03 | `openstack_blockstorage_encryption` |
| objectstorage | SVC-03 | `openstack_objectstorage_security` |
| image | TPR-04, SVC-05 | `openstack_image_integrity` |

### NHN (2 services)

| Prowler service | KSI(s) | Proposed fetcher |
|---|---|---|
| network | CNA-01/03 | `nhn_network_security` |
| compute | CNA-02, SVC-03 | `nhn_compute_security` |

### Vercel (6 services)

| Prowler service | KSI(s) | Proposed fetcher |
|---|---|---|
| security | CNA-05, SVC | `vercel_security_settings` |
| authentication | IAM-01/02 | `vercel_authentication` |
| domain | SVC-02 | `vercel_domain_tls` |
| deployment | CMT-02/03 | `vercel_deployment_config` |
| project / team | PIY-01, IAM-04 | `vercel_project_access` |

### MongoDB Atlas (3 services)

| Prowler service | KSI(s) | Proposed fetcher |
|---|---|---|
| clusters | SVC-03, CNA-01, CNA-06 | `mongodbatlas_cluster_security` |
| organizations | IAM-04 | `mongodbatlas_org_access` |
| projects | IAM-04, MLA-02 | `mongodbatlas_project_audit` |

---

## How to use

Identical workflow to the AWS worksheet — pick a 🔲 gap, read the Prowler
service's pydantic models for the field spec, port per
[`porting_playbook.md`](porting_playbook.md), and set
`evidence_set.reference_id` to the mapped KSI. See
[`ksi_prowler_mapping.md`](ksi_prowler_mapping.md) for the detailed AWS backlog
and the full method writeup.

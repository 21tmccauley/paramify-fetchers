# Plan: run the collector on local Kubernetes (for learning)

> ✅ **Picked up.** This checklist is now realized as apply-and-watch YAML +
> walkthrough in [`k8s/`](k8s/) — see [`k8s/LOCAL_K8S.md`](k8s/LOCAL_K8S.md). This
> file remains as the "why / what to internalize" rationale behind it.

**Goal:** see the EKS deployment model with your own eyes locally — a `CronJob`
spins up a throwaway Pod, secrets land as env vars, the collector runs
collect→upload, the Pod disappears, evidence is transient. ~90% of the YAML is
identical to real EKS.

**Not on the beta critical path** — this is to build intuition. Budget ~an afternoon.

---

## Prerequisites
- [ ] Docker Desktop installed (you have this).
- [ ] `kubectl` available (`kubectl version --client`; comes with Docker Desktop or `brew install kubectl`).
- [ ] The collector image built locally (`docker compose -f deploy/docker-compose.yml build`).
- [ ] Temporary AWS creds handy (`aws configure export-credentials --format env-no-export`) and the test SM secret from the local-Docker run.

## Steps
1. [ ] **Stand up a local cluster** — easiest: Docker Desktop → Settings → Kubernetes → Enable. (Alternative: `brew install kind && kind create cluster`.)
2. [ ] **Make the cluster see the local image** — Docker Desktop: set `imagePullPolicy: Never` in the Pod spec. kind: `kind load docker-image paramify-fetchers:beta`.
3. [ ] **Create a Secret** with the AWS creds + region (the local stand-in for IRSA):
       `kubectl create secret generic aws-creds --from-literal=AWS_ACCESS_KEY_ID=... --from-literal=AWS_SECRET_ACCESS_KEY=... --from-literal=AWS_SESSION_TOKEN=... --from-literal=AWS_REGION=...`
4. [ ] **Create a ConfigMap** holding a manifest (so you see the "manifest from ConfigMap, not baked in" pattern): `kubectl create configmap daily-manifest --from-file=daily.yaml=deploy/manifests/daily.yaml`.
5. [ ] **Apply a CronJob** that runs the image, mounts the manifest, and pulls env from the Secret (+ `PARAMIFY_SECRETS_ID`). (Claude can generate this — see below.)
6. [ ] **Trigger a run on demand** (don't wait for the schedule):
       `kubectl create job --from=cronjob/paramify-daily test-1`
7. [ ] **Watch it**: `kubectl get pods -w`, then `kubectl logs job/test-1`.
8. [ ] **Observe the lifecycle**: Pod appears → loads secrets → collect+upload → Pod `Completed` → gone. Note there's no persistent volume and no long-running process.
9. [ ] **Teardown**: `kubectl delete cronjob/paramify-daily configmap/daily-manifest secret/aws-creds` (and disable Docker Desktop K8s / `kind delete cluster`).

## What to internalize
- **Kubernetes is the scheduler** (the CronJob controller) — no host process you run.
- **Each run is an ephemeral Pod**; secrets + evidence live and die with it.
- **Manifest via ConfigMap** = change what's collected without rebuilding the image.
- The YAML you write here is what runs on EKS, with **two changes for prod**:
  the static-creds `Secret` is replaced by an **IRSA-annotated ServiceAccount**,
  and you'd point at a registry image instead of the local one.

## Gotchas to remember
- `ImagePullBackOff` → you forgot step 2 (image not visible to the cluster).
- **IRSA is EKS-only** — can't be tested locally; the Secret simulates "creds in the Pod."
- Use `kubectl create job --from=cronjob/...` to trigger instantly instead of waiting on the schedule.

## When you're ready
Ask Claude to generate **`deploy/k8s/`** — a `CronJob`, a `ConfigMap`-mounted
manifest, and a local `Secret` — plus a full `LOCAL_K8S.md` walkthrough, with the
exact two lines flagged that change for real EKS + IRSA. That turns this checklist
into apply-and-watch.

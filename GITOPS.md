# Git Operation (Gitea/ArgoCD)

This document describes how to migrate dependencies from GitHub (`github.com/synrc`)
to a locally managed Gitea instance for local development and build reproducibility
on macOS/Windows/Linux. This Gitea instance is also used as source of truth for
ArgoCD cluster controller.

## Full Bootstrap Sequence (macOS / M1)

Run these commands in order after every macOS reboot or fresh cluster setup:

```bash
# 1. Start local Gitea and mirror GitHub repos
./gitops.sh all

# 2. Create the KinD cluster (auto-generates kind-config.yaml for current user)
./kind.sh create synrc

# 3. Switch kubectl to the KinD context
./kind.sh kind
# Verify: kubectl config current-context  →  kind-synrc
# Verify: kubectl get nodes               →  synrc-control-plane Ready

# 4. Deploy base layer (namespaces, RBAC, storage, infra services)
./deploy.sh

# 5. Build all custom ERP images from local Dockerfiles and load into KinD
#    (pulls source from local Gitea via host.docker.internal:3000)
./rebuild.sh

# 6. Generate unified Helm values
./values.rb --force

# 7. Deploy ArgoCD + push CD repo to Gitea + set up port-forward
./argocd.sh
```

> **Note — M1/ARM64**: `./kind.sh create` automatically regenerates `kind-config.yaml`
> using your current `$HOME`, so the `hostPath` for local storage is always correct
> regardless of which user is running the script.

> **Note — First boot image pull**: On the first run, ArgoCD pulls ~186 MB of ARM64
> images. The rollout timeout is set to 300 s. If it still times out, all pods will
> be Running shortly after — just re-run `./argocd.sh` (it is idempotent).

### Clean Restart

```bash
./delete.sh          # deletes K8s namespaces + KinD cluster
./kind.sh create synrc
./kind.sh kind
./deploy.sh
./rebuild.sh
./values.rb --force
./argocd.sh
```

---

## Why Gitea?

* **Lightweight & Fast**: SQLite-backed Gitea starts in under 5 seconds and uses
  minimal resources (less than 100MB of RAM), making it ideal for local MacBook environments.

* **Local Reproducibility**: Pulling from in-cluster or local resources avoids rate limits,
  network failures, or dependency drift due to deleted external repositories.

* **No Web Install Wizard Required**: Custom configuration variables pre-seed Gitea
  and bypass the installation screen completely.

## Why ArgoCD?

The problem it solves:

* kubectl apply from CI/CD is fragile
* No source of truth for what's running
* Manual syncing between Git and cluster
* Can't audit who deployed what

Key concepts:

* GitOps: Git is source of truth for cluster state
* Continuous sync: ArgoCD keeps cluster matching Git
* Rollback: Revert to any previous commit

When to use it:

* Want declarative deployments
* Need visibility into what's deployed
* Multiple environments to manage

When to skip it:

* CI/CD pipeline works fine
* Team isn't ready for GitOps

## Step 1: Run Gitea and Migrate Repositories

All steps (startup, user creation, org/repo creation, and mirroring) are automated by the `gitops.sh` script.
Run the script with the `all` command: `./gitops.sh all`, This performs the following actions:

* Starts the Gitea container via [compose/gitea.yaml](compose/gitea.yaml).
* Provisions the admin user (`root` with password `ErpUnoGitea2026`).
* Creates the `synrc` organization.
* Initializes repositories for `ca`, `ns`, and `ldap`.
* Performs a bare-clone from GitHub and mirrors all branches/tags directly to Gitea.

### Verification

You can verify Gitea is running and populated by visiting: [http://localhost:3000/synrc](http://localhost:3000/synrc)

## Step 2: Docker Builds with Gitea Source

The Dockerfiles for `ca-pki`, `ns-dns`, and `ldap-directory` have been updated to accept a build argument `GIT_SOURCE`.

### Default configuration (for macOS and Windows)

By default, the Dockerfiles assume Gitea is running on the host machine and use `host.docker.internal:3000` to access it:

```dockerfile
ARG GIT_SOURCE=http://host.docker.internal:3000
RUN git clone ${GIT_SOURCE}/synrc/ca.git .
```

Docker Desktop automatically resolves `host.docker.internal` to the host machine during `docker build`.

### Building all images at once

Use `./rebuild.sh` to build every service that has a `build.sh` in `lib/` and load the
resulting image directly into the KinD cluster:

```bash
./rebuild.sh
```

This script:
1. Resets and re-creates the in-cluster `docker-registry`
2. Finds every `lib/**/build.sh` and runs `docker build` + `kind load docker-image`
3. Re-runs `./deploy.sh` to bring updated pods online

### Building with a custom Git Server

If Gitea is running on a different server or IP, you can override the source URL during build using `--build-arg`:

```bash
docker build --build-arg GIT_SOURCE=http://192.168.1.50:3000 -t erpuno/ca-pki:latest .
```

## Management Commands

* **Check Status**: `./gitops.sh status` Check container and migrated repository health
* **Stop Gitea**: `./gitops.sh stop` Shutdown the container
* **Start Gitea**: `./gitops.sh setup`
* **Force Re-Migration**: `./gitops.sh migrate` Pull fresh updates from GitHub and overwrite Gitea contents
* **Rebuild all images**: `./rebuild.sh`
* **Inspect registry**: `./images.sh` or `./images.sh --local` (also shows KinD-loaded images)

## Step 3: ArgoCD GitOps Integration

To verify and execute GitOps deployments inside the Kind cluster using ArgoCD:

1. **Publish the CD repository to Gitea**:

   The `cd` repository containing your deployment manifests and Helm chart must be hosted in Gitea.
   Running the `./argocd.sh` script automatically handles Gitea repository creation and pushes the current local repository state.

2. **Deploy ArgoCD and application**:

   Initialize ArgoCD by running the setup script:

   ```bash
   ./argocd.sh
   ```

   This script installs ArgoCD into the `argocd` namespace, configures an Ingress resource
   (using the cluster's Traefik ingress controller) for access, and deploys the `erp-uno` root
   Application pointing to the `helm/` directory.

3. **Accessing the ArgoCD Console**:

   Add the domain name resolution to your host machine's `/etc/hosts` file:

   ```text
   127.0.0.1 argocd.erp-uno.local
   ```

   Navigate to [http://argocd.erp-uno.local](http://argocd.erp-uno.local).

   To obtain the auto-generated ArgoCD admin password:

   ```bash
   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
   ```

### Port Forwarding and CLI Fallback

If the UI domain is not accessible (or you cannot edit `/etc/hosts`), you can port-forward the server port directly to your host:

```bash
kubectl port-forward -n argocd svc/argocd-server 8080:80
```

The console will then be accessible at [http://localhost:8080](http://localhost:8080).
To make this port forwarding tunnel permanent on macOS (surviving restarts and running
automatically in the background), install the provided LaunchAgent configuration:

```bash
cp argocd/uno.erp.argocd-portforward.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/uno.erp.argocd-portforward.plist
```

To use the ArgoCD command-line tool (CLI) on macOS:

```bash
brew install argocd
```

With the port forwarding tunnel running, retrieve the credentials and authenticate the client:

```bash
PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
argocd login localhost:8080 --insecure --username admin --password "$PASSWORD"
```

Once logged in, the context is stored locally and you can manage the sync state of the application directly:

```bash
# Check the application status
argocd app get erp-uno

# Trigger manual synchronization
argocd app sync erp-uno
```

Note: If you run these commands without first logging in (or if the config file context is not found),
you will receive a fatal `"Argo CD server address unspecified"` error. You can bypass this by explicitly
providing the server address and security flags on every execution:

```bash
# Get application status directly
argocd --server localhost:8080 --insecure app get erp-uno

# Trigger manual synchronization directly
argocd --server localhost:8080 --insecure app sync erp-uno
```

# Credits

* [5HT](https://5ht.co)

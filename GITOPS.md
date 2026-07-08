# GitOps Local Source Migration (Gitea)

This document describes how to migrate dependencies from GitHub (`github.com/synrc`)
to a locally managed Gitea instance for local development and build reproducibility
on macOS/Windows/Linux.

## Why Gitea?

1. **Lightweight & Fast**: SQLite-backed Gitea starts in under 5 seconds and uses
   minimal resources (less than 100MB of RAM), making it ideal for local MacBook environments.

2. **Local Reproducibility**: Pulling from in-cluster or local resources avoids rate limits,
   network failures, or dependency drift due to deleted external repositories.

3. **No Web Install Wizard Required**: Custom configuration variables pre-seed Gitea
   and bypass the installation screen completely.

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

### Building with a custom Git Server

If Gitea is running on a different server or IP, you can override the source URL during build using `--build-arg`:

```bash
docker build --build-arg GIT_SOURCE=http://192.168.1.50:3000 -t erpuno/ca-pki:latest .
```

## Management Commands

* **Check Status**: `./gitops.sh status` Check container and migrated repository health:
* **Stop Gitea**: `./gitops.sh stop` Shutdown the container:
* **Start Gitea**: `./gitops.sh setup`
* **Force Re-Migration**: `./gitops.sh migrate` Pull fresh updates from GitHub and overwrite Gitea contents:

## Step 3: ArgoCD GitOps Integration

To verify and execute GitOps deployments inside the Kind cluster using ArgoCD:

1. **Publish the CD repository to Gitea**:
   The `cd` repository containing your deployment manifests and Helm chart must be hosted in Gitea. Running the `./argocd.sh` script automatically handles Gitea repository creation and pushes the current local repository state.

2. **Deploy ArgoCD and application**:
   Initialize ArgoCD by running the setup script:
   ```bash
   ./argocd.sh
   ```
   This script installs ArgoCD into the `argocd` namespace, configures an Ingress resource (using the cluster's Traefik ingress controller) for access, and deploys the `erp-uno` root Application pointing to the `helm/` directory.

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

To make this port forwarding tunnel permanent on macOS (surviving restarts and running automatically in the background), install the provided LaunchAgent configuration:
```bash
# Copy the agent configuration to your LaunchAgents directory
cp argocd/uno.erp.argocd-portforward.plist ~/Library/LaunchAgents/

# Load the background service agent
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

*Note: If you run these commands without first logging in (or if the config file context is not found), you will receive a fatal `"Argo CD server address unspecified"` error. You can bypass this by explicitly providing the server address and security flags on every execution:*
```bash
# Get application status directly
argocd --server localhost:8080 --insecure app get erp-uno

# Trigger manual synchronization directly
argocd --server localhost:8080 --insecure app sync erp-uno
```

# Credits

* [5HT](https://5ht.co)

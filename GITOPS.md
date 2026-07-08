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

# Credits

* [5HT](https://5ht.co)

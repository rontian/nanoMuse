# nanoMuse family NAS deployment (draft)

This deployment-only directory targets the `rontian/nanoMuse` Fork. It does **not** change nanoMuse application code and does **not** deploy or start anything automatically.

## Why the Fork contains this directory

- **Cloud Relay**: upstream currently publishes source and `cloud/Dockerfile`, but no verified official standalone Relay image. `compose.yaml` builds `../../cloud` directly from this Fork.
- **Agent Runtime (optional)**: the official image `ghcr.io/nano-muse/nanomuse:1.0.5` is used in `compose.runtime.yaml` without building Runtime from source. Both amd64 and arm64 are supported by the default image.
- **Existing infrastructure**: reuse VPS Nginx, NPS and Magpie **or** CLIProxyAPI. No second Caddy or authentication gateway.

## NAS state and isolation

Example only; choose your real persistent storage path in `.env`:

```text
/volume1/docker/nanomuse/
  relay/data/                   # Relay SQLite; container UID 10001
  runtimes/primary/data/       # One person's Agent state; UID 1000
  runtimes/primary/workspace/  # One person's files; UID 1000
  backups/                     # Encrypted offsite copy strongly recommended
```

The Relay is shared across family accounts, each with isolated account-level data. A standard Runtime is **not** a safe multi-user execution container. Deploy an independent Runtime, account login, access token, volumes and workspace for each family member who needs NAS execution. Do not mount the NAS root, shared private family folders or the Docker socket into any agent.

## P0: prepare and validate locally

1. Copy `.env.example` to `.env` and `relay.env.example` to `relay.env`, and replace **all** example paths, keys, addresses, whitelisted emails and model IDs. These real files are gitignored.
2. Generate independent `CLOUD_SECRET` and `CLOUD_ADMIN_TOKEN` values with `openssl rand -hex 32`. Set `SIGNUP_OPEN=0`, a real `ALLOWED_IDENTIFIERS` list, `IMPROVE_DEFAULT=0`, and `CLOUD_ANY_MODEL_MEMBERS=0`.
3. Use your working OpenAI-compatible Magpie **or** CLIProxyAPI URL as `UPSTREAM_BASE`, not both stacked without reason. `CLOUD_MODELS` must name models the gateway actually serves; the example model ID is deliberately invalid.
4. `CODE_SENDER=log` is for an initial LAN test only; change to `smtp` and configure SMTP for normal family access. Do not expose sign-in codes through shared logs.
5. Configure the real NAS data directories with UID 10001 for Relay. `RELAY_BIND_IP=127.0.0.1` is appropriate only if the NPS client can reach NAS host loopback; otherwise choose a firewall-protected reachable NAS IP, **not** unguarded `0.0.0.0`.

Review on the NAS before starting any services:

```bash
cd deploy/nas
cp .env.example .env
cp relay.env.example relay.env
# Edit both files and replace example values before use.
# Adapt the path below to the actual NANOMUSE_DATA_ROOT.
mkdir -p /volume1/docker/nanomuse/relay/data
sudo chown 10001:10001 /volume1/docker/nanomuse/relay/data
docker compose config
docker compose build relay
# Only after configuration review: docker compose up -d relay
# On the NAS host: curl -fsS http://127.0.0.1:8787/healthz
```

## Optional individual NAS Runtime

```bash
cd deploy/nas
cp runtime.env.example runtime.env
# Edit with an independent strong NANOMUSE_SERVER_TOKEN and private Relay URL.
mkdir -p /volume1/docker/nanomuse/runtimes/primary/{data,workspace}
sudo chown 1000:1000 /volume1/docker/nanomuse/runtimes/primary/{data,workspace}
docker compose -f compose.yaml -f compose.runtime.yaml config
# When ready: docker compose -f compose.yaml -f compose.runtime.yaml up -d runtime
```

The Runtime binds `127.0.0.1:8788` by default. Reach it only through an authenticated private network/VPN or equally restricted gateway. Its Web access token is different from the Relay account key. `NANOMUSE_CLOUD_BASE_URL` does **not** log in automatically; sign in via Runtime Web with the corresponding person's Relay credentials, then verify the Hub device appears.

Do not use this one example Compose stack as a shared multi-user Runtime. Additional family users need their own Compose project/container, separate environment, data/workspace, device name and access control.

## VPS Nginx + NPS integration

The only Relay backend port is TCP 8787. Forward it using your existing NPS tunnel to VPS Nginx, terminate TLS at Nginx, and proxy `/v1/hub` WebSocket upgrades. The Relay request limit defaults to 16 MiB, so configure `client_max_body_size 20m` on Nginx (and matching NPS limits where relevant). Restrict the admin routes `/app/admin/` and `/v1/admin/*` to operator access. Only trust `X-Forwarded-*` from the verified ingress IPs (`TRUSTED_PROXIES`), not arbitrary clients.

## Backup, test, upgrade and rollback

`bash scripts/backup-relay.sh` runs SQLite's consistent online backup API in the live Relay container; a direct copy of `cloud.db` can omit data in WAL. The script archives the database **with** `relay.env`, which contains `CLOUD_SECRET` and other secrets. Backups are mode 0600 but **not encrypted**; encrypt before offsite transfer. Set `NANOMUSE_BACKUP_DIR` to a secure NAS backup directory. A reliable deployment also needs an actual restore drill on an isolated test stack.

Before upgrading: save both database and secrets; record the exact Fork commit and Runtime image version/digest; review release migrations; update one component at a time; verify sign-in, sync and Hub. A Relay database schema may be forward-migrated at startup, so rollback should restore the matching **pre-upgrade database snapshot** as well as the image. Never rotate `CLOUD_SECRET` independently of the database.

Acceptance checks: allowed family login succeeds; unlisted signup fails; SMTP delivery works; the shared model gateway responds and streams correctly; accounts cannot read each other's chats/devices; both Desktop and phones connect over Hub; Runtime works under its own account and volumes; full backup/restore tested.

## Sources and licensing

- [Cloud Relay self-hosting](https://github.com/nano-muse/nanoMuse/blob/main/docs/self-hosting.md)
- [Agent Runtime container](https://github.com/nano-muse/nanoMuse/blob/main/docs/deployment.md)
- [GPL-3.0-or-later](https://github.com/nano-muse/nanoMuse/blob/main/LICENSE)

This scaffold does not copy/modify upstream application code. Preserve upstream licenses and notices when distributing any custom image.

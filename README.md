# Organizační deploy šablona (davidfronek)

Toto je speciální repo **`davidfronek/.github`**. GitHub z něj automaticky bere:

- `workflow-templates/` – šablony workflow nabízené v každém repu organizace
  (Actions → New workflow → sekce „By davidfronek“).
- `.github/workflows/*.yml` – sdílené (reusable) workflow, které volají jednotlivá
  repa přes `uses:`. Deploy logika je na jednom místě.

## Jak deploy funguje

Všechny aplikace běží na VPS (46.28.108.112) pod správou helperu
**`/usr/local/sbin/vps-dashboard-domains`** (zdroj: repo `vps-dashboard`,
`scripts/domain-admin.sh`):

- aplikace žijí v `/srv/apps/<doména>`
- systemd služby se jmenují `vps-app-<doména-s-pomlčkami>`
- `domain-deploy <doména> <git-url> <větev> <port> <force_https> <www_redirect> <automatic_ssl>`
  naklonuje repo, buildne, nastaví nginx/SSL a restartuje službu

Reusable workflow [deploy-vps-reusable.yml](.github/workflows/deploy-vps-reusable.yml)
se přes SSH (jako root) připojí na VPS, zavolá `domain-deploy` a ověří health check.

## Organizační secrets

Nastavené pro celou organizaci (Settings → Secrets and variables → Actions):

| Secret | Hodnota |
|---|---|
| `SSH_HOST` | IP/doména VPS |
| `SSH_USER` | `root` (helper vyžaduje root) |
| `SSH_PORT` | `22` |
| `SSH_PRIVATE_KEY` | privátní část deploy klíče `github-actions-deploy` |

Veřejná část klíče musí být v `/root/.ssh/authorized_keys` na VPS.

> **Pozor (GitHub Free):** org secrets fungují jen pro **veřejná** repa.
> Privátním repům (např. `vps-dashboard`) je třeba stejné secrets nastavit
> na úrovni repa – viz [scripts/setup-org-secrets.ps1](scripts/setup-org-secrets.ps1):
>
> ```powershell
> .\scripts\setup-org-secrets.ps1 -Scope repos -Repos vps-dashboard -SshHost <IP> -SshUser root -KeyPath $HOME\.ssh\github_deploy
> ```

## Zapojení repozitáře

Vytvořte v repu `.github/workflows/deploy.yml`:

```yaml
name: Deploy

on:
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read

jobs:
  deploy:
    uses: davidfronek/.github/.github/workflows/deploy-vps-reusable.yml@main
    with:
      domain: moje-app.onremote.cz   # /srv/apps/<doména>, služba vps-app-*
      port: "3000"
      health_path: /                 # např. /health
    secrets: inherit
```

Volitelné vstupy: `branch` (default `main`), `force_https` (`"1"`),
`www_redirect` (`"0"`), `automatic_ssl` (`"1"`).

### Aktuálně zapojená repa

| Repo | Doména | Port | Health |
|---|---|---|---|
| `nastenka-live` | nastenka-live.onremote.cz | 3099 | `/health` |
| `mojekytara` | mojekytara.onremote.cz | 3001 | `/` |

`vps-dashboard` má vlastní workflow (instaluje helper, speciální kroky) a
`tankovani` zatím používá starší deploy přes `deploy/deploy.sh`.

## Alternativa: rsync deploy

Pro statické weby mimo helper je k dispozici
[deploy-rsync-reusable.yml](.github/workflows/deploy-rsync-reusable.yml):
build v CI → rsync výstupu na VPS → volitelný příkaz po nasazení.
Vyžaduje vstup `deploy_path` (cílový adresář na VPS).

## Rotace deploy klíče

```powershell
# nový klíč
ssh-keygen -t ed25519 -f $HOME\.ssh\github_deploy -C github-actions-deploy -N '' -q
# veřejnou část na VPS
type $HOME\.ssh\github_deploy.pub | ssh root@<IP> "cat >> /root/.ssh/authorized_keys"
# privátní část do org secrets
.\scripts\setup-org-secrets.ps1 -SshHost <IP> -SshUser root -KeyPath $HOME\.ssh\github_deploy
```

(Pozn.: v PowerShellu generujte klíč raději přes `cmd /c ssh-keygen ... -N ""`,
jinak může dostat passphrase `""`.)

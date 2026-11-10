# Organizační deploy šablona (davidfronek)

Obsah tohoto repozitáře patří do speciálního repa **`davidfronek/.github`** v organizaci.
GitHub z něj automaticky bere:

- `workflow-templates/` – šablony workflow, které se nabídnou v každém repu organizace
  (Actions → New workflow → sekce „By davidfronek“).
- `.github/workflows/deploy-vps-reusable.yml` – sdílený (reusable) workflow,
  který volají jednotlivá repa. Logika deploye je na jednom místě.

## Struktura

```
.github/workflows/deploy-vps-reusable.yml   # sdílená deploy logika (build + rsync + post-deploy)
workflow-templates/deploy-vps.yml           # šablona pro jednotlivá repa
workflow-templates/deploy-vps.properties.json
scripts/setup-org-secrets.ps1               # nastavení secrets přes gh CLI
```

## 1. Vytvoření repa `.github` v organizaci

```powershell
cd H:\projects\org-github
git init
git add .
git commit -m "Add VPS deploy template and reusable workflow"
git branch -M main
git remote add origin https://github.com/davidfronek/.github.git
git push -u origin main
```

(Repo `davidfronek/.github` nejdřív založte na GitHubu – doporučeně **public**,
jinak je nutné povolit přístup k reusable workflow: Settings → Actions → General
→ Access → „Accessible from repositories in the organization“.)

## 2. Deploy SSH klíč

Vygenerujte **samostatný** klíč jen pro deploy (ne váš osobní):

```powershell
ssh-keygen -t ed25519 -f $HOME\.ssh\github_deploy -C "github-actions-deploy" -N '""'
```

Veřejný klíč přidejte na VPS uživateli, pod kterým se deployuje:

```bash
# na VPS
cat >> ~/.ssh/authorized_keys   # vložit obsah github_deploy.pub
```

## 3. Nastavení secrets

Nainstalujte GitHub CLI a přihlaste se:

```powershell
winget install GitHub.cli
gh auth login
```

Organizační secrets (sdílené všemi repy):

```powershell
.\scripts\setup-org-secrets.ps1 -SshHost 1.2.3.4 -SshUser deploy -KeyPath $HOME\.ssh\github_deploy
```

Nastaví: `SSH_HOST`, `SSH_USER`, `SSH_PORT`, `SSH_PRIVATE_KEY`.

> **Pozor:** Na GitHub **Free** plánu organizace fungují org secrets jen pro
> **veřejná** repa. Pro privátní repa použijte per-repo režim:
>
> ```powershell
> .\scripts\setup-org-secrets.ps1 -Scope repos -Repos tankovani,life360 -SshHost 1.2.3.4 -SshUser deploy -KeyPath $HOME\.ssh\github_deploy
> ```

## 4. Zapojení repozitáře

V každém repu, které se má deployovat:

1. Nastavte repository variable s cílovou cestou:

   ```powershell
   gh variable set DEPLOY_PATH --repo davidfronek/tankovani --body "/opt/tankovani"
   ```

2. Přidejte workflow – buď přes Actions → New workflow → šablona
   „Deploy na VPS (SSH + rsync)“, nebo ručně vytvořte
   `.github/workflows/deploy.yml`:

   ```yaml
   name: Deploy

   on:
     push:
       branches: [ main ]
     workflow_dispatch:

   jobs:
     deploy:
       uses: davidfronek/.github/.github/workflows/deploy-vps-reusable.yml@main
       with:
         deploy_path: ${{ vars.DEPLOY_PATH }}
         build_command: "npm ci && npm run build"
         dist_dir: "dist"
         post_deploy_command: ""
       secrets: inherit
   ```

### Parametry reusable workflow

| Parametr | Výchozí | Popis |
|---|---|---|
| `deploy_path` | *(povinné)* | Cílový adresář na VPS |
| `build_command` | `npm ci && npm run build` | Build příkaz; prázdný = bez buildu, nasadí se celé repo |
| `dist_dir` | `dist` | Adresář s výstupem buildu, který se rsyncem nahraje |
| `node_version` | `22` | Verze Node.js |
| `post_deploy_command` | *(prázdné)* | Příkaz na VPS po nasazení, např. `sudo systemctl restart app` |

### Příklady pro vaše projekty

```yaml
# tankovani – build klienta, restart služby
with:
  deploy_path: ${{ vars.DEPLOY_PATH }}       # /var/www/tankovani
  build_command: "npm ci && npm --prefix client ci && npm --prefix client run build"
  dist_dir: "client/dist"
  post_deploy_command: "sudo systemctl restart tankovani"

# nastenka-live – bez buildu, nasazení celého repa + restart
with:
  deploy_path: ${{ vars.DEPLOY_PATH }}       # /opt/nastenka-live
  build_command: ""
  post_deploy_command: "cd /opt/nastenka-live && npm ci --omit=dev && sudo systemctl restart nastenka"
```

## Bezpečnostní poznámky

- Deploy klíč omezte na VPS jen na to, co deploy potřebuje
  (ideálně vlastní uživatel `deploy` s právy jen do web rootu + `sudo` jen na restart konkrétní služby).
- Pokud `post_deploy_command` používá `sudo`, povolte ho bez hesla jen pro daný příkaz v `/etc/sudoers.d/deploy`:

  ```
  deploy ALL=(root) NOPASSWD: /usr/bin/systemctl restart tankovani
  ```

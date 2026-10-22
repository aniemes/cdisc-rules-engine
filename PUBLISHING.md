# Publishing the SQL Engine Docker Image

The SQL-mode engine image is built from `Dockerfile.source` (it bundles an embedded Postgres via `pgserver`) and published to Azure Container Registry (ACR).

- Repository: `ctd/clintrakdefine/core-rules-engine`
- Registry login server: `<registry>.azurecr.io`

## Tagging scheme

| Tag | Purpose |
|-----|---------|
| `fork-<YYYYMMDD>-<HHMMSS>-<git sha>` | Immutable. One per build; never overwritten. |
| `latest-copy-from-fork` | Moving pointer to the build consumers should use. |

Reverting means re-pointing `latest-copy-from-fork` at an older immutable tag. Nothing is rebuilt or deleted.

## Prerequisites

- Docker, Azure CLI (`az`), and permission to push to the registry.
- Run `az login` first. Do not use `docker login -p <password>`: the password would be stored in shell history. `az acr login` uses your Azure identity, so no password is typed.
- Commit your changes first so the sha in the tag matches the image contents.

## Publish

From the repository root:

```powershell
az login
.\publish.ps1 -Registry <registry>
```

The script will:

1. Log in to ACR (`az acr login`).
2. Print the digest the pointer tag currently targets (note it as your revert target).
3. Build the image and push the immutable `fork-...` tag.
4. Only after that push succeeds, move `latest-copy-from-fork` to the new build.

Use `-NoPointer` to push the immutable tag without moving the pointer, e.g. to test first.

## Revert

Find the previous immutable tag in the portal (Repositories > core-rules-engine; the tag whose digest matched the pointer before the publish), then:

```powershell
.\publish.ps1 -Registry <registry> -Revert fork-20261008-134009-0825478c82f9
```

This uses `az acr import --force` to re-tag inside the registry. Confirm in the portal that `latest-copy-from-fork` shows the expected digest again.

## Manual equivalent

```powershell
az acr login --name <registry>
$sha = (git rev-parse --short=12 HEAD)
$tag = "fork-$(Get-Date -Format 'yyyyMMdd-HHmmss')-$sha"
$img = "<registry>.azurecr.io/ctd/clintrakdefine/core-rules-engine"
docker build -f Dockerfile.source -t "${img}:$tag" .
docker push "${img}:$tag"
docker tag "${img}:$tag" "${img}:latest-copy-from-fork"
docker push "${img}:latest-copy-from-fork"
```

## Notes

- `.dockerignore` keeps the local venv, test output and sample data out of the image.
- If a credential is ever typed into a terminal by mistake, rotate it and clear history: `Remove-Item (Get-PSReadLineOption).HistorySavePath`.

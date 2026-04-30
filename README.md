# mit-agent-releases

Public release repository for the **M-IT Management Agent** MSI artefacts.

> Source code lives in [`mit-windows-agent`](https://github.com/M-IT-Services/mit-windows-agent).
> This repository only hosts signed/verified release binaries for download by deployed agents.

## How agents download updates

Each release publishes:

| Asset | Description |
| --- | --- |
| `MitAgent-<version>.msi` | The installer payload |
| `MitAgent-<version>.msi.sha256` | Hex SHA-256 checksum (text file, one line) |
| `MitAgent-<version>.msi.sha256.asc` | *(optional)* Detached GPG signature of the checksum file |

Direct download URL pattern (stable):

```
https://github.com/M-IT-Services/mit-agent-releases/releases/download/v<version>/MitAgent-<version>.msi
```

## Security model

Defense in depth — each layer is independent:

1. **HTTPS only** — GitHub's TLS certificate is validated by Windows by default.
2. **SHA-256 verification** — agent must compute hash of downloaded file and compare with value provided by Odoo (`update_sha256` field) **before** running the MSI.
3. **Authenticode signature** *(optional, recommended)* — sign the MSI with an EV/OV code-signing certificate so Windows SmartScreen approves the install without warning.
4. **Branch protection** — `main` requires PR review + passing CI before merge.
5. **Tag protection** — only maintainers may push `v*` tags that trigger releases.
6. **Token-less downloads** — public release assets, no PAT needed on the agent side.
7. **Reproducible build** — build runs in GitHub Actions on `windows-latest`, sources pinned to a release tag.
8. **Audit trail** — every release published via Actions is logged with commit SHA and workflow run id.

## How to publish a new release

1. Tag the matching commit in [`mit-windows-agent`](https://github.com/M-IT-Services/mit-windows-agent), e.g. `v1.0.8`.
2. Build the MSI (CI in source repo or local).
3. In **this** repository run:

   ```pwsh
   .\scripts\publish-release.ps1 -Version 1.0.8 -MsiPath C:\path\to\MitAgent-1.0.8.msi
   ```

   The script:
   - Verifies the MSI exists.
   - Computes SHA-256 and writes `MitAgent-1.0.8.msi.sha256`.
   - Creates a git tag `v1.0.8` if missing.
   - Calls `gh release create` with both files attached and notes auto-generated.

4. Update Odoo (System Parameters or per-tenant on `res.partner`):

   ```
   mit_agent.target_agent_version = 1.0.8
   mit_agent.update_msi_url       = https://github.com/M-IT-Services/mit-agent-releases/releases/download/v1.0.8/MitAgent-1.0.8.msi
   mit_agent.update_sha256        = <hex from .sha256 file>
   ```

## Repository hardening checklist

- [ ] Enable **branch protection** on `main` (require PR + status checks).
- [ ] Enable **tag protection** on `v*` (admins only).
- [ ] Enforce **2FA** for all org members (already org-wide).
- [ ] Enable **Dependabot alerts**.
- [ ] Enable **Secret scanning** + **push protection**.
- [ ] Restrict **GitHub Actions** to selected actions (no third-party).
- [ ] Disable **wiki** and **projects** (not used here).

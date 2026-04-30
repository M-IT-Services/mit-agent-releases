# Reporting a vulnerability

If you discover a security issue in the M-IT Management Agent or any release
artefact published in this repository, please **do not** open a public issue.

Instead, contact us privately:

- Email: **security@mitservices.nl**
- Subject: `[SECURITY] mit-agent-releases`

Please include:

1. A description of the vulnerability and potential impact.
2. Steps to reproduce, ideally with a proof-of-concept.
3. Any suggested mitigation.

We aim to acknowledge reports within **2 business days** and to publish a fix
or mitigation within **30 days** for confirmed high-severity issues.

## Verifying releases

Every release ships with:

- `MitAgent-<version>.msi` — the installer.
- `MitAgent-<version>.msi.sha256` — SHA-256 hex digest.

Recommended verification on Windows:

```powershell
$expected = (Get-Content .\MitAgent-1.0.8.msi.sha256).Trim().ToLower()
$actual   = (Get-FileHash .\MitAgent-1.0.8.msi -Algorithm SHA256).Hash.ToLower()
if ($expected -ne $actual) { throw "Checksum mismatch — DO NOT install." }
```

If a code-signing certificate is configured (see `.github/workflows/`), also
verify the Authenticode signature:

```powershell
$sig = Get-AuthenticodeSignature .\MitAgent-1.0.8.msi
if ($sig.Status -ne 'Valid') { throw "Invalid signature — DO NOT install." }
$sig.SignerCertificate | Format-List Subject, Issuer, Thumbprint, NotAfter
```

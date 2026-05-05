# Install-DotNet8Runtime-WinGet.ps1
# Doel: .NET 8 Runtime (Microsoft.DotNet.Runtime.8) silent installeren via WinGet in SYSTEM/ESET context
# Detectie: skip als .NET 8 runtime al aanwezig is
# Exit codes: geschikt voor reporting

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# === Config ===
$PackageId = 'Microsoft.DotNet.Runtime.8'
$Source    = 'winget'  # expliciet voor voorspelbaarheid
$Return3010OnReboot = $true   # Zet op $false als je altijd 0 wilt teruggeven (en reboot alleen loggen)

# Exit code afspraken (pas gerust aan)
$EC_SUCCESS                  = 0
$EC_REBOOT_REQUIRED          = 3010
$EC_WINGET_NOT_FOUND         = 20
$EC_WINGET_CANNOT_RUN        = 21
$EC_INSTALL_FAILED           = 30
$EC_POSTCHECK_FAILED         = 31
$EC_UNEXPECTED_ERROR         = 99

function Write-Log([string]$msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Output "[$ts] $msg"
}

function Test-DotNet8RuntimeInstalled {
    # Check registry locaties voor installed sharedfx (x64 en x86)
    # .NET-installers slaan versies soms op als subkeys, soms als values (REG_DWORD)
    $paths = @(
        'HKLM:\SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.NETCore.App',
        'HKLM:\SOFTWARE\dotnet\Setup\InstalledVersions\x86\sharedfx\Microsoft.NETCore.App'
    )

    foreach ($p in $paths) {
        if (Test-Path $p) {
            try {
                # Methode 1: versies als subkeys (oudere .NET-installer gedrag)
                $subkeys = Get-ChildItem -Path $p -ErrorAction SilentlyContinue | Select-Object -ExpandProperty PSChildName
                if ($subkeys | Where-Object { $_ -like '8.*' }) { return $true }

                # Methode 2: versies als value-namen (nieuwere .NET-installer gedrag)
                $values = Get-Item -Path $p -ErrorAction SilentlyContinue
                if ($values) {
                    $valueNames = $values.GetValueNames()
                    if ($valueNames | Where-Object { $_ -like '8.*' }) { return $true }
                }
            } catch {
                # als pad niet leesbaar is, ga door naar volgende
            }
        }
    }

    # Fallback: dotnet CLI (werkt als PATH al bijgewerkt is in deze sessie)
    try {
        $dotnetExe = 'C:\Program Files\dotnet\dotnet.exe'
        if (Test-Path $dotnetExe) {
            $runtimes = & $dotnetExe --list-runtimes 2>$null
            if ($runtimes | Where-Object { $_ -match 'Microsoft\.NETCore\.App 8\.' }) { return $true }
        }
    } catch { }

    return $false
}

function Resolve-WingetPath {
    # 1) Soms is winget wel resolvebaar (interactief), probeer eerst:
    try {
        $cmd = Get-Command winget.exe -ErrorAction Stop
        if ($cmd -and $cmd.Source -and (Test-Path $cmd.Source)) {
            return $cmd.Source
        }
    } catch { }

    # 2) SYSTEM-proof: zoek in WindowsApps naar DesktopAppInstaller
    $base = 'C:\Program Files\WindowsApps'
    if (-not (Test-Path $base)) { return $null }

    # Specifiek patroon voorkomt dure -Recurse
    $candidates = @()
    $patterns = @(
        "$base\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe",
        "$base\Microsoft.DesktopAppInstaller_*__8wekyb3d8bbwe\winget.exe"
    )

    foreach ($pat in $patterns) {
        try {
            $candidates += Get-ChildItem -Path $pat -Force -ErrorAction SilentlyContinue
        } catch { }
    }

    $best = $candidates | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($best -and (Test-Path $best.FullName)) { return $best.FullName }

    return $null
}

try {
    Write-Log "Start: detectie .NET 8 Runtime..."

    if (Test-DotNet8RuntimeInstalled) {
        Write-Log ".NET 8 Runtime is al aanwezig. Skip install."
        exit $EC_SUCCESS
    }

    Write-Log ".NET 8 Runtime niet gevonden. Winget pad resolven (SYSTEM context)..."
    $winget = Resolve-WingetPath
    if (-not $winget) {
        Write-Log "FOUT: winget.exe niet gevonden (App Installer ontbreekt of niet bereikbaar in SYSTEM)."
        exit $EC_WINGET_NOT_FOUND
    }

    Write-Log "Winget gevonden: $winget"
    # sanity check: kan winget draaien?
    try {
        $ver = & $winget --version 2>$null
        if (-not $ver) {
            Write-Log "FOUT: winget.exe gestart maar gaf geen versie terug."
            exit $EC_WINGET_CANNOT_RUN
        }
        Write-Log "Winget versie: $ver"
    } catch {
        Write-Log "FOUT: winget.exe kan niet draaien in deze context: $($_.Exception.Message)"
        exit $EC_WINGET_CANNOT_RUN
    }

    $args = @(
        'install',
        '-e', '--id', $PackageId,
        '--source', $Source,
        '--silent',
        '--accept-source-agreements',
        '--accept-package-agreements',
        '--disable-interactivity'
    )

    Write-Log "Install uitvoeren: $PackageId (silent, agreements accepted, disable-interactivity)..."
    $p = Start-Process -FilePath $winget -ArgumentList $args -Wait -PassThru -WindowStyle Hidden

    $exit = [int]$p.ExitCode
    Write-Log "Winget exit code: $exit"

    # Post-check: is runtime nu aanwezig?
    if (Test-DotNet8RuntimeInstalled) {
        Write-Log "Post-check OK: .NET 8 Runtime is nu aanwezig."

        # Reboot codes (sommige installers geven 3010/1641 terug; we mappen alleen 3010 naar ESET als gewenst)
        if ($Return3010OnReboot -and ($exit -eq 3010 -or $exit -eq 1641)) {
            Write-Log "Install OK maar reboot required (installer exit $exit). Return 3010 voor reporting."
            exit $EC_REBOOT_REQUIRED
        }

        exit $EC_SUCCESS
    }

    Write-Log "FOUT: Winget draaide, maar .NET 8 Runtime is na afloop nog steeds niet gedetecteerd."
    exit $EC_POSTCHECK_FAILED
}
catch {
    Write-Log "ONVERWACHTE FOUT: $($_.Exception.Message)"
    exit $EC_UNEXPECTED_ERROR
}
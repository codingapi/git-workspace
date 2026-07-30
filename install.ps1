# git-workspace installer for native Windows (PowerShell)
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File install.ps1 [-Prefix DIR] [-Uninstall]
#   iex "& { $(irm https://raw.githubusercontent.com/codingapi/git-workspace/main/install.ps1) }"
#   iex "& { $(irm .../install.ps1) } -Uninstall"
#
# Standalone mode (irm|iex) installs the LATEST RELEASE TAG, not the
# development branch. Default prefix: %LOCALAPPDATA%\Programs\git-workspace
# Installs git-workspace.cmd and adds the directory to your user PATH.
# For Git Bash / MSYS / Cygwin use install.sh instead.

param(
    [string]$Prefix = (Join-Path $env:LOCALAPPDATA "Programs\git-workspace"),
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"
$RepoUrl = "https://github.com/codingapi/git-workspace.git"

function Set-UserPathDir([string]$Dir, [bool]$Add) {
    $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    $parts = @($userPath -split ';' | Where-Object { $_ -and ($_ -ne $Dir) })
    if ($Add) { $parts += $Dir }
    [Environment]::SetEnvironmentVariable("PATH", ($parts -join ';'), "User")
}

if ($Uninstall) {
    Set-UserPathDir $Prefix $false
    if (Test-Path $Prefix) { Remove-Item -Recurse -Force $Prefix }
    Write-Host "==> removed $Prefix (open a new terminal for PATH changes to apply)"
    exit 0
}

# ---- preflight: required dependencies (git, python) ----------------------
# Checked up front so every missing dependency is reported clearly, together,
# before any work (cloning, copying) is done. git is needed both to clone in
# standalone mode and by git-workspace itself at runtime; python runs the CLI.
$PyExe = $null
$PyArgs = @()
$missing = @()
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    $missing += "git     - install Git for Windows: https://git-scm.com"
}
if (Get-Command python -ErrorAction SilentlyContinue) {
    $PyExe = "python"
} elseif (Get-Command py -ErrorAction SilentlyContinue) {
    $PyExe = "py"
    $PyArgs = @("-3")
} else {
    $missing += "python  - install Python 3.8+: https://python.org"
}
if ($missing.Count -gt 0) {
    Write-Host "error: missing required dependencies:" -ForegroundColor Red
    foreach ($m in $missing) { Write-Host "  $m" -ForegroundColor Red }
    exit 1
}

# ---- locate sources: beside this script, or clone the repo ----------------
$SrcDir = $PSScriptRoot
$TempDir = $null
# When run via irm|iex there is no script file, so $PSScriptRoot is an empty
# string and Join-Path would fail on it - treat that as "not beside a checkout".
if (-not $SrcDir -or -not (Test-Path (Join-Path $SrcDir "git-workspace"))) {
    $TempDir = Join-Path $env:TEMP "git-workspace-install"
    if (Test-Path $TempDir) { Remove-Item -Recurse -Force $TempDir }
    # install from the latest release tag, not the development branch
    $refs = git ls-remote --tags --refs --sort=-v:refname $RepoUrl 2>$null
    $tag = $null
    if ($refs) {
        $tag = (($refs | Select-Object -First 1) -split 'refs/tags/')[-1]
    }
    if ($tag) {
        Write-Host "==> cloning $RepoUrl @ $tag (latest release)"
        git clone --depth 1 --quiet --branch $tag $RepoUrl $TempDir
    } else {
        Write-Warning "no release tags found - installing from the default branch"
        Write-Host "==> cloning $RepoUrl"
        git clone --depth 1 --quiet $RepoUrl $TempDir
    }
    if ($LASTEXITCODE -ne 0) { Write-Error "git clone failed" }
    $SrcDir = $TempDir
}

try {
    # ---- dependency check: PyYAML (git + python verified in preflight) ----
    # Native commands emit diagnostics on stderr. With $ErrorActionPreference
    # = "Stop", Windows PowerShell 5.1 turns that stderr into a *terminating*
    # NativeCommandError, which would abort the installer the moment the probe
    # below reports "PyYAML missing" (an ImportError traceback on stderr) -
    # before the pip-install fallback could run. Relax the preference around
    # the external calls and judge success by $LASTEXITCODE instead.
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    & $PyExe @PyArgs -c "import yaml" *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "==> PyYAML missing - attempting: $PyExe $($PyArgs -join ' ') -m pip install --user pyyaml"
        & $PyExe @PyArgs -m pip install --user pyyaml
        if ($LASTEXITCODE -ne 0) {
            $ErrorActionPreference = $prevEAP
            Write-Error "could not install PyYAML - install it manually (pip install pyyaml)"
        }
    }

    $ErrorActionPreference = $prevEAP

    # ---- install: script + cmd shim + user PATH ----------------------------
    New-Item -ItemType Directory -Force -Path $Prefix | Out-Null
    Copy-Item (Join-Path $SrcDir "git-workspace") (Join-Path $Prefix "git-workspace") -Force

    $launcher = $PyExe
    if ($PyArgs.Count -gt 0) { $launcher = "$PyExe $($PyArgs -join ' ')" }
    $shim = "@echo off`r`n$launcher `"%~dp0git-workspace`" %*"
    Set-Content -Path (Join-Path $Prefix "git-workspace.cmd") -Value $shim -Encoding ASCII

    $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if (@($userPath -split ';') -notcontains $Prefix) {
        Set-UserPathDir $Prefix $true
        Write-Host "==> added $Prefix to your user PATH (open a new terminal to apply)"
    }

    Write-Host "==> installed: $(Join-Path $Prefix 'git-workspace.cmd')"
    Write-Host "==> done. Try: git-workspace version"
} finally {
    if ($TempDir -and (Test-Path $TempDir)) { Remove-Item -Recurse -Force $TempDir }
}

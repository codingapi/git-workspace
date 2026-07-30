# git-workspace installer for native Windows (PowerShell)
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File install.ps1 [-Prefix DIR] [-Uninstall]
#
# Default prefix: %LOCALAPPDATA%\Programs\git-workspace
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

# ---- locate sources: beside this script, or clone the repo ----------------
$SrcDir = $PSScriptRoot
$TempDir = $null
if (-not (Test-Path (Join-Path $SrcDir "git-workspace"))) {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Error "git is required to clone the repository"
    }
    $TempDir = Join-Path $env:TEMP "git-workspace-install"
    if (Test-Path $TempDir) { Remove-Item -Recurse -Force $TempDir }
    Write-Host "==> cloning $RepoUrl"
    git clone --depth 1 --quiet $RepoUrl $TempDir
    if ($LASTEXITCODE -ne 0) { Write-Error "git clone failed" }
    $SrcDir = $TempDir
}

try {
    # ---- dependency checks: python (or py launcher), git, PyYAML ----------
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Error "git not found - install Git for Windows (https://git-scm.com)"
    }

    $PyExe = $null
    $PyArgs = @()
    if (Get-Command python -ErrorAction SilentlyContinue) {
        $PyExe = "python"
    } elseif (Get-Command py -ErrorAction SilentlyContinue) {
        $PyExe = "py"
        $PyArgs = @("-3")
    } else {
        Write-Error "python not found - install Python 3.8+ (https://python.org)"
    }

    & $PyExe @PyArgs -c "import yaml" *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "==> PyYAML missing - attempting: $PyExe $($PyArgs -join ' ') -m pip install --user pyyaml"
        & $PyExe @PyArgs -m pip install --user pyyaml
        if ($LASTEXITCODE -ne 0) {
            Write-Error "could not install PyYAML - install it manually (pip install pyyaml)"
        }
    }

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

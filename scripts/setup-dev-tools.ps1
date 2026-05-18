param(
  [switch]$InstallFlutter,
  [switch]$InstallSupabase,
  [switch]$UserScope,
  [switch]$All
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Download-FileRobust {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Uri,
    [Parameter(Mandatory = $true)]
    [string]$OutFile,
    [int]$MaxAttempts = 4
  )

  $curlPath = (Get-Command curl.exe -ErrorAction SilentlyContinue)?.Source

  for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
    try {
      if ($curlPath) {
        $curlArgs = @(
          '-L',
          '--fail',
          '--retry', '5',
          '--retry-all-errors',
          '--connect-timeout', '30',
          '--output', $OutFile
        )

        if (Test-Path $OutFile) {
          $curlArgs = @('--continue-at', '-') + $curlArgs
        }

        & $curlPath @curlArgs $Uri
        if ($LASTEXITCODE -ne 0) {
          throw "curl.exe failed with exit code $LASTEXITCODE"
        }
      }
      else {
        Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing -MaximumRetryCount 5 -RetryIntervalSec 5
      }

      if (-not (Test-Path $OutFile)) {
        throw 'Download did not create the output file.'
      }

      if ((Get-Item $OutFile).Length -le 0) {
        throw 'Downloaded output file is empty.'
      }

      return
    }
    catch {
      if ($attempt -ge $MaxAttempts) {
        throw
      }

      Write-Host "[MedRash] Download attempt $attempt failed: $($_.Exception.Message)" -ForegroundColor Yellow
      Write-Host '[MedRash] Retrying download...' -ForegroundColor Yellow
    }
  }
}

function Assert-Admin {
  $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
  if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script in an elevated PowerShell session (Administrator).'
  }
}

function Install-Flutter {
  param(
    [bool]$UseUserScope
  )

  if (-not $UseUserScope) {
    Write-Host '[MedRash] Installing Flutter via Chocolatey...' -ForegroundColor Cyan
    choco install flutter -y --no-progress
    Write-Host '[MedRash] Flutter install complete.' -ForegroundColor Green
    return
  }

  Write-Host '[MedRash] Installing Flutter SDK in user scope from official release...' -ForegroundColor Cyan

  $releaseApi = 'https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json'
  $releases = Invoke-RestMethod -Uri $releaseApi -UseBasicParsing
  $stableHash = $releases.current_release.stable
  $stableRelease = $releases.releases | Where-Object { $_.hash -eq $stableHash } | Select-Object -First 1

  if (-not $stableRelease) {
    throw 'Could not resolve stable Flutter release metadata.'
  }

  $archiveRelativePath = $stableRelease.archive
  $archiveUrl = "https://storage.googleapis.com/flutter_infra_release/releases/$archiveRelativePath"

  $tempRoot = Join-Path $env:TEMP 'medrash-flutter-sdk'
  $archivePath = Join-Path $tempRoot 'flutter_windows_stable.zip'
  $installBase = Join-Path $env:LOCALAPPDATA 'medrash'
  $installDir = Join-Path $installBase 'flutter'
  $flutterBinDir = Join-Path $installDir 'bin'

  if (Test-Path $tempRoot) {
    Remove-Item -Path $tempRoot -Recurse -Force
  }
  New-Item -ItemType Directory -Path $tempRoot | Out-Null

  if (-not (Test-Path $installBase)) {
    New-Item -ItemType Directory -Path $installBase | Out-Null
  }

  if (Test-Path $installDir) {
    Remove-Item -Path $installDir -Recurse -Force
  }

  Download-FileRobust -Uri $archiveUrl -OutFile $archivePath
  tar -xf $archivePath -C $installBase

  if ($LASTEXITCODE -ne 0) {
    throw "Failed to extract Flutter archive with tar (exit code: $LASTEXITCODE)."
  }

  $flutterExe = Join-Path $flutterBinDir 'flutter.bat'
  if (-not (Test-Path $flutterExe)) {
    throw 'flutter.bat was not found after extraction.'
  }

  $userPath = [Environment]::GetEnvironmentVariable('Path', [EnvironmentVariableTarget]::User)
  if ($userPath -notlike "*$flutterBinDir*") {
    [Environment]::SetEnvironmentVariable('Path', "$userPath;$flutterBinDir", [EnvironmentVariableTarget]::User)
    Write-Host "[MedRash] Added $flutterBinDir to user PATH." -ForegroundColor Yellow
  }

  Write-Host '[MedRash] Flutter user-scope install complete.' -ForegroundColor Green
  Write-Host '[MedRash] Open a new terminal and run: flutter --version' -ForegroundColor Yellow
}

function Install-SupabaseCli {
  param(
    [bool]$UseUserScope
  )

  Write-Host '[MedRash] Installing Supabase CLI from GitHub release...' -ForegroundColor Cyan

  $releaseApi = 'https://api.github.com/repos/supabase/cli/releases/latest'
  $release = Invoke-RestMethod -Uri $releaseApi -UseBasicParsing
  $asset = $release.assets | Where-Object { $_.name -eq 'supabase_windows_amd64.tar.gz' } | Select-Object -First 1

  if (-not $asset) {
    throw 'Could not locate supabase_windows_amd64.tar.gz in latest release assets.'
  }

  $tempRoot = Join-Path $env:TEMP 'medrash-supabase-cli'
  $archivePath = Join-Path $tempRoot 'supabase_windows_amd64.tar.gz'
  $extractPath = Join-Path $tempRoot 'extract'
  $installDir = if ($UseUserScope) {
    Join-Path $env:LOCALAPPDATA 'medrash\supabase'
  } else {
    'C:\tools\supabase'
  }

  if (Test-Path $tempRoot) {
    Remove-Item -Path $tempRoot -Recurse -Force
  }

  New-Item -ItemType Directory -Path $tempRoot | Out-Null
  New-Item -ItemType Directory -Path $extractPath | Out-Null
  if (-not (Test-Path $installDir)) {
    New-Item -ItemType Directory -Path $installDir | Out-Null
  }

  Download-FileRobust -Uri $asset.browser_download_url -OutFile $archivePath

  tar -xzf $archivePath -C $extractPath

  $exePath = Get-ChildItem -Path $extractPath -Filter 'supabase.exe' -Recurse | Select-Object -First 1
  if (-not $exePath) {
    throw 'supabase.exe was not found after extraction.'
  }

  Copy-Item -Path $exePath.FullName -Destination (Join-Path $installDir 'supabase.exe') -Force

  if ($UseUserScope) {
    $userPath = [Environment]::GetEnvironmentVariable('Path', [EnvironmentVariableTarget]::User)
    if ($userPath -notlike "*$installDir*") {
      [Environment]::SetEnvironmentVariable('Path', "$userPath;$installDir", [EnvironmentVariableTarget]::User)
      Write-Host "[MedRash] Added $installDir to user PATH." -ForegroundColor Yellow
    }
  } else {
    $machinePath = [Environment]::GetEnvironmentVariable('Path', [EnvironmentVariableTarget]::Machine)
    if ($machinePath -notlike "*$installDir*") {
      [Environment]::SetEnvironmentVariable('Path', "$machinePath;$installDir", [EnvironmentVariableTarget]::Machine)
      Write-Host "[MedRash] Added $installDir to machine PATH." -ForegroundColor Yellow
    }
  }

  Write-Host '[MedRash] Supabase CLI install complete.' -ForegroundColor Green
  Write-Host '[MedRash] Open a new terminal and run: supabase --version' -ForegroundColor Yellow
}

if (-not ($InstallFlutter -or $InstallSupabase -or $All)) {
  Write-Host 'Usage:' -ForegroundColor Yellow
  Write-Host '  .\scripts\setup-dev-tools.ps1 -All'
  Write-Host '  .\scripts\setup-dev-tools.ps1 -InstallFlutter'
  Write-Host '  .\scripts\setup-dev-tools.ps1 -InstallSupabase'
  Write-Host '  .\scripts\setup-dev-tools.ps1 -InstallFlutter -UserScope'
  Write-Host '  .\scripts\setup-dev-tools.ps1 -InstallSupabase -UserScope'
  exit 0
}

if ($All -or $InstallFlutter) {
  if (-not $UserScope) {
    Assert-Admin
  }
}

if (($All -or $InstallSupabase) -and -not $UserScope -and -not ($All -or $InstallFlutter)) {
  Assert-Admin
}

if ($All -or $InstallFlutter) {
  Install-Flutter -UseUserScope:$UserScope
}

if ($All -or $InstallSupabase) {
  Install-SupabaseCli -UseUserScope:$UserScope
}

Write-Host '[MedRash] Tool setup script finished.' -ForegroundColor Green


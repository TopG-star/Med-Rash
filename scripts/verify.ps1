param(
  [ValidateSet('auto', 'local', 'hosted')]
  [string]$SupabaseMode = 'auto',
  [switch]$RequireLocalSupabase
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$appDir = Join-Path $repoRoot 'app'

$results = New-Object System.Collections.Generic.List[object]

function Add-Result {
  param(
    [string]$Step,
    [string]$Status,
    [string]$Details
  )

  $results.Add([PSCustomObject]@{
      Step = $Step
      Status = $Status
      Details = $Details
    }) | Out-Null

  if ($Status -eq 'PASS') {
    Write-Host "[PASS] $Step" -ForegroundColor Green
  }
  elseif ($Status -eq 'SKIP') {
    Write-Host "[SKIP] $Step" -ForegroundColor Yellow
  }
  else {
    Write-Host "[FAIL] $Step" -ForegroundColor Red
  }

  $normalizedDetails = $Details -replace '[^\x09\x0A\x0D\x20-\x7E]', ' '
  if ($normalizedDetails.Trim().Length -gt 0) {
    Write-Host $normalizedDetails
  }
}

function Resolve-Tool {
  param(
    [string]$Name,
    [string]$FallbackPath = ''
  )

  $command = Get-Command $Name -ErrorAction SilentlyContinue
  if ($null -ne $command) {
    return $command.Source
  }

  if ($FallbackPath -and (Test-Path $FallbackPath)) {
    return $FallbackPath
  }

  return $null
}

function Resolve-Flutter {
  $fromPath = Resolve-Tool -Name 'flutter'
  if ($fromPath) {
    return $fromPath
  }

  $candidates = @(
    (Join-Path $env:LOCALAPPDATA 'medrash\flutter\bin\flutter.bat'),
    (Join-Path $env:LOCALAPPDATA 'flutter\bin\flutter.bat'),
    'C:\src\flutter\bin\flutter.bat',
    'C:\tools\flutter\bin\flutter.bat'
  )

  foreach ($candidate in $candidates) {
    if ($candidate -and (Test-Path $candidate)) {
      return $candidate
    }
  }

  $medRashRoot = Join-Path $env:LOCALAPPDATA 'medrash'
  if (Test-Path $medRashRoot) {
    $found = Get-ChildItem -Path $medRashRoot -Filter 'flutter.bat' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) {
      return $found.FullName
    }
  }

  return $null
}

function Invoke-Step {
  param(
    [string]$Step,
    [scriptblock]$Action
  )

  Write-Host "`n==== $Step ====" -ForegroundColor Cyan
  try {
    $output = & $Action 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    if ($null -eq $exitCode) {
      $exitCode = 0
    }

    if ($exitCode -eq 0) {
      Add-Result -Step $Step -Status 'PASS' -Details $output.Trim()
    }
    else {
      Add-Result -Step $Step -Status 'FAIL' -Details "ExitCode=$exitCode`n$output"
    }
  }
  catch {
    Add-Result -Step $Step -Status 'FAIL' -Details $_.Exception.Message
  }
}

function Invoke-OptionalStep {
  param(
    [string]$Step,
    [scriptblock]$Action,
    [bool]$Strict
  )

  Write-Host "`n==== $Step ====" -ForegroundColor Cyan
  try {
    $output = & $Action 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    if ($null -eq $exitCode) {
      $exitCode = 0
    }

    if ($exitCode -eq 0) {
      Add-Result -Step $Step -Status 'PASS' -Details $output.Trim()
      return
    }

    $details = "ExitCode=$exitCode`n$output"
    if ($Strict) {
      Add-Result -Step $Step -Status 'FAIL' -Details $details
    }
    else {
      Add-Result -Step $Step -Status 'SKIP' -Details "Optional local Supabase check failed. $details"
    }
  }
  catch {
    if ($Strict) {
      Add-Result -Step $Step -Status 'FAIL' -Details $_.Exception.Message
    }
    else {
      Add-Result -Step $Step -Status 'SKIP' -Details "Optional local Supabase check failed. $($_.Exception.Message)"
    }
  }
}

function Read-EnvValue {
  param([string]$Name)
  $value = [Environment]::GetEnvironmentVariable($Name)
  if ($null -eq $value) {
    return ''
  }
  return $value.Trim()
}

$flutterExe = Resolve-Flutter
$dartExe = Resolve-Tool -Name 'dart' -FallbackPath (Join-Path $env:LOCALAPPDATA 'medrash\flutter\bin\cache\dart-sdk\bin\dart.exe')
$nodeExe = Resolve-Tool -Name 'node'
$supabaseExe = Resolve-Tool -Name 'supabase' -FallbackPath (Join-Path $env:LOCALAPPDATA 'medrash\supabase\supabase.exe')
$dockerExe = Resolve-Tool -Name 'docker'

$strictLocalSupabase = $RequireLocalSupabase.IsPresent -or $SupabaseMode -eq 'local'

Invoke-Step -Step 'Flutter Version' -Action {
  if (-not $flutterExe) {
    throw 'flutter was not found in PATH.'
  }
  & $flutterExe --version
}

Invoke-Step -Step 'Dart Version' -Action {
  if ($dartExe) {
    & $dartExe --version
    return
  }

  if ($flutterExe) {
    & $flutterExe dart --version
    return
  }

  throw 'dart and flutter were not found in PATH.'
}

Invoke-Step -Step 'Flutter Pub Get' -Action {
  if (-not $flutterExe) {
    throw 'flutter was not found in PATH.'
  }

  Push-Location $appDir
  try {
    & $flutterExe pub get
  }
  finally {
    Pop-Location
  }
}

Invoke-Step -Step 'Flutter Analyze' -Action {
  if (-not $flutterExe) {
    throw 'flutter was not found in PATH.'
  }

  Push-Location $appDir
  try {
    & $flutterExe analyze
  }
  finally {
    Pop-Location
  }
}

Invoke-Step -Step 'Flutter Test' -Action {
  if (-not $flutterExe) {
    throw 'flutter was not found in PATH.'
  }

  Push-Location $appDir
  try {
    & $flutterExe test
  }
  finally {
    Pop-Location
  }
}

if ($SupabaseMode -eq 'hosted') {
  Add-Result -Step 'Supabase Version' -Status 'SKIP' -Details "Skipped in hosted mode."
  Add-Result -Step 'Docker Version' -Status 'SKIP' -Details "Skipped in hosted mode."
}
else {
  Invoke-OptionalStep -Step 'Supabase Version' -Strict:$strictLocalSupabase -Action {
    if (-not $supabaseExe) {
      throw 'supabase was not found in PATH or user local install directory.'
    }

    & $supabaseExe --version
  }

  Invoke-OptionalStep -Step 'Docker Version' -Strict:$strictLocalSupabase -Action {
    if (-not $dockerExe) {
      throw 'docker was not found in PATH.'
    }

    & $dockerExe --version
  }
}

if ($SupabaseMode -eq 'hosted') {
  Invoke-Step -Step 'Hosted Supabase Env Check' -Action {
    $url = Read-EnvValue -Name 'SUPABASE_URL'
    $anonKey = Read-EnvValue -Name 'SUPABASE_ANON_KEY'
    $serviceRoleKey = Read-EnvValue -Name 'SUPABASE_SERVICE_ROLE_KEY'

    $missing = New-Object System.Collections.Generic.List[string]
    if (-not $url) { $missing.Add('SUPABASE_URL') | Out-Null }
    if (-not $anonKey) { $missing.Add('SUPABASE_ANON_KEY') | Out-Null }
    if (-not $serviceRoleKey) { $missing.Add('SUPABASE_SERVICE_ROLE_KEY') | Out-Null }

    if ($missing.Count -gt 0) {
      throw "Missing hosted Supabase environment variables: $($missing -join ', ')"
    }

    if (-not ($url -match '^https?://')) {
      throw 'SUPABASE_URL must be an absolute http(s) URL.'
    }

    "Hosted Supabase environment variables are configured."
  }

  Invoke-Step -Step 'Hosted Supabase Smoke Check' -Action {
    if (-not $nodeExe) {
      throw 'node was not found in PATH.'
    }

    Push-Location $repoRoot
    try {
      & $nodeExe scripts/hosted-check.mjs
    }
    finally {
      Pop-Location
    }
  }
}
else {
  Invoke-OptionalStep -Step 'Supabase Start' -Strict:$strictLocalSupabase -Action {
    if (-not $supabaseExe) {
      throw 'supabase was not found in PATH or user local install directory.'
    }

    Push-Location $repoRoot
    try {
      & $supabaseExe start
    }
    finally {
      Pop-Location
    }
  }

  Invoke-OptionalStep -Step 'Supabase Db Reset' -Strict:$strictLocalSupabase -Action {
    if (-not $supabaseExe) {
      throw 'supabase was not found in PATH or user local install directory.'
    }

    Push-Location $repoRoot
    try {
      & $supabaseExe db reset --yes
    }
    finally {
      Pop-Location
    }
  }

  if (-not $strictLocalSupabase) {
    Add-Result -Step 'Supabase Mode' -Status 'SKIP' -Details "Local Supabase checks are optional in 'auto' mode. Use -SupabaseMode local or -RequireLocalSupabase to enforce them."
  }
}

Write-Host "`n==== Verification Summary ====" -ForegroundColor Cyan
$results | Format-Table -AutoSize

$failures = @($results | Where-Object { $_.Status -eq 'FAIL' })
if ($failures.Count -gt 0) {
  Write-Host "`nVerification completed with failures." -ForegroundColor Red
  exit 1
}

Write-Host "`nVerification completed successfully." -ForegroundColor Green
exit 0


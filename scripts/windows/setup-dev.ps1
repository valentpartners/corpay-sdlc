# AISDLC dev-environment setup for Windows.
#
# Verifies the harness prerequisites the runner and skills depend on:
#   git, jq, curl.exe
#   yq              - mikefarah/yq Go binary
#   Bitbucket auth  - the runner opens PRs and posts comments through REST
#   codex, dotnet, node, npm
#
# The script avoids privileged or interactive installs. When something is
# missing it prints Windows-native commands for you to run in your own terminal.
#
# Usage:
#   powershell.exe -ExecutionPolicy Bypass -File .\scripts\windows\setup-dev.ps1
#   powershell.exe -ExecutionPolicy Bypass -File .\scripts\windows\setup-dev.ps1 --check

$ErrorActionPreference = 'Stop'

function Show-Help {
  @'
AISDLC dev-environment setup for Windows.

Usage:
  powershell.exe -ExecutionPolicy Bypass -File .\scripts\windows\setup-dev.ps1
  powershell.exe -ExecutionPolicy Bypass -File .\scripts\windows\setup-dev.ps1 --check

Checks baseline AISDLC tooling, Bitbucket REST access, and global Codex/.NET/Node
tool availability. Missing tools are reported with manual install commands.
'@ | Write-Output
}

$CheckOnly = $false
for ($i = 0; $i -lt $args.Count; $i++) {
  switch ($args[$i]) {
    '--check' { $CheckOnly = $true }
    '-Check' { $CheckOnly = $true }
    '-h' { Show-Help; exit 0 }
    '--help' { Show-Help; exit 0 }
    default {
      [Console]::Error.WriteLine("error: unknown argument: {0}", $args[$i])
      exit 2
    }
  }
}

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$AppRepo = Join-Path $RepoRoot 'code'

$script:Missing = New-Object 'System.Collections.Generic.List[string]'
$script:Manual = New-Object 'System.Collections.Generic.List[string]'

function Log([string]$Message) {
  [Console]::Error.WriteLine("[setup] {0}", $Message)
}

function Have([string]$Command) {
  $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

function Add-Missing([string]$Name, [string]$ManualCommand) {
  Log "missing: $Name"
  $script:Missing.Add($Name) | Out-Null
  if ($ManualCommand) {
    $script:Manual.Add($ManualCommand) | Out-Null
  }
}

function Check-Command([string]$Name, [string]$ManualCommand, [string]$DisplayName = $Name) {
  if (Have $Name) {
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    Log "ok: $DisplayName ($($cmd.Source))"
  } else {
    Add-Missing $DisplayName $ManualCommand
  }
}

function Check-CommandOrCandidate(
  [string]$Name,
  [string]$ManualCommand,
  [string]$DisplayName = $Name,
  [string[]]$CandidatePaths = @()
) {
  if (Have $Name) {
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    Log "ok: $DisplayName ($($cmd.Source))"
    return $true
  }

  foreach ($candidate in $CandidatePaths) {
    if ($candidate -and (Test-Path -LiteralPath $candidate)) {
      Log "installed but not on PATH: $DisplayName ($candidate)"
      $script:Missing.Add("$DisplayName (not on PATH)") | Out-Null
      if ($ManualCommand) {
        $script:Manual.Add($ManualCommand) | Out-Null
      }
      return $false
    }
  }

  Add-Missing $DisplayName $ManualCommand
  return $false
}

function Invoke-Text([string]$Command, [string[]]$Arguments) {
  try {
    $output = & $Command @Arguments 2>$null
  } catch {
    return ''
  }
  if ($LASTEXITCODE -ne 0) {
    return ''
  }
  return ($output -join "`n").Trim()
}

function Get-CodexConfigCandidates {
  if ($env:CODEX_CONFIG) { $env:CODEX_CONFIG }
  if ($HOME) { Join-Path $HOME '.codex\config.toml' }
  if ($env:USERPROFILE) { Join-Path $env:USERPROFILE '.codex\config.toml' }
}

function Read-CodexConfigKey([string]$Key) {
  $pattern = '^\s*' + [regex]::Escape($Key) + '\s*=\s*"([^"]*)"\s*$'
  foreach ($file in (Get-CodexConfigCandidates | Select-Object -Unique)) {
    if (-not $file -or -not (Test-Path -LiteralPath $file)) {
      continue
    }
    $value = $null
    foreach ($line in Get-Content -LiteralPath $file) {
      if ($line -match $pattern) {
        $value = $Matches[1]
      }
    }
    if ($value) {
      return $value
    }
  }
  return $null
}

function Load-Secret([string]$Name) {
  $value = [Environment]::GetEnvironmentVariable($Name, 'Process')
  if ($value) {
    return $value
  }
  return Read-CodexConfigKey $Name
}

function Jq-File([string]$Filter, [string]$File) {
  $filterFile = [System.IO.Path]::GetTempFileName()
  try {
    $utf8NoBom = New-Object 'System.Text.UTF8Encoding' $false
    [System.IO.File]::WriteAllText($filterFile, $Filter, $utf8NoBom)
    $output = & jq -r -f $filterFile $File 2>$null
  } catch {
    return ''
  } finally {
    Remove-Item -LiteralPath $filterFile -Force -ErrorAction SilentlyContinue
  }
  if ($LASTEXITCODE -ne 0) {
    return ''
  }
  return ($output -join "`n").Trim()
}

if ($CheckOnly) {
  Log 'check-only mode: no installs will be attempted'
}

# --- Windows baseline tools -------------------------------------------------

Check-Command 'git' 'winget install --id Git.Git -e'
Check-Command 'jq' 'winget install --id jqlang.jq -e'
Check-Command 'curl.exe' 'install or repair Windows curl.exe; it ships with supported Windows 10/11 builds' 'curl.exe'

if (Have 'yq') {
  $yqVersion = Invoke-Text 'yq' @('--version')
  if ($yqVersion -match 'mikefarah') {
    Log "ok: yq ($yqVersion)"
  } else {
    Log "WARN: a non-mikefarah 'yq' is on PATH. The runner needs mikefarah/yq v4 syntax."
    $script:Missing.Add('yq (wrong build on PATH)') | Out-Null
    $script:Manual.Add('winget install --id MikeFarah.yq -e') | Out-Null
  }
} else {
  Add-Missing 'yq' 'winget install --id MikeFarah.yq -e'
}

# --- Bitbucket auth ---------------------------------------------------------

$AisdlcJson = Join-Path $RepoRoot '.codex\aisdlc.json'
if (-not (Have 'jq')) {
  Log 'skipping Bitbucket auth check until jq is available'
} elseif (-not (Test-Path -LiteralPath $AisdlcJson)) {
  Log "missing $AisdlcJson"
  $script:Missing.Add('aisdlc.json') | Out-Null
} else {
  $ScmProvider = Jq-File '.sourceControl.provider // "bitbucket"' $AisdlcJson
  if ($ScmProvider -eq 'bitbucket') {
    $BbBaseUrl = Jq-File '.sourceControl.baseUrl // empty' $AisdlcJson
    $BbProjectKey = Jq-File '.sourceControl.projectKey // empty' $AisdlcJson
    $BbRepoSlug = Jq-File '.sourceControl.repositorySlug // empty' $AisdlcJson
    $BbTokenEnv = Jq-File '.sourceControl.apiTokenEnv // "BITBUCKET_API_TOKEN"' $AisdlcJson
    $BbToken = Load-Secret $BbTokenEnv

    if (-not $BbBaseUrl -or -not $BbProjectKey -or -not $BbRepoSlug) {
      Log 'missing Bitbucket sourceControl config in .codex/aisdlc.json'
      $script:Missing.Add('bitbucket-config') | Out-Null
    } elseif (-not $BbToken) {
      Log "missing Bitbucket API token ($BbTokenEnv)"
      $script:Manual.Add('$env:' + $BbTokenEnv + ' = "..."   # or add ' + $BbTokenEnv + ' to your Codex config') | Out-Null
      $script:Missing.Add($BbTokenEnv) | Out-Null
    } else {
      $BbBaseUrl = $BbBaseUrl.TrimEnd('/')
      $uri = "$BbBaseUrl/rest/api/latest/projects/$BbProjectKey/repos/$BbRepoSlug"
      try {
        Invoke-WebRequest -UseBasicParsing -Uri $uri -Headers @{
          Authorization = "Bearer $BbToken"
          Accept = 'application/json'
        } | Out-Null
        Log "ok: Bitbucket auth for $BbProjectKey/$BbRepoSlug"
      } catch {
        Log "Bitbucket auth/network check failed for $BbProjectKey/$BbRepoSlug"
        Log "web request: $($_.Exception.Message)"
        $script:Manual.Add("verify $BbTokenEnv can read $uri") | Out-Null
        $script:Missing.Add('bitbucket-auth') | Out-Null
      }
    }
  } else {
    Log "unsupported sourceControl.provider: $ScmProvider"
    $script:Missing.Add('sourceControl.provider') | Out-Null
  }
}

# --- stack-specific ---------------------------------------------------------

if (Test-Path -LiteralPath $AppRepo -PathType Container) {
  Log "ok: nested Corpay monorepo path exists ($AppRepo)"
  if (Have 'git') {
    & git -C $AppRepo rev-parse --is-inside-work-tree *> $null
    if ($LASTEXITCODE -eq 0) {
      Log 'ok: code/ is a git repository'
    } else {
      Log 'warning: code/ exists but git cannot inspect it'
      $script:Manual.Add("git config --global --add safe.directory `"$AppRepo`"   # if git reports dubious ownership") | Out-Null
    }
  } else {
    Log 'skipping code/ git inspection until git is available'
  }
} else {
  Log "missing: nested Corpay monorepo at $AppRepo"
  $script:Manual.Add("clone or move the Corpay monorepo to `"$AppRepo`"") | Out-Null
}

$DotnetCandidates = @(
  'C:\Program Files\dotnet\dotnet.exe',
  'C:\Program Files (x86)\dotnet\dotnet.exe'
)
$NodeCandidates = @(
  'C:\Program Files\nodejs\node.exe'
)
$NpmCandidates = @(
  'C:\Program Files\nodejs\npm.cmd',
  'C:\Program Files\nodejs\npm.ps1'
)

Check-Command 'codex' 'install Codex CLI, then re-run .\scripts\windows\setup-dev.ps1'
Check-CommandOrCandidate 'dotnet' 'add C:\Program Files\dotnet to PATH, restart the terminal, then re-run .\scripts\windows\setup-dev.ps1' 'dotnet' $DotnetCandidates | Out-Null
Check-CommandOrCandidate 'node' 'add C:\Program Files\nodejs to PATH, restart the terminal, then re-run .\scripts\windows\setup-dev.ps1' 'node' $NodeCandidates | Out-Null

if (Have 'npm') {
  $npmVersion = Invoke-Text 'npm' @('--version')
  if ($npmVersion) {
    $npmCommand = Get-Command npm -ErrorAction SilentlyContinue
    Log "ok: npm ($($npmCommand.Source))"
  } else {
    $npmCommand = Get-Command npm -ErrorAction SilentlyContinue
    Log "installed but unusable until node is on PATH: npm ($($npmCommand.Source))"
    $script:Missing.Add('npm (node not on PATH)') | Out-Null
    $script:Manual.Add('add C:\Program Files\nodejs to PATH, restart the terminal, then re-run .\scripts\windows\setup-dev.ps1') | Out-Null
  }
} else {
  Check-CommandOrCandidate 'npm' 'add C:\Program Files\nodejs to PATH, restart the terminal, then re-run .\scripts\windows\setup-dev.ps1' 'npm' $NpmCandidates | Out-Null
}

if (Have 'dotnet') {
  Log "dotnet version: $(Invoke-Text 'dotnet' @('--version'))"
}
if (Have 'node') {
  Log "node version: $(Invoke-Text 'node' @('--version'))"
}
if (Have 'npm') {
  $npmVersion = Invoke-Text 'npm' @('--version')
  if ($npmVersion) {
    Log "npm version: $npmVersion"
  }
}

Log 'note: no React/.NET dependencies are installed at the harness root; run discovered project commands from code/.'

# --- summary ---------------------------------------------------------------

[Console]::Error.WriteLine('')
if ($script:Missing.Count -eq 0 -and $script:Manual.Count -eq 0) {
  Log 'all set: baseline tooling present and Bitbucket auth verified.'
  exit 0
}

if ($script:Manual.Count -gt 0) {
  Log 'run these yourself:'
  foreach ($command in ($script:Manual | Select-Object -Unique)) {
    Log "  $command"
  }
}

if ($script:Missing.Count -gt 0) {
  Log "still missing after this run: $($script:Missing -join ', ')"
}

Log 're-run .\scripts\windows\setup-dev.ps1 after addressing the above.'
exit 1

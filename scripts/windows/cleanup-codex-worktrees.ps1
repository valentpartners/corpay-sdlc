# AISDLC worktree cleanup for Windows.
#
# Worktrees persist through `done` so per-story testing artifacts survive until
# they can be aggregated. This script copies those artifacts back into the
# integration tree, removes completed story worktrees, and deletes story
# branches.
#
# Usage:
#   powershell.exe -ExecutionPolicy Bypass -File .\scripts\windows\cleanup-codex-worktrees.ps1
#   powershell.exe -ExecutionPolicy Bypass -File .\scripts\windows\cleanup-codex-worktrees.ps1 --feature SLUG
#   powershell.exe -ExecutionPolicy Bypass -File .\scripts\windows\cleanup-codex-worktrees.ps1 --dry-run

$ErrorActionPreference = 'Stop'

function Show-Help {
  @'
AISDLC worktree cleanup for Windows.

Usage:
  powershell.exe -ExecutionPolicy Bypass -File .\scripts\windows\cleanup-codex-worktrees.ps1
  powershell.exe -ExecutionPolicy Bypass -File .\scripts\windows\cleanup-codex-worktrees.ps1 --feature SLUG
  powershell.exe -ExecutionPolicy Bypass -File .\scripts\windows\cleanup-codex-worktrees.ps1 --dry-run
'@ | Write-Output
}

$FeatureSlug = ''
$DryRun = $false
for ($i = 0; $i -lt $args.Count; $i++) {
  switch ($args[$i]) {
    '--feature' {
      $i++
      if ($i -ge $args.Count -or [string]::IsNullOrWhiteSpace($args[$i])) {
        [Console]::Error.WriteLine('error: --feature requires a feature slug')
        exit 2
      }
      $FeatureSlug = $args[$i]
    }
    '-Feature' {
      $i++
      if ($i -ge $args.Count -or [string]::IsNullOrWhiteSpace($args[$i])) {
        [Console]::Error.WriteLine('error: -Feature requires a feature slug')
        exit 2
      }
      $FeatureSlug = $args[$i]
    }
    '--dry-run' { $DryRun = $true }
    '-DryRun' { $DryRun = $true }
    '-h' { Show-Help; exit 0 }
    '--help' { Show-Help; exit 0 }
    default {
      [Console]::Error.WriteLine("error: unknown argument: {0}", $args[$i])
      exit 2
    }
  }
}

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$AisdlcJson = Join-Path $RepoRoot '.codex\aisdlc.json'

function Log([string]$Message) {
  $stamp = [DateTime]::UtcNow.ToString('HH:mm:ssZ')
  [Console]::Error.WriteLine("[{0}] {1}", $stamp, $Message)
}

function Fail([string]$Message) {
  Log "ERROR: $Message"
  exit 1
}

function Have([string]$Command) {
  $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

function To-Lines([string]$Text) {
  if ([string]::IsNullOrWhiteSpace($Text)) {
    return @()
  }
  return @($Text -split "`r?`n" | Where-Object { $_ -ne '' })
}

function New-FilterFile([string]$Filter) {
  $filterFile = [System.IO.Path]::GetTempFileName()
  $utf8NoBom = New-Object 'System.Text.UTF8Encoding' $false
  [System.IO.File]::WriteAllText($filterFile, $Filter, $utf8NoBom)
  return $filterFile
}

function Invoke-Text([string]$Command, [string[]]$Arguments, [switch]$AllowFailure) {
  $output = & $Command @Arguments 2>$null
  $code = $LASTEXITCODE
  if ($code -ne 0) {
    if ($AllowFailure) {
      return ''
    }
    Fail "$Command $($Arguments -join ' ') failed"
  }
  return ($output -join "`n").Trim()
}

function Test-NativeSuccess([string]$Command, [string[]]$Arguments) {
  & $Command @Arguments *> $null
  return $LASTEXITCODE -eq 0
}

function Jq-File([string]$Filter) {
  $filterFile = New-FilterFile $Filter
  try {
    $output = & jq -r -f $filterFile $AisdlcJson 2>$null
    if ($LASTEXITCODE -ne 0) {
      Fail "jq -r '$Filter' $AisdlcJson failed"
    }
    return ($output -join "`n").Trim()
  } finally {
    Remove-Item -LiteralPath $filterFile -Force -ErrorAction SilentlyContinue
  }
}

function Yq-File([string]$Filter, [string]$File) {
  $filterFile = New-FilterFile $Filter
  try {
    $output = & yq -r --from-file $filterFile $File 2>$null
    if ($LASTEXITCODE -ne 0) {
      Fail "yq -r '$Filter' $File failed"
    }
    return ($output -join "`n").Trim()
  } finally {
    Remove-Item -LiteralPath $filterFile -Force -ErrorAction SilentlyContinue
  }
}

function Expand-PathTemplate([string]$Template, [string]$Slug, [string]$StoryId = '') {
  $result = $Template.Replace('{feature-slug}', $Slug).Replace('{story-id}', $StoryId)
  return $result.TrimEnd([char[]]@('/', '\'))
}

function Join-Root([string]$Path) {
  if ([System.IO.Path]::IsPathRooted($Path)) {
    return [System.IO.Path]::GetFullPath($Path)
  }
  $native = $Path.Replace('/', [string][System.IO.Path]::DirectorySeparatorChar)
  return [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $native))
}

function Get-ManifestCandidates([string]$Template) {
  $token = '{feature-slug}'
  $tokenIndex = $Template.IndexOf($token)
  if ($tokenIndex -lt 0) {
    $candidate = Join-Root $Template
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
      Get-Item -LiteralPath $candidate
    }
    return
  }

  $prefix = $Template.Substring(0, $tokenIndex).TrimEnd([char[]]@('/', '\'))
  $suffix = $Template.Substring($tokenIndex + $token.Length).TrimStart([char[]]@('/', '\'))
  $searchRoot = if ($prefix) { Join-Root $prefix } else { $RepoRoot }
  if (-not (Test-Path -LiteralPath $searchRoot -PathType Container)) {
    return
  }

  $nativeSuffix = $suffix.Replace('/', [string][System.IO.Path]::DirectorySeparatorChar)
  foreach ($dir in Get-ChildItem -LiteralPath $searchRoot -Directory -ErrorAction SilentlyContinue) {
    $candidate = if ($nativeSuffix) { Join-Path $dir.FullName $nativeSuffix } else { $dir.FullName }
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
      Get-Item -LiteralPath $candidate
    }
  }
}

function Normalize-FullPath([string]$Path) {
  return ([System.IO.Path]::GetFullPath($Path)).TrimEnd([char[]]@('/', '\')).ToLowerInvariant()
}

foreach ($tool in @('git', 'yq', 'jq')) {
  if (-not (Have $tool)) {
    Fail "$tool required on PATH"
  }
}
if (-not (Have 'robocopy.exe')) {
  Fail 'robocopy.exe required on PATH'
}

if (-not (Test-Path -LiteralPath $AisdlcJson)) {
  Fail "missing $AisdlcJson"
}
Set-Location -LiteralPath $RepoRoot

$AppRepoRel = Jq-File '.repositories.application // "."'
$AppRepoRoot = Join-Root $AppRepoRel
if (-not (Test-Path -LiteralPath $AppRepoRoot -PathType Container)) {
  Fail "application repository path does not exist: $AppRepoRoot"
}
if (-not (Test-NativeSuccess 'git' @('-C', $AppRepoRoot, 'rev-parse', '--is-inside-work-tree'))) {
  Fail "not a git repository or not trusted by git: $AppRepoRoot"
}

$BranchPrefix = Jq-File '.branches.prefix'
$PathManifestTpl = Jq-File '.paths.manifest'
$PathWorktreesTpl = Jq-File '.paths.worktrees'
$PathRunsTpl = Jq-File '.paths.runs'

# --- locate manifest --------------------------------------------------------

$Manifest = ''
if ($FeatureSlug) {
  $Manifest = Join-Root (Expand-PathTemplate $PathManifestTpl $FeatureSlug)
  if (-not (Test-Path -LiteralPath $Manifest)) {
    Fail "no manifest at $Manifest"
  }
} else {
  $CurrentBranch = Invoke-Text 'git' @('-C', $AppRepoRoot, 'branch', '--show-current')
  if (-not $CurrentBranch) {
    Fail 'could not determine current branch; pass --feature SLUG'
  }

  foreach ($candidate in Get-ManifestCandidates $PathManifestTpl) {
    $branch = Yq-File '.feature.branch' $candidate.FullName
    if ($branch -eq $CurrentBranch) {
      if ($Manifest) {
        Fail "multiple manifests match branch '$CurrentBranch': $Manifest and $($candidate.FullName)"
      }
      $Manifest = $candidate.FullName
    }
  }
  if (-not $Manifest) {
    Fail "no manifest matches current branch '$CurrentBranch'; pass --feature SLUG"
  }
  $FeatureSlug = Yq-File '.feature.slug' $Manifest
}

Log "feature=$FeatureSlug manifest=$Manifest dry-run=$DryRun"

# --- registered-worktree set ------------------------------------------------

$script:RegisteredWorktrees = @{}
$worktreeList = Invoke-Text 'git' @('-C', $AppRepoRoot, 'worktree', 'list', '--porcelain')
foreach ($line in To-Lines $worktreeList) {
  if ($line.StartsWith('worktree ')) {
    $path = $line.Substring('worktree '.Length)
    $script:RegisteredWorktrees[(Normalize-FullPath $path)] = $true
  }
}

function Test-WorktreeRegistered([string]$RelativeWorktree) {
  $full = Join-Root $RelativeWorktree
  return $script:RegisteredWorktrees.ContainsKey((Normalize-FullPath $full))
}

# --- pre-flight -------------------------------------------------------------

$BailList = New-Object 'System.Collections.Generic.List[string]'
$storyRows = Yq-File '.stories[] | [.id, .state] | @tsv' $Manifest
foreach ($row in To-Lines $storyRows) {
  $parts = $row -split "`t"
  if ($parts.Count -lt 2) {
    continue
  }
  $sid = $parts[0]
  $state = $parts[1]
  if ($state -eq 'done' -or $state -eq 'wontfix') {
    continue
  }
  $wt = Expand-PathTemplate $PathWorktreesTpl $FeatureSlug $sid
  if (Test-WorktreeRegistered $wt) {
    $BailList.Add("$sid (state=$state)") | Out-Null
  }
}

if ($BailList.Count -gt 0) {
  Log 'ERROR: non-terminal stories still have worktrees; refusing to proceed'
  foreach ($story in $BailList) {
    Log "  - $story"
  }
  Log 'let testing complete (or mark the slice wontfix) and re-run.'
  exit 1
}

# --- iterate stories --------------------------------------------------------

$cleaned = 0
$skippedState = 0
$skippedMissing = 0
$skippedDirty = 0
$SkippedDetail = New-Object 'System.Collections.Generic.List[string]'

foreach ($row in To-Lines $storyRows) {
  $parts = $row -split "`t"
  if ($parts.Count -lt 2) {
    continue
  }
  $sid = $parts[0]
  $state = $parts[1]
  $branch = "$BranchPrefix$sid"
  $wt = Expand-PathTemplate $PathWorktreesTpl $FeatureSlug $sid
  $wtFull = Join-Root $wt

  if ($state -ne 'done') {
    $skippedState++
    $SkippedDetail.Add("${sid}: state=$state") | Out-Null
    continue
  }

  $wtLive = Test-WorktreeRegistered $wt
  $wtOrphan = (-not $wtLive) -and (Test-Path -LiteralPath $wtFull -PathType Container)
  $brPresent = Test-NativeSuccess 'git' @('-C', $AppRepoRoot, 'show-ref', '--verify', '--quiet', "refs/heads/$branch")
  $remotePresent = Test-NativeSuccess 'git' @('-C', $AppRepoRoot, 'ls-remote', '--exit-code', '--heads', 'origin', $branch)

  if (-not $wtLive -and -not $wtOrphan -and -not $brPresent -and -not $remotePresent) {
    $skippedMissing++
    continue
  }

  if ($wtLive) {
    $dirty = Invoke-Text 'git' @(
      '-C', $wtFull,
      'status', '--porcelain', '--',
      '.', ':(exclude).codex', ':(exclude)AGENTS.md', ':(exclude).worktreeinclude',
      ':(exclude)CONTEXT.md', ':(exclude)docs', ':(exclude)scripts'
    ) -AllowFailure
    if ($dirty) {
      $firstDirty = (To-Lines $dirty)[0]
      Log "warn: $sid - worktree has uncommitted changes; skipping ($firstDirty)"
      $skippedDirty++
      $SkippedDetail.Add("${sid}: dirty worktree") | Out-Null
      continue
    }
  }

  if ($DryRun) {
    Log "would clean: $sid (worktree=$wtLive orphan=$wtOrphan branch=$brPresent remote=$remotePresent)"
    $cleaned++
    continue
  }

  if ($wtLive) {
    $runsRel = Expand-PathTemplate $PathRunsTpl $FeatureSlug $sid
    $src = Join-Root (Join-Path $wt $runsRel)
    $dst = Join-Root $runsRel
    if (Test-Path -LiteralPath $src -PathType Container) {
      New-Item -ItemType Directory -Force -Path $dst | Out-Null
      & robocopy.exe $src $dst /E /NFL /NDL /NJH /NJS /NP *> $null
      $copyCode = $LASTEXITCODE
      if ($copyCode -gt 7) {
        Log "  warn: robocopy failed for $sid (exit $copyCode)"
      }
    } else {
      Log "  note: $sid has no runs dir in worktree; skipping copy-back"
    }
  }

  if ($wtLive) {
    & git -C $AppRepoRoot worktree remove --force $wtFull 2>$null
    if ($LASTEXITCODE -ne 0) {
      Log "  warn: failed to remove worktree $wt (will remove dir as fallback)"
    }
  }

  if (Test-Path -LiteralPath $wtFull -PathType Container) {
    Remove-Item -LiteralPath $wtFull -Recurse -Force
    if ($wtOrphan) {
      Log "  removed orphan dir $wt"
    }
  }

  if ($brPresent) {
    & git -C $AppRepoRoot branch -D $branch 2>$null
    if ($LASTEXITCODE -ne 0) {
      Log "  warn: failed to delete branch $branch"
    }
  }

  if ($remotePresent) {
    & git -C $AppRepoRoot push origin --delete $branch *> $null
    if ($LASTEXITCODE -eq 0) {
      Log "  deleted remote branch origin/$branch"
    } else {
      Log "  warn: failed to delete remote branch origin/$branch"
    }
  }

  Log "cleaned: $sid (runs copied + worktree + branch)"
  $cleaned++
}

# --- summary ----------------------------------------------------------------

[Console]::Error.WriteLine('')
Log "summary: cleaned=$cleaned skipped_state=$skippedState skipped_missing=$skippedMissing skipped_dirty=$skippedDirty"
if ($SkippedDetail.Count -gt 0) {
  Log 'stories left intact:'
  foreach ($line in $SkippedDetail) {
    Log "  - $line"
  }
}

$featureBranch = Yq-File '.feature.branch' $Manifest
Log "feature integration branch ($featureBranch) left alone; delete it manually after merging into protected."
if ($cleaned -gt 0 -and -not $DryRun) {
  Log "next: invoke to-qa-handoff to generate docs/ai-runs/$FeatureSlug/qa-handoff.md"
}

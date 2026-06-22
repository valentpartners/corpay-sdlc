# AISDLC Phase 2 runner for Windows - manifest-driven, Bitbucket-backed.
#
# Reads docs/ai-runs/<feature-slug>/manifest.yaml. The script picks one
# eligible story at a time, spawns a fresh `codex` in a per-story worktree,
# runs post-agent gates, pushes the branch, opens or updates the PR, posts a
# typed `run-summary` PR comment, and flips manifest state.
#
# Usage:
#   powershell.exe -ExecutionPolicy Bypass -File .\scripts\windows\run-codex-loop.ps1
#   powershell.exe -ExecutionPolicy Bypass -File .\scripts\windows\run-codex-loop.ps1 --watch 300

$ErrorActionPreference = 'Stop'

function Show-Help {
  @'
AISDLC Phase 2 runner for Windows.

Usage:
  powershell.exe -ExecutionPolicy Bypass -File .\scripts\windows\run-codex-loop.ps1
  powershell.exe -ExecutionPolicy Bypass -File .\scripts\windows\run-codex-loop.ps1 --watch 300
'@ | Write-Output
}

$WatchInterval = 0
for ($i = 0; $i -lt $args.Count; $i++) {
  switch ($args[$i]) {
    '--watch' {
      $i++
      if ($i -ge $args.Count -or $args[$i] -notmatch '^\d+$' -or [int]$args[$i] -lt 30) {
        [Console]::Error.WriteLine('error: --watch requires a positive integer >= 30 (seconds)')
        exit 2
      }
      $WatchInterval = [int]$args[$i]
    }
    '-Watch' {
      $i++
      if ($i -ge $args.Count -or $args[$i] -notmatch '^\d+$' -or [int]$args[$i] -lt 30) {
        [Console]::Error.WriteLine('error: -Watch requires a positive integer >= 30 (seconds)')
        exit 2
      }
      $WatchInterval = [int]$args[$i]
    }
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
$script:RunnerLog = ''
$script:PrOpenRemaining = 0

function Log([string]$Message) {
  $stamp = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
  $line = "[$stamp] $Message"
  [Console]::Error.WriteLine($line)
  if ($script:RunnerLog) {
    Add-Content -LiteralPath $script:RunnerLog -Value $line -Encoding UTF8
  }
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

function Resolve-GitCommonDir([string]$RepoRoot) {
  $commonDir = Invoke-Text 'git' @('-C', $RepoRoot, 'rev-parse', '--git-common-dir')
  if (-not $commonDir) {
    Fail "could not resolve git common dir for $RepoRoot"
  }
  if ([System.IO.Path]::IsPathRooted($commonDir)) {
    return [System.IO.Path]::GetFullPath($commonDir)
  }
  return [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $commonDir))
}

function Resolve-GitDir([string]$RepoRoot) {
  $gitDir = Invoke-Text 'git' @('-C', $RepoRoot, 'rev-parse', '--git-dir')
  if (-not $gitDir) {
    Fail "could not resolve git dir for $RepoRoot"
  }
  if ([System.IO.Path]::IsPathRooted($gitDir)) {
    return [System.IO.Path]::GetFullPath($gitDir)
  }
  return [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $gitDir))
}

function Test-NativeSuccess([string]$Command, [string[]]$Arguments) {
  & $Command @Arguments *> $null
  return $LASTEXITCODE -eq 0
}

function Invoke-NativeQuiet([string]$Command, [string[]]$Arguments, [switch]$AllowFailure) {
  $previousErrorActionPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    $output = & $Command @Arguments 2>&1
    $code = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }

  if ($code -ne 0) {
    if ($AllowFailure) {
      return $false
    }
    $snippet = (($output | ForEach-Object { $_.ToString() }) -join "`n").Trim()
    if ($snippet.Length -gt 800) {
      $snippet = $snippet.Substring(0, 800) + '...'
    }
    if ($snippet) {
      Fail "$Command $($Arguments -join ' ') failed rc=$code`n$snippet"
    }
    Fail "$Command $($Arguments -join ' ') failed rc=$code"
  }
  return $true
}

function Invoke-JqInput([string[]]$Arguments, [string]$InputJson, [switch]$AllowFailure) {
  $filterIndex = -1
  for ($i = 0; $i -lt $Arguments.Count; $i++) {
    $arg = $Arguments[$i]
    if (@('--arg', '--argjson', '--slurpfile', '--rawfile', '--argfile') -contains $arg) {
      $i += 2
      continue
    }
    if (@('-f', '--from-file') -contains $arg) {
      $i += 1
      continue
    }
    if ($arg.StartsWith('-')) {
      continue
    }
    $filterIndex = $i
    break
  }

  $filterFile = $null
  $jqArgs = New-Object 'System.Collections.Generic.List[string]'
  try {
    for ($i = 0; $i -lt $Arguments.Count; $i++) {
      if ($i -eq $filterIndex) {
        $filterFile = New-FilterFile $Arguments[$i]
        $jqArgs.Add('-f') | Out-Null
        $jqArgs.Add($filterFile) | Out-Null
      } else {
        $jqArgs.Add($Arguments[$i]) | Out-Null
      }
    }

    $output = $InputJson | & jq @($jqArgs.ToArray()) 2>$null
    $code = $LASTEXITCODE
    if ($code -ne 0) {
      if ($AllowFailure) {
        return ''
      }
      Fail "jq $($Arguments -join ' ') failed"
    }
    return ($output -join "`n").Trim()
  } finally {
    if ($filterFile) {
      Remove-Item -LiteralPath $filterFile -Force -ErrorAction SilentlyContinue
    }
  }
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

function Yq-File([string]$Filter, [string]$File, [switch]$AllowFailure) {
  $filterFile = New-FilterFile $Filter
  try {
    $output = & yq -r --from-file $filterFile $File 2>$null
    $code = $LASTEXITCODE
    if ($code -ne 0) {
      if ($AllowFailure) {
        return ''
      }
      Fail "yq -r '$Filter' $File failed"
    }
    return ($output -join "`n").Trim()
  } finally {
    Remove-Item -LiteralPath $filterFile -Force -ErrorAction SilentlyContinue
  }
}

function Invoke-YqEdit([string]$Filter, [string]$File) {
  $filterFile = New-FilterFile $Filter
  try {
    & yq -i --from-file $filterFile $File 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
      Fail "yq -i '$Filter' $File failed"
    }
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

function Get-ManifestPathSlug([string]$ManifestPath) {
  return Split-Path (Split-Path $ManifestPath -Parent) -Leaf
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

foreach ($tool in @('git', 'jq', 'yq', 'codex')) {
  if (-not (Have $tool)) {
    Fail "$tool required on PATH"
  }
}
if (-not (Have 'taskkill.exe')) {
  Fail 'taskkill.exe required on PATH'
}
if (-not (Test-Path -LiteralPath $AisdlcJson)) {
  Fail "missing $AisdlcJson"
}

$AppRepoRel = Jq-File '.repositories.application // "."'
$AppRepoRoot = Join-Root $AppRepoRel
if (-not (Test-Path -LiteralPath $AppRepoRoot -PathType Container)) {
  Fail "application repository path does not exist: $AppRepoRoot"
}

Set-Location -LiteralPath $RepoRoot

if (-not (Test-NativeSuccess 'git' @('-C', $AppRepoRoot, 'rev-parse', '--is-inside-work-tree'))) {
  Fail "not a git repository or not trusted by git: $AppRepoRoot"
}
$AppRepoGitCommonDir = Resolve-GitCommonDir $AppRepoRoot

# --- config load ------------------------------------------------------------

$BranchPrefix = Jq-File '.branches.prefix'
$ProtectedBranches = To-Lines (Jq-File '.branches.protected[]')
$DiffFileCap = [int](Jq-File '.caps.diffFiles')
$DiffLineCap = [int](Jq-File '.caps.diffLines')
$DiffIgnorePathspec = @()
foreach ($glob in To-Lines (Jq-File '.caps.diffIgnoreGlobs[]?')) {
  if ($glob) {
    $DiffIgnorePathspec += ":(exclude)$glob"
  }
}
$TddMaxAttempts = Jq-File '.caps.tddAttempts'
$PerStoryWallClock = [int](Jq-File '.caps.perStoryWallClockSec')
$SandboxMode = Jq-File '.runner.sandboxMode // "workspace-write"'
$ApprovalPolicy = Jq-File '.runner.approvalPolicy // "on-request"'
$Model = Jq-File '.runner.model // empty'

$ScmProvider = Jq-File '.sourceControl.provider // "bitbucket"'
if ($ScmProvider -ne 'bitbucket') {
  Fail "unsupported sourceControl.provider '$ScmProvider' (this runner expects bitbucket)"
}
$script:BbBaseUrl = (Jq-File '.sourceControl.baseUrl // empty').TrimEnd('/')
$BbProjectKey = Jq-File '.sourceControl.projectKey // empty'
$BbRepoSlug = Jq-File '.sourceControl.repositorySlug // empty'
$BbTokenEnv = Jq-File '.sourceControl.apiTokenEnv // "BITBUCKET_API_TOKEN"'
if (-not $script:BbBaseUrl) { Fail 'sourceControl.baseUrl required for Bitbucket' }
if (-not $BbProjectKey) { Fail 'sourceControl.projectKey required for Bitbucket' }
if (-not $BbRepoSlug) { Fail 'sourceControl.repositorySlug required for Bitbucket' }
$script:BbRestPath = "/rest/api/latest/projects/$BbProjectKey/repos/$BbRepoSlug"
$script:BbToken = Load-Secret $BbTokenEnv
if (-not $script:BbToken) {
  Fail "$BbTokenEnv required in environment or Codex config for Bitbucket API"
}

$PathManifestTpl = Jq-File '.paths.manifest'
$PathRunsTpl = Jq-File '.paths.runs'
$PathWorktreesTpl = Jq-File '.paths.worktrees'
$CommentTypeRunSummary = Jq-File '.commentTypes.runSummary'
$CommentTypeDiagnostics = Jq-File '.commentTypes.agentDiagnostics'

$WorktreesRoot = ($PathWorktreesTpl -replace '\{.*$', '').TrimEnd([char[]]@('/', '\'))
$LockRel = if ($WorktreesRoot) { Join-Path $WorktreesRoot '.runner.lock' } else { '.runner.lock' }
$LockFile = Join-Root $LockRel

# --- branch + manifest resolution ------------------------------------------

$IntegrationBranch = Invoke-Text 'git' @('-C', $AppRepoRoot, 'branch', '--show-current')
if (-not $IntegrationBranch) {
  Fail 'could not determine current branch (detached HEAD?)'
}
if ($ProtectedBranches -contains $IntegrationBranch) {
  Fail "refusing to run from protected branch '$IntegrationBranch'; check out a feature branch first"
}

$Manifest = ''
foreach ($candidate in Get-ManifestCandidates $PathManifestTpl) {
  $branch = Yq-File '.feature.branch' $candidate.FullName
  if ($branch -eq $IntegrationBranch) {
    if ($Manifest) {
      Fail "multiple manifests claim feature.branch=${IntegrationBranch}: $Manifest and $($candidate.FullName)"
    }
    $Manifest = $candidate.FullName
  }
}
if (-not $Manifest) {
  Fail "no manifest matching template '$PathManifestTpl' matches current branch '$IntegrationBranch'"
}

$FeatureSlug = Yq-File '.feature.slug' $Manifest
$FeaturePathSlug = Get-ManifestPathSlug $Manifest
$runsForBase = Expand-PathTemplate $PathRunsTpl $FeaturePathSlug 'X'
$RunsBase = Split-Path $runsForBase -Parent
$script:RunnerLog = Join-Root (Join-Path $RunsBase 'runner.log')
New-Item -ItemType Directory -Force -Path (Split-Path $script:RunnerLog -Parent) | Out-Null

Log "feature=$FeatureSlug runFolder=$FeaturePathSlug integration=$IntegrationBranch appRepo=$AppRepoRoot manifest=$Manifest"

# --- lockfile ---------------------------------------------------------------

New-Item -ItemType Directory -Force -Path (Split-Path $LockFile -Parent) | Out-Null
if (Test-Path -LiteralPath $LockFile) {
  $prevPid = (Get-Content -LiteralPath $LockFile -ErrorAction SilentlyContinue | Select-Object -First 1)
  if ($prevPid -and (Get-Process -Id $prevPid -ErrorAction SilentlyContinue)) {
    Fail "another runner is active (pid $prevPid). Remove $LockFile if you're sure it isn't."
  }
  Log "stale lockfile at $LockFile (pid $prevPid no longer alive); removing"
  Remove-Item -LiteralPath $LockFile -Force
}
Set-Content -LiteralPath $LockFile -Value $PID -Encoding ASCII

function Invoke-BitbucketApi([string]$Method, [string]$Path, [AllowNull()][string]$Body = $null) {
  $headers = @{
    Authorization = "Bearer $script:BbToken"
    Accept = 'application/json'
  }
  $params = @{
    Method = $Method
    Uri = "$script:BbBaseUrl$Path"
    Headers = $headers
    UseBasicParsing = $true
  }
  if ($PSBoundParameters.ContainsKey('Body') -and -not [string]::IsNullOrEmpty($Body)) {
    $params['Body'] = $Body
    $params['ContentType'] = 'application/json'
  }
  try {
    $response = Invoke-WebRequest @params
    return $response.Content
  } catch {
    $message = $_.Exception.Message
    $status = ''
    $bodySnippet = ''
    if ($_.Exception.Response) {
      try {
        $status = " status=$([int]$_.Exception.Response.StatusCode) $($_.Exception.Response.StatusDescription)"
      } catch {
        $status = ''
      }
    }
    if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
      $bodySnippet = $_.ErrorDetails.Message
      if ($bodySnippet.Length -gt 500) {
        $bodySnippet = $bodySnippet.Substring(0, 500) + '...'
      }
    }
    throw "Bitbucket $Method $($params['Uri']) failed$status`: $message $bodySnippet"
  }
}

try {
  Invoke-BitbucketApi 'GET' $script:BbRestPath | Out-Null
} catch {
  Fail "could not read Bitbucket repo $BbProjectKey/$BbRepoSlug with ${BbTokenEnv}: $_"
}
Log "bitbucket repo: $BbProjectKey/$BbRepoSlug ($script:BbBaseUrl)"

# --- manifest helpers -------------------------------------------------------

function Manifest-StoryField([string]$StoryId, [string]$Field) {
  Yq-File ('.stories[] | select(.id == "' + $StoryId + '") | .' + $Field) $Manifest
}

function Manifest-SetState([string]$StoryId, [string]$State) {
  Invoke-YqEdit ('(.stories[] | select(.id == "' + $StoryId + '") | .state) = "' + $State + '"') $Manifest
  Log "state: $StoryId -> $State"
}

function Manifest-SetPr([string]$StoryId, [string]$PrNumber) {
  Invoke-YqEdit ('(.stories[] | select(.id == "' + $StoryId + '") | .pr) = ' + $PrNumber) $Manifest
}

function Get-ManifestStoryIds {
  To-Lines (Yq-File '.stories[].id' $Manifest)
}

function Story-HasOverride([string]$StoryId, [string]$Token) {
  $hit = Yq-File ('.stories[] | select(.id == "' + $StoryId + '") | .override[]? | select(. == "' + $Token + '")') $Manifest -AllowFailure
  return -not [string]::IsNullOrWhiteSpace($hit)
}

function Story-HasTouch([string]$StoryId, [string]$Token) {
  $hit = Yq-File ('.stories[] | select(.id == "' + $StoryId + '") | .touches[]? | select(. == "' + $Token + '")') $Manifest -AllowFailure
  return -not [string]::IsNullOrWhiteSpace($hit)
}

function Story-IsVerificationOnly([string]$StoryId) {
  return (Story-HasTouch $StoryId 'verification')
}

function Manifest-StateOf([string]$StoryId) {
  Manifest-StoryField $StoryId 'state'
}

function Test-ManifestPredecessorsDone([string]$StoryId) {
  $preds = To-Lines (Yq-File ('.stories[] | select(.id == "' + $StoryId + '") | .blocked_by[]') $Manifest -AllowFailure)
  foreach ($pred in $preds) {
    if ((Manifest-StateOf $pred) -ne 'done') {
      return $false
    }
  }
  return $true
}

function Get-ManifestFirstUndonePredecessor([string]$StoryId) {
  $preds = To-Lines (Yq-File ('.stories[] | select(.id == "' + $StoryId + '") | .blocked_by[]') $Manifest -AllowFailure)
  foreach ($pred in $preds) {
    $state = Manifest-StateOf $pred
    if ($state -ne 'done') {
      return "$pred ($state)"
    }
  }
  return ''
}

# --- Bitbucket helpers ------------------------------------------------------

function Test-PrExists([string]$Pr) {
  if (-not $Pr -or $Pr -eq 'null') {
    return $false
  }
  try {
    Invoke-BitbucketApi 'GET' "$script:BbRestPath/pull-requests/$Pr" | Out-Null
    return $true
  } catch {
    return $false
  }
}

function Test-PrMerged([string]$Pr) {
  try {
    $json = Invoke-BitbucketApi 'GET' "$script:BbRestPath/pull-requests/$Pr"
    $state = Invoke-JqInput @('-r', '.state // empty') $json
    return $state -eq 'MERGED'
  } catch {
    return $false
  }
}

function Get-BbPrActivitiesJson([string]$Pr) {
  $start = 0
  $out = '[]'
  while ($true) {
    $page = Invoke-BitbucketApi 'GET' "$script:BbRestPath/pull-requests/$Pr/activities?limit=100&start=$start"
    $out = Invoke-JqInput @('-s', '.[0] + (.[1].values // [])') "$out`n$page"
    $isLast = Invoke-JqInput @('-r', '.isLastPage // true') $page
    if ($isLast -eq 'true') {
      break
    }
    $next = Invoke-JqInput @('-r', '.nextPageStart // empty') $page
    if (-not $next) {
      break
    }
    $start = [int]$next
  }
  return $out
}

function Get-BbPrCommentsJson([string]$Pr) {
  $activities = Get-BbPrActivitiesJson $Pr
  $filter = @'
[
  .[]
  | select(.action == "COMMENTED")
  | select(.comment != null)
  | {
      id: (.comment.id // null),
      createdDate: (.comment.createdDate // 0),
      createdIso: (((.comment.createdDate // 0) / 1000) | todateiso8601),
      author: (.comment.author.displayName // .comment.author.name // .comment.author.emailAddress // "unknown"),
      text: (.comment.text // ""),
      anchor: (.commentAnchor // null),
      replies: [
        (.comment.comments // [])[]
        | {
            id: (.id // null),
            createdDate: (.createdDate // 0),
            createdIso: (((.createdDate // 0) / 1000) | todateiso8601),
            author: (.author.displayName // .author.name // .author.emailAddress // "unknown"),
            text: (.text // "")
          }
      ]
    }
]
'@
  Invoke-JqInput @($filter) $activities
}

function Find-BbOpenPrForBranch([string]$FromBranch, [string]$TargetBranch) {
  $fromRef = "refs/heads/$FromBranch"
  $toRef = "refs/heads/$TargetBranch"
  $start = 0
  $filter = @'
.values[]
| select(.fromRef.id == $from_ref)
| select(.toRef.id == $to_ref)
| .id
'@
  while ($true) {
    $page = Invoke-BitbucketApi 'GET' "$script:BbRestPath/pull-requests?state=OPEN&limit=100&start=$start"
    $hit = To-Lines (Invoke-JqInput @('-r', '--arg', 'from_ref', $fromRef, '--arg', 'to_ref', $toRef, $filter) $page) | Select-Object -First 1
    if ($hit) {
      return $hit
    }
    $isLast = Invoke-JqInput @('-r', '.isLastPage // true') $page
    if ($isLast -eq 'true') {
      break
    }
    $next = Invoke-JqInput @('-r', '.nextPageStart // empty') $page
    if (-not $next) {
      break
    }
    $start = [int]$next
  }
  return ''
}

function Get-PrWatermark([string]$Pr) {
  try {
    $comments = Get-BbPrCommentsJson $Pr
    return Invoke-JqInput @('-r', '[.[] | select(.text | startswith("## [Type:")) | .createdDate] | max // empty') $comments
  } catch {
    return ''
  }
}

function Get-PrHumanFeedbackBundle([string]$Pr, [string]$Watermark) {
  $since = if ($Watermark) { $Watermark } else { '0' }
  try {
    $comments = Get-BbPrCommentsJson $Pr
    $general = Invoke-JqInput @('--argjson', 'since', $since, @'
[
  .[]
  | select(.createdDate > $since)
  | select(.text | startswith("## [Type:") | not)
]
'@) $comments
    $replies = Invoke-JqInput @('--argjson', 'since', $since, @'
[
  .[]
  | . as $parent
  | .replies[]
  | select(.createdDate > $since)
  | select(.text | startswith("## [Type:") | not)
  | . + {anchor: $parent.anchor, parentId: $parent.id}
]
'@) $comments
    $all = Invoke-JqInput @('-s', 'add | sort_by(.createdDate)') "$general`n$replies"
    if ([int](Invoke-JqInput @('length') $all) -le 0) {
      return ''
    }

    $general = Invoke-JqInput @('[.[] | select(.anchor == null)]') $all
    $inline = Invoke-JqInput @('[.[] | select(.anchor != null)]') $all
    $lines = New-Object 'System.Collections.Generic.List[string]'
    $lines.Add("## Human feedback on PR #$Pr since the last run-summary") | Out-Null

    if ([int](Invoke-JqInput @('length') $general) -gt 0) {
      $lines.Add('') | Out-Null
      $lines.Add('### General comments') | Out-Null
      foreach ($line in To-Lines (Invoke-JqInput @('-r', '.[] | "- [\(.createdIso)] \(.author): \(.text | gsub("\r?\n"; "\n  "))"') $general)) {
        $lines.Add($line) | Out-Null
      }
    }

    if ([int](Invoke-JqInput @('length') $inline) -gt 0) {
      $lines.Add('') | Out-Null
      $lines.Add('### Line comments (grouped by file)') | Out-Null
      $inlineFilter = @'
sort_by(.anchor.path // "unknown", .anchor.line // 0, .createdDate)
| group_by(.anchor.path // "unknown")
| .[] |
  "\n**\(.[0].anchor.path // "unknown")**\n" +
  (
    group_by(.anchor.line // 0)
    | map(
        "\nL\(.[0].anchor.line // "?"):\n" +
        (map("- [\(.createdIso)] \(.author): \(.text | gsub("\r?\n"; "\n  "))") | join("\n"))
      )
    | join("\n")
  )
'@
      foreach ($line in To-Lines (Invoke-JqInput @('-r', $inlineFilter) $inline)) {
        $lines.Add($line) | Out-Null
      }
    }
    return ($lines -join "`n")
  } catch {
    return ''
  }
}

# --- worktree helpers -------------------------------------------------------

function Get-StoryBranchName([string]$StoryId) {
  "$BranchPrefix$StoryId"
}

function Get-WorktreePath([string]$StoryId) {
  Expand-PathTemplate $PathWorktreesTpl $FeaturePathSlug $StoryId
}

function Get-StoryRunsDir([string]$StoryId) {
  Expand-PathTemplate $PathRunsTpl $FeaturePathSlug $StoryId
}

function Test-WorktreeExists([string]$StoryId) {
  Test-Path -LiteralPath (Join-Root (Get-WorktreePath $StoryId)) -PathType Container
}

function Ensure-Worktree([string]$StoryId) {
  $wt = Get-WorktreePath $StoryId
  $wtFull = Join-Root $wt
  $branch = Get-StoryBranchName $StoryId
  if (Test-WorktreeExists $StoryId) {
    Log "worktree $wt already exists; re-using"
    return
  }
  if (Test-NativeSuccess 'git' @('-C', $AppRepoRoot, 'show-ref', '--verify', '--quiet', "refs/heads/$branch")) {
    & git -C $AppRepoRoot worktree add $wtFull $branch
    if ($LASTEXITCODE -ne 0) {
      Fail "git worktree add $wt $branch failed"
    }
  } else {
    & git -C $AppRepoRoot worktree add $wtFull -b $branch $IntegrationBranch
    if ($LASTEXITCODE -ne 0) {
      Fail "git worktree add $wt -b $branch $IntegrationBranch failed"
    }
  }
}

function Copy-PathToWorktree([string]$Worktree, [string]$RelativePath) {
  $rel = $RelativePath.TrimEnd([char[]]@('/', '\'))
  if (-not $rel) {
    return
  }
  if ($rel -eq '.worktrees' -or $rel.StartsWith('.worktrees/')) {
    Log "skip copy of recursive worktree path: $rel"
    return
  }

  $src = Join-Root $rel
  $dst = Join-Root (Join-Path $Worktree $rel)
  if (-not (Test-Path -LiteralPath $src)) {
    return
  }

  if (Test-Path -LiteralPath $src -PathType Container) {
    New-Item -ItemType Directory -Force -Path $dst | Out-Null
    Get-ChildItem -LiteralPath $src -Force | Copy-Item -Destination $dst -Recurse -Force
  } else {
    New-Item -ItemType Directory -Force -Path (Split-Path $dst -Parent) | Out-Null
    Copy-Item -LiteralPath $src -Destination $dst -Force
  }
}

function Propagate-WorkspaceAssets([string]$StoryId) {
  $wt = Get-WorktreePath $StoryId
  $include = Join-Root '.worktreeinclude'
  if (-not (Test-Path -LiteralPath $include)) {
    Fail "missing $include"
  }
  foreach ($line in Get-Content -LiteralPath $include) {
    $rel = ($line -replace '#.*$', '').Trim()
    if (-not $rel) {
      continue
    }
    Copy-PathToWorktree $wt $rel
  }
}

# Worktree teardown is owned by scripts/windows/cleanup-codex-worktrees.ps1 at end-of-feature.

# --- gate checks ------------------------------------------------------------

function Get-HarnessExcludedPathspec {
  return @(
    '.',
    ':(exclude).codex',
    ':(exclude)AGENTS.md',
    ':(exclude).worktreeinclude',
    ':(exclude)CONTEXT.md',
    ':(exclude)docs',
    ':(exclude)scripts'
  )
}

function Get-CommittablePathspec {
  return @(
    '.',
    ':(exclude).codex',
    ':(exclude)AGENTS.md',
    ':(exclude).worktreeinclude',
    ':(exclude)CONTEXT.md',
    ':(exclude)docs',
    ':(exclude)scripts',
    ':(exclude).pnpm-store',
    ':(exclude).restore-deals.tar',
    ':(exclude)node_modules'
  )
}

function Get-StatusLines([string]$Worktree, [string[]]$Pathspec) {
  $args = @(
    '-C', (Join-Root $Worktree),
    'status', '--porcelain', '--untracked-files=all', '--'
  ) + $Pathspec
  return (To-Lines (Invoke-Text 'git' $args -AllowFailure))
}

function Get-NonHarnessChangeLines([string]$Worktree) {
  Get-StatusLines $Worktree @(Get-HarnessExcludedPathspec)
}

function Get-CommittableChangeLines([string]$Worktree) {
  Get-StatusLines $Worktree @(Get-CommittablePathspec)
}

function Refresh-WorktreeIndex([string]$Worktree) {
  Invoke-NativeQuiet 'git' @(
    '-C', (Join-Root $Worktree),
    'reset', '--mixed', '-q', 'HEAD'
  ) -AllowFailure | Out-Null
}

function Get-StoryCommitCount([string]$Worktree, [string]$StoryId) {
  $branch = Get-StoryBranchName $StoryId
  $count = Invoke-Text 'git' @('-C', (Join-Root $Worktree), 'rev-list', '--count', "$IntegrationBranch..$branch") -AllowFailure
  if (-not $count) {
    return 0
  }
  return [int]$count
}

function Gate-CommitsExist([string]$Worktree, [string]$StoryId) {
  $branch = Get-StoryBranchName $StoryId
  if ((Get-StoryCommitCount $Worktree $StoryId) -lt 1) {
    return "no new commits on $branch since fork from $IntegrationBranch"
  }
  return ''
}

function Gate-CommitMessagesReferenceStory([string]$Worktree, [string]$StoryId) {
  $branch = Get-StoryBranchName $StoryId
  $messages = To-Lines (Invoke-Text 'git' @('-C', (Join-Root $Worktree), 'log', '--format=%s', "$IntegrationBranch..$branch") -AllowFailure)
  foreach ($message in $messages) {
    if (-not $message.Contains($StoryId)) {
      return "commit message does not reference story id '$StoryId': '$message'"
    }
  }
  return ''
}

function Gate-DiffWithinCaps([string]$Worktree, [string]$StoryId) {
  if (Story-HasOverride $StoryId 'large-diff-ok') {
    return ''
  }
  $branch = Get-StoryBranchName $StoryId
  $range = "$IntegrationBranch..$branch"
  $nameArgs = @('-C', (Join-Root $Worktree), 'diff', '--name-only', $range)
  $statArgs = @('-C', (Join-Root $Worktree), 'diff', '--shortstat', $range)
  if ($DiffIgnorePathspec.Count -gt 0) {
    $nameArgs += @('--', '.')
    $nameArgs += $DiffIgnorePathspec
    $statArgs += @('--', '.')
    $statArgs += $DiffIgnorePathspec
  }

  $files = (To-Lines (Invoke-Text 'git' $nameArgs -AllowFailure)).Count
  $shortstat = Invoke-Text 'git' $statArgs -AllowFailure
  $lines = 0
  foreach ($match in [regex]::Matches($shortstat, '(\d+) (insertions|deletions)')) {
    $lines += [int]$match.Groups[1].Value
  }

  if ($files -gt $DiffFileCap) {
    return "diff exceeds file cap: $files > $DiffFileCap (add 'large-diff-ok' override to bypass)"
  }
  if ($lines -gt $DiffLineCap) {
    return "diff exceeds line cap: $lines > $DiffLineCap (add 'large-diff-ok' override to bypass)"
  }
  return ''
}

function Gate-NoHarnessAssetsCommitted([string]$Worktree, [string]$StoryId) {
  $branch = Get-StoryBranchName $StoryId
  $bad = To-Lines (Invoke-Text 'git' @(
    '-C', (Join-Root $Worktree),
    'diff', '--name-only', "$IntegrationBranch..$branch", '--',
    '.codex', 'AGENTS.md', '.worktreeinclude', 'CONTEXT.md', 'docs', 'scripts'
  ) -AllowFailure) | Select-Object -First 1
  if ($bad) {
    return "harness asset committed to application branch: $bad"
  }
  return ''
}

function Gate-RunLogPresent([string]$Worktree, [string]$StoryId, [int]$RunNumber) {
  $runLog = Join-Root (Join-Path (Join-Path $Worktree (Get-StoryRunsDir $StoryId)) "run-$RunNumber.md")
  if (-not (Test-Path -LiteralPath $runLog)) {
    return "run log missing: $(Get-StoryRunsDir $StoryId)/run-$RunNumber.md not written"
  }
  return ''
}

function Gate-WorktreeClean([string]$Worktree) {
  Refresh-WorktreeIndex $Worktree
  $dirty = @(Get-NonHarnessChangeLines $Worktree) | Select-Object -First 1
  if ($dirty) {
    return "worktree has uncommitted changes: '$dirty'"
  }
  return ''
}

function Run-Gates([string]$Worktree, [string]$StoryId, [int]$RunNumber, [int]$CodexExitCode) {
  if ($CodexExitCode -ne 0) {
    return "codex exited rc=$CodexExitCode (likely wall-clock kill or uncaught error)"
  }
  foreach ($reason in @(
    (Gate-CommitsExist $Worktree $StoryId),
    (Gate-CommitMessagesReferenceStory $Worktree $StoryId),
    (Gate-NoHarnessAssetsCommitted $Worktree $StoryId),
    (Gate-DiffWithinCaps $Worktree $StoryId),
    (Gate-RunLogPresent $Worktree $StoryId $RunNumber),
    (Gate-WorktreeClean $Worktree)
  )) {
    if ($reason) {
      return $reason
    }
  }
  return ''
}

function New-CommitOutcome([string]$Status, [string]$Reason) {
  return [pscustomobject]@{
    Status = $Status
    Reason = $Reason
  }
}

function Commit-StoryChanges([string]$Worktree, [string]$StoryId) {
  Refresh-WorktreeIndex $Worktree

  $committable = @(Get-CommittableChangeLines $Worktree)
  if ($committable.Count -eq 0) {
    $nonHarness = @(Get-NonHarnessChangeLines $Worktree)
    if ($nonHarness.Count -gt 0) {
      return (New-CommitOutcome 'failed' "worktree has uncommitted non-harness changes that the runner will not auto-commit: '$($nonHarness[0])'")
    }
    if ((Get-StoryCommitCount $Worktree $StoryId) -gt 0) {
      return (New-CommitOutcome 'existing-commit' '')
    }
    if (Story-IsVerificationOnly $StoryId) {
      return (New-CommitOutcome 'no-code-verification' '')
    }
    return (New-CommitOutcome 'failed' 'no application changes to commit')
  }

  $addArgs = @(
    '-C', (Join-Root $Worktree),
    'add', '--all', '--'
  ) + @(Get-CommittablePathspec)
  if (-not (Invoke-NativeQuiet 'git' $addArgs -AllowFailure)) {
    return (New-CommitOutcome 'failed' 'git add failed while staging application changes')
  }

  if (Test-NativeSuccess 'git' @('-C', (Join-Root $Worktree), 'diff', '--cached', '--quiet')) {
    return (New-CommitOutcome 'failed' 'git add completed but produced no staged application changes')
  }

  $title = Manifest-StoryField $StoryId 'title'
  if (-not $title -or $title -eq 'null') {
    $title = 'implement story'
  }
  $message = "$StoryId - $title"
  if (-not (Invoke-NativeQuiet 'git' @('-C', (Join-Root $Worktree), 'commit', '-m', $message) -AllowFailure)) {
    return (New-CommitOutcome 'failed' 'git commit failed after staging application changes')
  }

  Log "parent commit created for ${StoryId}: $message"
  return (New-CommitOutcome 'committed' '')
}

function Run-NoCodeVerificationGates([string]$Worktree, [string]$StoryId, [int]$RunNumber, [int]$CodexExitCode) {
  if ($CodexExitCode -ne 0) {
    return "codex exited rc=$CodexExitCode (likely wall-clock kill or uncaught error)"
  }
  $reason = Gate-RunLogPresent $Worktree $StoryId $RunNumber
  if ($reason) {
    return $reason
  }
  $dirty = @(Get-NonHarnessChangeLines $Worktree) | Select-Object -First 1
  if ($dirty) {
    return "verification-only story left application changes: '$dirty'"
  }
  return ''
}

# --- spawn prompt + codex ---------------------------------------------------

function Get-NextRunNumber([string]$StoryId) {
  $dir = Join-Root (Join-Path (Get-WorktreePath $StoryId) (Get-StoryRunsDir $StoryId))
  if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
    return 1
  }
  $max = 0
  foreach ($file in Get-ChildItem -LiteralPath $dir -Filter 'run-*' -File -ErrorAction SilentlyContinue) {
    if ($file.Name -match '^run-(\d+)\.') {
      $n = [int]$Matches[1]
      if ($n -gt $max) {
        $max = $n
      }
    }
  }
  return ($max + 1)
}

function Build-SpawnPrompt([string]$StoryId, [int]$RunNumber, [string]$Feedback) {
  $branch = Get-StoryBranchName $StoryId
  $override = if (Story-HasOverride $StoryId 'large-diff-ok') { '1' } else { '0' }
  $runsDir = Get-StoryRunsDir $StoryId

  $prompt = @"
Read and follow the local implementation skill before making changes:

  .codex/skills/implement-story/SKILL.md

You are the Phase 2 implementation agent for story $StoryId under feature
$FeatureSlug. Run #$RunNumber in this worktree.

This worktree is the application repository root. Harness docs and story briefs
may mention paths under `code/` because the main harness checkout keeps the
application repo nested there. Inside this worktree, strip that leading `code/`
prefix. For example, use `Camtrade.Portal/...`, not `code/Camtrade.Portal/...`;
do not `cd code`.

Story branch: $branch
Integration branch: $IntegrationBranch
Diff cap override (large-diff-ok): $override
Diff cap: $DiffFileCap files / $DiffLineCap lines
TDD attempt cap: $TddMaxAttempts

Your spec is on disk at:

  $runsDir/implementation.md

Do not stage, commit, push, open or update any PR, or post any comment. The
harness owns git staging, commits, and every remote-side write after you exit.
Your job is: ground the touch surface, vertical-slice TDD per logical unit,
leave application changes unstaged/uncommitted, write the next run log at
$runsDir/run-$RunNumber.md, then exit.

Do not edit AGENTS.md, .worktreeinclude, CONTEXT.md, docs/ except the named
run log, scripts/, or anything under .codex/. Those files are copied into this
worktree as harness context only.
"@

  if ($Feedback) {
    $prompt += @"

The human left feedback on the PR since the last run-summary. Treat this as a
narrative redirect for this iteration. Default behaviour is
keep-working-from-where-you-left-off.

$Feedback

Also read the prior run logs under $runsDir/ (run-1.md, run-2.md, ...)
before making changes.
"@
  }

  return $prompt
}

function Quote-ProcessArgument([string]$Argument) {
  if ($null -eq $Argument) {
    return '""'
  }
  return '"' + ($Argument -replace '"', '\"') + '"'
}

function Get-PowerShellHostPath {
  $current = (Get-Process -Id $PID).Path
  if ($current) {
    return $current
  }
  $pwsh = Get-Command 'pwsh' -ErrorAction SilentlyContinue
  if ($pwsh) {
    return $pwsh.Source
  }
  $powershell = Get-Command 'powershell.exe' -ErrorAction SilentlyContinue
  if ($powershell) {
    return $powershell.Source
  }
  Fail 'could not locate a PowerShell host for codex process supervision'
}

function New-CodexChildScript {
  $path = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-runner-{0}.ps1" -f ([guid]::NewGuid().ToString('N')))
  $content = @'
param(
  [string]$PromptFile,
  [string]$StreamLog,
  [string]$WorkDir,
  [string]$CodexArgsFile
)

$ErrorActionPreference = 'Continue'
$CodexArgs = @(Get-Content -LiteralPath $CodexArgsFile)
Set-Location -LiteralPath $WorkDir
Set-Content -LiteralPath $StreamLog -Value $null -Encoding UTF8
Get-Content -Raw -LiteralPath $PromptFile | & codex @CodexArgs 2>&1 | ForEach-Object {
  $line = $_.ToString()
  [Console]::Out.WriteLine($line)
  Add-Content -LiteralPath $StreamLog -Value $line -Encoding UTF8
}
$code = $LASTEXITCODE
if ($null -eq $code) {
  exit 1
}
exit $code
'@
  Set-Content -LiteralPath $path -Value $content -Encoding UTF8
  return $path
}

function Spawn-Codex([string]$StoryId, [string]$PromptFile, [int]$RunNumber) {
  $wt = Get-WorktreePath $StoryId
  $wtFull = Join-Root $wt
  $streamLog = Join-Root (Join-Path (Join-Path $wt (Get-StoryRunsDir $StoryId)) "run-$RunNumber.stream.jsonl")
  New-Item -ItemType Directory -Force -Path (Split-Path $streamLog -Parent) | Out-Null
  Log "spawning codex in $wt (run $RunNumber, stream-log: $streamLog)"

  $promptText = Get-Content -Raw -LiteralPath $PromptFile
  $promptBlock = "----- prompt for $StoryId run $RunNumber (begin) -----`n$promptText`n----- prompt for $StoryId run $RunNumber (end) -----"
  [Console]::Error.WriteLine($promptBlock)
  if ($script:RunnerLog) {
    Add-Content -LiteralPath $script:RunnerLog -Value $promptBlock -Encoding UTF8
  }

  $wtGitDir = Resolve-GitDir $wtFull
  $codexArgs = @('--sandbox', $SandboxMode, '--ask-for-approval', $ApprovalPolicy, '-C', $wtFull, '--add-dir', $AppRepoGitCommonDir)
  if ($wtGitDir -ne $AppRepoGitCommonDir) {
    $codexArgs += @('--add-dir', $wtGitDir)
  }
  if ($Model) {
    $codexArgs += @('--model', $Model)
  }
  $codexArgs += @('exec', '--json', '-')
  $childScript = New-CodexChildScript
  $codexArgsFile = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-args-{0}.txt" -f ([guid]::NewGuid().ToString('N')))
  Set-Content -LiteralPath $codexArgsFile -Value $codexArgs -Encoding UTF8

  $psHost = Get-PowerShellHostPath
  $psArgs = @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', $childScript,
    '-PromptFile', $PromptFile,
    '-StreamLog', $streamLog,
    '-WorkDir', $wtFull,
    '-CodexArgsFile', $codexArgsFile
  )
  $argLine = ($psArgs | ForEach-Object { Quote-ProcessArgument $_ }) -join ' '
  $proc = Start-Process -FilePath $psHost -ArgumentList $argLine -WorkingDirectory $wtFull -PassThru -NoNewWindow

  $rc = 0
  try {
    if (-not $proc.WaitForExit($PerStoryWallClock * 1000)) {
      Log "codex exceeded ${PerStoryWallClock}s; killing process tree rooted at pid $($proc.Id)"
      & taskkill.exe /PID $proc.Id /T /F *> $null
      $rc = 124
    } else {
      $proc.Refresh()
      if ($null -eq $proc.ExitCode) {
        $rc = 1
      } else {
        $rc = [int]$proc.ExitCode
      }
    }
  } finally {
    Remove-Item -LiteralPath $childScript -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $codexArgsFile -Force -ErrorAction SilentlyContinue
  }

  Log "codex exited rc=$rc"
  return $rc
}

# --- push + PR + comment ----------------------------------------------------

function Push-Branch([string]$StoryId) {
  $wt = Get-WorktreePath $StoryId
  $branch = Get-StoryBranchName $StoryId
  & git -C (Join-Root $wt) push -u origin $branch
  if ($LASTEXITCODE -ne 0) {
    Log "git push failed for $branch"
    return $false
  }
  return $true
}

function Open-OrUpdatePr([string]$StoryId) {
  $existing = Manifest-StoryField $StoryId 'pr'
  if (Test-PrExists $existing) {
    Log "PR #$existing already open for $StoryId; push updated it"
    return $true
  }

  $branch = Get-StoryBranchName $StoryId
  $title = "${StoryId}: $(Manifest-StoryField $StoryId 'title')"
  $description = Manifest-StoryField $StoryId 'description'
  $preds = To-Lines (Yq-File ('.stories[] | select(.id == "' + $StoryId + '") | .blocked_by[]?') $Manifest -AllowFailure)
  $predsList = if ($preds.Count -gt 0) { $preds -join ', ' } else { 'none' }

  $body = @"
> *Generated by AI during the AISDLC workflow.*

## Summary
- $description

## Linked work
- Story: $StoryId (feature $FeatureSlug, manifest at $Manifest)
- Predecessors merged: $predsList

## Verification
- Per-run details are posted as separate run-summary comments below.
- Test plan: posted on this PR after Phase 3 test-item runs.
"@

  $existing = Find-BbOpenPrForBranch $branch $IntegrationBranch
  if ($existing) {
    Manifest-SetPr $StoryId $existing
    Log "PR #$existing already open for $StoryId; manifest updated"
    return $true
  }

  $payload = [ordered]@{
    title = $title
    description = $body
    state = 'OPEN'
    open = $true
    closed = $false
    fromRef = [ordered]@{
      id = "refs/heads/$branch"
      repository = [ordered]@{
        slug = $BbRepoSlug
        project = [ordered]@{ key = $BbProjectKey }
      }
    }
    toRef = [ordered]@{
      id = "refs/heads/$IntegrationBranch"
      repository = [ordered]@{
        slug = $BbRepoSlug
        project = [ordered]@{ key = $BbProjectKey }
      }
    }
  } | ConvertTo-Json -Depth 10

  try {
    $createOut = Invoke-BitbucketApi 'POST' "$script:BbRestPath/pull-requests" $payload
  } catch {
    Log "Bitbucket PR create failed for ${branch}: $($_.Exception.Message)"
    return $false
  }

  $prNum = Invoke-JqInput @('-r', '.id // empty') $createOut
  if (-not $prNum) {
    Log "Bitbucket PR create did not return a PR id for $branch"
    return $false
  }

  Manifest-SetPr $StoryId $prNum
  Log "PR #$prNum opened for $StoryId"
  return $true
}

function Post-RunSummary([string]$StoryId, [int]$RunNumber) {
  $pr = Manifest-StoryField $StoryId 'pr'
  if (-not (Test-PrExists $pr)) {
    Log "post_run_summary: no PR for $StoryId (pr=$pr)"
    return $false
  }
  $runLog = Join-Root (Join-Path (Join-Path (Get-WorktreePath $StoryId) (Get-StoryRunsDir $StoryId)) "run-$RunNumber.md")
  if (-not (Test-Path -LiteralPath $runLog)) {
    Log "post_run_summary: $runLog missing"
    return $false
  }
  $runText = Get-Content -Raw -LiteralPath $runLog
  $body = "## [Type: $CommentTypeRunSummary | by: scripts/windows/run-codex-loop.ps1 | run $RunNumber]`n`n$runText"
  $payload = @{ text = $body } | ConvertTo-Json -Depth 5
  try {
    Invoke-BitbucketApi 'POST' "$script:BbRestPath/pull-requests/$pr/comments" $payload | Out-Null
    Log "run-summary posted on PR #$pr (run $RunNumber)"
    return $true
  } catch {
    Log "Bitbucket PR comment failed for PR #$pr"
    return $false
  }
}

function Post-DiagnosticsComment([string]$StoryId, [int]$RunNumber, [string]$Reason) {
  $pr = Manifest-StoryField $StoryId 'pr'
  if (-not (Test-PrExists $pr)) {
    return
  }
  $worktree = Get-WorktreePath $StoryId
  $branch = Get-StoryBranchName $StoryId
  $stream = "$(Get-StoryRunsDir $StoryId)/run-$RunNumber.stream.jsonl"
  $body = @"
## [Type: $CommentTypeDiagnostics | by: scripts/windows/run-codex-loop.ps1 | run $RunNumber]

> *Generated by AI during the AISDLC workflow.*

Agent run #$RunNumber for $StoryId did not pass post-agent gates.

- Gate failure: $Reason
- Worktree: $worktree (left intact)
- Branch: $branch (kept; commits, if any, preserved)
- Stream log: $stream

State: agent-dev -> needs-info. Fix the blocker, then either re-tag
ready-for-agent in the manifest, or post a comment here to give it another
pass. The next runner iteration will pick the fresh feedback up.
"@
  $payload = @{ text = $body } | ConvertTo-Json -Depth 5
  try {
    Invoke-BitbucketApi 'POST' "$script:BbRestPath/pull-requests/$pr/comments" $payload | Out-Null
  } catch {
    return
  }
}

# --- iteration body ---------------------------------------------------------

function Ensure-IntegrationPushed {
  if (Test-NativeSuccess 'git' @('-C', $AppRepoRoot, 'ls-remote', '--exit-code', '--heads', 'origin', $IntegrationBranch)) {
    Log "integration branch '$IntegrationBranch' present on origin"
    return
  }
  Log "integration branch '$IntegrationBranch' not on origin; pushing"
  & git -C $AppRepoRoot push -u origin $IntegrationBranch
  if ($LASTEXITCODE -ne 0) {
    Fail "failed to push integration branch '$IntegrationBranch' to origin"
  }
}

function Sync-Remote {
  Log 'sync: git fetch + reconcile pr-open stories'
  Invoke-NativeQuiet 'git' @('-C', $AppRepoRoot, 'fetch', 'origin', $IntegrationBranch) | Out-Null
  Invoke-NativeQuiet 'git' @('-C', $AppRepoRoot, 'pull', '--ff-only', 'origin', $IntegrationBranch) | Out-Null

  foreach ($sid in Get-ManifestStoryIds) {
    $state = Manifest-StateOf $sid
    if ($state -ne 'pr-open') {
      continue
    }
    $pr = Manifest-StoryField $sid 'pr'
    if (-not (Test-PrExists $pr)) {
      continue
    }
    if (Test-PrMerged $pr) {
      Log "PR #$pr merged -> $sid done (worktree retained for end-of-feature cleanup)"
      Manifest-SetState $sid 'done'
    }
  }
}

function Pick-NextStory {
  foreach ($sid in Get-ManifestStoryIds) {
    $state = Manifest-StateOf $sid
    switch ($state) {
      'ready-for-agent' {
        if (Test-ManifestPredecessorsDone $sid) {
          return $sid
        }
      }
      'agent-dev' {
        if (Test-WorktreeExists $sid) {
          return $sid
        }
      }
      'pr-open' {
        if (-not (Test-ManifestPredecessorsDone $sid)) {
          continue
        }
        $pr = Manifest-StoryField $sid 'pr'
        if (-not (Test-PrExists $pr)) {
          continue
        }
        $watermark = Get-PrWatermark $pr
        $bundle = Get-PrHumanFeedbackBundle $pr $watermark
        if ($bundle) {
          return $sid
        }
      }
    }
  }
  return ''
}

function Report-ExitReason {
  $blockedCount = 0
  $needsInfoCount = 0
  $prOpenCount = 0
  $firstBlockerId = ''
  $firstBlockerPred = ''

  foreach ($sid in Get-ManifestStoryIds) {
    $state = Manifest-StateOf $sid
    switch ($state) {
      'ready-for-agent' {
        if (-not (Test-ManifestPredecessorsDone $sid)) {
          $blockedCount++
          if (-not $firstBlockerId) {
            $firstBlockerId = $sid
            $firstBlockerPred = Get-ManifestFirstUndonePredecessor $sid
            if (-not $firstBlockerPred) {
              $firstBlockerPred = '?'
            }
          }
        }
      }
      'needs-info' { $needsInfoCount++ }
      'pr-open' { $prOpenCount++ }
    }
  }

  $script:PrOpenRemaining = $prOpenCount
  Log "exit summary: pr-open=$prOpenCount needs-info=$needsInfoCount blocked=$blockedCount"
  if ($prOpenCount -gt 0) {
    Log "  -> $prOpenCount story PR(s) awaiting human review/merge"
  }
  if ($firstBlockerId) {
    Log "  -> next eligible: $firstBlockerId (blocked on $firstBlockerPred)"
  }
  if ($needsInfoCount -gt 0) {
    Log "  -> $needsInfoCount story/stories in needs-info; see runner.log for details"
  }
}

function Run-OneIteration {
  Sync-Remote

  $sid = Pick-NextStory
  if (-not $sid) {
    return $false
  }
  Log "==> picking $sid (current state: $(Manifest-StateOf $sid))"

  $implementation = Join-Root (Join-Path (Get-StoryRunsDir $sid) 'implementation.md')
  if (-not (Test-Path -LiteralPath $implementation)) {
    Log "brief audit failed: $(Get-StoryRunsDir $sid)/implementation.md missing"
    Manifest-SetState $sid 'needs-info'
    return $true
  }

  $priorState = Manifest-StateOf $sid
  if ($priorState -ne 'agent-dev') {
    Manifest-SetState $sid 'agent-dev'
  }

  Ensure-Worktree $sid
  Propagate-WorkspaceAssets $sid

  $runNumber = Get-NextRunNumber $sid
  $feedback = ''
  if ($priorState -eq 'pr-open') {
    $pr = Manifest-StoryField $sid 'pr'
    $watermark = Get-PrWatermark $pr
    $feedback = Get-PrHumanFeedbackBundle $pr $watermark
  }

  $promptFile = [System.IO.Path]::GetTempFileName()
  try {
    Set-Content -LiteralPath $promptFile -Value (Build-SpawnPrompt $sid $runNumber $feedback) -Encoding UTF8
    $rc = Spawn-Codex $sid $promptFile $runNumber
  } finally {
    Remove-Item -LiteralPath $promptFile -Force -ErrorAction SilentlyContinue
  }

  $wt = Get-WorktreePath $sid
  if ($rc -ne 0) {
    $reason = Run-Gates $wt $sid $runNumber $rc
    Log "gate failure for ${sid}: $reason"
    if ($priorState -eq 'pr-open') {
      Post-DiagnosticsComment $sid $runNumber $reason
    }
    Manifest-SetState $sid 'needs-info'
    return $true
  }

  $commitOutcome = Commit-StoryChanges $wt $sid
  if ($commitOutcome.Status -eq 'failed') {
    Log "gate failure for ${sid}: $($commitOutcome.Reason)"
    if ($priorState -eq 'pr-open') {
      Post-DiagnosticsComment $sid $runNumber $commitOutcome.Reason
    }
    Manifest-SetState $sid 'needs-info'
    return $true
  }

  if ($commitOutcome.Status -eq 'no-code-verification') {
    $reason = Run-NoCodeVerificationGates $wt $sid $runNumber $rc
    if ($reason) {
      Log "gate failure for ${sid}: $reason"
      if ($priorState -eq 'pr-open') {
        Post-DiagnosticsComment $sid $runNumber $reason
      }
      Manifest-SetState $sid 'needs-info'
      return $true
    }

    Manifest-SetState $sid 'done'
    Log "==> $sid done (verification-only no-code run $runNumber; no PR opened)"
    return $true
  }

  $reason = Run-Gates $wt $sid $runNumber $rc
  if ($reason) {
    Log "gate failure for ${sid}: $reason"
    if ($priorState -eq 'pr-open') {
      Post-DiagnosticsComment $sid $runNumber $reason
    }
    Manifest-SetState $sid 'needs-info'
    return $true
  }

  if (-not (Push-Branch $sid)) {
    Manifest-SetState $sid 'needs-info'
    return $true
  }
  if (-not (Open-OrUpdatePr $sid)) {
    Manifest-SetState $sid 'needs-info'
    return $true
  }

  Post-RunSummary $sid $runNumber | Out-Null
  Manifest-SetState $sid 'pr-open'
  Log "==> $sid pr-open (run $runNumber complete)"
  return $true
}

function Main-Loop {
  Ensure-IntegrationPushed
  while ($true) {
    if (Run-OneIteration) {
      continue
    }
    Report-ExitReason
    if ($WatchInterval -eq 0) {
      Log 'no eligible work; single-shot exit'
      break
    }
    if ($script:PrOpenRemaining -eq 0) {
      Log 'no eligible work and no open PRs; nothing left for --watch to advance; exiting'
      break
    }
    Log "no eligible work; sleeping ${WatchInterval}s (--watch); $script:PrOpenRemaining open PR(s) may still merge"
    Start-Sleep -Seconds $WatchInterval
  }
}

try {
  Main-Loop
  Log "runner exiting; feature=$FeatureSlug"
} finally {
  Remove-Item -LiteralPath $LockFile -Force -ErrorAction SilentlyContinue
}

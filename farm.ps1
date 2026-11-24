<#
  GitHub contribution farmer (Windows / PowerShell)
  Makes backdated commits in a separate repo so your contribution graph fills up.

  Run with no arguments for a guided setup:
    .\farm.ps1

  Or pass options:
    .\farm.ps1 -Total 5000 -Push                          # exactly 5000 contributions over the last year
    .\farm.ps1 -Total 800 -From 2025-01-01 -To 2025-12-31 # exactly 800 in 2025
    .\farm.ps1 -Days 180 -MaxPerDay 10 -SkipWeekends -Push
    .\farm.ps1 -RemoteUrl https://github.com/you/my-contrib-farm.git -Push
#>
param(
    [string]$RepoPath = (Join-Path $HOME "my-contrib-farm"),
    [int]$Total = 0,               # exact number of contributions; 0 = random amount using Min/MaxPerDay
    [int]$Days = 365,              # how far back to start (ignored when -From is given)
    [string]$From,                 # start date, yyyy-MM-dd
    [string]$To,                   # end date, yyyy-MM-dd (default: today)
    [int]$MinPerDay = 1,           # min commits on an active day (when -Total is 0)
    [int]$MaxPerDay = 8,           # max commits on an active day (when -Total is 0)
    [int]$SkipChance = 20,         # % chance a day gets zero commits
    [int]$BusyDays = 0,            # how many days get a lot of contributions
    [int]$BusyMin = 30,            # min contributions on a busy day
    [int]$BusyMax = 50,            # max contributions on a busy day
    [switch]$SkipWeekends,
    [int]$StartHour = 9,           # earliest hour of the day for commits (0-23)
    [int]$EndHour = 23,            # latest hour of the day for commits (0-23)
    [string]$Message = "update",   # commit message (the timestamp is added after it)
    [string]$RemoteUrl,            # GitHub repo URL; leave empty to auto-create one with the GitHub CLI
    [string]$RepoName = "my-contrib-farm",
    [switch]$Public,               # make the auto-created repo public (default private)
    [switch]$Push,                 # push to GitHub when done
    [int]$BatchSize = 500          # commits per push; GitHub skips commits beyond ~1000 in one push
)

$ErrorActionPreference = "Stop"

function Ask([string]$q, [string]$default) {
    $a = Read-Host "$q [$default]"
    if ([string]::IsNullOrWhiteSpace($a)) { return $default } else { return $a.Trim() }
}
function AskYes([string]$q, [bool]$default) {
    $d = if ($default) { "Y/n" } else { "y/N" }
    $a = Read-Host "$q [$d]"
    if ([string]::IsNullOrWhiteSpace($a)) { return $default }
    return $a.Trim().ToLower().StartsWith("y")
}
function ParseDate([string]$s, [string]$what) {
    try { return [datetime]::ParseExact($s.Trim(), "yyyy-MM-dd", [Globalization.CultureInfo]::InvariantCulture) }
    catch { throw "$what '$s' is not a date like 2025-01-31." }
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "git is not installed or not on PATH. Get it at https://git-scm.com" }
$hasGh = [bool](Get-Command gh -ErrorAction SilentlyContinue)
$today = (Get-Date).Date

# ---------- guided mode when started with no arguments ----------
if ($PSBoundParameters.Count -eq 0) {
    Write-Host ""
    Write-Host "=== GitHub contribution farmer ===" -ForegroundColor Cyan
    Write-Host "Press Enter to accept the default in brackets."
    Write-Host ""
    $t = Ask "How many contributions do you want? (number, or 'random')" "random"
    if ($t -match '^\d+$') { $Total = [int]$t }
    $From = Ask "Start date (yyyy-MM-dd)" $today.AddDays(-365).ToString("yyyy-MM-dd")
    $To   = Ask "End date (yyyy-MM-dd)" $today.ToString("yyyy-MM-dd")
    if ($Total -eq 0) {
        $MinPerDay = [int](Ask "Min commits on an active day?" "1")
        $MaxPerDay = [int](Ask "Max commits on an active day?" "8")
    }
    $BusyDays     = [int](Ask "How many days should be extra busy (lots of contributions)?" "0")
    if ($BusyDays -gt 0) {
        $BusyMin  = [int](Ask "Min contributions on a busy day?" "30")
        $BusyMax  = [int](Ask "Max contributions on a busy day?" "50")
    }
    $SkipChance   = [int](Ask "Chance (%) a day is left empty?" "20")
    $SkipWeekends = [switch](AskYes "Skip weekends?" $false)
    $StartHour    = [int](Ask "Earliest hour for commits (0-23)?" "9")
    $EndHour      = [int](Ask "Latest hour for commits (0-23)?" "23")
    $Message      = Ask "Commit message?" "update"
    $RepoPath     = Ask "Local folder for the farm repo?" $RepoPath
    if (AskYes "Push to GitHub when done?" $true) {
        $Push = [switch]$true
        if ($hasGh) {
            $RemoteUrl = Ask "GitHub repo URL (leave empty to create '$RepoName' automatically)" ""
        } else {
            $RemoteUrl = Ask "GitHub repo URL (create an empty repo on github.com first)" ""
        }
    }
}

# ---------- validate ----------
if ($MinPerDay -lt 0 -or $MinPerDay -gt $MaxPerDay) { throw "MinPerDay must be between 0 and MaxPerDay." }
if ($Total -lt 0) { throw "Total cannot be negative." }
if ($SkipChance -lt 0 -or $SkipChance -gt 100) { throw "SkipChance must be 0-100." }
if ($BusyDays -lt 0 -or $BusyMin -lt 0 -or $BusyMin -gt $BusyMax) { throw "BusyDays must be 0 or more, and BusyMin <= BusyMax." }
if ($StartHour -lt 0 -or $EndHour -gt 23 -or $StartHour -gt $EndHour) { throw "Hours must be 0-23 and StartHour <= EndHour." }
if ([string]::IsNullOrWhiteSpace($Message)) { $Message = "update" }

$endDate   = if ($To)   { ParseDate $To "End date" }     else { $today }
if ($endDate -gt $today) { $endDate = $today }
$startDate = if ($From) { ParseDate $From "Start date" } else { $endDate.AddDays(-$Days) }
if ($startDate -gt $endDate) { throw "Start date is after end date." }

# ---------- plan: which days get how many commits ----------
$active = New-Object System.Collections.Generic.List[datetime]
for ($d = $startDate; $d -le $endDate; $d = $d.AddDays(1)) {
    if ($SkipWeekends -and ($d.DayOfWeek -eq 'Saturday' -or $d.DayOfWeek -eq 'Sunday')) { continue }
    if ((Get-Random -Minimum 0 -Maximum 100) -lt $SkipChance) { continue }
    $active.Add($d)
}
if ($active.Count -eq 0) { throw "No days left to commit on. Lower the skip chance, turn off skip weekends, or widen the dates." }

$counts = New-Object int[] $active.Count
$isBusy = New-Object bool[] $active.Count

# busy days first: random days that get BusyMin..BusyMax contributions
$busyN = [math]::Min($BusyDays, $active.Count)
if ($busyN -gt 0) {
    foreach ($i in (0..($active.Count - 1) | Get-Random -Count $busyN)) {
        $isBusy[$i] = $true
        $counts[$i] = Get-Random -Minimum $BusyMin -Maximum ($BusyMax + 1)
    }
}
$busySum = ($counts | Measure-Object -Sum).Sum
$normal = @(0..($active.Count - 1) | Where-Object { -not $isBusy[$_] })

if ($Total -gt 0) {
    # exact total: the busy days take their share, the rest is spread over the other days with random weights
    $rest = $Total - $busySum
    if ($rest -lt 0) { throw "The $busyN busy days alone make $busySum contributions, more than your total of $Total. Lower BusyDays/BusyMin or raise Total." }
    $pool = if ($normal.Count -gt 0) { $normal } else { @(0..($active.Count - 1)) }
    $weights = @{}; $sumW = 0
    foreach ($i in $pool) { $weights[$i] = Get-Random -Minimum 1 -Maximum 11; $sumW += $weights[$i] }
    $given = 0
    foreach ($i in $pool) { $n = [math]::Floor($rest * $weights[$i] / $sumW); $counts[$i] += $n; $given += $n }
    for ($r = $given; $r -lt $rest; $r++) { $counts[$pool[(Get-Random -Maximum $pool.Count)]]++ }
} else {
    foreach ($i in $normal) { $counts[$i] = Get-Random -Minimum $MinPerDay -Maximum ($MaxPerDay + 1) }
}
$planned = ($counts | Measure-Object -Sum).Sum
$busiest = ($counts | Measure-Object -Maximum).Maximum

Write-Host ""
Write-Host ("Plan: {0} contributions from {1} to {2}, on {3} days (busiest day: {4})" -f `
    $planned, $startDate.ToString("yyyy-MM-dd"), $endDate.ToString("yyyy-MM-dd"), $active.Count, $busiest) -ForegroundColor Cyan
if ($busyN -gt 0) {
    $over = @($counts | Where-Object { $_ -ge $BusyMin }).Count
    Write-Host ("      {0} busy days with {1}-{2} each ({3} days in total have {1}+)" -f $busyN, $BusyMin, $BusyMax, $over) -ForegroundColor Cyan
}
if ($PSBoundParameters.Count -eq 0 -and -not (AskYes "Go?" $true)) { return }
if ($planned -eq 0) { Write-Host "Nothing to do."; return }

# ---------- set up the repo ----------
if (-not (Test-Path $RepoPath)) { New-Item -ItemType Directory -Path $RepoPath | Out-Null }
$RepoPath = (Resolve-Path $RepoPath).Path
Push-Location $RepoPath
try {
    $newRepo = -not (Test-Path ".git")
    if ($newRepo) {
        git init -q
        git checkout -q -b main
        git config core.autocrlf false
    }
    if (git status --porcelain) { throw "$RepoPath has uncommitted changes. Commit or remove them first." }

    $name  = git config user.name
    $email = git config user.email
    if (-not $email) { throw "git user.email is not set. Run: git config --global user.email you@example.com" }
    if (-not $name)  { throw "git user.name is not set. Run: git config --global user.name `"Your Name`"" }
    Write-Host "Committing as $email (must match an email on your GitHub account)" -ForegroundColor Cyan

    $branch = git symbolic-ref --short HEAD

    # ---------- connect to GitHub first, so new commits go on top of what's already there ----------
    $created = $false
    if ($RemoteUrl) {
        if ((git remote) -contains "origin") { git remote set-url origin $RemoteUrl } else { git remote add origin $RemoteUrl }
    }
    $hasRemoteBranch = $false
    if ($Push) {
        if (-not ((git remote) -contains "origin")) {
            if (-not $hasGh) { throw "No remote set. Pass -RemoteUrl <url>, or install the GitHub CLI (https://cli.github.com) to create the repo automatically." }
            $vis = if ($Public) { "--public" } else { "--private" }
            $url = gh repo create $RepoName $vis
            if ($LASTEXITCODE -ne 0) { throw "Creating the GitHub repo failed (see above)." }
            git remote add origin ("$url".Trim())
            $created = $true
        }
        git fetch -q origin
        if ($LASTEXITCODE -ne 0) { throw "Could not reach the GitHub repo (see above)." }
        git rev-parse -q --verify "refs/remotes/origin/$branch" *> $null
        $hasRemoteBranch = ($LASTEXITCODE -eq 0)
        if ($hasRemoteBranch) {
            git rev-parse -q --verify HEAD *> $null
            if ($LASTEXITCODE -ne 0) {
                git reset -q --hard "origin/$branch"      # empty local repo: start from what's on GitHub
                $newRepo = $false
            } else {
                git merge-base --is-ancestor "origin/$branch" HEAD
                if ($LASTEXITCODE -ne 0) {
                    # GitHub has commits we don't (e.g. a README/LICENSE made on github.com). Merge them in;
                    # never rebase, that would reset every commit date to today.
                    Write-Host "GitHub repo has commits you don't have locally, merging them in..." -ForegroundColor Yellow
                    git merge "origin/$branch" --allow-unrelated-histories --no-edit -q -X ours
                    if ($LASTEXITCODE -ne 0) { throw "Merge failed. Resolve it in $RepoPath and run again." }
                }
            }
        }
    }

    git rev-parse -q --verify HEAD *> $null
    $hasHead = ($LASTEXITCODE -eq 0)

    # Build one git fast-import stream: thousands of commits in seconds instead of minutes
    $utf8 = New-Object System.Text.UTF8Encoding $false
    $sb = New-Object System.Text.StringBuilder
    $now = Get-Date
    $first = $true
    $lo = $StartHour * 3600; $hi = $EndHour * 3600 + 3599

    for ($i = 0; $i -lt $active.Count; $i++) {
        if ($counts[$i] -eq 0) { continue }
        $day = $active[$i]
        $times = 1..$counts[$i] | ForEach-Object {
            $t = $day.AddSeconds((Get-Random -Minimum $lo -Maximum ($hi + 1)))
            if ($t -gt $now) { $t = $now.AddSeconds(-(Get-Random -Minimum 1 -Maximum 600)); if ($t -lt $day) { $t = $day } }
            $t
        } | Sort-Object

        foreach ($t in $times) {
            $dto   = [DateTimeOffset]$t
            $off   = $dto.Offset
            $tz    = "{0}{1:00}{2:00}" -f $(if ($off -lt 0) { "-" } else { "+" }), [math]::Abs($off.Hours), [math]::Abs($off.Minutes)
            $epoch = $dto.ToUnixTimeSeconds()
            $stamp = $t.ToString("yyyy-MM-ddTHH:mm:ss")
            $msg   = "$Message $stamp"
            $who   = "$name <$email> $epoch $tz"

            [void]$sb.Append("commit refs/heads/$branch`n")
            [void]$sb.Append("author $who`ncommitter $who`n")
            [void]$sb.Append("data $($utf8.GetByteCount($msg))`n$msg`n")
            if ($first) {
                if ($hasHead) { [void]$sb.Append("from refs/heads/$branch^0`n") }
                if ($newRepo) { $readme = "# my-contrib-farm`n"; [void]$sb.Append("M 100644 inline README.md`ndata $($utf8.GetByteCount($readme))`n$readme`n") }
                $first = $false
            }
            [void]$sb.Append("M 100644 inline activity.log`ndata $($stamp.Length + 1)`n$stamp`n`n")
        }
        Write-Progress -Activity "Building commits" -Status $day.ToString("yyyy-MM-dd") -PercentComplete (($i + 1) * 100 / $active.Count)
    }
    Write-Progress -Activity "Building commits" -Completed

    $stream = Join-Path ([IO.Path]::GetTempPath()) ("farm-" + [guid]::NewGuid().ToString("N") + ".txt")
    [IO.File]::WriteAllText($stream, $sb.ToString(), $utf8)
    Write-Host "Writing $planned commits..."
    cmd /c "git fast-import --quiet < `"$stream`""
    $ok = ($LASTEXITCODE -eq 0)
    Remove-Item $stream -ErrorAction SilentlyContinue
    if (-not $ok) { throw "git fast-import failed (see above)." }
    git reset -q --hard
    Write-Host "Done: $planned commits in $RepoPath" -ForegroundColor Green

    # ---------- push ----------
    if ($Push) {
        # GitHub only counts roughly the newest 1000 commits of a single push, so push oldest first in batches.
        $range = if ($hasRemoteBranch) { "origin/$branch..HEAD" } else { "HEAD" }
        $shas = @(git rev-list --reverse --first-parent $range)
        if ($BatchSize -lt 1) { $BatchSize = 500 }
        for ($k = $BatchSize - 1; $k -lt $shas.Count - 1; $k += $BatchSize) {
            $sha = $shas[$k]
            if ($hasRemoteBranch) {
                git merge-base --is-ancestor "origin/$branch" $sha
                if ($LASTEXITCODE -ne 0) { continue }   # would not be a fast-forward yet
            }
            Write-Host ("Pushing {0} / {1}..." -f ($k + 1), $shas.Count)
            git push -q origin "${sha}:refs/heads/$branch"
            if ($LASTEXITCODE -ne 0) { throw "Push failed (see above)." }
        }
        Write-Host ("Pushing {0} / {0}..." -f $shas.Count)
        git push -q -u origin $branch
        if ($LASTEXITCODE -ne 0) { throw "Push failed (see above)." }
        Write-Host "Pushed. The graph can take a few minutes to update." -ForegroundColor Green
        if (-not $Public -and $created) {
            Write-Host "The repo is private: turn on 'Private contributions' on your GitHub profile so the commits show." -ForegroundColor Yellow
        }
    } else {
        Write-Host "Not pushed. Run again with -Push (and -RemoteUrl <url> if you don't have the GitHub CLI)." -ForegroundColor Yellow
    }
}
finally {
    Pop-Location
}

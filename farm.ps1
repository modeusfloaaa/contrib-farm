<#
  GitHub contribution farmer (Windows / PowerShell)
  Makes backdated commits in a separate repo so your contribution graph fills up.

  Run with no arguments for a guided setup:
    .\farm.ps1

  Or pass options:
    .\farm.ps1 -Days 180 -MaxPerDay 10 -SkipWeekends -Push
    .\farm.ps1 -RemoteUrl https://github.com/you/my-contrib-farm.git -Push
#>
param(
    [string]$RepoPath = (Join-Path $HOME "my-contrib-farm"),
    [int]$Days = 365,              # how far back to start
    [int]$MinPerDay = 1,           # min commits on an active day
    [int]$MaxPerDay = 8,           # max commits on an active day
    [int]$SkipChance = 20,         # % chance a day gets zero commits
    [switch]$SkipWeekends,
    [string]$RemoteUrl,            # GitHub repo URL; leave empty to auto-create one with the GitHub CLI
    [string]$RepoName = "my-contrib-farm",
    [switch]$Public,               # make the auto-created repo public (default private)
    [switch]$Push                  # push to GitHub when done
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

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "git is not installed or not on PATH. Get it at https://git-scm.com" }
$hasGh = [bool](Get-Command gh -ErrorAction SilentlyContinue)

# Guided mode when started with no arguments
if ($PSBoundParameters.Count -eq 0) {
    Write-Host ""
    Write-Host "=== GitHub contribution farmer ===" -ForegroundColor Cyan
    Write-Host "Press Enter to accept the default in brackets."
    Write-Host ""
    $Days        = [int](Ask "How many days back?" "365")
    $MinPerDay   = [int](Ask "Min commits on an active day?" "1")
    $MaxPerDay   = [int](Ask "Max commits on an active day?" "8")
    $SkipChance  = [int](Ask "Chance (%) a day is left empty?" "20")
    $SkipWeekends = [switch](AskYes "Skip weekends?" $false)
    $RepoPath    = Ask "Local folder for the farm repo?" $RepoPath
    if (AskYes "Push to GitHub when done?" $true) {
        $Push = [switch]$true
        if ($hasGh) {
            $RemoteUrl = Ask "GitHub repo URL (leave empty to create '$RepoName' automatically)" ""
        } else {
            $RemoteUrl = Ask "GitHub repo URL (create an empty repo on github.com first)" ""
        }
    }
    $est = [math]::Round(($Days + 1) * (100 - $SkipChance) / 100 * ($MinPerDay + $MaxPerDay) / 2 * ($(if ($SkipWeekends) { 5 / 7 } else { 1 })))
    Write-Host ""
    Write-Host "This will make roughly $est commits." -ForegroundColor Cyan
    if (-not (AskYes "Go?" $true)) { return }
}

if ($MinPerDay -gt $MaxPerDay) { throw "MinPerDay cannot be larger than MaxPerDay." }

# Set up the repo
if (-not (Test-Path $RepoPath)) { New-Item -ItemType Directory -Path $RepoPath | Out-Null }
$RepoPath = (Resolve-Path $RepoPath).Path
Push-Location $RepoPath
try {
    if (-not (Test-Path ".git")) {
        git init -q
        git checkout -q -b main
        git config core.autocrlf false
        "# contrib-farm`n" | Out-File -Encoding utf8 README.md
    }

    $email = git config user.email
    if (-not $email) { throw "git user.email is not set. Run: git config --global user.email you@example.com" }
    Write-Host "Committing as $email (must match an email on your GitHub account)" -ForegroundColor Cyan

    $start = (Get-Date).Date.AddDays(-$Days)
    $now = Get-Date
    $total = 0

    for ($i = 0; $i -le $Days; $i++) {
        $day = $start.AddDays($i)
        if ($SkipWeekends -and ($day.DayOfWeek -eq 'Saturday' -or $day.DayOfWeek -eq 'Sunday')) { continue }
        if ((Get-Random -Minimum 0 -Maximum 100) -lt $SkipChance) { continue }

        $count = Get-Random -Minimum $MinPerDay -Maximum ($MaxPerDay + 1)
        $times = 1..$count | ForEach-Object { $day.AddSeconds((Get-Random -Minimum 32400 -Maximum 84600)) } | Sort-Object

        foreach ($t in $times) {
            if ($t -gt $now) { continue }   # never commit in the future
            $stamp = $t.ToString("yyyy-MM-ddTHH:mm:ss")
            Add-Content -Path "activity.log" -Value $stamp
            $env:GIT_AUTHOR_DATE = $stamp
            $env:GIT_COMMITTER_DATE = $stamp
            git add -A
            git commit -q -m "update $stamp"
            $total++
        }
        Write-Progress -Activity "Farming contributions" -Status $day.ToString("yyyy-MM-dd") -PercentComplete (($i / [math]::Max($Days, 1)) * 100)
    }
    Remove-Item Env:GIT_AUTHOR_DATE, Env:GIT_COMMITTER_DATE -ErrorAction SilentlyContinue
    Write-Progress -Activity "Farming contributions" -Completed
    Write-Host "Done: $total commits over $Days days in $RepoPath" -ForegroundColor Green

    $hasOrigin = (git remote) -contains "origin"
    if ($RemoteUrl) {
        if ($hasOrigin) { git remote set-url origin $RemoteUrl } else { git remote add origin $RemoteUrl }
        $hasOrigin = $true
    }

    if ($Push) {
        if (-not $hasOrigin) {
            if (-not $hasGh) { throw "No remote set. Pass -RemoteUrl <url>, or install the GitHub CLI (https://cli.github.com) to create the repo automatically." }
            $vis = if ($Public) { "--public" } else { "--private" }
            gh repo create $RepoName $vis --source . --remote origin --push
            if ($LASTEXITCODE -ne 0) { throw "Creating the GitHub repo failed (see above)." }
        } else {
            git push -u origin main
            if ($LASTEXITCODE -ne 0) {
                # The GitHub repo already has commits (e.g. a README/LICENSE made on github.com).
                # Merge them in; never rebase, that would reset every commit date to today.
                Write-Host "GitHub repo has commits you don't have locally, merging them in..." -ForegroundColor Yellow
                git fetch -q origin
                git merge origin/main --allow-unrelated-histories --no-edit -q -X ours
                if ($LASTEXITCODE -ne 0) { throw "Merge failed. Resolve it in $RepoPath, then run: git push -u origin main" }
                git push -u origin main
                if ($LASTEXITCODE -ne 0) { throw "Push failed (see above)." }
            }
        }
        Write-Host "Pushed. The graph can take a few minutes to update." -ForegroundColor Green
        if (-not $Public -and -not $RemoteUrl) {
            Write-Host "The repo is private: turn on 'Private contributions' on your GitHub profile so the commits show." -ForegroundColor Yellow
        }
    } else {
        Write-Host "Not pushed. Run again with -Push (and -RemoteUrl <url> if you don't have the GitHub CLI)." -ForegroundColor Yellow
    }
}
finally {
    Pop-Location
}

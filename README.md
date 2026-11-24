# contrib-farm

Fill your GitHub contribution graph with backdated commits. Works on Windows, macOS and Linux.

## Quick start

**Windows:** download this repo (green **Code** button, then **Download ZIP**), unzip it, and double-click **`farm.bat`**.

**macOS / Linux:**
```bash
git clone https://github.com/modeusfloaaa/contrib-farm.git
cd contrib-farm
chmod +x farm.sh
./farm.sh
```

The script asks how many contributions you want, which dates, which hours and so on (press Enter to accept the defaults), shows the plan, then does the rest. Even tens of thousands of commits only take seconds.

If you have the [GitHub CLI](https://cli.github.com) installed and logged in (`gh auth login`), it creates the GitHub repo and pushes for you. Otherwise, create an **empty** repo on github.com first and paste its URL when the script asks.

## Requirements

- [git](https://git-scm.com)
- Your git email must match an email on your GitHub account, or the commits won't count:
  ```bash
  git config --global user.email "you@example.com"
  ```
  Your GitHub noreply address works too (Settings, Emails).

## How it works

GitHub puts each commit on the graph by the date stored **in the commit**, not the date you pushed it. Git lets you set that date with `GIT_AUTHOR_DATE` and `GIT_COMMITTER_DATE`.

The script:
1. Goes through every day in your date range and leaves some days empty (weekends if you want, plus a random skip chance) so the graph has natural gaps.
2. Decides how many commits each remaining day gets: either your exact total spread randomly over the days, or a random number between min and max per day.
3. Gives each commit a random time inside your hours and writes them all at once with `git fast-import`, so it's fast.

All commits go into a **separate repo** (default `~/my-contrib-farm`), never into this one.

## How many contributions?

**Pick an exact number** with `-Total` / `--total` (or answer the first question in guided mode). That's exactly how many you get.

**Or leave it random.** Then it's roughly `days × (1 - skip%) × (min + max) / 2`:

| Settings | Expected commits |
|---|---|
| Defaults (365 days, 1 to 8 per day, 20% skip) | ~1,300 |
| Defaults + skip weekends | ~940 |
| `min 5, max 15, skip 0` | ~3,700 |
| `max 4, skip 35, skip weekends` (subtle) | ~340 |

Running it again on the same repo **adds** commits on top of the existing ones.

**Busy days:** the graph's colors are relative to your busiest day. If you have one real day with 30+ contributions, everything else looks pale next to it. Use `-BusyDays` / `--busy-days` to give a number of random days 30 to 50 contributions each (change the range with the busy min/max options). With an exact total, the busy days are part of that total.

**Why it pushes in batches:** GitHub only counts roughly the newest 1,000 commits of a single push and silently skips the older ones, so months at the start of your range would stay empty. The script pushes oldest first, 500 commits at a time, so all of them count.

## Options

| PowerShell (`farm.ps1`) | Bash (`farm.sh`) | Default | What it does |
|---|---|---|---|
| `-Total` | `--total` | random | Exact number of contributions |
| `-From` | `--from` | 1 year ago | Start date (`2025-01-31`) |
| `-To` | `--to` | today | End date |
| `-Days` | `--days` | 365 | How many days back to start (if no start date) |
| `-MinPerDay` | `--min` | 1 | Min commits on an active day (random mode) |
| `-MaxPerDay` | `--max` | 8 | Max commits on an active day (random mode) |
| `-BusyDays` | `--busy-days` | 0 | How many days get a lot of contributions |
| `-BusyMin` | `--busy-min` | 30 | Min contributions on a busy day |
| `-BusyMax` | `--busy-max` | 50 | Max contributions on a busy day |
| `-SkipChance` | `--skip` | 20 | % chance a day is left empty |
| `-SkipWeekends` | `--skip-weekends` | off | No commits on weekends |
| `-StartHour` | `--start-hour` | 9 | Earliest hour for commits (0-23) |
| `-EndHour` | `--end-hour` | 23 | Latest hour for commits (0-23) |
| `-Message` | `--message` | update | Commit message (timestamp added after it) |
| `-RepoPath` | `--path` | `~/my-contrib-farm` | Local folder for the farm repo |
| `-RemoteUrl` | `--remote` | | GitHub repo URL to push to |
| `-RepoName` | `--name` | my-contrib-farm | Name for the auto-created repo |
| `-Public` | `--public` | private | Make the auto-created repo public |
| `-Push` | `--push` | off | Push to GitHub when done |
| `-BatchSize` | `--batch` | 500 | Commits per push (see below) |

Examples:
```powershell
.\farm.ps1 -Total 5000 -Push                                  # exactly 5000 over the last year
.\farm.ps1 -Total 800 -From 2025-01-01 -To 2025-12-31 -Push   # exactly 800 in 2025
.\farm.ps1 -Total 300 -SkipWeekends -StartHour 9 -EndHour 17  # office hours only
.\farm.ps1 -Total 5000 -BusyDays 25 -Push                     # 25 days with 30-50 each
.\farm.ps1 -Days 180 -MaxPerDay 10 -SkipWeekends -Push        # random amount, last 6 months
```
```bash
./farm.sh --total 5000 --push
./farm.sh --total 800 --from 2025-01-01 --to 2025-12-31 --push
./farm.sh --total 300 --skip-weekends --start-hour 9 --end-hour 17
./farm.sh --total 5000 --busy-days 25 --push
./farm.sh --days 180 --max 10 --skip-weekends --push
```

## Commits not showing up?

- The email in the commits must be verified on your GitHub account.
- Commits must be on the repo's **default branch** (the script uses `main`).
- The repo can't be a fork.
- Private repo? Turn on **Private contributions** on your profile (click "Contribution settings" above the graph).
- Give GitHub a few minutes to update the graph.
- Pushed thousands of commits at once with an older version (or by hand)? GitHub only counted the newest ~1,000 of that push and won't count the rest later. Run the script again for the empty period, it pushes in batches.

## Undo

Delete the farm repo on GitHub (Settings, Danger zone, Delete). The contributions disappear from your graph.

## Disclaimer

This is a toy. The commits are filler, and anyone who opens the repo can see that. Use it for fun, not to mislead people.

## License

MIT

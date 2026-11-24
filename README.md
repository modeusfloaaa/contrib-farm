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

The script asks a few questions (press Enter to accept the defaults), shows how many commits it will make, then does the rest.

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

For every day in the range the script:
1. Skips the day if it's a weekend (optional) or if a random roll lands under the skip chance, so the graph has natural gaps.
2. Picks a random number of commits between min and max.
3. Makes each commit at a random time between 09:00 and 23:30, appending a line to `activity.log` and committing with that date.

All commits go into a **separate repo** (default `~/my-contrib-farm`), never into this one.

## How many contributions?

Roughly: `days × (1 - skip%) × (min + max) / 2`

| Settings | Expected commits |
|---|---|
| Defaults (365 days, 1 to 8 per day, 20% skip) | ~1,300 |
| Defaults + skip weekends | ~940 |
| `min 5, max 15, skip 0` | ~3,700 |
| `max 4, skip 35, skip weekends` (subtle) | ~340 |

Running it again on the same repo **adds** commits on top of the existing ones.

## Options

| PowerShell (`farm.ps1`) | Bash (`farm.sh`) | Default | What it does |
|---|---|---|---|
| `-RepoPath` | `--path` | `~/my-contrib-farm` | Local folder for the farm repo |
| `-Days` | `--days` | 365 | How many days back to start |
| `-MinPerDay` | `--min` | 1 | Min commits on an active day |
| `-MaxPerDay` | `--max` | 8 | Max commits on an active day |
| `-SkipChance` | `--skip` | 20 | % chance a day is left empty |
| `-SkipWeekends` | `--skip-weekends` | off | No commits on weekends |
| `-RemoteUrl` | `--remote` | | GitHub repo URL to push to |
| `-RepoName` | `--name` | my-contrib-farm | Name for the auto-created repo |
| `-Public` | `--public` | private | Make the auto-created repo public |
| `-Push` | `--push` | off | Push to GitHub when done |

Example:
```powershell
.\farm.ps1 -Days 180 -MaxPerDay 10 -SkipWeekends -Push
```
```bash
./farm.sh --days 180 --max 10 --skip-weekends --push
```

## Commits not showing up?

- The email in the commits must be verified on your GitHub account.
- Commits must be on the repo's **default branch** (the script uses `main`).
- The repo can't be a fork.
- Private repo? Turn on **Private contributions** on your profile (click "Contribution settings" above the graph).
- Give GitHub a few minutes to update the graph.

## Undo

Delete the farm repo on GitHub (Settings, Danger zone, Delete). The contributions disappear from your graph.

## Disclaimer

This is a toy. The commits are filler, and anyone who opens the repo can see that. Use it for fun, not to mislead people.

## License

MIT

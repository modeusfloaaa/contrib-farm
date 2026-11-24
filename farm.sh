#!/usr/bin/env bash
# GitHub contribution farmer (macOS / Linux / Git Bash)
# Makes backdated commits in a separate repo so your contribution graph fills up.
#
#   ./farm.sh                       guided setup
#   ./farm.sh --days 180 --max 10 --skip-weekends --push
#   ./farm.sh --remote https://github.com/you/my-contrib-farm.git --push
set -euo pipefail

REPO_PATH="$HOME/my-contrib-farm"
DAYS=365
MIN=1
MAX=8
SKIP=20
SKIP_WEEKENDS=0
REMOTE=""
REPO_NAME="my-contrib-farm"
PUBLIC=0
PUSH=0

usage() {
  cat <<EOF
Usage: ./farm.sh [options]   (no options = guided setup)
  --path DIR         local folder for the farm repo (default: ~/my-contrib-farm)
  --days N           how many days back (default: 365)
  --min N            min commits on an active day (default: 1)
  --max N            max commits on an active day (default: 8)
  --skip N           % chance a day is left empty (default: 20)
  --skip-weekends    no commits on Saturday/Sunday
  --remote URL       GitHub repo URL (empty = auto-create with the GitHub CLI)
  --name NAME        name for the auto-created repo (default: my-contrib-farm)
  --public           make the auto-created repo public (default: private)
  --push             push to GitHub when done
EOF
}

ask()    { local a; read -r -p "$1 [$2] " a; echo "${a:-$2}"; }
ask_yes() { local a; read -r -p "$1 [$2] " a; a="${a:-$2}"; [[ "$a" =~ ^[Yy] ]]; }

command -v git >/dev/null || { echo "git is not installed. Get it at https://git-scm.com"; exit 1; }
HAS_GH=0; command -v gh >/dev/null && HAS_GH=1

if [[ $# -eq 0 ]]; then
  echo
  echo "=== GitHub contribution farmer ==="
  echo "Press Enter to accept the default in brackets."
  echo
  DAYS=$(ask "How many days back?" 365)
  MIN=$(ask "Min commits on an active day?" 1)
  MAX=$(ask "Max commits on an active day?" 8)
  SKIP=$(ask "Chance (%) a day is left empty?" 20)
  ask_yes "Skip weekends?" n && SKIP_WEEKENDS=1
  REPO_PATH=$(ask "Local folder for the farm repo?" "$REPO_PATH")
  if ask_yes "Push to GitHub when done?" y; then
    PUSH=1
    if [[ $HAS_GH -eq 1 ]]; then
      REMOTE=$(ask "GitHub repo URL (leave empty to create '$REPO_NAME' automatically)" "")
    else
      REMOTE=$(ask "GitHub repo URL (create an empty repo on github.com first)" "")
    fi
  fi
  factor=7; [[ $SKIP_WEEKENDS -eq 1 ]] && factor=5
  est=$(( (DAYS + 1) * (100 - SKIP) * (MIN + MAX) * factor / (100 * 2 * 7) ))
  echo
  echo "This will make roughly $est commits."
  ask_yes "Go?" y || exit 0
else
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --path) REPO_PATH="$2"; shift 2 ;;
      --days) DAYS="$2"; shift 2 ;;
      --min) MIN="$2"; shift 2 ;;
      --max) MAX="$2"; shift 2 ;;
      --skip) SKIP="$2"; shift 2 ;;
      --skip-weekends) SKIP_WEEKENDS=1; shift ;;
      --remote) REMOTE="$2"; shift 2 ;;
      --name) REPO_NAME="$2"; shift 2 ;;
      --public) PUBLIC=1; shift ;;
      --push) PUSH=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) echo "Unknown option: $1"; usage; exit 1 ;;
    esac
  done
fi

(( MIN <= MAX )) || { echo "--min cannot be larger than --max"; exit 1; }

# GNU date (Linux, Git Bash) vs BSD date (macOS)
if date -d @0 +%s >/dev/null 2>&1; then
  fmt()  { date -d "@$1" "+$2"; }
else
  fmt()  { date -r "$1" "+$2"; }
fi

mkdir -p "$REPO_PATH"
cd "$REPO_PATH"
if [[ ! -d .git ]]; then
  git init -q
  git checkout -q -b main
  git config core.autocrlf false
  printf '# contrib-farm\n' > README.md
fi

EMAIL=$(git config user.email || true)
[[ -n "$EMAIL" ]] || { echo 'git user.email is not set. Run: git config --global user.email you@example.com'; exit 1; }
echo "Committing as $EMAIL (must match an email on your GitHub account)"

NOW=$(date +%s)
TODAY_MIDNIGHT=$(( NOW - NOW % 86400 ))
TOTAL=0

for (( i = DAYS; i >= 0; i-- )); do
  DAY=$(( TODAY_MIDNIGHT - i * 86400 + 43200 ))   # noon, safe from DST/timezone edges
  DAY_START=$(( DAY - 43200 ))
  if [[ $SKIP_WEEKENDS -eq 1 ]]; then
    dow=$(fmt "$DAY" %u)
    [[ $dow -ge 6 ]] && continue
  fi
  (( RANDOM % 100 < SKIP )) && continue

  COUNT=$(( MIN + RANDOM % (MAX - MIN + 1) ))
  TIMES=()
  for (( c = 0; c < COUNT; c++ )); do
    TIMES+=( $(( DAY_START + 32400 + (RANDOM * 32768 + RANDOM) % 52200 )) )
  done
  IFS=$'\n' TIMES=($(sort -n <<<"${TIMES[*]}")); unset IFS

  for T in "${TIMES[@]}"; do
    (( T > NOW )) && continue
    STAMP=$(fmt "$T" "%Y-%m-%dT%H:%M:%S")
    echo "$STAMP" >> activity.log
    git add -A
    GIT_AUTHOR_DATE="$STAMP" GIT_COMMITTER_DATE="$STAMP" git commit -q -m "update $STAMP"
    TOTAL=$(( TOTAL + 1 ))
  done
  printf '\r%s  (%d commits)' "$(fmt "$DAY" %Y-%m-%d)" "$TOTAL"
done
echo
echo "Done: $TOTAL commits over $DAYS days in $REPO_PATH"

HAS_ORIGIN=0; git remote | grep -qx origin && HAS_ORIGIN=1
if [[ -n "$REMOTE" ]]; then
  if [[ $HAS_ORIGIN -eq 1 ]]; then git remote set-url origin "$REMOTE"; else git remote add origin "$REMOTE"; fi
  HAS_ORIGIN=1
fi

if [[ $PUSH -eq 1 ]]; then
  if [[ $HAS_ORIGIN -eq 0 ]]; then
    [[ $HAS_GH -eq 1 ]] || { echo "No remote set. Pass --remote <url>, or install the GitHub CLI (https://cli.github.com)."; exit 1; }
    VIS="--private"; [[ $PUBLIC -eq 1 ]] && VIS="--public"
    gh repo create "$REPO_NAME" "$VIS" --source . --remote origin --push
  elif ! git push -u origin main; then
    # GitHub repo already has commits (README/LICENSE made on github.com): merge, never rebase
    echo "GitHub repo has commits you don't have locally, merging them in..."
    git fetch -q origin
    git merge origin/main --allow-unrelated-histories --no-edit -q -X ours
    git push -u origin main
  fi
  echo "Pushed. The graph can take a few minutes to update."
  if [[ $PUBLIC -eq 0 && -z "$REMOTE" ]]; then
    echo "The repo is private: turn on 'Private contributions' on your GitHub profile so the commits show."
  fi
else
  echo "Not pushed. Run again with --push (and --remote <url> if you don't have the GitHub CLI)."
fi

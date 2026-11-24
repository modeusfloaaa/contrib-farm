#!/usr/bin/env bash
# GitHub contribution farmer (macOS / Linux / Git Bash)
# Makes backdated commits in a separate repo so your contribution graph fills up.
#
#   ./farm.sh                                          guided setup
#   ./farm.sh --total 5000 --push                      exactly 5000 contributions over the last year
#   ./farm.sh --total 800 --from 2025-01-01 --to 2025-12-31
#   ./farm.sh --days 180 --max 10 --skip-weekends --push
set -euo pipefail

REPO_PATH="$HOME/my-contrib-farm"
TOTAL=0
DAYS=365
FROM=""
TO=""
MIN=1
MAX=8
SKIP=20
BUSY_DAYS=0
BUSY_MIN=30
BUSY_MAX=50
SKIP_WEEKENDS=0
START_HOUR=9
END_HOUR=23
MESSAGE="update"
REMOTE=""
REPO_NAME="my-contrib-farm"
PUBLIC=0
PUSH=0
BATCH=500
GUIDED=0

usage() {
  cat <<EOF
Usage: ./farm.sh [options]   (no options = guided setup)
  --total N          exact number of contributions (default: random, using --min/--max)
  --days N           how many days back (default: 365, ignored with --from)
  --from YYYY-MM-DD  start date
  --to YYYY-MM-DD    end date (default: today)
  --min N            min commits on an active day (default: 1)
  --max N            max commits on an active day (default: 8)
  --skip N           % chance a day is left empty (default: 20)
  --busy-days N      how many days get a lot of contributions (default: 0)
  --busy-min N       min contributions on a busy day (default: 30)
  --busy-max N       max contributions on a busy day (default: 50)
  --skip-weekends    no commits on Saturday/Sunday
  --start-hour N     earliest hour for commits, 0-23 (default: 9)
  --end-hour N       latest hour for commits, 0-23 (default: 23)
  --message TEXT     commit message, the timestamp is added after it (default: update)
  --path DIR         local folder for the farm repo (default: ~/my-contrib-farm)
  --remote URL       GitHub repo URL (empty = auto-create with the GitHub CLI)
  --name NAME        name for the auto-created repo (default: my-contrib-farm)
  --public           make the auto-created repo public (default: private)
  --push             push to GitHub when done
  --batch N          commits per push (default: 500; GitHub skips commits beyond ~1000 in one push)
EOF
}

die()     { echo "Error: $*" >&2; exit 1; }
ask()     { local a; read -r -p "$1 [$2] " a; echo "${a:-$2}"; }
ask_yes() { local a; read -r -p "$1 [$2] " a; a="${a:-$2}"; [[ "$a" =~ ^[Yy] ]]; }
is_int()  { [[ "$1" =~ ^[0-9]+$ ]]; }

command -v git >/dev/null || die "git is not installed. Get it at https://git-scm.com"
HAS_GH=0; command -v gh >/dev/null && HAS_GH=1

# GNU date (Linux, Git Bash) vs BSD date (macOS)
if date -d @0 +%s >/dev/null 2>&1; then
  fmt()      { date -d "@$1" "+$2"; }
  midnight() { date -d "$1 00:00:00" +%s 2>/dev/null; }
else
  fmt()      { date -r "$1" "+$2"; }
  midnight() { date -j -f "%Y-%m-%d %H:%M:%S" "$1 00:00:00" +%s 2>/dev/null; }
fi
TODAY=$(date +%Y-%m-%d)

# ---------- options / guided mode ----------
if [[ $# -eq 0 ]]; then
  GUIDED=1
  echo
  echo "=== GitHub contribution farmer ==="
  echo "Press Enter to accept the default in brackets."
  echo
  t=$(ask "How many contributions do you want? (number, or 'random')" random)
  is_int "$t" && TOTAL=$t
  FROM=$(ask "Start date (YYYY-MM-DD)" "$(fmt $(( $(midnight "$TODAY") + 43200 - 365 * 86400 )) %Y-%m-%d)")
  TO=$(ask "End date (YYYY-MM-DD)" "$TODAY")
  if [[ $TOTAL -eq 0 ]]; then
    MIN=$(ask "Min commits on an active day?" 1)
    MAX=$(ask "Max commits on an active day?" 8)
  fi
  BUSY_DAYS=$(ask "How many days should be extra busy (lots of contributions)?" 0)
  if [[ "$BUSY_DAYS" != "0" ]]; then
    BUSY_MIN=$(ask "Min contributions on a busy day?" 30)
    BUSY_MAX=$(ask "Max contributions on a busy day?" 50)
  fi
  SKIP=$(ask "Chance (%) a day is left empty?" 20)
  ask_yes "Skip weekends?" n && SKIP_WEEKENDS=1
  START_HOUR=$(ask "Earliest hour for commits (0-23)?" 9)
  END_HOUR=$(ask "Latest hour for commits (0-23)?" 23)
  MESSAGE=$(ask "Commit message?" update)
  REPO_PATH=$(ask "Local folder for the farm repo?" "$REPO_PATH")
  if ask_yes "Push to GitHub when done?" y; then
    PUSH=1
    if [[ $HAS_GH -eq 1 ]]; then
      REMOTE=$(ask "GitHub repo URL (leave empty to create '$REPO_NAME' automatically)" "")
    else
      REMOTE=$(ask "GitHub repo URL (create an empty repo on github.com first)" "")
    fi
  fi
else
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --total) TOTAL="$2"; shift 2 ;;
      --days) DAYS="$2"; shift 2 ;;
      --from) FROM="$2"; shift 2 ;;
      --to) TO="$2"; shift 2 ;;
      --min) MIN="$2"; shift 2 ;;
      --max) MAX="$2"; shift 2 ;;
      --skip) SKIP="$2"; shift 2 ;;
      --busy-days) BUSY_DAYS="$2"; shift 2 ;;
      --busy-min) BUSY_MIN="$2"; shift 2 ;;
      --busy-max) BUSY_MAX="$2"; shift 2 ;;
      --skip-weekends) SKIP_WEEKENDS=1; shift ;;
      --start-hour) START_HOUR="$2"; shift 2 ;;
      --end-hour) END_HOUR="$2"; shift 2 ;;
      --message) MESSAGE="$2"; shift 2 ;;
      --path) REPO_PATH="$2"; shift 2 ;;
      --remote) REMOTE="$2"; shift 2 ;;
      --name) REPO_NAME="$2"; shift 2 ;;
      --public) PUBLIC=1; shift ;;
      --push) PUSH=1; shift ;;
      --batch) BATCH="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) usage; die "unknown option: $1" ;;
    esac
  done
fi

# ---------- validate ----------
for v in TOTAL DAYS MIN MAX SKIP START_HOUR END_HOUR BATCH BUSY_DAYS BUSY_MIN BUSY_MAX; do is_int "${!v}" || die "$v must be a whole number"; done
(( MIN <= MAX )) || die "--min cannot be larger than --max"
(( BUSY_MIN <= BUSY_MAX )) || die "--busy-min cannot be larger than --busy-max"
(( SKIP <= 100 )) || die "--skip must be 0-100"
(( START_HOUR <= END_HOUR && END_HOUR <= 23 )) || die "hours must be 0-23 and start <= end"
[[ -n "$MESSAGE" ]] || MESSAGE="update"

[[ -n "$TO" ]] || TO="$TODAY"
TO_MID=$(midnight "$TO") || die "end date '$TO' is not a date like 2025-01-31"
TODAY_MID=$(midnight "$TODAY")
(( TO_MID > TODAY_MID )) && TO_MID=$TODAY_MID
if [[ -n "$FROM" ]]; then
  FROM_MID=$(midnight "$FROM") || die "start date '$FROM' is not a date like 2025-01-31"
else
  FROM_MID=$(midnight "$(fmt $(( TO_MID + 43200 - DAYS * 86400 )) %Y-%m-%d)")
fi
(( FROM_MID <= TO_MID )) || die "start date is after end date"
NDAYS=$(( (TO_MID - FROM_MID + 43200) / 86400 ))

# ---------- plan: which days get how many commits ----------
LABELS=(); MIDS=(); TZS=()
for (( k = 0; k <= NDAYS; k++ )); do
  NOON=$(( FROM_MID + 43200 + k * 86400 ))
  read -r LABEL DOW ZONE <<<"$(fmt "$NOON" '%Y-%m-%d %u %z')"
  [[ $SKIP_WEEKENDS -eq 1 && $DOW -ge 6 ]] && continue
  (( RANDOM % 100 < SKIP )) && continue
  LABELS+=("$LABEL"); MIDS+=("$(midnight "$LABEL")"); TZS+=("$ZONE")
done
N=${#LABELS[@]}
(( N > 0 )) || die "no days left to commit on. Lower the skip chance, turn off skip weekends, or widen the dates."

COUNTS=(); BUSY=(); IDX=()
for (( i = 0; i < N; i++ )); do COUNTS+=(0); BUSY+=(0); IDX+=("$i"); done

# busy days first: random days that get BUSY_MIN..BUSY_MAX contributions
BUSY_N=$(( BUSY_DAYS < N ? BUSY_DAYS : N ))
BUSY_SUM=0
for (( j = 0; j < BUSY_N; j++ )); do
  r=$(( j + (RANDOM * 32768 + RANDOM) % (N - j) )); t=${IDX[j]}; IDX[j]=${IDX[r]}; IDX[r]=$t
  i=${IDX[j]}; BUSY[i]=1
  COUNTS[i]=$(( BUSY_MIN + RANDOM % (BUSY_MAX - BUSY_MIN + 1) ))
  BUSY_SUM=$(( BUSY_SUM + COUNTS[i] ))
done
NORMAL=(); for (( i = 0; i < N; i++ )); do if [[ ${BUSY[i]} -eq 0 ]]; then NORMAL+=("$i"); fi; done

if (( TOTAL > 0 )); then
  # exact total: the busy days take their share, the rest is spread over the other days with random weights
  REST=$(( TOTAL - BUSY_SUM ))
  (( REST >= 0 )) || die "the $BUSY_N busy days alone make $BUSY_SUM contributions, more than your total of $TOTAL. Lower --busy-days/--busy-min or raise --total."
  if (( ${#NORMAL[@]} > 0 )); then POOL=("${NORMAL[@]}"); else POOL=("${IDX[@]}"); fi
  P=${#POOL[@]}
  W=(); SUMW=0
  for (( p = 0; p < P; p++ )); do W+=( $(( 1 + RANDOM % 10 )) ); SUMW=$(( SUMW + W[p] )); done
  GIVEN=0
  for (( p = 0; p < P; p++ )); do
    i=${POOL[p]}; n=$(( REST * W[p] / SUMW )); COUNTS[i]=$(( COUNTS[i] + n )); GIVEN=$(( GIVEN + n ))
  done
  for (( r = GIVEN; r < REST; r++ )); do i=${POOL[(RANDOM * 32768 + RANDOM) % P]}; COUNTS[i]=$(( COUNTS[i] + 1 )); done
else
  for i in ${NORMAL[@]+"${NORMAL[@]}"}; do COUNTS[i]=$(( MIN + RANDOM % (MAX - MIN + 1) )); done
fi
PLANNED=0; BUSIEST=0
for c in "${COUNTS[@]}"; do PLANNED=$(( PLANNED + c )); (( c > BUSIEST )) && BUSIEST=$c; done

echo
echo "Plan: $PLANNED contributions from ${LABELS[0]} to ${LABELS[N-1]}, on $N days (busiest day: $BUSIEST)"
if (( BUSY_N > 0 )); then
  OVER=0; for c in "${COUNTS[@]}"; do if (( c >= BUSY_MIN )); then OVER=$(( OVER + 1 )); fi; done
  echo "      $BUSY_N busy days with $BUSY_MIN-$BUSY_MAX each ($OVER days in total have $BUSY_MIN+)"
fi
if [[ $GUIDED -eq 1 ]]; then ask_yes "Go?" y || exit 0; fi
(( PLANNED > 0 )) || { echo "Nothing to do."; exit 0; }

# ---------- set up the repo ----------
mkdir -p "$REPO_PATH"
cd "$REPO_PATH"
NEW_REPO=0
if [[ ! -d .git ]]; then
  NEW_REPO=1
  git init -q
  git checkout -q -b main
  git config core.autocrlf false
fi
[[ -z "$(git status --porcelain)" ]] || die "$REPO_PATH has uncommitted changes. Commit or remove them first."

NAME=$(git config user.name || true)
EMAIL=$(git config user.email || true)
[[ -n "$EMAIL" ]] || die 'git user.email is not set. Run: git config --global user.email you@example.com'
[[ -n "$NAME" ]]  || die 'git user.name is not set. Run: git config --global user.name "Your Name"'
echo "Committing as $EMAIL (must match an email on your GitHub account)"

BRANCH=$(git symbolic-ref --short HEAD)

# ---------- connect to GitHub first, so new commits go on top of what's already there ----------
CREATED=0; HAS_REMOTE_BRANCH=0
if [[ -n "$REMOTE" ]]; then
  if git remote | grep -qx origin; then git remote set-url origin "$REMOTE"; else git remote add origin "$REMOTE"; fi
fi
if [[ $PUSH -eq 1 ]]; then
  if ! git remote | grep -qx origin; then
    [[ $HAS_GH -eq 1 ]] || die "no remote set. Pass --remote <url>, or install the GitHub CLI (https://cli.github.com)."
    VIS="--private"; [[ $PUBLIC -eq 1 ]] && VIS="--public"
    URL=$(gh repo create "$REPO_NAME" "$VIS") || die "creating the GitHub repo failed (see above)"
    git remote add origin "$(echo "$URL" | tr -d '[:space:]')"
    CREATED=1
  fi
  git fetch -q origin || die "could not reach the GitHub repo (see above)"
  if git rev-parse -q --verify "refs/remotes/origin/$BRANCH" >/dev/null; then
    HAS_REMOTE_BRANCH=1
    if ! git rev-parse -q --verify HEAD >/dev/null; then
      git reset -q --hard "origin/$BRANCH"     # empty local repo: start from what's on GitHub
      NEW_REPO=0
    elif ! git merge-base --is-ancestor "origin/$BRANCH" HEAD; then
      # GitHub has commits we don't (README/LICENSE made on github.com): merge, never rebase
      echo "GitHub repo has commits you don't have locally, merging them in..."
      git merge "origin/$BRANCH" --allow-unrelated-histories --no-edit -q -X ours || die "merge failed. Resolve it in $REPO_PATH and run again."
    fi
  fi
fi

HAS_HEAD=0; git rev-parse -q --verify HEAD >/dev/null && HAS_HEAD=1

# Build one git fast-import stream: thousands of commits in seconds instead of minutes
NOW=$(date +%s)
LO=$(( START_HOUR * 3600 )); SPAN=$(( (END_HOUR - START_HOUR + 1) * 3600 ))
STREAM=$(mktemp)
trap 'rm -f "$STREAM"' EXIT
(
  export LC_ALL=C   # so ${#var} counts bytes, which fast-import needs
  FIRST=1
  for (( i = 0; i < N; i++ )); do
    (( COUNTS[i] > 0 )) || continue
    MID=${MIDS[i]}; LABEL=${LABELS[i]}; ZONE=${TZS[i]}
    SECS=()
    for (( c = 0; c < COUNTS[i]; c++ )); do
      S=$(( LO + (RANDOM * 32768 + RANDOM) % SPAN ))
      if (( MID + S > NOW )); then S=$(( NOW - MID - 1 - RANDOM % 600 )); (( S < 0 )) && S=0; fi
      SECS+=("$S")
    done
    while read -r S; do
      printf -v STAMP '%sT%02d:%02d:%02d' "$LABEL" $(( S / 3600 )) $(( S % 3600 / 60 )) $(( S % 60 ))
      MSG="$MESSAGE $STAMP"
      WHO="$NAME <$EMAIL> $(( MID + S )) $ZONE"
      printf 'commit refs/heads/%s\nauthor %s\ncommitter %s\ndata %d\n%s\n' "$BRANCH" "$WHO" "$WHO" "${#MSG}" "$MSG"
      if [[ $FIRST -eq 1 ]]; then
        [[ $HAS_HEAD -eq 1 ]] && printf 'from refs/heads/%s^0\n' "$BRANCH"
        [[ $NEW_REPO -eq 1 ]] && printf 'M 100644 inline README.md\ndata 18\n# my-contrib-farm\n\n'
        FIRST=0
      fi
      printf 'M 100644 inline activity.log\ndata %d\n%s\n\n' $(( ${#STAMP} + 1 )) "$STAMP"
    done < <(printf '%s\n' "${SECS[@]}" | sort -n)
    printf '\rBuilding commits: %s' "$LABEL" >&2
  done
) > "$STREAM"
echo >&2
echo "Writing $PLANNED commits..."
git fast-import --quiet < "$STREAM"
git reset -q --hard
echo "Done: $PLANNED commits in $REPO_PATH"

# ---------- push ----------
if [[ $PUSH -eq 1 ]]; then
  # GitHub only counts roughly the newest 1000 commits of a single push, so push oldest first in batches.
  RANGE="HEAD"; [[ $HAS_REMOTE_BRANCH -eq 1 ]] && RANGE="origin/$BRANCH..HEAD"
  SHAS=( $(git rev-list --reverse --first-parent "$RANGE") )
  COUNT=${#SHAS[@]}
  (( BATCH > 0 )) || BATCH=500
  for (( k = BATCH - 1; k < COUNT - 1; k += BATCH )); do
    if [[ $HAS_REMOTE_BRANCH -eq 1 ]] && ! git merge-base --is-ancestor "origin/$BRANCH" "${SHAS[k]}"; then
      continue   # would not be a fast-forward yet
    fi
    echo "Pushing $(( k + 1 )) / $COUNT..."
    git push -q origin "${SHAS[k]}:refs/heads/$BRANCH"
  done
  echo "Pushing $COUNT / $COUNT..."
  git push -q -u origin "$BRANCH"
  echo "Pushed. The graph can take a few minutes to update."
  if [[ $PUBLIC -eq 0 && $CREATED -eq 1 ]]; then
    echo "The repo is private: turn on 'Private contributions' on your GitHub profile so the commits show."
  fi
else
  echo "Not pushed. Run again with --push (and --remote <url> if you don't have the GitHub CLI)."
fi

#!/bin/bash
# GitUP - Backup shit with git <3
# Flags: --auto / --dry-run / --config /path/to/gitup.conf

# --- COLOR SETUP ---
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
RESET=$(tput sgr0)

# --- FLAGS ---
AUTO_MODE=0
DRY_RUN=0
CONFIG_FILE=""

# --- REQUIREMENTS ---
command -v jq >/dev/null 2>&1 || { echo "Missing jq. Install it."; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --auto) AUTO_MODE=1 ;;
        --dry-run) DRY_RUN=1 ;;
        --config)
            shift
            CONFIG_FILE="$1"
            ;;
        *) ;;
    esac
    shift
done

# --- LOAD CONFIG FROM FILE ---
CONFIG_FILE="${CONFIG_FILE:-gitup.conf}"
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"

# --- DEFAULT CONFIG (fallbacks) ---
GIT_USER="${GIT_USER:-serainox420}"
GIT_EMAIL="${GIT_EMAIL:-serainox@gmail.com}"
GITHUB_USER="${GITHUB_USER:-serainox420}"
GITHUB_TOKEN="${GITHUB_TOKEN:-ghp_2uNMvSjwypi3r0al4y3HtqI6}"
DEFAULT_REPO_URL="${DEFAULT_REPO_URL:-github.com/serainox420/PersonalBackup.git}"
DEFAULT_DIR="${DEFAULT_DIR:-.}"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-backup}"
export DEFAULT_REPO_URL DEFAULT_BRANCH
# ----------------------------------

# --- HELPERS ---
log() { echo -e "${YELLOW}[INFO]${RESET} $1"; }
success() { echo -e "${GREEN}[OK]${RESET} $1"; }
error() { echo -e "${RED}[ERR]${RESET} $1"; }

run() {
    if [[ "$DRY_RUN" == "1" ]]; then
        log "(dry-run) $*"
    else
        eval "$@"
    fi
}

menu() {
    repo_name=$(basename "$DEFAULT_REPO_URL" .git)
    current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "none")
    header=$"[$GITHUB_USER] / [$repo_name] / [Branch: $current_branch]"

    options=("New Backup" "Create Repo" "Select Repo" "Create Branch" "Change Branch" "Pull Remote" "Merge Local" "Merge Remote" "Exit")
    choice=$(printf "%s\n" "${options[@]}" | fzf \
        --reverse \
        --prompt="Choose action > " \
        --height=10 \
        --border \
        --header="$header")

    case "$choice" in
        "New Backup") new_backup ;;
        "Create Repo") create_repo ;;
        "Select Repo") select_repo ;;
        "Create Branch") create_branch ;;
        "Change Branch") change_branch ;;
        "Pull Remote") pull_remote ;;
        "Merge Local") merge_branches ;;
        "Merge Remote") merge_remote ;;
        "Exit") exit 0 ;;
        *) error "Invalid choice" ;;
    esac
}

new_backup() {
    if [[ "$AUTO_MODE" == "1" || "$DRY_RUN" == "1" ]]; then
        REPO_URL="$DEFAULT_REPO_URL"
        DIR="$DEFAULT_DIR"
        BRANCH="$DEFAULT_BRANCH"
    else
        read -p "Repo URL [${DEFAULT_REPO_URL}]: " REPO_URL
        REPO_URL="${REPO_URL:-$DEFAULT_REPO_URL}"

        read -p "Directory [${DEFAULT_DIR}]: " DIR
        DIR="${DIR:-$DEFAULT_DIR}"

        read -p "Branch [${DEFAULT_BRANCH}]: " BRANCH
        BRANCH="${BRANCH:-$DEFAULT_BRANCH}"
    fi

    log "Backing up: $DIR → $REPO_URL [$BRANCH]"

    cd "$DIR" || { error "Failed to cd into $DIR"; exit 1; }

    [ ! -d ".git" ] && run "git init"

    run "git config user.name \"$GIT_USER\""
    run "git config user.email \"$GIT_EMAIL\""

    if git remote | grep -q origin; then
        run "git remote set-url origin \"https://$GITHUB_USER:$GITHUB_TOKEN@$REPO_URL\""
    else
        run "git remote add origin \"https://$GITHUB_USER:$GITHUB_TOKEN@$REPO_URL\""
    fi

    if git rev-parse --verify "$BRANCH" >/dev/null 2>&1; then
        run "git checkout \"$BRANCH\""
    else
        run "git checkout -b \"$BRANCH\""
    fi

    export DEFAULT_REPO_URL="$REPO_URL"
    export DEFAULT_BRANCH="$BRANCH"

    run "git add ."
    run "git commit -m \"Backup $(date '+%Y-%m-%d %H:%M:%S')\" || true"
    run "git push -u origin \"$BRANCH\" --force"

    success "Backup completed."
}

change_branch() {
    branch=$(git branch -a | sed 's/^..//' | fzf --prompt="Checkout branch > ")
    [ -n "$branch" ] && run "git checkout \"$branch\"" && export DEFAULT_BRANCH="$branch"
}

pull_remote() {
    br=$(git branch -r | sed 's/origin\///' | sort -u | fzf --prompt="Pull branch > " | xargs)
    if [ -n "$br" ]; then
        url="https://$GITHUB_USER:$GITHUB_TOKEN@${DEFAULT_REPO_URL}"
        run "git remote set-url origin \"$url\""
        run "git pull --no-rebase --strategy=recursive -X theirs origin \"$br\""
        export DEFAULT_BRANCH="$br"
    fi
}

merge_branches() {
    from=$(git branch | sed 's/^..//' | fzf --prompt="Merge FROM > ")
    to=$(git branch | sed 's/^..//' | fzf --prompt="Merge TO > ")
    [ -n "$from" ] && [ -n "$to" ] && run "git checkout \"$to\"" && run "git merge -X theirs \"$from\" --no-edit"
}

merge_remote() {
    base=$(git branch | sed 's/^..//' | fzf --prompt="Merge INTO (base) > ")
    head=$(git branch | sed 's/^..//' | fzf --prompt="Merge FROM (head) > ")
    if [ -n "$base" ] && [ -n "$head" ]; then
        json=$(printf '{"title":"Merge %s into %s","head":"%s","base":"%s"}' "$head" "$base" "$head" "$base")
        url="https://api.github.com/repos/$GITHUB_USER/$(basename "$DEFAULT_REPO_URL" .git)/pulls"
        if [[ "$DRY_RUN" == "1" ]]; then
            log "(dry-run) curl -X POST $url -d '$json'"
        else
            curl -s -X POST \
                -H "Authorization: token $GITHUB_TOKEN" \
                -H "Accept: application/vnd.github.v3+json" \
                "$url" \
                -d "$json"
        fi
        success "Merge request sent (or simulated)."
    fi
}

create_repo() {
    read -p "New repo name: " name
    read -p "Description (optional): " desc
    json=$(jq -n --arg name "$name" --arg desc "$desc" '{name: $name, description: $desc, private: false}')
    run "curl -s -X POST -H \"Authorization: token $GITHUB_TOKEN\" -H \"Accept: application/vnd.github.v3+json\" https://api.github.com/user/repos -d '$json'"
    success "Repo '$name' created."
}

select_repo() {
    page=1
    repos=""
    while :; do
        res=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
            "https://api.github.com/user/repos?affiliation=owner&per_page=100&page=$page")

        count=$(echo "$res" | jq length)
        [[ "$count" -eq 0 ]] && break

        repos+=$(echo "$res" | jq -r '.[].full_name')$'\n'
        ((page++))
    done

    selected=$(echo "$repos" | fzf --prompt="Select repo > ")
    [ -n "$selected" ] && DEFAULT_REPO_URL="github.com/$selected.git" && export DEFAULT_REPO_URL
    success "Repo set to: $DEFAULT_REPO_URL"
}

create_branch() {
    read -p "New branch name: " br
    [ -n "$br" ] && run "git checkout -b \"$br\"" && export DEFAULT_BRANCH="$br" && success "Branch '$br' created."
}

# --- MAIN ---
if [[ "$AUTO_MODE" == "1" || "$DRY_RUN" == "1" ]]; then
    new_backup
    exit 0
else
    while true; do
        menu
    done
fi

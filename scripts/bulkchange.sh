#!/usr/bin/env bash

# shellcheck disable=SC2317

# Variables

ROOT_DIRECTORY=$(pwd)

MESSAGE="$ROOT_DIRECTORY/message.txt"
export MESSAGE
if [ ! -f "$MESSAGE" ]; then
    echo "Message text file not found: $MESSAGE"; exit 1
fi

# Source common script functions
# shellcheck source=scripts/common.sh
source common.sh

# Trap actions on exit
cleanup_on_exit() {
    #if [ -d /tmp/bulk-git ]; then
    #    rm -Rf /tmp/bulk-git
    #fi
    #if [ -d "$GITHUB_ORG" ]; then
    #    rm -Rf "$GITHUB_ORG"
    #fi
    echo "Script completed"
}
trap cleanup_on_exit EXIT

# Make sure the GitHub CLI is authenticated
echo "Checking authentication status"
auth_check

echo "Directory: $ROOT_DIRECTORY"

# Create an array containing the repositories
declare -a REPO_ARRAY
mapfile -t REPO_ARRAY < <(gfind . -maxdepth 1 -mindepth 1 -type d -printf '%f\n')

echo "Repositories: ${#REPO_ARRAY[@]}"
if [ "$DEBUG" = "true" ]; then
    for REPO in "${EXCLUDED_ARRAY[@]}"; do
        echo "Excluded: $REPO"
    done
fi

update_repo() {
    REPO="$1"
    cd "$REPO" || exit 1
    if [ -f README.md ]; then
        DOCUMENT="README.md"
    fi

    # Test against a specific repo before removing conditionality
    #if [ "$REPO" = "Data-Requests" ]; then
        echo "Processing repo: $1"
        # Delete the first three lines from the markdown file
        sed -i "1,3d" "$DOCUMENT"
        # Inject the message text from the specified file
        sed -i "0r $MESSAGE" "$DOCUMENT"
        git add "$DOCUMENT"
        git checkout -b banner-linting-fix
        git commit -as -S -m "Fix: Add missing linting exclusions for README.md [skip ci]" --no-verify
        PR_URL=$(git push 2>&1 | grep "https://github.org")
        PR_URL=$(gh pr create --fill)
        echo "Change: $PR_URL"
        sleep 60
        gh pr merge --squash --delete-branch --admin --subject \
            "Fix: Add missing linting exclusions for README.md [skip ci]" \
            "$PR_URL"
    #fi

    cd .. || exit 1
}
export -f update_repo

if [ "$PARALLEL_THREADS" -eq 1 ]; then
    echo "Running update operations in serial"
    for REPO in "${REPO_ARRAY[@]}"; do
        update_repo "$REPO"
    done
else
    echo "Thread count: $PARALLEL_THREADS"
    "$PARALLEL_CMD" --record-env
    "$PARALLEL_CMD" -j "$PARALLEL_THREADS" --env _ update_repo ::: "${REPO_ARRAY[@]}"
fi

# Exit and cleanup
cd ..
exit 0

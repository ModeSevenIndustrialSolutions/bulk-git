#!/usr/bin/env bash

### Script to bulk refresh a directory containing repositories ###

# shellcheck disable=SC2317

set -o pipefail
# set -xv

### Variables ###

PARALLEL_THREADS="6"
# Declare an array to store enumerated repo names
declare -a REPO_ARRAY

### Checks ###

GIT_CMD=$(which git)
export GIT_CMD
if [ ! -x "$GIT_CMD" ]; then
    echo "GIT was not found in your PATH"; exit 1
fi
PARALLEL_CMD=$(which parallel)
export PARALLEL_CMD
if [ ! -x "$PARALLEL_CMD" ]; then
    echo "GNU parallel was not found in your PATH"; exit 1
fi

# Check arguments to script
if [ $# -ne 0 ]; then
    echo "Usage: $0"; exit 1
fi

### Functions ###

check_is_repo() {
    ORIGINAL_DIR=$(pwd)
    TARGET_DIR=$(basename "$1")
    # Check directory is a GIT repository
    cd "$TARGET_DIR" || change_dir_error
    "$GIT_CMD" status > /dev/null 2>&1
    if [ $? -eq 128 ]; then
        cd "$ORIGINAL_DIR" || change_dir_error
        return 1
    else
        cd "$ORIGINAL_DIR" || change_dir_error
        return 0
    fi
}

process_directory() {
    ORIGINAL_DIR=$(pwd)
    TARGET_DIR="$1"
    printf "Processing: %s -> " "$TARGET_DIR"
    cd "$TARGET_DIR" || change_dir_error
    if (checkout_head_branch); then
        # Update the repository
        update_repo
    fi
    cd "$ORIGINAL_DIR" || change_dir_error
}

count_repos() {
    # Count the number of GIT repositories
    REPOS="0"
    FOLDERS=$(find . -type d -depth 1)
    for FOLDER in $FOLDERS; do
        # Get rid of the leading "./"
        TARGET=$(basename "$FOLDER")
        if (check_is_repo "$TARGET"); then
            REPOS=$((REPOS+1))
            REPO_LIST="${REPO_LIST} ${TARGET}"
            REPO_ARRAY[REPOS]="$TARGET"
        fi
    done
    FOUND=$(echo "$FOLDERS" | wc -w)
    echo "Found: $FOUND directories, $REPOS git repositories"
}

check_if_fork() {
    # Checks for both upstream and origin
    UPSTREAM_COUNT=$(git remote | \
        grep -E -e 'upstream|origin' -c)
    if [ "$UPSTREAM_COUNT" -eq 2 ]; then
        # Repository is a fork
        return 0
    else
        return 1
    fi
}

checkout_head_branch() {
    CURRENT_BRANCH=$("$GIT_CMD" branch --show-current)
    HEAD_BRANCH=$("$GIT_CMD" rev-parse --abbrev-ref HEAD)
    # Only checkout HEAD if not already on that branch
    if [ "$CURRENT_BRANCH" != "$HEAD_BRANCH" ]; then
        # Need to swap branch in this repository
        if ("$GIT_CMD" checkout "$HEAD_BRANCH" > /dev/null 2>&1); then
            printf "switched to %s -> " "$HEAD_BRANCH"
            return 0
        else
            echo "Error checking out $HEAD_BRANCH"
            return 1
        fi
    else
        # Already on the appropriate branch
        printf "%s -> " "$HEAD_BRANCH"
        return 0
    fi
}

update_repo() {
    HEAD_BRANCH=$("$GIT_CMD" rev-parse --abbrev-ref HEAD)
    if ! (check_if_fork); then
        printf "updating clone -> "
        if ("$GIT_CMD" pull > /dev/null 2>&1;); then
            echo "Done."
            return 0
        else
            echo "Error."
            return 1
        fi
    else
        # Repository is a fork
        printf "resetting fork -> "
        if ("$GIT_CMD" fetch upstream > /dev/null 2>&1; \
            "$GIT_CMD" reset --hard upstream/"$HEAD_BRANCH" > /dev/null 2>&1; \
            "$GIT_CMD" push origin "$HEAD_BRANCH" --force > /dev/null 2>&1); then
            echo "Done."
            return 0
        else
            echo "Error."
            return 1
        fi
    fi
}

change_dir_error() {
    echo "Could not change directory"; exit 1
}

refresh_repos_serial() {
    for REPO in "${REPO_ARRAY[@]}"; do
        process_directory "$REPO"
    done
}

refresh_repos_parallel() {
    "$PARALLEL_CMD" --record-env
    "$PARALLEL_CMD" -j "$PARALLEL_THREADS" --env _ process_directory ::: "${REPO_ARRAY[@]}"
}

# Make functions available to GNU parallel
export -f check_if_fork update_repo process_directory \
    checkout_head_branch change_dir_error

### Operations ###

CURRENT_DIR=$(basename "$PWD")
echo "Processing all GIT repositories in: $CURRENT_DIR"
count_repos
if [ "$PARALLEL_THREADS" -eq 1 ]; then
    echo "Running update operations in serial"
    refresh_repos_serial
else
    echo "Running operations concurrently; thread count: $PARALLEL_THREADS"
    refresh_repos_parallel
fi
echo "Script completed"; exit 0

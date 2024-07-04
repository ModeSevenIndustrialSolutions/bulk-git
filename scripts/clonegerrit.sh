#!/usr/bin/env bash

### Script to bulk clone/fork all of a GitHub organisation's repositories ###

set -o pipefail

### Debugging ###

# set -xv
# DEBUG="true"

### Variables ###

PARALLEL_THREADS="1"
# Declare a bunch of arrays
declare -a GERRIT_REPO_ARRAY REPOS_FETCH_ARRAY

### Checks ###

GIT_CMD=$(which git)
if [ ! -x "$GIT_CMD" ]; then
    echo "GIT was NOT found in your PATH"; exit 1
else
    export GIT_CMD
fi

PARALLEL_CMD=$(which parallel)
if [ ! -x "$PARALLEL_CMD" ]; then
    echo "The GNU parallel command was NOT found in your PATH"
    echo "On macOS you can install with homebrew using:"
    echo "  brew install parallel"; exit 1
else
    export PARALLEL_CMD
fi

ZIP_CMD=$(which zip)
if [ ! -x "$ZIP_CMD" ]; then
    echo "The zip command was NOT found in your PATH"; exit 1
else
    export ZIP_CMD
fi

if [ $# -ne 1 ]; then
    echo "Usage: $0 [ gerrit server ]"; exit 1
else
    GERRIT_SVR="$1"
fi

### Functions ###

populate_gerrit_repos_array() {
    if [ $# -ne 1 ]; then
        echo "Function populate_gerrit_repos_array() expects an argument"
        echo "Received: $*"; exit 1
    else
        GERRIT_SVR="$1"
    fi
    ssh -p 29418 "$GERRIT_SVR" gerrit ls-projects
}

fetch_gerrit_repo() {
    if [ $# -ne 1 ]; then
        echo "Error: Invalid arguments to fetch_gerrit_repo() function"
        exit 1
    fi
    REPO_NAME="$1"
    if [ -d "$REPO_NAME" ]; then
        echo "Local repository already exists: $DIRNAME"
    else
        if [ "$DEBUG" = "true" ]; then
            echo "Running: git clone --bare ssh://$GERRIT_SVR:29418/$REPO_NAME.git $REPO_NAME"
        else
            echo "Fetching: $REPO_NAME"
        fi
        if ($GIT_CMD clone --bare "ssh://$GERRIT_SVR:29418/$REPO_NAME.git" "$REPO_NAME" > /dev/null 2>&1); then
            SUCCESSES=$((SUCCESSES+1))
        else
            echo "Error: received return code $?"
            ERRORS=$((ERRORS+1))
        fi
    fi
}

report_results() {
    # Prints out the number of successes/failures
    if [ "$ERRORS" -ne 0 ] || [ "$DEBUG" = "true" ]; then
        echo "Successes: ${SUCCESSES} Failures: ${ERRORS}"
    fi
}

fetch_series() {
    # Set starting counter values for reporting
    ERRORS="0"; SUCCESSES="0"
    for GERRIT_REPO in "${GERRIT_REPO_ARRAY[@]}"; do
        fetch_gerrit_repo "$GERRIT_REPO"
    done
    report_results
}

fetch_parallel() {
    # Set some useful counters
    ERRORS="0"; SUCCESSES="0"
    # Send operations to GNU parallel from array
    "$PARALLEL_CMD" --record-env
    "$PARALLEL_CMD" -j "$PARALLEL_THREADS" --env _ fetch_gerrit_repo ::: "${GERRIT_REPO_ARRAY[@]}"
    report_results
}

export -f fetch_gerrit_repo report_results

### Operations m###

# List all the repositories in the source ORG
printf "Querying repositories in Gerrit server: %s" "$GERRIT_SVR"
mapfile -t GERRIT_REPO_ARRAY < <(populate_gerrit_repos_array "$GERRIT_SVR")
printf " [%s]\n" "${#GERRIT_REPO_ARRAY[@]}"

FETCH_COUNT=${#GERRIT_REPO_ARRAY[@]}
if [ "$FETCH_COUNT" -gt 0 ]; then
    echo "Repositories to retrieve: [$FETCH_COUNT] "
    for GERRIT_REPO in "${REPOS_FETCH_ARRAY[@]}"; do
        # REPO_NAME=$(basename "$GERRIT_REPO")
        echo "  $GERRIT_REPO"
    done
fi

if [ "$FETCH_COUNT" -ne 0 ] || [ "$REMOVE_COUNT" -ne 0 ]; then
    printf "Number of threads set to: %s" "$PARALLEL_THREADS"
    if [ "$PARALLEL_THREADS" -eq 1 ]; then
        echo " [running operations in serial]"
        fetch_series
    else
        echo " [running operations in parallel]"
        fetch_parallel
    fi
else
    echo "No repositories to fetch or remove"; exit 0
fi

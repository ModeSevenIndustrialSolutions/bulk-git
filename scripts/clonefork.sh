#!/usr/bin/env bash

### Script to bulk clone/fork all of a GitHub organisation's repositories ###

set -o pipefail

### Debugging ###

# set -xv
# DEBUG="true"

### Variables ###

PARALLEL_THREADS="1"
# Declare a bunch of arrays
declare -a SRC_ORG_REPO_ARRAY DST_ORG_REPO_ARRAY REPOS_FETCH_ARRAY REPOS_REMOVE_ARRAY
DATE=$(date '+%Y-%m-%d')

### Checks ###

GITHUB_CLI=$(which gh)
if [ ! -x "$GITHUB_CLI" ]; then
    echo "The GitHub CLI was NOT found in your PATH"; exit 1
else
    export GITHUB_CLI
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

_usage() {
    echo "Script has two modes of operation:"
    echo "Usage: $0 clone [ src github org ]"
    echo "       $0 fork [ src github org ] [ dst github org ]"; exit 1
}

# Source repository specification is entirely optional
# (if unspecified uses your personal profile repos)

# Setup the two different parameters of clone operations
if  { [ $# -eq 1 ] || [ $# -eq 2 ]; } && [ "$1" = "clone" ]; then
    SRC_GITHUB_ORG="$2"

# Setup the two different parameters of fork operations
elif  [ $# -eq 2 ] && [ "$1" = "fork" ]; then
    SRC_GITHUB_ORG="$2"
    export FLAGS="--default-branch-only --clone --remote"
elif  [ $# -eq 3 ] && [ "$1" = "fork" ]; then
    SRC_GITHUB_ORG="$2"
    DST_GITHUB_ORG="$3"
    export FLAGS="--default-branch-only --org $DST_GITHUB_ORG --clone --remote"
else
    _usage
fi
export OPERATION="$1"

### Functions ###

auth_check() {
    if ! ("$GITHUB_CLI" auth status > /dev/null ); then
        echo "You are not logged into GitHub"
        echo "Use the command:  gh auth login"
        echo "...then try this script again"; exit 1
    fi
}

populate_repos_array() {
    if [ $# -ne 2 ]; then
        echo "Function populate_repos_array() expects 2 arguments"
        echo "Received: $*"; exit 1
    fi
    GITHUB_ORG="$1"; FLAGS="$2"
    # shellcheck disable=SC2086
    "$GITHUB_CLI" repo list "$GITHUB_ORG" $FLAGS \
        --limit 4000 --json nameWithOwner --jq '.[].nameWithOwner'
}

check_arg_in_array() {
    # https://stackoverflow.com/questions/3685970/check-if-a-bash-array-contains-a-value
    # check_arg_in_array "$needle" "${haystack[@]}"
    local a b;
    # shellcheck disable=SC2182
    printf -va '\n%q\n' "$1";
    # shellcheck disable=SC2182
    printf -vb '%q\n' "${@:2}";
    case $'\n'"$b" in (*"$a"*) return 0;; esac;
    return 1;
}

check_repo_present() {
    # Function checks to presence of repo in a repo array
    if [ $# -ne 2 ]; then
        echo "Function check_repo_present() expects two arguments"
        echo "Received: $*"; exit 1
    fi
    ORG_REPO="$1"; ARRAY="$2"
    REPO_NAME=$(basename "$ORG_REPO")
    if [ "$ARRAY" = "src" ]; then
        if check_arg_in_array "$DST_GITHUB_ORG/$REPO_NAME" "${SRC_ORG_REPO_ARRAY[@]}"; then
            echo "Found match with check_repo_present(): "; return 0
        fi
    elif [ "$ARRAY" = "dst" ]; then
        if check_arg_in_array "$SRC_GITHUB_ORG/$REPO_NAME" "${DST_ORG_REPO_ARRAY[@]}"; then
            echo "Found match with check_repo_present(): "; return 0
        fi
    else
        echo "Error: Invalid array specified: $1"; exit 1
    fi
    return 1
}

remove_repo() {
    if [ $# -ne 1 ]; then
        echo "Error: Invalid arguments to remove_repo() function"
        exit 1
    fi
    ORG_REPO="$1"
    REPO_NAME=$(basename "$ORG_REPO")
    if [ -d "$REPO_NAME" ]; then
        echo "Archiving repository: $REPO_NAME"
        "$ZIP_CMD" -rq "$REPO-$DATE.zip" "$REPO_NAME"
        rm -Rf "$REPO_NAME"
    fi
    if [ "$DEBUG" = "true" ]; then
        echo "Running: $GITHUB_CLI repo delete $ORG_REPO --yes"
    else
        echo "Removing forked repository: $REPO_NAME"
    fi
    if "$GITHUB_CLI" repo delete "$ORG_REPO" --yes; then
        SUCCESSES=$((SUCCESSES+1))
    else
        echo "Error: received return code $?"
        ERRORS=$((ERRORS+1))
    fi

}

delete_series() {
    # Set starting counter values for reporting
    ERRORS="0"; SUCCESSES="0"
    for ORG_REPO in "${REPOS_REMOVE_ARRAY[@]}"; do
        remove_repo "$ORG_REPO"
    done
    report_results
}

delete_parallel() {
    # Set some useful counters
    ERRORS="0"; SUCCESSES="0"
    # Send operations to GNU parallel from array
    "$PARALLEL_CMD" -j "$PARALLEL_THREADS" --env _ remove_repo ::: "${REPOS_REMOVE_ARRAY[@]}"
    report_results
}

fetch_repo() {
    if [ $# -ne 1 ]; then
        echo "Error: Invalid arguments to fetch_repo() function"
        exit 1
    fi
    ORG_REPO="$1"
    REPO_NAME=$(basename "$ORG_REPO")
    if [ "$DEBUG" = "true" ]; then
        echo "Running: $GITHUB_CLI repo $OPERATION $ORG_REPO $FLAGS"
    else
        echo "Fetching: $REPO_NAME"
    fi
    # shellcheck disable=SC2086
    if "$GITHUB_CLI" repo "$OPERATION" "$ORG_REPO" $FLAGS > /dev/null 2>&1; then
        SUCCESSES=$((SUCCESSES+1))
    else
        echo "Error: received return code $?"
        ERRORS=$((ERRORS+1))
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
    for ORG_REPO in "${REPOS_FETCH_ARRAY[@]}"; do
        fetch_repo "$ORG_REPO"
    done
    report_results
}

fetch_parallel() {
    # Set some useful counters
    ERRORS="0"; SUCCESSES="0"
    # Send operations to GNU parallel from array
    "$PARALLEL_CMD" --record-env
    "$PARALLEL_CMD" -j "$PARALLEL_THREADS" --env _ fetch_repo ::: "${REPOS_FETCH_ARRAY[@]}"
    report_results
}

export -f fetch_repo delete_parallel report_results

### Operations m###

# Make sure we are logged into GitHub
auth_check

# List all the repositories in the source ORG
printf "Querying repositories in SRC organisation: %s" "$SRC_GITHUB_ORG"
mapfile -t SRC_ORG_REPO_ARRAY < <(populate_repos_array "$SRC_GITHUB_ORG" "--no-archived --source" )
printf " [%s]\n" "${#SRC_ORG_REPO_ARRAY[@]}"

if [ "$OPERATION" = "fork" ]; then
    printf "Querying repositories in DST organisation: %s" "$DST_GITHUB_ORG"
    mapfile -t DST_ORG_REPO_ARRAY < <(populate_repos_array "$DST_GITHUB_ORG" "--no-archived")
    printf " [%s]\n" "${#DST_ORG_REPO_ARRAY[@]}"
else
    echo "Number of repositories: ${#SRC_ORG_REPO_ARRAY[@]}"
fi

# Set a counter
FETCH_COUNT="0"
for ORG_REPO in "${SRC_ORG_REPO_ARRAY[@]}"; do
    # Extract target folder/repository from composite that includes ORG
    REPO_NAME=$(basename "$ORG_REPO")
    if [ -d "$REPO_NAME" ] && ! check_arg_in_array "$DST_GITHUB_ORG/$REPO_NAME" "${DST_ORG_REPO_ARRAY[@]}"; then
        echo "Archiving existing folder for unforked repository: $REPO_NAME"
        echo "$ZIP_CMD -rq $REPO_NAME-$DATE.zip $REPO_NAME"
        "$ZIP_CMD" -rq "$REPO_NAME-$DATE.zip" "$REPO_NAME"
        mv "$REPO_NAME" "$REPO_NAME-$DATE"
        FETCH_COUNT=$((FETCH_COUNT+1))
        REPOS_FETCH_ARRAY[FETCH_COUNT]="$ORG_REPO"
    elif [ ! -d "$REPO_NAME" ]; then
        FETCH_COUNT=$((FETCH_COUNT+1))
        REPOS_FETCH_ARRAY[FETCH_COUNT]="$ORG_REPO"
    fi
done

if [ "$FETCH_COUNT" -gt 0 ]; then
    echo "Repositories to retrieve: [$FETCH_COUNT] "
    for ORG_REPO in "${REPOS_FETCH_ARRAY[@]}"; do
        REPO_NAME=$(basename "$ORG_REPO")
        echo "  $REPO_NAME"
    done
fi

REMOVE_COUNT="0"
if [ "$OPERATION" = "fork" ]; then
    # Check to see if there are duplicate forks in target repository
    for ORG_REPO in "${DST_ORG_REPO_ARRAY[@]}"; do
        REPO_NAME=$(basename "$ORG_REPO")
        check_arg_in_array "$SRC_GITHUB_ORG/$REPO_NAME" "${SRC_ORG_REPO_ARRAY[@]}"
        if [ $? -eq 1 ]; then
            REMOVE_COUNT=$((REMOVE_COUNT+1))
            REPOS_REMOVE_ARRAY[REMOVE_COUNT]="$ORG_REPO"
        fi
    done
    if [ "$REMOVE_COUNT" -ne 0 ]; then
        echo "Repositories to remove: [$REMOVE_COUNT]"
        for ORG_REPO in "${REPOS_REMOVE_ARRAY[@]}"; do
            REPO_NAME=$(basename "$ORG_REPO")
            echo "  $REPO_NAME"
        done
    fi
fi

if [ "$FETCH_COUNT" -ne 0 ] || [ "$REMOVE_COUNT" -ne 0 ]; then
    printf "Number of threads set to: %s" "$PARALLEL_THREADS"
    if [ "$PARALLEL_THREADS" -eq 1 ]; then
        echo " [running operations in serial]"
        fetch_series
        delete_series
    else
        echo " [running operations in parallel]"
        fetch_parallel
        delete_parallel
    fi
else
    echo "No repositories to fetch or remove"; exit 0
fi

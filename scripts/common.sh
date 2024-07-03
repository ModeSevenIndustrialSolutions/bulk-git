#!/usr/bin/env bash

### Debugging ###

# DEBUG="true"

### Functions ###

auth_check() {
    if ! ("$GITHUB_CLI" auth status > /dev/null ); then
        echo "You are not logged into GitHub"
        echo "Use the command:  gh auth login"
        echo "...then try this script again"; exit 1
    fi
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
export -f check_arg_in_array

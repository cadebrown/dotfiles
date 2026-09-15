#!/usr/bin/env bats

setup() {
    export LIMITS_TEMPLATE="$BATS_TEST_DIRNAME/../home/.chezmoitemplates/resource-limits.sh"
}

run_limits() {
    local shell_name="$1"
    shift
    run "$shell_name" -f -c '
        soft="$1" hard="$2" os_name="$3" mode="$4"
        uname() { printf "%s\\n" "$os_name"; }
        ulimit() {
            case "$1" in
                -Sn)
                    if [[ $# -eq 1 ]]; then
                        printf "%s\\n" "$soft"
                    elif [[ "$mode" == fail ]]; then
                        return 1
                    else
                        soft="$2"
                    fi
                    ;;
                -Hn) printf "%s\\n" "$hard" ;;
                *) return 2 ;;
            esac
        }
        source "$5"
        printf "limits=%s|%s\\n" "$soft" "$hard"
    ' _ "$@" "$LIMITS_TEMPLATE"
}

@test "Linux shell startup raises a low soft nofile limit without changing hard" {
    local shell_name
    for shell_name in bash zsh; do
        run_limits "$shell_name" 1024 1048576 Linux ok
        [ "$status" -eq 0 ]
        [ "$output" = 'limits=65536|1048576' ]
    done
}

@test "Linux shell startup preserves an already higher soft nofile limit" {
    local shell_name
    for shell_name in bash zsh; do
        run_limits "$shell_name" 131072 1048576 Linux ok
        [ "$status" -eq 0 ]
        [ "$output" = 'limits=131072|1048576' ]
    done
}

@test "Linux shell startup caps soft nofile at the unchanged hard limit" {
    local shell_name
    for shell_name in bash zsh; do
        run_limits "$shell_name" 1024 4096 Linux ok
        [ "$status" -eq 0 ]
        [[ "$output" == *'hard limit 4096 caps'* ]]
        [[ "$output" == *'limits=4096|4096' ]]
    done
}

@test "Linux shell startup warns when raising soft nofile fails" {
    local shell_name
    for shell_name in bash zsh; do
        run_limits "$shell_name" 1024 1048576 Linux fail
        [ "$status" -eq 0 ]
        [[ "$output" == *'could not raise soft nofile limit from 1024 to 65536'* ]]
        [[ "$output" == *'limits=1024|1048576' ]]
    done
}

@test "macOS shell startup leaves nofile limits unchanged" {
    local shell_name
    for shell_name in bash zsh; do
        run_limits "$shell_name" 1024 1048576 Darwin ok
        [ "$status" -eq 0 ]
        [ "$output" = 'limits=1024|1048576' ]
    done
}

@test "every login and interactive shell template applies the shared limit policy" {
    local template
    for template in dot_zprofile.tmpl dot_bash_profile.tmpl dot_zshrc.tmpl dot_bashrc.tmpl; do
        grep -Fq '{{ template "resource-limits.sh" . }}' "$BATS_TEST_DIRNAME/../home/$template"
    done
}

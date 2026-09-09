#!/usr/bin/env bats

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    TEST_HOME="$BATS_TEST_TMPDIR/home"
    FAKE_BIN="$BATS_TEST_TMPDIR/bin"
    CALLS="$BATS_TEST_TMPDIR/calls"
    mkdir -p "$TEST_HOME" "$FAKE_BIN"
    export HOME="$TEST_HOME"
    export PATH="$FAKE_BIN:/usr/bin:/bin"
    export CALLS

cat > "$FAKE_BIN/gcloud" <<'EOF'
#!/usr/bin/env bash
printf 'gcloud vertex-env=%s\n' "${GOOGLE_GENAI_USE_VERTEXAI:-}" >> "$CALLS"
printf 'gcloud %s\n' "$*" >> "$CALLS"
case "$*" in
    'auth list '* ) printf 'active@example.test\n' ;;
    'config get-value project') printf 'cli-project\n' ;;
esac
EOF
cat > "$FAKE_BIN/gemini" <<'EOF'
#!/usr/bin/env bash
printf 'gemini %s|%s|%s|%s\n' "$*" "${GEMINI_API_KEY:-}" "${GOOGLE_API_KEY:-}" "${GOOGLE_GENAI_USE_VERTEXAI:-}" >> "$CALLS"
EOF
    cat > "$FAKE_BIN/gws" <<'EOF'
#!/usr/bin/env bash
printf 'gws %s|%s|%s\n' "$*" "$GOOGLE_WORKSPACE_CLI_CLIENT_ID" "$GOOGLE_WORKSPACE_CLI_CLIENT_SECRET" >> "$CALLS"
EOF
cat > "$FAKE_BIN/jq" <<'EOF'
#!/usr/bin/env bash
file="${!#}"
case "$2" in
    *selectedType*) sed -n 's/.*"selectedType":"\([^"]*\)".*/\1/p' "$file" ;;
    *) sed -n 's/.*"quota_project_id":"\([^"]*\)".*/\1/p' "$file" ;;
esac
EOF
    chmod +x "$FAKE_BIN/gcloud" "$FAKE_BIN/gemini" "$FAKE_BIN/gws" "$FAKE_BIN/jq"
}

@test "gemini stores one Developer API key with private mode and masks it" {
    run bash "$REPO/install/auth.sh" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Gemini Developer API key (Gemini API, including Live)"* ]]
    [[ "$output" != *"gemini-live"* ]]

    run bash -c "printf '%s\\n' 'gemini-secret-1234' | bash '$REPO/install/auth.sh' gemini"

    [ "$status" -eq 0 ]
    [ -f "$HOME/.gemini.env" ]
    case "$(uname -s)" in
        Darwin) [ "$(stat -f '%Lp' "$HOME/.gemini.env")" = "600" ] ;;
        *) [ "$(stat -c '%a' "$HOME/.gemini.env")" = "600" ] ;;
    esac
    grep -Fqx 'export GEMINI_API_KEY=gemini-secret-1234' "$HOME/.gemini.env"
    [[ "$output" == *"Set GEMINI_API_KEY"* ]]

    run bash "$REPO/install/auth.sh" google-status
    [ "$status" -eq 0 ]
    [[ "$output" == *"configured"* ]]
    [[ "$output" != *"gemini-secret-1234"* ]]
}

@test "google-status reports key precedence and distinguishes CLI from ADC project state" {
    printf 'export GEMINI_API_KEY=gemini-secret-1234\n' > "$HOME/.gemini.env"
    chmod 600 "$HOME/.gemini.env"
    mkdir -p "$HOME/.config/gcloud" "$HOME/.gemini"
    printf '{"quota_project_id":"adc-project"}\n' > "$HOME/.config/gcloud/application_default_credentials.json"
    printf '{"security":{"auth":{"selectedType":"oauth-personal"}}}\n' > "$HOME/.gemini/settings.json"
    : > "$HOME/.gemini/oauth_creds.json"

    run env GOOGLE_API_KEY=override-key GOOGLE_CLOUD_QUOTA_PROJECT=override-project \
        bash "$REPO/install/auth.sh" google-status

    [ "$status" -eq 0 ]
    [[ "$output" == *"GOOGLE_API_KEY is set and takes precedence"* ]]
    [[ "$output" == *"active@example.test"* ]]
    [[ "$output" == *"cli-project"* ]]
    [[ "$output" == *"override-project"* ]]
    [[ "$output" == *"unverified local state"* ]]
    [[ "$output" == *"settings select oauth-personal"* ]]
    [[ "$output" == *"workspace-cli"* ]]
    [[ "$output" != *"gemini-secret-1234"* ]]
    [[ "$output" != *"override-key"* ]]
    ! grep -Fq 'application-default login' "$CALLS"
}

@test "google-status identifies an explicit credential-file override without dumping it" {
    local credential_file="$BATS_TEST_TMPDIR/credentials.json"
    printf '{"quota_project_id":"credential-project","refresh_token":"do-not-print"}\n' > "$credential_file"

    run env GOOGLE_APPLICATION_CREDENTIALS="$credential_file" \
        bash "$REPO/install/auth.sh" google-status

    [ "$status" -eq 0 ]
    [[ "$output" == *"credential-project"* ]]
    [[ "$output" == *"GOOGLE_APPLICATION_CREDENTIALS override"* ]]
    [[ "$output" != *"do-not-print"* ]]
    [[ "$output" != *"$credential_file"* ]]
}

@test "google-status reports an environment-only Gemini key and gcloud minting separately" {
    mkdir -p "$HOME/.config/gcloud"
    printf '{"quota_project_id":"adc-project"}\n' > "$HOME/.config/gcloud/application_default_credentials.json"

    run env GEMINI_API_KEY=environment-only-key bash "$REPO/install/auth.sh" google-status

    [ "$status" -eq 0 ]
    [[ "$output" == *"GEMINI_API_KEY is supplied by the environment"* ]]
    [[ "$output" != *"environment-only-key"* ]]

    run env GOOGLE_APPLICATION_CREDENTIALS="$HOME/.config/gcloud/application_default_credentials.json" \
        bash "$REPO/install/auth.sh" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"gcloud ADC refresh works"* ]]
    [[ "$output" == *"selected SDK ADC quota project adc-project"* ]]
}

@test "Gemini CLI and Google status dispatch together without an invented login flag" {
    run env GEMINI_API_KEY=inherited-key GOOGLE_API_KEY=inherited-google GOOGLE_GENAI_USE_VERTEXAI=true \
        bash "$REPO/install/auth.sh" gemini-cli google-status

    [ "$status" -eq 0 ]
    [[ "$output" == *"Launching without inherited Gemini API/Vertex settings"* ]]
    [[ "$output" == *'Select "Login with Google"'* ]]
    [[ "$output" == *'run `/auth` inside Gemini'* ]]
    grep -Fx 'gemini |||' "$CALLS"
    ! grep -Fq 'gemini auth' "$CALLS"
}

@test "workspace CLI login uses existing client credentials and read-only selected services" {
    cat > "$HOME/.google.env" <<'EOF'
export GOOGLE_OAUTH_CLIENT_ID=client\ id
export GOOGLE_OAUTH_CLIENT_SECRET=client\ secret
EOF

    run bash "$REPO/install/auth.sh" workspace-cli

    [ "$status" -eq 0 ]
    grep -Fx 'gws auth login --readonly -s drive,gmail,calendar|client id|client secret' "$CALLS"
    ! grep -Fq 'auth setup' "$CALLS"
}

@test "vertex command logs into ADC and only enables its API after opt-in" {
    run bash -c "printf 'y\\n' | bash '$REPO/install/auth.sh' vertex"

    [ "$status" -eq 0 ]
    grep -Fx 'gcloud auth application-default login' "$CALLS"
    grep -Fx 'gcloud services enable aiplatform.googleapis.com --project cli-project' "$CALLS"
    grep -Fx 'gcloud vertex-env=' "$CALLS"
}

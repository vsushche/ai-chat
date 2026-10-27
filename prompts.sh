#!/usr/bin/env bash
# System prompts (who the model is) for chat scripts (chat.sh, ask.sh).
# Source this file after llm.sh: it defines functions to list and load prompts
# from prompts/ and to start a conversation (prompt_start uses llm_generate).
#
# Prompt file format (prompts/<name>.txt):
#   description line(s)
#   user: NAME     (optional, user label in chat, default "You")
#   ai: NAME       (optional, model label in chat, default "AI")
#   ---            (3 or more dashes)
#   prompt body
#   --- intro      (optional, narrator text shown at start, not sent to the model)
#   --- greeting   (optional, fixed first line of the AI)
#   --- opening    (optional, instruction for the model how to start the conversation)
# Without a separator the whole file is the body and the name is the description.

PROMPTS_DIR="prompts"
PROMPT_SEPARATOR='^---+[[:space:]]*$'
PROMPT_SECTION_SEPARATOR='^---+[[:space:]]+(intro|greeting|opening)([[:space:]]+-+)?[[:space:]]*$'
PROMPT_LABEL_KEYS='^(user|ai)[[:space:]]*:'

# Hidden user turns are marked as director notes, the rule is added to the system prompt
DIRECTOR_RULE="Messages marked [DIRECTOR NOTE] come from the game director, not from the user. The user cannot see them. Follow them, but never quote, mention or answer them directly. The user's first message is the first message without this mark."
SESSION_STARTED_NOTE="The user has just started the session."

PROMPT_RED='\033[0;31m'
PROMPT_RESET='\033[0m'

# Print prompt names (without .txt), one per line
prompt_names() {
    local file
    for file in "$PROMPTS_DIR"/*.txt; do
        [[ -f "$file" ]] || continue
        file="${file##*/}"
        printf '%s\n' "${file%.txt}"
    done
}

# Print prompt description (lines before the separator except labels, joined with spaces)
# $1 - prompt name
prompt_description() {
    local file="$PROMPTS_DIR/${1%.txt}.txt"
    if grep -qE "$PROMPT_SEPARATOR" "$file"; then
        awk -v sep_re="$PROMPT_SEPARATOR" -v key_re="$PROMPT_LABEL_KEYS" \
            '$0 ~ sep_re {exit} tolower($0) ~ key_re {next} NF {printf "%s%s", sep, $0; sep=" "}' "$file"
        printf '\n'
    else
        printf '%s\n' "${1%.txt}"
    fi
}

# Print a section of the prompt (leading blank lines skipped)
# $1 - prompt name, $2 - section: intro, greeting, opening or empty for the body
prompt_section() {
    local file="$PROMPTS_DIR/${1%.txt}.txt"
    if ! grep -qE "$PROMPT_SEPARATOR" "$file"; then
        [[ -z "$2" ]] && cat "$file"
        return 0
    fi
    awk -v sep_re="$PROMPT_SEPARATOR" -v sec_re="$PROMPT_SECTION_SEPARATOR" -v want="$2" '
        !header_done {if ($0 ~ sep_re) header_done = 1; next}
        $0 ~ sec_re {current = $0; sub(/^-+[[:space:]]+/, "", current); sub(/[[:space:]].*$/, "", current); started = 0; next}
        current == want && (NF || started) {started = 1; print}' "$file"
}

# Print prompt body (lines after the separator up to the first named section)
# $1 - prompt name
prompt_body() {
    prompt_section "$1" ""
}

# Print label from the prompt header (empty if not set)
# $1 - prompt name, $2 - key: user or ai
prompt_label() {
    local file="$PROMPTS_DIR/${1%.txt}.txt"
    grep -qE "$PROMPT_SEPARATOR" "$file" || return 0
    awk -v sep_re="$PROMPT_SEPARATOR" -v key_re="^$2[[:space:]]*:" '
        $0 ~ sep_re {exit}
        tolower($0) ~ key_re {sub(/^[^:]*:[[:space:]]*/, ""); sub(/[[:space:]]+$/, ""); print; exit}' "$file"
}

# Print "name  description" for every prompt
prompt_list() {
    local name
    while IFS= read -r name; do
        printf '  %-12s %s\n' "$name" "$(prompt_description "$name")"
    done < <(prompt_names)
}

# Load prompt into SYSTEM_PROMPT, set PROMPT_NAME, PROMPT_USER_LABEL, PROMPT_AI_LABEL,
# PROMPT_INTRO, PROMPT_GREETING, PROMPT_OPENING
# $1 - prompt name (with or without .txt)
# On failure prints an error to stderr and returns 1.
prompt_load() {
    local name="${1%.txt}"
    if [[ ! -f "$PROMPTS_DIR/$name.txt" ]]; then
        echo "Error: prompt '$name' not found in $PROMPTS_DIR/." >&2
        return 1
    fi
    PROMPT_NAME="$name"
    SYSTEM_PROMPT=$(prompt_body "$name")
    PROMPT_USER_LABEL=$(prompt_label "$name" user)
    PROMPT_AI_LABEL=$(prompt_label "$name" ai)
    PROMPT_USER_LABEL="${PROMPT_USER_LABEL:-You}"
    PROMPT_AI_LABEL="${PROMPT_AI_LABEL:-AI}"
    PROMPT_INTRO=$(prompt_section "$name" intro)
    PROMPT_GREETING=$(prompt_section "$name" greeting)
    PROMPT_OPENING=$(prompt_section "$name" opening)

    if [[ -n "$PROMPT_GREETING" && -n "$PROMPT_OPENING" ]]; then
        printf '%bWarning: prompt '\''%s'\'' has both greeting and opening, using greeting.%b\n' \
            "$PROMPT_RED" "$name" "$PROMPT_RESET" >&2
        PROMPT_OPENING=""
    fi

    # The conversation will start with a hidden director note - explain it to the model
    if [[ -n "$PROMPT_GREETING" || -n "$PROMPT_OPENING" ]]; then
        SYSTEM_PROMPT+=$'\n\n'"$DIRECTOR_RULE"
    fi
}

# Print one history turn as compact JSON
# $1 - role: user or model, $2 - text
prompt_turn() {
    jq -nc --arg role "$1" --arg text "$2" '{role: $role, parts: [{text: $text}]}'
}

# Start the conversation for the loaded prompt: greeting or opening.
# Sets PROMPT_START_TEXT (first AI line, empty if none) and
# PROMPT_START_HISTORY (hidden director note + first AI line, JSON turns).
# $1 - optional safetySettings for llm_generate
# Returns 1 if the opening request failed (error is printed by llm_generate).
prompt_start() {
    local note
    PROMPT_START_TEXT=""
    PROMPT_START_HISTORY=()

    if [[ -n "$PROMPT_GREETING" ]]; then
        note="[DIRECTOR NOTE - not visible to the user: $SESSION_STARTED_NOTE]"
        PROMPT_START_TEXT="$PROMPT_GREETING"
    elif [[ -n "$PROMPT_OPENING" ]]; then
        note="[DIRECTOR NOTE - not visible to the user: $PROMPT_OPENING]"
        PROMPT_START_TEXT=$(llm_generate "$(llm_history_json "$(prompt_turn user "$note")")" "${1:-}") || return 1
    else
        return 0
    fi

    PROMPT_START_HISTORY=("$(prompt_turn user "$note")" "$(prompt_turn model "$PROMPT_START_TEXT")")
}

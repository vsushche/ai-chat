#!/usr/bin/env bash
# System prompts (who the model is) for chat scripts (chat.sh, ask.sh).
# Source this file: it defines functions to list and load prompts from prompts/.
#
# Prompt file format (prompts/<name>.txt):
#   description line(s)
#   user: NAME     (optional, user label in chat, default "You")
#   ai: NAME       (optional, model label in chat, default "AI")
#   ---            (3 or more dashes)
#   prompt body
# Without a separator the whole file is the body and the name is the description.

PROMPTS_DIR="prompts"
PROMPT_SEPARATOR='^---+[[:space:]]*$'
PROMPT_LABEL_KEYS='^(user|ai)[[:space:]]*:'

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

# Print prompt body (lines after the separator, leading blank lines skipped)
# $1 - prompt name
prompt_body() {
    local file="$PROMPTS_DIR/${1%.txt}.txt"
    if grep -qE "$PROMPT_SEPARATOR" "$file"; then
        awk -v sep_re="$PROMPT_SEPARATOR" 'body && (NF || started) {started=1; print; next} $0 ~ sep_re {body=1}' "$file"
    else
        cat "$file"
    fi
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

# Load prompt into SYSTEM_PROMPT, set PROMPT_NAME, PROMPT_USER_LABEL, PROMPT_AI_LABEL
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
}

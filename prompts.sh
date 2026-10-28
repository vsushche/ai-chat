#!/usr/bin/env bash
# System prompts (who the model is) for chat scripts (chat.sh, ask.sh).
# Source this file after llm.sh: it defines functions to list and load prompts
# from prompts/ and to start a conversation.
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

PROMPTS_DIR="prompts"
PROMPT_SEPARATOR='^---+[[:space:]]*$'
PROMPT_SECTION_SEPARATOR='^---+[[:space:]]+(intro|greeting|opening)([[:space:]]+-+)?[[:space:]]*$'
PROMPT_LABEL_KEYS='^(user|ai)[[:space:]]*:'

# Hidden user turns are marked as director notes, the rule is added to the system prompt
DIRECTOR_RULE="Messages marked [DIRECTOR NOTE] come from the game director, not from the user. The user cannot see them. Follow them, but never quote, mention or answer them directly. The user's first message is the first message without this mark."
SESSION_STARTED_NOTE="The user has just started the session."

# Print prompt names (without .txt), one per line
prompt_names() {
    local file
    for file in "$PROMPTS_DIR"/*.txt; do
        file="${file##*/}"
        printf '%s\n' "${file%.txt}"
    done
}

# Print prompt description (lines before the separator except labels, joined with spaces)
# $1 - prompt name
prompt_description() {
    awk -v sep_re="$PROMPT_SEPARATOR" -v key_re="$PROMPT_LABEL_KEYS" '
        $0 ~ sep_re {exit}
        tolower($0) ~ key_re {next}
        NF {printf "%s%s", sep, $0; sep = " "}
        END {print ""}' "$PROMPTS_DIR/$1.txt"
}

# Print a section of the prompt (leading blank lines skipped)
# $1 - prompt name, $2 - section: intro, greeting, opening or empty for the body
prompt_section() {
    awk -v sep_re="$PROMPT_SEPARATOR" -v sec_re="$PROMPT_SECTION_SEPARATOR" -v want="$2" '
        !header_done {if ($0 ~ sep_re) header_done = 1; next}
        $0 ~ sec_re {current = $0; sub(/^-+[[:space:]]+/, "", current); sub(/[[:space:]].*$/, "", current); started = 0; next}
        current == want && (NF || started) {started = 1; print}' "$PROMPTS_DIR/$1.txt"
}

# Print label from the prompt header (empty if not set)
# $1 - prompt name, $2 - key: user or ai
prompt_label() {
    awk -v sep_re="$PROMPT_SEPARATOR" -v key_re="^$2[[:space:]]*:" '
        $0 ~ sep_re {exit}
        tolower($0) ~ key_re {sub(/^[^:]*:[[:space:]]*/, ""); sub(/[[:space:]]+$/, ""); print; exit}' "$PROMPTS_DIR/$1.txt"
}

# Print "name  description" for every prompt
prompt_list() {
    local name
    for name in $(prompt_names); do
        printf '  %-12s %s\n' "$name" "$(prompt_description "$name")"
    done
}

# Load prompt into SYSTEM_PROMPT, set PROMPT_NAME, PROMPT_USER_LABEL, PROMPT_AI_LABEL,
# PROMPT_INTRO, PROMPT_GREETING, PROMPT_OPENING
# $1 - prompt name
# On failure prints an error to stderr and returns 1.
prompt_load() {
    if [[ ! -f "$PROMPTS_DIR/$1.txt" ]]; then
        echo "Error: prompt '$1' not found in $PROMPTS_DIR/." >&2
        return 1
    fi
    PROMPT_NAME="$1"
    SYSTEM_PROMPT=$(prompt_section "$1" "")
    PROMPT_USER_LABEL=$(prompt_label "$1" user)
    PROMPT_USER_LABEL="${PROMPT_USER_LABEL:-You}"
    PROMPT_AI_LABEL=$(prompt_label "$1" ai)
    PROMPT_AI_LABEL="${PROMPT_AI_LABEL:-AI}"
    PROMPT_INTRO=$(prompt_section "$1" intro)
    PROMPT_GREETING=$(prompt_section "$1" greeting)
    PROMPT_OPENING=$(prompt_section "$1" opening)

    if [[ -n "$PROMPT_GREETING" && -n "$PROMPT_OPENING" ]]; then
        llm_error "Warning: prompt '$1' has both greeting and opening, using greeting."
        PROMPT_OPENING=""
    fi

    # The conversation will start with a hidden director note - explain it to the model
    if [[ -n "$PROMPT_GREETING" || -n "$PROMPT_OPENING" ]]; then
        SYSTEM_PROMPT+=$'\n\n'"$DIRECTOR_RULE"
    fi
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
        PROMPT_START_TEXT=$(llm_generate "$(llm_history_json "$(llm_turn user "$note")")" "${1:-}") || return 1
    else
        return 0
    fi

    PROMPT_START_HISTORY=("$(llm_turn user "$note")" "$(llm_turn model "$PROMPT_START_TEXT")")
}

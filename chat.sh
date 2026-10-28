#!/usr/bin/env bash

# Set BASH "strict mode"
# -e: exit immediately if a command exits with an error
# -u: treat usage of undeclared variables as an error
# -o pipefail: the return code of a pipeline will be equal to the code of the last command that failed
set -euo pipefail

# --- CONFIGURATION ---

# Shared LLM access: provider from .env (llm_generate, llm_turn, PROVIDER, LLM_MODEL)
. ./llm.sh

# System prompts from prompts/ (prompt_load, prompt_start, prompt_names, prompt_description)
. ./prompts.sh

# Color codes for terminal output
GREEN='\033[0;32m'   # AI replies
CYAN='\033[0;36m'    # intro (narrator)
YELLOW='\033[0;33m'  # system messages
RESET='\033[0m'

# We disable blocking for safety reasons (for personal use)
SAFETY_SETTINGS='[
    {"category": "HARM_CATEGORY_SEXUALLY_EXPLICIT", "threshold": "BLOCK_NONE"},
    {"category": "HARM_CATEGORY_HATE_SPEECH", "threshold": "BLOCK_NONE"},
    {"category": "HARM_CATEGORY_HARASSMENT", "threshold": "BLOCK_NONE"},
    {"category": "HARM_CATEGORY_DANGEROUS_CONTENT", "threshold": "BLOCK_NONE"}
]'

# --- CHAT LOGIC ---

# Typewriter effect - prints text character by character
# $1 - text, $2 - delay in seconds per character, $3 - color code
typewriter() {
    local text="$1" delay="$2" color="$3" i
    printf "%b" "$color"
    for (( i=0; i<${#text}; i++ )); do
        printf "%s" "${text:$i:1}"
        sleep "$delay"
    done
    printf "%b\n" "$RESET"
}

# System message (banner, menu, hints) - fast typewriter in yellow
say() {
    typewriter "$1" 0.005 "$YELLOW"
}

# Menu to choose who to talk to - sets PROMPT
# Returns 1 on Ctrl+D (EOF)
choose_prompt() {
    local names=() i choice
    mapfile -t names < <(prompt_names)

    say "Who do you want to talk to?"
    for i in "${!names[@]}"; do
        say "$((i + 1))) ${names[i]} - $(prompt_description "${names[i]}")"
    done

    while true; do
        read -e -r -p "Choose [1-${#names[@]}]: " choice || return 1
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#names[@]} )); then
            PROMPT="${names[choice - 1]}"
            return 0
        fi
        say "Invalid choice."
    done
}

# Array to store conversation history.
# Each element is a JSON object created by llm_turn
history=()

say "=========================================="
say "   LLM Chat"
say "   Powered by ${PROVIDER} (${LLM_MODEL})"
say "=========================================="

# Prompt from PROMPT in .env, otherwise let the user choose
if [[ -z "${PROMPT:-}" ]]; then
    if ! choose_prompt; then
        echo
        say "Goodbye!"
        exit 0
    fi
fi
prompt_load "$PROMPT"

say "=========================================="
say "Talking to: $(prompt_description "$PROMPT_NAME")"
say "Type 'exit' or press Ctrl+D to terminate."
say "=========================================="

# Intro from the narrator: shown only, not sent to the model
if [[ -n "$PROMPT_INTRO" ]]; then
    echo
    typewriter "$PROMPT_INTRO" 0.02 "$CYAN"
fi

# First AI line: fixed greeting or generated from the opening instruction
if prompt_start "$SAFETY_SETTINGS" && [[ -n "$PROMPT_START_TEXT" ]]; then
    echo
    typewriter "$PROMPT_AI_LABEL: $PROMPT_START_TEXT" 0.02 "$GREEN"
    history+=("${PROMPT_START_HISTORY[@]}")
fi

# Infinite loop for chat
while true; do
    # 1. Read user input
    # -e: readline editing (Backspace, arrows), -r: keep backslashes as typed
    read -e -r -p "${PROMPT_USER_LABEL}: " user_prompt

    # Check for Ctrl+D (EOF) or "exit" command
    if [[ -z "$user_prompt" ]] || [[ "$user_prompt" == "exit" ]]; then
        say "Goodbye!"
        break
    fi

    # 2. Add user request to history
    history+=("$(llm_turn user "$user_prompt")")

    # 3. Send complete history to the model
    if ! model_text=$(llm_generate "$(llm_history_json "${history[@]}")" "$SAFETY_SETTINGS"); then
        # Remove last (failed) user request from history
        unset 'history[${#history[@]}-1]'
        continue
    fi

    # 4. Output response and add to history
    typewriter "$PROMPT_AI_LABEL: $model_text" 0.02 "$GREEN"
    history+=("$(llm_turn model "$model_text")")

done

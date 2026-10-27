#!/usr/bin/env bash

# Set BASH "strict mode"
# -e: exit immediately if a command exits with an error
# -u: treat usage of undeclared variables as an error
# -o pipefail: the return code of a pipeline will be equal to the code of the last command that failed
set -euo pipefail

# --- CONFIGURATION ---

# Shared LLM access: provider from .env (llm_generate, LLM_PROVIDER, LLM_MODEL)
. ./llm.sh

# System prompts from prompts/ (prompt_load, prompt_names, prompt_description)
. ./prompts.sh

# Color codes for terminal output
GREEN='\033[0;32m'
RESET='\033[0m'

# We disable blocking for safety reasons (for personal use)
SAFETY_SETTINGS='[
    {"category": "HARM_CATEGORY_SEXUALLY_EXPLICIT", "threshold": "BLOCK_NONE"},
    {"category": "HARM_CATEGORY_HATE_SPEECH", "threshold": "BLOCK_NONE"},
    {"category": "HARM_CATEGORY_HARASSMENT", "threshold": "BLOCK_NONE"},
    {"category": "HARM_CATEGORY_DANGEROUS_CONTENT", "threshold": "BLOCK_NONE"}
]'

# --- CHAT LOGIC ---

# Typewriter effect function - prints text character by character
typewriter() {
    local text="$1"
    local delay="${2:-0.03}"  # Default 0.03 seconds per character
    local color="${3:-}"       # Optional color code
    local i
    
    # Print color code if provided
    [[ -n "$color" ]] && printf "%b" "$color"
    
    for (( i=0; i<${#text}; i++ )); do
        printf "%s" "${text:$i:1}"
        sleep "$delay"
    done
    
    # Reset color if it was set
    [[ -n "$color" ]] && printf "%b" "$RESET"
    printf "\n"
}

# Menu to choose who to talk to - sets PROMPT_FILE
# Returns 1 on Ctrl+D (EOF)
choose_prompt() {
    local names=() labels=() name label
    mapfile -t names < <(prompt_names)
    if [[ ${#names[@]} -eq 0 ]]; then
        echo "Error: no prompts found in $PROMPTS_DIR/." >&2
        exit 1
    fi
    for name in "${names[@]}"; do
        labels+=("$name - $(prompt_description "$name")")
    done

    echo "Who do you want to talk to?"
    PS3="Choose [1-${#names[@]}]: "
    select label in "${labels[@]}"; do
        if [[ -n "$label" ]]; then
            PROMPT_FILE="${names[REPLY-1]}"
            return 0
        fi
        echo "Invalid choice."
    done
    return 1
}

# Array to store conversation history.
# Each element is a JSON object created by 'jq'
declare -a history=()

echo "=========================================="
echo "   LLM Chat"
echo "   Powered by ${LLM_PROVIDER} (${LLM_MODEL})"
echo "=========================================="

# Prompt from PROMPT_FILE in .env, otherwise let the user choose
if [[ -z "${PROMPT_FILE:-}" ]]; then
    if ! choose_prompt; then
        echo
        echo "Goodbye!"
        exit 0
    fi
fi
prompt_load "$PROMPT_FILE" || exit 1

echo "=========================================="
echo "Talking to: $(prompt_description "$PROMPT_NAME")"
echo "Type 'exit' or press Ctrl+D to terminate."
echo "=========================================="

# Infinite loop for chat
while true; do
    # 1. Read user input
    # -e: readline editing (Backspace, arrows), -r: keep backslashes as typed
    read -e -r -p "${PROMPT_USER_LABEL}: " user_prompt

    # Check for Ctrl+D (EOF) or "exit" command
    if [[ -z "$user_prompt" ]] || [[ "$user_prompt" == "exit" ]]; then
        echo "Goodbye!"
        break
    fi

    # 2. Add user request to history
    user_json=$(jq -n --arg text "$user_prompt" '{role: "user", parts: [{text: $text}]}')
    history+=("$user_json")

    # 3. Send complete history to the model
    if ! model_text=$(llm_generate "$(llm_history_json "${history[@]}")" "$SAFETY_SETTINGS"); then
        # Remove last (failed) user request from history
        unset 'history[${#history[@]}-1]'
        continue
    fi

    # 4. Output response and add to history
    printf "%b%s: %b" "$GREEN" "$PROMPT_AI_LABEL" "$RESET"
    typewriter "$model_text" 0.02 "$GREEN"
    model_json=$(jq -n --arg text "$model_text" '{role: "model", parts: [{text: $text}]}')
    history+=("$model_json")

done

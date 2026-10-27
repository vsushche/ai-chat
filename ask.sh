#!/usr/bin/env bash

set -euo pipefail

# --- CONFIGURATION ---

# Shared LLM access: provider from .env (llm_generate, LLM_PROVIDER, LLM_MODEL)
. ./llm.sh

# System prompts from prompts/ (prompt_load, prompt_list)
. ./prompts.sh

SESSION_FILE="session.txt"

usage() {
    if [[ -n "${PROMPT_FILE:-}" ]]; then
        echo "Usage: $0 \"your question here\"   (prompt '${PROMPT_FILE%.txt}' from .env)"
    else
        echo "Usage: $0 <prompt> \"your question here\""
    fi
    echo "       $0 --reset   (start a new session)"
    echo "Session persists across calls."
}

# --- RESET SESSION ---
if [[ "${1:-}" == "--reset" ]]; then
    > "$SESSION_FILE"
    echo "Session reset."
    exit 0
fi

# --- NO ARGUMENT: LIST PROMPTS ---
if [[ $# -eq 0 ]]; then
    echo "=========================================="
    echo "   LLM Session Chat"
    echo "   Model: ${LLM_PROVIDER} (${LLM_MODEL})"
    echo "=========================================="
    usage
    echo
    echo "Available prompts:"
    prompt_list
    exit 0
fi

# --- SELECT PROMPT ---
# Prompt from PROMPT_FILE in .env, otherwise from the first argument
if [[ -n "${PROMPT_FILE:-}" ]]; then
    prompt_name="$PROMPT_FILE"
else
    prompt_name="$1"
    shift
fi

if ! prompt_load "$prompt_name"; then
    echo "Available prompts:" >&2
    prompt_list >&2
    exit 1
fi

if [[ $# -eq 0 ]]; then
    echo "Error: no question given." >&2
    usage >&2
    exit 1
fi

# --- LOAD HISTORY ---
declare -a history=()
if [[ -f "$SESSION_FILE" && -s "$SESSION_FILE" ]]; then
    while IFS= read -r line; do
        history+=("$line")
    done < "$SESSION_FILE"
fi

# --- ADD USER QUESTION ---
user_prompt="$*"
user_json=$(jq -nc --arg text "$user_prompt" '{role: "user", parts: [{text: $text}]}')
history+=("$user_json")

# --- CALL API ---
if ! model_text=$(llm_generate "$(llm_history_json "${history[@]}")"); then
    exit 1
fi

# --- OUTPUT AND SAVE ---
echo "$model_text"

model_json=$(jq -nc --arg text "$model_text" '{role: "model", parts: [{text: $text}]}')
history+=("$model_json")

# Save to session file
> "$SESSION_FILE"
for item in "${history[@]}"; do
    echo "$item" >> "$SESSION_FILE"
done

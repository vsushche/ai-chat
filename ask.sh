#!/usr/bin/env bash

set -euo pipefail

# --- CONFIGURATION ---

# Shared LLM access: provider from .env (llm_generate, llm_turn, PROVIDER, LLM_MODEL)
. ./llm.sh

# System prompts from prompts/ (prompt_load, prompt_start, prompt_list)
. ./prompts.sh

# One session file per prompt: sessions/<prompt>.jsonl (one JSON turn per line)
SESSIONS_DIR="sessions"

usage() {
    if [[ -n "${PROMPT:-}" ]]; then
        echo "Usage: $0 \"your question here\"   (prompt '$PROMPT' from .env)"
        echo "       $0 --reset   (new session: show intro and first AI line)"
    else
        echo "Usage: $0 <prompt> \"your question here\""
        echo "       $0 --reset <prompt>   (new session: show intro and first AI line)"
    fi
    echo "Each prompt has its own session in $SESSIONS_DIR/, it persists across calls."
}

# Load prompt and set SESSION_FILE; if not found, list prompts and exit
# $1 - prompt name
load_prompt() {
    if ! prompt_load "$1"; then
        echo "Available prompts:" >&2
        prompt_list >&2
        exit 1
    fi
    mkdir -p "$SESSIONS_DIR"
    SESSION_FILE="$SESSIONS_DIR/$PROMPT_NAME.jsonl"
}

# --- RESET SESSION ---
# Reset the session of one prompt (argument or PROMPT) and start the conversation
if [[ "${1:-}" == "--reset" ]]; then
    prompt_name="${2:-${PROMPT:-}}"
    if [[ -z "$prompt_name" ]]; then
        echo "Error: no prompt given for --reset." >&2
        usage >&2
        exit 1
    fi
    load_prompt "$prompt_name"
    > "$SESSION_FILE"
    echo "Session '$PROMPT_NAME' reset."

    if [[ -n "$PROMPT_INTRO" ]]; then
        echo
        echo "$PROMPT_INTRO"
    fi
    prompt_start
    if [[ -n "$PROMPT_START_TEXT" ]]; then
        echo
        echo "$PROMPT_START_TEXT"
        printf '%s\n' "${PROMPT_START_HISTORY[@]}" > "$SESSION_FILE"
    fi
    exit 0
fi

# --- NO ARGUMENT: LIST PROMPTS ---
if [[ $# -eq 0 ]]; then
    echo "=========================================="
    echo "   LLM Session Chat"
    echo "   Model: ${PROVIDER} (${LLM_MODEL})"
    echo "=========================================="
    usage
    echo
    echo "Available prompts:"
    prompt_list
    exit 0
fi

# --- SELECT PROMPT ---
# Prompt from PROMPT in .env, otherwise from the first argument
if [[ -n "${PROMPT:-}" ]]; then
    load_prompt "$PROMPT"
else
    load_prompt "$1"
    shift
fi

if [[ $# -eq 0 ]]; then
    echo "Error: no question given." >&2
    usage >&2
    exit 1
fi

# --- LOAD HISTORY AND ADD USER QUESTION ---
history=()
if [[ -s "$SESSION_FILE" ]]; then
    mapfile -t history < "$SESSION_FILE"
fi
history+=("$(llm_turn user "$*")")

# --- CALL API ---
model_text=$(llm_generate "$(llm_history_json "${history[@]}")")

# --- OUTPUT AND SAVE ---
echo "$model_text"
history+=("$(llm_turn model "$model_text")")
printf '%s\n' "${history[@]}" > "$SESSION_FILE"

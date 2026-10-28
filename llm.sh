#!/usr/bin/env bash
# LLM access for chat scripts (chat.sh, ask.sh).
# Source this file: it loads .env, picks the provider from PROVIDER (gemini|openai,
# default gemini) and defines llm_error, llm_turn, llm_history_json and llm_generate.
# Sets LLM_MODEL for display.

. ./.env

# Check for required utilities
for tool in curl jq; do
    if ! command -v "$tool" &> /dev/null; then
        echo "Error: '$tool' not found. Please install it." >&2
        exit 1
    fi
done

# Print an error message in red to stderr
llm_error() {
    printf '\033[0;31m%s\033[0m\n' "$*" >&2
}

# Print one history turn as compact JSON
# $1 - role: user or model, $2 - text
llm_turn() {
    jq -nc --arg role "$1" --arg text "$2" '{role: $role, parts: [{text: $text}]}'
}

# Join JSON turns (one per argument) into a JSON array
llm_history_json() {
    printf '%s\n' "$@" | jq -sc .
}

PROVIDER="${PROVIDER:-gemini}"

case "$PROVIDER" in
    gemini) . ./gemini.sh; LLM_MODEL="$GEMINI_MODEL" ;;
    openai) . ./openai.sh; LLM_MODEL="$OPENAI_MODEL" ;;
    *)
        echo "Error: unknown PROVIDER '$PROVIDER' in .env (use 'gemini' or 'openai')." >&2
        exit 1
        ;;
esac

# Send conversation to the provider (gemini_generate or openai_generate)
llm_generate() {
    "${PROVIDER}_generate" "$@"
}

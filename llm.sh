#!/usr/bin/env bash
# LLM provider selection for chat scripts (chat.sh, ask.sh).
# Source this file: it reads PROVIDER from .env (gemini|openai, default gemini),
# sources the matching provider file and defines llm_history_json and llm_generate.
# Sets LLM_PROVIDER and LLM_MODEL for display.

. ./.env

LLM_PROVIDER="${PROVIDER:-gemini}"

case "$LLM_PROVIDER" in
    gemini)
        . ./gemini.sh
        LLM_MODEL="$GEMINI_MODEL"
        llm_history_json() { gemini_history_json "$@"; }
        llm_generate() { gemini_generate "$@"; }
        ;;
    openai)
        . ./openai.sh
        LLM_MODEL="$OPENAI_MODEL"
        llm_history_json() { openai_history_json "$@"; }
        llm_generate() { openai_generate "$@"; }
        ;;
    *)
        echo "Error: unknown PROVIDER '$LLM_PROVIDER' in .env (use 'gemini' or 'openai')." >&2
        exit 1
        ;;
esac

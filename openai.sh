#!/usr/bin/env bash
# Shared OpenAI API access for chat scripts (chat.sh, ask.sh).
# Source this file: it loads .env, sets the model,
# and defines openai_history_json and openai_generate.
# Expects SYSTEM_PROMPT to be set (see prompts.sh: prompt_load).
# History uses the same format as gemini.sh ({role: "user"|"model", parts: [{text}]}).

# --- CONFIGURATION ---

# .env provides OPENAI_API_KEY and optionally OPENAI_MODEL
. ./.env

OPENAI_MODEL="${OPENAI_MODEL:-gpt-5-mini}"
OPENAI_API_URL="https://api.openai.com/v1/chat/completions"

# --- TOOLS CHECK ---

# Check for required utilities
for tool in curl jq; do
    if ! command -v "$tool" &> /dev/null; then
        echo "Error: '$tool' not found. Please install it." >&2
        exit 1
    fi
done

# --- API ---

# Join JSON objects (one per argument) into a JSON array string
openai_history_json() {
    local json="[" item
    for item in "$@"; do
        json+="$item,"
    done
    printf '%s' "${json%,}]"
}

# Send conversation to OpenAI and print the model's reply text.
# $1 - JSON array of contents (conversation history)
# $2 - ignored (Gemini safetySettings, accepted for compatibility)
# On failure prints an error to stderr and returns 1.
openai_generate() {
    local contents="$1"
    local payload response api_error model_text
    local curl_exit_code=0

    # Convert history to OpenAI messages: "model" role becomes "assistant"
    payload=$(jq -n --argjson hist "$contents" --arg model "$OPENAI_MODEL" --arg sys_prompt "$SYSTEM_PROMPT" \
        '{
            model: $model,
            messages: (
                [{role: "system", content: $sys_prompt}]
                + [$hist[] | {
                    role: (if .role == "model" then "assistant" else .role end),
                    content: ([.parts[].text] | join(""))
                  }]
            )
        }') || return 1

    response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        -d "$payload" "$OPENAI_API_URL") || curl_exit_code=$?

    # Handle curl error (e.g., no network)
    if [[ $curl_exit_code -ne 0 ]]; then
        echo "OpenAI Error (curl): Failed to connect to API. Error code: $curl_exit_code" >&2
        return 1
    fi

    # Look for error in API response (e.g., invalid key)
    api_error=$(echo "$response" | jq -r '.error.message // empty')
    if [[ -n "$api_error" ]]; then
        echo "OpenAI Error (API): $api_error" >&2
        return 1
    fi

    # `.choices[0].message.content` - standard path to the response
    model_text=$(echo "$response" | jq -r '.choices[0].message.content // empty')

    # Check for empty response (e.g., refusal or content filter)
    if [[ -z "$model_text" ]]; then
        echo "OpenAI Error: Received empty or unexpected response." >&2
        echo "RAW response: $response" >&2
        return 1
    fi

    printf '%s\n' "$model_text"
}

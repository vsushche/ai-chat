#!/usr/bin/env bash
# Shared Gemini API access for chat scripts (chat.sh, ask.sh).
# Source this file: it loads .env, sets the model,
# and defines gemini_history_json and gemini_generate.
# Expects SYSTEM_PROMPT to be set (see prompts.sh: prompt_load).

# --- CONFIGURATION ---

# .env provides GEMINI_API_KEY and optionally GEMINI_MODEL
. ./.env

GEMINI_MODEL="${GEMINI_MODEL:-gemini-flash-latest}"
API_URL="https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent"

# --- TOOLS CHECK ---

# Check for required utilities
for tool in curl jq; do
    if ! command -v "$tool" &> /dev/null; then
        echo "Error: '$tool' not found. Please install it." >&2
        exit 1
    fi
done

# --- API ---

# Print an error message in red to stderr
gemini_error() {
    printf '\033[0;31m%s\033[0m\n' "$*" >&2
}

# Join JSON objects (one per argument) into a JSON array string
gemini_history_json() {
    local json="[" item
    for item in "$@"; do
        json+="$item,"
    done
    printf '%s' "${json%,}]"
}

# Send conversation to Gemini and print the model's reply text.
# $1 - JSON array of contents (conversation history)
# $2 - optional JSON array of safetySettings
# On failure prints an error to stderr and returns 1.
gemini_generate() {
    local contents="$1"
    local safety="${2:-null}"
    local payload response api_error model_text
    local curl_exit_code=0

    # Build request with 'jq' for safe JSON formatting
    # System instruction makes the model adopt the role from the prompt
    payload=$(jq -n --argjson hist "$contents" --argjson safety "$safety" --arg sys_prompt "$SYSTEM_PROMPT" \
        '{
            systemInstruction: {
                parts: [{text: $sys_prompt}]
            },
            contents: $hist
        } + (if $safety then {safetySettings: $safety} else {} end)') || return 1

    response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "x-goog-api-key: $GEMINI_API_KEY" \
        -d "$payload" "$API_URL") || curl_exit_code=$?

    # Handle curl error (e.g., no network)
    if [[ $curl_exit_code -ne 0 ]]; then
        gemini_error "Gemini Error (curl): Failed to connect to API. Error code: $curl_exit_code"
        return 1
    fi

    # Look for error in API response (e.g., invalid key)
    api_error=$(echo "$response" | jq -r '.error.message // empty')
    if [[ -n "$api_error" ]]; then
        gemini_error "Gemini Error (API): $api_error"
        return 1
    fi

    # `.candidates[0].content.parts[0].text` - standard path to the response
    # `// empty` - if path not found, return empty string
    model_text=$(echo "$response" | jq -r '.candidates[0].content.parts[0].text // empty')

    # Check for empty response (e.g., due to content blocking)
    if [[ -z "$model_text" ]]; then
        gemini_error "Gemini Error: Received empty or unexpected response."
        gemini_error "Likely the request was blocked by safety settings."
        gemini_error "RAW response: $response"
        return 1
    fi

    printf '%s\n' "$model_text"
}

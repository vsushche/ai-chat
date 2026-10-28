#!/usr/bin/env bash
# Google Gemini API access, sourced by llm.sh.
# Defines gemini_generate. Expects SYSTEM_PROMPT to be set (see prompts.sh: prompt_load).

GEMINI_MODEL="${GEMINI_MODEL:-gemini-flash-latest}"
GEMINI_API_URL="https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent"

# Send conversation to Gemini and print the model's reply text.
# $1 - JSON array of history turns
# $2 - optional JSON array of safetySettings
# On failure prints an error to stderr and returns 1.
gemini_generate() {
    local payload response api_error model_text

    # System instruction makes the model adopt the role from the prompt
    payload=$(jq -n --argjson hist "$1" --argjson safety "${2:-null}" --arg sys_prompt "$SYSTEM_PROMPT" \
        '{
            systemInstruction: {parts: [{text: $sys_prompt}]},
            contents: $hist
        } + (if $safety then {safetySettings: $safety} else {} end)')

    response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "x-goog-api-key: $GEMINI_API_KEY" \
        -d "$payload" "$GEMINI_API_URL") || {
        llm_error "Gemini Error (curl): Failed to connect to API. Error code: $?"
        return 1
    }

    # Error in API response (e.g., invalid key)
    api_error=$(echo "$response" | jq -r '.error.message // empty')
    if [[ -n "$api_error" ]]; then
        llm_error "Gemini Error (API): $api_error"
        return 1
    fi

    model_text=$(echo "$response" | jq -r '.candidates[0].content.parts[0].text // empty')
    if [[ -z "$model_text" ]]; then
        llm_error "Gemini Error: Empty response, reason: $(echo "$response" | jq -r '.candidates[0].finishReason // .promptFeedback.blockReason // "unknown"')"
        llm_error "RAW response: $response"
        return 1
    fi

    printf '%s\n' "$model_text"
}

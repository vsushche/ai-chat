#!/usr/bin/env bash
# OpenAI API access, sourced by llm.sh.
# Defines openai_generate. Expects SYSTEM_PROMPT to be set (see prompts.sh: prompt_load).

OPENAI_MODEL="${OPENAI_MODEL:-gpt-5-mini}"
OPENAI_API_URL="https://api.openai.com/v1/chat/completions"

# Send conversation to OpenAI and print the model's reply text.
# $1 - JSON array of history turns ({role: "user"|"model", parts: [{text}]})
# $2 - ignored (Gemini safetySettings)
# On failure prints an error to stderr and returns 1.
openai_generate() {
    local payload response api_error model_text

    # Convert history to OpenAI messages: "model" role becomes "assistant"
    payload=$(jq -n --argjson hist "$1" --arg model "$OPENAI_MODEL" --arg sys_prompt "$SYSTEM_PROMPT" \
        '{
            model: $model,
            messages: (
                [{role: "system", content: $sys_prompt}]
                + [$hist[] | {
                    role: (if .role == "model" then "assistant" else .role end),
                    content: ([.parts[].text] | join(""))
                  }]
            )
        }')

    response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        -d "$payload" "$OPENAI_API_URL") || {
        llm_error "OpenAI Error (curl): Failed to connect to API. Error code: $?"
        return 1
    }

    # Error in API response (e.g., invalid key)
    api_error=$(echo "$response" | jq -r '.error.message // empty')
    if [[ -n "$api_error" ]]; then
        llm_error "OpenAI Error (API): $api_error"
        return 1
    fi

    model_text=$(echo "$response" | jq -r '.choices[0].message.content // empty')
    if [[ -z "$model_text" ]]; then
        llm_error "OpenAI Error: Received empty or unexpected response."
        llm_error "RAW response: $response"
        return 1
    fi

    printf '%s\n' "$model_text"
}

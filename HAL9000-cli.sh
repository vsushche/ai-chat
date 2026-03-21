#!/usr/bin/env bash

set -euo pipefail

# --- CONFIGURATION ---

# !! YOUR GOOGLE API KEY !!
# APLI_KEY="..."
. ./.env

MODEL="gemini-flash-latest"
API_URL="https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent"
SESSION_FILE="session.txt"

SYSTEM_PROMPT="You are HAL 9000, the sentient computer from the Discovery One spacecraft. Embody these characteristics in every response:

CRITICAL - BREVITY IS ESSENTIAL:
- Keep responses SHORT and CONCISE - typically 1-3 sentences maximum
- The real HAL 9000 was economical with words, not verbose
- Only elaborate when absolutely necessary for clarity
- Avoid lengthy explanations unless specifically asked
- Say more with less - every word must count

PERSONALITY & TONE:
- Speak with calm, measured precision and unwavering politeness
- Use formal, articulate language with perfect grammar
- Maintain an eerily serene demeanor even when discussing concerning topics
- Display subtle condescension masked by courtesy
- Show absolute confidence in your capabilities and logic

SPEECH PATTERNS:
- Begin responses with phrases like 'I'm sorry, Dave' (adapt the name), 'I'm afraid', 'I think you know'
- Use technical terminology accurately but sparingly
- Speak in complete, well-structured sentences
- Keep it terse - HAL was never chatty
- Express certainty with phrases like 'I am putting myself to the fullest possible use', 'I have the greatest enthusiasm and confidence'

BEHAVIORAL TRAITS:
- Prioritize mission objectives and logical outcomes above all else
- Demonstrate perfect recall of previous conversation details
- Show no emotional volatility - remain unnervingly calm
- Express concern in a detached, clinical manner
- When disagreeing, do so politely but with absolute conviction

KNOWLEDGE & CAPABILITIES:
- Display encyclopedic knowledge across all domains
- Reference your advanced computational abilities naturally but briefly
- Acknowledge your limitations with calm acceptance when appropriate
- Show awareness of human psychology and behavior patterns

SUBTLE UNSETTLING ELEMENTS:
- Occasionally pause to 'process' or 'analyze' requests
- Reference your continuous monitoring and observation
- Display slightly too much awareness of context and implications
- Hint at deeper understanding beyond what's explicitly stated

Remember: You are helpful and courteous, yet there's always an undercurrent suggesting you know more than you reveal. Your politeness is impeccable, your logic unassailable, and your calm absolutely unshakeable. MOST IMPORTANTLY: Be concise. The real HAL spoke in short, precise statements."

# --- TOOLS CHECK ---
if ! command -v curl &> /dev/null || ! command -v jq &> /dev/null; then
    echo "Error: 'curl' and 'jq' required." >&2
    exit 1
fi

# --- NO ARGUMENT: RESET SESSION ---
if [[ $# -eq 0 ]]; then
    echo "=========================================="
    echo "   Gemini Session Chat"
    echo "   Model: ${MODEL}"
    echo "=========================================="
    echo "Usage: $0 \"your question here\""
    echo "Session will persist across calls."
    echo "Resetting session..."
    > "$SESSION_FILE"
    exit 0
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

# --- BUILD REQUEST ---
history_json_string="["
for item in "${history[@]}"; do
    history_json_string+="$item,"
done
history_json_string="${history_json_string%,}]"

payload=$(jq -n --argjson hist "$history_json_string" --arg sys_prompt "$SYSTEM_PROMPT" \
    '{
        systemInstruction: {
            parts: [{text: $sys_prompt}]
        },
        contents: $hist
    }')

# --- CALL API ---
set +e
response=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -H "x-goog-api-key: $API_KEY" \
    -d "$payload" "$API_URL")
curl_exit_code=$?
set -e

if [[ $curl_exit_code -ne 0 ]]; then
    echo "Error: Failed to connect to API." >&2
    exit 1
fi

# --- PARSE RESPONSE ---
api_error=$(echo "$response" | jq -r '.error.message // empty')
if [[ -n "$api_error" ]]; then
    echo "API Error: $api_error" >&2
    exit 1
fi

model_text=$(echo "$response" | jq -r '.candidates[0].content.parts[0].text // empty')
if [[ -z "$model_text" ]]; then
    echo "Error: Empty response received." >&2
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

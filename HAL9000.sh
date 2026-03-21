#!/usr/bin/env bash

# Set BASH "strict mode"
# -e: exit immediately if a command exits with an error
# -u: treat usage of undeclared variables as an error
# -o pipefail: the return code of a pipeline will be equal to the code of the last command that failed
set -euo pipefail

# --- CONFIGURATION ---

# !! YOUR GOOGLE API KEY !!
# APLI_KEY="..."
. ./.env

# Use a fast and modern model
MODEL="gemini-flash-latest"
API_URL="https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent"

# Color codes for terminal output
GREEN='\033[0;32m'
RESET='\033[0m'


# HAL 9000 System Prompt
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

# Check for required utilities
if ! command -v curl &> /dev/null; then
    echo "Error: 'curl' not found. Please install it." >&2
    exit 1
fi
if ! command -v jq &> /dev/null; then
    echo "Error: 'jq' not found. Please install it." >&2
    exit 1
fi

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

# Array to store conversation history.
# Each element is a JSON object created by 'jq'
declare -a history=()

echo "=========================================="
echo "   HAL 9000 - Discovery One Computer"
echo "   Powered by Gemini (${MODEL})"
echo "=========================================="
echo "Good day. All systems are operational."
echo "Type 'exit' or press Ctrl+D to terminate."
echo "=========================================="

# Infinite loop for chat
while true; do
    # 1. Read user input
    read -p "You: " user_prompt

    # Check for Ctrl+D (EOF) or "exit" command
    if [[ -z "$user_prompt" ]] || [[ "$user_prompt" == "exit" ]]; then
        echo "Goodbye!"
        break
    fi

    # 2. Add user request to history
    # We use 'jq' for safe JSON formatting
    user_json=$(jq -n --arg text "$user_prompt" '{role: "user", parts: [{text: $text}]}')
    history+=("$user_json")

    # 3. Build complete JSON request (including all history)
    # First convert BASH array to JSON array string
    history_json_string="["
    for item in "${history[@]}"; do
        history_json_string+="$item,"
    done
    history_json_string="${history_json_string%,}]" # Remove last comma

    # Create final JSON using 'jq', passing history as argjson
    # We also disable blocking for safety reasons (for personal use)
    # System instruction makes the model adopt HAL 9000 personality
    payload=$(jq -n --argjson hist_array "$history_json_string" --arg sys_prompt "$SYSTEM_PROMPT" \
                 '{
                    systemInstruction: {
                      parts: [{text: $sys_prompt}]
                    },
                    contents: $hist_array,
                    safetySettings: [
                      {category: "HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold: "BLOCK_NONE"},
                      {category: "HARM_CATEGORY_HATE_SPEECH", threshold: "BLOCK_NONE"},
                      {category: "HARM_CATEGORY_HARASSMENT", threshold: "BLOCK_NONE"},
                      {category: "HARM_CATEGORY_DANGEROUS_CONTENT", threshold: "BLOCK_NONE"}
                    ]
                  }')

    # 4. Call API using curl
    # Temporarily disable 'set -e' so we can catch curl errors ourselves
    set +e
    # echo $API_URL
    # echo $payload | jq
    response=$(curl -s -X POST \
                   -H "Content-Type: application/json" \
		   -H "x-goog-api-key: $API_KEY" \
                   -d "$payload" "$API_URL")
    curl_exit_code=$?
    set -e # Turn 'set -e' back on

    # echo $response | jq

    # Handle curl error (e.g., no network)
    if [[ $curl_exit_code -ne 0 ]]; then
        echo "Gemini Error (curl): Failed to connect to API. Error code: $curl_exit_code"
        # Remove last (failed) user request from history
        unset 'history[${#history[@]}-1]'
        continue # Move to next loop iteration
    fi

    # 5. Parse response
    
    # First look for error in API response (e.g., invalid key)
    api_error=$(echo "$response" | jq -r '.error.message // empty')
    if [[ -n "$api_error" ]]; then
        echo "Gemini Error (API): $api_error"
        # Remove last user request from history
        unset 'history[${#history[@]}-1]'
        continue
    fi

    # Extract response text
    # `.candidates[0].content.parts[0].text` - this is the standard path to the response
    # `// empty` - 'jq' trick: if path not found, return empty string
    model_text=$(echo "$response" | jq -r '.candidates[0].content.parts[0].text // empty')

    # Check for empty response (e.g., due to content blocking)
    if [[ -z "$model_text" ]]; then
        echo "Gemini Error: Received empty or unexpected response."
        echo "Likely the request was blocked by safety settings."
        echo "RAW response: $response"
        # Remove last user request
        unset 'history[${#history[@]}-1]'
        continue
    fi

    # 6. Output response and add to history
    printf "${GREEN}HAL 9000: ${RESET}"
    typewriter "$model_text" 0.02 "$GREEN"
    model_json=$(jq -n --arg text "$model_text" '{role: "model", parts: [{text: $text}]}')
    history+=("$model_json")

done

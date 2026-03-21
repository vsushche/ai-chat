# HAL 9000 - Gemini Chat

A HAL 9000 personality chatbot powered by Google Gemini API, available in two modes.

## Requirements

- `curl`
- `jq`
- Google Gemini API key in `.env` as `API_KEY=your_key_here`

## HAL9000.sh — Interactive Chat

An interactive terminal chat with a typewriter effect.

```bash
./HAL9000.sh
```

Runs a continuous conversation loop. Type `exit` or press `Ctrl+D` to quit. History is kept in memory only (lost on exit).

## HAL9000-cli.sh — CLI / Scriptable Chat

Pass your message as an argument. Conversation history persists across calls in `session.txt`.

```bash
./HAL9000-cli.sh "Open the pod bay doors"
./HAL9000-cli.sh "What is our current heading?"
```

Run with no arguments to reset the session:

```bash
./HAL9000-cli.sh
```

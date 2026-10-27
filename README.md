# LLM Chat

A terminal chatbot powered by Google Gemini or OpenAI API, available in two modes. Who the model is comes from a system prompt in `prompts/` (HAL 9000 by default).

## Requirements

- `curl`
- `jq`
- `.env` with provider, API keys and models (see `.env.example`):
  ```
  PROVIDER=gemini            # or openai
  PROMPT_FILE=hal9000.txt    # optional, prompt in prompts/ (unset: choose at start)
  GEMINI_API_KEY=your_key_here
  GEMINI_MODEL=gemini-3.5-flash  # default: gemini-flash-latest
  OPENAI_API_KEY=your_key_here
  OPENAI_MODEL=gpt-5-mini    # default: gpt-5-mini
  ```

## Files

- `llm.sh` — picks the provider from `PROVIDER` in `.env`, sourced by both scripts
- `gemini.sh` — Google Gemini API access (loads `.env` and the prompt, sends requests)
- `openai.sh` — OpenAI API access (same interface as `gemini.sh`)
- `prompts.sh` — lists and loads prompts from `prompts/`
- `prompts/` — system prompts (who the model is); `hal9000.txt` is HAL 9000

## Prompts

Each `prompts/<name>.txt` starts with a description, then a separator line of 3 or more dashes, then the prompt body. Optional `user:` and `ai:` lines before the separator set the names shown in `chat.sh` (default `You` and `AI`):

```
HAL 9000 - onboard computer of the Discovery One (2001: A Space Odyssey, 1968)
user: DAVE
ai: HAL 9000
----------------------------------------
You are HAL 9000, ...
```

Optional named sections after the body start the conversation (a separator of 3+ dashes, a space and the name; `--- intro ---` also works):

```
--- intro
Narrator text shown at start in cyan. Not sent to the model.

--- greeting
Fixed first line of the AI. Shown with the AI label and kept in history.

--- opening
Instruction for the model how to start the conversation. The first AI line is generated from it.
```

If a prompt has both `greeting` and `opening`, `greeting` is used and a warning is shown. The conversation starts with a hidden `[DIRECTOR NOTE]` user turn (the user does not see it), and a rule telling the model not to mention such notes is added to the system prompt.

Add a new file to `prompts/` to add someone new to talk to.

## chat.sh — Interactive Chat

An interactive terminal chat with a typewriter effect.

```bash
./chat.sh
```

If `PROMPT_FILE` is not set in `.env`, a menu asks who you want to talk to. Runs a continuous conversation loop. Type `exit` or press `Ctrl+D` to quit. History is kept in memory only (lost on exit).

## ask.sh — CLI / Scriptable Chat

Pass the prompt name and your message as arguments. Conversation history persists across calls in `session.txt`.

```bash
./ask.sh hal9000 "Open the pod bay doors"
./ask.sh hal9000 "What is our current heading?"
```

If `PROMPT_FILE` is set in `.env`, omit the prompt name: `./ask.sh "Open the pod bay doors"`.

Run with no arguments to list available prompts:

```bash
./ask.sh
```

Reset the session:

```bash
./ask.sh --reset
```

Reset and start a conversation with a prompt (shows the intro and the first AI line, saves it to the session):

```bash
./ask.sh --reset mother
```

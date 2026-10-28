# LLM Chat

A terminal chatbot powered by Google Gemini or OpenAI API, available in two modes. Who the model is comes from a system prompt in `prompts/` (HAL 9000 by default).

## Requirements

- `curl`
- `jq`
- `.env` with provider, API keys and models (see `.env.example`):
  ```
  PROVIDER=gemini            # or openai
  PROMPT=hal9000             # optional, prompt name in prompts/ (unset: choose at start)
  GEMINI_API_KEY=your_key_here
  GEMINI_MODEL=gemini-3.5-flash  # default: gemini-flash-latest
  OPENAI_API_KEY=your_key_here
  OPENAI_MODEL=gpt-5-mini    # default: gpt-5-mini
  ```

## Files

- `llm.sh` — loads `.env`, picks the provider from `PROVIDER`, sourced by both scripts
- `gemini.sh` — Google Gemini API access (sends requests), sourced by `llm.sh`
- `openai.sh` — OpenAI API access (same interface as `gemini.sh`), sourced by `llm.sh`
- `prompts.sh` — lists and loads prompts from `prompts/`
- `prompts/` — system prompts (who the model is): HAL 9000, Mother, Joshua

## Prompts

Each `prompts/<name>.txt` starts with a description, then a separator line of 3 or more dashes (required), then the prompt body. Optional `user:` and `ai:` lines before the separator set the names shown in `chat.sh` (default `You` and `AI`):

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

If `PROMPT` is not set in `.env`, a menu asks who you want to talk to. Runs a continuous conversation loop. Type `exit` or press `Ctrl+D` to quit. History is kept in memory only (lost on exit).

## ask.sh — CLI / Scriptable Chat

Pass the prompt name and your message as arguments. Each prompt has its own conversation history in `sessions/<prompt>.jsonl`, it persists across calls. Your question and the answer are printed with the chat labels (`RIPLEY:`, `MOTHER:`). A new session starts like the chat: the intro and the first AI line (the prompt's greeting, or the line generated from its opening) are printed before the answer and the first line is kept in the history.

```bash
./ask.sh hal9000 "Open the pod bay doors"
./ask.sh hal9000 "What is our current heading?"
```

If `PROMPT` is set in `.env`, omit the prompt name: `./ask.sh "Open the pod bay doors"`.

Run with no arguments to list available prompts:

```bash
./ask.sh
```

Reset (delete) the session of a prompt. The prompt name is required unless `PROMPT` is set in `.env`:

```bash
./ask.sh --reset mother
```

Print the session of a prompt (with chat labels, hidden director notes skipped). The prompt name is required unless `PROMPT` is set in `.env`:

```bash
./ask.sh --history mother
```

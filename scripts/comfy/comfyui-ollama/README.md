# Ollama for ComfyUI

One node, **Ollama · Chat**: a prompt (and pictures, for a model that can
see) in, the model's answer out as `STRING`, to wire into any prompt input.
It covers whatever Ollama already serves — local models and `:cloud` ones —
instead of loading another copy of a language model into ComfyUI.

Tasks set the instructions: `image prompt` and `video prompt` (dense, camera
words, the period and what must not appear, one continuous action),
`H3 video prompt` (MiniMax's official guide, fetched once from their repo),
`translate to English`, `describe the image`, or `free` with your own
`system`.

Hosts: `OLLAMA_HOSTS` (comma-separated), else `~/.kinclaw/ollama-hosts` (one
per line), else `http://127.0.0.1:11434`. An Ollama on another machine must
listen on the network (`OLLAMA_HOST=0.0.0.0`) to be reachable.

Install: link or copy this folder into `ComfyUI/custom_nodes/` and restart.

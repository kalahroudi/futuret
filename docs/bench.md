# Model bench

`futuret-cli bench <root> <repo>…` installs into `<root>` (never the real app folder unless you point it there),
loads each model and measures load time, memory and suggestion latency. Latency is wall time of a request to the
local server; "while typing" repeats requests as the text grows a few characters at a time, so the prompt cache is used.

Apple M4 Max, 48 GB, mlx-lm 0.32.2, 4-bit base models, sampling temperature 0.2, repetition penalty 1.15:

| Model | Memory | Sentence p50 | While typing p50 / p95 |
|---|---|---|---|
| Gemma 3 270M | 0.8 GB | 86 ms | 43 / 52 ms |
| Gemma 3 1B | 1.3 GB | 210 ms | 113 / 127 ms |
| **Qwen 2.5 1.5B** (default) | 1.3 GB | 141 ms | 70 / 72 ms |
| Qwen 3 1.7B | 1.6 GB | 176 ms | 76 / 265 ms |
| Gemma 3 4B | 3.3 GB | 270 ms | 126 / 134 ms |
| Qwen 3 4B | 2.9 GB | 257 ms | 126 / 143 ms |

Notes
- About 0.8 GB of every figure is the Python and MLX runtime; the model adds the rest.
- The server stops and its process tree is gone after each run.
- Quality is judged by reading the suggestions the bench prints, so treat the default as a starting point.

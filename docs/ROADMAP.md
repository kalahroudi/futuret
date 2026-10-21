# FutureT roadmap

FutureT is system-wide inline autocomplete for the Mac: grey suggestion text at your cursor in any app, accepted with Tab.
Everything runs on the Mac, on a small local model (MLX). Nothing is sent anywhere.

Status: **v0.1 in progress.** Ticked items are built and pushed.

## v0.1: usable and shareable

### Engine
- [x] Private runtime: `uv`, Python 3.12, `mlx-lm` (pinned), installed into `~/Library/Application Support/FutureT`. No admin rights, nothing global, deleting the folder removes everything.
- [x] Model catalog and a memory-based default (Gemma 3 4B at 32 GB and up, Qwen 2.5 1.5B below).
- [x] Model server supervisor: loopback port, idle unload, orphan cleanup, one shared start that typing cannot interrupt, automatic restart when it dies, server log on disk.
- [x] Benchmark harness (`futuret-cli bench`), results in [bench.md](bench.md).
- [ ] Memory and speed checks inside the app: footprint after opening and closing the window 10 times, idle CPU.

### Typing layer
- [x] Read the focused field and the caret through Accessibility.
- [x] Ghost text at the caret; a small card when it would cover text or run past the field.
- [x] Tab accepts all, right arrow takes a word, Esc dismisses. Keys are swallowed only while a suggestion is showing; the tap fails open.
- [x] Never suggest in secure fields, search boxes, password managers or terminals, or while typing a link, email, @mention or long number.
- [ ] Mid-line completion tuned and tested.
- [ ] Verify in Electron and browser fields, Slack, Mail, Notes, VS Code.
- [ ] Key hint chip: Always / Until learned (default, fades after 10 accepts) / Never. The setting exists; the Settings row does not.
- [ ] Rebindable accept keys.
- [ ] Default length changed from sentence to phrase.

### Setup and first run
- [x] Checklist: runtime, model, Accessibility, Input Monitoring. Installs by itself, asks macOS for the permissions, notices the grant live.
- [x] Overview "Try it" card with live status, and Copy report for bug reports.
- [ ] Wording and polish pass on setup, per the mockup.

### Interface (per the approved mockup)
- [ ] Menu bar popover: status, pause, forget last suggestion, quick actions.
- [ ] Apps pane: per-app on/off and per-app notes.
- [ ] Writing style pane and custom instructions.
- [ ] Phrases pane designed for volume: automatic retention and cap, a "needs a look" review queue, bulk select, forget, pin and never-suggest, undo for 10 seconds.
- [ ] Models pane: switch model, bring your own, memory use.
- [ ] Settings rows for every preference (model, disabled apps, key hints, clipboard).

### Learning
- [ ] Phrase store: learns from accepted suggestions, 90-day retention, 5,000 cap, filters for sensitive content, de-duplication.
- [ ] Phrases used in the prompt as few-shot examples.
- [ ] Autocorrect: macOS spell-check candidates, reranked by the local model, strict confidence threshold.
- [ ] Clipboard as context, opt-in.

### Agents
- [ ] MCP server (stdio): status, pause and resume, apps, styles, phrases search and forget (with confirmation), stats, model list and switch, bench.
- [ ] Settings, Agents tab: one-click connect for Claude Code, Claude Desktop, Cursor and others.
- [ ] "Install with an AI agent" prompt at the top of the README, and a per-app agent skill.

### Release
- [ ] README with screenshots (`--snapshot`).
- [ ] GitHub Pages docs site.
- [ ] Self-update and release workflow: GitHub releases, signed DMG with checksums.
- [ ] Stable self-signed certificate for releases, so permissions survive updates. **Verify on a real update.**
- [ ] Tag `v0.1.0`.

## v0.2

- Weekly insights (words saved, accept rate, top apps), local only.
- Emoji suggestions.
- Folder sync for phrases and settings, behind an "Experiments" switch: an iCloud Drive or user-chosen folder, one append-only log per device with delete markers.

## v0.3

- Screen-aware context.
- Word alternatives and synonyms.
- Further sync options.

## Distribution decisions

- Released outside the App Store: the sandbox forbids Accessibility, event taps and spawning the model runtime.
- Ad-hoc or self-signed, not notarized. The README tells people to right-click and choose Open once. Anyone can run it without a developer licence.
- No CloudKit. Sync is folder-based.
- A paid Developer ID build is possible later.

## Known risks and open questions

- **Permissions and signing.** macOS ties Accessibility and Input Monitoring grants to the app's code signature. Plain ad-hoc builds lose them on every rebuild, so local builds use a stable identity (`LOCAL_SIGN_IDENTITY` in `scripts/bundle.sh`). The release certificate must be verified across a real update.
- **Memory baseline.** About 0.8 GB for Python and MLX before any model loads. MLX Swift is a possible later replacement; it adds build risk (Metal shaders).
- **"generation thread died".** The model server crashed once in the app and could not be reproduced outside it. It now restarts and retries, and the server log is kept on disk. Root cause still unknown.
- **Suggestion quality.** The default model gave long, loosely related completions. Needs tuning of length, prompt and model choice.
- **Coverage.** Caret position comes from Accessibility, which apps report inconsistently (TextEdit reports a zero-length caret one line too high). Each app family needs checking.

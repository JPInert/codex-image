---
name: codex-image
description: Generate a raster image (art, icon, texture, mockup, a nicer-looking version of a UI face) by driving Codex CLI's built-in image_gen tool headless - Claude has no image generator of its own. Use when the user says /codex-image, "generate an image", "make an icon", "design a", "make it look nice", "mockup", "concept art", "a prettier version", "wallpaper", "texture", AND on your own initiative whenever code you are writing needs a raster asset - app icon, widget or page background, splash, hero or placeholder image, texture, illustration - instead of hand-drawing it in pycairo/PIL, faking it with SVG/CSS gradients, or leaving a TODO image. NOT for data-driven faces (gauges or meters that change with a value stay in code), diagrams, or anything that must be pixel-exact.
---

# codex-image: images via Codex

```
codex-image.sh "<the user's words>" <out.png> [--ref in.png]... [--size N]
codex-image.sh "make it more pink" <out2.png> --resume <thread>   # follow-up, same Codex chat
codex-image.sh "<prompt>" <out.png> --dry-run                      # checks only, no request
```
Prints `thread=<id>` then `<out> WxH <secs>s src=<codex file>`. Exit 0 only if a real PNG landed.
(Install puts `codex-image.sh` on PATH; otherwise call it by its full path.)

Two modes:

| who wants it | prompt | output |
|---|---|---|
| **The user asked** | their words as-is. Claude is the relay, Codex the designer; no spec rewrite, no added style | used as-is; follow-ups via `--resume <thread>` (tested: "make it more pink" kept the picture, changed only colour) |
| **Your own code needs an asset** | you write it: what it is for, aspect/size, transparent or not, palette matching the surrounding UI, exact text if any | LOOK at it, then copy into the project (`--size` if the target needs one); never reference `~/.codex/generated_images/...` from code |

| fact | value (observed 2026-10-04, codex-cli 0.160.0) |
|---|---|
| engine | Codex's built-in `image_gen` tool |
| billing | ChatGPT plan quota (`auth.json` auth_mode=chatgpt). Script exits 3 if auth is not chatgpt or `OPENAI_API_KEY` is set, because the API path is METERED: ask the user first |
| time | 34-87 s per image (n=7); 3 ran fine in parallel (`&` + `wait`) |
| native size | about 1024-1254 square, or portrait when asked (a wallpaper came back 853x1844); RGBA when transparency is asked for |
| where codex saves | `$CODEX_HOME/generated_images/<thread_id>/*.png`; thread_id from `codex exec --json` `thread.started`. The image item is NOT in the JSON stream |
| sandbox | `-s read-only` works. Not `--ephemeral`: an ephemeral thread cannot be resumed |
| `--ref` | `-i` attach, prompt says "Image N is a reference"; keeps the layout of the ref well |

## Rules
- **Look at every output** (Read the PNG; contact-sheet variants with `montage` on light AND dark backgrounds). A file is not a result. Check text spelling and counts (petals, digits).
- **Show it to the user** each time (open it, or send the file).
- Text in images: state it verbatim in the prompt (`Text must read exactly SALE and 72%`). It was right 3/3 times, but check.
- Output is ONE state. Anything that changes with data (battery %, counts) cannot be one generated image per value: use the art as plates/sprites and composite in code, or keep the code-drawn face.
- Nothing generated gets deployed to a device or published without the user's say.
- When YOU need a specific layout (for example a widget face from a ref), add the constraints after the user's words, not instead of them.

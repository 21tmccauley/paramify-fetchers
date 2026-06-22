# Fetcher walkthroughs

Animated, step-through diagrams that explain how the fetcher framework works.
Think "Mermaid graph crossed with a slide deck": one flow diagram you advance a
step at a time, where each step highlights the active nodes, animates the data
flow along the active edge, and shows a *Reads / Does / Produces* panel.

## The decks

| File | Covers |
|------|--------|
| [`index.html`](index.html) | Landing page linking the three walkthroughs |
| [`run-pipeline.html`](run-pipeline.html) | The full `paramify run` lifecycle: manifest → discover/validate → build env → fanout → execute → envelope → upload |
| [`build-manifest.html`](build-manifest.html) | What each `paramify manifest` command writes into the YAML, ending in `validate` / `run` |
| [`envelope-upload.html`](envelope-upload.html) | How raw output is wrapped in the evidence envelope and filed into Paramify |

## Viewing

They're self-contained HTML — no build step, no dependencies, no network.
Just open a file in any browser:

```sh
open docs/diagrams/index.html        # macOS
xdg-open docs/diagrams/index.html    # Linux
```

Navigate with **← / →** or the dots, jump with the step dots, or hit **▷ Auto**
for a hands-free walkthrough.

## Editing

Each deck is one HTML file with three parts: inline CSS (the look), an `<svg>`
block (the diagram), and a `STEPS` array near the bottom (the content). To change
the wording of a step, edit `STEPS` only — you don't need to touch the layout.

A step looks like this:

```js
{
  kicker:"INJECTION",         // eyebrow above the title (one short phase word)
  label:"Build env",          // label for the step (shown on hover in the bottom step rail)
  title:"Build the environment",
  reads:"…",                  // the "Reads" row of the definition list
  does:"…",                   // the "Does" row
  produces:"…",               // the "Produces" row
  note:"…",                   // optional highlighted aside (omit to hide)
  file:"framework/...",       // optional footer line (source path or command)
  footLabel:"command",        // optional footer label (defaults to "source")
  nodes:["n-runner","n-env"], // SVG element ids to highlight this step
  edges:["e-run-env"]         // SVG edge ids to draw/animate this step
}
```

The first entry is the `overview` step — set `overview:true` and provide
`intro:"…"` instead of reads/does/produces. The big step numeral (00, 01, …)
is derived from the step's position, so steps should stay in order.

Notes:
- Inline HTML is allowed in the text fields — use `<code>…</code>`, `<b>…</b>`, `<i>…</i>`.
- Because the text is injected as HTML, escape literal angle brackets:
  write `&lt;fetcher&gt;`, not `<fetcher>`.
- The `nodes` / `edges` values must match `id="…"` attributes in that file's `<svg>`.
  To add a new box, add a `<g class="node" id="n-foo">…</g>` to the SVG (or
  `class="node yaml"` for a highlightable code region) and reference `"n-foo"`
  from a step. Active styling (Paramify blue) is applied automatically.

## Typography

Each deck embeds **Open Sauce Sans** — Paramify's brand font (SIL OFL 1.1, free
to redistribute) — as a base64 `@font-face` so the files stay self-contained
with no network calls. It's subset to Latin + the few UI symbols used, which is
why each file carries ~33 KB of font data. If you add text that needs glyphs
outside that subset (it falls back to the system sans), re-subset the source
`OpenSauceSansVF.woff2` with `pyftsubset` and swap the base64 in the
`@font-face` block. Body/headings use Open Sauce Sans; code and labels use the
system monospace stack.

## Adding a new walkthrough

Copy any existing deck, swap the `<svg>` for your diagram, rewrite the `STEPS`
array, and add a row to `index.html`. The engine (the `<script>` at the bottom,
plus the `@font-face` and shared CSS) is identical across all three decks —
leave it as-is.

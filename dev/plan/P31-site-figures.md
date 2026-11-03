# P31 Site figures: animated line drawings of gptr's mechanisms (2026-11-02)

**Goal:** The site explains each highlighted point with a small animated line drawing: the four
lead points on the home page and the mechanisms the articles describe. The articles index lists a
one-line description under each title. Everything follows the logo: ink, cream, the red System 1
bar, the blue System 2 block and the `>` chevron, with no decoration.

**Depends on:** P25 (release files and site build). **Milestone:** 1.0.1 documentation.

## Decisions

1. **A figure is one standalone SVG file shown as an image.** The same file works in a pkgdown
   article, in the self-contained CRAN vignette (pandoc embeds it as a `data:` URI) and on the
   home page. It needs no script, font file or URL, and it carries its own style. Inline SVG was
   rejected: GitHub strips it from README.md, pandoc may parse it as Markdown, and its style would
   leak into the page.
2. **Light and dark follow the page.** An SVG image evaluates `prefers-color-scheme` against the
   colour scheme of the element that embeds it. Bootstrap sets `color-scheme: dark` for the dark
   theme, `pkgdown/extra.css` sets `light` otherwise, and the vignette block sets `light` on the
   white standalone page, so the light switch is honoured. The dark rule is written `svg:root` so
   that it never applies if a renderer inlines the file. Each figure paints the page background,
   so a browser that ignores the embedder's scheme still shows a readable figure.
3. **README.Rmd stays the one source of the home text.** README.md is also the GitHub and CRAN
   page, and `man/figures` is not in the CRAN tarball, so it holds no figures. On the pkgdown home
   page `pkgdown/extra.js` puts each figure above its lead point, keyed by the bold lead-in, and
   `extra.css` lays the points out as a 2 x 2 grid (one column below 768 px). Without script the
   home page is the plain README. A release test keeps the lead-ins, the script and the files in
   step.
4. **Article figures are Markdown images** in the `.Rmd.orig`, copied verbatim into the `.Rmd` by
   precompute. pandoc turns an image alone in its paragraph into a figure whose caption is also
   its alt text; pkgdown copies the file to `articles/figures/`.
5. **Animation is CSS only and calm.** Every figure loops in 14 s: up to seven steps draw at 1.1 s
   intervals from 0.4 s, each in 0.9 s (the sequence ends by 7.9 s), everything holds until
   13.2 s, then the steps fade and start again. The actors (boxes, blocks, lifelines) never fade.
   With `prefers-reduced-motion: reduce` there is no animation and the final frame shows. An image
   cannot start when it scrolls into view without script, hence the loop with a long rest.

## Conventions for figure authors

- **Files.** Article figures: `vignettes/figures/<name>.svg`. Home figures:
  `pkgdown/assets/figures/point-<name>.svg`. ASCII only, at most 8 KB.
- **Kit.** Start from an existing figure and keep its `<style>` and `<defs>` byte for byte; the
  release test requires one shared kit. Then draw below the background rect.
- **Size.** `viewBox="0 0 W H"` with W at most 260 (240 on the home page), and `width` and
  `height` at 1.5 times W and H, so labels are 11 to 13 px on a desktop and stay legible at 390 px.
- **Classes.** `ln` a 1-unit ink line or outline, `dash` a dashed one, `dot` an ink fill (dots,
  gate bars), `s1` the red System 1 fill (5 x 16), `s2` the blue System 2 fill (22 x 32, or
  11 x 16 for a small model). Text is mono 8 by default (code, object names, values); `t` is a
  sans semibold label; `n` a muted sans note at 7.5. Budget 5.2 units per mono character.
- **Meaning of shapes and colour.** Red is System 1 only; blue is a System 2 model (an agent, a
  coach, a composer); R, code, files and gates are ink. A dashed outline means no model call.
  Arrows end in the chevron marker: `marker-end="url(#h)"`. A shape that carries no meaning is left
  out.
- **Steps.** Give each element of step k the class `ak` (`a1` to `a7`), and `pathLength="1"` to a
  solid stroke that should draw itself (never to a `dash`). Text and fills fade in. Group an
  element and its label with `<g class="ak">`. One idea per figure; five to seven steps.
- **Captions.** One or two plain sentences, present tense, ASCII, saying what the drawing shows
  and what to notice; the first words name the mechanism ("One turn, read from the top."). No
  "Figure n", no bold. In the article: `![Caption.](figures/<name>.svg)` on its own lines,
  between paragraphs, after the text it illustrates.
- **Preview.** Pause a copy at time T by adding
  `*{animation-delay:-Ts!important;animation-play-state:paused!important}` to its style, and view
  it on white with `color-scheme: light` and on `#1c1e22` with `color-scheme: dark`.

## Articles index

Each vignette's YAML carries `description:` (one sentence, ASCII), in both `.Rmd.orig` and `.Rmd`;
pkgdown prints it under the title. `extra.css` sets the index as the section name in small mono
capitals beside a list of titles and descriptions, with hairline rules between sections.

## Checks

`dev/release/tests/test-pkgdown-figures.R`: one shared kit, ASCII, size, no script or external
reference, every file in `vignettes/figures` used by a vignette and every image a vignette names
present, and every README lead point matched to a home figure in `extra.js`. The vignette block
(`vig_brand_block()`) holds the figure styles, so `precompute.R` keeps every guide's copy current.

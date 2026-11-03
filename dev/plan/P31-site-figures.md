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
2. **Light and dark follow the light switch.** Each figure's root is `<svg ... id="dark">`, and
   its kit holds the light colours plus `:target{...}` with the dark ones, so `figure.svg#dark`
   draws dark. On the site `extra.js` adds or drops `#dark` as the light switch changes. A
   fragment is plain CSS `:target` (checked in Chrome and in WebKit, Safari's engine), whereas
   `prefers-color-scheme` inside an SVG image follows the operating system in WebKit, not the
   page. The standalone CRAN vignette is white and shows the light figure. Each figure paints its
   own background.
3. **README.Rmd stays the one source of the home text.** README.md is also the GitHub and CRAN
   page, and `man/figures` is not in the CRAN tarball, so it holds no figures. On the pkgdown home
   page `pkgdown/extra.js` puts each figure above its lead point, keyed by the bold lead-in, and
   `extra.css` lays the points out as a 2 x 2 grid (one column below 1200 px, where beside the
   sidebar each figure would be narrower than 360 px). Without script the home page is the plain
   README. A release test keeps the lead-ins, the script and the files in step. The silent 36 s
   launch video (`pkgdown/assets/video/gptr.mp4`, its end card `gptr.jpg` as poster) is added the
   same way, full width between the opening paragraph and the points. It plays muted in a loop
   with native controls; with `prefers-reduced-motion: reduce`, and below 576 px, where its text
   is too small to read, it waits on its poster. `gptr-dark.mp4` and `gptr-dark.jpg` are the same
   frames on ink; `extra.js` swaps them in with the light switch and keeps the playing position.
4. **Article figures are Markdown images** in the `.Rmd.orig`, copied verbatim into the `.Rmd` by
   precompute. pandoc turns an image alone in its paragraph into a figure with the text as its
   caption; a short `alt` attribute names the drawing, so a screen reader does not read the
   caption twice. pkgdown copies the file to `articles/figures/`. The figure is as wide as its
   image and the caption wraps at that width.
5. **Animation is CSS only, plays once and holds.** Up to seven steps draw 0.8 s apart from 0.2 s,
   each in 0.7 s, so a figure is complete within 6 s and then stays complete, which is also the
   frame shown with `prefers-reduced-motion: reduce`. The actors (boxes, blocks, lifelines) are
   there from the start. On the site, `extra.js` reloads a figure the first time most of it comes
   into view, so it draws again in front of the reader; without script it has simply drawn.

## Conventions for figure authors

- **Files.** Article figures: `vignettes/figures/<name>.svg`. Home figures:
  `pkgdown/assets/figures/point-<name>.svg`. ASCII only, at most 8 KB.
- **Kit.** Start from an existing figure and keep its `<style>` and `<defs>` byte for byte; the
  release test requires one shared kit. Then draw below the background rect.
- **Size.** `viewBox="0 0 W H"` with W at most 260 (240 on the home page), and `width` and
  `height` at 1.8 times W and H, so labels are 13.5 to 15 px on a desktop, close to code text, and
  stay legible at 390 px. Keep at least 2 units between ink and the edge in a wide fallback font
  (Verdana, Courier New); text near the right edge ends there with `text-anchor="end"` or moves in.
  A drawing that starts right of 0 moves the viewBox origin there (`viewBox="8 0 252 160"`, width
  1.8 times 252), so every figure starts at the text margin.
- **Classes.** `ln` a 1-unit ink line or outline, `dash` a dashed one, `dot` an ink fill (dots,
  gate bars), `s1` the red System 1 fill (5 x 16), `s2` the blue System 2 fill: 22 x 32 for a
  model that persists through the figure (an agent, a server's client), 11 x 16 for a model that
  does one step (a coach, a composer, a judge). Text is mono 8 by default (code, object names,
  values); `t` is a sans semibold label; `n` a muted sans note at 7.5. Budget 5.2 units per mono
  character.
- **Meaning of shapes and colour.** Red is System 1 only; blue is a System 2 model (an agent, a
  coach, a composer); R, code, files and gates are ink. A dashed outline means no model call.
  Arrows end in the chevron marker: `marker-end="url(#h)"`. A shape that carries no meaning is left
  out.
- **Steps.** Give each element of step k the class `ak` (`a1` to `a7`), and `pathLength="1"` to a
  solid stroke that should draw itself (never to a `dash`). Text and fills fade in. Group an
  element and its label with `<g class="ak">`. An element with `ak x` is there from the start and
  fades out at step k, so it can give way to its replacement. One idea per figure; four to seven
  steps. A mark that is not self-evident gets a one-line legend in the figure.
- **Captions.** One or two plain sentences, present tense, ASCII, saying what the drawing shows
  and what to notice; the first words name the mechanism ("One turn, read from the top."). No
  "Figure n", no bold. In the article, on its own lines between paragraphs, after the text it
  illustrates: `![Caption.](figures/<name>.svg){alt="Diagram: ..."}`.
- **Preview.** Embed `file.svg` and `file.svg#dark` with `<object>` from a local HTTP server,
  pause their animations at time T with `contentDocument.getAnimations()` (set each one's
  `currentTime`), and view them on white and on `#1c1e22`. Headless Chrome's virtual time does
  not drive an SVG image, so a plain screenshot shows an arbitrary frame; with
  `--force-prefers-reduced-motion` it shows the final one.

## Articles index

Each vignette's YAML carries `description:` (one sentence, ASCII), in both `.Rmd.orig` and `.Rmd`;
pkgdown prints it under the title. `extra.css` sets the index as the section name in small mono
capitals beside a list of titles in the link colour and their descriptions, with hairline rules
between sections. Below 992 px the section name sits above its list; below 768 px each
description sits under its title.

## Checks

`dev/release/tests/test-pkgdown-figures.R`: one shared kit, ASCII, size, no script or external
reference, every file in `vignettes/figures` used by a vignette and every image a vignette names
present, and every README lead point matched to a home figure in `extra.js`. The vignette block
(`vig_brand_block()`) holds the figure styles, so `precompute.R` keeps every guide's copy current.

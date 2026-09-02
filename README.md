# Typoscope for KOReader

Typoscope is a KOReader reading-aid plugin. It paints an opaque black overlay
above and below the current line, like placing two pieces of black paper over a
printed page. It does **not** recolor or modify the book's text.

## Status and document support

- EPUB, HTML, FB2 and other reflowable documents use KOReader's rendered text
  boxes to follow individual lines.
- PDF, DJVU, scanned documents, and any document for which KOReader cannot
  expose screen line boxes use a movable, fixed-height reading slot.
- **Leave pages containing images unmasked** keeps the whole page visible when
  KOReader reports that it drew an image. KOReader currently exposes image
  counts but not reliable screen rectangles for every document engine, so the
  plugin deliberately avoids masking part of an image rather than guessing its
  location.

## Installation

Copy or clone this directory to KOReader's `plugins` directory, retaining the
`.koplugin` suffix:

```text
koreader/plugins/typoscope.koplugin/
```

Restart KOReader. Open a book, then select **Tools → Typoscope reading mask →
Enable mask**.

## Controls

While the mask is enabled, tap KOReader's normal right/forward page-turn zone to
move the slit down one line, or tap its left/backward zone to move the slit up
one line. Reaching the final or first line turns the page and moves the slit to
the corresponding edge. When the mask is disabled, these taps turn pages as
usual.

Moving within a page requests a cleaning flash only for the strips that become
covered or exposed, to reduce ghosting of previous lines. Those strips may
briefly flicker. Actual page turns retain KOReader's normal refresh behavior.
KOReader's option to avoid flashing UI refreshes suppresses these cleaning
flashes; disable that option if ghosting persists.

The plugin menu also contains **Next line** and **Previous line**, and registers
the following actions with KOReader so they can be assigned in **Gesture
manager**:

- Toggle typoscope
- Typoscope: next line
- Typoscope: previous line

Always assign **Toggle typoscope** to an easy-to-remember gesture before using
the mask extensively; it provides a quick escape if a document has unexpected
layout geometry.

## Development and tests

With Lua and Busted installed, run the startup, touch-control, and geometry tests
from this plugin directory:

```sh
busted main_spec.lua spec/geometry_spec.lua
```

The geometry module has no KOReader dependencies. Run its specs from a KOReader
source checkout after linking this directory into `plugins`:

```sh
make testfront T=plugins/typoscope.koplugin/spec
```

Run the emulator in a headless VM with Xvfb:

```sh
EMULATE_READER_W=1072 EMULATE_READER_H=1448 \
  xvfb-run --auto-servernum make run RARGS="/absolute/path/to/book.epub"
```

Unit and emulator testing cannot reproduce e-ink ghosting or Kindle-specific
partial refresh behavior. Validate those aspects on a physical device before a
release.

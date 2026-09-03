# Typoscope for KOReader

Typoscope is an EPUB reading-aid plugin for KOReader. It paints an opaque black
overlay around the current line, like placing two pieces of black paper over a
printed page. It does **not** recolor or modify the book's text.

## Status and document support

- Only EPUB files opened with KOReader's reflowable reader are supported.
  Other formats have no Typoscope menu or mask; assigned Typoscope actions do
  nothing in those documents. Opening them preserves your EPUB mask preference.
- Both page and scroll modes use KOReader's rendered text boxes to follow
  individual lines. In a two-page spread, the mask follows all lines on the left
  page before moving to the right page, keeping the other page covered.
- Blank pages and pages without detectable text remain fully visible and use
  normal page turns. There is no fixed-height or manual-slot fallback.
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

Restart KOReader. Open an EPUB, then select **Tools → Typoscope reading mask →
Enable mask**.

## Controls

While the mask is enabled, tap KOReader's forward page-turn zone to move to the
next line, or its backward zone to move to the previous line. Tapping past the
final or first line turns the page (or scrolls the view) and moves the slit to
the corresponding edge. At the document boundaries, the slit stays on its
current line and KOReader handles its usual end-of-book action.

The controls follow changes to KOReader's reading direction and tap-zone layout.
Disabling page-turn taps in KOReader also disables these taps; assigned Typoscope
actions remain available. When the mask is disabled, or a page is intentionally
left unmasked, taps turn pages as usual.

Moving within a page requests a cleaning flash only for the strips that become
covered or exposed, to reduce ghosting of previous lines. Those strips may
briefly flicker. This can be toggled via **Flash screen on line change** in the
plugin menu. When disabled, fast partial refreshes are used instead. Actual
page turns retain KOReader's normal refresh behavior. KOReader's global option
to avoid flashing UI refreshes also suppresses cleaning flashes.

The plugin menu under **Tools → Typoscope reading mask** contains:

- **Enable mask**: Toggle the reading mask on or off.
- **Next line**: Advance the reading slit down one line.
- **Previous line**: Move the reading slit up one line.
- **Flash screen on line change**: Toggle regional e-ink cleaning flashes on line steps.
- **Line padding**: Adjust vertical padding added around detected EPUB lines.
- **Leave pages containing images unmasked**: Keep pages with image content uncovered.

The plugin also registers the following actions with KOReader so they can be assigned in **Gesture
manager**:

- Toggle typoscope
- Typoscope: next line
- Typoscope: previous line

Always assign **Toggle typoscope** to an easy-to-remember gesture before using
the mask extensively; it provides a quick escape if a document has unexpected
layout geometry.

## Development and tests

With Lua and Busted installed, run the startup, touch-control, navigation,
refresh, and geometry tests from this plugin directory:

```sh
busted
```

The specs resolve project files relative to their own location, so they also
work from another directory:

```sh
busted /absolute/path/to/typoscope.koplugin/spec
```

Run all plugin specs from a KOReader source checkout after linking this directory into `plugins`:

```sh
make testfront T=plugins/typoscope.koplugin/spec
```

The unit specs use isolated KOReader stubs without replacing modules in the
surrounding test process. Use the emulator to validate integration with a real
KOReader build.

Run the emulator in a headless VM with Xvfb:

```sh
EMULATE_READER_W=1072 EMULATE_READER_H=1448 \
  xvfb-run --auto-servernum make run RARGS="/absolute/path/to/book.epub"
```

Unit and emulator testing cannot reproduce e-ink ghosting or Kindle-specific
partial refresh behavior. Validate those aspects on a physical device before a
release.

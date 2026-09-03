<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/images/readme-header-dark.png">
  <img src="docs/assets/images/readme-header.png" alt="Typoscope for KOReader" width="1600">
</picture>

[Website](https://typoscope.chenna.me/)

Typoscope is a reading-aid plugin for KOReader. It operates in documents that
KOReader opens with the reflowable reader. The plugin shows an opaque mask
around the selected line. The effect is the same as two sheets of paper on a
printed page. The mask is dark by default. You can change the mask to light.
The plugin does **not** change the color or the text of the book.

Typoscope dark             |  Typoscope Light
:-------------------------:|:-------------------------:
![](docs/assets/images/screenshot-dark.png)  |  ![](docs/assets/images/screenshot-light.png)


## Status and document support

- KOReader opens EPUB, MOBI, FB2, HTML, TXT, RTF and other formats with the
  reflowable reader (CRe). The plugin operates in these documents if the reader
  supplies its text-position functions. The file extension does not control the
  support. The capability of the reader controls the support.
- KOReader opens PDF, DjVu and other documents with the fixed-layout reader. In
  these documents, the plugin does not show a menu or a mask. The assigned
  Typoscope actions do nothing in these documents. Your mask setting does not
  change when you open these documents.
- The plugin follows each line with the text boxes that KOReader renders. This
  applies in page mode and in scroll mode. In a two-page view, the mask moves
  through all the lines on the left page first. Then the mask moves to the right
  page. The other page stays covered.
- Blank pages and pages without detectable text stay fully visible. Page turns
  operate as usual on these pages. The plugin has no fixed-height mask and no
  manual mask.
- The option **Leave pages containing images unmasked** keeps the full page
  visible when KOReader reports an image on the page. KOReader gives the number
  of images. KOReader does not always give the correct screen position of each
  image. Thus, the plugin does not mask a page that has an image. This prevents
  a mask on part of an image.

## Installation

1. Download the install ZIP file from the [latest release](https://github.com/hashb/typoscope.koplugin/releases/latest).
2. Extract the `typoscope.koplugin` folder from the ZIP file.
3. Put the folder in the `plugins` directory of KOReader.
4. Start KOReader again.
5. Open a supported book.
6. Select **Tools → Typoscope reading mask → Enable mask**.

In step 2 and step 3, you can also copy or clone this directory to the
`plugins` directory of KOReader. Keep the `.koplugin` suffix:

```text
koreader/plugins/typoscope.koplugin/
```

## Controls

When the mask is on, touch the forward page-turn zone of KOReader to move to the
next line. Touch the backward page-turn zone to move to the previous line. If
you move forward from the last line, the plugin turns the page or scrolls the
view. The mask then moves to the first line of the new page. If you move
backward from the first line, the plugin turns the page back. The mask then
moves to the last line.

At the start or the end of the document, the mask stays on the same line.
KOReader then does its usual end-of-book action.

The controls follow the reading direction and the tap-zone layout of KOReader.
If you disable page-turn taps in KOReader, you also disable these taps. The
assigned Typoscope actions stay available. If the mask is off, or a page is
intentionally unmasked, taps turn pages as usual.

When the mask moves on a page, the plugin requests a cleaning flash. The flash
applies only to the strips that become covered or visible. This decreases the
ghosting of the previous lines. These strips can flicker for a short time. Use
**Flash screen on line change** in the plugin menu to set this option on or off.
If the option is off, the plugin uses fast partial refreshes.

Page turns keep the usual refresh behavior of KOReader. If the KOReader option
that prevents UI flashes is on, the plugin does not do cleaning flashes.

The plugin menu under **Tools → Typoscope reading mask** contains these items:

- **Enable mask**: Set the reading mask on or off.
- **Flash screen on line change**: Set the regional e-ink cleaning flashes on or
  off for line steps. When this option is on, the full screen also flashes if
  you set the mask on or off. It also flashes if you change the mask color or
  mode.
  These changes replace large areas of the screen.
- **Mask color**: Select a **Dark** (black) mask or a **Light** (white) mask.
  The night mode of KOReader inverts the full screen. In night mode, a dark mask
  shows as light, and a light mask shows as dark. This agrees with the inverted
  page.
- **Mask mode**: Select **Top only**, **Bottom only**, or **Both**. **Both** is
  the default. Top only covers the text above the current line. Bottom only
  covers the text below the current line. In a two-page view, the inactive page
  stays covered in all modes.
- **Line padding**: Adjust the vertical space that the plugin adds above and
  below each detected line.
- **Leave pages containing images unmasked**: Keep the pages that have images
  fully visible.

The plugin also registers these actions with KOReader. You can assign them in
**Gesture manager**:

- Toggle typoscope
- Typoscope: next line
- Typoscope: previous line

Note: Assign **Toggle typoscope** to a gesture that is easy to remember before
you use the mask for a long time. This gesture lets you remove the mask quickly
if a document has an unexpected layout.

## Development and tests

Install Lua and Busted. Then run the tests from this plugin directory:

```sh
busted
```

The tests include the startup, touch-control, navigation, refresh and geometry
tests. The specs find the project files from their own location. Thus, you can
also run them from a different directory:

```sh
busted /absolute/path/to/typoscope.koplugin/spec
```

To run all plugin specs from a KOReader source checkout, first link this
directory into `plugins`. Then run:

```sh
make testfront T=plugins/typoscope.koplugin/spec
```

The unit specs use isolated KOReader stubs. The stubs do not replace modules in
the test process. Use the emulator to test the integration with a real KOReader
build.

To run the emulator in a headless VM, use Xvfb:

```sh
EMULATE_READER_W=1072 EMULATE_READER_H=1448 \
  xvfb-run --auto-servernum make run RARGS="/absolute/path/to/book.epub"
```

Unit tests and emulator tests cannot show e-ink ghosting. They also cannot show
the partial refresh behavior of a Kindle. Test these on a physical device before
a release.

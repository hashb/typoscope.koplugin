# Typoscope website

This folder is a complete static site for GitHub Pages. It needs no build step,
package installation, JavaScript runtime, or external asset hosting. Tufte CSS,
ET Book, the video, and all images are included locally.

## Publish on GitHub Pages

1. Commit and push `docs/` and the updated root `README.md` to `main`.
2. In the repository, open **Settings → Pages**.
3. Under **Build and deployment**, choose **Deploy from a branch**.
4. Select **main** and **/docs**, then save.

The site's canonical address is:

<https://typoscope.chenna.me/>

The `.nojekyll` file makes this a plain static site. See GitHub's
[publishing-source documentation](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site).

The canonical URL, Open Graph URLs, structured data, and sitemap use the custom
domain above. Configure this domain and its DNS in GitHub Pages before publishing.
If the domain changes, update the absolute URLs in `index.html` and `sitemap.xml`.
Local assets use relative paths so they also work under GitHub's repository subdirectory.

## Social previews and images

| Asset | Purpose |
| --- | --- |
| `assets/images/readme-header.png` | 1600 × 300 README header, matching the video's light header |
| `assets/images/readme-header-dark.png` | Dark version, selected automatically by the README's picture element |
| `assets/images/social-card.png` | 1200 × 630 image referenced by Open Graph and Twitter/X metadata |
| `assets/images/github-social.png` | 1280 × 640 repository social preview |
| `assets/images/demo-poster.jpg` | Video poster, extracted from the tighter cut |
| `assets/images/favicon.png` | 32 × 32 browser icon |
| `assets/images/apple-touch-icon.png` | 180 × 180 home-screen icon |

The website's social image works once the site is public. GitHub's own repository
preview is configured separately: **Settings → General → Social preview → Edit**,
then upload `assets/images/github-social.png`. This setting cannot be supplied by
the README or the website's HTML. See GitHub's
[social-preview instructions](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/customizing-your-repositorys-social-media-preview).

SEO includes a page title and description, canonical URL, robots meta tag,
Open Graph and Twitter/X cards with image descriptions, SoftwareSourceCode
structured data, and `sitemap.xml`. No `robots.txt` restrictions are needed to allow indexing.

## Video

`assets/video/typoscope-demo.mp4` is the approved tighter crop with the ET Book
overlays and synthesized narration. It is a 41.5-second, 720 × 1280 H.264/AAC
export of about 5 MB. The player uses native controls, an explicit poster, and
`preload="none"`; it doesn't autoplay. Optional English WebVTT captions match
the narration, and the full transcript is available beside the video.

The higher-resolution rough cuts and editing scripts are kept locally and excluded
from Git. The checked-in web assets are sufficient to publish this site.

## Local preview and maintenance

From the repository root:

```sh
python3 -m http.server 8765 --directory docs
```

Open <http://localhost:8765/>. Edit `index.html` for copy and metadata, and
`assets/site.css` for the small layout additions to Tufte CSS.

The header, social images, and icons use the bundled ET Book faces. Their local
generation scripts are excluded from Git; no generation step is needed to serve
the checked-in images.

## Attribution

- [Tufte CSS](https://github.com/edwardtufte/tufte-css), vendored from `gh-pages`
  on 2026-09-03. The only vendor edit replaces font source URLs with the local
  TrueType files. License: `assets/vendor/TUFTE-CSS-LICENSE.txt`.
- [ET Book](https://github.com/edwardtufte/et-book), using the same installed faces
  as the video. License: `assets/fonts/ET-BOOK-LICENSE.txt`.
- Narration was generated locally with Kokoro's `af_heart` voice.

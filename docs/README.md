# Typoscope website

This folder contains a complete static site for GitHub Pages. The site does not
need a build step, a package installation, a JavaScript runtime or external
asset hosting. Tufte CSS, ET Book, the video and all the images are in this
folder.

## Publish on GitHub Pages

1. Commit `docs/` and the updated root `README.md`. Push them to `main`.
2. In the repository, open **Settings → Pages**.
3. Under **Build and deployment**, select **Deploy from a branch**.
4. Select **main** and **/docs**. Then save.

The canonical address of the site is:

<https://typoscope.chenna.me/>

The `.nojekyll` file makes the site a plain static site. Refer to the GitHub
[publishing-source documentation](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site).

The canonical URL, the Open Graph URLs, the structured data and the sitemap use
the custom domain above. Configure this domain and its DNS in GitHub Pages
before you publish. If the domain changes, update the absolute URLs in
`index.html` and `sitemap.xml`. The local assets use relative paths. Thus, they
also operate in the repository subdirectory of GitHub.

## Social previews and images

| Asset | Purpose |
| --- | --- |
| `assets/images/readme-header.png` | 1600 × 300 README header. It agrees with the light header of the video. |
| `assets/images/readme-header-dark.png` | Dark version. The picture element of the README selects it automatically. |
| `assets/images/social-card.png` | 1200 × 630 image. The Open Graph and Twitter/X metadata refer to it. |
| `assets/images/github-social.png` | 1280 × 640 repository social preview. |
| `assets/images/demo-poster.jpg` | Video poster, taken from the tight cut. |
| `assets/images/favicon.png` | 32 × 32 browser icon. |
| `assets/images/apple-touch-icon.png` | 180 × 180 home-screen icon. |

The social image of the website operates when the site is public. The
repository preview of GitHub has a different configuration. Open **Settings →
General → Social preview → Edit**. Then upload `assets/images/github-social.png`.
The README and the website HTML cannot set this option. Refer to the GitHub
[social-preview instructions](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/customizing-your-repositorys-social-media-preview).

The SEO data includes these items:

- A page title and a description
- A canonical URL
- A robots meta tag
- Open Graph and Twitter/X cards with image descriptions
- SoftwareSourceCode structured data
- `sitemap.xml`

No `robots.txt` restrictions are necessary. Search engines can index the site.

## Video

`assets/video/typoscope-demo.mp4` is the approved tight crop. It has the ET Book
overlays and the synthesized narration. The file is a 720 × 1280 H.264/AAC
export. Its length is 41.5 seconds. Its size is approximately 5 MB.

The player uses native controls, an explicit poster and `preload="none"`. The
video does not start automatically. The optional English WebVTT captions agree
with the narration. The full transcript is available next to the video.

The high-resolution rough cuts and the editing scripts are local files. They are
not in Git. The web assets in Git are sufficient to publish this site.

## Local preview and maintenance

From the repository root, run:

```sh
python3 -m http.server 8765 --directory docs
```

Open <http://localhost:8765/>. Edit `index.html` to change the text and the
metadata. Edit `assets/site.css` to change the small layout additions to Tufte
CSS.

The header, the social images and the icons use the ET Book fonts in this
folder. The scripts that make these images are not in Git. You do not need a
generation step to serve the images in Git.

## Attribution

- [Tufte CSS](https://github.com/edwardtufte/tufte-css), copied from the
  `gh-pages` branch on 2026-09-03. The only change replaces the font source URLs
  with the local TrueType files. License: `assets/vendor/TUFTE-CSS-LICENSE.txt`.
- [ET Book](https://github.com/edwardtufte/et-book). The site uses the same
  installed fonts as the video. License: `assets/fonts/ET-BOOK-LICENSE.txt`.
- The narration was made locally with the `af_heart` voice of Kokoro.

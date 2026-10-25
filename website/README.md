Automatic first-launch setup: on a fresh installation Howdoey opens Settings and starts downloading and configuring the local Ollama runtime and Qwen3.5:2b model. Progress and Cancel are visible; failed/cancelled setup can be retried with Download local AI. Existing saved providers are preserved. The app ZIP does not contain runtime or model weights; each device downloads them during setup. No developer credentials or Claude subscription is included.

## Current download publishing

The app ZIP is now committed at `website/downloads/Howdoey-macOS-arm64.zip` and copied into the static deployment. It is approximately 1.8 MB, below Cloudflare’s per-file limit. App downloads are enabled by default with a same-origin URL; R2 is needed only for independent video hosting. Set `HOWDOEY_PUBLIC_DOWNLOADS=false` to disable the button deliberately. A build verifies the archive against `release-metadata.json` before publishing. Replace both together for future releases. No macOS build is required in Cloudflare. The app remains a development-signed, non-notarized beta.

The earlier R2 archive publishing instructions below describe the previous optional workflow; the current build serves the committed app archive directly regardless of the media base URL.

# Cloudflare Workers Git deployment (current dashboard)

The root `wrangler.jsonc` supports the dashboard’s `npx wrangler deploy` command. Wrangler runs the static build itself. This also works with `website` as the root directory using its matching configuration.

| Dashboard setting | Value |
| --- | --- |
| Root directory | repository root (leave blank) |
| Build command | leave blank; Wrangler invokes the build |
| Deploy command | `npx wrangler deploy` |
| Worker name | `howdoey` |

No environment variable is needed for the initial website deployment. Without an R2 URL the two recorded videos use their public GitHub raw URLs. For release hosting, upload them to R2 and set `HOWDOEY_ASSETS_BASE_URL` as described below. The public app download is served directly from the committed ZIP; it does not need R2. The Linux deployment never tries to build the Swift app.

The current configs target Workers Static Assets. For a separate Pages deployment, use the dashboard’s Pages product with the static build settings below; remove the Workers config from that project’s configured root if its tooling rejects it. Do not run `wrangler pages deploy` against the Workers project.

---

# Howdoey website

Static website with two real recorded walkthroughs, screenshot gallery, native video controls, generic Terms and Privacy pages, and a download popup. No provider secrets belong in the website.

## Local preview

Run `node website/dev-server.mjs` from the repository root, then open http://127.0.0.1:8080. The loopback-only server serves the current desktop ZIP from `desktop/dist`, the real videos with byte-range seeking, and the policies. Clicking Download starts the actual archive and shows instructions using the supplied browser-download screenshot. The screenshot is illustrative; it is not an OS control. Users double-click the actual downloaded ZIP, move the app to Applications, and open it.

## Cloudflare Pages + R2

Pages has a 25 MiB per-file limit. Videos and application archives belong in R2, not Pages. No deployment or upload happens during a build.

1. Create an R2 bucket in your Cloudflare account. Attach a public custom domain, for example `assets.howdoey.com`. This example is not a provisioned domain. Public artifacts must contain no secrets; do not upload the original screen recordings or relay configuration.
2. Install/authenticate the Cloudflare Wrangler CLI using Cloudflare’s current instructions. From the repo root, build the desktop archive with `bash desktop/scripts/package.sh` if needed.
3. From `website`, set `HOWDOEY_ASSETS_BASE_URL=https://YOUR-ASSET-DOMAIN` and run `npm run build`. This creates `dist/` for Pages and `.r2-staging/` for R2. Missing videos fail the build. By default the public Download button reports unavailable.
4. Upload artifacts explicitly with `HOWDOEY_R2_BUCKET=YOUR-BUCKET npm run upload:assets`. This command writes to your Cloudflare account. It uploads the two MP4 files, existing ZIP, and portable checksum file. It does not upload source credentials or change bucket access settings.
5. Once artifacts are uploaded and your release is ready, rebuild with the same asset URL and `HOWDOEY_PUBLIC_DOWNLOADS=true`. Deploy `dist` with `npx wrangler pages deploy dist --project-name howdoey`, or connect the repository to Pages: root `website`, build command `npm run build`, output `dist`, environment variable `HOWDOEY_ASSETS_BASE_URL`. Set `HOWDOEY_PUBLIC_DOWNLOADS=true` only when intentionally publishing that archive.
6. Add `howdoey.com` as the Pages custom domain in Cloudflare. Preview video loading, seeking, both demos, policy navigation, and download on an actual Mac before announcing the release.

The build writes a static `releases.json` with SHA-256, archive size, architecture, and signing status. No Node server or `/api/download` endpoint is required in production. The current manifest deliberately says `notarized: false` because the current archive is a development build. Update signing metadata only after an actual Developer ID signing/notarization release process. Refer to `desktop/README.md` for signing requirements. A local development certificate does not establish public distribution trust.

## Local model setup

The ZIP contains Howdoey. On first launch, users choose **Download local AI** in Settings. That downloads a checksum-verified Ollama runtime and Qwen3.5:2b vision model, then selects the local endpoint. It requires internet for setup, about 3 GB of downloads, and at least 8 GB free disk. Initial support is Apple silicon, macOS 14+. Existing provider settings are preserved. Users can keep an optional remote provider instead. No developer API key is shipped in the app or site.

Model weights use Apache 2.0; Ollama uses MIT. These are separate licenses, not a claim that all model training data and training code are available. See the links in `desktop/LOCAL_AI.md`.

## Media and policies

`media/email-demo.mp4` and `media/community-demo.mp4` are browser exports of the two supplied recordings. Originals remain on the Desktop. The second recording demonstrates signing up for a computer class. Gallery PNGs remain in `assets/howdoey/`. Review recorded personal details before public release.

The Terms and Privacy pages describe current beta behavior and use the repository as a contact route. They do not assert legal compliance, an invented company identity, or a support email.

References: https://developers.cloudflare.com/pages/platform/limits/ and https://developers.cloudflare.com/r2/buckets/public-buckets/.

## GitHub → Cloudflare dashboard settings

In **Workers & Pages → Create → Pages → Connect to Git**, choose `atakanturg/howdoey`, then the branch containing these changes. Configure:

| Setting | Value |
| --- | --- |
| Framework preset | None |
| Root directory | `website` |
| Build command | `npm run build` |
| Build output directory | `dist` |
| Environment: `NODE_VERSION` | `22` |
| Environment: `HOWDOEY_ASSETS_BASE_URL` | Your actual public R2 HTTPS domain |
| Environment: `HOWDOEY_PUBLIC_DOWNLOADS` | `true` only after the matching archive is uploaded |

No macOS or Swift build runs inside Cloudflare’s Linux build environment. The desktop source can live alongside the website in GitHub; only the static website is built by Pages. `release-metadata.json` carries the checksum and size of the separately uploaded archive, allowing a clean GitHub checkout to build without `desktop/dist`. Regenerate it when replacing the downloadable app. `npm run build` never deploys or uploads.

Favicon uses the existing logo. `robots.txt`, canonical URLs, `sitemap.xml`, Open Graph/Twitter metadata, basic SoftwareApplication structured data, and a real 404 page are included. Canonical URLs target `https://howdoey.com`; add that custom domain before requesting indexing. Cloudflare branch previews automatically receive noindex headers and a disallow-all robots file. The production branch defaults to `main`; set `HOWDOEY_PRODUCTION_BRANCH` if yours differs. Do not block production indexing accidentally.

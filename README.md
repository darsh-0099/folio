# Folio

Native SwiftUI eBook reader for iPhone, iOS 17+. Bundle ID: `com.folio.reader`.

## Status

**Folio 1.1 (build 2): clean device build and all 29 iOS tests passed** in
[Actions run 44878668522](https://github.com/darsh-0099/folio/actions/runs/44878668522).
The verified unsigned arm64 IPA is in **Folio-device-unsigned**, together with the
complete generated Xcode project and checksum. Bundle ID `com.folio.reader`, iPhone
only, iOS 17+. The unchanged identifier supports updating an existing installation.

New in 1.1: searchable/sortable library, Continue Reading, completion filters, safe
removal confirmations, weekly Activity charts, corrected reading-time accounting,
per-source pagination, durable transfer receipts, stricter access flags, annotation
search/deduplication, and Gutenberg maintenance fallback. See
[release notes](docs/RELEASE_1_1.md).

The live UI test downloaded a real book, opened Readium, adjusted font size, saved a
bookmark, relaunched, reopened the book and confirmed download deletion. Physical
SideStore installation, airplane mode and background transfers remain manual checks.
See [docs/STATUS.md](docs/STATUS.md) for evidence and limits; this is not a claim of a
complete production/device QA pass.

## Build entirely on GitHub

1. Open **Actions → iOS device IPA and tests**. Pushes to main trigger it automatically;
   **Run workflow** also starts a build.
2. The macOS runner installs XcodeGen, resolves Readium 3.5.0, performs a clean Release
   build for **generic iOS / iphoneos**, checks the arm64 executable and packages it.
3. Download **Folio-device-unsigned** from the successful run. Unzip the artifact once
   to obtain `Folio.ipa` (do not unzip the IPA). The artifact also includes the generated
   complete `Folio.xcodeproj` and SHA-256 checksum.
4. Inspect **Folio-test-results** for the simulator XCTest result bundle.

No Apple certificate or paid developer membership is needed to build this unsigned
package. GitHub-hosted macOS runner availability and Actions permissions are required.
The build uses Apple Xcode on GitHub even if no local Xcode is installed.

### Rebuild locally on a Mac (optional)

Install Xcode with an iOS SDK and XcodeGen (`brew install xcodegen`), then:

```sh
scripts/build-ipa.sh
# Output: build/Folio.ipa
```

`project.yml` is the reproducible project source. The generated `Folio.xcodeproj`
and dependency lockfile are included. `xcodegen generate` recreates the Xcode
project with the app, XCTest and UI test targets. Dependency: Readium Swift Toolkit **3.5.0**
(BSD-3-Clause), products Shared, Streamer, Navigator and AdapterGCDWebServer; transitive
SPM dependencies are resolved by Xcode. No LCP binaries or private entitlements.
The workflow uploads the generated project including its resolved package versions.

## Install with SideStore

1. Set up a current SideStore installation and its required pairing/VPN configuration
   using [SideStore's official instructions](https://docs.sidestore.io/).
2. Transfer `Folio.ipa` to Files on the iPhone.
3. In SideStore open **My Apps → +**, select the IPA, and let SideStore sign and install it
   with your Apple account.
4. Refresh the app before its signing expires. Free-account limits and provisioning
   rules apply; SideStore manages signing. This repository cannot verify your personal
   signing configuration or guarantee a particular SideStore version's behavior.

When updating, retain the existing app and install the new IPA through SideStore with
the same account/identifier so its sandbox data can be preserved.

The package contains `Payload/Folio.app/`, targets iPhone arm64, and uses standard
frameworks. Background URLSession needs no special background entitlement. The app is
unsigned until SideStore signs it. Never install a simulator `.app` or ZIP of source code.

## Implemented

- Five working tabs: live discovery, filtered search, offline library, activity and settings.
- Gutendex public-domain catalog; Open Library official search/work metadata, covers,
  publication/language/subject information and edition identifiers; Archive metadata/files.
- Source-attributed details, saved books, download progress/cancel/retry, file checks,
  missing-file recovery, storage usage and deletion.
- Gutenberg EPUB3-with-images downloads can retry once on its HTTPS distribution
  host during primary-site 502/503/504 outages. Authentication/permission errors, missing
  files and rate limits do not trigger fallback.
- Conservative Archive rights allowlist: CC0, public-domain mark, CC BY 4.0 and CC BY-SA
  4.0 URLs. Dark/restricted/private files are excluded. Gutenberg copyright must be false.
  Availability is a catalog declaration, not a worldwide copyright determination.
- Readium EPUB pagination/scrolling, TOC, native selection, images and hyperlinks,
  font/spacing/margin/theme controls, locator-based resume, bookmarks, highlights and
  notes, annotation deletion and paged full-book search. Selected-passage speech controls.
- PDFKit page/zoom/search/resume. UTF-8 plain text viewing has no EPUB features.
- Persistent daily time, goal, reading/completed counts and streaks. Two-minute inactivity
  cutoff; the operating system's active-app state excludes background reading time.
- Dynamic Type SwiftUI screens, system controls, accessible labels and light/dark UI.
- No account, analytics, embedded API credentials or required backend.

## Tests and verification

`FolioTests` contains 27 tests covering decoding, missing metadata, copyright/license/access gates,
malformed responses, duplicate records, streak boundaries, disk-backed SwiftData reopen,
locator and annotation persistence, offline file existence/deletion and corrupt-download
rejection. Run them through Actions or `xcodebuild test` on a Mac.

`FolioUITests` covers tab navigation and reader settings. Push builds also run a live
Gutenberg search/download/read/bookmark/relaunch/delete integration test. Public catalog
availability is required. Manual workflow runs can disable this live test with the
`live_reading_flow` input.

`python3 -m unittest discover -s scripts -p 'test_*.py'` exercises package rejection and
project checks on Linux. This is not a substitute for Swift compilation or device tests.

See [docs/ACCEPTANCE.md](docs/ACCEPTANCE.md) for the physical-device flow and
[docs/STATUS.md](docs/STATUS.md) for verified results and limitations.

## Limitations

- AI provider integration is deferred. Settings correctly says no provider is configured;
  no AI request or credential storage is presented as functional.
- Cross-source matches with the same normalized title and author are grouped with explicit
  alternate-edition navigation. Same-source differing editions remain distinct.
- Author names and edition IDs are displayed; dedicated author biographies and rich
  edition comparison are not implemented.
- Interrupted background transfers recover as retryable failures when the OS cannot
  reconnect them. They restart rather than guarantee byte-range resume.
- EPUB speech reads selected text, not an automatic whole-book narration session.
- Plain-text reading has no position/statistics tracking; PDF has no EPUB annotations.
- The Linux workspace cannot compile iOS. GitHub Actions established device-build and
  simulator-flow correctness; an iPhone must establish physical-device behavior.
- Simulator transfers use a foreground session; real devices use background URLSession.
  Background behavior has not been validated on an iPhone.

## Privacy and rights

Queries reach Gutendex and Open Library; cover and download hosts receive normal HTTP
requests. Reading records remain in the app sandbox. Book downloads are excluded from
backup to avoid duplicating large files; annotations and metadata use SwiftData.
Public-domain status varies by country. Verify the source record before downloading.
Folio does not bypass loans, authentication, DRM or other access controls.

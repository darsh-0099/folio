# Folio

Native SwiftUI eBook reader for iPhone, iOS 17+. Bundle ID: `com.folio.reader`.

## Status

Implementation is under active verification. This repository contains real catalog clients,
SwiftData persistence, background downloads, Readium EPUB integration and PDFKit viewing.
Do not treat the app as production verified until the Actions device build, tests and
physical-device acceptance checklist pass. An IPA is available only when the device
build workflow succeeds; a source archive is not an installable app.

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

`project.yml` is the reproducible project source. `xcodegen generate` recreates the Xcode
project with an app and XCTest target. Dependency: Readium Swift Toolkit **3.5.0**
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

The package contains `Payload/Folio.app/`, targets iPhone arm64, and uses standard
frameworks. Background URLSession needs no special background entitlement. The app is
unsigned until SideStore signs it. Never install a simulator `.app` or ZIP of source code.

## Implemented

- Five working tabs: live discovery, filtered search, offline library, activity and settings.
- Gutendex public-domain catalog; Open Library official search/work metadata, covers,
  publication/language/subject information and edition identifiers; Archive metadata/files.
- Source-attributed details, saved books, download progress/cancel/retry, file checks,
  missing-file recovery, storage usage and deletion.
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

`FolioTests` includes decoding, missing metadata, copyright/license/access gates,
malformed responses, duplicate records, streak boundaries, disk-backed SwiftData reopen,
locator and annotation persistence, offline file existence/deletion and corrupt-download
rejection. Run them through Actions or `xcodebuild test` on a Mac.

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
- Local iOS compilation is impossible in the initial Linux workspace. GitHub Actions
  and an iPhone must establish build and end-to-end correctness.

## Privacy and rights

Queries reach Gutendex and Open Library; cover and download hosts receive normal HTTP
requests. Reading records remain in the app sandbox. Book downloads are excluded from
backup to avoid duplicating large files; annotations and metadata use SwiftData.
Public-domain status varies by country. Verify the source record before downloading.
Folio does not bypass loans, authentication, DRM or other access controls.

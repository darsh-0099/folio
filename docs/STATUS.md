# Verified build and test results

Successful GitHub Actions run: https://github.com/darsh-0099/folio/actions/runs/43823195236

Tested application commit: `41c634da65f03ec5dca9c9b5bfa8942f0dfff761`.
Subsequent documentation-only commits do not change this executable.

- Clean iPhoneOS Release device build: **passed**.
- Toolchain: **Xcode 16.4, Swift 6.1.2**, minimum deployment **iOS 17.0**.
- Executable: **arm64**, Mach-O platform **iOS (2)**, minimum OS **17.0**.
- App: `com.folio.reader`, iPhone device family `[1]`.
- Signing: **unsigned**, for SideStore to re-sign. No provisioning profile is embedded.
- Package: `Payload/Folio.app/`, app icons, SwiftPM Readium resources and dependency
  linkage checked. ZIP CRC checks and independent Mach-O verification passed.
- **10 unit/persistence tests passed**, zero failures.
- **2 simulator UI tests passed**, zero failures.
- **4 local Python packaging/configuration tests passed**, zero failures.
- All **15 Swift source files** passed local syntax parsing; compilation was separately
  verified by the actual Apple SDK build above.

IPA SHA-256:
`c14a058541c6cf9519387d018d64b2ebc1d88cc0b9458f2023541b1208e73280`

Device artifact: https://github.com/darsh-0099/folio/actions/runs/43823195236/artifacts/14205537492

## What the UI test actually established

The test used real public catalogs and the actual Project Gutenberg #1342 EPUB.
It searched for Pride and Prejudice, opened details, downloaded the EPUB, opened
Readium, saved a bookmark, navigated, terminated the app, relaunched, opened the local
book, verified a nonempty persisted annotation list, closed the reader, deleted the
file and verified the Read action disappeared. A separate UI test opened all five tabs
and changed the continuous-scrolling preference. Persistence tests reopened an on-disk
SwiftData store and asserted exact saved progress/locator and note values.

The simulator uses foreground URLSession transfers through the same delegate,
validation and storage pipeline. Physical iPhones use background URLSession. Simulator
success does not establish physical-device background transfer or SideStore signing.

## Remaining verification and feature limits

No physical iPhone or SideStore signing session was available. The airplane-mode flow,
real-device background transfers, interruption recovery, VoiceOver audit, PDF reading,
text selection/highlight rendering, speech playback, TOC and visual appearance changes
need the manual checks in ACCEPTANCE.md. No claim of a complete device QA pass is made.

AI provider integration and dedicated author biographies/edition comparison are deferred.
Speech reads selected EPUB text, not automatic whole-book narration. PDF has page/zoom/
search/resume but no EPUB annotations. Plain text has no reading-position/statistics
tracking. Interrupted transfers restart when necessary rather than guaranteeing byte
resume. See README.md for the full feature scope and installation instructions.

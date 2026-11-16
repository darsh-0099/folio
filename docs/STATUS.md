# Verification record

Initial environment: Linux x86_64. No Swift compiler, Xcode, Apple SDK, simulator,
physical iPhone connection or local Apple signing identity. A local device build and
IPA cannot be produced here. GitHub Actions macOS is configured as the build environment.

Readium integration inspected against actual 3.5.0 source, commit
`8bd799d00a835248a6f5987f70c23c4c30280e48`, including PublicationOpener,
AssetRetriever, EPUBNavigatorViewController, EPUBPreferences, Locator, decorations,
editing actions and SearchIterator. API inspection is not compilation verification.

Swift tests and physical-device acceptance are pending the build workflow and device.
See the latest Actions run for actual compiler and XCTest results.

Local checks performed:

- Four Python packaging/configuration tests passed, including rejecting simulator-only
  and missing-executable packages. No placeholder IPA was generated.
- All 14 Swift files passed tree-sitter Swift syntax parsing (not SDK type checking).
- Live Gutendex #1342 response: copyright false, actual EPUB-with-images URL present.
- Live Open Library title search returned two documents with requested metadata fields.
- Actual Gutenberg #1342 EPUB downloaded outside the repository for inspection: correct
  mimetype, META-INF/container.xml, 182 ZIP entries, no CRC errors. It was not rendered
  by Readium here because no iOS runtime is available.

GitHub Actions run 43817863061: Xcode 16.4 / Swift 6.1.2. Clean iphoneos Release
build succeeded. IPA arm64, identifier, minimum OS, platform, assets and dependencies
checks passed; signing state confirmed unsigned. Test-target compilation found a
Readium Locator test using String instead of RelativeURL; corrected in the next commit.
The IPA from this run predates the background-download startup/retry fixes.

Run 43818911060: revised device build and package checks passed. All 10 unit tests
and the five-tab/settings UI test passed. The live UI test reached the real book
details and tapped Download but timed out before Read appeared. Download validation
and simulator transfer diagnostics are being investigated; do not claim the end-to-end
reader flow has passed yet. Simulator transfers now use a foreground session with the
same delegate/validation/storage code; physical devices retain background URLSession.

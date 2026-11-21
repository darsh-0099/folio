# Folio 1.1 — verified build and test results

Successful run: https://github.com/darsh-0099/folio/actions/runs/44878668522

Tested application commit: `1575a5f34e34aadae8be9e00c4c9ebc0f4720a9d`.
Later documentation/project synchronization commits do not change the executable.

- Version **1.1 (build 2)**; bundle ID **com.folio.reader**; iPhone family `[1]`.
- Clean iPhoneOS Release build: **passed**, with Xcode 16.4 / iPhoneOS 18.5 SDK.
- Mach-O: **arm64**, physical iOS platform **2**, minimum OS **17.0**.
- Signing: **unsigned**, ready for SideStore to re-sign with the user's account.
- Package: `Payload/Folio.app/`, icons, Readium resources and dependencies verified.
  Archive CRCs and independent executable/platform checks passed.
- **27 unit/persistence tests passed**, zero failures.
- **2 simulator UI tests passed**, zero failures.
- **4 local packaging/configuration tests passed**, zero failures.
- All **17 Swift files** passed local syntax parsing; the Apple SDK compilation
  above separately establishes type checking and linkage.

IPA SHA-256:
`191f7686e0d4ca771c1ec107c36134db4be6589bec82f56c70d3f20e6554d5ae`

Device artifact: https://github.com/darsh-0099/folio/actions/runs/44878668522/artifacts/14696433541

## Verified behavior

Unit tests cover API decoding and malformed/missing metadata; per-source pagination
and failed-source retry cursors; Archive rights and access flags; mirror eligibility;
duplicate books/files/bookmarks; library search/sorting/filtering; reading intervals,
inactivity and midnight; disk-backed locator/note restoration; local deletion and
transfer-state cleanup; receipt serialization/path validation; valid/corrupt PDFs and
corrupt/incomplete EPUB rejection.

The live UI test searches for Gutenberg #1342, opens its details, downloads the real
EPUB, opens Readium, changes the font-size slider through the reader appearance sheet,
saves a bookmark, navigates, terminates, relaunches, opens the local book, checks the
annotation list, closes the reader, confirms deletion, and verifies Read disappears.
A separate UI test navigates all five tabs and changes continuous-scrolling settings.

During development Gutenberg's primary download site returned HTTP 503 with a
maintenance notice. The same public-domain EPUB was independently downloaded from
`gutenberg.pglaf.org`: HTTP 200, 24,864,480 bytes, correct EPUB mimetype/container,
182 ZIP entries, valid CRCs and the title Pride and Prejudice. Folio now performs one
fallback for recognized Gutenberg EPUB3-with-images URLs on 502/503/504 only. Access
denials, missing editions, rate limits and non-Gutenberg sources never use this route.

## Remaining device QA and limits

No iPhone or SideStore signing session was available. Physical-device installation,
airplane mode, background transfers/retry scheduling and interruption recovery still
need manual verification. The simulator uses foreground URLSession through the same
validation/storage pipeline; iPhones retain background URLSession.

Interactive PDF navigation/zoom/search, highlight rendering and text-selection notes,
speech, detailed VoiceOver/contrast testing and broad EPUB compatibility still need
manual coverage. PDF file validation and annotation storage have automated tests;
those tests do not establish every reader interaction.

AI integration, author biographies and rich edition comparison remain deferred.
Speech reads selected EPUB text. PDF has no EPUB annotations. Plain text has no
position/statistics tracking. Interrupted transfers may restart rather than resume
at a byte boundary. See ACCEPTANCE.md and README.md for installation and full scope.

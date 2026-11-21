# Folio 1.2 — build 3 verification

Build run: https://github.com/darsh-0099/folio/actions/runs/44956691849

Application commit: `1188fad8ce49e07040d1306511a868def7a1a49f`.
Later documentation/project synchronization commits do not change the executable.

- Version **1.2 (build 3)**; bundle ID **com.folio.reader**; iPhone family `[1]`.
- Clean iPhoneOS Release build: **passed**, with Xcode 16.4 / iPhoneOS 18.5 SDK.
- Mach-O: **arm64**, physical iOS platform **2**, minimum OS **17.0**.
- Signing: **unsigned**, for SideStore to re-sign with the user's account.
- Package: `Payload/Folio.app/`, icons, Readium resources and dependencies verified.
  Archive CRCs and independent executable/platform checks passed. No embedded signing
  profile, code signature or test-book fixture is present in the Release package.
- **42 unit/persistence tests passed**, zero failures.
- **2 simulator UI tests passed**, zero failures.
- Full GitHub Actions workflow: **success**, including the live Gutenberg flow.
- **4 local packaging/configuration tests passed**, zero failures.
- All **19 Swift files** passed local syntax parsing; Apple SDK compilation above
  separately establishes application type checking and linkage.

IPA: 5,327,125 bytes. SHA-256:
`e59eb5daa16d74dfc38b024e9b89772e1065692ea321b5b6c2f222fe2dfc8c72`

Device artifact: https://github.com/darsh-0099/folio/actions/runs/44956691849/artifacts/14728081875

Test result bundle: https://github.com/darsh-0099/folio/actions/runs/44956691849/artifacts/14728660559

## Test scope

Unit tests cover API decoding and malformed/missing metadata; per-source pagination
and failed-source retry cursors; Archive rights and access flags; mirror eligibility;
duplicate books/files/bookmarks; library search/sorting/filtering; reading intervals,
inactivity and midnight; disk-backed locator/note restoration; local deletion and
transfer-state cleanup; receipt serialization/path validation; valid/corrupt PDFs and
corrupt/incomplete EPUB rejection.

Build 3 adds actual EPUB/PDF/TXT import and metadata parsing, content-hash duplicate
imports, reimport after deletion without losing position, invalid/oversized/unsupported
file rejection, editable notes preserving identity/locator, PDF page validation and
protection against initial page notifications overwriting the saved position. Catalog
URL and copyright-filter tests cover the simplified Gutendex query. The EPUB fixture
is an original MIT-licensed publication, limited to the test bundle.

The live UI test searches for Gutenberg #1342, opens details, downloads the real EPUB,
opens Readium, changes font size, saves a bookmark, navigates, terminates, relaunches,
opens the local book, requires an actual saved annotation row, closes the reader,
confirms deletion, and verifies Read disappears. A separate UI test navigates all five
tabs and changes continuous-scrolling settings. These are simulator UI tests.

## Service availability during development

An earlier build 3 run passed all 39 then-current unit tests but its live search failed:
Gutendex timed out while Open Library returned results. The captured accessibility
hierarchy confirmed the cause. Direct public requests reproduced the timeout with the
filtered URL; the default case-insensitive search endpoint returned real results.
Folio now uses a canonical query/default first page, filters copyright declarations in
the decoded response, and exposes Retry for partial catalog failures. The live test
keeps the real service dependency and captures search/download diagnostics on failure.

Gutenberg's primary download site also returned HTTP 503 during earlier development.
Folio retries the same public-domain EPUB once on `gutenberg.pglaf.org` for recognized
EPUB3-with-images URLs on 502/503/504 only. Access denials, missing editions, rate limits
and non-Gutenberg sources never use this route. The downloaded mirror book was checked
independently: correct EPUB mimetype/container, 182 entries, valid CRCs, 24,864,480 bytes,
and title Pride and Prejudice.

## Remaining device QA and limits

No iPhone or SideStore signing session was available. Physical installation, airplane
mode, background transfers/retry scheduling and interruption recovery still need manual
verification. The simulator uses foreground URLSession through the same validation and
storage pipeline; iPhones retain background URLSession.

The native Files picker, iCloud provider access, interactive PDF navigation/zoom/search,
highlight rendering, note-editing UI, speech, detailed VoiceOver/Dynamic Type checks and
broad EPUB compatibility need manual coverage. Import tests call the real importer and
Readium/PDFKit with local files; they do not establish file-provider UI behavior.

AI integration, author biographies and rich edition comparison remain deferred.
Speech reads selected EPUB text. PDF has no EPUB annotations. Plain text has no
position/statistics tracking. Interrupted transfers may restart rather than resume
at a byte boundary. See ACCEPTANCE.md and README.md for installation and full scope.

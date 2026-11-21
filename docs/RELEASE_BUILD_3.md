# Folio 1.2 — build 3

- Import EPUB, PDF and UTF-8 TXT from Files using security-scoped access and coordinated
  reads. Copies are staged in app storage, validated and content-hashed before being
  added to SwiftData. Duplicate imports reuse the existing book and saved position.
- Reimport a deleted local file to restore offline availability without resetting notes
  or reading progress. EPUB/PDF titles and authors are read from document metadata.
- Edit saved annotation notes with explicit Save/Cancel and error handling. The locator
  and annotation identity stay unchanged. Existing annotation search includes edits.
- PDF page selection validates the range and disables invalid navigation. Resume is
  applied after layout; the navigation bar reports current page and page count.
- Adaptive accent colors for light/dark appearance; darker cover placeholders improve
  white-text contrast. Reader preferences have a confirmed reset action.
- Stronger live bookmark assertion checks an actual saved annotation row.
- New offline import, duplicate/reimport, note editing, page validation and file rejection
  tests. The original MIT-licensed EPUB fixture is test-only; production catalogs remain
  live and the live UI test still downloads the real Gutenberg #1342 book.

Imported text files are limited to 10 MB for the plain-text view. EPUB/PDF remain the
recommended formats for large books. Import does not remove DRM or grant content rights.

Verification is in progress. The final build and test report will be in STATUS.md.

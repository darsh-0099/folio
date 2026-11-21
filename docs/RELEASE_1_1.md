# Folio 1.1 improvements

- Search and sort the library by recently read, recently added, title or author.
  Filter all/downloaded/reading/finished books, continue the last local book directly,
  and change completion state through a context menu.
- Confirm file/entry removal; preserve positions and notes when deleting only a file.
  Bulk storage deletion also cancels active transfers and clears stale transfer state.
- Reading time pauses while tools cover the reader, excludes inactivity, and splits
  intervals across local midnight. Activity shows a real seven-day chart and goal line.
- Track pagination independently for Gutenberg and Open Library. Exhausted sources stop;
  failed sources keep their page for retry. Subject search uses Gutendex's topic field.
- Bound metadata cache size and prevent repeated metadata from duplicating download links.
  Downloaded-book details use persisted metadata without requiring a network refresh.
- Persist transfer receipts before validation, recover them on launch, and retain old
  downloads if a replacement cannot be committed. Ignore obsolete/cancelled receipts.
- Decode Archive private/restricted/dark flags conservatively across boolean, integer
  and string representations. Canonicalize only known Creative Commons license URLs.
- Merge repeated bookmarks, search annotations, add explicit appearance Done controls,
  and keep PDF content within safe areas. No library schema changes are required.
- Handle primary Gutenberg maintenance through one HTTPS retry on its distribution
  mirror for the same public-domain EPUB. Only 502/503/504 responses qualify; access
  denials, missing files and rate limits never trigger mirror routing. HTTP errors
  now include an actionable status message.
- Add regression tests for time accounting, library behavior, access flags, pagination,
  receipts and PDF validation. The live reading test also adjusts font size.

Version: 1.1 (build 2), same bundle identifier com.folio.reader. The clean device build and all 29 iOS tests passed in Actions run 44878668522.
See docs/STATUS.md for build evidence, test scope and remaining physical-device checks.

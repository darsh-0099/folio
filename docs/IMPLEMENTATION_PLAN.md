# Implementation and validation plan

1. Inspect host/toolchain and establish device-build route. Done: Linux only; use macOS CI.
2. Build catalog models and official API clients; verify real responses. Implemented;
   live Gutendex, Open Library and Gutenberg download checks passed.
3. Connect discover, filtered search, details, edition/source attribution and rights gates.
   Implemented; iOS execution pending.
4. Add SwiftData library, persistent downloads, validation, cancellation and offline files.
   Implemented; XCTest and device recovery checks pending.
5. Integrate pinned Readium, stable locators, appearance, TOC, search and annotations.
   Implemented against toolkit source; Apple SDK compilation and runtime pending.
6. Add PDFKit, statistics, settings and selected-passage speech. Implemented;
   runtime validation pending. AI provider integration explicitly deferred.
7. Run syntax and packaging checks locally; run clean device build and XCTest on GitHub.
   Local checks passed; GitHub upload blocked by connection permissions.
8. Verify device artifact, install with SideStore and execute physical-device checklist.
   Pending successful CI and access to an iPhone; never substitute simulator packaging.

Current external blocker: GitHub API returns 403 Resource not accessible by integration
for writes to darsh-0099/folio. Repository is visible with read access. No source upload,
workflow run or device artifact is claimed until access is corrected.

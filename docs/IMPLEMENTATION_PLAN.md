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
   Local checks passed; source uploaded and GitHub Actions device build started.
8. Verify device artifact, install with SideStore and execute physical-device checklist.
   Pending successful CI and access to an iPhone; never substitute simulator packaging.

Repository access was corrected. Source and the macOS build workflow are on main.
The first Actions build is being monitored; device artifacts are not claimed until verified.

# Implementation and validation plan — final status

1. Environment inspection: completed. The workspace is Linux with no Apple SDK;
   GitHub Actions macOS supplies the actual Xcode device and simulator toolchain.
2. Catalog models, official API clients, live-response verification: completed.
3. Discover, search, detail screens, edition grouping and rights gates: implemented.
4. SwiftData library, downloads, validation, cancellation, offline files: implemented.
5. Readium EPUB navigation, locators, appearance, search and annotations: implemented.
6. PDFKit, statistics, settings and selected-passage speech: implemented.
   AI provider integration is explicitly deferred.
7. Clean device build, packaging checks, 10 unit/persistence tests and 2 UI tests:
   passed in Actions run 43823195236. The live UI flow includes download, reading,
   relaunch, persisted bookmark and deletion.
8. Generated Xcode project, dependency lockfile, verified unsigned IPA, source archive,
   README and test results: delivered. Source is maintained in darsh-0099/folio.
9. Physical-iPhone/SideStore installation, airplane mode and the broader manual QA
   checklist: pending hardware access. These cannot be inferred from simulator tests.

import XCTest

final class FolioUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testFiveTabsAndReaderSettings() {
        let app = XCUIApplication(); app.launch()
        for title in ["Search", "Library", "Activity", "Settings", "Discover"] {
            let tab = app.tabBars.buttons[title]
            XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        }
        app.tabBars.buttons["Settings"].tap()
        app.buttons["Reader preferences"].tap()
        XCTAssertTrue(app.switches["Continuous scrolling"].waitForExistence(timeout: 10))
        app.switches["Continuous scrolling"].tap()
    }
    // Real network integration: no hardcoded results or fake EPUB.
    // Availability of public services is required.
    func testLiveGutenbergDownloadReaderAndRelaunch() throws {
        let app = XCUIApplication(); app.launch()
        app.tabBars.buttons["Search"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 20))
        search.tap(); search.typeText("Pride and Prejudice\n")
        let book = app.descendants(matching: .any).matching(identifier: "book.gutenberg:1342").firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 90)); book.tap()
        let download = app.buttons["download.epub"].firstMatch
        for _ in 0..<5 where !download.isHittable { app.swipeUp() }
        if download.exists { download.tap() }
        let read = app.buttons["reader.open"]
        XCTAssertTrue(read.waitForExistence(timeout: 180))
        for _ in 0..<5 where !read.isHittable { app.swipeDown() }
        read.tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 90))
        let bookmark = app.buttons["Bookmark this position"]
        XCTAssertTrue(bookmark.waitForExistence(timeout: 20)); bookmark.tap()
        app.webViews.firstMatch.swipeLeft()
        app.terminate(); app.launch()
        app.tabBars.buttons["Library"].tap()
        let saved = app.descendants(matching: .any).matching(identifier: "library.gutenberg:1342").firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 30)); saved.tap()
        let resume = app.buttons["reader.open"]
        for _ in 0..<5 where !resume.isHittable { app.swipeUp() }
        XCTAssertTrue(resume.waitForExistence(timeout: 20)); resume.tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 90))
        app.buttons["Chapters, search and annotations"].tap()
        app.buttons["Bookmarks, highlights and notes"].tap()
        XCTAssertTrue(app.navigationBars["Annotations"].waitForExistence(timeout: 10))
        XCTAssertGreaterThan(app.cells.count, 0, "A saved bookmark must survive relaunch")
        app.buttons["Done"].tap()
        app.buttons["Close"].tap()
        let delete = app.buttons["Delete download"]
        for _ in 0..<5 where !delete.isHittable { app.swipeUp() }
        XCTAssertTrue(delete.waitForExistence(timeout: 10)); delete.tap()
        XCTAssertFalse(app.buttons["reader.open"].exists)
        // Persistence values are asserted by disk-reopen unit tests. A physical
        // device with airplane mode is still required by docs/ACCEPTANCE.md.
    }
}

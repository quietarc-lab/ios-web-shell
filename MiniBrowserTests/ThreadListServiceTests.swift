import Foundation
import XCTest
@testable import MiniBrowser

final class ThreadListServiceTests: XCTestCase {
    func testSortURLsMatchOfficialListModes() {
        XCTAssertEqual(ThreadListSort.momentum.url.absoluteString,
                       "https://img.2chan.net/b/futaba.php?mode=cat&sort=6")
        XCTAssertEqual(ThreadListSort.list.url.absoluteString,
                       "https://img.2chan.net/b/futaba.php?mode=cat")
        XCTAssertEqual(ThreadListSort.allCases.map(\.title), ["勢順", "カ順"])
        XCTAssertEqual(ThreadListSort.allCases.map(\.accessibilityTitle), ["勢い順", "カタログ順"])
        XCTAssertEqual(ThreadListSort.allCases.count, 2)
    }

    func testListParserPreservesOrderLimitsItemsAndUsesHTTPS() {
        let cells = (1...35).map { number in
            """
            <td><a href='res/\(1000 + number).htm' target='_blank'>
            <img src='http://img.2chan.net/b/cat/\(number)s.jpg'></a>
            <br><font size=2>\(number * 2)</font></td>
            """
        }.joined(separator: "\n")
        let html = "<html><table id='cattable'><tr>\(cells)</tr></table></html>"

        let items = ThreadListService.parseListHTML(
            html,
            baseURL: ThreadListSort.momentum.url,
            limit: 30
        )

        XCTAssertEqual(items.count, 30)
        XCTAssertEqual(items.first?.id, "1001")
        XCTAssertEqual(items.last?.id, "1030")
        XCTAssertEqual(items.first?.threadURL.absoluteString,
                       "https://img.2chan.net/b/res/1001.htm")
        XCTAssertEqual(items.first?.thumbnailURL.scheme, "https")
        XCTAssertEqual(items.first?.replyCount, 2)
    }

    func testListParserRejectsForeignURLs() {
        let html = """
        <table id="cattable"><tr><td>
        <a href="https://example.com/res/123.htm"><img src="https://example.com/a.jpg"></a>
        <font>5</font></td></tr></table>
        """
        XCTAssertTrue(ThreadListService.parseListHTML(
            html,
            baseURL: ThreadListSort.list.url
        ).isEmpty)
    }

    func testListParserExcludesCompletedThreadsAndReturnsSixtyItems() {
        let cells = (1...65).map { number in
            let replies = number == 3 ? 1_000 : number
            return """
            <td><a href='res/\(2000 + number).htm'>
            <img src='/b/cat/\(number)s.jpg'></a><font>\(replies)</font></td>
            """
        }.joined(separator: "\n")
        let html = "<table id='cattable'><tr>\(cells)</tr></table>"

        let items = ThreadListService.parseListHTML(
            html,
            baseURL: ThreadListSort.momentum.url,
            limit: 60
        )

        XCTAssertEqual(items.count, 60)
        XCTAssertFalse(items.contains(where: { $0.replyCount >= 1_000 }))
        XCTAssertEqual(items.first?.id, "2001")
        XCTAssertEqual(items.last?.id, "2061")
    }

    func testListParserExcludesTemporarilyUnavailableThreads() {
        let cells = (1...3).map { number in
            """
            <td><a href='res/\(3000 + number).htm'>
            <img src='/b/cat/\(number)s.jpg'></a><font>\(number)</font></td>
            """
        }.joined(separator: "\n")
        let html = "<table id='cattable'><tr>\(cells)</tr></table>"

        let items = ThreadListService.parseListHTML(
            html,
            baseURL: ThreadListSort.list.url,
            limit: 3,
            excludingIDs: ["3002"]
        )

        XCTAssertEqual(items.map(\.id), ["3001", "3003"])
    }

    func testOpenerParserConvertsBreaksLinksAndEntities() {
        let html = """
        <html><div class="thre" data-res="123">
        metadata<a href="/b/src/a.jpg"><img src="a.jpg"></a>
        <blockquote>一行目<br><a href="/jump">リンク</a>&amp;&#12316;</blockquote>
        <table><blockquote>他ユーザー</blockquote></table></div></html>
        """
        XCTAssertEqual(ThreadListService.parseOpenerHTML(html), "一行目 リンク&〜")
    }

    func testOpenerParserReturnsPlaceholderForEmptyBody() {
        let html = #"<div class="thre"><blockquote></blockquote></div>"#
        XCTAssertEqual(ThreadListService.parseOpenerHTML(html), "本文なし")
    }

    func testOpenerParserRejectsIncompleteHTML() {
        let html = #"<div class="thre"><blockquote>途中"#
        XCTAssertNil(ThreadListService.parseOpenerHTML(html))
    }

    func testOpenerRequestUsesBoundedRange() {
        let url = URL(string: "https://img.2chan.net/b/res/123.htm")!
        let request = ThreadListService.makeOpenerRequest(for: url)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Range"), "bytes=0-32767")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept-Encoding"), "identity")
        XCTAssertEqual(request.timeoutInterval, 15)
    }

    func testThumbnailRequestUsesListRefererAndImageHeaders() {
        let imageURL = URL(string: "https://img.2chan.net/b/cat/123s.jpg")!
        let referer = ThreadListSort.momentum.url
        let request = ThreadListService.makeThumbnailRequest(for: imageURL,
                                                                referer: referer)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"),
                       referer.absoluteString)
        XCTAssertTrue(request.value(forHTTPHeaderField: "Accept")?.contains("image/*") == true)
        XCTAssertTrue(request.value(forHTTPHeaderField: "User-Agent")?.contains("iPhone") == true)
        XCTAssertEqual(request.timeoutInterval, 6)
    }

    func testNativeRequestsUseTheSelectedUserAgent() {
        let userAgent = BrowserUserAgent.all[3].value
        let url = URL(string: "https://img.2chan.net/b/res/123.htm")!
        let list = ThreadListService.makeListRequest(for: ThreadListSort.momentum.url,
                                                      userAgent: userAgent)
        let opener = ThreadListService.makeOpenerRequest(for: url, userAgent: userAgent)
        let thumbnail = ThreadListService.makeThumbnailRequest(
            for: URL(string: "https://img.2chan.net/b/cat/123s.jpg")!,
            referer: ThreadListSort.momentum.url,
            userAgent: userAgent
        )
        XCTAssertEqual(list.value(forHTTPHeaderField: "User-Agent"), userAgent)
        XCTAssertEqual(opener.value(forHTTPHeaderField: "User-Agent"), userAgent)
        XCTAssertEqual(thumbnail.value(forHTTPHeaderField: "User-Agent"), userAgent)
    }

    func testShiftJISDecoder() throws {
        let original = "対象ページ"
        let data = try XCTUnwrap(original.data(using: .shiftJIS))
        XCTAssertEqual(ThreadListService.decodeShiftJIS(data), original)
    }
}

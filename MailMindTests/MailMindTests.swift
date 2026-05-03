import XCTest
@testable import MailMind

final class MailMindServiceProtocolsTests: XCTestCase {
    func testEmailClassificationIsMatched() {
        let matched = EmailClassification(category: "Work", confidence: 0.9, matchReason: "test")
        XCTAssertTrue(matched.isMatched)

        let uncategorized = EmailClassification(
            category: OnDeviceLLMService.uncategorized,
            confidence: 0.9,
            matchReason: "test"
        )
        XCTAssertFalse(uncategorized.isMatched)
    }

}

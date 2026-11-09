import Testing
@testable import ImageCore

struct LocalizationTests {
    @Test func interpolationDoesNotInterpretFileNamesAsPlaceholders() {
        let filename = "image-{1}.png"
        #expect(L("\(filename) / \(2)") == "image-{1}.png / 2")
        let message: LocalizedMessage = "Files: \(3)"
        #expect(message.key == "Files: {0}")
        #expect(message.arguments == ["3"])
    }
}

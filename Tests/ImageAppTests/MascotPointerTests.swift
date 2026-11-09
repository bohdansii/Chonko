import SwiftUI
import Testing
@testable import ImageOptimMac

@MainActor struct MascotPointerTests {
    @Test func gazeFollowsDirectionStaysBoundedAndResetsOutsideWindow() throws {
        let pointer = MascotPointer()
        pointer.frame = CGRect(x: 100, y: 50, width: 56, height: 46)
        #expect(pointer.eyeOffset == nil)
        pointer.location = CGPoint(x: 136.96, y: 76.45)
        let center = try #require(pointer.eyeOffset)
        #expect(abs(center.width) < 0.001 && abs(center.height) < 0.001)
        pointer.location = CGPoint(x: 10000, y: 10000)
        let right = try #require(pointer.eyeOffset)
        #expect(right.width > 0 && right.width <= 2.5)
        #expect(right.height > 0 && right.height <= 2)
        pointer.location = CGPoint(x: -10000, y: -10000)
        let left = try #require(pointer.eyeOffset)
        #expect(left.width < 0 && left.width >= -9)
        #expect(left.height < 0 && left.height >= -2)
        pointer.location = CGPoint(x: -500, y: 76.45)
        #expect(try #require(pointer.eyeOffset).width < -8)
        pointer.location = nil
        #expect(pointer.eyeOffset == nil)
    }
}

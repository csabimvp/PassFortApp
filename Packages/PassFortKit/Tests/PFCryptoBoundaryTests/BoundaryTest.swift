import Testing
import Foundation
@testable import PassFortCrypto

@Suite struct BoundaryTests {
    @Test func echoRoundTripsArbitraryBytes() throws {
        let input = Data((0..<512).map { UInt8($0 & 0xFF) })
        #expect(try echo(input) == input)
    }

    @Test func echoHandlesEmptyInput() throws {
        #expect(try echo(Data()) == Data())
    }
}

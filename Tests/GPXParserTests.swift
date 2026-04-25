import XCTest
@testable import VeloGPXShared

final class GPXParserTests: XCTestCase {
    func testParsesBasicGPX() throws {
        let xml = """
        <gpx version="1.1">
          <trk><name>Test Ride</name><trkseg>
            <trkpt lat="45.5" lon="-73.5"><ele>10</ele></trkpt>
            <trkpt lat="45.6" lon="-73.6"><ele>20</ele></trkpt>
          </trkseg></trk>
        </gpx>
        """.data(using: .utf8)!

        let route = try GPXParser.parse(data: xml, filename: "test.gpx")
        XCTAssertEqual(route.name, "Test Ride")
        XCTAssertEqual(route.trackPoints.count, 2)
        XCTAssertEqual(route.sourceFormat, .gpx)
    }
}

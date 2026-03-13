import XCTest
import CoreVideo
import CoreGraphics
@testable import ShotCoachCore

final class SCCloudSupportTests: XCTestCase {

    // MARK: - scExtractJSONData

    func test_extractJSONData_plainJSON_returnsSameContent() throws {
        let json = #"{"score":80,"shotType":"wide","issues":[],"recommendations":[]}"#
        let data = try scExtractJSONData(from: json)
        let decoded = try JSONDecoder().decode(SCParsedCloudResult.self, from: data)
        XCTAssertEqual(decoded.score, 80)
    }

    func test_extractJSONData_withLowercaseFence_stripsFence() throws {
        let content = "```json\n{\"score\":72,\"shotType\":\"detail\",\"issues\":[],\"recommendations\":[]}\n```"
        let data = try scExtractJSONData(from: content)
        let decoded = try JSONDecoder().decode(SCParsedCloudResult.self, from: data)
        XCTAssertEqual(decoded.score, 72)
    }

    func test_extractJSONData_withUppercaseFence_stripsFence() throws {
        let content = "```JSON\n{\"score\":65,\"shotType\":\"close-up\",\"issues\":[],\"recommendations\":[]}\n```"
        let data = try scExtractJSONData(from: content)
        let decoded = try JSONDecoder().decode(SCParsedCloudResult.self, from: data)
        XCTAssertEqual(decoded.score, 65)
    }

    func test_extractJSONData_withLeadingWhitespace_strips() throws {
        let content = "  \n  {\"score\":50,\"shotType\":\"wide\",\"issues\":[],\"recommendations\":[]}\n  "
        let data = try scExtractJSONData(from: content)
        let decoded = try JSONDecoder().decode(SCParsedCloudResult.self, from: data)
        XCTAssertEqual(decoded.score, 50)
    }

    // MARK: - scBuildCloudResult

    func test_buildCloudResult_clampsScoreAbove100() {
        let parsed = SCParsedCloudResult(score: 150, shotType: "wide", issues: [], recommendations: [])
        let result = scBuildCloudResult(from: parsed, rawJSON: "{}")
        XCTAssertEqual(result.score, 100)
    }

    func test_buildCloudResult_clampsScoreBelow0() {
        let parsed = SCParsedCloudResult(score: -10, shotType: "wide", issues: [], recommendations: [])
        let result = scBuildCloudResult(from: parsed, rawJSON: "{}")
        XCTAssertEqual(result.score, 0)
    }

    func test_buildCloudResult_preservesValidScore() {
        let parsed = SCParsedCloudResult(score: 73, shotType: "detail", issues: [], recommendations: [])
        let result = scBuildCloudResult(from: parsed, rawJSON: "{}")
        XCTAssertEqual(result.score, 73)
        XCTAssertEqual(result.shotType, "detail")
    }

    func test_buildCloudResult_mapsIssues() {
        let issue = SCParsedCloudResult.Issue(title: "Dark", detail: "Underexposed", impact: .high)
        let parsed = SCParsedCloudResult(score: 40, shotType: "wide",
                                         issues: [issue], recommendations: [])
        let result = scBuildCloudResult(from: parsed, rawJSON: "{}")
        XCTAssertEqual(result.issues.count, 1)
        XCTAssertEqual(result.issues[0].title, "Dark")
        XCTAssertEqual(result.issues[0].impact, .high)
    }

    // MARK: - scCompressImage

    func test_compressImage_validBuffer_returnsData() throws {
        let jpegData = makeMinimalJPEG()
        let compressed = try scCompressImage(jpegData, maxPx: 256)
        XCTAssertFalse(compressed.isEmpty)
    }

    func test_compressImage_emptyData_throwsImageProcessingFailed() {
        XCTAssertThrowsError(try scCompressImage(Data(), maxPx: 256)) { error in
            guard let cloudError = error as? SCCloudError,
                  case .imageProcessingFailed = cloudError else {
                XCTFail("Expected imageProcessingFailed, got \(error)")
                return
            }
        }
    }

    // MARK: - Helpers

    /// Creates a minimal valid JPEG from a 1×1 red pixel buffer.
    private func makeMinimalJPEG() -> Data {
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 4, 4, kCVPixelFormatType_32BGRA, nil, &pb)
        guard let buf = pb else { return Data() }
        CVPixelBufferLockBaseAddress(buf, [])
        if let ptr = CVPixelBufferGetBaseAddress(buf)?.assumingMemoryBound(to: UInt8.self) {
            let bpr = CVPixelBufferGetBytesPerRow(buf)
            for y in 0..<4 { for x in 0..<4 {
                let off = y * bpr + x * 4
                ptr[off] = 0; ptr[off+1] = 0; ptr[off+2] = 255; ptr[off+3] = 255
            }}
        }
        CVPixelBufferUnlockBaseAddress(buf, [])

        let output = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            output as CFMutableData, "public.jpeg" as CFString, 1, nil
        ) else { return Data() }
        let ciImage = CIImage(cvPixelBuffer: buf)
        let ctx = CIContext()
        guard let cgImage = ctx.createCGImage(ciImage, from: ciImage.extent) else { return Data() }
        CGImageDestinationAddImage(dest, cgImage, nil)
        CGImageDestinationFinalize(dest)
        return output as Data
    }
}

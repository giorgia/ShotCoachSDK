import XCTest
import CoreVideo
@testable import ShotCoachCore

/// Tests for `SCAnthropicProvider` and `SCOpenAIProvider` that do NOT require
/// network access — only the fast-fail and synchronous validation paths.
final class SCCloudProviderTests: XCTestCase {

    // MARK: - Helpers

    private func makePhoto() -> SCPhoto {
        SCPhoto(imageData: Data())
    }

    // MARK: - SCAnthropicProvider fast-fail

    func test_anthropicProvider_emptyKey_throwsInvalidAPIKey() async {
        let provider = SCAnthropicProvider(apiKey: "")
        do {
            _ = try await provider.analyze(photo: makePhoto(), prompt: "test")
            XCTFail("Expected invalidAPIKey to be thrown")
        } catch let error as SCCloudError {
            guard case .invalidAPIKey = error else {
                XCTFail("Expected .invalidAPIKey, got \(error)"); return
            }
        } catch {
            XCTFail("Expected SCCloudError, got \(error)")
        }
    }

    func test_anthropicProvider_emptyKey_doesNotPerformNetworkIO() async {
        // The fast-fail guard must throw before compressImage is called.
        // We pass completely empty imageData — compressImage would throw
        // imageProcessingFailed if it were reached. Getting invalidAPIKey
        // proves the guard fires first.
        let provider = SCAnthropicProvider(apiKey: "")
        let photo = SCPhoto(imageData: Data())
        do {
            _ = try await provider.analyze(photo: photo, prompt: "test")
            XCTFail("Expected throw")
        } catch let error as SCCloudError {
            guard case .invalidAPIKey = error else {
                XCTFail("Expected .invalidAPIKey, got \(error)"); return
            }
        } catch { XCTFail("Expected SCCloudError") }
    }

    func test_anthropicProvider_customModel_isAccepted() {
        // Verify init accepts a custom model string without precondition failure.
        let provider = SCAnthropicProvider(apiKey: "sk-ant-test", model: "claude-opus-4-6")
        XCTAssertNotNil(provider) // struct init always succeeds — just verifying no crash
    }

    // MARK: - SCOpenAIProvider fast-fail

    func test_openAIProvider_emptyKey_throwsInvalidAPIKey() async {
        let provider = SCOpenAIProvider(apiKey: "")
        let photo    = makePhoto()
        do {
            _ = try await provider.analyze(photo: photo, prompt: "test")
            XCTFail("Expected invalidAPIKey to be thrown")
        } catch let error as SCCloudError {
            guard case .invalidAPIKey = error else {
                XCTFail("Expected .invalidAPIKey, got \(error)"); return
            }
        } catch {
            XCTFail("Expected SCCloudError, got \(error)")
        }
    }

    func test_openAIProvider_emptyKey_doesNotPerformNetworkIO() async {
        let provider = SCOpenAIProvider(apiKey: "")
        let photo = SCPhoto(imageData: Data())
        do {
            _ = try await provider.analyze(photo: photo, prompt: "test")
            XCTFail("Expected throw")
        } catch let error as SCCloudError {
            guard case .invalidAPIKey = error else {
                XCTFail("Expected .invalidAPIKey, got \(error)"); return
            }
        } catch { XCTFail("Expected SCCloudError") }
    }

    // MARK: - SCCloudError LocalizedError

    func test_cloudError_invalidAPIKey_hasReadableDescription() {
        let error = SCCloudError.invalidAPIKey
        XCTAssertNotNil(error.localizedDescription)
        XCTAssertFalse(error.localizedDescription.contains("SCCloudError"),
            "Error description must not expose internal type name")
    }

    func test_cloudError_imageProcessingFailed_hasReadableDescription() {
        let error = SCCloudError.imageProcessingFailed
        XCTAssertNotNil(error.localizedDescription)
        XCTAssertFalse(error.localizedDescription.isEmpty)
    }

    func test_cloudError_rateLimited_hasReadableDescription() {
        let error = SCCloudError.rateLimited
        XCTAssertNotNil(error.localizedDescription)
        XCTAssertFalse(error.localizedDescription.contains("SCCloudError"))
    }
}

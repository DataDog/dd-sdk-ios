import XCTest
@testable import Datadog

class DatadogConfigurationTests: XCTestCase {
    private typealias Configuration = Datadog.Configuration

    func testDefaultConfiguration() {
        let defaultConfiguration = Configuration.builderUsing(clientToken: "abcd").build()
        XCTAssertEqual(
            defaultConfiguration.logsUploadURL.url,
            URL(string: "https://mobile-http-intake.logs.datadoghq.com/v1/input/abcd?ddsource=mobile")!
        )
    }

    func testWhenConfigurationIsInvalid_itThrowsProgrammerError() {
        XCTAssertThrowsError(
            try Configuration.builderUsing(clientToken: "").buildOrThrow()
        ) { error in
            XCTAssertTrue(error is ProgrammerError)
        }
    }

    // MARK: - Logs endpoint

    func testUSLogsEndpoint() {
        XCTAssertEqual(
            Configuration.builderUsing(clientToken: "abcd").set(logsEndpoint: .us).build().logsUploadURL.url,
            URL(string: "https://mobile-http-intake.logs.datadoghq.com/v1/input/abcd?ddsource=mobile")!
        )
    }

    func testEULogsEndpoint() {
        XCTAssertEqual(
            Configuration.builderUsing(clientToken: "abcd").set(logsEndpoint: .eu).build().logsUploadURL.url,
            URL(string: "https://mobile-http-intake.logs.datadoghq.eu/v1/input/abcd?ddsource=mobile")!
        )
    }

    func testCustomLogsEndpoint() {
        XCTAssertEqual(
            Configuration.builderUsing(clientToken: "abcd")
                .set(logsEndpoint: .custom(url: "https://api.example.com/v1/logs/"))
                .build().logsUploadURL.url,
            URL(string: "https://api.example.com/v1/logs/abcd?ddsource=mobile")!
        )
    }
}

import XCTest
@testable import Datadog

class DatadogTests: XCTestCase {
    override func setUp() {
        super.setUp()
        XCTAssertNil(Datadog.instance)
    }

    override func tearDown() {
        XCTAssertNil(Datadog.instance)
        super.tearDown()
    }

    func testItCanBeInitialized() throws {
        Datadog.initialize(
            appContext: .mockAny(),
            configuration: Datadog.Configuration.builderUsing(clientToken: "abcdefghi").build()
        )
        XCTAssertNotNil(Datadog.instance)
        try Datadog.deinitializeOrThrow()
    }

    func testWhenInitializedMoreThanOnce_itThrowsProgrammerError() throws {
        let initialize = {
            try Datadog.initializeOrThrow(
                appContext: .mockAny(),
                configuration: Datadog.Configuration.builderUsing(clientToken: "abcdefghi").build()
            )
        }
        try initialize()
        XCTAssertThrowsError(try initialize()) { error in
            XCTAssertEqual(
                (error as? ProgrammerError)?.description,
                "Datadog SDK usage error: SDK is already initialized."
            )
        }
        try Datadog.deinitializeOrThrow()
    }
}

import XCTest
@testable import Datadog

class DatadogTests: XCTestCase {
    private var printFunction: PrintFunctionMock! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        XCTAssertNil(Datadog.instance)
        printFunction = PrintFunctionMock()
        consolePrint = printFunction.print
    }

    override func tearDown() {
        consolePrint = { print($0) }
        printFunction = nil
        XCTAssertNil(Datadog.instance)
        super.tearDown()
    }

    // MARK: - Initializing with configuration

    func testGivenValidConfiguration_itCanBeInitialized() throws {
        Datadog.initialize(
            appContext: .mockAny(),
            configuration: Datadog.Configuration.builderUsing(clientToken: "abcdefghi").build()
        )
        XCTAssertNotNil(Datadog.instance)
        try Datadog.deinitializeOrThrow()
    }

    func testGivenInvalidLogsUploadURL_whenInitializing_itPrintsError() throws {
        Datadog.verbosityLevel = .debug
        defer { Datadog.verbosityLevel = nil }

        Datadog.initialize(appContext: .mockAny(), configuration: .mockWith(logsUploadURL: nil))

        XCTAssertEqual(
            printFunction.printedMessage,
            "🔥 Datadog SDK usage error: SDK configuration is invalid - check `logsEndpoint` and (or) `clientToken`."
        )
        XCTAssertNil(Datadog.instance)
    }

    func testGivenVerbosityLevelSetToLowest_whenInitializingDatadogMoreThanOnce_itPrintsError() throws {
        Datadog.verbosityLevel = .debug
        defer { Datadog.verbosityLevel = nil }

        Datadog.initialize(appContext: .mockAny(), configuration: .mockAny())
        Datadog.initialize(appContext: .mockAny(), configuration: .mockAny())

        XCTAssertEqual(
            printFunction.printedMessage,
            "🔥 Datadog SDK usage error: SDK is already initialized."
        )

        try Datadog.deinitializeOrThrow()
    }

    // MARK: - Defaults

    func testDefaultAppContext() throws {
        Datadog.initialize(appContext: .init(), configuration: .mockAny())

        let appContext = Datadog.instance?.appContext
        let bundle = Bundle.main

        XCTAssertNotNil(appContext)
        XCTAssertEqual(appContext?.bundleIdentifier, bundle.bundleIdentifier)
        XCTAssertEqual(appContext?.bundleVersion, bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
        XCTAssertEqual(appContext?.bundleShortVersion, bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        XCTAssertEqual(appContext?.executableName, bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String)

        if MobileDevice.current != nil {
            XCTAssertNotNil(appContext?.mobileDevice)
        } else {
            XCTAssertNil(appContext?.mobileDevice)
        }

        try Datadog.deinitializeOrThrow()
    }

    func testDefaultVerbosityLevel() {
        XCTAssertNil(Datadog.verbosityLevel)
    }
}

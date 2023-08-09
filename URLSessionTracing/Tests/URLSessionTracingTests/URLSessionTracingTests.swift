import XCTest
@testable import URLSessionTracing
import Foundation

struct MockInterceptor: Interceptor {
    let onResume: (URLSessionTask) -> Void
    let onURLSession: (URLSession, URLSessionTask, URLSessionTaskMetrics) -> Void

    init(onResume: @escaping (URLSessionTask) -> Void, onURLSession: @escaping (URLSession, URLSessionTask, URLSessionTaskMetrics) -> Void) throws {
        self.onResume = onResume
        self.onURLSession = onURLSession
    }

    func resume(_ task: URLSessionTask) {
        self.onResume(task)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        self.onURLSession(session, task, metrics)
    }
}

final class URLSessionTracingTests: XCTestCase {
    func testGet_SharedURLSession() throws {
        let start = XCTestExpectation(description: "onResume")
        let stop = XCTestExpectation(description: "onURLSession")

        let interceptor = try MockInterceptor { _ in
            start.fulfill()
        } onURLSession: { _, _, _ in
            stop.fulfill()
        }

        let _ = try NetworkInstrumentation(interceptor: interceptor)
        let url = URL(string: "https://www.datadoghq.com/")!
        let session = URLSession.shared
        let task = session.dataTask(with: url) { data, response, error in
            print(response)
        }
        task.resume()
        wait(for: [start, stop], timeout: 10)
    }

    func testGet_init1() throws {
        let start = XCTestExpectation(description: "onResume")
        let stop = XCTestExpectation(description: "onURLSession")

        let interceptor = try MockInterceptor { _ in
            start.fulfill()
        } onURLSession: { _, _, _ in
            stop.fulfill()
        }

        let _ = try NetworkInstrumentation(interceptor: interceptor)
        let url = URL(string: "https://www.datadoghq.com/")!
        let session = URLSession(configuration: .default)
        let task = session.dataTask(with: url) { data, response, error in
            print(response)
        }
        task.resume()
        wait(for: [start, stop], timeout: 10)
    }

    func testGet_init2() throws {
        let start = XCTestExpectation(description: "onResume")
        let stop = XCTestExpectation(description: "onURLSession")

        let interceptor = try MockInterceptor { _ in
            start.fulfill()
        } onURLSession: { _, _, _ in
            stop.fulfill()
        }

        let _ = try NetworkInstrumentation(interceptor: interceptor)
        let url = URL(string: "https://www.datadoghq.com/")!
        let session = URLSession(configuration: .default, delegate: MyURLSessionTaskDelegate(), delegateQueue: OperationQueue.main)
        let task = session.dataTask(with: url) { data, response, error in
            print(response)
        }
        task.resume()
        wait(for: [start, stop], timeout: 10)
    }

    @available(macOS 12.0, iOS 15.0, *)
    func testAsyncAwaitGet_URL() async throws {
        let start = XCTestExpectation(description: "onResume")
        let stop = XCTestExpectation(description: "onURLSession")

        let interceptor = try MockInterceptor { _ in
            start.fulfill()
        } onURLSession: { _, _, _ in
            stop.fulfill()
        }

        let _ = try NetworkInstrumentation(interceptor: interceptor)
        let url = URL(string: "https://www.datadoghq.com/")!
        let session = URLSession(configuration: .default, delegate: MyURLSessionTaskDelegate(), delegateQueue: OperationQueue.main)
        let (data, response) = try await session.data(from: url)
        print(response)
        await fulfillment(of: [start, stop], timeout: 10)
    }

    @available(macOS 12.0, iOS 15.0, *)
    func testAsyncAwaitGet_URL_Delegate() async throws {
        let start = XCTestExpectation(description: "onResume")
        let stop = XCTestExpectation(description: "onURLSession")

        let interceptor = try MockInterceptor { _ in
            start.fulfill()
        } onURLSession: { _, _, _ in
            stop.fulfill()
        }

        let _ = try NetworkInstrumentation(interceptor: interceptor)
        let url = URL(string: "https://www.datadoghq.com/")!
        let session = URLSession(configuration: .default, delegate: MyURLSessionTaskDelegate(), delegateQueue: OperationQueue.main)
        let (data, response) = try await session.data(from: url, delegate: MyURLSessionTaskDelegate())
        print(response)
        await fulfillment(of: [start, stop], timeout: 10)
        XCTAssertNotNil(session.delegate as? MyURLSessionTaskDelegate)
    }

    @available(macOS 12.0, iOS 15.0, *)
    func testAsyncAwaitGet_Request() async throws {
        let start = XCTestExpectation(description: "onResume")
        let stop = XCTestExpectation(description: "onURLSession")

        let interceptor = try MockInterceptor { _ in
            start.fulfill()
        } onURLSession: { _, _, _ in
            stop.fulfill()
        }

        let _ = try NetworkInstrumentation(interceptor: interceptor)
        let request = URLRequest(url: URL(string: "https://www.datadoghq.com/")!)
        let session = URLSession(configuration: .default, delegate: MyURLSessionTaskDelegate(), delegateQueue: OperationQueue.main)
        let (data, response) = try await session.data(for: request)
        print(response)
        await fulfillment(of: [start, stop], timeout: 10)
        XCTAssertNotNil(session.delegate as? MyURLSessionTaskDelegate)
    }

    @available(macOS 12.0, iOS 15.0, *)
    func testAsyncAwaitGet_Request_Delegate() async throws {
        let start = XCTestExpectation(description: "onResume")
        let stop = XCTestExpectation(description: "onURLSession")

        let interceptor = try MockInterceptor { _ in
            start.fulfill()
        } onURLSession: { _, _, _ in
            stop.fulfill()
        }

        let _ = try NetworkInstrumentation(interceptor: interceptor)
        let request = URLRequest(url: URL(string: "https://www.datadoghq.com/")!)
        let session = URLSession(configuration: .default, delegate: MyURLSessionTaskDelegate(), delegateQueue: OperationQueue.main)
        let (data, response) = try await session.data(for: request, delegate: MyURLSessionTaskDelegate())
        print(response)
        await fulfillment(of: [start, stop], timeout: 10)
        XCTAssertNotNil(session.delegate as? MyURLSessionTaskDelegate)
    }
}

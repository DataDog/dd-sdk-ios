/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog
import _Datadog_Private

private typealias RequestInterceptor = HookedSession.RequestInterceptor
private typealias TaskObserver = HookedSession.TaskObserver

private func buildSession(
    with configuration: URLSessionConfiguration = URLSessionConfiguration.default,
    interceptor: RequestInterceptor? = nil,
    observer: TaskObserver? = nil,
    sessionDelegate: URLSessionDelegate? = nil,
    delegateQueue: OperationQueue? = nil
) -> URLSession {
    let session = URLSession(configuration: configuration,
                             delegate: sessionDelegate,
                             delegateQueue: delegateQueue)
    let requestInterceptor = interceptor ?? { $0 }
    let taskObserver = observer ?? { _, _ in }
    return HookedSession(
        session: session,
        requestInterceptor: requestInterceptor,
        taskObserver: taskObserver
    ).asURLSession()
}

class HookedSessionTests: XCTestCase {
    func testIntegrity() {
        final class TestSessionDelegate: NSObject, URLSessionDelegate { }

        let config = URLSessionConfiguration.background(withIdentifier: "unitTestIdentifier")
        let delegate = TestSessionDelegate()
        let session = buildSession(with: config, sessionDelegate: delegate)

        XCTAssertEqual(session.configuration.identifier, config.identifier)
        XCTAssertTrue(session.superclass is URLSession.Type)
        XCTAssertNotNil(session.delegate)
        XCTAssertEqual(session.delegate!.debugDescription, delegate.debugDescription)
    }

    func testSimpleTask() {
        let session = buildSession()
        let task = session.dataTask(with: URL(string: "https://foo.bar/1")!)
        XCTAssertNotNil(task)
    }

    func testSimpleTaskCompletion() {
        let session = buildSession()
        let expect = expectation(description: "task completion")
        let task = session.dataTask(with: URL(string: "https://news.ycombinator.com")!) { _, _, _ in
            expect.fulfill()
        }
        task.resume()
        wait(for: [expect], timeout: 3.0)
    }

    func testRequestInterception() {
        let interceptionHeaders: [String: String] = ["interception": "success"]
        let interceptor: RequestInterceptor = {
            var newRequest = $0
            newRequest.allHTTPHeaderFields = interceptionHeaders
            return newRequest
        }
        let session = buildSession(with: .default, interceptor: interceptor)
        let task = session.dataTask(with: URL(string: "https://foo.bar")!)

        XCTAssertEqual(task.originalRequest?.allHTTPHeaderFields, interceptionHeaders)
    }

    func testTaskObservation() {
        let runningExpc = expectation(description: "running expectation")
        let completedExpc = expectation(description: "completed expectation")
        let taskObserver: TaskObserver = { observed, previousState in
            if case .running = observed.state, case .suspended = previousState {
                runningExpc.fulfill()
            }
            if case .completed = observed.state, case .running = previousState {
                completedExpc.fulfill()
            }
        }
        let interceptor: RequestInterceptor = { $0 }
        let session = buildSession(with: .default, interceptor: interceptor, observer: taskObserver)
        let task = session.dataTask(with: URL(string: "https://foo.bar")!)
        task.resume()

        wait(for: [runningExpc, completedExpc], timeout: 1.0, enforceOrder: true)
    }

    func testUnrecognizedSelector() {
        let exceptionHandler = ObjcExceptionHandler()
        let session = buildSession()
        var caughtException: NSError? = nil
        do {
            try exceptionHandler.rethrowToSwift {
                session.perform(NSSelectorFromString("foo"))
            }
        } catch {
            caughtException = error as NSError
        }
        XCTAssertNotNil(caughtException)
        let exceptionReason = caughtException?.userInfo["reason"] as? String
        XCTAssertNotNil(exceptionReason)
        XCTAssertFalse(exceptionReason!.contains("HookedSession"))
    }
}

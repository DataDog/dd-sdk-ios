/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

public extension URLSession {
    internal typealias RequestInterceptor = HookedSession.RequestInterceptor
    internal typealias TaskObserver = HookedSession.TaskObserver

    static func tracedSession(
        configuration: URLSessionConfiguration = .default,
        delegate: URLSessionDelegate? = nil,
        delegateQueue: OperationQueue? = nil
    ) -> URLSession {
        let session = URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: delegateQueue
        )

        let requestInterceptor: RequestInterceptor = {
            // TODO: RUMM-300 Inject tracing headers
            return $0
        }

        let taskObserver: TaskObserver = { _, _ in
            // TODO: RUMM-300 Start/stop span based on state
        }

        let hookedSession = HookedSession(
            session: session,
            requestInterceptor: requestInterceptor,
            taskObserver: taskObserver
        )
        return hookedSession.asURLSession()
    }
}

/*
 HookedSession is a NSObject subclass.
 It keeps an URLSession instance inside.
 It relays all the method calls to URLSession,
 except those that are implemented by HookedSession.

 It intercepts and observes requests and tasks respectively.
 */
internal final class HookedSession: NSObject {
    typealias RequestInterceptor = (URLRequest) -> URLRequest
    typealias TaskObserver = (URLSessionTask, URLSessionTask.State?) -> Void

    private let session: URLSession
    let requestInterceptor: RequestInterceptor
    let taskObserver: TaskObserver
    private var observations = [Int: NSKeyValueObservation](minimumCapacity: 100)

    init(session: URLSession,
         requestInterceptor: @escaping RequestInterceptor,
         taskObserver: @escaping TaskObserver) {
        self.session = session
        self.requestInterceptor = requestInterceptor
        self.taskObserver = taskObserver
        super.init()
    }

    func asURLSession() -> URLSession {
        let castedSession: URLSession = unsafeBitCast(self, to: URLSession.self)
        return castedSession
    }

    // MARK: - Transparent messaging
    /*
     As a NSObject subclass yet exposed as URLSession (ref: URLSession.tracedSession)
     all the method calls are `unrecognized_selector` for HookedSession, except
     those which are implemented in HookedSession.
     forwardingTarget passes those unimplemented method calls to session
     */
    override func forwardingTarget(for aSelector: Selector!) -> Any? { // swiftlint:disable:this implicitly_unwrapped_optional
        return session
    }

    // MARK: - Helpers

    /*
     IMPORTANT NOTE:
     If you create an URLSessionTask instance from an URLSession instance,
     the task stays alive EVEN IF you nullify the session instance.
     This happens because URLSessionTask has private `__taskGroup` property which keeps
     session instance alive as long as the task is alive.

     This is not the case for HookedSession instances.

     let task = hookedSession.dataTask(...)
     hookedSession = nil
     task.resume()

     In the case above, task and
     hookedSession.session (private property) will stay alive
     yet hookedSession will be deallocated.
     That means observations will be deallocated too.
     In order to keep observing until the task completes,
     observationBlock below captures `self` on purpose.
     Therefore, observationBlock keeps `self` alive
     until the block is removed from self.observations dict.
     */
    private func observed<T: URLSessionTask>(_ task: T) -> T {
        let observer = taskObserver
        var previousState: URLSessionTask.State? = nil
        let observation = task.observe(\.state, options: [.initial]) { observed, _ in
            observer(observed, previousState)
            previousState = observed.state

            switch observed.state {
            case .canceling, .completed:
                self.observations[observed.taskIdentifier] = nil
            default:
                break
            }
        }
        observations[task.taskIdentifier] = observation

        return task
    }

    // MARK: - URLSessionDataTask

    /*
     IMPORTANT NOTE:
     @objc enables dynamic method dispatch and
     make sure @objc names match NSURLSession Obj-C interface.
     Otherwise, these methods are not called.
     */
    @objc(dataTaskWithURL:)
    func dataTask(with url: URL) -> URLSessionDataTask {
        return dataTask(with: URLRequest(url: url))
    }

    @objc(dataTaskWithURL:completionHandler:)
    func dataTask(with url: URL, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask {
        return dataTask(with: URLRequest(url: url), completionHandler: completionHandler)
    }

    @objc(dataTaskWithRequest:)
    func dataTask(with request: URLRequest) -> URLSessionDataTask {
        return observed(session.dataTask(with: requestInterceptor(request)))
    }

    @objc(dataTaskWithRequest:completionHandler:)
    func dataTask(with request: URLRequest, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask {
        let task = session.dataTask(with: requestInterceptor(request),
                                    completionHandler: completionHandler)
        return observed(task)
    }

    // MARK: - URLSessionUploadTask

    @objc(uploadTaskWithRequest:fromFile:)
    func uploadTask(with request: URLRequest, fromFile fileURL: URL) -> URLSessionUploadTask {
        return observed(session.uploadTask(with: requestInterceptor(request), fromFile: fileURL))
    }

    @objc(uploadTaskWithRequest:fromBodyData:)
    func uploadTask(with request: URLRequest, from bodyData: Data) -> URLSessionUploadTask {
        return observed(session.uploadTask(with: requestInterceptor(request), from: bodyData))
    }

    @objc(uploadTaskWithStreamedRequest:)
    func uploadTask(withStreamedRequest request: URLRequest) -> URLSessionUploadTask {
        return observed(session.uploadTask(withStreamedRequest: requestInterceptor(request)))
    }

    @objc(uploadTaskwithRequest:fromFile:completionHandler:)
    func uploadTask(with request: URLRequest, fromFile fileURL: URL, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionUploadTask {
        let task = session.uploadTask(
            with: requestInterceptor(request),
            fromFile: fileURL,
            completionHandler: completionHandler
        )
        return observed(task)
    }

    @objc(uploadTaskwithRequest:fromData:completionHandler:)
    func uploadTask(with request: URLRequest, from bodyData: Data?, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionUploadTask {
        let task = session.uploadTask(
            with: requestInterceptor(request),
            from: bodyData,
            completionHandler: completionHandler
        )
        return observed(task)
    }

    // MARK: - URLSessionDownloadTask

    @objc(downloadTaskWithURL:)
    func downloadTask(with url: URL) -> URLSessionDownloadTask {
        return downloadTask(with: URLRequest(url: url))
    }

    @objc(downloadTaskWithURL:completionHandler:)
    func downloadTask(with url: URL, completionHandler: @escaping (URL?, URLResponse?, Error?) -> Void) -> URLSessionDownloadTask {
        return downloadTask(with: URLRequest(url: url), completionHandler: completionHandler)
    }

    @objc(downloadTaskWithRequest:)
    func downloadTask(with request: URLRequest) -> URLSessionDownloadTask {
        return observed(session.downloadTask(with: requestInterceptor(request)))
    }

    @objc(downloadTaskWithRequest:completionHandler:)
    func downloadTask(with request: URLRequest, completionHandler: @escaping (URL?, URLResponse?, Error?) -> Void) -> URLSessionDownloadTask {
        let task = session.downloadTask(
            with: requestInterceptor(request),
            completionHandler: completionHandler
        )
        return observed(task)
    }

    @objc(downloadTaskWithResumeData:)
    func downloadTask(withResumeData resumeData: Data) -> URLSessionDownloadTask {
        return observed(session.downloadTask(withResumeData: resumeData))
    }

    @objc(downloadTaskWithResumeData:completionHandler:)
    func downloadTask(withResumeData resumeData: Data, completionHandler: @escaping (URL?, URLResponse?, Error?) -> Void) -> URLSessionDownloadTask {
        let task = session.downloadTask(
            withResumeData: resumeData,
            completionHandler: completionHandler
        )
        return observed(task)
    }
}

// MARK: - Unsupported task types

// TODO: RUMM-300 are Stream/WebSocket supported by APM?

//extension HookedSession {
//    // MARK: - URLSessionStreamTask
//    @objc(streamTaskWithHostName:port:)
//    func streamTask(withHostName hostname: String, port: Int) -> URLSessionStreamTask { }
//    @objc(streamTaskWithService:)
//    func streamTask(with service: NetService) -> URLSessionStreamTask { }
//}
//
//@available(iOS 13, *)
//extension HookedSession {
//    // MARK: - URLSessionWebSocketTask
//    @objc(webSocketTaskWithURL:)
//    func webSocketTask(with url: URL) -> URLSessionWebSocketTask { }
//    @objc(webSocketTaskWithURL:protocols:)
//    func webSocketTask(with url: URL, protocols: [String]) -> URLSessionWebSocketTask { }
//    @objc(webSocketTaskWithRequest:)
//    func webSocketTask(with request: URLRequest) -> URLSessionWebSocketTask { }
//}

extension HookedSession: CustomReflectable {
    /*
     HookedSession imitates URLSession from outside in case that anyone does type-check
     such as isKindOf:/isMemberOf: or checks superclass at runtime
     */
    var customMirror: Mirror {
        return Mirror(reflecting: session)
    }
    override func isKind(of aClass: AnyClass) -> Bool {
        return session.isKind(of: aClass)
    }
    override class func isKind(of aClass: AnyClass) -> Bool {
        return URLSession.isKind(of: aClass)
    }
    override func isMember(of aClass: AnyClass) -> Bool {
        return session.isMember(of: aClass)
    }
    override class func isMember(of aClass: AnyClass) -> Bool {
        return URLSession.isMember(of: aClass)
    }
    override var superclass: AnyClass? { return session.superclass }
    override class func superclass() -> AnyClass? { return URLSession.superclass() }
}

import Foundation

class MyURLSessionTaskDelegate: NSObject, URLSessionTaskDelegate {
    
}

class MyURLSessionDelegate: NSObject, URLSessionDelegate {
    
}

@objc
class _URLSessionTaskDelegate: NSObject, URLSessionTaskDelegate {
    weak var delegate: URLSessionDelegate?

    init(delegate: URLSessionDelegate?) {
        self.delegate = delegate
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        guard let delegate = delegate as? URLSessionTaskDelegate else {
            return
        }
        delegate.urlSession?(session, task: task, didFinishCollecting: metrics)
    }
}

class URLSessionDelegateSwizzler {

    static var didFinishCollecting: DidFinishCollecting?

    static var lock = NSLock()
    static var bindingsCount: UInt = 0

    static func bind(intercept: @escaping (URLSession, URLSessionTask, URLSessionTaskMetrics) -> Void) throws {
        lock.lock()
        defer { lock.unlock() }

        guard bindingsCount == 0 else {
            bindingsCount += 1
            return
        }
        
        didFinishCollecting = try DidFinishCollecting.build()
        didFinishCollecting?.swizzle { session, task, metrics in
            intercept(session, task, metrics)
        }

        bindingsCount += 1
    }

    static func unbind() {
        lock.lock()
        defer { lock.unlock() }

        guard bindingsCount > 0 else {
            return
        }

        didFinishCollecting?.unswizzle()
        bindingsCount -= 1

        guard bindingsCount == 0 else {
            return
        }
    }

    class DidFinishCollecting: MethodSwizzler<
        @convention(c) (_URLSessionTaskDelegate, Selector, URLSession, URLSessionTask, URLSessionTaskMetrics) -> Void,
        @convention(block) (_URLSessionTaskDelegate, URLSession, URLSessionTask, URLSessionTaskMetrics) -> Void> {
        private static let selector = #selector(_URLSessionTaskDelegate.urlSession(_:task:didFinishCollecting:))

        private let method: FoundMethod

        static func build() throws -> DidFinishCollecting {
            return try DidFinishCollecting(selector: self.selector, klass: _URLSessionTaskDelegate.self)
        }

        private init(selector: Selector, klass: AnyClass) throws {
            self.method = try Self.findMethod(with: selector, in: klass)
            super.init()
        }

        func swizzle(intercept: @escaping (URLSession, URLSessionTask, URLSessionTaskMetrics) -> Void) {
            typealias Signature = @convention(block) (_URLSessionTaskDelegate, URLSession, URLSessionTask, URLSessionTaskMetrics) -> Void
            swizzle(method) { previousImplementation -> Signature in
                return { delegate, session, task, metrics in
                    intercept(session, task, metrics)
                    return previousImplementation(delegate, Self.selector, session, task, metrics)
                }
            }
        }
    }
}

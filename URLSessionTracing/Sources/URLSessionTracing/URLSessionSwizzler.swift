import Foundation

class URLSessionSwizzler {

    static var initWithConfigurationDelegateDelegateQueueDelegateDispatchQueue: InitWithConfigurationDelegateDelegateQueueDelegateDispatchQueue?
    static var delegate: Delegate?

    static var lock = NSLock()
    static var bindingsCount: UInt = 0

    static func bind() throws {
        lock.lock()
        defer { lock.unlock() }

        guard bindingsCount == 0 else {
            bindingsCount += 1
            return
        }

        initWithConfigurationDelegateDelegateQueueDelegateDispatchQueue = try InitWithConfigurationDelegateDelegateQueueDelegateDispatchQueue.build()
        initWithConfigurationDelegateDelegateQueueDelegateDispatchQueue?.swizzle()

        delegate = try Delegate.build()
        delegate?.swizzle()

        bindingsCount += 1
    }

    static func unbind() {
        lock.lock()
        defer { lock.unlock() }

        guard bindingsCount > 0 else {
            return
        }

        initWithConfigurationDelegateDelegateQueueDelegateDispatchQueue?.unswizzle()
        initWithConfigurationDelegateDelegateQueueDelegateDispatchQueue = nil

        delegate?.unswizzle()
        delegate = nil

        bindingsCount -= 1

        guard bindingsCount == 0 else {
            return
        }

    }

    class InitWithConfigurationDelegateDelegateQueueDelegateDispatchQueue: MethodSwizzler<@convention(c) (URLSession, Selector, URLSessionConfiguration, URLSessionDelegate?, DispatchQueue?, DispatchQueue?) -> URLSession?, @convention(block) (URLSession, URLSessionConfiguration, URLSessionDelegate?, DispatchQueue?, DispatchQueue?) -> URLSession?> {
        private static let selector = Selector("initWithConfiguration:delegate:delegateQueue:delegateDispatchQueue:")

        private let method: FoundMethod

        static func build() throws -> InitWithConfigurationDelegateDelegateQueueDelegateDispatchQueue {
            return try InitWithConfigurationDelegateDelegateQueueDelegateDispatchQueue(selector: self.selector, klass: URLSession.self)
        }

        private init(selector: Selector, klass: AnyClass) throws {
            self.method = try Self.findMethod(with: selector, in: klass)
            super.init()
        }

        func swizzle() {
            typealias Signature = @convention(block) (URLSession, URLSessionConfiguration, URLSessionDelegate?, DispatchQueue?, DispatchQueue?) -> URLSession?
            swizzle(method) { previousImplementation -> Signature in
                return { session, configuration, delegate, delegateQueue, delegateDispatchQueue in
                    session.originalDelegate = delegate
                    if let delegate = delegate as? _URLSessionTaskDelegate {
                        return previousImplementation(session, Self.selector, configuration, delegate, delegateQueue, delegateDispatchQueue)
                    } else {
                        let _delegate = _URLSessionTaskDelegate(delegate: delegate)
                        return previousImplementation(session, Self.selector, configuration, _delegate, delegateQueue, delegateDispatchQueue)
                    }
                }
            }
        }
    }

    class Delegate: MethodSwizzler<@convention(c) (URLSession, Selector) -> URLSessionDelegate?, @convention(block) (URLSession) -> URLSessionDelegate?> {
        private static let selector = #selector(getter: URLSession.delegate)

        private let method: FoundMethod

        static func build() throws -> Delegate {
            return try Delegate(selector: self.selector, klass: URLSession.self)
        }

        private init(selector: Selector, klass: AnyClass) throws {
            self.method = try Self.findMethod(with: selector, in: klass)
            super.init()
        }

        func swizzle() {
            typealias Signature = @convention(block) (URLSession) -> URLSessionDelegate?
            swizzle(method) { _ -> Signature in
                return { session in
                    return session.originalDelegate
                }
            }
        }
    }
}

fileprivate var originalDelegateKey: UInt8 = 1
extension URLSession {
    var originalDelegate: URLSessionDelegate? {
        set {
            objc_setAssociatedObject(self, &originalDelegateKey, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        get {
            return objc_getAssociatedObject(self, &originalDelegateKey) as? URLSessionDelegate
        }
    }
}

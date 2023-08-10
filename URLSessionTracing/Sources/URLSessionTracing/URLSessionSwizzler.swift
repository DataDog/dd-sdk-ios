import Foundation

class URLSessionSwizzler {
    
    static var initWithConfigurationDelegateDelegateQueueDelegateDispatchQueue: InitWithConfigurationDelegateDelegateQueueDelegateDispatchQueue?
    static var delegate: Delegate?
    static var dataTaskWithURLAndCompletion: DataTaskWithURLAndCompletion?
    
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
        
        dataTaskWithURLAndCompletion = try DataTaskWithURLAndCompletion.build()
        dataTaskWithURLAndCompletion?.swizzle()
        
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
        
        dataTaskWithURLAndCompletion?.unswizzle()
        dataTaskWithURLAndCompletion = nil
        
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
    
    typealias CompletionHandler = (Data?, URLResponse?, Error?) -> Void
    
    /// Swizzles the `URLSession.dataTask(with:completionHandler:)` for `URLRequest`.
    class DataTaskWithURLRequestAndCompletion: MethodSwizzler<@convention(c) (URLSession, Selector, URLRequest, CompletionHandler?) -> URLSessionDataTask, @convention(block) (URLSession, URLRequest, CompletionHandler?) -> URLSessionDataTask> {
        private static let selector = #selector(
            URLSession.dataTask(with:completionHandler:) as (URLSession) -> (URLRequest, @escaping CompletionHandler) -> URLSessionDataTask
        )
        
        private let method: FoundMethod
        
        static func build() throws -> DataTaskWithURLRequestAndCompletion {
            return try DataTaskWithURLRequestAndCompletion(
                selector: self.selector,
                klass: URLSession.self
            )
        }
        
        private init(selector: Selector, klass: AnyClass) throws {
            self.method = try Self.findMethod(with: selector, in: klass)
            super.init()
        }
        
        func swizzle() {
            typealias Signature = @convention(block) (URLSession, URLRequest, CompletionHandler?) -> URLSessionDataTask
            swizzle(method) { previousImplementation -> Signature in
                fatalError()
            }
        }
    }
    
    /// Swizzles the `URLSession.dataTask(with:completionHandler:)` for `URL`.
    class DataTaskWithURLAndCompletion: MethodSwizzler<@convention(c) (URLSession, Selector, URL, CompletionHandler?) -> URLSessionDataTask, @convention(block) (URLSession, URL, CompletionHandler?) -> URLSessionDataTask> {
        private static let selector = #selector(
            URLSession.dataTask(with:completionHandler:) as (URLSession) -> (URL, @escaping CompletionHandler) -> URLSessionDataTask
        )
        
        private let method: FoundMethod
        
        static func build() throws -> DataTaskWithURLAndCompletion {
            return try DataTaskWithURLAndCompletion(
                selector: self.selector,
                klass: URLSession.self
            )
        }
        
        private init(selector: Selector, klass: AnyClass) throws {
            self.method = try Self.findMethod(with: selector, in: klass)
            super.init()
        }
        
        func swizzle() {
            swizzle(method) { previousImplementation -> @convention(block) (URLSession, URL, CompletionHandler?) -> URLSessionDataTask in
                return { session, url, completionHandler in
                    let task = previousImplementation(session, Self.selector, url, completionHandler)
                    task.firstPartyHosts = session.delegate?.firstPartyHosts
                    return task
                }
            }
        }
    }
    
    /// Swizzles the `URLSession.dataTask(with:)` for `URLRequest`.
    class DataTaskWithURLRequest: MethodSwizzler<@convention(c) (URLSession, Selector, URLRequest) -> URLSessionDataTask, @convention(block) (URLSession, URLRequest) -> URLSessionDataTask> {
        private static let selector = #selector(
            URLSession.dataTask(with:) as (URLSession) -> (URLRequest) -> URLSessionDataTask
        )
        
        private let method: FoundMethod
        
        static func build() throws -> DataTaskWithURLRequest {
            return try DataTaskWithURLRequest(
                selector: self.selector,
                klass: URLSession.self
            )
        }
        
        private init(selector: Selector, klass: AnyClass) throws {
            self.method = try Self.findMethod(with: selector, in: klass)
            super.init()
        }
        
        func swizzle() {
            typealias Signature = @convention(block) (URLSession, URLRequest) -> URLSessionDataTask
            swizzle(method) { previousImplementation -> Signature in
                return { session, request -> URLSessionDataTask in
                    fatalError()
                }
            }
        }
    }
    
    /// Swizzles the `URLSession.dataTask(with:)` for `URL`.
    class DataTaskWithURL: MethodSwizzler<@convention(c) (URLSession, Selector, URL) -> URLSessionDataTask, @convention(block) (URLSession, URL) -> URLSessionDataTask> {
        private static let selector = #selector(
            URLSession.dataTask(with:) as (URLSession) -> (URL) -> URLSessionDataTask
        )
        
        private let method: FoundMethod
        
        static func build() throws -> DataTaskWithURL {
            return try DataTaskWithURL(
                selector: self.selector,
                klass: URLSession.self
            )
        }
        
        private init(selector: Selector, klass: AnyClass) throws {
            self.method = try Self.findMethod(with: selector, in: klass)
            super.init()
        }
        
        func swizzle() {
            swizzle(method) { previousImplementation -> @convention(block) (URLSession, URL) -> URLSessionDataTask in
                return { session, url -> URLSessionDataTask in
                    let task = previousImplementation(session, Self.selector, url)
                    task.firstPartyHosts = session.delegate?.firstPartyHosts
                    return task
                }
            }
        }
    }
}

typealias CompletionHandler = (Data?, URLResponse?, Error?) -> Void

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

fileprivate var firstPartyHostsKey: UInt8 = 1

extension URLSessionDelegate {
    public var firstPartyHosts: Set<String>? {
        set {
            objc_setAssociatedObject(self, &firstPartyHostsKey, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        get {
            return objc_getAssociatedObject(self, &firstPartyHostsKey) as? Set<String>
        }
    }
}

extension URLSessionTask {
    var firstPartyHosts: Set<String>? {
        set {
            objc_setAssociatedObject(self, &firstPartyHostsKey, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        get {
            return objc_getAssociatedObject(self, &firstPartyHostsKey) as? Set<String>
        }
    }
}

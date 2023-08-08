import Foundation

class URLSessionTaskSwizzler {
    static var resume: Resume?

    static var lock = NSLock()
    static var bindingsCount: UInt = 0

    static func bind(intercept: @escaping (URLSessionTask) -> Void) throws {
        lock.lock()
        defer { lock.unlock() }

        guard bindingsCount == 0 else {
            bindingsCount += 1
            return
        }

        self.resume = try Resume.build()

        resume?.swizzle(intercept: intercept)

        bindingsCount += 1
    }

    static func unbind() {
        lock.lock()
        defer { lock.unlock() }

        guard bindingsCount > 0 else {
            return
        }

        resume?.unswizzle()
        bindingsCount -= 1

        guard bindingsCount == 0 else {
            return
        }
        resume = nil
    }

    class Resume: MethodSwizzler<@convention(c) (URLSessionTask, Selector) -> Void, @convention(block) (URLSessionTask) -> Void> {
        private static let selector = #selector(URLSessionTask.resume)

        private let method: FoundMethod

        static func build() throws -> Resume {
            return try Resume(selector: self.selector, klass: URLSessionTask.self)
        }

        private init(selector: Selector, klass: AnyClass) throws {
            self.method = try Self.findMethod(with: selector, in: klass)
            super.init()
        }

        func swizzle(intercept: @escaping (URLSessionTask) -> Void) {
            typealias Signature = @convention(block) (URLSessionTask) -> Void
            swizzle(method) { previousImplementation -> Signature in
                return { task in
                    intercept(task)
                    previousImplementation(task, Self.selector)
                }
            }
        }
    }
}

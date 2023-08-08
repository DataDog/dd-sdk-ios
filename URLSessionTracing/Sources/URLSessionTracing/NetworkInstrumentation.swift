import Foundation

class NetworkInstrumentation {
    let interceptor: Interceptor

    init(interceptor: Interceptor) throws {
        self.interceptor = interceptor

        try URLSessionTaskSwizzler.bind { task in
            print("Intercepted: resume")
            interceptor.resume(task)
        }

        try URLSessionSwizzler.bind()

        try URLSessionDelegateSwizzler.bind { session, task, metrics in
            print("Intercepted: didFinishCollecting")
            interceptor.urlSession(session, task: task, didFinishCollecting: metrics)
        }
    }
    
    deinit {
//        URLSessionTaskSwizzler.unbind()
//        URLSessionSwizzler.unbind()
//        URLSessionDelegateSwizzler.unbind()
    }

}

protocol Interceptor {
    func resume(_ task: URLSessionTask)
    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics)
}

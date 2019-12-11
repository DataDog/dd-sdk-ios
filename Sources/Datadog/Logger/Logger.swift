import Foundation

public class Logger {
    
    private let httpClient: HTTPClient

    internal init() {
        self.httpClient = HTTPClient()
    }

    internal func log(_ message: String) {
        var request = URLRequest(url: URL(string: "https://www.google.com/")!)
        request.timeoutInterval = 10
        request.httpMethod = "GET"

        httpClient.send(request: request)
    }
}


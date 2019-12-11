import Foundation

final class HTTPClient {
    
    private let session: URLSession
    
    init() {
        self.session = URLSession(configuration: .default)
    }
    
    func send(request: URLRequest) {
        let task = session.dataTask(with: request) { (data, response, error) in
            print("🔥 error: \(error.debugDescription)")
            print("⭐️ response: \(response?.description ?? "")")
            print("⭐️ data of size: \(data?.count ?? 0)")
        }
        task.resume()
    }
}

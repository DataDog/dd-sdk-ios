import UIKit
import Datadog

class ViewController: UIViewController {

    var logger: Logger!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        do {
            let configuration = try Datadog(
                logsEndpoint: "", // specify URL // TODO: improve in RUMM-124
                clientToken: "" // specify client token
            )
            self.logger = Logger(configuration: configuration)
            logger.info("Test message from ios-app-example")
        } catch {
            print("Error when configuring `Datadog` SDK: \(error)")
            print("💡 Make sure `logsEndpoint` and `clientToken` are specified")
        }
    }
}

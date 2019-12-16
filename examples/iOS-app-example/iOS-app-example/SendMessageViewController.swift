import UIKit
import Datadog

class SendMessageViewController: UIViewController {

    @IBOutlet weak var logLevelSegmentedControl: UISegmentedControl!
    @IBOutlet weak var logMessageTextField: UITextField!
    @IBOutlet weak var logServiceNameTextField: UITextField!
    @IBOutlet weak var sendOnceButton: UIButton!
    @IBOutlet weak var send10xButton: UIButton!

    var logger: Logger!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        hideKeyboardWhenTapOutside()
        
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

    @IBAction func didTapSend(_ sender: Any) {
        print(sender)
    }

    @IBAction func didChangeLogLevel(_ sender: Any) {
        print(sender)
    }
}

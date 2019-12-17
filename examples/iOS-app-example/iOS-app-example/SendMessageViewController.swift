import UIKit

class SendMessageViewController: UIViewController {

    @IBOutlet weak var logLevelSegmentedControl: UISegmentedControl!
    @IBOutlet weak var logMessageTextField: UITextField!
    @IBOutlet weak var logServiceNameTextField: UITextField!
    @IBOutlet weak var sendOnceButton: UIButton!
    @IBOutlet weak var send10xButton: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        hideKeyboardWhenTapOutside()
    }

    @IBAction func didTapSendSingleLog(_ sender: Any) {
        let message: String = logMessageTextField.text ?? ""
        logger?.info(message)
    }
    
    @IBAction func didTapSend10Logs(_ sender: Any) {
        let message: String = logMessageTextField.text ?? ""
        (0..<10).forEach { _ in logger?.info(message) }
    }
    
    @IBAction func didChangeLogLevel(_ sender: Any) {
        // TODO: RUMM-107 Add support to log levels
    }
}

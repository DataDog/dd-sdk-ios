import UIKit
import Datadog

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        
        let _ = Datadog()
    }
}

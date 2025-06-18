import SwiftUI
import SRFixtures

struct SwiftUIFixture: FixtureProtocol {
    private let _instantiateViewController: () -> UIViewController

    init<Content: View>(@ViewBuilder content: @escaping () -> Content) {
        _instantiateViewController = {
            UIHostingController(rootView: content())
        }
    }

    func instantiateViewController() -> UIViewController {
        _instantiateViewController()
    }
}

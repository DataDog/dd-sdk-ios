"""Generate the single remaining human-paced H16 fixture; preserve its qualified source."""
import hashlib
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'acceptance'))
from acceptance_common import require

BASE_SHA256 = 'af0fb468a3b652001f321c416258b44aba4cfb17c1efe345e116e500da7f5e7a'


def render(original, expected_sha256):
    require(hashlib.sha256(original).hexdigest() == expected_sha256, 'hosting base fixture changed')
    text = original.decode()
    def replace(before, after):
        nonlocal text
        require(text.count(before) == 1, 'hosting source anchor changed: ' + before[:60])
        text = text.replace(before, after)
    replace('    private var fixtureControllers: Set<String> = []', '''    private var fixtureControllers: Set<String> = []
    private let pacedInput = PacedHostingInput()
    private let humanDeadline = DispatchTime.now().uptimeNanoseconds + 1_200_000_000_000

    private func humanStep(_ phase: String, title: String, controller: UIViewController,
                           attachments: [String: UIViewController], appear: [String], disappear: [String]) async throws {
        let issued = DispatchTime.now().uptimeNanoseconds
        let deadline = min(humanDeadline, issued + 180_000_000_000)
        while evidence.matching("swiftui-appear").compactMap({ $0["name"] as? String }) != appear
                || evidence.matching("swiftui-disappear").compactMap({ $0["name"] as? String }) != disappear {
            guard DispatchTime.now().uptimeNanoseconds < min(deadline, issued + 20_000_000_000)
            else { throw HostingFailure.boundary("human-lifecycle-readiness-" + phase) }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        guard let window else { throw HostingFailure.boundary("human-window") }
        try await pacedInput.request(phase, title: title, controller: controller, attachments: attachments,
                                     window: window, issued: issued, deadline: deadline)
    }''')
    replace('        phase = "push"', '''        try await humanStep("push", title: "Push Detail", controller: root,
            attachments: ["root": root], appear: ["RootView"], disappear: [])
        phase = "push"''')
    replace('        phase = "pop"', '''        try await humanStep("pop", title: "Return to Root", controller: detail,
            attachments: ["root": root, "detail": detail], appear: ["RootView", "DetailView"], disappear: ["RootView"])
        phase = "pop"''')
    replace('        phase = "present"', '''        try await humanStep("present", title: "Present Modal", controller: root,
            attachments: ["root": root, "detail": detail], appear: ["RootView", "DetailView", "RootView"],
            disappear: ["RootView", "DetailView"])
        phase = "present"''')
    replace('        phase = "dismiss"', '''        try await humanStep("dismiss", title: "Dismiss Modal", controller: modal,
            attachments: ["root": root, "detail": detail, "modal": modal],
            appear: ["RootView", "DetailView", "RootView", "ModalView"],
            disappear: ["RootView", "DetailView", "RootView"])
        phase = "dismiss"''')
    replace('        evidence.record("native-teardown")', '''        try await wait("modal-disappeared") {
            evidence.matching("swiftui-disappear").compactMap { $0["name"] as? String }
                == ["RootView", "DetailView", "RootView", "ModalView"]
        }
        evidence.record("native-teardown")''')
    return text.encode()

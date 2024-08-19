/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A view controller that demonstrates how to use `UIStepper`.
*/

import UIKit

class StepperViewController: BaseTableViewController {
    
    // Cell identifier for each stepper table view cell.
    enum StepperKind: String, CaseIterable {
        case defaultStepper
        case tintedStepper
        case customStepper
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        testCells.append(contentsOf: [
            CaseElement(title: NSLocalizedString("DefaultStepperTitle", bundle: .module, comment: ""),
                        cellID: StepperKind.defaultStepper.rawValue,
                        configHandler: configureDefaultStepper),
            CaseElement(title: NSLocalizedString("TintedStepperTitle", bundle: .module, comment: ""),
                        cellID: StepperKind.tintedStepper.rawValue,
                        configHandler: configureTintedStepper),
            CaseElement(title: NSLocalizedString("CustomStepperTitle", bundle: .module, comment: ""),
                        cellID: StepperKind.customStepper.rawValue,
                        configHandler: configureCustomStepper)
        ])
    }

    // MARK: - Configuration
    
    func configureDefaultStepper(stepper: UIStepper) {
        // Setup the stepper range 0 to 10, initial value 0, increment/decrement factor of 1.
        stepper.value = 0
        stepper.minimumValue = 0
        stepper.maximumValue = 10
        stepper.stepValue = 1

        stepper.addTarget(self,
                          action: #selector(StepperViewController.stepperValueDidChange(_:)),
                          for: .valueChanged)
    }

    func configureTintedStepper(stepper: UIStepper) {
        // Setup the stepper range 0 to 20, initial value 20, increment/decrement factor of 1.
        stepper.value = 20
        stepper.minimumValue = 0
        stepper.maximumValue = 20
        stepper.stepValue = 1
        
        stepper.tintColor = UIColor(named: "tinted_stepper_control")!
        stepper.setDecrementImage(stepper.decrementImage(for: .normal), for: .normal)
        stepper.setIncrementImage(stepper.incrementImage(for: .normal), for: .normal)

        stepper.addTarget(self,
                          action: #selector(StepperViewController.stepperValueDidChange(_:)),
                          for: .valueChanged)
    }

    func configureCustomStepper(stepper: UIStepper) {
        // Set the background image.
        let stepperBackgroundImage = UIImage(named: "background", in: .module, compatibleWith: nil)
        stepper.setBackgroundImage(stepperBackgroundImage, for: .normal)

        let stepperHighlightedBackgroundImage = UIImage(named: "background_highlighted", in: .module, compatibleWith: nil)
        stepper.setBackgroundImage(stepperHighlightedBackgroundImage, for: .highlighted)

        let stepperDisabledBackgroundImage = UIImage(named: "background_disabled", in: .module, compatibleWith: nil)
        stepper.setBackgroundImage(stepperDisabledBackgroundImage, for: .disabled)

        // Set the image which will be painted in between the two stepper segments. It depends on the states of both segments.
        let stepperSegmentDividerImage = UIImage(named: "stepper_and_segment_divider", in: .module, compatibleWith: nil)
        stepper.setDividerImage(stepperSegmentDividerImage, forLeftSegmentState: .normal, rightSegmentState: .normal)

        // Set the image for the + button.
        let stepperIncrementImage = UIImage(systemName: "plus")
        stepper.setIncrementImage(stepperIncrementImage, for: .normal)

        // Set the image for the - button.
        let stepperDecrementImage = UIImage(systemName: "minus")
        stepper.setDecrementImage(stepperDecrementImage, for: .normal)

        stepper.addTarget(self, action: #selector(StepperViewController.stepperValueDidChange(_:)), for: .valueChanged)
    }

    // MARK: - Actions

    @objc
    func stepperValueDidChange(_ stepper: UIStepper) {
        Swift.debugPrint("A stepper changed its value: \(stepper.value).")
    }
}

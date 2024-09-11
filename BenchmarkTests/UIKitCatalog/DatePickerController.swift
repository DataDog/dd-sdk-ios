/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A view controller that demonstrates how to use `UIDatePicker`.
*/

import UIKit

class DatePickerController: UIViewController {
    // MARK: - Properties

    @IBOutlet weak var datePicker: UIDatePicker!
    
    @IBOutlet weak var dateLabel: UILabel!
    
    // A date formatter to format the `date` property of `datePicker`.
    lazy var dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        
        return dateFormatter
    }()

    // MARK: - View Life Cycle

    override func viewDidLoad() {
        super.viewDidLoad()

        if #available(iOS 15, *) {
            // In case the label's content is too large to fit inside the label (causing truncation),
            // use this to reveal the label's full text drawn as a tool tip.
            dateLabel.showsExpansionTextWhenTruncated = true
        }
        
        configureDatePicker()
    }

    // MARK: - Configuration

    func configureDatePicker() {
        datePicker.datePickerMode = .dateAndTime

        /** Set min/max date for the date picker. As an example we will limit the date between
			now and 7 days from now.
        */
        let now = Date()
        datePicker.minimumDate = now

        // Decide the best date picker style based on the trait collection's vertical size.
        datePicker.preferredDatePickerStyle = traitCollection.verticalSizeClass == .compact ? .compact : .inline
        
        var dateComponents = DateComponents()
        dateComponents.day = 7

		let sevenDaysFromNow = Calendar.current.date(byAdding: .day, value: 7, to: now)
        datePicker.maximumDate = sevenDaysFromNow

        datePicker.minuteInterval = 2

        datePicker.addTarget(self, action: #selector(DatePickerController.updateDatePickerLabel), for: .valueChanged)

        updateDatePickerLabel()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        // Adjust the date picker style due to the trait collection's vertical size.
        super.traitCollectionDidChange(previousTraitCollection)
        datePicker.preferredDatePickerStyle = traitCollection.verticalSizeClass == .compact ? .compact : .inline
    }
    
    // MARK: - Actions

    @objc
    func updateDatePickerLabel() {
        dateLabel.text = dateFormatter.string(from: datePicker.date)
        
        Swift.debugPrint("Chosen date: \(dateFormatter.string(from: datePicker.date))")
    }
}

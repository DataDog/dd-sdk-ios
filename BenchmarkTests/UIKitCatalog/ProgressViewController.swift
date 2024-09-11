/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A view controller that demonstrates how to use `UIProgressView`.
*/

import UIKit

class ProgressViewController: BaseTableViewController {
    // Cell identifier for each progress view table view cell.
    enum ProgressViewKind: String, CaseIterable {
        case defaultProgress
        case barProgress
        case tintedProgress
    }
    
    // MARK: - Properties
    
    var observer: NSKeyValueObservation?
    
    // An `NSProgress` object whose `fractionCompleted` is observed using KVO to update the `UIProgressView`s' `progress` properties.
    let progress = Progress(totalUnitCount: 10)
    
    // A repeating timer that, when fired, updates the `NSProgress` object's `completedUnitCount` property.
    var updateTimer: Timer?
    
    var progressViews = [UIProgressView]() // Accumulated progress views from all table cells for progress updating.
    
    // MARK: - Initialization
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
		
        // Register as an observer of the `NSProgress`'s `fractionCompleted` property.
        observer = progress.observe(\.fractionCompleted, options: [.new]) { (_, _) in
            // Update the progress views.
            for progressView in self.progressViews {
				progressView.setProgress(Float(self.progress.fractionCompleted), animated: true)
            }
        }
    }
    
    deinit {
        // Unregister as an observer of the `NSProgress`'s `fractionCompleted` property.
		observer?.invalidate()
    }

    // MARK: - View Life Cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()

        testCells.append(contentsOf: [
            CaseElement(title: NSLocalizedString("ProgressDefaultTitle", bundle: .module, comment: ""),
                        cellID: ProgressViewKind.defaultProgress.rawValue,
                        configHandler: configureDefaultStyleProgressView),
            CaseElement(title: NSLocalizedString("ProgressBarTitle", bundle: .module, comment: ""),
                        cellID: ProgressViewKind.barProgress.rawValue,
                        configHandler: configureBarStyleProgressView)
        ])
        
        if traitCollection.userInterfaceIdiom != .mac {
            // Tinted progress views available only on iOS.
            testCells.append(contentsOf: [
                CaseElement(title: NSLocalizedString("ProgressTintedTitle", bundle: .module, comment: ""),
                            cellID: ProgressViewKind.tintedProgress.rawValue,
                            configHandler: configureTintedProgressView)
            ])
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        /** Reset the `completedUnitCount` of the `NSProgress` object and create
            a repeating timer to increment it over time.
        */
        progress.completedUnitCount = 0

		updateTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true, block: { (_) in
			/** Update the `completedUnitCount` of the `NSProgress` object if it's
				not completed. Otherwise, stop the timer.
			*/
			if self.progress.completedUnitCount < self.progress.totalUnitCount {
				self.progress.completedUnitCount += 1
			} else {
				self.updateTimer?.invalidate()
			}
		})
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        // Stop the timer from firing.
        updateTimer?.invalidate()
    }
	
    // MARK: - Configuration

    func configureDefaultStyleProgressView(_ progressView: UIProgressView) {
        progressView.progressViewStyle = .default
        
        // Reset the completed progress of the `UIProgressView`s.
        progressView.setProgress(0.0, animated: false)
        
        progressViews.append(progressView)
    }

    func configureBarStyleProgressView(_ progressView: UIProgressView) {
        progressView.progressViewStyle = .bar
        
        // Reset the completed progress of the `UIProgressView`s.
        progressView.setProgress(0.0, animated: false)
        
        progressViews.append(progressView)
    }

    func configureTintedProgressView(_ progressView: UIProgressView) {
        progressView.progressViewStyle = .default

        progressView.trackTintColor = UIColor.systemBlue
        progressView.progressTintColor = UIColor.systemPurple
        
        // Reset the completed progress of the `UIProgressView`s.
        progressView.setProgress(0.0, animated: false)
        
        progressViews.append(progressView)
    }

}

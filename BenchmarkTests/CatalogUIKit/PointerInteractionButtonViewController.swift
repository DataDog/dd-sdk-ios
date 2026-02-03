/*
See LICENSE folder for this sample's licensing information.

Abstract:
A view controller that demonstrates how to integrate pointer interactions to `UIButton`.
*/

import UIKit

class PointerInteractionButtonViewController: BaseTableViewController {
    
    // Cell identifier for each button pointer table view cell.
    enum PointerButtonKind: String, CaseIterable {
        case buttonPointer
        case buttonHighlight
        case buttonLift
        case buttonHover
        case buttonCustom
    }
    
    // The pointer effect kind to use for each button (corresponds to the button's view tag).
    enum ButtonPointerEffectKind: Int {
        case pointer = 1
        case highlight
        case lift
        case hover
        case custom
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        testCells.append(contentsOf: [
            CaseElement(title: "UIPointerEffect.automatic",
                                  cellID: PointerButtonKind.buttonPointer.rawValue,
                                  configHandler: configurePointerButton),
            CaseElement(title: "UIPointerEffect.highlight",
                                  cellID: PointerButtonKind.buttonHighlight.rawValue,
                                  configHandler: configureHighlightButton),
            CaseElement(title: "UIPointerEffect.lift",
                                  cellID: PointerButtonKind.buttonLift.rawValue,
                                  configHandler: configureLiftButton),
            CaseElement(title: "UIPointerEffect.hover",
                                  cellID: PointerButtonKind.buttonHover.rawValue,
                                  configHandler: configureHoverButton),
            CaseElement(title: "UIPointerEffect (custom)",
                                  cellID: PointerButtonKind.buttonCustom.rawValue,
                                  configHandler: configureCustomButton)
        ])
    }

    // MARK: - Configurations
    
    func configurePointerButton(button: UIButton) {
        button.pointerStyleProvider = defaultButtonProvider
    }
    
    func configureHighlightButton(button: UIButton) {
        button.pointerStyleProvider = highlightButtonProvider
    }
    
    func configureLiftButton(button: UIButton) {
        button.pointerStyleProvider = liftButtonProvider
    }
    
    func configureHoverButton(button: UIButton) {
        button.pointerStyleProvider = hoverButtonProvider
    }
    
    func configureCustomButton(button: UIButton) {
        button.pointerStyleProvider = customButtonProvider
    }
    
    // MARK: Button Pointer Providers
    
    func defaultButtonProvider(button: UIButton, pointerEffect: UIPointerEffect, pointerShape: UIPointerShape) -> UIPointerStyle? {
        var buttonPointerStyle: UIPointerStyle? = nil
        
        // Use the pointer effect's preview that's passed in.
        let targetedPreview = pointerEffect.preview
        
        /** UIPointerEffect.automatic attempts to determine the appropriate effect for the given preview automatically.
            The pointer effect has an automatic nature which adapts to the aspects of the button (background color, corner radius, size)
            */
        let buttonPointerEffect = UIPointerEffect.automatic(targetedPreview)
        buttonPointerStyle = UIPointerStyle(effect: buttonPointerEffect, shape: pointerShape)
        return buttonPointerStyle
    }
    
    func highlightButtonProvider(button: UIButton, pointerEffect: UIPointerEffect, pointerShape: UIPointerShape) -> UIPointerStyle? {
        var buttonPointerStyle: UIPointerStyle? = nil
        
        // Use the pointer effect's preview that's passed in.
        let targetedPreview = pointerEffect.preview
        
        // Pointer slides under the given view and morphs into the view's shape.
        let buttonHighlightPointerEffect = UIPointerEffect.highlight(targetedPreview)
        buttonPointerStyle = UIPointerStyle(effect: buttonHighlightPointerEffect, shape: pointerShape)
        
        return buttonPointerStyle
    }
    
    func liftButtonProvider(button: UIButton, pointerEffect: UIPointerEffect, pointerShape: UIPointerShape) -> UIPointerStyle? {
        var buttonPointerStyle: UIPointerStyle? = nil
        
        // Use the pointer effect's preview that's passed in.
        let targetedPreview = pointerEffect.preview
        
        /** Pointer slides under the given view and disappears as the view scales up and gains a shadow.
            Make the pointer shape’s bounds match the view’s frame so the highlight extends to the edges.
        */
        let buttonLiftPointerEffect = UIPointerEffect.lift(targetedPreview)
        let customPointerShape = UIPointerShape.path(UIBezierPath(roundedRect: button.bounds, cornerRadius: 6.0))
        buttonPointerStyle = UIPointerStyle(effect: buttonLiftPointerEffect, shape: customPointerShape)
        
        return buttonPointerStyle
    }
    
    func hoverButtonProvider(button: UIButton, pointerEffect: UIPointerEffect, pointerShape: UIPointerShape) -> UIPointerStyle? {
        var buttonPointerStyle: UIPointerStyle? = nil
        
        // Use the pointer effect's preview that's passed in.
        let targetedPreview = pointerEffect.preview
        
        /** Pointer retains the system shape while over the given view.
            Visual changes applied to the view are dictated by the effect's properties.
        */
        let buttonHoverPointerEffect =
            UIPointerEffect.hover(targetedPreview, preferredTintMode: .none, prefersShadow: true)
        buttonPointerStyle = UIPointerStyle(effect: buttonHoverPointerEffect, shape: nil)
        
        return buttonPointerStyle
    }
    
    func customButtonProvider(button: UIButton, pointerEffect: UIPointerEffect, pointerShape: UIPointerShape) -> UIPointerStyle? {
        var buttonPointerStyle: UIPointerStyle? = nil
        
        /** Hover pointer with a custom triangle pointer shape.
            Override the default UITargetedPreview with our own, make the visible path outset a little larger.
        */
        let parameters = UIPreviewParameters()
        parameters.visiblePath = UIBezierPath(rect: button.bounds.insetBy(dx: -15.0, dy: -15.0))
        let newTargetedPreview = UITargetedPreview(view: button, parameters: parameters)

        let buttonPointerEffect =
            UIPointerEffect.hover(newTargetedPreview, preferredTintMode: .overlay, prefersShadow: false, prefersScaledContent: false)
        
        let customPointerShape = UIPointerShape.path(trianglePointerShape())
        buttonPointerStyle = UIPointerStyle(effect: buttonPointerEffect, shape: customPointerShape)
        
        return buttonPointerStyle
    }
    
    // Return a triangle bezier path for the pointer's shape.
    func trianglePointerShape() -> UIBezierPath {
        let width = 20.0
        let height = 20.0
        let offset = 10.0 // Coordinate location to match up with the coordinate of default pointer shape.
        
        let pathView = UIBezierPath()
        pathView.move(to: CGPoint(x: (width / 2) - offset, y: -offset))
        pathView.addLine(to: CGPoint(x: -offset, y: height - offset))
        pathView.addLine(to: CGPoint(x: width - offset, y: height - offset))
        pathView.close()
        
        return pathView
    }
}

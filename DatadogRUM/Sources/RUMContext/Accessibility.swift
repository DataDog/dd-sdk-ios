import Foundation

struct Accessibility: Codable {
    var textSize: String?
    var screenReaderEnabled: Bool?
    var boldTextEnabled: Bool?
    var reduceTransparencyEnabled: Bool?
    var reduceMotionEnabled: Bool?
    var buttonShapesEnabled: Bool?
    var invertColorsEnabled: Bool?
    var increaseContrastEnabled: Bool?
    var assistiveSwitchEnabled: Bool?
    var assistiveTouchEnabled: Bool?
    var videoAutoplayEnabled: Bool?
    var closedCaptioningEnabled: Bool?
    var monoAudioEnabled: Bool?
    var shakeToUndoEnabled: Bool?
    var reducedAnimationsEnabled: Bool?
    var shouldDifferentiateWithoutColor: Bool?
    var grayscaleEnabled: Bool?
    var singleAppModeEnabled: Bool?
    var onOffSwitchLabelsEnabled: Bool?
    var speakScreenEnabled: Bool?
    var speakSelectionEnabled: Bool?
    var rtlEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case textSize = "text_size"
        case screenReaderEnabled = "screen_reader_enabled"
        case boldTextEnabled = "bold_text_enabled"
        case reduceTransparencyEnabled = "reduce_transparency_enabled"
        case reduceMotionEnabled = "reduce_motion_enabled"
        case buttonShapesEnabled = "button_shapes_enabled"
        case invertColorsEnabled = "invert_colors_enabled"
        case increaseContrastEnabled = "increase_contrast_enabled"
        case assistiveSwitchEnabled = "assistive_switch_enabled"
        case assistiveTouchEnabled = "assistive_touch_enabled"
        case videoAutoplayEnabled = "video_autoplay_enabled"
        case closedCaptioningEnabled = "closed_captioning_enabled"
        case monoAudioEnabled = "mono_audio_enabled"
        case shakeToUndoEnabled = "shake_to_undo_enabled"
        case reducedAnimationsEnabled = "reduced_animations_enabled"
        case shouldDifferentiateWithoutColor = "differentiate_without_color"
        case grayscaleEnabled = "grayscale_enabled"
        case singleAppModeEnabled = "single_app_mode_enabled"
        case onOffSwitchLabelsEnabled = "on_off_switch_labels_enabled"
        case speakScreenEnabled = "speak_screen_enabled"
        case speakSelectionEnabled = "speak_selection_enabled"
        case rtlEnabled = "rtl_enabled"
    }
}

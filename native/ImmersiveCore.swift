import Foundation

func desktopMotionEnabled(mode: String, reduceMotion: Bool?) -> Bool {
    mode == "always" || (mode == "system" && reduceMotion == false)
}

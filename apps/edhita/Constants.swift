import Foundation

struct Constants {
    // Google's demo banner unit is independent of the upstream publisher's account.
    static let adUnitID = "ca-app-pub-3940256099942544/2934735716"
    #if DEBUG
        static let enableAd = false
        static let debugGDPR = false
    #endif
}

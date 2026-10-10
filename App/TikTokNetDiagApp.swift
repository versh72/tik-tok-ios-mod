import SwiftUI
import NetDiagUI

/// Entry point for the iOS app target.
///
/// This file lives outside the `NetDiagUI` library target on purpose: a Swift
/// package library cannot declare `@main`. Add it to the app target alongside
/// the local package dependency.
@main
struct TikTokNetDiagApp: App {

    var body: some Scene {
        WindowGroup {
            NetDiagRootScene()
        }
    }
}
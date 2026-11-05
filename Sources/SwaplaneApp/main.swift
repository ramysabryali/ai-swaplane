import AppKit
import SwaplaneUI

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu bar app; Dock icon only while the main window is open
app.run()

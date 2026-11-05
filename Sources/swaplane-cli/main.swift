import Foundation
import SwaplaneCore

// v0.1 CLI stub: read-only. Never touches the Keychain; only reads non-secret metadata.
// Switching from the CLI arrives in v0.4 via IPC to the app.
let version = "0.1.0"
let paths = Paths()

func loadProfiles() -> [Profile] {
    guard let data = try? Data(contentsOf: paths.profilesFile),
        let p = try? SwaplaneJSON.decoder.decode([Profile].self, from: data)
    else { return [] }
    return p
}
func loadState() -> VaultState {
    (try? Data(contentsOf: paths.stateFile)).flatMap { try? SwaplaneJSON.decoder.decode(VaultState.self, from: $0) } ?? VaultState()
}

let args = Array(CommandLine.arguments.dropFirst())
let json = args.contains("--json")
switch args.first(where: { !$0.hasPrefix("--") }) ?? "help" {
case "list":
    let state = loadState()
    let profiles = loadProfiles()
    if json {
        let rows = profiles.map { p -> [String: Any] in
            ["id": p.id.uuidString, "tool": p.tool.rawValue, "label": p.label, "active": state.active[p.tool.rawValue] == p.id]
        }
        let data = (try? JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])) ?? Data("[]".utf8)
        print(String(decoding: data, as: UTF8.self))
    } else if profiles.isEmpty {
        print("No profiles yet. Open Swaplane from the menu bar to import one.")
    } else {
        for p in profiles.sorted(by: { ($0.tool.rawValue, $0.label) < ($1.tool.rawValue, $1.label) }) {
            print("\(state.active[p.tool.rawValue] == p.id ? "*" : " ") \(p.tool.rawValue)\t\(p.label)")
        }
    }
case "current":
    let state = loadState()
    let profiles = loadProfiles()
    for tool in Tool.allCases {
        let label = state.active[tool.rawValue].flatMap { id in profiles.first { $0.id == id }?.label } ?? "-"
        print("\(tool.rawValue)\t\(label)")
    }
case "version", "--version":
    print("swaplane \(version)")
default:
    print("""
    swaplane \(version)
    usage: swaplane <command> [--json]
      list      show profiles (* = active)
      current   show the active profile per tool
      version   print version
    Switching from the CLI arrives in v0.4. Use the menu bar app for now.
    """)
}

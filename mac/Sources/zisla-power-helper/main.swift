import Foundation
import Security
import ZislaPowerHelperSupport

guard geteuid() == 0,
      let label = Bundle.main.bundleIdentifier,
      let clients = Bundle.main.object(forInfoDictionaryKey: "SMAuthorizedClients") as? [String],
      clients.count == 1
else { exit(EXIT_FAILURE) }

var requirement: SecRequirement?
guard SecRequirementCreateWithString(clients[0] as CFString, [], &requirement) == errSecSuccess else {
    exit(EXIT_FAILURE)
}
let listener = NSXPCListener(machServiceName: label)
let delegate = PowerHelperListener(requirement: clients[0])
listener.delegate = delegate
listener.resume()
withExtendedLifetime(delegate) { RunLoop.current.run() }

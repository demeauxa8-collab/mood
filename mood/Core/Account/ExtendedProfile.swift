import Foundation

struct ExtendedProfile: Equatable {
    var bio = ""
    var pronouns = ""
}

struct AccountServerVersions: Decodable {
    let versions: [String]
    let unstableFeatures: [String: Bool]?
    enum CodingKeys: String, CodingKey { case versions; case unstableFeatures = "unstable_features" }
    var supportsExtendedProfiles: Bool {
        unstableFeatures?["uk.tcpip.msc4133"] == true || versions.contains { version in
            let parts = version.dropFirst().split(separator: ".").compactMap { Int($0) }
            return version.hasPrefix("v") && parts.count == 2 && (parts[0] > 1 || (parts[0] == 1 && parts[1] >= 16))
        }
    }
}

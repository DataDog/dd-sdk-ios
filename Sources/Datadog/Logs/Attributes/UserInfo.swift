import Foundation

/// Provides information about the user.
internal struct UserInfo {
    let id: String? // swiftlint:disable:this identifier_name
    let name: String?
    let email: String?
}

internal class UserInfoProvider {
    var value = UserInfo(id: nil, name: nil, email: nil)
}

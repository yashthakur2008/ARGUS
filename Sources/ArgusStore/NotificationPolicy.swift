import Foundation
import ArgusCore

public struct NotificationPolicy: Codable, Equatable, Sendable {
  public let quietHours: QuietHours?
  public let bypassQuietHours: Bool
  public let revision: Int64

  public init(quietHours: QuietHours? = nil, bypassQuietHours: Bool = false, revision: Int64 = 1) throws {
    guard revision > 0 else { throw CoreError.invalidRevision }
    self.quietHours = quietHours
    self.bypassQuietHours = bypassQuietHours
    self.revision = revision
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(quietHours: values.decodeIfPresent(QuietHours.self, forKey: .quietHours),
      bypassQuietHours: values.decode(Bool.self, forKey: .bypassQuietHours),
      revision: values.decode(Int64.self, forKey: .revision))
  }
}

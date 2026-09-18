import Foundation

public struct PromptVariable: Codable, Equatable, Sendable {
  public let name: String
  public let required: Bool

  public init(name: String, required: Bool) throws {
    let bytes = name.utf8
    func letter(_ byte: UInt8) -> Bool { (65...90).contains(byte) || (97...122).contains(byte) || byte == 95 }
    guard let first = bytes.first, bytes.count <= 64, name != "context", letter(first),
      bytes.dropFirst().allSatisfy({ letter($0) || (48...57).contains($0) })
    else { throw PromptError.invalidSchema }
    self.name = name
    self.required = required
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      name: values.decode(String.self, forKey: .name),
      required: values.decode(Bool.self, forKey: .required)
    )
  }
}

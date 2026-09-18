import Foundation

/// Detached trusted-memory editor fields. Not an Encodable persistence aggregate.
/// Mutations do not update a stored draft. Task 5 must persist with expected-revision CAS.
/// Task 2 must add the full canonical encoded-input bound at validated boundaries.
public struct PromptDraft: Decodable, Equatable, Sendable {
  public let promptID: UUID
  public let revision: Int64
  public let baseVersion: Int64?
  public let modifiedAt: Date
  public var metadata: PromptMetadata
  public var body: String
  public var schema: [PromptVariable]
  public var context: [PromptContextItem]
  public var workflow: PromptWorkflow?

  public init(promptID: UUID, revision: Int64, baseVersion: Int64?, modifiedAt: Date,
    metadata: PromptMetadata, body: String, schema: [PromptVariable],
    context: [PromptContextItem], workflow: PromptWorkflow?) throws {
    self.init(unvalidatedPromptID: promptID, revision: revision, baseVersion: baseVersion,
      modifiedAt: modifiedAt, metadata: metadata, body: body, schema: schema, context: context, workflow: workflow)
    try validate()
  }

  init(unvalidatedPromptID: UUID, revision: Int64, baseVersion: Int64?, modifiedAt: Date,
    metadata: PromptMetadata, body: String, schema: [PromptVariable],
    context: [PromptContextItem], workflow: PromptWorkflow?) {
    self.promptID = unvalidatedPromptID
    self.revision = revision
    self.baseVersion = baseVersion
    self.modifiedAt = modifiedAt
    self.metadata = metadata
    self.body = body
    self.schema = schema
    self.context = context
    self.workflow = workflow
  }

  public func validate() throws {
    guard revision > 0, baseVersion.map({ $0 > 0 }) ?? true else { throw CoreError.invalidRevision }
    try validateDate(modifiedAt)
    try validatePromptContent(body: body, schema: schema, context: context, workflow: workflow)
  }

  private enum CodingKeys: String, CodingKey {
    case promptID, revision, baseVersion, modifiedAt, metadata, body, schema, context, workflow
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      promptID: values.decode(UUID.self, forKey: .promptID),
      revision: values.decode(Int64.self, forKey: .revision),
      baseVersion: values.decodeIfPresent(Int64.self, forKey: .baseVersion),
      modifiedAt: values.decode(Date.self, forKey: .modifiedAt),
      metadata: values.decode(PromptMetadata.self, forKey: .metadata),
      body: values.decode(String.self, forKey: .body),
      schema: values.decode([PromptVariable].self, forKey: .schema),
      context: values.decode([PromptContextItem].self, forKey: .context),
      workflow: values.decodeIfPresent(PromptWorkflow.self, forKey: .workflow)
    )
  }
}

import Foundation

/// Record-shape checks shared by draft and decoded version boundaries.
/// This raw-byte lower bound is NOT the canonical encoded input size. Task 2 must
/// additionally account for all framing and identity bytes using PromptInputEncoding.v1.
func validatePromptContent(body: String, schema: [PromptVariable],
  context: [PromptContextItem], workflow: PromptWorkflow?) throws {
  guard schema.count <= 128, Set(schema.map(\.name)).count == schema.count else {
    throw PromptError.invalidSchema
  }
  guard context.count <= 10 else { throw PromptError.tooManyContextItems }
  guard Set(context.map(\.id)).count == context.count else { throw PromptError.invalidMetadata }
  var remaining = 1_048_576
  func count(_ field: String) throws {
    let bytes = field.utf8.count
    guard bytes <= remaining else { throw PromptError.inputTooLarge }
    remaining -= bytes
  }
  try count(body)
  for variable in schema { try count(variable.name) }
  for item in context {
    try count(item.label)
    try count(item.text)
  }
  if let workflow { try count(workflow.id) }
}

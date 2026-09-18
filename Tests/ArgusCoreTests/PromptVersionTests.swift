import Foundation
import Testing
import ArgusCore

@Suite struct PromptVersionTests {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)
  private let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
  private let contextID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

  // Catches omitted normalization, locale-sensitive folding and unwanted accent/width folding.
  @Test func normalizationGoldenVectors() {
    let vectors = [("RELEASE", "release"), ("É", "é"), ("E\u{301}", "é"),
                   ("I", "i"), ("İ", "i\u{307}"), ("ı", "ı"),
                   ("Straße", "strasse"), ("ﬃ", "ffi"), ("Ａ", "ａ")]
    for (input, expected) in vectors {
      #expect(Array(PromptSearchNormalization.v1(input).utf8) == Array(expected.utf8))
    }
    #expect(PromptSearchNormalization.v1("é") != PromptSearchNormalization.v1("e"))
    #expect(PromptSearchNormalization.v1("Ａ") != PromptSearchNormalization.v1("A"))
  }

  // Catches keeping duplicate normalized tags, losing display spelling or sorting by display text.
  @Test func metadataTrimsDeduplicatesAndSorts() throws {
    let metadata = try PromptMetadata(title: " Release \n", tags: ["z", " Work ", "work", "É", "E\u{301}", "A"], project: " ARGUS ", isFavorite: true)
    #expect(metadata.title == "Release")
    #expect(metadata.tags == ["A", "Work", "z", "É"])
    #expect(metadata.project == "ARGUS")
    #expect(metadata.isFavorite)
    #expect(try PromptMetadata(title: "T", tags: [], project: " \n", isFavorite: false).project == nil)
  }

  // Byte boundaries, not character counts, and no truncation of excess declarations.
  @Test func metadataRejectsEmptyAndOversizedFields() throws {
    for title in ["", " \n", String(repeating: "é", count: 257)] {
      #expect(throws: PromptError.invalidMetadata) { try PromptMetadata(title: title, tags: [], project: nil, isFavorite: false) }
    }
    _ = try PromptMetadata(title: String(repeating: "é", count: 256), tags: [String(repeating: "é", count: 64)], project: String(repeating: "é", count: 256), isFavorite: false)
    for tags in [[" "], [String(repeating: "é", count: 65)], Array(repeating: "same", count: 33)] {
      #expect(throws: PromptError.invalidMetadata) { try PromptMetadata(title: "T", tags: tags, project: nil, isFavorite: false) }
    }
    _ = try PromptMetadata(title: "T", tags: (0..<32).map { "tag\($0)" }, project: nil, isFavorite: false)
    #expect(throws: PromptError.invalidMetadata) { try PromptMetadata(title: "T", tags: [], project: String(repeating: "é", count: 257), isFavorite: false) }
  }

  @Test func variableGrammarIsASCIIReservedAndBounded() throws {
    for name in ["", "context", "9name", "a-b", "é", " name", "a.b", String(repeating: "a", count: 65)] {
      #expect(throws: PromptError.invalidSchema) { try PromptVariable(name: name, required: true) }
    }
    for name in ["_", "a9_Z", "Context", String(repeating: "a", count: 64)] {
      let variable = try PromptVariable(name: name, required: false)
      #expect(variable.name == name)
      #expect(!variable.required)
    }
  }

  private func capture(body: String = "Review {{project}} {{context}}") throws -> PromptDraft {
    try Prompt.capture(id: id,
      metadata: PromptMetadata(title: "Release", tags: ["Work", "work"], project: "ARGUS", isFavorite: true),
      body: body, schema: [PromptVariable(name: "project", required: true)],
      context: [PromptContextItem(id: contextID, label: "Selection", text: "Original")],
      workflow: PromptWorkflow(id: "prepare-prompt", version: 1), now: now)
  }

  // Catches loss of snapshot isolation for all editable fields, not just the body.
  @Test func promptVersionCopyDoesNotMutateHistory() throws {
    let draft = try capture()
    let v1 = try PromptVersion.save(draft: draft, number: 1, now: now)
    var editing = v1.editDraft(revision: 1, now: now.addingTimeInterval(1))
    editing.body = "Second literal"
    editing.metadata = try PromptMetadata(title: "Renamed", tags: [], project: nil, isFavorite: false)
    editing.schema = []
    editing.context = []
    editing.workflow = nil
    let v2 = try PromptVersion.save(draft: editing, number: 2, now: now.addingTimeInterval(2))
    #expect(v1.body == "Review {{project}} {{context}}")
    #expect(v1.metadata.title == "Release")
    #expect(v1.metadata.tags == ["Work"])
    #expect(v1.schema.map(\.name) == ["project"])
    #expect(v1.context.map(\.text) == ["Original"])
    #expect(v1.workflow?.id == "prepare-prompt")
    #expect(editing.baseVersion == 1)
    #expect(editing.modifiedAt == now.addingTimeInterval(1))
    #expect(v2.number == 2)
    #expect(v2.promptID == id)
    #expect(v2.metadata.title == "Renamed")
    #expect(v2.savedAt == now.addingTimeInterval(2))
  }

  @Test func saveRequiresConsecutiveVersionAndValidDraftRevision() throws {
    let draft = try capture()
    for number: Int64 in [0, -1, 2, Int64.max] {
      #expect(throws: CoreError.invalidRevision) { try PromptVersion.save(draft: draft, number: number, now: now) }
    }
    let v1 = try PromptVersion.save(draft: draft, number: 1, now: now)
    for revision: Int64 in [0, -1] {
      let invalid = v1.editDraft(revision: revision, now: now)
      #expect(throws: CoreError.invalidRevision) { try invalid.validate() }
      #expect(throws: CoreError.invalidRevision) { try PromptVersion.save(draft: invalid, number: 2, now: now) }
    }
    let editing = v1.editDraft(revision: 1, now: now)
    for number: Int64 in [1, 3] {
      #expect(throws: CoreError.invalidRevision) { try PromptVersion.save(draft: editing, number: number, now: now) }
    }
  }

  @Test func datesAreValidatedAtCaptureEditAndSaveBoundaries() throws {
    let draft = try capture()
    let v1 = try PromptVersion.save(draft: draft, number: 1, now: now)
    for seconds in [Double.nan, Double.infinity, -62_135_596_801, 253_402_300_800] {
      let badDate = Date(timeIntervalSince1970: seconds)
      #expect(throws: CoreError.invalidDate) {
        try Prompt.capture(id: id, metadata: draft.metadata, body: "", schema: [], context: [], workflow: nil, now: badDate)
      }
      #expect(throws: CoreError.invalidDate) { try v1.editDraft(revision: 1, now: badDate).validate() }
      #expect(throws: CoreError.invalidDate) { try PromptVersion.save(draft: draft, number: 1, now: badDate) }
    }
    #expect(throws: CoreError.invalidDate) { try PromptVersion.save(draft: draft, number: 1, now: now.addingTimeInterval(-1)) }
  }

  @Test func captureAllowsIncompleteTemplatesButRejectsInvalidRecordShape() throws {
    #expect(try capture(body: "Unfinished {{").body == "Unfinished {{")
    var draft = try capture()
    draft.schema = [try PromptVariable(name: "x", required: true), try PromptVariable(name: "x", required: false)]
    #expect(throws: PromptError.invalidSchema) { try draft.validate() }
    draft.schema = try (0..<129).map { try PromptVariable(name: "v\($0)", required: false) }
    #expect(throws: PromptError.invalidSchema) { try draft.validate() }
    draft.schema.removeLast()
    try draft.validate()
    draft.schema = [try PromptVariable(name: "x", required: true), try PromptVariable(name: "X", required: true)]
    try draft.validate()
    draft.context = (0..<11).map { _ in PromptContextItem(id: contextID, label: "", text: "") }
    #expect(throws: PromptError.tooManyContextItems) { try draft.validate() }
    draft.context = [PromptContextItem(id: contextID, label: "One", text: "1"), PromptContextItem(id: contextID, label: "Two", text: "2")]
    #expect(throws: PromptError.invalidMetadata) { try draft.validate() }
    draft.context = []
    draft.body = String(repeating: "é", count: 524_289)
    #expect(throws: PromptError.inputTooLarge) { try draft.validate() }
  }

  @Test func workflowIdentityIsExplicitAndValidated() throws {
    for identity in ["", " ", " prepare-prompt"] {
      #expect(throws: PromptError.invalidMetadata) { try PromptWorkflow(id: identity, version: 1) }
    }
    for version: Int64 in [0, -1] {
      #expect(throws: CoreError.invalidRevision) { try PromptWorkflow(id: "prepare-prompt", version: version) }
    }
    #expect(try PromptWorkflow(id: "future-workflow", version: 2).version == 2)
  }

  private func root(latest: Int64? = nil, draft: Int64? = 1, revision: Int64 = 1,
    created: Date? = nil, modified: Date? = nil) throws -> Prompt {
    try Prompt(id: id, createdAt: created ?? now, modifiedAt: modified ?? now,
      revision: revision, isArchived: false, latestVersion: latest, draftRevision: draft)
  }

  @Test func archivedInitialCaptureRestoresToInbox() throws {
    let initial = try root()
    #expect(initial.membership == .inbox)
    let archived = try initial.settingArchived(true, expectedRevision: 1, now: now.addingTimeInterval(1))
    #expect(archived.visibleMembership == nil)
    #expect(archived.membership == .inbox)
    #expect(archived.draftRevision == 1)
    let restored = try archived.settingArchived(false, expectedRevision: 2, now: now.addingTimeInterval(2))
    #expect(restored.visibleMembership == .inbox)
    #expect(restored.revision == 3)
    #expect(restored.createdAt == now)
    #expect(restored.modifiedAt == now.addingTimeInterval(2))
    #expect(!initial.isArchived)
  }

  @Test func savedPromptWithEditingDraftStaysInLibraryAcrossArchiveRestore() throws {
    for draft: Int64? in [nil, 7] {
      let saved = try root(latest: 3, draft: draft)
      #expect(saved.visibleMembership == .library)
      let archived = try saved.settingArchived(true, expectedRevision: 1, now: now)
      #expect(archived.visibleMembership == nil)
      let restored = try archived.settingArchived(false, expectedRevision: 2, now: now)
      #expect(restored.visibleMembership == .library)
      #expect(restored.latestVersion == 3)
      #expect(restored.draftRevision == draft)
    }
  }

  @Test func rootRejectsInvalidReferencesDatesAndStaleArchiveChanges() throws {
    for revision: Int64 in [0, -1] {
      #expect(throws: CoreError.invalidRevision) { try root(revision: revision) }
      #expect(throws: CoreError.invalidRevision) { try root(latest: revision) }
      #expect(throws: CoreError.invalidRevision) { try root(draft: revision) }
    }
    #expect(throws: PromptError.invalidMetadata) { try root(latest: nil, draft: nil) }
    #expect(throws: CoreError.invalidDate) { try root(created: now.addingTimeInterval(1)) }
    #expect(throws: CoreError.invalidDate) { try root(modified: Date(timeIntervalSince1970: .infinity)) }
    let initial = try root()
    #expect(throws: PromptError.conflict) { try initial.settingArchived(true, expectedRevision: 2, now: now) }
    #expect(throws: CoreError.invalidDate) { try initial.settingArchived(true, expectedRevision: 1, now: now.addingTimeInterval(-1)) }
    let exhausted = try root(revision: Int64.max)
    #expect(throws: CoreError.invalidRevision) { try exhausted.settingArchived(true, expectedRevision: Int64.max, now: now) }
  }

  // Synthetic test-only encoding. Production protected domain aggregates are not Encodable.
  private func versionObject(_ version: PromptVersion) throws -> [String: Any] {
    var object: [String: Any] = ["promptID": version.promptID.uuidString, "number": version.number,
      "savedAt": version.savedAt.timeIntervalSinceReferenceDate,
      "metadata": try JSONSerialization.jsonObject(with: JSONEncoder().encode(version.metadata)),
      "body": version.body,
      "schema": try JSONSerialization.jsonObject(with: JSONEncoder().encode(version.schema)),
      "context": version.context.map { ["id": $0.id.uuidString, "label": $0.label, "text": $0.text] }]
    if let workflow = version.workflow {
      object["workflow"] = ["id": workflow.id, "version": workflow.version]
    }
    return object
  }

  private func decode<T: Decodable>(_ type: T.Type, _ object: [String: Any]) throws -> T {
    try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: object))
  }

  @Test func versionRoundTripPreservesIdentityAndOrderedContext() throws {
    var draft = try capture()
    draft.context.append(PromptContextItem(id: id, label: "Second", text: "é\u{0000}Z"))
    let original = try PromptVersion.save(draft: draft, number: 1, now: now)
    let restored = try decode(PromptVersion.self, versionObject(original))
    #expect(restored == original)
    #expect(restored.context.map(\.id) == [contextID, id])
    #expect(restored.context.map(\.text) == ["Original", "é\u{0000}Z"])
  }

  @Test func versionDecodeRejectsInvalidIdentityRevisionDateAndContent() throws {
    let version = try PromptVersion.save(draft: capture(), number: 1, now: now)
    let valid = try versionObject(version)
    for number: Int64 in [0, -1] {
      var object = valid; object["number"] = number
      #expect(throws: CoreError.invalidRevision) { try decode(PromptVersion.self, object) }
    }
    for field in ["promptID", "number", "savedAt"] {
      var object = valid; object.removeValue(forKey: field)
      #expect(throws: (any Error).self) { try decode(PromptVersion.self, object) }
    }
    var object = valid; object["promptID"] = "not-a-uuid"
    #expect(throws: (any Error).self) { try decode(PromptVersion.self, object) }
    object = valid; object["savedAt"] = Date(timeIntervalSince1970: 253_402_300_800).timeIntervalSinceReferenceDate
    #expect(throws: CoreError.invalidDate) { try decode(PromptVersion.self, object) }
    object = valid; object["schema"] = [["name": "x", "required": true], ["name": "x", "required": false]]
    #expect(throws: PromptError.invalidSchema) { try decode(PromptVersion.self, object) }
    object = valid; object["context"] = [["id": "broken", "label": "L", "text": "T"]]
    #expect(throws: (any Error).self) { try decode(PromptVersion.self, object) }
    object = valid; object["body"] = String(repeating: "x", count: 1_048_577)
    #expect(throws: PromptError.inputTooLarge) { try decode(PromptVersion.self, object) }
  }

  @Test func decodedDraftKeepsRevisionAndRejectsInvalidReferences() throws {
    let version = try PromptVersion.save(draft: capture(), number: 1, now: now)
    let original = version.editDraft(revision: 7, now: now)
    var object = try versionObject(version)
    object.removeValue(forKey: "number")
    object.removeValue(forKey: "savedAt")
    object["revision"] = 7; object["baseVersion"] = 1
    object["modifiedAt"] = now.timeIntervalSinceReferenceDate
    #expect(try decode(PromptDraft.self, object) == original)
    for field in ["revision", "baseVersion"] {
      var invalid = object; invalid[field] = 0
      #expect(throws: CoreError.invalidRevision) { try decode(PromptDraft.self, invalid) }
    }
    object["baseVersion"] = Int64.max
    let exhausted = try decode(PromptDraft.self, object)
    #expect(throws: CoreError.invalidRevision) { try PromptVersion.save(draft: exhausted, number: 1, now: now) }
  }

  @Test func metadataVariableWorkflowDecodersCannotBypassValidation() throws {
    #expect(throws: PromptError.invalidMetadata) {
      try decode(PromptMetadata.self, ["title": " ", "tags": [], "isFavorite": false])
    }
    let meta = try decode(PromptMetadata.self, ["title": " T ", "tags": ["A", "a"], "isFavorite": false])
    #expect(meta.title == "T")
    #expect(meta.tags == ["A"])
    #expect(throws: PromptError.invalidSchema) { try decode(PromptVariable.self, ["name": "context", "required": true]) }
    #expect(throws: CoreError.invalidRevision) { try decode(PromptWorkflow.self, ["id": "prepare-prompt", "version": 0]) }
  }

  @Test func rootDecoderPreservesDraftReferenceAndValidatesInvariants() throws {
    let original = try root(latest: 2, draft: 7)
    let data = try JSONEncoder().encode(original)
    #expect(try JSONDecoder().decode(Prompt.self, from: data) == original)
    let valid = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    for field in ["revision", "latestVersion", "draftRevision"] {
      var object = valid; object[field] = 0
      #expect(throws: CoreError.invalidRevision) { try decode(Prompt.self, object) }
    }
    var object = valid; object["modifiedAt"] = now.addingTimeInterval(-1).timeIntervalSinceReferenceDate
    #expect(throws: CoreError.invalidDate) { try decode(Prompt.self, object) }
    object = valid; object.removeValue(forKey: "latestVersion"); object.removeValue(forKey: "draftRevision")
    #expect(throws: PromptError.invalidMetadata) { try decode(Prompt.self, object) }
  }

  @Test func errorDescriptionsNeverExposeAssociatedInput() {
    let marker = "private-value-or-key-material"
    for error in [PromptError.missingVariable(marker), .unexpectedVariable(marker)] {
      #expect(!String(describing: error).contains(marker))
      #expect(!String(reflecting: error).contains(marker))
      #expect(!error.localizedDescription.contains(marker))
    }
    #expect(PromptError.missingVariable("x") != PromptError.missingVariable("y"))
  }
}

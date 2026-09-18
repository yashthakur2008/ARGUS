import Foundation

public enum PromptError: Error, Equatable, Sendable, LocalizedError, CustomStringConvertible, CustomDebugStringConvertible {
  case invalidMetadata, invalidTemplate, invalidSchema
  case missingVariable(String), unexpectedVariable(String)
  case contextPlaceholderRequired, inputTooLarge, outputTooLarge, tooManyContextItems, invalidUTF8
  case conflict, notFound, archived, draftOnly
  case protectedStorageUnavailable, recoveryRequired, corruptProtectedContent, unsupportedEnvelope
  case searchScopeTooLarge, staleSearch, invalidSearchPage

  /// Static descriptions only. Associated names are available for typed UI handling,
  /// but must not be accidentally interpolated into diagnostics.
  public var description: String {
    switch self {
    case .invalidMetadata: "Invalid prompt metadata."
    case .invalidTemplate: "Invalid prompt template."
    case .invalidSchema: "Invalid variable schema."
    case .missingVariable: "A required variable is missing."
    case .unexpectedVariable: "An undeclared variable was supplied."
    case .contextPlaceholderRequired: "A context placeholder is required."
    case .inputTooLarge: "Prompt input exceeds the byte limit."
    case .outputTooLarge: "Resolved output exceeds the byte limit."
    case .tooManyContextItems: "Too many context items."
    case .invalidUTF8: "Invalid UTF-8 input."
    case .conflict: "The prompt has changed."
    case .notFound: "The prompt was not found."
    case .archived: "The prompt is archived."
    case .draftOnly: "A saved prompt version is required."
    case .protectedStorageUnavailable: "Protected prompt storage is unavailable."
    case .recoveryRequired: "Protected prompt storage requires recovery."
    case .corruptProtectedContent: "Protected prompt content could not be authenticated."
    case .unsupportedEnvelope: "Unsupported protected content envelope."
    case .searchScopeTooLarge: "Narrow the prompt search scope."
    case .staleSearch: "Refresh the prompt search."
    case .invalidSearchPage: "Invalid prompt search page."
    }
  }

  public var debugDescription: String { description }
  public var errorDescription: String? { description }
}

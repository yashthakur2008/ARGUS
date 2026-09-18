import Foundation

public enum SpeechOutputResult: Sendable, Equatable { case finished, cancelled, failed }

/// Completions carry the originating request ID and must be delivered after speak returns.
/// Implementations report actual finish/cancel/failure, never a timer-based successful finish.
@MainActor public protocol SpeechOutput: AnyObject {
  var isSpeaking: Bool { get }
  var onCompletion: (@MainActor @Sendable (UUID, SpeechOutputResult) -> Void)? { get set }
  @discardableResult func speak(_ text: String) -> UUID
  func stop()
}

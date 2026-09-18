import AVFoundation
import Foundation

@MainActor public protocol MP3Playback: AnyObject {
  var onCompletion: (@MainActor @Sendable (UUID, SpeechOutputResult) -> Void)? { get set }
  func play(_ data: Data, id: UUID) throws
  func stop()
}

/// In-memory playback only. No temporary audio files or synthesized system voices.
@MainActor public final class NativeMP3Playback: NSObject, MP3Playback, AVAudioPlayerDelegate {
  public var onCompletion: (@MainActor @Sendable (UUID, SpeechOutputResult) -> Void)?
  private var current: (player: AVAudioPlayer, id: UUID)?

  public override init() { super.init() }

  public func play(_ data: Data, id: UUID) throws {
    stop()
    guard !data.isEmpty, data.count <= ElevenLabsResponseBuffer.maximumBytes else {
      throw ElevenLabsSpeechFailure.invalidAudio
    }
    do {
      let player = try AVAudioPlayer(data: data, fileTypeHint: AVFileType.mp3.rawValue)
      player.delegate = self
      current = (player, id)
      guard player.prepareToPlay(), player.play() else {
        stop()
        throw ElevenLabsSpeechFailure.playback
      }
    } catch {
      stop()
      throw ElevenLabsSpeechFailure.playback
    }
  }

  public func stop() {
    let player = current?.player
    current = nil
    player?.delegate = nil
    player?.stop()
  }

  nonisolated public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer,
    successfully flag: Bool) {
    deliver(ObjectIdentifier(player), result: flag ? .finished : .failed)
  }

  nonisolated public func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer,
    error: (any Error)?) {
    deliver(ObjectIdentifier(player), result: .failed)
  }

  nonisolated private func deliver(_ identity: ObjectIdentifier, result: SpeechOutputResult) {
    Task { @MainActor [weak self] in
      guard let self, let current = self.current,
        ObjectIdentifier(current.player) == identity else { return }
      self.stop()
      self.onCompletion?(current.id, result)
    }
  }
}

import AppKit
import Testing
@testable import ArgusPresentation

struct ScreenEdgeGlowTests {
  @Test func borderUsesLocalCoordinatesForOffsetDisplay() {
    let frame = CGRect(x: -1920, y: 300, width: 1920, height: 1080)
    let edges = ScreenEdgeGlowGeometry.edges(for: frame.size)
    #expect(edges.count == 4)
    #expect(edges.contains(CGRect(x: 0, y: 0, width: 1920, height: 6)))
    #expect(edges.contains(CGRect(x: 0, y: 1074, width: 1920, height: 6)))
    #expect(edges.contains(CGRect(x: 0, y: 6, width: 6, height: 1068)))
    #expect(edges.contains(CGRect(x: 1914, y: 6, width: 6, height: 1068)))
  }

  @Test func tinyAndInvalidDisplaysStayBounded() {
    for size in [CGSize(width: 1, height: 1), CGSize(width: 8, height: 4)] {
      let bounds = CGRect(origin: .zero, size: size)
      let edges = ScreenEdgeGlowGeometry.edges(for: size)
      #expect(!edges.isEmpty)
      #expect(edges.allSatisfy { bounds.contains($0) && $0.width > 0 && $0.height > 0 })
    }
    for size in [CGSize.zero, CGSize(width: -1, height: 100), CGSize(width: CGFloat.infinity, height: 100)] {
      #expect(ScreenEdgeGlowGeometry.edges(for: size).isEmpty)
    }
  }

  @Test func feedbackIsBriefAndAlwaysStaticIncludingReduceMotion() {
    let policy = ScreenEdgeGlowPolicy()
    #expect(policy.duration > .zero)
    #expect(policy.duration <= .seconds(2))
    #expect(policy.animationBehavior == .none)
    #expect(policy.styleMask == [.borderless, .nonactivatingPanel])
    #expect(policy.styleMask.contains(.nonactivatingPanel))
    #expect(policy.ignoresMouseEvents)
    #expect(policy.collectionBehavior.contains(.canJoinAllSpaces))
    #expect(policy.collectionBehavior.contains(.fullScreenAuxiliary))
    #expect(policy.collectionBehavior.contains(.ignoresCycle))
  }

  @Test func staleHideCannotEndNewPresentation() {
    var lifetime = ScreenEdgeGlowLifetime()
    let first = lifetime.begin()
    let second = lifetime.begin()
    #expect(first != second)
    let staleEnded = lifetime.end(ifCurrent: first)
    let currentEnded = lifetime.end(ifCurrent: second)
    let endedTwice = lifetime.end(ifCurrent: second)
    #expect(!staleEnded)
    #expect(currentEnded)
    #expect(!endedTwice)
  }

  @Test func explicitHideAndScreenCleanupInvalidatePendingHide() {
    var lifetime = ScreenEdgeGlowLifetime()
    let first = lifetime.begin()
    lifetime.invalidate()
    let staleEnded = lifetime.end(ifCurrent: first)
    #expect(!staleEnded)
    let next = lifetime.begin()
    let nextEnded = lifetime.end(ifCurrent: next)
    #expect(nextEnded)
  }
}

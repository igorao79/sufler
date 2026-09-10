import Foundation
import os
import QuartzCore

/// Fan-out for the cursor.
///
/// The cursor is written by the aligner queue and read by the render loop (`CADisplayLink`, main
/// thread) and by the JS bridge. The renderer must never block on the aligner, and the aligner
/// must never block on the main thread — so the value itself lives behind an unfair lock that is
/// held for exactly one integer store, and the two consumers are notified out-of-band.
final class PositionBus {

  struct Position {
    var tokenIndex: Int = 0
    var lineIndex: Int = 0
    var indexInLine: Int = 0
    var confidence: Double = 0
  }

  /// Called synchronously on whatever thread committed the position. Used by the PiP pump to
  /// flip its dirty flag — must stay cheap and lock-free.
  var onImmediateChange: ((Position) -> Void)?

  /// Called on the main queue, rate-limited to `jsThrottleHz`. Used to emit a JS event.
  var onThrottledChange: ((Position) -> Void)?

  var jsThrottleHz: Double = 12 {
    didSet { jsThrottleHz = min(max(jsThrottleHz, 1), 60) }
  }

  private var lock = os_unfair_lock_s()
  private var current = Position()
  private var lastEmit: CFTimeInterval = 0
  private var pendingEmit = false

  var position: Position {
    os_unfair_lock_lock(&lock)
    defer { os_unfair_lock_unlock(&lock) }
    return current
  }

  func commit(_ position: Position) {
    os_unfair_lock_lock(&lock)
    let changed = position.tokenIndex != current.tokenIndex
    current = position
    os_unfair_lock_unlock(&lock)

    onImmediateChange?(position)
    guard changed else { return }
    scheduleThrottledEmit()
  }

  func reset(to tokenIndex: Int, lineIndex: Int, indexInLine: Int) {
    commit(Position(tokenIndex: tokenIndex, lineIndex: lineIndex,
                    indexInLine: indexInLine, confidence: 1))
  }

  private func scheduleThrottledEmit() {
    let interval = 1.0 / jsThrottleHz
    let now = CACurrentMediaTime()

    os_unfair_lock_lock(&lock)
    let due = now - lastEmit >= interval
    let alreadyPending = pendingEmit
    if due {
      lastEmit = now
    } else if !alreadyPending {
      pendingEmit = true
    }
    let snapshot = current
    os_unfair_lock_unlock(&lock)

    if due {
      DispatchQueue.main.async { [weak self] in self?.onThrottledChange?(snapshot) }
    } else if !alreadyPending {
      // Coalesce: one trailing emit carries whatever the latest value is when it fires.
      DispatchQueue.main.asyncAfter(deadline: .now() + interval) { [weak self] in
        guard let self else { return }
        os_unfair_lock_lock(&self.lock)
        self.pendingEmit = false
        self.lastEmit = CACurrentMediaTime()
        let latest = self.current
        os_unfair_lock_unlock(&self.lock)
        self.onThrottledChange?(latest)
      }
    }
  }
}

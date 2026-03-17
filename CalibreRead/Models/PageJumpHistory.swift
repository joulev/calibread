import Foundation

/// Tracks page jump history for the EPUB reader, enabling browser-like
/// back/forward navigation when the user jumps more than 5 pages at once
/// (e.g. via table of contents).
///
/// All jump origins are stored as a flat list of targets. Each target is a
/// position the user can navigate to. When the user clicks a target, their
/// current position replaces it in the list. Buttons are displayed based on
/// whether the target page is before or after the current page.
@MainActor
@Observable
final class PageJumpHistory {
    /// A reading position in the book.
    struct Position: Equatable {
        let chapterIndex: Int
        let page: Int
        /// Estimated global page for distance comparison and display.
        /// Uses actual pagination counts when available, otherwise a rough estimate.
        let estimatedGlobalPage: Int
    }

    /// Minimum page distance to consider a navigation a "jump" worth tracking.
    private let jumpThreshold = 5

    /// Maximum number of targets to keep.
    private let maxTargets = 10

    /// How long (seconds) after the last navigation button use before
    /// the buttons auto-hide, assuming only normal navigation occurs.
    private let autoHideDelay: TimeInterval = 300 // 5 minutes

    /// All positions the user can jump to.
    private(set) var targets: [Position] = []

    /// The last known position, used to detect jump distance.
    var lastKnownPosition: Position?

    /// Whether the buttons should be visible.
    private(set) var isVisible = false

    /// Timer that hides buttons after inactivity.
    private var hideTimer: Task<Void, Never>?

    /// Whether the current navigation was triggered by a target button,
    /// so we don't re-record it as a new jump.
    private var isNavigatingFromHistory = false

    /// Call this whenever the reading position changes (normal or jump navigation).
    /// Detects jumps and updates history accordingly.
    func positionDidChange(to position: Position) {
        defer { lastKnownPosition = position }

        // If this navigation was triggered by a target button, don't record it
        if isNavigatingFromHistory {
            isNavigatingFromHistory = false
            checkAutoRemoval(arrivedAt: position)
            return
        }

        guard let previous = lastKnownPosition else { return }
        let distance = abs(position.estimatedGlobalPage - previous.estimatedGlobalPage)

        if distance > jumpThreshold {
            // This is a jump — save the origin as a target
            targets.append(previous)
            // Trim oldest targets if we exceed the limit
            if targets.count > maxTargets {
                targets.removeFirst(targets.count - maxTargets)
            }
            isVisible = true
            resetHideTimer()
        } else {
            // Normal navigation — check if we've arrived at a target
            checkAutoRemoval(arrivedAt: position)
        }
    }

    /// Navigate to a specific target. Returns the position to go to.
    /// Removes the target and adds the current position in its place.
    func navigateToTarget(at index: Int, from current: Position) -> Position? {
        guard targets.indices.contains(index) else { return nil }
        let target = targets[index]
        targets[index] = current
        isNavigatingFromHistory = true
        resetHideTimer()
        return target
    }

    /// Reset state (e.g. when book changes).
    func reset() {
        targets.removeAll()
        lastKnownPosition = nil
        isVisible = false
        hideTimer?.cancel()
        hideTimer = nil
    }

    // MARK: - Private

    /// If the user navigates normally to exactly a target position, remove it.
    private func checkAutoRemoval(arrivedAt position: Position) {
        targets.removeAll { target in
            target.chapterIndex == position.chapterIndex && target.page == position.page
        }
        // Hide if no targets remain
        if targets.isEmpty {
            isVisible = false
            hideTimer?.cancel()
            hideTimer = nil
        }
    }

    /// Start/restart the auto-hide timer. If the user doesn't use navigation buttons
    /// for `autoHideDelay` seconds while navigating normally, hide the buttons.
    private func resetHideTimer() {
        hideTimer?.cancel()
        let delay = autoHideDelay
        hideTimer = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            isVisible = false
            targets.removeAll()
        }
    }
}

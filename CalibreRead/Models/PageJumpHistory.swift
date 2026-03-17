import Foundation

/// Tracks page jump history for the EPUB reader, enabling browser-like
/// back/forward navigation when the user jumps more than 5 pages at once
/// (e.g. via table of contents).
@MainActor
@Observable
final class PageJumpHistory {
    /// Minimum page distance to consider a navigation a "jump" worth tracking.
    private let jumpThreshold = 5

    /// How long (seconds) after the last back/forward button use before
    /// the buttons auto-hide, assuming only normal navigation occurs.
    private let autoHideDelay: TimeInterval = 300 // 5 minutes

    /// The history stack of global page positions where jumps originated.
    /// backStack[last] is the most recent origin we can go back to.
    private(set) var backStack: [Int] = []

    /// Pages we can go forward to after using "back".
    private(set) var forwardStack: [Int] = []

    /// The last known global page, used to detect jump distance.
    var lastKnownPage: Int?

    /// Whether the buttons should be visible.
    private(set) var isVisible = false

    /// Timer that hides buttons after inactivity.
    private var hideTimer: Task<Void, Never>?

    /// Whether the current navigation was triggered by a back/forward action,
    /// so we don't re-record it as a new jump.
    private var isNavigatingFromHistory = false

    var canGoBack: Bool { !backStack.isEmpty && isVisible }
    var canGoForward: Bool { !forwardStack.isEmpty && isVisible }

    /// The page the back button would navigate to (for display/removal logic).
    var backTarget: Int? { backStack.last }
    /// The page the forward button would navigate to (for display/removal logic).
    var forwardTarget: Int? { forwardStack.last }

    /// Call this whenever the global page changes (normal or jump navigation).
    /// Detects jumps and updates history accordingly.
    func pageDidChange(to globalPage: Int) {
        defer { lastKnownPage = globalPage }

        // If this navigation was triggered by back/forward, don't record it
        if isNavigatingFromHistory {
            isNavigatingFromHistory = false
            checkAutoRemoval(arrivedAt: globalPage)
            return
        }

        guard let previous = lastKnownPage else { return }
        let distance = abs(globalPage - previous)

        if distance > jumpThreshold {
            // This is a jump — push the origin onto the back stack
            backStack.append(previous)
            // Clear forward stack on new jump (like browser behavior)
            forwardStack.removeAll()
            isVisible = true
            resetHideTimer()
        } else {
            // Normal navigation — check if we've arrived at a target
            checkAutoRemoval(arrivedAt: globalPage)
        }
    }

    /// Navigate back. Returns the global page to go to, or nil if can't go back.
    func goBack(currentGlobalPage: Int) -> Int? {
        guard let target = backStack.popLast() else { return nil }
        forwardStack.append(currentGlobalPage)
        isNavigatingFromHistory = true
        resetHideTimer()
        return target
    }

    /// Navigate forward. Returns the global page to go to, or nil if can't go forward.
    func goForward(currentGlobalPage: Int) -> Int? {
        guard let target = forwardStack.popLast() else { return nil }
        backStack.append(currentGlobalPage)
        isNavigatingFromHistory = true
        resetHideTimer()
        return target
    }

    /// Reset state (e.g. when book changes or pagination invalidates pages).
    func reset() {
        backStack.removeAll()
        forwardStack.removeAll()
        lastKnownPage = nil
        isVisible = false
        hideTimer?.cancel()
        hideTimer = nil
    }

    // MARK: - Private

    /// If the user navigates normally to exactly the page a button points to,
    /// remove that entry from the stack.
    private func checkAutoRemoval(arrivedAt page: Int) {
        if let backTarget = backStack.last, backTarget == page {
            backStack.removeLast()
        }
        if let forwardTarget = forwardStack.last, forwardTarget == page {
            forwardStack.removeLast()
        }
        // Hide if both stacks are empty
        if backStack.isEmpty && forwardStack.isEmpty {
            isVisible = false
            hideTimer?.cancel()
            hideTimer = nil
        }
    }

    /// Start/restart the auto-hide timer. If the user doesn't use back/forward
    /// for `autoHideDelay` seconds while navigating normally, hide the buttons.
    private func resetHideTimer() {
        hideTimer?.cancel()
        let delay = autoHideDelay
        hideTimer = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            isVisible = false
            backStack.removeAll()
            forwardStack.removeAll()
        }
    }
}

import QuartzCore
import SwiftUI

extension ConversationView {
    func scrollIfPinned(_ proxy: ScrollViewProxy, animated: Bool) {
        guard !scrollState.isPrepending else { return }
        if isOpeningSession {
            showLatest(proxy)
            return
        }
        guard isPinnedToBottom else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo(bottomAnchor, anchor: .bottom)
            }
        } else {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                proxy.scrollTo(bottomAnchor, anchor: .bottom)
            }
        }
    }

    func prefetchEarlierTranscript(topGap: CGFloat) {
        guard !isOpeningSession, !scrollState.isPrepending, controller.hasEarlierTranscript,
              scrollState.viewportHeight > 0, let bottom = scrollState.bottomY,
              bottom > scrollState.viewportHeight + 2,
              topGap < scrollState.viewportHeight * 3 else { return }
        isPinnedToBottom = false
        scrollState.isPrepending = true
        let generation = scrollState.generation
        scrollState.pageTask = Task { @MainActor in
            // Leave the geometry-preference update before mutating the row list.
            await Task.yield()
            guard !Task.isCancelled, generation == scrollState.generation else { return }
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                // Preserve the visible row; never interrupt wheel momentum with
                // a scrollTo while prepending earlier messages.
                controller.loadEarlierTranscript()
            }
            do { try await Task.sleep(nanoseconds: 200_000_000) }
            catch { return }
            guard generation == scrollState.generation else { return }
            scrollState.isPrepending = false
            prefetchEarlierTranscript(topGap: scrollState.topGap)
        }
    }

    /// Keeps a few screens of earlier history laid out above the viewport,
    /// adding one turn at a time while the transcript is at rest.
    ///
    /// Prepending a turn builds all of its rows in one main-thread pass — tens of
    /// milliseconds for a long reply. Done on demand, that pass lands in the
    /// middle of a scroll and is felt as a stall; done here, it lands while
    /// nothing is moving, so scrolling up finds the history already in place.
    /// The on-demand prefetch above stays as the fallback for a fast fling.
    func startIdleHistoryFill() {
        scrollState.idleFillTask?.cancel()
        let generation = scrollState.generation
        scrollState.idleFillTask = Task { @MainActor in
            while !Task.isCancelled, generation == scrollState.generation {
                do { try await Task.sleep(nanoseconds: 250_000_000) }
                catch { return }
                guard generation == scrollState.generation else { return }
                guard controller.hasEarlierTranscript else { return }
                guard !isOpeningSession, !scrollState.isPrepending,
                      !controller.runtime.isBusy,
                      scrollState.viewportHeight > 0,
                      scrollState.topGap < scrollState.viewportHeight * Self.idleHistoryScreens,
                      CACurrentMediaTime() - scrollState.lastScrollActivity > 0.4
                else { continue }
                scrollState.isPrepending = true
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    controller.loadEarlierTranscript()
                }
                do { try await Task.sleep(nanoseconds: 200_000_000) }
                catch { return }
                guard generation == scrollState.generation else { return }
                scrollState.isPrepending = false
            }
        }
    }

    /// How many viewport heights of history the idle fill keeps above the
    /// visible rows.
    static let idleHistoryScreens: CGFloat = 8

    func beginOpeningSession(_ proxy: ScrollViewProxy) {
        scrollState.idleFillTask?.cancel()
        scrollState.pageTask?.cancel()
        scrollState.isPrepending = false
        scrollState.topGap = .infinity
        visibleTranscriptRowID = nil
        scrollState.generation = UUID()
        scrollState.openingTask?.cancel()
        scrollState.openingTask = nil
        isOpeningSession = true
        isPinnedToBottom = true
        showLatest(proxy)
    }

    func showLatest(_ proxy: ScrollViewProxy) {
        // One task owns the opening scroll. Geometry notifications merely wake
        // this path; they never cancel/recreate timers or queue extra scrolls.
        guard isOpeningSession, scrollState.openingTask == nil else { return }
        let generation = scrollState.generation
        scrollState.openingTask = Task { @MainActor in
            var settledSamples = 0
            while !Task.isCancelled, generation == scrollState.generation {
                do { try await Task.sleep(nanoseconds: 50_000_000) }
                catch { return }
                let waitingForOpen = state.sessionOpeningKey == state.selectedSessionKey
                    && state.sessionOpenRevision != state.sessionOpenCompletedRevision
                // Saved local history is enough to display the conversation;
                // model lists and tree metadata can continue refreshing later.
                guard !controller.isLoadingTranscriptHistory,
                      (!controller.items.isEmpty || !waitingForOpen),
                      scrollState.viewportHeight > 0 else { continue }

                if let bottom = scrollState.bottomY,
                   bottom <= scrollState.viewportHeight + 2 {
                    settledSamples += 1
                    if settledSamples >= 2 {
                        isPinnedToBottom = true
                        isOpeningSession = false
                        scrollState.openingTask = nil
                        startIdleHistoryFill()
                        return
                    }
                } else {
                    settledSamples = 0
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        proxy.scrollTo(bottomAnchor, anchor: .bottom)
                    }
                }
            }
        }
    }

    func followLatestWhileOpening(_ proxy: ScrollViewProxy) {
        guard isOpeningSession else { return }
        showLatest(proxy)
    }
}

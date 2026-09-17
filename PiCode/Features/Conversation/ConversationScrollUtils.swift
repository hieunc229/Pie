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

    func beginOpeningSession(_ proxy: ScrollViewProxy) {
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

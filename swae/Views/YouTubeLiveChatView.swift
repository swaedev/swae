//
//  YouTubeLiveChatView.swift
//  swae
//
//  Created by Suhail Saqan on 2/16/25.
//

import Combine
import Kingfisher
import NostrSDK
import SwiftUI

struct YouTubeLiveChatView: View {
    @EnvironmentObject var appState: AppState

    private let liveActivitiesEvent: LiveActivitiesEvent

    private let pageSize: Int = 50

    // Create the view model as a StateObject.
    @StateObject private var viewModel: LiveChatViewModel

    // Chat state
    @State private var liveChatMessages: [LiveChatMessageEvent] = []
    @State private var cancellables = Set<AnyCancellable>()

    @State private var autoScrollEnabled: Bool = true
    @State private var isPaginating: Bool = false
    @State private var isLoadingPage: Bool = false
    @State private var hasMoreMessages: Bool = true

    @State private var scrollOffset: CGFloat = 0
    @State private var lastScrollOffset: CGFloat = 0

    @State private var pubkeysToPullMetadata = Set<String>()
    @State private var metadataPullCancellable: AnyCancellable?

    // Add keyboard tracking for smooth interactions
    @State private var keyboardHeight: CGFloat = 0
    @State private var isKeyboardVisible: Bool = false
    @FocusState private var isTextFieldFocused: Bool

    init(liveActivitiesEvent: LiveActivitiesEvent) {
        self.liveActivitiesEvent = liveActivitiesEvent
        _viewModel = StateObject(
            wrappedValue: LiveChatViewModel(liveActivitiesEvent: liveActivitiesEvent))
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Chat messages
                chatMessagesView
                    .clipped()
                    .padding(
                        .bottom,
                        60
                            + (keyboardHeight > 0
                                ? keyboardHeight : geometry.safeAreaInsets.bottom + 20)
                    )
                    .animation(.easeInOut(duration: 0.25), value: keyboardHeight)

                // Chat input bar
                chatInputBar
            }
            .onAppear {
                viewModel.appState = appState
                subscribeToLiveChat()
                setupKeyboardObserver()
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .dismissKeyboardOnTap()
    }

    private var chatMessagesView: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    GeometryReader { geo in
                        Color.clear
                            .preference(
                                key: ScrollOffsetPreferenceKey.self,
                                value: geo.frame(in: .named("youtube_chat_scroll")).minY
                            )
                    }
                    .frame(height: 0)

                    ForEach(Array(liveChatMessages.enumerated()), id: \.offset) { index, message in
                        chatMessageRow(message: message, index: index)
                    }

                    // Spacer to ensure last message is visible above input
                    Color.clear
                        .frame(height: 20)
                        .id("youtube_chat_bottom")
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .coordinateSpace(name: "youtube_chat_scroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { newOffset in
                handleScrollOffset(newOffset)
            }
            .onChange(of: liveChatMessages) { _, messages in
                if autoScrollEnabled && !isPaginating && !messages.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            scrollProxy.scrollTo("youtube_chat_bottom", anchor: .bottom)
                        }
                    }
                }
            }
            .onChange(of: isKeyboardVisible) { _, visible in
                if visible && !autoScrollEnabled {
                    autoScrollEnabled = true
                    withAnimation(.easeOut(duration: 0.3)) {
                        scrollProxy.scrollTo("youtube_chat_bottom", anchor: .bottom)
                    }
                }
            }
        }
    }

    private func chatMessageRow(message: LiveChatMessageEvent, index: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ProfilePicView(
                pubkey: message.pubkey,
                size: 32,  // Smaller for YouTube layout
                profile: appState.metadataEvents[message.pubkey]?.userMetadata
            )

            VStack(alignment: .leading, spacing: 4) {
                ProfileNameView(publicKeyHex: message.pubkey)
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Text(message.content)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.caption)
            }
        }
        .id(index)
        .onAppear {
            if index == 0, hasMoreMessages, !isLoadingPage {
                loadMoreMessages()
            }
        }
    }

    private func handleScrollOffset(_ newOffset: CGFloat) {
        DispatchQueue.main.async {
            let delta = newOffset - lastScrollOffset
            let threshold: CGFloat = 15

            if delta < -threshold {
                // Scrolling down: enable auto-scroll
                if !autoScrollEnabled {
                    let isNearBottom = abs(newOffset) < 100
                    if isNearBottom {
                        autoScrollEnabled = true
                    }
                }
            } else if delta > threshold {
                // Scrolling up: disable auto-scroll
                autoScrollEnabled = false
            }
            lastScrollOffset = newOffset
        }
    }

    private var chatInputBar: some View {
        VStack(spacing: 0) {
            // Subtle separator
            Rectangle()
                .fill(Color(.separator))
                .frame(height: 0.5)

            HStack(spacing: 12) {
                TextField("Type a message...", text: $viewModel.messageText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(.systemGray6))
                    .cornerRadius(18)
                    .lineLimit(1...3)
                    .focused($isTextFieldFocused)
                    .font(.caption)
                    .onSubmit {
                        sendMessage()
                    }

                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(
                                    viewModel.messageText.trimmingCharacters(
                                        in: .whitespacesAndNewlines
                                    ).isEmpty ? Color(.systemGray4) : Color.purple)
                        )
                }
                .disabled(
                    viewModel.messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial)
        }
        .background(.regularMaterial)
    }

    private func sendMessage() {
        guard !viewModel.messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        if viewModel.saveLiveChatMessageEvent() {
            viewModel.messageText = ""
            autoScrollEnabled = true
        }
    }

    // MARK: - Keyboard Observer Setup

    private func setupKeyboardObserver() {
        let keyboardWillShow = NotificationCenter.default.publisher(
            for: UIResponder.keyboardWillShowNotification
        )
        .map { notification -> (CGFloat, Bool) in
            guard
                let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey]
                    as? CGRect
            else {
                return (0, false)
            }
            return (keyboardFrame.height, true)
        }

        let keyboardWillHide = NotificationCenter.default.publisher(
            for: UIResponder.keyboardWillHideNotification
        )
        .map { _ in (CGFloat(0), false) }

        Publishers.Merge(keyboardWillShow, keyboardWillHide)
            .receive(on: DispatchQueue.main)
            .sink { (height, visible) in
                withAnimation(.easeInOut(duration: 0.25)) {
                    self.keyboardHeight = height
                    self.isKeyboardVisible = visible
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Live Chat Subscription and Pagination

    private func subscribeToLiveChat() {
        appState.subscribeToLiveChat(for: liveActivitiesEvent)

        let coordinates = liveActivitiesEvent.replaceableEventCoordinates()?.tag.value ?? ""

        // Subscribe to incoming live chat messages.
        appState.$liveChatMessagesEvents
            .map { $0[coordinates] ?? [] }
            .receive(on: DispatchQueue.main)
            .sink { incomingMessages in
                if liveChatMessages.isEmpty {
                    // On first appearance, take the latest page and sort it.
                    let latestPage = Array(incomingMessages.suffix(pageSize))
                    liveChatMessages = latestPage.sorted { $0.createdAt < $1.createdAt }
                    hasMoreMessages = incomingMessages.count > pageSize
                } else {
                    // Try to find the index of the last visible message in the incoming batch.
                    if let lastMessage = liveChatMessages.last,
                        let lastIndex = incomingMessages.firstIndex(where: {
                            $0.id == lastMessage.id
                        }),
                        lastIndex + 1 < incomingMessages.count
                    {
                        // Get only the new messages.
                        let newMessages = Array(incomingMessages[(lastIndex + 1)...])

                        // If the new messages are already in order, simply append.
                        if let firstNew = newMessages.first,
                            lastMessage.createdAt <= firstNew.createdAt
                        {
                            liveChatMessages.append(contentsOf: newMessages)
                        } else {
                            // Otherwise, sort the new messages and merge them.
                            let sortedNewMessages = newMessages.sorted {
                                $0.createdAt < $1.createdAt
                            }
                            liveChatMessages = mergeSortedMessages(
                                liveChatMessages, sortedNewMessages)
                        }
                    }
                }

                // Accumulate pubkeys.
                incomingMessages.forEach { message in
                    pubkeysToPullMetadata.insert(message.pubkey)
                }

                // Debounce the metadata pull to avoid calling it too frequently.
                scheduleMetadataPull()
            }
            .store(in: &cancellables)
    }

    private func scheduleMetadataPull() {
        // Cancel any previous scheduled call.
        metadataPullCancellable?.cancel()
        // Schedule a new call after 0.5 seconds of inactivity.
        metadataPullCancellable = Just(())
            .delay(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { _ in
                let pubkeysArray = Array(self.pubkeysToPullMetadata)
                self.appState.pullMissingEventsFromPubkeysAndFollows(pubkeysArray)
                // Optionally clear the set if you no longer need the pubkeys.
                self.pubkeysToPullMetadata.removeAll()
            }
    }

    private func loadMoreMessages() {
        guard let coordinates = liveActivitiesEvent.replaceableEventCoordinates()?.tag.value,
            let allMessages = appState.liveChatMessagesEvents[coordinates],
            let currentFirstMessage = liveChatMessages.first,
            let currentFirstIndex = allMessages.firstIndex(of: currentFirstMessage)
        else {
            return
        }

        isLoadingPage = true
        isPaginating = true  // Mark that we are paginating so auto-scroll won't trigger.

        // Determine how many messages precede the current first (oldest) message.
        let remainingMessagesCount = currentFirstIndex  // because allMessages is sorted oldest → newest
        if remainingMessagesCount > 0 {
            let start = max(0, remainingMessagesCount - pageSize)
            let olderPage = allMessages[start..<remainingMessagesCount]
            // Prepend the older messages.
            liveChatMessages.insert(contentsOf: olderPage, at: 0)
            hasMoreMessages = (start > 0)
        } else {
            hasMoreMessages = false
        }
        isLoadingPage = false

        // Reset the paginating flag on the next runloop cycle.
        DispatchQueue.main.async {
            self.isPaginating = false
        }
    }

    /// A helper function to merge two sorted arrays.
    func mergeSortedMessages(
        _ left: [LiveChatMessageEvent],
        _ right: [LiveChatMessageEvent]
    ) -> [LiveChatMessageEvent] {
        var merged: [LiveChatMessageEvent] = []
        merged.reserveCapacity(left.count + right.count)

        var i = 0
        var j = 0
        while i < left.count && j < right.count {
            let leftMsg = left[i]
            let rightMsg = right[j]

            // Compare based on createdAt
            if leftMsg.createdAt < rightMsg.createdAt {
                // Only add if last message in merged is not the same (by id)
                if merged.last?.id != leftMsg.id { merged.append(leftMsg) }
                i += 1
            } else if leftMsg.createdAt > rightMsg.createdAt {
                if merged.last?.id != rightMsg.id { merged.append(rightMsg) }
                j += 1
            } else {  // createdAt is equal; check IDs
                if leftMsg.id == rightMsg.id {
                    // Same message – add one instance.
                    if merged.last?.id != leftMsg.id { merged.append(leftMsg) }
                    i += 1
                    j += 1
                } else {
                    // Same timestamp but different messages – add both.
                    if merged.last?.id != leftMsg.id { merged.append(leftMsg) }
                    i += 1
                    if merged.last?.id != rightMsg.id { merged.append(rightMsg) }
                    j += 1
                }
            }
        }

        // Append remaining messages from left.
        while i < left.count {
            let msg = left[i]
            if merged.last?.id != msg.id { merged.append(msg) }
            i += 1
        }
        // Append remaining messages from right.
        while j < right.count {
            let msg = right[j]
            if merged.last?.id != msg.id { merged.append(msg) }
            j += 1
        }

        return merged
    }
}


//
//  ProfileView.swift
//  swae
//
//  Created by Suhail Saqan on 2/23/25.
//

import NostrSDK
import SwiftUI

struct ProfileView: View {
    let appState: AppState
    let pfp_size: CGFloat = 90.0
    let bannerHeight: CGFloat = 150.0

    @StateObject private var viewModel: ProfileViewModel
    @State var is_zoomed: Bool = false
    @State var show_share_sheet: Bool = false
    @State var show_qr_code: Bool = false
    @State var action_sheet_presented: Bool = false
    @State var filter_state: FilterState = .liveActivities
    @State var yOffset: CGFloat = 0
    @State private var selectedTabIndex: Int = 0
    @State private var showSettings: Bool = false

    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.presentationMode) var presentationMode

    init(appState: AppState, publicKeyHex: String? = nil) {
        self.appState = appState
        // Resolve publicKeyHex using the provided value or fallback to appState's active profile.
        let resolvedPublicKeyHex =
            publicKeyHex ?? appState.appSettings?.activeProfile?.publicKeyHex ?? ""
        _viewModel = StateObject(
            wrappedValue: ProfileViewModel(appState: appState, publicKeyHex: resolvedPublicKeyHex))
    }

    func bannerBlurViewOpacity() -> Double {
        let progress = -(yOffset + navbarHeight) / 100
        return Double(-yOffset > navbarHeight ? progress : 0)
    }

    func getProfileInfo() -> (String, String) {
        let displayName = viewModel.profileMetadata?.displayName?.truncate(maxLength: 25) ?? ""
        let userName = viewModel.profileMetadata?.name?.truncate(maxLength: 25) ?? ""
        return (displayName, "@\(userName)")
    }

    func showFollowBtnInBlurrBanner() -> Bool {
        bannerBlurViewOpacity() > 1.0
    }

    var bannerSection: some View {
        GeometryReader { proxy -> AnyView in
            let minY = proxy.frame(in: .global).minY

            DispatchQueue.main.async {
                self.yOffset = minY
            }

            return AnyView(
                VStack(spacing: 0) {
                    ZStack {
                        BannerImageView(
                            appState: appState, pubkey: viewModel.publicKeyHex,
                            profile: viewModel.profileMetadata
                        )
                        .aspectRatio(contentMode: .fill)
                        .frame(
                            width: proxy.size.width,
                            height: minY > 0 ? bannerHeight + minY : bannerHeight
                        )
                        .clipped()

                        VisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
                            .opacity(bannerBlurViewOpacity())
                    }

                    Divider().opacity(bannerBlurViewOpacity())
                }
                .frame(height: minY > 0 ? bannerHeight + minY : nil)
                .offset(y: minY > 0 ? -minY : -minY < navbarHeight ? 0 : -minY - navbarHeight)
            )
        }
        .frame(height: bannerHeight)
        .allowsHitTesting(false)
    }

    // Static banner used for pager measurement and pinned/collapsible layout
    var staticBannerSection: some View {
        ZStack(alignment: .bottom) {
            BannerImageView(
                appState: appState, pubkey: viewModel.publicKeyHex,
                profile: viewModel.profileMetadata
            )
            .aspectRatio(contentMode: .fill)
            .frame(height: bannerHeight)
            .clipped()
            Divider()
        }
        .frame(height: bannerHeight)
    }

    var navbarHeight: CGFloat {
        return 100.0 - (safeArea().top)
    }

    var settingsButton: some View {
        NavigationLink(destination: AppSettingsView(appState: appState)) {
            Image(systemName: "gearshape.fill")
                .frame(width: 33, height: 33)
                .background(Color.black.opacity(0.4))
                .clipShape(Circle())
        }
    }

    var floatingSettingsButton: some View {
        Button(action: { showSettings = true }) {
            Image(systemName: "gearshape.fill")
                .foregroundColor(.white)
                .frame(width: 33, height: 33)
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Settings"))
    }

    private var followsYouBadge: some View {
        Text("Follows you", comment: "Text to indicate that a user is following your profile.")
            .padding([.leading, .trailing], 6.0)
            .padding([.top, .bottom], 2.0)
            .foregroundColor(.gray)
            .font(.footnote)
    }

    func actionSection() -> some View {
        return Group {
            if viewModel.publicKeyHex != appState.appSettings?.activeProfile?.publicKeyHex {
                FollowButtonView(profileViewModel: viewModel)
            }
        }
    }

    func pfpOffset() -> CGFloat {
        let progress = -yOffset / navbarHeight
        let offset = (pfp_size / 4.0) * (progress < 1.0 ? progress : 1)
        return offset > 0 ? offset : 0
    }

    func pfpScale() -> CGFloat {
        let progress = -yOffset / navbarHeight
        let scale = 1.0 - (0.5 * (progress < 1.0 ? progress : 1))
        return scale < 1 ? scale : 1
    }

    func nameSection(profile: UserMetadata?) -> some View {
        return Group {
            HStack(alignment: .center) {
                ProfilePicView(
                    pubkey: viewModel.publicKeyHex, size: pfp_size,
                    profile: viewModel.profileMetadata
                )
                .padding(.top, -(pfp_size / 2.0))
                .offset(y: pfpOffset())
                .scaleEffect(pfpScale())
                .animation(.easeInOut(duration: 0.1), value: yOffset)
                .onTapGesture {
                    is_zoomed.toggle()
                }

                Spacer()

                if viewModel.followsYou {
                    followsYouBadge
                }

                actionSection()
            }
            ProfileNameView(publicKeyHex: viewModel.publicKeyHex)
        }
    }

    var aboutSection: some View {
        VStack(alignment: .leading, spacing: 8.0) {
            nameSection(profile: viewModel.profileMetadata)

            if let about = viewModel.profileMetadata?.about {
                AboutView(about: about)
            }

            HStack {
                HStack {
                    Text(
                        "\(Text("\(viewModel.profileFollowList.count.formatted())").font(.subheadline.weight(.medium))) following"
                    )
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Pages
    @ViewBuilder
    private func liveActivitiesPage() -> some View {
        LiveActivitiesView(publicKeyHex: viewModel.publicKeyHex)
            .environmentObject(appState)
            .padding(.horizontal, safeArea().left)
            .padding(.bottom, navbarHeight)
    }

    @ViewBuilder
    private func shortsPage() -> some View {
        ShortsView()
            .padding(.horizontal, safeArea().left)
    }

    var body: some View {
        ZStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    bannerSection
                        .zIndex(1)

                    aboutSection
                        .zIndex(-yOffset > navbarHeight ? 0 : 1)

                    VStack(spacing: 0) {
                        ProfileHeaderTabs(selectedIndex: $selectedTabIndex)
                        Divider()
                            .frame(height: 1)
                    }
                    .background(colorScheme == .dark ? Color.black : Color.white)
                    .zIndex(-yOffset > navbarHeight ? 0 : 1)

                    TabView(selection: $selectedTabIndex) {
                        liveActivitiesPage()
                            .tag(0)

                        shortsPage()
                            .tag(1)
                    }
                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                    .frame(height: UIScreen.main.bounds.height)
                    .animation(.easeInOut(duration: 0.3), value: selectedTabIndex)
                }
            }
            .ignoresSafeArea()
            .navigationTitle("")
            .navigationBarBackButtonHidden()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: -4.5) {
                            Text(getProfileInfo().0)  // Display name
                                .font(.headline)
                                .foregroundColor(.white)
                            Text(getProfileInfo().1)  // Username
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .opacity(bannerBlurViewOpacity())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, max(5, 15 + (yOffset / 30)))
                    }
                }
                if showFollowBtnInBlurrBanner() {
                    ToolbarItem(placement: .topBarTrailing) {
                        // reserved for follow button if needed
                    }
                }
            }
            .toolbarBackground(.hidden)
            .overlay(alignment: .topTrailing) {
                floatingSettingsButton
                    .padding(.top, safeArea().top + 8)
                    .padding(.trailing, 12)
                    .zIndex(1000)
            }
            .onAppear {
                appState.pullMissingEventsFromPubkeysAndFollows([viewModel.publicKeyHex])
                appState.subscribeToProfile(for: viewModel.publicKeyHex)
            }
            .onDisappear {
                appState.unsubscribeFromProfile(for: viewModel.publicKeyHex)
            }
            .sheet(isPresented: $showSettings) {
                NavigationView {
                    AppSettingsView(appState: appState)
                }
            }
        }
    }
}

struct VisualEffectView: UIViewRepresentable {
    var effect: UIVisualEffect?
    var darkeningOpacity: CGFloat = 0.3  // degree of darkening

    func makeUIView(context: UIViewRepresentableContext<Self>) -> UIVisualEffectView {
        let effectView = UIVisualEffectView()
        effectView.backgroundColor = UIColor.black.withAlphaComponent(darkeningOpacity)
        return effectView
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: UIViewRepresentableContext<Self>) {
        uiView.effect = effect
        uiView.backgroundColor = UIColor.black.withAlphaComponent(darkeningOpacity)
    }
}

enum FilterState: Int {
    case liveActivities = 1
    case shorts = 0

    func filter(ev: NostrEvent) -> Bool {
        switch self {
        case .liveActivities:
            return ev.kind.rawValue == EventKind.liveActivities.rawValue
        case .shorts:
            //            set to shorts kind
            return false
        }
    }
}

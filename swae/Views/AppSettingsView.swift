//
//  SettingsView.swift
//  swae
//
//  Created by Suhail Saqan on 2/19/25.
//

import NostrSDK
import SwiftData
import SwiftUI

struct AppSettingsView: View {
    // MARK: - State Variables
    @State private var viewModel: AppSettingsViewModel
    @State private var isAccountsSheetExpanded = false
    @State private var profileToSignOut: Profile?
    @State private var isShowingSignOutConfirmation = false
    @State private var isShowingAddProfileConfirmation = false

    // MARK: - Initializer
    init(appState: AppState) {
        let viewModel = AppSettingsViewModel(appState: appState)
        _viewModel = State(initialValue: viewModel)
    }
    
    // MARK: - Body
    var body: some View {
        VStack(spacing: 30) {
            profilesSection
            
            profileSettingsSection
            
            if let activeProfile = viewModel.activeProfile,
               activeProfile.publicKeyHex != nil {
                Section {
                    Button(
                        action: {
                            profileToSignOut = activeProfile
                            isShowingSignOutConfirmation = true
                        },
                        label: {
                            Label(
                                String(
                                    localized: "Sign Out of \(viewModel.activeProfileName)",
                                    comment: "Button to sign out of a profile from the device."
                                ),
                                systemImage: "door.left.hand.open"
                            )
                        }
                    )
                }
            }
        }
        .sheet(isPresented: $viewModel.isSignInViewPresented) {
            NavigationStack { SignInView() }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $viewModel.isAccountsSheetExpanded) {
            NavigationStack { profileSheet }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            Text("Add Profile", comment: "Button to add a profile."),
            isPresented: $isShowingAddProfileConfirmation
        ) {
            NavigationLink(destination: CreateProfileView(appState: viewModel.appState)) {
                Text("Create Profile", comment: "Button to create a profile.")
            }
            Button(action: { viewModel.isSignInViewPresented = true }) {
                Text("Sign Into Existing Profile", comment: "Button to sign into existing profile.")
            }
        }
        .confirmationDialog(
            Text("Sign out of profile?", comment: "Title of confirmation dialog when user initiates a profile sign out."),
            isPresented: $isShowingSignOutConfirmation
        ) {
            if let profileToSignOut, let publicKeyHex = profileToSignOut.publicKeyHex {
                Button(role: .destructive) {
                    viewModel.signOut(profileToSignOut)
                    self.profileToSignOut = nil
                } label: {
                    Text(
                        "Sign Out of \(viewModel.profileName(publicKeyHex: publicKeyHex))",
                        comment: "Button to sign out of a profile from the device."
                    )
                }
            }
            
            Button(role: .cancel) {
                profileToSignOut = nil
            } label: {
                Text("Cancel", comment: "Button to cancel out of dialog.")
            }
        } message: {
            Text(
                "Your app settings will be deleted from this device. Your data on Nostr relays will not be affected.",
                comment: "Message to inform user about what will happen if they sign out."
            )
        }
    }
    
    // MARK: - Profiles Section
    var profilesSection: some View {
        Button(role: .destructive) {
            viewModel.isAccountsSheetExpanded = true
        } label: {
            HStack {
                let publicKeyHex = viewModel.publicKeyHex
                if let publicKeyHex,
                   PublicKey(hex: publicKeyHex) != nil {
                    if viewModel.isActiveProfileSignedInWithPrivateKey {
                        ProfilePicView(pubkey: publicKeyHex, size: 20, profile: viewModel.activeProfileMetadata)
                    } else {
                        ImageOverlayView(imageSystemName: "lock.fill", overlayBackgroundColor: .purple) {
                            ProfilePicView(pubkey: publicKeyHex, size: 20, profile: viewModel.activeProfileMetadata)
                        }
                    }
                } else {
                    ImageOverlayView(imageSystemName: "lock.fill", overlayBackgroundColor: .purple) {
                        GuestProfilePictureView()
                    }
                }
                ProfileNameView(publicKeyHex: publicKeyHex)
                    .foregroundStyle(.purple)
            }
        }
    }
    
    // MARK: - Profile Sheet
    var profileSheet: some View {
        VStack {
            ForEach(viewModel.profiles, id: \.self) { profile in
                HStack {
                    if viewModel.isSignedInWithPrivateKey(profile) {
                        ProfilePicView(pubkey: profile.publicKeyHex ?? "", size: 20, profile: viewModel.appState.metadataEvents[profile.publicKeyHex ?? ""]?.userMetadata)
                    } else {
                        ImageOverlayView(imageSystemName: "lock.fill", overlayBackgroundColor: .purple) {
                            ProfilePicView(pubkey: profile.publicKeyHex ?? "", size: 20, profile: viewModel.appState.metadataEvents[profile.publicKeyHex ?? ""]?.userMetadata)
                        }
                    }
                    
                    if viewModel.isActiveProfile(profile) {
                        ProfileNameView(publicKeyHex: profile.publicKeyHex)
                            .foregroundStyle(.purple)
                    } else {
                        ProfileNameView(publicKeyHex: profile.publicKeyHex)
                    }
                }
                .tag(profile.publicKeyHex)
                .onTapGesture {
                    viewModel.appState.updateActiveProfile(profile)
                    viewModel.isAccountsSheetExpanded = false
                }
                .swipeActions {
                    if profile.publicKeyHex != nil {
                        Button(role: .destructive) {
                            profileToSignOut = profile
                            isShowingSignOutConfirmation = true
                        } label: {
                            Label(
                                String(localized: "Sign Out", comment: "Label indicating that the button signs out of a profile."),
                                systemImage: "door.left.hand.open"
                            )
                        }
                    }
                }
            }
            
            Button(action: { isShowingAddProfileConfirmation = true }) {
                HStack {
                    Image(systemName: "plus.circle")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40)
                    Text("Add Profile", comment: "Button to add a profile.")
                }
            }
        }
    }
    
    // MARK: - Profile Settings Section
    var profileSettingsSection: some View {
        Section(
            content: {
                let publicKeyHex = viewModel.publicKeyHex
                 if let publicKeyHex, let publicKey = PublicKey(hex: publicKeyHex) {
                     NavigationLink(destination: KeysSettingsView(publicKey: publicKey)) {
                         Label(
                             String(localized: "Keys", comment: "Settings section for Nostr key management."),
                             systemImage: "key"
                         )
                     }
                 }
                 NavigationLink(destination: RelaysSettingsView()) {
                     Label(
                         String(localized: "Relays", comment: "Settings section for relay management."),
                         systemImage: "server.rack"
                     )
                 }
            }
        )
    }
}

extension AppSettingsView {
    @Observable class AppSettingsViewModel {
        let appState: AppState
        var isAccountsSheetExpanded: Bool = false
        var isSignInViewPresented: Bool = false

        init(appState: AppState) {
            self.appState = appState
        }

        var publicKeyHex: String? {
            appState.appSettings?.activeProfile?.publicKeyHex
        }

        var activeProfile: Profile? {
            appState.appSettings?.activeProfile
        }

        var activeProfileName: String {
            profileName(publicKeyHex: publicKeyHex)
        }

        var profiles: [Profile] {
            appState.profiles
        }
        
        var activeProfileMetadata: UserMetadata? {
            guard let activeProfilePublicKeyHex = appState.appSettings?.activeProfile?.publicKeyHex else {
                return nil
            }
            return appState.metadataEvents[activeProfilePublicKeyHex]?.userMetadata
        }

        func profileName(publicKeyHex: String?) -> String {
            Utilities.shared.profileName(
                publicKeyHex: publicKeyHex,
                appState: appState
            )
        }

        var isActiveProfileSignedInWithPrivateKey: Bool {
            guard let activeProfile = appState.appSettings?.activeProfile else {
                return false
            }
            return isSignedInWithPrivateKey(activeProfile)
        }

        func isSignedInWithPrivateKey(_ profile: Profile) -> Bool {
            guard let publicKeyHex = profile.publicKeyHex, let publicKey = PublicKey(hex: publicKeyHex) else {
                return false
            }
            return PrivateKeySecureStorage.shared.keypair(for: publicKey) != nil
        }

        func signOut(_ profile: Profile) {
            appState.deleteProfile(profile)
            if profiles.count == 1, let activeProfile = activeProfile, activeProfile.publicKeyHex == nil {
                UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
            }
        }

        func isActiveProfile(_ profile: Profile) -> Bool {
            return appState.appSettings?.activeProfile == profile
        }
    }
}

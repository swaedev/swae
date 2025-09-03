import SwiftUI

struct AboutSettingsView: View {
    var body: some View {
        Form {
            Section {
                TextItemView(name: String(localized: "Version"), value: appVersion())
                NavigationLink {
                    AboutVersionHistorySettingsView()
                } label: {
                    Text("Version history")
                }
                NavigationLink {
                    AboutLicensesSettingsView()
                } label: {
                    Text("Licenses")
                }
                NavigationLink {
                    AboutAttributionsSettingsView()
                } label: {
                    Text("Attributions")
                }
            }
            Section {
                Button {
                    openUrl(url: "https://eerimoq.github.io/swae/privacy-policy/en.html")
                } label: {
                    Text("Privacy policy")
                }
                Button {
                    openUrl(
                        url: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
                } label: {
                    Text("End-user license agreement (EULA)")
                }
            }
        }
        .navigationTitle("About")
    }
}

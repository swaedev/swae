import SwiftUI

struct StreamWizardAfreecaTvSettingsView: View {
    @EnvironmentObject private var model: Model
    @ObservedObject var createStreamWizard: CreateStreamWizard

    var body: some View {
        Form {
            Section {
                TextField("MyChannel", text: $createStreamWizard.afreecaTvChannelName)
                    .disableAutocorrection(true)
            } header: {
                Text("Channel name")
            }
            Section {
                TextField("908123903", text: $createStreamWizard.afreecaTvStreamId)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
            } header: {
                Text("Video id")
            }
            Section {
                NavigationLink {
                    StreamWizardNetworkSetupSettingsView(
                        createStreamWizard: createStreamWizard,
                        platform: String(localized: "AfreecaTV")
                    )
                } label: {
                    WizardNextButtonView()
                }
            }
        }
        .onAppear {
            createStreamWizard.platform = .afreecaTv
            createStreamWizard.name = makeUniqueName(name: String(localized: "AfreecaTV"),
                                                     existingNames: model.database.streams)
            createStreamWizard.directIngest = ""
        }
        .navigationTitle("AfreecaTV")
        .toolbar {
            CreateStreamWizardToolbar(createStreamWizard: createStreamWizard)
        }
    }
}

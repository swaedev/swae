import SwiftUI

struct WidgetMapSettingsView: View {
    @EnvironmentObject var model: Model
    let widget: SettingsWidget
    @State var delay: Double

    var body: some View {
        Section {
            HStack {
                Text("Location Permission")
                Spacer()
                if model.locationManager.isAuthorized() {
                    Text("Granted")
                        .foregroundColor(.green)
                } else {
                    Button("Request") {
                        model.locationManager.requestPermissionIfNeeded()
                    }
                    .foregroundColor(.blue)
                }
            }
        } footer: {
            Text(
                "Location permission is required for the map widget to work. If denied, enable it in iOS Settings → Privacy & Security → Location Services."
            )
        }
        Section {
            Toggle(
                isOn: Binding(
                    get: {
                        widget.map.northUp!
                    },
                    set: { value in
                        widget.map.northUp = value
                        model.resetSelectedScene(changeScene: false)
                    })
            ) {
                Text("North up")
            }
        } footer: {
            Text("The map will rotate based of movement direction if disabled.")
        }
        Section {
            NavigationLink {
                LocationSettingsView(
                    database: model.database,
                    location: model.database.location,
                    stream: $model.stream)
            } label: {
                Label("Location", systemImage: "location")
            }
        } header: {
            Text("Shortcut")
        }
        Section {
            HStack {
                Slider(
                    value: $delay,
                    in: 0...10,
                    step: 0.5,
                    onEditingChanged: { begin in
                        guard !begin else {
                            return
                        }
                        widget.map.delay = delay
                        model.resetSelectedScene(changeScene: false)
                    }
                )
                Text(String(String(delay)))
                    .frame(width: 35)
            }
        } header: {
            Text("Delay")
        } footer: {
            Text("To show the widget in sync with high latency cameras.")
        }
        WidgetEffectsView(widget: widget)
    }
}

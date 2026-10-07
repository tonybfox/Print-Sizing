import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Units") { UnitPicker(unit: $model.settings.unit) }
                    LabeledContent {
                        Picker("Print quality", selection: $model.settings.dpi) {
                            Text("Standard").tag(200)
                            Text("High").tag(300)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 180)
                    } label: {
                        Labelled(title: "Print quality", hint: "High is sharper; Standard is quicker")
                    }
                }
                Section("Printing tips") {
                    Tip(text: "**Print** opens the iPhone print screen with the right paper already chosen. Load that paper in the printer.")
                    Tip(text: "Pages print at actual size, so exact sizes come out exact.")
                    Tip(text: "Turn on **Photo paper** for glossy or matte photo paper, so the printer uses its photo settings.")
                    Tip(text: "Set the page margin to 0 to print borderless, if your printer supports it.")
                    Tip(text: "**Share PDF** saves the pages to Files or sends them to a printer's own app.")
                }
                Section("Tips") {
                    Tip(text: "Tap any photo in the preview to choose which part is kept when cropping.")
                    Tip(text: "Turn on cut guides to make cutting out easier.")
                    Tip(text: "Your photos never leave your phone: everything is done on the device.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct Tip: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text).font(.subheadline)
    }
}

import CodexUsageCore
import SwiftUI

struct PreferencesView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Toggle(model.strings.alwaysOnTop, isOn: $model.isAlwaysOnTop)

            Picker(model.strings.refreshInterval, selection: $model.refreshInterval) {
                ForEach(RefreshInterval.allCases, id: \.self) { interval in
                    Text(model.strings.intervalLabel(interval)).tag(interval)
                }
            }

            Picker(model.strings.speedMode, selection: $model.speedMode) {
                Text("Auto").tag(SpeedMode.auto)
                Text("Standard").tag(SpeedMode.standard)
                Text("Fast").tag(SpeedMode.fast)
            }

            TextField(model.strings.codexPath, text: $model.pathOverride)

            Button(model.strings.refresh) {
                model.refresh()
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

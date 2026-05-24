import CodexUsageCore
import SwiftUI

struct PreferencesView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Picker(model.strings.refreshInterval, selection: $model.refreshInterval) {
                ForEach(RefreshInterval.allCases, id: \.self) { interval in
                    Text(model.strings.intervalLabel(interval)).tag(interval)
                }
            }

            Picker(model.strings.speedMode, selection: $model.speedMode) {
                Text(model.strings.auto).tag(SpeedMode.auto)
                Text(model.strings.standard).tag(SpeedMode.standard)
                Text(model.strings.fast).tag(SpeedMode.fast)
            }

            LabeledContent(model.strings.panelOpacity) {
                HStack(spacing: 10) {
                    Slider(value: $model.panelOpacity, in: 0.55...1, step: 0.05)
                    Text(model.panelOpacity, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 42, alignment: .trailing)
                }
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

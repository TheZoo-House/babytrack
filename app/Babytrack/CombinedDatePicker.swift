import SwiftUI

/// Use UIKit's dateAndTime mode so date and time belong to one wheel control.
struct CombinedDatePicker: UIViewRepresentable {
    @Binding var date: Date
    var dateOnly = false
    var minimumDate: Date?
    func makeUIView(context: Context) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.preferredDatePickerStyle = .wheels
        picker.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        picker.accessibilityIdentifier = "combinedDateTimePicker"
        return picker
    }

    func updateUIView(_ picker: UIDatePicker, context: Context) {
        context.coordinator.parent = self
        picker.datePickerMode = dateOnly ? .date : .dateAndTime
        picker.minimumDate = minimumDate
        picker.overrideUserInterfaceStyle = context.environment.colorScheme == .dark ? .dark : .light
        if picker.date != date {
            picker.setDate(date, animated: false)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor final class Coordinator: NSObject {
        var parent: CombinedDatePicker
        init(parent: CombinedDatePicker) {
            self.parent = parent
        }

        @objc func changed(_ picker: UIDatePicker) {
            parent.date = picker.date
        }
    }
}

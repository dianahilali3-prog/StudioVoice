import SwiftUI
import UIKit

/// High-performance text editor for very long scripts (UITextView based:
/// smooth with 100 000+ characters, natural RTL for Arabic paragraphs).
struct ScriptEditor: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var insertRequest: InsertRequest?

    /// Asks the editor to insert a snippet at the cursor (expression tags…).
    struct InsertRequest: Equatable {
        let id = UUID()
        let snippet: String
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.font = UIFont.preferredFont(forTextStyle: .body).withSize(18)
        view.adjustsFontForContentSizeCategory = true
        view.textColor = UIColor(Theme.ink)
        view.tintColor = UIColor(Theme.roseDeep)
        view.textAlignment = .natural
        view.autocorrectionType = .default
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.keyboardDismissMode = .interactive
        view.alwaysBounceVertical = true
        view.textContainerInset = UIEdgeInsets(top: 14, left: 10, bottom: 14, right: 10)
        view.layoutManager.allowsNonContiguousLayout = true
        view.text = text

        let label = UILabel()
        label.text = placeholder
        label.numberOfLines = 0
        label.font = view.font
        label.textColor = UIColor(Theme.silver)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isUserInteractionEnabled = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            label.leadingAnchor.constraint(equalTo: view.frameLayoutGuide.leadingAnchor, constant: 15),
            label.trailingAnchor.constraint(equalTo: view.frameLayoutGuide.trailingAnchor, constant: -15)
        ])
        context.coordinator.placeholder = label
        label.isHidden = !text.isEmpty

        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        toolbar.items = [
            UIBarButtonItem(systemItem: .flexibleSpace),
            UIBarButtonItem(title: "Terminé", style: .done, target: view, action: #selector(UIResponder.resignFirstResponder))
        ]
        toolbar.tintColor = UIColor(Theme.roseDeep)
        view.inputAccessoryView = toolbar
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        if view.text != text {
            let selected = view.selectedRange
            view.text = text
            let location = min(selected.location, (text as NSString).length)
            view.selectedRange = NSRange(location: location, length: 0)
        }
        context.coordinator.placeholder?.isHidden = !text.isEmpty
        if let request = insertRequest, request != context.coordinator.lastInsert {
            context.coordinator.lastInsert = request
            view.insertText(request.snippet)
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ScriptEditor
        weak var placeholder: UILabel?
        var lastInsert: InsertRequest?

        init(_ parent: ScriptEditor) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            placeholder?.isHidden = !textView.text.isEmpty
            parent.text = textView.text
        }
    }
}

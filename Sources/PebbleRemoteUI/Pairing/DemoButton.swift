import PebbleDesign
import SwiftUI

/// "Try the demo" at the bottom of the pairing screen, with what the demo is.
struct DemoButton: View {
    let action: () -> Void

    var body: some View {
        VStack {
            Button(AppCopy.Pairing.tryDemo, systemImage: PebbleSymbol.demo, action: action)
                .buttonStyle(.pebbleGlass)
            Text(AppCopy.Pairing.tryDemoHint)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// An account kept, as a card in Settings › Accounts: the selection mark,
// its kind's letter, the server's name, the kind and the user, the address.
// The photographer, 21 November 2026: "kun je op alle versies een
// toegevoegde server als een soort card tonen die werken als een soort
// radiobutton (er moet altijd 1 server actief zijn)". Linux's twin is
// Preferences.swift's accountRow, in the same order and words
// (docs/design/settings.md, SYSTEM.md's "Account cards").
//
// The selection mark is the card's one swappable part (`indicator`): today
// a radio, as one account is signed in at a time. Should several servers
// play side by side one day ("waarom we die beperking moeten hebben", the
// photographer, 21 November 2026), it becomes a toggle that keeps at least
// one on, and the card itself stays as it is.

import JukeboxKit
import SwiftUI
#if os(macOS)
import AppKit
#endif

struct AccountCard<Indicator: View>: View {
    let account: ServerCredentials
    let isActive: Bool
    let choose: () -> Void
    @ViewBuilder var indicator: Indicator

    var body: some View {
        Button(action: choose) {
            HStack(alignment: .center, spacing: Theme.Space.m) {
                indicator
                KindMark(kind: account.kind, isActive: isActive)
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    // The name in the serif, as a sleeve's title (tells 3).
                    Text(verbatim: ServerWords.name(of: account))
                        .font(.serif(.body))
                        .foregroundStyle(.primary)
                    Text(verbatim: "\(ServerWords.product(account.kind, version: account.serverVersion)) · \(account.userName)")
                        .desktopFont(Tokens.Size.fact13.size, phone: .footnote)
                        .foregroundStyle(.secondary)
                    Text(verbatim: account.serverURL.absoluteString)
                        .desktopFont(Tokens.Size.fact13.size, phone: .footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, Theme.Space.xs)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

/// The kind's letter in a round label, in one ink: the accent on the card
/// signed in, grey on the others.
private struct KindMark: View {
    let kind: ServerKind
    let isActive: Bool

    var body: some View {
        let ink = isActive ? Theme.accent : Color.secondary
        Text(verbatim: ServerWords.mark(kind))
            .font(.serif(.body))
            .foregroundStyle(ink)
            .frame(width: 32, height: 32)
            .background(Circle().fill(ink.opacity(0.12)))
            .accessibilityHidden(true)
    }
}

/// The radio of a card. On the Mac the system's own radio button, as its
/// settings windows choose one of several; on the iPhone and the iPad,
/// which have no radio, the circle Apple's lists check a choice with, in
/// Jukebox's accent.
struct AccountRadio: View {
    let isOn: Bool

    var body: some View {
        #if os(macOS)
        MacRadio(isOn: isOn)
            .fixedSize()
            .allowsHitTesting(false)
            .accessibilityLabel(isOn ? Text("Signed In") : Text("Switch to This Account"))
        #else
        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(isOn ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.tertiary))
            .accessibilityLabel(isOn ? Text("Signed In") : Text("Switch to This Account"))
        #endif
    }
}

#if os(macOS)
/// NSButton's radio, untitled: the card's words are its title. Drawn only;
/// the click is the card's, so one click is one switch, and its state is
/// always the account signed in: a switch that does not happen leaves it
/// off.
private struct MacRadio: NSViewRepresentable {
    let isOn: Bool

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(radioButtonWithTitle: "", target: nil, action: nil)
        button.setAccessibilityElement(false)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        button.state = isOn ? .on : .off
    }
}
#endif

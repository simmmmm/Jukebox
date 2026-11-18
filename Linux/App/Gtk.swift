// GTK from Swift, as little as the screens need: GTK is C, so a widget is a
// pointer and a signal a C function. Here that is made to read like the
// rest of the app — `on(button, "clicked") { … }`, `observe(widget) { … }`
// for anything @Observable — and nothing more: no wrapper classes, no
// binding library (the ones there are for Swift are young; C's GTK is not).
//
// Everything here is the main thread's: GTK calls back on it, and the main
// actor is that thread (main.swift drains its queue from GLib's loop).

import CAdw
import CGlue
import Foundation
import Observation

typealias Widget = UnsafeMutablePointer<GtkWidget>
typealias NavPage = UnsafeMutablePointer<AdwNavigationPage>

// MARK: Pointers
// GTK's types are C structs, some with a body (GtkWidget, GtkBox: a typed
// pointer in Swift) and most without (GtkLabel, everything of libadwaita: an
// OpaquePointer). `ptr` turns one into what the call wants.

func ptr<T, U>(_ pointer: UnsafeMutablePointer<T>) -> UnsafeMutablePointer<U> {
    UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: U.self)
}

func ptr<T>(_ pointer: UnsafeMutablePointer<T>) -> OpaquePointer { OpaquePointer(pointer) }

func ptr<U>(_ pointer: OpaquePointer) -> UnsafeMutablePointer<U> { UnsafeMutablePointer<U>(pointer) }

func ptr(_ pointer: OpaquePointer) -> OpaquePointer { pointer }
func ptr<U>(_ pointer: UnsafeMutableRawPointer) -> UnsafeMutablePointer<U> { pointer.assumingMemoryBound(to: U.self) }
func ptr(_ pointer: UnsafeMutableRawPointer) -> OpaquePointer { OpaquePointer(pointer) }

func raw<T>(_ pointer: UnsafeMutablePointer<T>) -> UnsafeMutableRawPointer { UnsafeMutableRawPointer(pointer) }
func raw(_ pointer: OpaquePointer) -> UnsafeMutableRawPointer { UnsafeMutableRawPointer(pointer) }

// MARK: Signals

/// A Swift closure as a signal's data, released when the signal goes.
private nonisolated final class Handler {
    let run: @MainActor (UnsafeMutableRawPointer?) -> Void
    init(_ run: @escaping @MainActor (UnsafeMutableRawPointer?) -> Void) { self.run = run }
}

// Connected "swapped": the data comes first, then the signal's own
// arguments, of which C lets a function take fewer than are passed.
private let callNoArgument: @convention(c) (UnsafeMutableRawPointer?) -> Void = { data in
    guard let data else { return }
    let handler = Unmanaged<Handler>.fromOpaque(data).takeUnretainedValue()
    MainActor.assumeIsolated { handler.run(nil) }
}

private let callOneArgument: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void = { data, argument in
    guard let data else { return }
    let handler = Unmanaged<Handler>.fromOpaque(data).takeUnretainedValue()
    MainActor.assumeIsolated { handler.run(argument) }
}

private let releaseHandler: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<GClosure>?) -> Void = { data, _ in
    guard let data else { return }
    Unmanaged<Handler>.fromOpaque(data).release()
}

/// `body` whenever `object` emits `signal`.
@discardableResult
func on(_ object: UnsafeMutableRawPointer, _ signal: String, _ body: @escaping @MainActor () -> Void) -> UInt {
    let handler = Unmanaged.passRetained(Handler { _ in body() }).toOpaque()
    return UInt(g_signal_connect_data(object, signal, unsafeBitCast(callNoArgument, to: GCallback.self),
                                      handler, releaseHandler, G_CONNECT_SWAPPED))
}

@discardableResult
func on(_ object: OpaquePointer, _ signal: String, _ body: @escaping @MainActor () -> Void) -> UInt {
    on(raw(object), signal, body)
}

/// The same for a signal with one argument that is a pointer or a number
/// (a list's row, a position), given as the raw word it was passed in.
@discardableResult
func on(_ object: UnsafeMutableRawPointer, _ signal: String,
        argument body: @escaping @MainActor (UnsafeMutableRawPointer?) -> Void) -> UInt {
    let handler = Unmanaged.passRetained(Handler(body)).toOpaque()
    return UInt(g_signal_connect_data(object, signal, unsafeBitCast(callOneArgument, to: GCallback.self),
                                      handler, releaseHandler, G_CONNECT_SWAPPED))
}

/// A `guint` argument out of the word it came in.
func number(_ argument: UnsafeMutableRawPointer?) -> Int {
    Int(UInt32(truncatingIfNeeded: UInt(bitPattern: argument)))
}

// MARK: Swift objects kept by a widget

private let releaseObject: @convention(c) (UnsafeMutableRawPointer?) -> Void = { data in
    guard let data else { return }
    Unmanaged<AnyObject>.fromOpaque(data).release()
}

/// `object` lives as long as `owner` does (a row's labels, a page's state).
func keep(_ object: AnyObject, on owner: UnsafeMutableRawPointer, as key: String = "jukebox") {
    g_object_set_data_full(ptr(owner.assumingMemoryBound(to: GObject.self)), key,
                           Unmanaged.passRetained(object).toOpaque(), releaseObject)
}

func kept<T: AnyObject>(on owner: UnsafeMutableRawPointer, as key: String = "jukebox") -> T? {
    guard let data = g_object_get_data(ptr(owner.assumingMemoryBound(to: GObject.self)), key) else { return nil }
    return Unmanaged<AnyObject>.fromOpaque(data).takeUnretainedValue() as? T
}

// MARK: Observation

/// What `observe` keeps on its widget: it stops when the widget goes.
private final class Observer {
    var apply: (() -> Void)?

    func run() {
        guard let apply else { return }
        withObservationTracking(apply) { [weak self] in
            // Told before the value changes, on whatever thread changes it:
            // read again a moment later, on the main actor.
            Task { @MainActor in self?.run() }
        }
    }

    deinit { apply = nil }
}

private var observerCount = 0

/// `apply` now, and again whenever anything @Observable it read has
/// changed, for as long as `owner` lives: what SwiftUI does for a view's
/// body, by hand. `apply` sets the widgets from the stores.
func observe(_ owner: Widget, _ apply: @escaping () -> Void) {
    let observer = Observer()
    observer.apply = apply
    observerCount += 1
    keep(observer, on: raw(owner), as: "jukebox-observer-\(observerCount)")
    observer.run()
}

// MARK: Widgets, briefly

extension UnsafeMutablePointer where Pointee == GtkWidget {
    @discardableResult
    func css(_ classes: String...) -> Widget {
        for name in classes { gtk_widget_add_css_class(self, name) }
        return self
    }

    @discardableResult
    func margins(_ all: Int32) -> Widget { margins(horizontal: all, vertical: all) }

    @discardableResult
    func margins(horizontal: Int32 = 0, vertical: Int32 = 0) -> Widget {
        gtk_widget_set_margin_start(self, horizontal)
        gtk_widget_set_margin_end(self, horizontal)
        gtk_widget_set_margin_top(self, vertical)
        gtk_widget_set_margin_bottom(self, vertical)
        return self
    }

    @discardableResult
    func expand(horizontal: Bool = false, vertical: Bool = false) -> Widget {
        if horizontal { gtk_widget_set_hexpand(self, 1) }
        if vertical { gtk_widget_set_vexpand(self, 1) }
        return self
    }

    @discardableResult
    func align(horizontal: GtkAlign? = nil, vertical: GtkAlign? = nil) -> Widget {
        if let horizontal { gtk_widget_set_halign(self, horizontal) }
        if let vertical { gtk_widget_set_valign(self, vertical) }
        return self
    }

    @discardableResult
    func size(width: Int32 = -1, height: Int32 = -1) -> Widget {
        gtk_widget_set_size_request(self, width, height)
        return self
    }

    @discardableResult
    func tooltip(_ text: String) -> Widget {
        gtk_widget_set_tooltip_text(self, text)
        return self
    }

    var isVisible: Bool {
        get { gtk_widget_get_visible(self) != 0 }
        nonmutating set { if isVisible != newValue { gtk_widget_set_visible(self, newValue ? 1 : 0) } }
    }

    var isSensitive: Bool {
        get { gtk_widget_get_sensitive(self) != 0 }
        nonmutating set { gtk_widget_set_sensitive(self, newValue ? 1 : 0) }
    }
}

func box(_ orientation: GtkOrientation, spacing: Int32 = 0, _ children: [Widget] = []) -> Widget {
    let box = gtk_box_new(orientation, spacing)!
    for child in children { gtk_box_append(ptr(box), child) }
    return box
}

func vbox(spacing: Int32 = 0, _ children: [Widget] = []) -> Widget { box(GTK_ORIENTATION_VERTICAL, spacing: spacing, children) }
func hbox(spacing: Int32 = 0, _ children: [Widget] = []) -> Widget { box(GTK_ORIENTATION_HORIZONTAL, spacing: spacing, children) }

func append(_ child: Widget, to box: Widget) { gtk_box_append(ptr(box), child) }

/// Every child out of a box, before it is filled again.
func clear(_ box: Widget) {
    while let child = gtk_widget_get_first_child(box) { gtk_box_remove(ptr(box), child) }
}

/// A label that starts at the margin and ends in "…" rather than widening
/// its window (tells.md 8: left-aligned).
func label(_ text: String = "", _ classes: String..., lines: Int32 = 1, selectable: Bool = false) -> Widget {
    let label = gtk_label_new(text)!
    gtk_label_set_xalign(ptr(label), 0)
    if lines == 1 {
        gtk_label_set_ellipsize(ptr(label), PANGO_ELLIPSIZE_END)
    } else {
        gtk_label_set_wrap(ptr(label), 1)
        gtk_label_set_wrap_mode(ptr(label), PANGO_WRAP_WORD_CHAR)
        if lines > 1 {
            gtk_label_set_lines(ptr(label), lines)
            gtk_label_set_ellipsize(ptr(label), PANGO_ELLIPSIZE_END)
        }
    }
    if selectable { gtk_label_set_selectable(ptr(label), 1) }
    for name in classes { gtk_widget_add_css_class(label, name) }
    return label
}

func setText(_ label: Widget, _ text: String) {
    // Setting the same words again still lays the label out again.
    if String(cString: gtk_label_get_text(ptr(label))) != text { gtk_label_set_text(ptr(label), text) }
}

/// A button of words.
func button(_ title: String, _ classes: String..., action: @escaping @MainActor () -> Void) -> Widget {
    let button = gtk_button_new_with_label(title)!
    for name in classes { gtk_widget_add_css_class(button, name) }
    on(button, "clicked", action)
    return button
}

/// A button of one of Adwaita's symbols, named for the screen reader and
/// the pointer.
func iconButton(_ icon: String, _ name: String, _ classes: String..., action: @escaping @MainActor () -> Void) -> Widget {
    let button = gtk_button_new_from_icon_name(icon)!
    gtk_widget_set_tooltip_text(button, name)
    for name in classes { gtk_widget_add_css_class(button, name) }
    on(button, "clicked", action)
    return button
}

func setIcon(_ button: Widget, _ icon: String) {
    gtk_button_set_icon_name(ptr(button), icon)
}

func scrolled(_ child: Widget, horizontal: Bool = false) -> Widget {
    let scroller = gtk_scrolled_window_new()!
    gtk_scrolled_window_set_child(ptr(scroller), child)
    gtk_scrolled_window_set_policy(ptr(scroller),
                                   horizontal ? GTK_POLICY_AUTOMATIC : GTK_POLICY_NEVER,
                                   horizontal ? GTK_POLICY_NEVER : GTK_POLICY_AUTOMATIC)
    return scroller
}

/// Down to the 4-point grid every measure is on (Style.swift).
func grid(_ points: Int32) -> Int32 { max(4, points / 4 * 4) }

func hairline() -> Widget { gtk_separator_new(GTK_ORIENTATION_HORIZONTAL)! }

/// "3:07", "1:02:45".
func clock(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, seconds > 0 else { return "0:00" }
    let total = Int(seconds.rounded())
    let h = total / 3600, m = (total % 3600) / 60, s = total % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}

/// "12 songs, 48 minutes": a fact for under a title.
func length(songs: Int, seconds: TimeInterval) -> String {
    let count = songs == 1 ? "1 song" : "\(songs) songs"
    let minutes = Int((seconds / 60).rounded())
    guard minutes > 0 else { return count }
    if minutes < 60 { return "\(count), \(minutes) min" }
    return "\(count), \(minutes / 60) hr \(minutes % 60) min"
}

// MARK: Lists
// GtkListView and GtkGridView make only the rows on screen, so Songs is as
// quick with 20 000 songs as with 20 (a GtkListBox makes them all).

/// A list (or a grid) of `Item`s. `make` builds an empty row and what fills
/// it; `fill` puts one item in a row, again each time a row is reused.
final class ItemList<Item, Row: AnyObject> {
    let widget: Widget
    private(set) var items: [Item] = []
    private let strings: OpaquePointer
    private let fill: (Row, Item, Int) -> Void
    /// Whether an item's row can be played (a heading in the list cannot).
    var activatable: ((Item) -> Bool)?

    /// `singleClick`: a click plays, as a page's songs do; false, a
    /// double-click or Enter does (Up next, where a click would skip away
    /// from what plays).
    init(grid: Bool = false, singleClick: Bool = true, make: @escaping () -> (Widget, Row),
         fill: @escaping (Row, Item, Int) -> Void, activate: @escaping (Item, Int, [Item]) -> Void) {
        self.fill = fill
        // The model is only the rows' numbers; the items stay Swift's.
        strings = gtk_string_list_new(nil)
        let selection = gtk_no_selection_new(strings)
        let factory = gtk_signal_list_item_factory_new()!
        widget = grid ? gtk_grid_view_new(selection, factory) : gtk_list_view_new(selection, factory)
        if grid {
            gtk_grid_view_set_single_click_activate(ptr(widget), 1)
            gtk_grid_view_set_max_columns(ptr(widget), 12)
        } else {
            gtk_list_view_set_single_click_activate(ptr(widget), singleClick ? 1 : 0)
        }
        on(raw(factory), "setup", argument: { item in
            guard let item else { return }
            let (child, row) = make()
            keep(row, on: raw(child))
            gtk_list_item_set_child(OpaquePointer(item), child)
        })
        on(raw(factory), "bind", argument: { [unowned self] item in
            guard let item, let child = gtk_list_item_get_child(OpaquePointer(item)),
                  let row: Row = kept(on: raw(child)) else { return }
            let position = Int(gtk_list_item_get_position(OpaquePointer(item)))
            guard self.items.indices.contains(position) else { return }
            if let activatable = self.activatable {
                gtk_list_item_set_activatable(OpaquePointer(item), activatable(self.items[position]) ? 1 : 0)
            }
            self.fill(row, self.items[position], position)
        })
        on(raw(widget), "activate", argument: { [unowned self] position in
            let position = number(position)
            guard self.items.indices.contains(position) else { return }
            activate(self.items[position], position, self.items)
        })
        // The list lives as long as its widget.
        keep(self, on: raw(widget), as: "jukebox-list")
    }

    /// Told when the items change, before the rows show them (a list's
    /// picked songs are by place, so they go: TrackPicks).
    var willSet: (() -> Void)?

    func set(_ items: [Item]) {
        willSet?()
        let old = self.items.count
        self.items = items
        var names: [UnsafePointer<CChar>?] = items.indices.map { UnsafePointer(strdup(String($0))) }
        names.append(nil)
        gtk_string_list_splice(strings, 0, guint(old), names)
        for name in names { free(UnsafeMutablePointer(mutating: name)) }
    }
}

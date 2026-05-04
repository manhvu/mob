// MobViewModel.swift — Shared state store between BEAM NIFs and SwiftUI.
// NIFs call setRoot() from any thread; the @Published triggers SwiftUI re-render on main.

import Combine
import SwiftUI

@objc public class MobViewModel: NSObject, ObservableObject {
    @objc public static let shared = MobViewModel()

    @Published public var root: MobNode? = nil
    /// Increments on every setRoot call; views use onChange(of: rootVersion) to
    /// trigger withAnimation rather than watching root directly (root identity
    /// may change even for same-screen re-renders).
    @Published public var rootVersion: Int = 0
    /// Increments ONLY when a navigation transition is requested.
    /// MobRootView uses this (not rootVersion) as the view identity (.id(navVersion))
    /// so the whole view is only torn down and rebuilt on screen pushes/pops,
    /// not on every state-update re-render (e.g., typing in a text field).
    @Published public var navVersion: Int = 0
    /// Transition type for the *next* root change. Read by MobRootView before
    /// calling withAnimation; not @Published to avoid spurious recompositions.
    public var transition: String = "none"
    /// Current startup phase message shown while BEAM is initialising.
    @Published public var startupPhase: String = "Starting…"
    /// Non-nil when a fatal startup error has occurred; the error screen stalls here.
    @Published public var startupError: String? = nil

    @objc public func setRoot(_ node: MobNode?, transition: String) {
        DispatchQueue.main.async {
            // Lightweight check: if node type and child count match, skip rebuild
            if let new = node, let old = self.root,
                new.nodeType == old.nodeType,
                new.children.count == old.children.count
            {
                // Quick bail: same structure, just update in place
                // (SwiftUI will diff the view tree automatically)
                self.root = new
                self.rootVersion += 1
                return
            }
            self.transition = transition
            self.root = node
            self.rootVersion += 1
            if transition != "none" {
                self.navVersion += 1
            }
        }
    }

    /// Parse JSON string and update root. Called from Rust NIF via ObjC bridge.
    @objc public func setRootFromJSON(_ json: String, transition: String) {
        guard let data = json.data(using: .utf8) else {
            NSLog("[Mob] Failed to convert JSON string to data")
            return
        }
        do {
            let obj = try JSONSerialization.jsonObject(with: data)
            guard let dict = obj as? [String: Any] else {
                NSLog("[Mob] JSON root is not a dictionary")
                return
            }
            let node = MobNode.fromDictionary(dict)
            setRoot(node, transition: transition)
        } catch {
            NSLog("[Mob] JSON parse error: %@", error.localizedDescription)
        }
    }

    @objc public func setStartupPhase(_ phase: String) {
        DispatchQueue.main.async { self.startupPhase = phase }
    }

    @objc public func setStartupError(_ error: String?) {
        DispatchQueue.main.async { self.startupError = error }
    }
}

// UIHostingController subclass that intercepts the left-edge swipe gesture
// and forwards it to the BEAM as {:mob, :back}.
// Using UIScreenEdgePanGestureRecognizer rather than a SwiftUI DragGesture
// because it integrates cleanly with scroll views and doesn't require
// threading gesture priority through the view tree.
public class MobHostingController: UIHostingController<MobRootView> {
    override public func viewDidLoad() {
        super.viewDidLoad()
        let edgePan = UIScreenEdgePanGestureRecognizer(
            target: self, action: #selector(handleEdgePan(_:)))
        edgePan.edges = .left
        view.addGestureRecognizer(edgePan)
    }

    @objc private func handleEdgePan(_ gesture: UIScreenEdgePanGestureRecognizer) {
        if gesture.state == .ended {
            mob_handle_back()
        }
    }
}

// Factory: lets ObjC (AppDelegate.m) create the SwiftUI hosting controller
// without knowing about the generic UIHostingController<MobRootView> type.
@objc public class MobUIFactory: NSObject {
    @objc public static func makeRootViewController() -> UIViewController {
        return MobHostingController(rootView: MobRootView())
    }
}

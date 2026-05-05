// DalaViewModel.swift — Shared state store between BEAM NIFs and SwiftUI.
// NIFs call setRoot() from any thread; the @Published triggers SwiftUI re-render on main.

import Combine
import SwiftUI

@objc public class DalaViewModel: NSObject, ObservableObject {
    @objc public static let shared = DalaViewModel()

    @Published public var root: DalaNode? = nil
    /// Increments on every setRoot call; views use onChange(of: rootVersion) to
    /// trigger withAnimation rather than watching root directly (root identity
    /// may change even for same-screen re-renders).
    @Published public var rootVersion: Int = 0
    /// Increments ONLY when a navigation transition is requested.
    /// DalaRootView uses this (not rootVersion) as the view identity (.id(navVersion))
    /// so the whole view is only torn down and rebuilt on screen pushes/pops,
    /// not on every state-update re-render (e.g., typing in a text field).
    @Published public var navVersion: Int = 0
    /// Transition type for the *next* root change. Read by DalaRootView before
    /// calling withAnimation; not @Published to avoid spurious recompositions.
    public var transition: String = "none"
    /// Current startup phase message shown while BEAM is initialising.
    @Published public var startupPhase: String = "Starting…"
    /// Non-nil when a fatal startup error has occurred; the error screen stalls here.
    @Published public var startupError: String? = nil

    /// Throttle interval for setRoot calls (milliseconds)
    /// Prevents rapid-fire updates from overwhelming SwiftUI
    private var lastSetRootTime: TimeInterval = 0
    private let minSetRootInterval: TimeInterval = 0.016  // ~60fps

    @objc public func setRoot(_ node: DalaNode?, transition: String) {
        DispatchQueue.main.async {
            // Throttle: skip updates that come too quickly (< 16ms apart)
            // This prevents rapid-fire BEAM updates from overwhelming SwiftUI
            let now = CACurrentMediaTime()
            let elapsed = now - self.lastSetRootTime
            if elapsed < self.minSetRootInterval && transition == "none" {
                // For non-navigation updates, throttle aggressively
                return
            }
            self.lastSetRootTime = now

            // Skip if root node is equal (same content, different object)
            // This prevents unnecessary SwiftUI re-renders when BEAM sends
            // the same tree again (e.g., during hot code reload with no changes)
            if let newRoot = node, let currentRoot = self.root, newRoot == currentRoot {
                // Still increment rootVersion so any pending BEAM expectations
                // (like Dala.Test.screen/1) can complete, but don't trigger
                // SwiftUI update
                if transition != "none" {
                    self.transition = transition
                    self.navVersion += 1
                }
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
            NSLog("[Dala] Failed to convert JSON string to data")
            return
        }
        do {
            let obj = try JSONSerialization.jsonObject(with: data)
            guard let dict = obj as? [String: Any] else {
                NSLog("[Dala] JSON root is not a dictionary")
                return
            }
            let node = DalaNode.fromDictionary(dict)
            setRoot(node, transition: transition)
        } catch {
            NSLog("[Dala] JSON parse error: %@", error.localizedDescription)
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
// and forwards it to the BEAM as {:dala, :back}.
// Using UIScreenEdgePanGestureRecognizer rather than a SwiftUI DragGesture
// because it integrates cleanly with scroll views and doesn't require
// threading gesture priority through the view tree.
public class DalaHostingController: UIHostingController<DalaRootView> {
    override public func viewDidLoad() {
        super.viewDidLoad()
        let edgePan = UIScreenEdgePanGestureRecognizer(
            target: self, action: #selector(handleEdgePan(_:)))
        edgePan.edges = .left
        view.addGestureRecognizer(edgePan)
    }

    @objc private func handleEdgePan(_ gesture: UIScreenEdgePanGestureRecognizer) {
        if gesture.state == .ended {
            dala_handle_back()
        }
    }
}

// Factory: lets ObjC (AppDelegate.m) create the SwiftUI hosting controller
// without knowing about the generic UIHostingController<DalaRootView> type.
@objc public class DalaUIFactory: NSObject {
    @objc public static func makeRootViewController() -> UIViewController {
        return DalaHostingController(rootView: DalaRootView())
    }
}

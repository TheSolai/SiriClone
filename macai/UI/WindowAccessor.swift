//
//  WindowAccessor.swift
//  SiriClone
//
//  NSViewRepresentable that captures the hosting NSWindow so views can
//  react to window-level events (focus, key status, etc.).
//

import AppKit
import SwiftUI

struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            self.window = view.window
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            self.window = nsView.window
        }
    }
}
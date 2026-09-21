import ReactNativeBottomSheet
import UIKit

enum BottomSheetTestPresentationMode {
  case portal
  case nativeOverlay

  var usesNativeOverlay: Bool {
    self == .nativeOverlay
  }
}

@MainActor
final class BottomSheetHostFixture {
  let window: UIWindow
  let rootViewController: UIViewController
  let hosts: [BottomSheetHostingView]
  let eventRecorders: [BottomSheetEventRecorder]

  var host: BottomSheetHostingView { hosts[0] }
  var events: BottomSheetEventRecorder { eventRecorders[0] }

  private let components: [UIView]

  init() {
    window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    rootViewController = UIViewController()
    let host = BottomSheetHostingView(frame: window.bounds)
    let events = BottomSheetEventRecorder()
    hosts = [host]
    eventRecorders = [events]
    components = []

    window.rootViewController = rootViewController
    rootViewController.view.frame = window.bounds
    rootViewController.view.addSubview(host)

    host.eventDelegate = events
    host.modal = true
    host.animateIn = false
    host.setScrimOpacities([0, 1])
    host.setDetents([
      ["value": 0.0, "kind": "points", "programmatic": false],
      ["value": 320.0, "kind": "points", "programmatic": false],
    ])
    host.setDetentIndex(1)

    window.makeKeyAndVisible()
    host.setNeedsLayout()
    host.layoutIfNeeded()
  }

  init(presentations: [BottomSheetTestPresentationMode]) {
    precondition(!presentations.isEmpty)
    window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    rootViewController = UIViewController()
    let components = presentations.map {
      BottomSheetTestComponentFactory.makeProductionComponent(
        withNativeOverlay: $0.usesNativeOverlay
      )
    }
    let hosts = components.map { component in
      guard let host = Self.findHost(in: component) else {
        preconditionFailure("The production component must contain a BottomSheetHostingView")
      }
      return host
    }
    self.components = components
    self.hosts = hosts
    eventRecorders = hosts.map { host in
      let recorder = BottomSheetEventRecorder()
      recorder.adapter = host.eventDelegate
      precondition(recorder.adapter != nil, "The host must retain its production component adapter")
      host.eventDelegate = recorder
      return recorder
    }

    window.rootViewController = rootViewController
    rootViewController.view.frame = window.bounds
    components.forEach {
      $0.frame = window.bounds
      rootViewController.view.addSubview($0)
    }
    window.makeKeyAndVisible()
    Self.layoutTree(window)
    eventRecorders.forEach { $0.reset() }
  }

  func tearDown() {
    for (host, recorder) in zip(hosts, eventRecorders) {
      host.eventDelegate = recorder.adapter
    }
    for component in components.reversed() {
      BottomSheetTestComponentFactory.prepare(forRecycle: component)
      component.removeFromSuperview()
    }
    if components.isEmpty {
      host.removeFromSuperview()
    }
    window.isHidden = true
    window.rootViewController = nil
  }

  func detachComponent(at index: Int) {
    components[index].removeFromSuperview()
  }

  func bringComponentToFront(at index: Int) {
    rootViewController.view.bringSubviewToFront(components[index])
    Self.layoutTree(window)
  }

  private static func findHost(in view: UIView) -> BottomSheetHostingView? {
    if let host = view as? BottomSheetHostingView {
      return host
    }
    return view.subviews.lazy.compactMap(findHost).first
  }

  private static func layoutTree(_ view: UIView) {
    view.setNeedsLayout()
    view.layoutIfNeeded()
    view.subviews.forEach(layoutTree)
  }
}

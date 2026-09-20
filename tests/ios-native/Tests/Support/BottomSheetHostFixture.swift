import ReactNativeBottomSheet
import UIKit

@MainActor
final class BottomSheetHostFixture {
  let window: UIWindow
  let rootViewController: UIViewController
  let host: BottomSheetHostingView
  let events: BottomSheetEventRecorder

  init() {
    window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    rootViewController = UIViewController()
    host = BottomSheetHostingView(frame: window.bounds)
    events = BottomSheetEventRecorder()

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

  func tearDown() {
    host.removeFromSuperview()
    window.isHidden = true
    window.rootViewController = nil
  }
}

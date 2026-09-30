import ReactNativeBottomSheet
import UIKit
import XCTest

@MainActor
final class BottomSheetAccessibleDismissalTests: XCTestCase {
  func testStableDismissUsesOutsideSheetScreenFrameWithoutResizingScrim() throws {
    let fixture = BottomSheetHostFixture()
    defer { fixture.tearDown() }
    let host = fixture.host
    let dismiss = try XCTUnwrap(findDismiss(in: host))
    let expectedHostRect = CGRect(
      x: host.bounds.minX,
      y: host.bounds.minY,
      width: host.bounds.width,
      height: 524
    )
    let expectedScreenFrame = UIAccessibility.convertToScreenCoordinates(
      expectedHostRect,
      in: host
    )

    XCTAssertEqual(dismiss.frame, host.bounds, "the visual scrim must remain full-screen")
    assertRect(dismiss.accessibilityFrame, equals: expectedScreenFrame)
  }

  func testDismissRequiresDirectClosedDetentAndPositiveOutsideSheetArea() {
    let fixture = BottomSheetHostFixture()
    defer { fixture.tearDown() }
    let host = fixture.host

    host.setDetents([
      ["value": 0.0, "kind": "points", "programmatic": true],
      ["value": 320.0, "kind": "points", "programmatic": false],
    ])
    host.layoutIfNeeded()
    XCTAssertNil(findDismiss(in: host), "programmatic-only close must not expose Dismiss")

    host.setDetents([
      ["value": 320.0, "kind": "points", "programmatic": false]
    ])
    host.layoutIfNeeded()
    XCTAssertNil(findDismiss(in: host), "a sheet without a closed detent must not expose Dismiss")

    host.animateContentHeight = false
    host.setDetents([
      ["value": 0.0, "kind": "points", "programmatic": false],
      ["value": 844.0, "kind": "points", "programmatic": false],
    ])
    host.layoutIfNeeded()
    XCTAssertNil(findDismiss(in: host), "an empty outside-sheet area must not expose Dismiss")
  }

  func testActivationRemovesDismissAtCloseCommitAndRejectsRetries() async throws {
    let fixture = BottomSheetHostFixture()
    defer { fixture.tearDown() }
    let host = fixture.host
    let events = fixture.events
    let dismiss = try XCTUnwrap(findDismiss(in: host))
    let settle = expectation(description: "activation closes through the real spring")
    settle.assertForOverFulfill = true
    events.didSettleExpectation = settle
    events.positionSamples.removeAll()

    XCTAssertTrue(host.isModalAccessibilityActive)
    XCTAssertTrue(dismiss.accessibilityActivate())
    XCTAssertEqual(events.changedIndices, [0])
    XCTAssertNil(findDismiss(in: host), "Dismiss must leave the accessibility tree at close commit")
    XCTAssertNotNil(host.sheetContainer.layer.animation(forKey: "bottomSheetSettle"))
    XCTAssertLessThan(host.currentContentOffsetY, host.bounds.height - 0.5)
    XCTAssertFalse(dismiss.isHidden, "the visual scrim remains during closing")
    XCTAssertTrue(host.isModalAccessibilityActive)
    XCTAssertTrue(host.hitTest(CGPoint(x: host.bounds.midX, y: 1), with: nil) === dismiss)
    XCTAssertEqual(events.settledIndices, [])
    XCTAssertFalse(dismiss.accessibilityActivate(), "activation during closing must report rejection")
    XCTAssertEqual(events.changedIndices, [0])

    await fulfillment(of: [settle], timeout: 2.0)

    XCTAssertNil(findDismiss(in: host))
    XCTAssertFalse(dismiss.accessibilityActivate(), "activation after closed settle must report rejection")
    XCTAssertEqual(events.changedIndices, [0])
    XCTAssertEqual(events.settledIndices, [0])
    XCTAssertEqual(host.currentContentOffsetY, host.bounds.height, accuracy: 0.5)
    XCTAssertNil(host.sheetContainer.layer.animation(forKey: "bottomSheetSettle"))
    XCTAssertFalse(host.isModalAccessibilityActive)
    XCTAssertTrue(dismiss.isHidden)
    XCTAssertNil(host.hitTest(CGPoint(x: host.bounds.midX, y: 1), with: nil))
    XCTAssertGreaterThan(events.positionSamples.count, 1)
    XCTAssertTrue(events.positionSamples.dropLast().allSatisfy(\.isPresentationActive))
    XCTAssertEqual(events.positionSamples.last?.isPresentationActive, false)
  }

  func testDuplicateZeroTargetRejectsDismissalAndRetainsOwnershipUntilSettle() async throws {
    let fixture = BottomSheetHostFixture(
      presentations: [.portal],
      initialIndices: [2],
      detents: [
        ["value": 0.0, "kind": "points", "programmatic": false],
        ["value": 0.0, "kind": "points", "programmatic": false],
        ["value": 320.0, "kind": "points", "programmatic": false],
      ]
    )
    defer { fixture.tearDown() }
    let host = fixture.host
    let events = fixture.events
    let boundary = try XCTUnwrap(host.superview)
    let dismiss = try XCTUnwrap(findDismiss(in: host))
    let topIdentity = try XCTUnwrap(
      BottomSheetPresentationCoordinator.topPresentationIdentity(in: fixture.window)
    )
    let settle = expectation(description: "second zero detent settles through the real spring")
    settle.assertForOverFulfill = true
    events.didSettleExpectation = settle
    events.observedPresentationBoundary = boundary

    XCTAssertEqual(host.currentContentOffsetY, host.bounds.height - 320, accuracy: 0.5)
    XCTAssertNil(host.sheetContainer.layer.animation(forKey: "bottomSheetSettle"))
    XCTAssertTrue(boundary.accessibilityViewIsModal)

    host.setDetentIndex(1)

    let closingAnimation = try XCTUnwrap(
      host.sheetContainer.layer.animation(forKey: "bottomSheetSettle")
    )
    XCTAssertNil(findDismiss(in: host), "every zero-height target must remove Dismiss immediately")
    XCTAssertFalse(dismiss.accessibilityActivate(), "activation during closing must reject dismissal")
    XCTAssertEqual(events.changedIndices, [], "programmatic closing must not emit a dismissal to index 0")
    XCTAssertTrue(host.accessibilityPerformEscape(), "closing Top must consume Escape")
    XCTAssertEqual(events.changedIndices, [], "Escape must not emit an additional index event")
    XCTAssertTrue(host.sheetContainer.layer.animation(forKey: "bottomSheetSettle") === closingAnimation)
    XCTAssertEqual(events.settledIndices, [])
    XCTAssertTrue(host.isModalAccessibilityActive)
    XCTAssertTrue(boundary.accessibilityViewIsModal)
    XCTAssertTrue(
      BottomSheetPresentationCoordinator.topPresentationIdentity(in: fixture.window) === topIdentity
    )

    await fulfillment(of: [settle], timeout: 2.0)

    XCTAssertEqual(events.changedIndices, [])
    XCTAssertEqual(events.settledIndices, [1])
    XCTAssertNil(findDismiss(in: host))
    XCTAssertFalse(dismiss.accessibilityActivate())
    XCTAssertFalse(host.accessibilityPerformEscape())
    XCTAssertFalse(host.isModalAccessibilityActive)
    XCTAssertFalse(boundary.accessibilityViewIsModal)
    XCTAssertNil(BottomSheetPresentationCoordinator.topPresentationIdentity(in: fixture.window))
    XCTAssertGreaterThan(events.positionSamples.count, 1)
    XCTAssertTrue(events.positionSamples.dropLast().allSatisfy(\.isPresentationActive))
    XCTAssertTrue(events.positionSamples.allSatisfy { $0.isPresentationBoundaryModal == true })
  }

  func testHostEscapeRemovesDismissAtCloseCommitAndConsumesRetries() async throws {
    let fixture = BottomSheetHostFixture(presentations: [.portal])
    defer { fixture.tearDown() }
    let host = fixture.host
    let events = fixture.events
    let dismiss = try XCTUnwrap(findDismiss(in: host))
    let settle = expectation(description: "host Escape closes through the real spring")
    settle.assertForOverFulfill = true
    events.didSettleExpectation = settle
    events.positionSamples.removeAll()

    XCTAssertTrue(host.isModalAccessibilityActive)
    XCTAssertTrue(host.accessibilityPerformEscape())
    XCTAssertEqual(events.changedIndices, [0])
    XCTAssertNil(findDismiss(in: host), "Dismiss must leave the accessibility tree at Escape close commit")
    XCTAssertNotNil(host.sheetContainer.layer.animation(forKey: "bottomSheetSettle"))
    XCTAssertLessThan(host.currentContentOffsetY, host.bounds.height - 0.5)
    XCTAssertFalse(dismiss.isHidden)
    XCTAssertTrue(host.isModalAccessibilityActive)
    XCTAssertEqual(events.settledIndices, [])
    XCTAssertTrue(host.accessibilityPerformEscape(), "closing Top must keep consuming Escape")
    XCTAssertEqual(events.changedIndices, [0])

    await fulfillment(of: [settle], timeout: 2.0)

    XCTAssertNil(findDismiss(in: host))
    XCTAssertFalse(host.accessibilityPerformEscape())
    XCTAssertEqual(events.changedIndices, [0])
    XCTAssertEqual(events.settledIndices, [0])
    XCTAssertEqual(host.currentContentOffsetY, host.bounds.height, accuracy: 0.5)
    XCTAssertNil(host.sheetContainer.layer.animation(forKey: "bottomSheetSettle"))
    XCTAssertFalse(host.isModalAccessibilityActive)
    XCTAssertTrue(dismiss.isHidden)
    XCTAssertGreaterThan(events.positionSamples.count, 1)
    XCTAssertTrue(events.positionSamples.dropLast().allSatisfy(\.isPresentationActive))
    XCTAssertEqual(events.positionSamples.last?.isPresentationActive, false)
  }

}

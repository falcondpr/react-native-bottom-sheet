import CoreGraphics
import ReactNativeBottomSheet
import XCTest

@MainActor
final class BottomSheetEventRecorder: NSObject, @preconcurrency BottomSheetHostingViewDelegate {
  struct PositionSample {
    let position: CGFloat
    let isPresentationActive: Bool
  }

  var changedIndices: [Int] = []
  var settledIndices: [Int] = []
  var positionSamples: [PositionSample] = []
  var didSettleExpectation: XCTestExpectation?

  func bottomSheetHostingView(_: BottomSheetHostingView, didChangeIndex index: Int) {
    changedIndices.append(index)
  }

  func bottomSheetHostingView(_ view: BottomSheetHostingView, didSettle index: Int) {
    settledIndices.append(index)
    didSettleExpectation?.fulfill()
  }

  func bottomSheetHostingView(
    _ view: BottomSheetHostingView,
    didChangePosition position: CGFloat,
    index _: CGFloat
  ) {
    positionSamples.append(
      PositionSample(
        position: position,
        isPresentationActive: view.isModalAccessibilityActive
      )
    )
  }

  func bottomSheetHostingView(_: BottomSheetHostingView, didReportError message: String) {
    XCTFail("Production host reported an error: \(message)")
  }

  func bottomSheetHostingViewDidLayout(_: BottomSheetHostingView) {}
}

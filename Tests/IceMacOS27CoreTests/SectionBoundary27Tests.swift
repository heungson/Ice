import CoreGraphics
import Testing
@testable import IceMacOS27Core

@Suite("Physical section boundary")
struct SectionBoundary27Tests {
    let arrow = CGRect(x: 500, y: 0, width: 24, height: 24)
    func frame(_ x: CGFloat, y: CGFloat = 0, width: CGFloat = 22) -> CGRect {
        CGRect(x: x, y: y, width: width, height: 24)
    }

    @Test func leftHidesAndRightStaysVisible() {
        #expect(SectionBoundary27.section(of: frame(470), arrow: arrow) == .hidden)
        #expect(SectionBoundary27.section(of: frame(530), arrow: arrow) == .visible)
    }
    @Test func overlapAndOtherDisplaysAreNotAdopted() {
        #expect(SectionBoundary27.section(of: frame(490), arrow: arrow) == nil)
        #expect(SectionBoundary27.section(of: frame(470, y: 900), arrow: arrow) == nil)
        #expect(SectionBoundary27.section(of: frame(470, width: 0), arrow: arrow) == nil)
    }
    @Test func neighbouringAccessibilityPaddingDoesNotCrossTheBoundary() {
        #expect(SectionBoundary27.section(of: frame(470, width: 34), arrow: arrow) == .hidden)
        #expect(SectionBoundary27.section(of: frame(520, width: 34), arrow: arrow) == .visible)
    }
    @Test func multipleIconsOfAnAppStayVisibleWhenTheyStraddleTheArrow() {
        let layout = SectionBoundary27.observedSections(items: [("viewer", frame(470)), ("viewer", frame(530))], arrow: arrow)
        #expect(layout == ["viewer": .visible])
    }
    @Test func bothHiddenSectionsBelongLeftOfTheArrow() {
        #expect(SectionBoundary27.isCorrect(bounds: frame(470), arrow: arrow, section: .alwaysHidden))
        #expect(!SectionBoundary27.isCorrect(bounds: frame(530), arrow: arrow, section: .hidden))
    }
    @Test func negativeDisplayCoordinatesAreClassifiedNormally() {
        let a = CGRect(x: -500, y: 0, width: 24, height: 24)
        #expect(SectionBoundary27.section(of: frame(-540), arrow: a) == .hidden)
        #expect(SectionBoundary27.section(of: frame(-460), arrow: a) == .visible)
    }
    @Test func duplicateProcessesHaveSeparateItemIdentities() {
        #expect(SyntheticWindowID27.make(bundleID: "viewer", identifier: "Item-0", index: 0, processID: 1) !=
                SyntheticWindowID27.make(bundleID: "viewer", identifier: "Item-0", index: 0, processID: 2))
    }
}

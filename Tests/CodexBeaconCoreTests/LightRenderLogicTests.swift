import Foundation
import Testing

@testable import CodexBeaconCore

struct LightRenderLogicTests {
  @Test("off illumination always renders dim, never oscillating")
  func offIsStaticAndDim() {
    let logic = LightRenderLogic(illumination: .off, reducesMotion: false)
    let samples = stride(from: 0.0, to: 5.0, by: 0.1).map { Date(timeIntervalSince1970: $0) }
    for date in samples {
      #expect(logic.displayedOpacity(at: date) == 0.08)
    }
    #expect(logic.shouldAnimate == false)
    #expect(logic.showsWaitingRing == false)
  }

  @Test("steady illumination is solid regardless of reduce motion")
  func steadyIsStaticAndSolid() {
    let noReduce = LightRenderLogic(illumination: .steady, reducesMotion: false)
    let reduce = LightRenderLogic(illumination: .steady, reducesMotion: true)
    #expect(noReduce.displayedOpacity(at: .now) == 1.0)
    #expect(reduce.displayedOpacity(at: .now) == 1.0)
    #expect(noReduce.shouldAnimate == false)
    #expect(reduce.shouldAnimate == false)
  }

  @Test("breathing illumination oscillates between 0.6 and 1.0 with a slow period")
  func breathingOscillates() {
    let logic = LightRenderLogic(illumination: .breathing, reducesMotion: false)
    #expect(logic.shouldAnimate == true)
    #expect(logic.minimumOpacity == 0.6)
    #expect(logic.animationPeriod == 3.6)

    let period = logic.animationPeriod
    let t0 = Date(timeIntervalSince1970: 0)
    let samples = (0..<60).map { i in t0.addingTimeInterval(Double(i) * period / 60) }
    let opacities = samples.map { logic.displayedOpacity(at: $0) }
    #expect(opacities.min()! >= 0.59)
    #expect(opacities.min()! <= 0.62)
    #expect(opacities.max()! >= 0.999)
    #expect(opacities.max()! <= 1.0)
  }

  @Test("flashing illumination oscillates between 0.4 and 1.0 with a faster period")
  func flashingOscillatesFaster() {
    let logic = LightRenderLogic(illumination: .flashing, reducesMotion: false)
    #expect(logic.shouldAnimate == true)
    #expect(logic.minimumOpacity == 0.4)
    #expect(logic.animationPeriod == 1.4)

    let period = logic.animationPeriod
    let t0 = Date(timeIntervalSince1970: 0)
    let samples = (0..<60).map { i in t0.addingTimeInterval(Double(i) * period / 60) }
    let opacities = samples.map { logic.displayedOpacity(at: $0) }
    #expect(opacities.min()! >= 0.39)
    #expect(opacities.min()! <= 0.42)
    #expect(opacities.max()! >= 0.999)
    #expect(opacities.max()! <= 1.0)
  }

  @Test("flashing under reduce motion shows the static waiting ring and never animates")
  func flashingUnderReduceMotionIsStaticRing() {
    let logic = LightRenderLogic(illumination: .flashing, reducesMotion: true)
    #expect(logic.shouldAnimate == false)
    #expect(logic.showsWaitingRing == true)
    let t0 = Date(timeIntervalSince1970: 0)
    let samples = (0..<20).map { i in t0.addingTimeInterval(Double(i) * 0.1) }
    for date in samples {
      #expect(logic.displayedOpacity(at: date) == 1.0)
    }
  }

  @Test("breathing under reduce motion collapses to solid 1.0 (no animation)")
  func breathingUnderReduceMotionIsSolid() {
    let logic = LightRenderLogic(illumination: .breathing, reducesMotion: true)
    #expect(logic.shouldAnimate == false)
    #expect(logic.showsWaitingRing == false)
    let t0 = Date(timeIntervalSince1970: 0)
    let samples = (0..<20).map { i in t0.addingTimeInterval(Double(i) * 0.1) }
    for date in samples {
      #expect(logic.displayedOpacity(at: date) == 1.0)
    }
  }

  @Test("REGRESSION: switching out of breathing must collapse to the off base opacity")
  func workingToCompletedCollapsesAmberToDim() {
    let working = LightRenderLogic(illumination: .breathing, reducesMotion: false)
    let completed = LightRenderLogic(illumination: .off, reducesMotion: false)
    let date = Date(timeIntervalSince1970: 1.7)
    #expect(working.displayedOpacity(at: date) > 0.5)
    #expect(completed.displayedOpacity(at: date) == 0.08)
  }

  @Test("REGRESSION: switching out of flashing must collapse to steady 1.0 immediately")
  func waitingToCompletedCollapsesGreenToSteady() {
    let waiting = LightRenderLogic(illumination: .flashing, reducesMotion: false)
    let completed = LightRenderLogic(illumination: .steady, reducesMotion: false)
    let date = Date(timeIntervalSince1970: 0.6)
    #expect(waiting.displayedOpacity(at: date) < 1.0)
    #expect(completed.displayedOpacity(at: date) == 1.0)
  }
}

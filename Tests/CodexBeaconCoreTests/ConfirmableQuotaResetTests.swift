import Foundation
import Testing

@testable import CodexBeaconCore

@MainActor
struct ConfirmableQuotaResetTests {
  private static let start = Date(timeIntervalSince1970: 1_753_353_600)
  private static let windowDuration: TimeInterval = 18_000

  @Test("the first available snapshot establishes a baseline without a reset notification")
  func firstSnapshotDoesNotReportReset() throws {
    let defaults = try makeDefaults()
    let store = QuotaResetBaselineStore(defaults: defaults, key: "quota-reset-baseline")
    let coordinator = AppCoordinator(quotaResetBaselineStore: store)

    sendSnapshot(
      to: coordinator,
      at: Self.start,
      accountID: "account-a",
      usedPercent: 80,
      resetsAt: Self.start.addingTimeInterval(Self.windowDuration)
    )

    #expect(coordinator.drainViewResetEvents().isEmpty)
    let baseline = try #require(store.load())
    #expect(baseline.windowKey == "5h")
    #expect(baseline.accountContextDigest != "account-a")
    let storedData = try #require(defaults.data(forKey: "quota-reset-baseline"))
    #expect(!String(decoding: storedData, as: UTF8.self).contains("account-a"))
  }

  @Test("a recent reset proven across a Beacon restart is reported once")
  func recentRestartReportsOnce() throws {
    let defaults = try makeDefaults()
    let store = QuotaResetBaselineStore(defaults: defaults, key: "quota-reset-baseline")
    let firstRun = AppCoordinator(quotaResetBaselineStore: store)
    sendSnapshot(
      to: firstRun,
      at: Self.start,
      accountID: "account-a",
      usedPercent: 80,
      resetsAt: Self.start.addingTimeInterval(Self.windowDuration)
    )
    let resumedAt = Self.start.addingTimeInterval(3_600)
    let secondRun = AppCoordinator(quotaResetBaselineStore: store)
    sendSnapshot(
      to: secondRun,
      at: resumedAt,
      accountID: "account-a",
      usedPercent: 0,
      resetsAt: resumedAt.addingTimeInterval(Self.windowDuration)
    )

    let events = secondRun.drainViewResetEvents()
    #expect(events.count == 1)
    #expect(events.first?.kind == .confirmed)
    #expect(events.first?.windowKeys == ["5h"])

    let laterRun = AppCoordinator(quotaResetBaselineStore: store)
    sendSnapshot(
      to: laterRun,
      at: resumedAt.addingTimeInterval(60),
      accountID: "account-a",
      usedPercent: 0,
      resetsAt: resumedAt.addingTimeInterval(Self.windowDuration)
    )
    #expect(laterRun.drainViewResetEvents().isEmpty)
  }

  @Test("a quota response that arrives before account context keeps the earlier evidence")
  func quotaResponseBeforeAccountContextStillReportsReset() throws {
    let defaults = try makeDefaults()
    let store = QuotaResetBaselineStore(defaults: defaults, key: "quota-reset-baseline")
    let firstRun = AppCoordinator(quotaResetBaselineStore: store)
    sendSnapshot(
      to: firstRun,
      at: Self.start,
      accountID: "account-a",
      usedPercent: 80,
      resetsAt: Self.start.addingTimeInterval(Self.windowDuration)
    )

    let resumedAt = Self.start.addingTimeInterval(3_600)
    let secondRun = AppCoordinator(quotaResetBaselineStore: store)
    sendSnapshot(
      to: secondRun,
      at: resumedAt,
      accountID: "account-a",
      usedPercent: 0,
      resetsAt: resumedAt.addingTimeInterval(Self.windowDuration),
      accountContextBeforeQuota: false
    )

    #expect(secondRun.drainViewResetEvents().count == 1)
  }

  @Test("a baseline older than 24 hours never produces a reset notification")
  func expiredBaselineDoesNotReportReset() throws {
    let defaults = try makeDefaults()
    let store = QuotaResetBaselineStore(defaults: defaults, key: "quota-reset-baseline")
    let firstRun = AppCoordinator(quotaResetBaselineStore: store)
    sendSnapshot(
      to: firstRun,
      at: Self.start,
      accountID: "account-a",
      usedPercent: 80,
      resetsAt: Self.start.addingTimeInterval(Self.windowDuration)
    )

    let resumedAt = Self.start.addingTimeInterval(86_401)
    let secondRun = AppCoordinator(quotaResetBaselineStore: store)
    sendSnapshot(
      to: secondRun,
      at: resumedAt,
      accountID: "account-a",
      usedPercent: 0,
      resetsAt: resumedAt.addingTimeInterval(Self.windowDuration)
    )

    #expect(secondRun.drainViewResetEvents().isEmpty)
  }

  @Test("a sleep recovery reports only the latest provable reset")
  func sleepRecoveryReportsAtMostOneReset() throws {
    let defaults = try makeDefaults()
    let store = QuotaResetBaselineStore(defaults: defaults, key: "quota-reset-baseline")
    let coordinator = AppCoordinator(quotaResetBaselineStore: store)
    sendSnapshot(
      to: coordinator,
      at: Self.start,
      accountID: "account-a",
      usedPercent: 80,
      resetsAt: Self.start.addingTimeInterval(Self.windowDuration)
    )

    coordinator.handle(.task(.monitoringConnectionFailed))
    let resumedAt = Self.start.addingTimeInterval(12 * 60 * 60)
    sendSnapshot(
      to: coordinator,
      at: resumedAt,
      accountID: "account-a",
      usedPercent: 0,
      resetsAt: resumedAt.addingTimeInterval(Self.windowDuration)
    )

    let events = coordinator.drainViewResetEvents()
    #expect(events.count == 1)
    #expect(events.first?.windowKeys == ["5h"])
  }

  @Test("an observed account change replaces the baseline without crossing accounts")
  func accountChangeClearsOldBaseline() throws {
    let defaults = try makeDefaults()
    let store = QuotaResetBaselineStore(defaults: defaults, key: "quota-reset-baseline")
    let firstRun = AppCoordinator(quotaResetBaselineStore: store)
    sendSnapshot(
      to: firstRun,
      at: Self.start,
      accountID: "account-a",
      usedPercent: 80,
      resetsAt: Self.start.addingTimeInterval(Self.windowDuration)
    )
    let oldDigest = try #require(store.load()?.accountContextDigest)

    let secondRun = AppCoordinator(quotaResetBaselineStore: store)
    let resumedAt = Self.start.addingTimeInterval(3_600)
    sendSnapshot(
      to: secondRun,
      at: resumedAt,
      accountID: "account-b",
      usedPercent: 0,
      resetsAt: resumedAt.addingTimeInterval(Self.windowDuration)
    )

    #expect(secondRun.drainViewResetEvents().isEmpty)
    let baseline = try #require(store.load())
    #expect(baseline.accountContextDigest != oldDigest)
    #expect(baseline.accountContextDigest != "account-b")
  }

  @Test("a percentage jump without a new reset boundary does not report a reset")
  func insufficientEvidenceDoesNotReportReset() throws {
    let defaults = try makeDefaults()
    let store = QuotaResetBaselineStore(defaults: defaults, key: "quota-reset-baseline")
    let firstRun = AppCoordinator(quotaResetBaselineStore: store)
    let resetAt = Self.start.addingTimeInterval(Self.windowDuration)
    sendSnapshot(
      to: firstRun,
      at: Self.start,
      accountID: "account-a",
      usedPercent: 80,
      resetsAt: resetAt
    )

    let secondRun = AppCoordinator(quotaResetBaselineStore: store)
    sendSnapshot(
      to: secondRun,
      at: Self.start.addingTimeInterval(3_600),
      accountID: "account-a",
      usedPercent: 0,
      resetsAt: resetAt
    )

    #expect(secondRun.drainViewResetEvents().isEmpty)
  }

  @Test("a reset boundary that predates the baseline is not proven by the snapshots")
  func resetBeforeBaselineDoesNotReportReset() throws {
    let defaults = try makeDefaults()
    let store = QuotaResetBaselineStore(defaults: defaults, key: "quota-reset-baseline")
    let firstRun = AppCoordinator(quotaResetBaselineStore: store)
    sendSnapshot(
      to: firstRun,
      at: Self.start,
      accountID: "account-a",
      usedPercent: 80,
      resetsAt: Self.start.addingTimeInterval(3_600)
    )

    let secondRun = AppCoordinator(quotaResetBaselineStore: store)
    sendSnapshot(
      to: secondRun,
      at: Self.start.addingTimeInterval(2 * 3_600),
      accountID: "account-a",
      usedPercent: 0,
      resetsAt: Self.start.addingTimeInterval(4 * 3_600)
    )

    #expect(secondRun.drainViewResetEvents().isEmpty)
  }

  @Test("an account context notification clears the persisted baseline")
  func accountContextNotificationClearsBaseline() throws {
    let defaults = try makeDefaults()
    let store = QuotaResetBaselineStore(defaults: defaults, key: "quota-reset-baseline")
    let coordinator = AppCoordinator(quotaResetBaselineStore: store)
    sendSnapshot(
      to: coordinator,
      at: Self.start,
      accountID: "account-a",
      usedPercent: 80,
      resetsAt: Self.start.addingTimeInterval(Self.windowDuration)
    )
    #expect(store.load() != nil)

    coordinator.handle(
      .task(.appServerMessage("""
        {"method":"account/updated","params":{"authMode":"chatgpt","planType":"plus"}}
        """))
    )

    #expect(store.load() == nil)
  }

  @Test("a missing stable account identifier never reports a reset across restarts")
  func missingAccountIdentifierDoesNotReportReset() throws {
    let defaults = try makeDefaults()
    let store = QuotaResetBaselineStore(defaults: defaults, key: "quota-reset-baseline")
    let firstRun = AppCoordinator(quotaResetBaselineStore: store)
    sendSnapshot(
      to: firstRun,
      at: Self.start,
      accountID: nil,
      usedPercent: 80,
      resetsAt: Self.start.addingTimeInterval(Self.windowDuration)
    )

    let resumedAt = Self.start.addingTimeInterval(3_600)
    let secondRun = AppCoordinator(quotaResetBaselineStore: store)
    sendSnapshot(
      to: secondRun,
      at: resumedAt,
      accountID: nil,
      usedPercent: 0,
      resetsAt: resumedAt.addingTimeInterval(Self.windowDuration)
    )

    #expect(secondRun.drainViewResetEvents().isEmpty)
  }

  private func makeDefaults() throws -> UserDefaults {
    let suiteName = "ConfirmableQuotaResetTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
  }

  private func sendSnapshot(
    to coordinator: AppCoordinator,
    at date: Date,
    accountID: String?,
    usedPercent: Double,
    resetsAt: Date,
    accountContextBeforeQuota: Bool = true
  ) {
    coordinator.handle(.time(.advanced(to: date)))
    coordinator.handle(.task(.monitoringConnectionEstablished(protocolCompatible: true)))
    let requests = coordinator.drainAppServerRequests()
    let accountRequest = requests.first { $0.method == "account/read" }!
    let rateLimitsRequest = requests.first { $0.method == "account/rateLimits/read" }!
    let accountResult = accountID.map { "\"email\":\"\($0)\"" } ?? ""
    let accountResponse = """
      {"id":\(accountRequest.id),"result":{\(accountResult)}}
      """
    let quotaResponse = """
      {"id":\(rateLimitsRequest.id),"result":{"rateLimits":{"5h":{"durationSeconds":\(Self.windowDuration),"usedPercent":\(usedPercent),"resetsAt":\(resetsAt.timeIntervalSince1970)}}}}
      """
    let responses = accountContextBeforeQuota
      ? [accountResponse, quotaResponse]
      : [quotaResponse, accountResponse]
    for response in responses {
      coordinator.handle(.task(.appServerMessage(response)))
    }
  }
}

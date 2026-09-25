import Foundation
import Testing

@testable import IMsgCore
@testable import imsg

@Test
func rpcReadOnlyRejectsEveryMutationAndAdvertisesOnlyApprovedReads() async throws {
  let store = try CommandTestDatabase.makeStoreForRPC()
  let output = TestRPCOutput()
  var sendCalls = 0
  var bridgeCalls = 0
  let server = RPCServer(
    store: store, verbose: false, readOnly: true, output: output,
    sendMessage: { options in
      sendCalls += 1
      return options
    },
    invokeBridge: { _, _ in
      bridgeCalls += 1
      return [:]
    })

  let denied =
    rpcMethodDescriptors
    .filter { $0.lane == .mutation }
    .flatMap(\.names) + ["future.unknown", "bridge.events.subscribe", "handles.check"]
  for (index, method) in denied.enumerated() {
    await server.handleLineForTesting(
      "{\"jsonrpc\":\"2.0\",\"id\":\(index),\"method\":\"\(method)\",\"params\":{}}")
  }
  #expect(output.responses.isEmpty)
  #expect(output.errors.count == denied.count)
  #expect(
    output.errors.allSatisfy {
      rpcTestInt64Value(($0["error"] as? [String: Any])?["code"]) == -32601
    })
  #expect(sendCalls == 0)
  #expect(bridgeCalls == 0)

  await server.handleLineForTesting(
    #"{"jsonrpc":"2.0","id":"status","method":"status","params":{}}"#)
  let status = try #require(output.responses.last?["result"] as? [String: Any])
  let supported = Set(status["supported_methods"] as? [String] ?? [])
  let available = Set(status["methods"] as? [String] ?? [])
  #expect(supported.isSubset(of: kReadOnlyRPCMethods))
  #expect(available.isSubset(of: kReadOnlyRPCMethods))
  #expect(supported.contains("messages.after"))
  #expect(supported.contains("messages.by_guid"))
  #expect(!supported.contains("send"))
}

import Foundation

@main
struct CodexTaskStatusLogParserTests {
    static var failures = 0

    static func expect(_ condition: Bool, _ label: String) {
        if condition {
            print("PASS \(label)")
        } else {
            print("FAIL \(label)")
            failures += 1
        }
    }

    static func event(_ type: String, detail: String = "") -> Data {
        let payload: [String: Any] = [
            "type": "event_msg",
            "payload": ["type": type, "detail": detail],
        ]
        let data = try! JSONSerialization.data(withJSONObject: payload)
        return data + Data([0x0A])
    }

    static func responseItem(_ payload: [String: Any]) -> Data {
        let data = try! JSONSerialization.data(withJSONObject: [
            "type": "response_item",
            "payload": payload,
        ])
        return data + Data([0x0A])
    }

    static func permissionRequest(_ callID: String) -> Data {
        responseItem([
            "type": "function_call",
            "name": "request_permissions",
            "call_id": callID,
        ])
    }

    static func functionOutput(_ callID: String) -> Data {
        responseItem([
            "type": "function_call_output",
            "call_id": callID,
            "output": "approved",
        ])
    }

    static func sessionMeta(subagent: Bool) -> Data {
        let source: Any = subagent
            ? ["subagent": ["other": "guardian"]]
            : "vscode"
        let data = try! JSONSerialization.data(withJSONObject: [
            "type": "session_meta",
            "payload": ["source": source],
        ])
        return data + Data([0x0A])
    }

    static func main() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let log = directory.appendingPathComponent("rollout-test.jsonl")
        var data = event("task_started")
        data.append(event("stream_error"))
        try data.write(to: log)
        expect(
            CodexTaskStatusLogParser.parse(at: log) == .error,
            "failure marker is cached"
        )

        let filler = String(repeating: "x", count: 180)
        let growthHandle = try FileHandle(forWritingTo: log)
        try growthHandle.seekToEnd()
        while data.count < 530 * 1024 {
            let update = event("response_item", detail: filler)
            data.append(update)
            try growthHandle.write(contentsOf: update)
            if data.count % (64 * 1024) < update.count {
                _ = CodexTaskStatusLogParser.parse(at: log)
            }
        }
        try growthHandle.close()
        data.append(event("task_complete"))
        try event("task_complete").append(to: log)

        expect(
            CodexTaskStatusLogParser.parse(at: log) == .error,
            "failure outside tail survives task_complete"
        )

        let oversized = directory.appendingPathComponent("rollout-oversized.jsonl")
        var oversizedData = event("task_started")
        oversizedData.append(
            event("response_item", detail: String(repeating: "x", count: 1024))
        )
        oversizedData.append(event("task_complete"))
        try oversizedData.write(to: oversized)
        expect(
            CodexTaskStatusLogParser.parse(at: oversized, maxBytes: 128) == .idle,
            "oversized record fallback stays within the read cap"
        )

        let noBoundary = directory.appendingPathComponent("rollout-no-boundary.jsonl")
        try Data(repeating: 0x78, count: 1024).write(to: noBoundary)
        expect(
            CodexTaskStatusLogParser.parse(at: noBoundary, maxBytes: 128) == nil,
            "fresh read without a complete line returns nil"
        )

        let continued = directory.appendingPathComponent("rollout-continued.jsonl")
        try event("stream_error").write(to: continued)
        expect(
            CodexTaskStatusLogParser.parse(at: continued) == .error,
            "continuation state is initialized"
        )
        try Data("partial".utf8).append(to: continued)
        expect(
            CodexTaskStatusLogParser.parse(at: continued) == .error,
            "cached continuation without a complete line preserves state"
        )

        let currentVocabulary = directory.appendingPathComponent("rollout-current.jsonl")
        var currentData = event("task_started")
        currentData.append(event("mcp_tool_call_end"))
        try currentData.write(to: currentVocabulary)
        expect(
            CodexTaskStatusLogParser.parse(at: currentVocabulary) == .running,
            "current rollout end events preserve running state"
        )
        try event("turn_aborted").append(to: currentVocabulary)
        expect(
            CodexTaskStatusLogParser.parse(at: currentVocabulary) == .cancelled,
            "turn_aborted is cancelled rather than error"
        )

        let growthGap = directory.appendingPathComponent("rollout-growth-gap.jsonl")
        var growthData = event("task_started")
        growthData.append(
            event("response_item", detail: String(repeating: "x", count: 1024))
        )
        try growthData.write(to: growthGap)
        expect(
            CodexTaskStatusLogParser.parse(at: growthGap, maxBytes: 128) == nil,
            "unrecognized truncated tail reports unavailable"
        )

        let cachedGrowthGap = directory.appendingPathComponent("rollout-cached-growth-gap.jsonl")
        try event("task_started").write(to: cachedGrowthGap)
        expect(
            CodexTaskStatusLogParser.parse(at: cachedGrowthGap, maxBytes: 128) == .running,
            "long-running task establishes a cached running state"
        )
        try event(
            "response_item",
            detail: String(repeating: "x", count: 1024)
        ).append(to: cachedGrowthGap)
        expect(
            CodexTaskStatusLogParser.parse(at: cachedGrowthGap, maxBytes: 128) == .running,
            "large unrecognized growth preserves the cached running state"
        )
        try event("task_complete").append(to: cachedGrowthGap)
        expect(
            CodexTaskStatusLogParser.parse(at: cachedGrowthGap, maxBytes: 128) == .idle,
            "completion after a large growth gap is still detected"
        )

        let now = Date()
        expect(
            CodexTaskStatusPolicy.priority(for: .running, updatedAt: now, now: now)
                > CodexTaskStatusPolicy.priority(for: .error, updatedAt: now, now: now),
            "live running work outranks a recent error"
        )
        expect(
            CodexTaskStatusPolicy.priority(
                for: .error,
                updatedAt: now.addingTimeInterval(-11 * 60),
                now: now
            ) < CodexTaskStatusPolicy.priority(for: .idle, updatedAt: now, now: now),
            "stale terminal state decays below idle"
        )
        expect(
            !CodexTaskStatusPolicy.isPastTerminalDecay(
                updatedAt: now.addingTimeInterval(-9 * 60),
                now: now
            ) && CodexTaskStatusPolicy.isPastTerminalDecay(
                updatedAt: now.addingTimeInterval(-11 * 60),
                now: now
            ),
            "terminal decay phase changes after ten minutes"
        )

        let utcBoundary = ISO8601DateFormatter().date(
            from: "2026-08-07T01:00:00Z"
        )!
        let utcComponents = CodexTaskStatusDirectoryPolicy.utcDateComponents(
            for: utcBoundary
        )
        expect(
            utcComponents.year == 2026
                && utcComponents.month == 8
                && utcComponents.day == 7,
            "rollout directory components use the UTC date"
        )

        let shortTask = directory.appendingPathComponent("rollout-short-task.jsonl")
        var shortTaskData = event("task_started")
        shortTaskData.append(event("task_complete"))
        try shortTaskData.write(to: shortTask)
        let shortTaskResult = CodexTaskStatusLogParser.parseUpdate(at: shortTask)
        expect(
            shortTaskResult?.state == .idle
                && shortTaskResult?.soundEvents == [.completed],
            "short task completed between polls still emits a completion event"
        )

        let incrementalTask = directory.appendingPathComponent("rollout-incremental-task.jsonl")
        try event("task_started").write(to: incrementalTask)
        let startedResult = CodexTaskStatusLogParser.parseUpdate(at: incrementalTask)
        try event("task_complete").append(to: incrementalTask)
        let completedResult = CodexTaskStatusLogParser.parseUpdate(at: incrementalTask)
        expect(
            startedResult?.soundEvents.isEmpty == true
                && completedResult?.soundEvents == [.completed],
            "incremental task completion emits exactly one completion event"
        )

        let parallelTask = directory.appendingPathComponent("rollout-parallel-task.jsonl")
        var parallelTaskData = event("task_started")
        parallelTaskData.append(event("turn_aborted"))
        try parallelTaskData.write(to: parallelTask)
        expect(
            CodexTaskStatusLogParser.parseUpdate(at: parallelTask)?.soundEvents
                == [.cancelled],
            "each independently parsed task emits its own terminal event"
        )

        let errorTask = directory.appendingPathComponent("rollout-error-task.jsonl")
        var errorTaskData = event("task_started")
        errorTaskData.append(event("stream_error"))
        errorTaskData.append(event("task_complete"))
        try errorTaskData.write(to: errorTask)
        expect(
            CodexTaskStatusLogParser.parseUpdate(at: errorTask)?.soundEvents == [.error],
            "error emits its own sound event without a completion event"
        )

        let approvalTask = directory.appendingPathComponent("rollout-approval-task.jsonl")
        let approvalCallID = "call-approval"
        var approvalData = event("task_started")
        approvalData.append(permissionRequest(approvalCallID))
        approvalData.append(event("task_complete"))
        try approvalData.write(to: approvalTask)
        let approvalResult = CodexTaskStatusLogParser.parseUpdate(at: approvalTask)
        expect(
            approvalResult?.state == .waitingApproval
                && approvalResult?.soundEvents == [.approvalRequired],
            "unresolved permission request waits for approval without completion sound"
        )
        try functionOutput(approvalCallID).append(to: approvalTask)
        let approvedResult = CodexTaskStatusLogParser.parseUpdate(at: approvalTask)
        expect(
            approvedResult?.state == .running
                && approvedResult?.soundEvents.isEmpty == true,
            "permission output resumes running without another alert"
        )

        let subagentLog = directory.appendingPathComponent("rollout-subagent.jsonl")
        var subagentData = sessionMeta(subagent: true)
        subagentData.append(event("task_started"))
        subagentData.append(event("task_complete"))
        try subagentData.write(to: subagentLog)
        expect(
            CodexTaskStatusLogParser.isSubagentSession(at: subagentLog),
            "subagent session metadata is detected for notification filtering"
        )

        let topLevelLog = directory.appendingPathComponent("rollout-top-level.jsonl")
        try sessionMeta(subagent: false).write(to: topLevelLog)
        expect(
            !CodexTaskStatusLogParser.isSubagentSession(at: topLevelLog),
            "top-level session metadata remains eligible for notifications"
        )

        var subagentLogs: [URL] = []
        for index in 0..<30 {
            let url = directory.appendingPathComponent(
                "rollout-subagent-\(index).jsonl"
            )
            try sessionMeta(subagent: true).write(to: url)
            subagentLogs.append(url)
        }
        let selectedTopLevelFiles = CodexTaskStatusFilePolicy.selectTopLevelFiles(
            from: subagentLogs + [topLevelLog],
            maximumCount: 1
        )
        expect(
            selectedTopLevelFiles == [topLevelLog],
            "subagents do not consume the top-level task file limit"
        )

        if failures > 0 {
            print("\(failures) failure(s)")
            exit(1)
        }
        print("all CodexTaskStatusLogParserTests passed")
    }
}

private extension Data {
    func append(to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: self)
    }
}

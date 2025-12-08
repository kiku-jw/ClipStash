# Unit Tests Implementation Plan (TDD)

Branch: `feature/unit-tests`

## Micro-Tasks (2-5 min each)

### Task 1: Test Infrastructure Setup
- [x] Create `ClipStashTests` target in Xcode project
- [x] Create `ClipStashTests.swift` with basic XCTest import
- [x] Verify test target builds

### Task 2: StorageManager — Insert & Fetch (RED)
- [x] Write test `testInsertTextItem` — insert text, verify returned ID > 0
- [x] Run test, confirm FAILS (no in-memory DB setup)

### Task 3: StorageManager — Insert & Fetch (GREEN)
- [x] Create in-memory SQLite for tests (`:memory:`)
- [x] Run test, confirm PASSES

### Task 4: StorageManager — Deduplication (RED → GREEN)
- [x] Write test `testDeduplication` — insert same hash twice, verify 1 item
- [x] Implement/verify dedup works, confirm PASSES

### Task 5: StorageManager — Eviction (RED → GREEN)
- [x] Write test `testEviction` — insert 10, limit 5, verify 5 remain
- [x] Confirm PASSES

### Task 6: StorageManager — Search FTS5 (RED → GREEN)
- [x] Write test `testSearch` — insert 3 items, search, verify match
- [x] Confirm PASSES

### Task 7: StorageManager — Paging (RED → GREEN)
- [x] Write test `testPaging` — insert 20, fetch 10 offset 0, then 10 offset 10
- [x] Confirm PASSES

### Task 8: ExportService — Markdown Format (RED → GREEN)
- [x] Write test `testMarkdownGeneration` — export 1 item, verify format
- [x] Confirm PASSES

### Task 9: ExportService — Auto-Split (RED → GREEN)
- [x] Write test `testAutoSplit` — export large content, verify multiple files
- [x] Confirm PASSES

### Task 10: ClipboardMonitor — Hash Computation
- [x] Write test `testHashComputation` — same input = same hash
- [x] Confirm PASSES

---

## Verification
```bash
xcodebuild test -project ClipStash.xcodeproj -scheme ClipStash -destination 'platform=macOS'
```

## Commit Strategy
- Commit after each GREEN phase
- Message: `test: add [test name]`

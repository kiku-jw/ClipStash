## 2024-05-23 - Blocking Main Actor with CPU bound work
**Learning:** Even if a function is called within an `async` method, if it's on an actor (like `@MainActor`), synchronous CPU-bound work (like SHA256 hashing) will block that actor.
**Action:** Always move expensive CPU operations to `Task.detached` or a non-isolated async function to ensure they run on a background thread and don't block the UI.

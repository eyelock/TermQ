# Tutorial: MCP resource subscriptions

A long-running assistant connected to `termqmcp` can subscribe to a TermQ resource and react when the user changes the board in the GUI. This is the spec feature that turns MCP from a polling API into an event-driven one.

This tutorial walks through:
- What "subscribe" actually does
- How TermQ implements it
- **Which clients can actually use it** (not all of them)
- A worked example: a session-summariser that updates whenever pending work changes
- Step-by-step verification with MCP Inspector
- Limits and known sharp edges

## Client compatibility — read this first

MCP defines `resources/subscribe`, but **not every MCP client proxies that primitive through to the LLM**. The server side of TermQ works correctly — subscriptions register, the file watcher arms, and `notifications/resources/updated` events are emitted on the wire. Whether the assistant *sees* those notifications depends on the client.

| Client | Subscribes? | Notes |
|---|---|---|
| **MCP Inspector** | Yes — full | Subscribe button in the Resources tab; notifications appear in the events panel. Best for verifying the wire protocol. |
| **Custom MCP SDK client** (TS/Python) | Yes — full | The TypeScript SDK's `client.resources.subscribe(...)` + `onResourceUpdated` handler delivers notifications. Build your own daemon this way. |
| **Claude Code** (v2.x) | **No** | Only exposes `ReadMcpResourceTool` / `ListMcpResourcesTool` to the model. `subscribe` is not surfaced. The model can read resources on demand but cannot receive push updates. |
| **Claude Desktop** | Partial | Subscribes at the transport level but does not surface change notifications to the conversation. Treat as read-only for the assistant. |

**Practical consequence:** if you want to verify subscriptions end-to-end with a real user-facing assistant, use Inspector or roll a custom SDK script. The 6-step "set next action → assistant reacts" pattern below is what subscriptions *enable* — but you can only observe it working in clients that proxy the notification through.

## What "subscribe" means in MCP

The MCP spec defines two complementary methods:

- `resources/subscribe { uri }` — client asks the server to send change notifications for one URI
- `resources/unsubscribe { uri }` — cancel

When the underlying resource changes, the server emits a `notifications/resources/updated { uri }` notification (JSON-RPC notification, no response expected). The client decides what to do: re-fetch the resource, summarise it, ignore it, etc.

The subscription survives until the client either unsubscribes or disconnects. The server is not required to remember subscriptions across restarts.

## How TermQ implements it

The server declares `resources: { subscribe: true }` in its capabilities. Internally, it holds a `ResourceSubscriptionManager` actor with three responsibilities:

1. **Tracking subscribed URIs** — a `Set<String>` populated by `subscribe` / drained by `unsubscribe`.
2. **Watching the data file** — a `DispatchSourceFileSystemObject` watches `board.json` for `.write`, `.extend`, `.delete`, and `.rename` events.
3. **Debouncing emissions** — when a change fires, the manager waits 150ms before emitting. Atomic writes replace the file inode, so a single user action can fire `.delete` + new-file events in quick succession; debouncing collapses these into one notification per subscribed URI.

When the file changes and the debouncer fires, the server sends a `notifications/resources/updated` for every URI in the subscription set. It doesn't try to be clever about which URI's contents actually changed — that's the subscriber's job. If you subscribed to `termq://terminals` but only the pending count changed, you still get the notification.

## Worked example: a pending-aware assistant

Here's a minimal client (pseudocode — TypeScript-style with the MCP SDK):

```typescript
import { MCPClient } from "@modelcontextprotocol/sdk";

const client = new MCPClient({ name: "termq-watcher", version: "1.0.0" });
await client.connect({ transport: stdioTransport("termqmcp") });

// 1. Subscribe to the pending feed.
await client.resources.subscribe({ uri: "termq://pending" });

// 2. Handle change notifications.
client.notifications.onResourceUpdated(async ({ uri }) => {
    if (uri !== "termq://pending") return;
    const result = await client.resources.read({ uri });
    const pending = JSON.parse(result.contents[0].text);
    console.log(`Pending changed — ${pending.summary.withNextAction} terminals now have actions queued`);
});

// 3. Stay connected.
await client.waitForever();
```

Now any time the user moves a card in the TermQ GUI, queues an action on a terminal, or runs another tool that mutates the board, this client gets a notification and re-renders.

## Sharp edges (read these)

### Your own writes notify you back

If the same MCP client calls `set` (which mutates board.json), the file change fires the watcher, and that client gets a `resources/updated` for its own write. This is by design for v1 — subscribers should track their own causal writes (e.g. via an ETag or `lastModified`) and no-op on stale ones.

A future revision can thread a skip-notification token through `BoardWriter` for true self-write filtering.

### Debouncing means you can miss intermediate states

The 150ms debounce window collapses bursts of writes. If three writes land within that window, you get **one** notification, not three. The latest state is always reflected in the resource — you never get stale data — but if you were trying to count writes by counting notifications, that's the wrong shape.

### Subscriptions are per-connection

If you disconnect and reconnect, your subscriptions are gone. Re-subscribe at the start of each session.

### Notifications are best-effort

If the transport stutters at the wrong moment the server logs a warning and drops the notification — the file content is still accurate when the subscriber next reads it. Don't build state machines that require every notification to arrive.

## What URIs are worth subscribing to?

| URI | Useful for |
|---|---|
| `termq://pending` | Most common — react when the user queues work or clears it |
| `termq://terminals` | React to any card change anywhere on the board |
| `termq://columns` | React to column CRUD only — usually overkill |
| `termq://terminal/{id}` | Watch one specific card — useful for a per-card daemon |

## Combining with `record_handshake`

The natural pattern for an assistant inside a TermQ session:

```
1. Subscribe to termq://terminal/${TERMQ_TERMINAL_ID}
2. Receive a notification when the user queues work
3. Read the resource → llmNextAction is set
4. Process the action
5. Call record_handshake(id: $TERMQ_TERMINAL_ID)
6. Call set(llmNextAction: "") to clear it
7. Wait for the next notification
```

Steps 5 and 6 should be separate calls — `record_handshake` is the explicit "I touched this" signal, and `set(llmNextAction: "")` is the "I consumed the queued work" signal. Combining them in one tool would re-introduce the side-effect-on-read pattern that Tier 1b deliberately split apart.

**This is the pattern subscriptions enable** — but as noted above, only clients that proxy `resources/subscribe` to the LLM can actually wake on step 2. In Claude Code today the assistant only sees the queued action when the user prompts it to read; the rest of the steps still work.

## Verifying subscriptions with MCP Inspector

The cleanest way to see the full pattern fire. Requires `make mcp.inspect` (launches `@modelcontextprotocol/inspector` against the debug `termqmcp` binary).

**Test 1 — push notification on board change**

1. Open TermQ (Debug for the development binary). Note a card's UUID.
2. `make mcp.inspect` → connect → **Resources** tab → enter `termq://terminal/<uuid>` → **Subscribe**.
3. In the TermQ GUI, right-click that card → **Set next action…** → enter "test action".
4. Within ~150 ms, Inspector's events panel shows `notifications/resources/updated` with that URI.
5. Click **Read** on the resource — `llmNextAction` reflects the new value.

If step 4 doesn't fire, `tail -f /tmp/termq-debug.log | grep SubscriptionManager` will show whether the watcher armed and the debouncer fired.

**Test 2 — debounce collapses bursts**

1. Still subscribed. Rapidly change `llmNextAction` three times in <100 ms.
2. Inspector receives **one** notification. The resource read returns the final value.

**Test 3 — unsubscribe stops the stream**

1. Click **Unsubscribe**.
2. Make another change in the GUI.
3. No notification arrives.

**Test 4 — full handshake round-trip**

1. Re-subscribe.
2. GUI: set `llmNextAction: "say hello"`. Inspector receives notification.
3. Inspector → **Tools** → `record_handshake { identifier: "<uuid>" }` (this *itself* fires the watcher — that's the self-write notification documented above).
4. Inspector → **Tools** → `set { identifier: "<uuid>", llmNextAction: "" }`.
5. In the GUI, the card's `lastHandshake` timestamp updates and the queued action is cleared.

If all four tests pass, the subscription stack is healthy end-to-end and any compatible client will see the same behaviour.

## Further reading

- [MCP spec, resources/subscribe](https://modelcontextprotocol.io/specification/2025-11-25/server/resources/#subscriptions)
- `Sources/MCPServerLib/SubscriptionManager.swift` — the implementation
- [MCP Reference](../reference/mcp.md) — full tool / resource catalogue

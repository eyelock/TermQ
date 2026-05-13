# Tutorial: MCP resource subscriptions

A long-running assistant connected to `termqmcp` can subscribe to a TermQ resource and react when the user changes the board in the GUI. This is the spec feature that turns MCP from a polling API into an event-driven one.

This tutorial walks through:
- What "subscribe" actually does
- How TermQ implements it
- A worked example: a session-summariser that updates whenever pending work changes
- Limits and known sharp edges

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
2. Read the resource → has llmNextAction set
3. Process the action
4. Call record_handshake(id: $TERMQ_TERMINAL_ID)
5. Call set(llmNextAction: "") to clear it
6. Wait for the next notification
```

Steps 4 and 5 should be separate calls — `record_handshake` is the explicit "I touched this" signal, and `set(llmNextAction: "")` is the "I consumed the queued work" signal. Combining them in one tool would re-introduce the side-effect-on-read pattern that Tier 1b deliberately split apart.

## Further reading

- [MCP spec, resources/subscribe](https://modelcontextprotocol.io/specification/2025-11-25/server/resources/#subscriptions)
- `Sources/MCPServerLib/SubscriptionManager.swift` — the implementation
- [MCP Reference](../reference/mcp.md) — full tool / resource catalogue

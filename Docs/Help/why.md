# Why TermQ

You probably already have a terminal app you're happy with. So why would you add something on top of it?

## The problem with terminal sessions

Terminals are ephemeral by design. Open a tab, run something, close it — or forget to close it. By the end of a busy day you might have a dozen sessions open: one running a dev server, one mid-migration, one with a half-finished test run, three you're not sure about.

The window titles don't help. "bash", "zsh", "node" — they tell you what's running, not *what it's for*.

And when you come back tomorrow? The context is gone. Which terminal had the thing you were debugging? What was that server command? What were you even working on?

## The shift: terminals as work

TermQ is built on a simple idea: **every terminal session is a piece of work**, not just a window.

When you treat terminals as work items, they get all the things work items get:

- A **name** ("API Server — prod debug") instead of "bash"
- A **description** of what this session is actually for
- A **column** that represents its current status (To Do, In Progress, Blocked, Done)
- **Tags** that carry structured context (`env=prod`, `project=myrepo`)
- Metadata that **persists** — the card is still there tomorrow, exactly as you left it

![TermQ Board View](Images/board-view.png)

That's the board. At a glance you can see everything you're working on, where it stands, and what's waiting.

## What this changes

The most obvious change is visual: you can see all your work at once, organized into whatever stages make sense for you. But the deeper change is in how you think about terminal sessions.

When a session has a name and a column, you make a deliberate decision to move it. "Done" means you finished, not just that the window closed. "Blocked" means something is waiting on someone else, and you can see that at a glance next week.

Sessions with context are sessions you can hand off — to a colleague, or to an AI assistant that can read the board and understand what each terminal is for and what it needs next.

## What TermQ is not

TermQ doesn't replace your terminal emulator. It uses your shell and runs your programs exactly as it always has. It adds a layer on top that gives your sessions names, context, and a place to live.

It's also not a project management tool. The board is for your current work — not a backlog of tickets. Keep it to what's actually open on your machine right now.

## Where to go from here

**Ready to try it?** → [Tutorial 1: Your First Board](tutorials/first-board.md)

**Just want to see what it can do?** → [Overview](README.md)

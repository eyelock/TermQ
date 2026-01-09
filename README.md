# TermQ

A Kanban-style terminal queue manager for macOS. Organize multiple terminal sessions in a visual board layout, drag them between columns, and never lose track of your running tasks.

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Screenshots](#screenshots)
- [Installation](#installation)
- [Usage](#usage)
  - [GUI Application](#gui-application)
  - [Keyboard Shortcuts](#keyboard-shortcuts)
  - [CLI Tool](#cli-tool)
- [Configuration](#configuration)
- [Contributing](#contributing)
- [License](#license)

## Features

- **Kanban Board Layout** - Organize terminals in customizable columns (To Do, In Progress, Blocked, Done)
- **Persistent Sessions** - Terminal sessions persist when navigating between views
- **Pinned Terminals** - Pin frequently-used terminals for quick access via tabs in focus mode
- **Rich Metadata** - Add titles, descriptions, and key=value tags to each terminal
- **Drag & Drop** - Move terminals between columns with drag and drop
- **Keyboard Shortcuts** - Quick terminal creation and navigation with standard shortcuts
- **Shell Environment** - Full access to your shell configuration (.zshrc, .bashrc)
- **CLI Tool** - Open new terminals from the command line with `termq open`

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode Command Line Tools (for building from source)

## Screenshots

### Queue Window

![TermQ Queue Window](./Docs/Images/termq-queue-view.png "TermQ Queue Window showing the default Kanban like columns")

### Terminal Focussed

![TermQ Terminal Focussed](./Docs/Images/termq-terminal-focussed.png "TermQ Terminal Focussed with navigation back to the board")

### New Terminal

![TermQ New Terminal](./Docs/Images/termq-new-terminal.png "TermQ New Terminal showing the options available to enter")

### Managing Columns

![TermQ Managing Columns](./Docs/Images/termq-queue-new.png "TermQ Managing Columns showing that you can add/edit your own columns")

## Installation

### From Release (Recommended)

1. Download the latest `TermQ-{version}.zip` from [Releases](../../releases)
2. Unzip and move `TermQ.app` to your Applications folder
3. Right-click and select "Open" on first launch (required for unsigned apps)

### From Source

```bash
git clone https://github.com/eyelock/termq.git
cd termq
make sign
open TermQ.app
```

See the [Contributing Guide](./CONTRIBUTING.md) for detailed build instructions.

### CLI Tool

The `termq` command lets you open terminals from the command line:

```bash
# Install after building
make install

# Or manually
cp .build/release/termq /usr/local/bin/
```

## Usage

### GUI Application

1. Launch `TermQ.app`
2. Click the **+** button in the toolbar to add a new terminal or column
3. Click on a terminal card to open it in full view
4. Right-click cards for options (Edit, Delete)
5. Drag cards between columns to organize your workflow
6. Use the column menu (⋯) to rename or delete columns
7. Pin terminals with the ⭐ button to access them quickly via tabs

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘T | Quick new terminal (same column and working directory as current) |
| ⌘N | New terminal with dialog |
| ⌘⇧N | New column |
| ⌘D | Toggle pin on current terminal |
| ⌘] | Next pinned terminal |
| ⌘[ | Previous pinned terminal |

### CLI Tool

```bash
# Open a new terminal in the current directory
termq open

# Open with a specific name and description
termq open --name "API Server" --description "Running the backend"

# Open in a specific column
termq open --column "In Progress"

# Open with tags
termq open --name "Build" --tag env=prod --tag version=1.0

# Open in a specific directory
termq open --path /path/to/project
```

## Configuration

The app stores its data at:

```
~/Library/Application Support/TermQ/board.json
```

This JSON file contains all columns, cards, and their metadata. You can back it up or edit it manually if needed.

## Contributing

Contributions are welcome! See the [Contributing Guide](./CONTRIBUTING.md) for:

- Development setup
- Project structure
- Building and testing
- Release process

## License

MIT License - See [LICENSE](LICENSE) for details.

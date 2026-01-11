# CLI Tool

> NOTE: Sorry, currently this isn't working!!!

## Installation

The `termq` CLI tool lets you open terminals from your shell.

```bash
# Install after building
make install

# Or manually copy
cp .build/release/termq /usr/local/bin/
```

## Usage Examples

```bash
# Open in current directory
termq open

# Open with name and description
termq open --name "API Server" --description "Backend"

# Open in specific column
termq open --column "In Progress"

# Open with tags
termq open --name "Build" --tag env=prod --tag version=1.0

# Open in specific directory
termq open --path /path/to/project
```

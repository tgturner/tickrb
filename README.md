# TickRb

A Ruby gem that provides TickTick integration through a Model Context Protocol (MCP) server, enabling Claude and other AI assistants to manage your TickTick tasks seamlessly.

## Quick Start

1. **Install the gem**: `gem install tickrb`
2. **Get TickTick credentials** from [TickTick Developer Console](https://developer.ticktick.com/)
3. **Configure Claude** with your credentials in MCP config
4. **Authenticate**: The first time Claude starts TickRb MCP server, it will prompt for OAuth.
5. **Start chatting** with Claude about your tasks!

## Installation

    $ gem install tickrb

## Setup

Before using TickRb, you need to create a TickTick application to get OAuth credentials:

1. Go to [TickTick Developer Console](https://developer.ticktick.com/)
2. Create a new application
3. Note your `Client ID` and `Client Secret`
4. Set the redirect URI to `http://localhost:8080/callback`

## Usage

After installing the MCP server, the first usage will open a browser window to authenticate with ticktick.

### Claude Desktop Configuration

For Claude Desktop, add this to your MCP settings file:

**macOS**: `~/Library/Application Support/Claude/claude_desktop_config.json`

```json
{
  "mcpServers": {
    "tickrb": {
      "command": "tickrb-mcp-server",
      "args": [
        "--client-id", "your_ticktick_client_id",
        "--client-secret", "your_ticktick_client_secret"
      ]
    }
  }
}
```

### Claude Code (CLI) Configuration

For Claude Code, add the MCP server to your configuration:

```bash
# Add the MCP server with credentials
claude-code mcp install tickrb tickrb-mcp-server --client-id your_ticktick_client_id --client-secret your_ticktick_client_secret
```

### Available MCP Tools

Once connected to Claude, you can use these natural language commands:

- **"List my tasks"** - Shows all your TickTick tasks
- **"Create a task called 'Buy groceries'"** - Creates a new task
- **"Complete the task with ID xyz"** - Marks a task as complete
- **"Delete the task with ID xyz"** - Removes a task
- **"Show my projects"** - Lists all your TickTick projects

## Configuration

### Token Storage

Authentication tokens are stored in `~/.config/tickrb/token.json`.

### Command Line Help

To see all available options:

```bash
tickrb-mcp-server --help
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. 

### Running Tests

```bash
# Run all tests
bundle exec rake spec

# Run complete pipeline (tests + linting + type checking)
bundle exec rake ci

# Run individual quality checks
bundle exec rake test      # Tests only
bundle exec rake lint      # Linting only  
bundle exec rake typecheck # Type checking only
bundle exec rake fix       # Auto-fix linting issues
```

### Type Checking

This gem uses [Sorbet](https://sorbet.org/) for static type checking. Common Sorbet commands:

- `bundle exec rake typecheck` - Run type checker
- `bundle exec rake rbi` - Update RBI files

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

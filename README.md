# market-research

Deep market research using **z.ai GLM-5** for cost-efficient iterative agentic research.

## What This Is

A repository that contains the **market-research skill** for OpenClaw, configured to use z.ai's GLM-5 model. This keeps the skill in version control and makes it maintainable.

## Why z.ai?

| Model | Input | Output | vs Claude |
|-------|-------|--------|-----------|
| **GLM-5** | $1.00/1M | $3.20/1M | ~**3x cheaper** |
| **GLM-4.7** | $0.60/1M | $2.20/1M | ~**5x cheaper** |
| **GLM-4.5-Air** | $0.20/1M | $1.10/1M | ~**10x cheaper** |
| Web Search Tool | $0.01/query | — | Built-in |

## Repository Structure

```
.claude/settings.json    # Repo-specific z.ai config (isolated from global Claude)
skill/
  SKILL.md              # Full skill documentation
  research.sh           # Bash entrypoint
  lib/
    zai-client.sh       # z.ai API client functions
    agents.sh           # Sub-agent spawning logic
    synthesis.sh        # Findings merger
README.md               # This file
```

## Usage

### Prerequisites

1. Get a z.ai API key from [z.ai/model-api](https://z.ai/model-api)
2. Set it as an environment variable:
   ```bash
   export ZAI_API_KEY="your_key_here"
   ```

### Running Research

From OpenClaw (your main Claude session):

```
/market-research "AI agent deployment platforms" --depth standard --focus competitors
```

This will:
1. Spawn GLM-5 sub-agents (configured via `.claude/settings.json` in this repo)
2. Those agents use z.ai's endpoint
3. Your main Claude session stays on Anthropic

### Depth Levels

| Mode | Agents | Time | Est. Cost |
|------|--------|------|-----------|
| shallow | 1 | 5-10 min | $0.50-1.50 |
| standard | 3 | 10-20 min | $1.50-3.00 |
| deep | 5 | 20-40 min | $3.00-6.00 |

### Focus Areas

- `all` — Comprehensive market analysis
- `competitors` — Top players, positioning, strengths/weaknesses
- `trends` — Market size, growth, emerging trends
- `pricing` — Pricing models, tiers, willingness to pay
- `customers` — Segments, personas, pain points
- `gaps` — Unserved needs, whitespace opportunities

## How the Isolation Works

**Your global Claude Code** (`~/.claude/settings.json`):
- Stays on Anthropic (Opus/Sonnet)
- No z.ai configuration
- Completely unaffected

**This repository's Claude Code** (`.claude/settings.json`):
- Uses z.ai endpoint
- Only applies when running in this directory
- Sub-agents spawned from here inherit this config

The `ANTHROPIC_AUTH_TOKEN` uses `${ZAI_API_KEY}` — it references your environment variable, so you set it once and it works here without touching global config.

## Developing This Skill

### Running Locally

```bash
cd ~/dev/market-research
claude  # This launches with z.ai config from .claude/settings.json
```

### Testing Changes

1. Make edits to files in `skill/`
2. Test with a research query
3. Commit and push: `git push origin main`
4. OpenClaw pulls the latest skill from this repo

### Claude Code Integration

When you run `claude` in this directory, it uses z.ai automatically. This is useful for:
- Testing the skill directly
- Debugging research queries
- Developing new features

To verify: run `/status` in Claude Code — it should show you're using GLM-5.

## Cost Tracking

The skill tracks estimated costs and reports them:
- Token usage (input/output)
- Web search calls ($0.01 each)
- Per-agent and total cost

Costs are logged to `logs/costs/` for analysis.

## Future Roadmap

- [ ] Cached research (avoid re-researching same topics)
- [ ] Scheduled monitoring (monthly market updates via cron)
- [ ] Competitive alerts (new entrants, price changes)
- [ ] Export integrations (Google Sheets, Notion, Airtable)
- [ ] Source credibility scoring
- [ ] Multi-language research

## See Also

- [z.ai Documentation](https://docs.z.ai)
- [GLM-5 Model Card](https://docs.z.ai/guides/llm/glm-5)
- [z.ai Pricing](https://docs.z.ai/guides/overview/pricing)
- [Claude Code + z.ai Guide](https://docs.z.ai/devpack/tool/claude)

## License

MIT — Same as GLM-5 itself

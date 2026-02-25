---
name: market-research
description: "Deep market research using iterative agentic loops with z.ai GLM-5. Spawns parallel research agents that search, synthesize, and analyze cost-efficiently. Usage: /market-research <topic> [--depth shallow|standard|deep] [--focus competitors|trends|pricing|customers|gaps|all] [--output markdown|json|brief]"
user-invocable: true
metadata:
  { "openclaw": { "requires": { "bins": ["curl", "jq"], "primaryEnv": "ZAI_API_KEY" } } }
---

# market-research — Deep Market Research with z.ai GLM-5

Iterative research using **z.ai GLM-5** sub-agents. 3x cheaper than Claude for the same depth.

## Overview

This skill conducts comprehensive market research by spawning **z.ai GLM-5 sub-agents** that iteratively search, synthesize, and analyze. You (the orchestrator) stay on Claude; the sub-agents do the heavy lifting on z.ai.

**Why z.ai?**
- GLM-5: $1.00/$3.20 per 1M tokens vs Claude's ~$3/$15
- Built-in web search: $0.01 per query
- 200K context window for massive synthesis
- Native agentic capabilities

## Architecture

```
You (Claude, Anthropic) — orchestrator
  ↓
OpenClaw spawns sub-agents with model: zai/glm-5
  ↓
Sub-agents use .claude/settings.json (z.ai endpoint)
  ↓
Research loops: search → synthesize → identify gaps → search again
  ↓
Results back to you
```

**Your global Claude Code config stays on Anthropic.** Only sub-agents spawned from this repo use z.ai.

## Phase 1 — Parse Arguments

| Flag | Default | Description |
|------|---------|-------------|
| topic (positional) | required | Market/topic to research |
| --depth | standard | shallow (1 agent, 2 loops) / standard (3 agents, 4 loops) / deep (5 agents, 6+ loops) |
| --focus | all | competitors, trends, pricing, customers, gaps, all |
| --output | markdown | markdown, json, brief |
| --max-cost | 5 | Max USD spend (safety limit) |
| --cache | true | Use cached results if < 7 days old |

**Depth determines agents and loops:**
- shallow: 1 agent, 2 loops, ~$0.50-1.50, 5-10 min
- standard: 3 agents, 4 loops, ~$1.50-3.00, 10-20 min
- deep: 5 agents, 6 loops, ~$3.00-6.00, 20-40 min

## Phase 2 — Check Cache

Before spawning agents, check if recent research exists:

```
Cache location: ~/.openclaw/workspace-dev/.research-cache/<hash>.json
TTL: 7 days (configurable)
Hash: SHA256 of normalized topic + depth + focus
```

If cache hit and --cache is true:
- Return cached results immediately
- Cost: $0
- Report: "Using cached research from <date>"

## Phase 3 — Configure Research Plan

Based on `--focus`, create parallel research tracks:

| Focus | Agent Count | Research Objectives |
|-------|-------------|-------------------|
| competitors | 1-2 | Top 5-10 players, positioning, strengths, weaknesses, market share |
| trends | 1 | Market size, growth rate, emerging trends, regulatory/tech shifts |
| pricing | 1 | Pricing models, tiers, freemium vs premium, deal sizes, willingness to pay |
| customers | 1 | Target segments, buyer personas, pain points, decision makers, use cases |
| gaps | 1 | Unserved needs, whitespace opportunities, competitive vulnerabilities |
| all | 3-5 | All of the above (standard = 3, deep = 5) |

Generate research plan with:
- Initial search queries (5-10 per agent)
- Follow-up query templates
- Synthesis checkpoints
- Output schema

## Phase 4 — Spawn Iterative Research Sub-agents

Spawn agents in parallel (up to `subagents.maxConcurrent`):

```bash
sessions_spawn(
  task="<full research prompt>",
  model="zai/glm-5",  # ← This is the key: forces z.ai
  runTimeoutSeconds=1800,
  cleanup="keep"
)
```

### Sub-Agent Research Loop (per agent)

**Loop 1: Discovery**
- Execute 5-10 parallel web searches
- Search patterns by focus:
  - competitors: `"{topic} top companies"`, `"{topic} vs {competitor}"`, `"{topic} market share"`
  - trends: `"{topic} market size 2024 2025"`, `"{topic} industry trends"`, `"{topic} growth forecast"`
  - pricing: `"{topic} pricing"`, `"{topic} cost comparison"`, `"{topic} subscription plans"`
  - customers: `"{topic} customer reviews"`, `"{topic} case studies"`, `"{topic} user testimonials"`
- Extract key findings with source URLs
- Tag confidence (high/medium/low)

**Loop 2+: Deep Dive**
- Synthesize Loop 1 findings
- Identify gaps: "What do we still need to know?"
- Generate 2-4 follow-up queries
- Execute follow-up searches
- Cross-reference sources for validation
- Flag contradictory information

**Final Loop: Synthesis**
- Structure all findings by category
- Include source citations
- Flag confidence levels
- Note remaining information gaps
- Estimate cost consumed

### Sub-Agent Output Format

Each agent returns:

```json
{
  "agent_id": "competitors-1",
  "focus": "competitors",
  "sources_count": 12,
  "loops_completed": 4,
  "findings": {
    "competitors": [
      {
        "name": "Company Name",
        "positioning": "...",
        "strengths": ["...", "..."],
        "weaknesses": ["...", "..."],
        "pricing": "...",
        "market_share": "..."
      }
    ],
    "trends": ["...", "..."],
    "pricing_insights": {...},
    "customer_insights": {...},
    "gaps": ["...", "..."]
  },
  "sources": [
    {"url": "...", "title": "...", "date": "...", "confidence": "high"}
  ],
  "confidence": "high|medium|low",
  "gaps_remaining": ["..."],
  "cost_estimate": "$2.34",
  "tokens_used": {"input": 15000, "output": 45000}
}
```

## Phase 5 — Synthesize & Deliver

After all sub-agents complete:

1. **Collect** JSON outputs from each agent
2. **Resolve conflicts** — if agents found contradictory info, flag for review
3. **Merge** into unified structure
4. **Format** per `--output`:

### Markdown Output (default)

```markdown
# Market Research: {TOPIC}

## Executive Summary
[2-3 paragraphs with key takeaways, confidence level, date]

## Market Landscape
### Size & Growth
- Market size: $X (source, date)
- CAGR: X% (source, date)
- Key drivers: ...

### Competitive Landscape
| Company | Position | Strengths | Weaknesses | Pricing | Market Share |
|---------|----------|-----------|------------|---------|--------------|
| ... | ... | ... | ... | ... | ... |

### Key Trends
1. **[Trend name]** — Evidence... (source)
2. **[Trend name]** — Evidence... (source)

## Customer Insights
### Target Segments
### Pain Points
### Decision Criteria

## Pricing Analysis
### Pricing Models
### Tiers & Packages
### Willingness to Pay

## Opportunities & Gaps
[Whitespace analysis]

## Methodology
- Agents: {N}
- Loops: {N} per agent
- Sources: {N} total
- Research date: {date}
- Confidence: {high/medium/low}
- Cost: ${amount}

## Sources
[Citations with URLs and access dates]

---
*Research by market-research skill using z.ai GLM-5*
```

### JSON Output

Machine-readable with full data structure for programmatic use.

### Brief Output

1-page executive summary only (market size, top 3 competitors, 3 key trends, top opportunity).

## Phase 6 — Cache Results

Write to cache for future use:

```bash
~/.openclaw/workspace-dev/.research-cache/<hash>.json
```

Includes:
- Full findings
- Sources
- Metadata (date, cost, confidence)

## Cost Tracking & Safety

### Per-Agent Tracking
Each agent reports:
- Input/output tokens
- Web search calls
- Estimated cost

### Global Safety
- `--max-cost` enforces hard limit
- If cost approaches limit, pause and ask for confirmation
- Never exceed max-cost without explicit user approval

### Cost Reporting
Final output includes:
- Total estimated cost
- Cost breakdown by agent
- Comparison to Claude-equivalent cost

## Repository Config (.claude/settings.json)

```json
{
  "env": {
    "ANTHROPIC_AUTH_TOKEN": "${ZAI_API_KEY}",
    "ANTHROPIC_BASE_URL": "https://api.z.ai/api/anthropic",
    "API_TIMEOUT_MS": "3000000"
  }
}
```

This is **repo-specific config** — it only applies when Claude Code runs in this directory. Your global `~/.claude/settings.json` stays on Anthropic.

## Error Handling

| Error | Response |
|-------|----------|
| ZAI_API_KEY missing | Prompt user, stop |
| API rate limit | Exponential backoff retry |
| Agent timeout | Spawn replacement with reduced scope |
| Cost limit reached | Pause, ask for confirmation |
| All agents fail | Fall back to cached research or report failure |
| Contradictory findings | Flag in output, present both sides |

## Example Usage

```
# Deep competitive analysis
/market-research "AI coding assistants" --depth deep --focus competitors

# Quick pricing scan
/market-research "CRM software for SMBs" --depth shallow --focus pricing

# Full market landscape with JSON output
/market-research "vertical AI for legal" --depth standard --focus all --output json

# Bypass cache, force fresh research
/market-research "AI agents market" --depth standard --cache false

# Tight cost control
/market-research "devops tools" --depth shallow --max-cost 1
```

## Integration Notes

### With Claude Code (this repo)

When you run `claude` in this directory:
```bash
cd ~/dev/market-research
claude
```

It automatically uses z.ai because of `.claude/settings.json`. Verify with `/status`.

### With OpenClaw

OpenClaw spawns sub-agents with `model: zai/glm-5`, which routes through this repo's config.

### With gh-issues Skill

Can be combined:
```
/gh-issues recursive-systems/market-research --model zai/glm-5
```

## Maintenance

### Updating the Skill

1. Edit files in this repo
2. Test: `claude` (in this dir) → run research
3. Commit: `git add . && git commit -m "..."`
4. Push: `git push origin main`
5. OpenClaw automatically uses latest

### Adding New Focus Areas

1. Add to `--focus` enum in SKILL.md
2. Add research logic in `lib/agents.sh`
3. Add output schema in synthesis
4. Update README examples

### Monitoring Costs

Check logs:
```bash
ls -la logs/costs/
cat logs/costs/2026-02-25.json
```

## Development Roadmap

- [ ] v1.1: Caching with TTL
- [ ] v1.2: Scheduled re-research (cron integration)
- [ ] v1.3: Competitive alerts (diff detection)
- [ ] v1.4: Export to Sheets/Notion
- [ ] v1.5: Source credibility scoring
- [ ] v2.0: Multi-agent debate mode (agents critique each other's findings)

---

**Cost comparison for typical research task:**
- Claude (Opus): ~$10-15
- z.ai GLM-5: ~$3-5
- **Savings: 60-75%**

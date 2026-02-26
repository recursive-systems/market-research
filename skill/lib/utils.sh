#!/bin/bash
#
# lib/utils.sh — Utility functions
#

# Colors (disable if not TTY)
if [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  CYAN='\033[0;36m'
  NC='\033[0m'
else
  RED=''
  GREEN=''
  YELLOW=''
  BLUE=''
  CYAN=''
  NC=''
fi

# Logging functions
log() { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $*"; }
info() { echo -e "${GREEN}→${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*" >&2; }
error() { echo -e "${RED}✗${NC} $*" >&2; }
verbose() { [[ "$VERBOSE" == "true" ]] && echo -e "${CYAN}ℹ${NC} $*"; return 0; }

# Show help
show_help() {
  cat << 'EOF'
Usage: research.sh <topic> [options]

Market research using z.ai GLM-5 — cost-efficient iterative agentic research.

Arguments:
  topic                    The market or topic to research (required)

Options:
  --depth MODE             Research depth: shallow|standard|deep (default: standard)
  --focus AREA             Focus: all|competitors|trends|pricing|customers|gaps
  --output FORMAT          Output: markdown|json|brief|pdf (default: markdown)
  --max-cost USD           Max spend limit (default: 5)
  --cache true|false       Use cached results (default: true)
  --discord-channel ID     Discord channel to send PDF report to
  --verbose, -v            Show detailed progress
  --help, -h               Show this help

Examples:
  research.sh "AI coding assistants" --depth deep --focus competitors
  research.sh "CRM market" --depth shallow --focus pricing --max-cost 2
  research.sh "vertical AI" --depth standard --output json
  research.sh "SaaS market" --depth standard --output pdf --discord-channel 1475880024111583243

PDF Output:
  Use --output pdf to generate a styled PDF report.
  Combine with --discord-channel to automatically send to Discord.
  Requires wkhtmltopdf or pandoc for PDF generation.

Environment:
  ZAI_API_KEY              Required. Get from https://z.ai/model-api

Cost Estimates:
  shallow:  ~$0.50-1.50  (1 agent, 2 loops, 5-10 min)
  standard: ~$1.50-3.00  (3 agents, 4 loops, 10-20 min)
  deep:     ~$3.00-6.00  (5 agents, 6 loops, 20-40 min)
EOF
}

# Configure based on depth
configure_depth() {
  local depth="$1"
  case $depth in
    shallow)
      AGENT_COUNT=1
      LOOPS_PER_AGENT=2
      QUERIES_PER_LOOP=5
      EST_COST_MIN=0.50
      EST_COST_MAX=1.50
      ;;
    standard)
      AGENT_COUNT=3
      LOOPS_PER_AGENT=4
      QUERIES_PER_LOOP=8
      EST_COST_MIN=1.50
      EST_COST_MAX=3.00
      ;;
    deep)
      AGENT_COUNT=5
      LOOPS_PER_AGENT=6
      QUERIES_PER_LOOP=10
      EST_COST_MIN=3.00
      EST_COST_MAX=6.00
      ;;
    *)
      error "Invalid depth: $depth (must be shallow|standard|deep)"
      exit 1
      ;;
  esac
}

# Generate cache hash (macOS compatible)
generate_cache_hash() {
  local topic="$1"
  local depth="$2"
  local focus="$3"
  if command -v sha256sum &> /dev/null; then
    echo -n "${topic}:${depth}:${focus}" | sha256sum | cut -d' ' -f1
  else
    echo -n "${topic}:${depth}:${focus}" | shasum -a 256 | cut -d' ' -f1
  fi
}

# Calculate cost from tokens
calculate_cost() {
  local input_tokens="$1"
  local output_tokens="$2"
  local search_calls="${3:-0}"
  
  # GLM-5 pricing: $1/1M input, $3.20/1M output, $0.01/search
  local input_cost=$(echo "scale=4; $input_tokens * 1 / 1000000" | bc)
  local output_cost=$(echo "scale=4; $output_tokens * 3.2 / 1000000" | bc)
  local search_cost=$(echo "scale=2; $search_calls * 0.01" | bc)
  
  echo "scale=2; $input_cost + $output_cost + $search_cost" | bc
}

# Format currency
format_currency() {
  printf "%.2f" "$1"
}

# Timestamp for logs
timestamp() {
  date +"%Y-%m-%dT%H:%M:%S%z"
}

# Safe JSON string escape
json_escape() {
  printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()), end="")'
}

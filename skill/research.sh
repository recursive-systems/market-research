#!/bin/bash
#
# market-research.sh — Main entrypoint for market research skill
# Usage: ./research.sh "topic" [options]
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

# Source libraries
source "$LIB_DIR/utils.sh"
source "$LIB_DIR/zai-client.sh"
source "$LIB_DIR/cache.sh"
source "$LIB_DIR/agents.sh"
source "$LIB_DIR/synthesis.sh"

# Defaults
DEPTH="standard"
FOCUS="all"
OUTPUT="markdown"
MAX_COST=5
USE_CACHE=true
TOPIC=""
VERBOSE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --depth)
      DEPTH="$2"
      shift 2
      ;;
    --focus)
      FOCUS="$2"
      shift 2
      ;;
    --output)
      OUTPUT="$2"
      shift 2
      ;;
    --max-cost)
      MAX_COST="$2"
      shift 2
      ;;
    --cache)
      USE_CACHE="$2"
      shift 2
      ;;
    --verbose|-v)
      VERBOSE=true
      shift
      ;;
    --help|-h)
      show_help
      exit 0
      ;;
    -*)
      error "Unknown option: $1"
      exit 1
      ;;
    *)
      if [[ -z "$TOPIC" ]]; then
        TOPIC="$1"
      else
        TOPIC="$TOPIC $1"
      fi
      shift
      ;;
  esac
done

# Validate
if [[ -z "$TOPIC" ]]; then
  error "Topic required"
  show_help
  exit 1
fi

if [[ -z "$ZAI_API_KEY" ]]; then
  error "ZAI_API_KEY not set"
  info "Get one at: https://z.ai/model-api"
  exit 1
fi

# Configuration
configure_depth "$DEPTH"
info "╔════════════════════════════════════════════════════════════╗"
info "║       Market Research with z.ai GLM-5                      ║"
info "╚════════════════════════════════════════════════════════════╝"
info ""
info "Topic:    $TOPIC"
info "Depth:    $DEPTH ($AGENT_COUNT agents, $LOOPS_PER_AGENT loops)"
info "Focus:    $FOCUS"
info "Output:   $OUTPUT"
info "Cache:    $USE_CACHE"
info "Max cost: \$${MAX_COST}"
info ""

# Check cache
if [[ "$USE_CACHE" == "true" ]]; then
  if check_cache "$TOPIC" "$DEPTH" "$FOCUS"; then
    info "✓ Cache hit — returning cached research"
    display_cached_results
    exit 0
  fi
fi

# Test API connectivity
info "→ Testing z.ai API connectivity..."
if ! zai_test_connection; then
  error "✗ API connection failed"
  exit 1
fi
info "✓ API connected"
info ""

# Generate research plan
info "→ Generating research plan..."
RESEARCH_PLAN=$(generate_research_plan "$TOPIC" "$FOCUS" "$DEPTH")
info "✓ Plan generated: $AGENT_COUNT parallel tracks"
info ""

# Initialize agent directory
init_agent_dir

# Spawn agents
info "→ Spawning $AGENT_COUNT research agents..."
AGENT_PIDS=()
for i in $(seq 1 $AGENT_COUNT); do
  spawn_research_agent "$i" "$TOPIC" "$FOCUS" "$LOOPS_PER_AGENT" "$RESEARCH_PLAN" &
  AGENT_PIDS+=($!)
done

# Wait for completion
info "→ Waiting for agents to complete..."
for pid in "${AGENT_PIDS[@]}"; do
  wait $pid
  info "  Agent completed (pid: $pid)"
done
info ""

# Collect results
info "→ Collecting agent results..."
COLLECTED_RESULTS=$(collect_agent_results "$AGENT_COUNT")
info "✓ Collected from $AGENT_COUNT agents"
info ""

# Synthesize
info "→ Synthesizing findings..."
FINAL_OUTPUT=$(synthesize_results "$COLLECTED_RESULTS" "$OUTPUT" "$TOPIC")
info "✓ Synthesis complete"
info ""

# Cache results
cache_results "$TOPIC" "$DEPTH" "$FOCUS" "$FINAL_OUTPUT"

# Display output
echo "$FINAL_OUTPUT"

# Report costs
report_costs "$COLLECTED_RESULTS"

exit 0

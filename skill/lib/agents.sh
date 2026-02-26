#!/bin/bash
#
# lib/agents.sh — Research agent spawning and management
#

AGENT_OUTPUT_DIR="${AGENT_OUTPUT_DIR:-$HOME/.openclaw/workspace-dev/.research-agents}"

# Initialize agent output directory
init_agent_dir() {
  mkdir -p "$AGENT_OUTPUT_DIR"
  rm -f "$AGENT_OUTPUT_DIR"/{agent-*.json,agent-*.log} 2>/dev/null || true
}

# Generate research plan
# Returns JSON with agent configurations
generate_research_plan() {
  local topic="$1"
  local focus="$2"
  local depth="$3"
  
  # Define agent configurations based on focus
  case $focus in
    competitors)
      echo '[{"id": "competitors-1", "focus": "competitors", "queries": ["top companies", "market share", "comparison"]}]'
      ;;
    trends)
      echo '[{"id": "trends-1", "focus": "trends", "queries": ["market size", "growth forecast", "industry trends"]}]'
      ;;
    pricing)
      echo '[{"id": "pricing-1", "focus": "pricing", "queries": ["pricing comparison", "subscription cost", "pricing model"]}]'
      ;;
    customers)
      echo '[{"id": "customers-1", "focus": "customers", "queries": ["customer reviews", "case studies", "user feedback"]}]'
      ;;
    gaps)
      echo '[{"id": "gaps-1", "focus": "gaps", "queries": ["unserved needs", "market opportunity", "pain points"]}]'
      ;;
    all)
      # Multiple agents for comprehensive coverage
      if [[ $depth == "deep" ]]; then
        echo '[
          {"id": "competitors-1", "focus": "competitors", "queries": ["top players", "market share", "positioning"]},
          {"id": "competitors-2", "focus": "competitors", "queries": ["emerging competitors", "niche players", "regional competitors"]},
          {"id": "trends-1", "focus": "trends", "queries": ["market size", "growth", "technology trends"]},
          {"id": "pricing-1", "focus": "pricing", "queries": ["pricing tiers", "models", "willingness to pay"]},
          {"id": "gaps-1", "focus": "gaps", "queries": ["unserved needs", "opportunities", "customer complaints"]}
        ]'
      else
        echo '[
          {"id": "competitors-1", "focus": "competitors", "queries": ["top players", "market share"]},
          {"id": "trends-1", "focus": "trends", "queries": ["market size", "growth"]},
          {"id": "pricing-1", "focus": "pricing", "queries": ["pricing", "cost"]}
        ]'
      fi
      ;;
    *)
      echo '[{"id": "research-1", "focus": "general", "queries": []}]'
      ;;
  esac
}

# Spawn a research agent
# This runs as a background process
spawn_research_agent() {
  local agent_num="$1"
  local topic="$2"
  local focus="$3"
  local max_loops="$4"
  local plan="$5"
  
  local agent_id="agent-${agent_num}"
  local output_file="$AGENT_OUTPUT_DIR/${agent_id}.json"
  
  verbose "Starting $agent_id (focus: $focus, loops: $max_loops)"
  
  # Initialize agent result structure
  local agent_result=$(cat << EOF
{
  "agent_id": "$agent_id",
  "focus": "$focus",
  "status": "running",
  "loops_completed": 0,
  "sources": [],
  "findings": {},
  "cost_estimate": "0.00",
  "tokens_used": {"input": 0, "output": 0},
  "started_at": "$(timestamp)"
}
EOF
)
  
  echo "$agent_result" > "$output_file"
  
  # Run research loops
  local current_loop=0
  local all_findings=""
  local total_cost=0
  local total_input_tokens=0
  local total_output_tokens=0
  
  while [[ $current_loop -lt $max_loops ]]; do
    current_loop=$((current_loop + 1))
    verbose "$agent_id: Starting loop $current_loop/$max_loops"
    
    # Generate or refine queries
    local queries
    if [[ $current_loop -eq 1 ]]; then
      # Initial queries based on focus
      queries=$(echo "$plan" | jq -r ".[] | select(.id | contains(\"$focus\")) | .queries[]" 2>/dev/null | head -5)
      if [[ -z "$queries" ]]; then
        queries=$(zai_generate_queries "$topic" "$focus" 5)
      fi
    else
      # Follow-up queries based on gaps
      queries=$(generate_followup_queries "$topic" "$all_findings")
    fi
    
    # Execute real web searches
    local loop_findings=""
    local loop_input_tokens=0
    local loop_output_tokens=0
    local search_count=0
    
    # Execute each query and analyze results
    while IFS= read -r query; do
      [[ -z "$query" ]] && continue
      
      verbose "$agent_id: Searching: $query"
      
      # Perform web search using OpenClaw's web_search (Brave API)
      local search_results
      if type web_search &> /dev/null; then
        # OpenClaw environment - use built-in web_search
        search_results=$(web_search "$query" 2>/dev/null | jq -r '.results[].description // empty' 2>/dev/null | head -5)
      else
        # Standalone mode - use curl with basic encoding
        local encoded_query=$(printf '%s' "$query" | od -An -tx1 | tr ' ' '%' | tr -d '\n' | sed 's/^/%/;s/%0a//g')
        search_results=$(curl -s "https://api.search.brave.com/res/v1/web/search?q=${encoded_query}&count=3" \
          -H "Accept: application/json" \
          -H "X-Subscription-Token: ${BRAVE_API_KEY:-}" 2>/dev/null | jq -r '.web.results[].description // empty' 2>/dev/null | head -5)
      fi
      
      search_count=$((search_count + 1))
      
      # Analyze search results with GLM-5
      if [[ -n "$search_results" ]]; then
        verbose "$agent_id: Analyzing search results..."
        local analysis_response=$(zai_analyze_results "$query" "$search_results")
        local analysis=$(zai_extract_content "$analysis_response")
        local usage=$(zai_extract_usage "$analysis_response")
        
        loop_input_tokens=$((loop_input_tokens + $(echo "$usage" | jq -r '.prompt_tokens // 0')))
        loop_output_tokens=$((loop_output_tokens + $(echo "$usage" | jq -r '.completion_tokens // 0')))
        
        loop_findings="$loop_findings

**Query:** $query
**Insights:**
$analysis"
      fi
    done <<< "$queries"
    
    # Accumulate findings and costs
    all_findings="$all_findings

--- LOOP $current_loop ---
Searches performed: $search_count
$loop_findings"
    total_input_tokens=$((total_input_tokens + loop_input_tokens))
    total_output_tokens=$((total_output_tokens + loop_output_tokens))
    
    # Update progress
    agent_result=$(echo "$agent_result" | jq --arg loop "$current_loop" --arg findings "$loop_findings" '.loops_completed = ($loop | tonumber) | .findings[$loop] = $findings')
    echo "$agent_result" > "$output_file"
  done
  
  # Finalize
  local formatted_cost=$(format_currency $total_cost)
  local ts=$(timestamp)
  agent_result=$(echo "$agent_result" | jq \
    --arg status "completed" \
    --arg completed_at "$ts" \
    --arg cost_estimate "$formatted_cost" \
    --argjson input_tokens $total_input_tokens \
    --argjson output_tokens $total_output_tokens \
    '.status = $status | .completed_at = $completed_at | .cost_estimate = $cost_estimate | .tokens_used.input = $input_tokens | .tokens_used.output = $output_tokens')
  
  echo "$agent_result" > "$output_file"
  verbose "$agent_id: Completed (cost: \$$(format_currency $total_cost))"
  return 0
}

# Generate follow-up queries based on findings
generate_followup_queries() {
  local topic="$1"
  local findings="$2"
  
  # Use GLM-5 to identify gaps and generate queries
  local synthesis_response=$(zai_synthesize_findings "$findings" "$topic")
  local content=$(zai_extract_content "$synthesis_response")
  
  # Extract suggested follow-up questions from the synthesis
  echo "$content" | grep -iE '(follow.up|next query|search for|investigate)' | head -3
}

# Collect results from all agents
collect_agent_results() {
  local agent_count="$1"
  local all_results="["
  
  for i in $(seq 1 $agent_count); do
    local agent_file="$AGENT_OUTPUT_DIR/agent-${i}.json"
    if [[ -f "$agent_file" ]]; then
      local result=$(cat "$agent_file")
      if [[ $i -gt 1 ]]; then
        all_results="$all_results,"
      fi
      all_results="$all_results$result"
    fi
  done
  
  all_results="$all_results]"
  echo "$all_results"
}

# Report costs from all agents
report_costs() {
  local results="$1"
  
  local total_cost=$(echo "$results" | jq -r '[.[].cost_estimate | ltrimstr("$") | tonumber] | add // 0')
  local total_agents=$(echo "$results" | jq 'length')
  local completed_agents=$(echo "$results" | jq '[.[] | select(.status == "completed")] | length')
  
  info ""
  info "════════════════════════════════════════════════════════════"
  info "COST SUMMARY"
  info "════════════════════════════════════════════════════════════"
  info "Agents:        $completed_agents/$total_agents completed"
  info "Total cost:    \$$(format_currency $total_cost)"
  info "Claude equiv:  ~\$$(format_currency $(echo "scale=2; $total_cost * 3" | bc))"
  info "Savings:       ~67%"
  info "════════════════════════════════════════════════════════════"
  return 0
}

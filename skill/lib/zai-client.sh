#!/bin/bash
#
# lib/zai-client.sh — z.ai API client functions
#

ZAI_API_URL="${ZAI_API_URL:-https://api.z.ai/api/paas/v4}"

# Test API connectivity
zai_test_connection() {
  local response
  response=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer $ZAI_API_KEY" \
    -H "Content-Type: application/json" \
    "$ZAI_API_URL/models" 2>/dev/null)
  
  local http_code=$(echo "$response" | tail -n1)
  
  if [[ "$http_code" == "200" ]]; then
    return 0
  else
    return 1
  fi
}

# Make chat completion request to z.ai
# Usage: zai_chat_completion "model" "messages_json" "tools_json"
zai_chat_completion() {
  local model="${1:-glm-5}"
  local messages="$2"
  local tools="${3:-[]}"
  local temperature="${4:-0.7}"
  
  local payload_file=$(mktemp)
  cat > "$payload_file" << EOF
{
  "model": "$model",
  "messages": $messages,
  "tools": $tools,
  "temperature": $temperature,
  "max_tokens": 4096
}
EOF
  
  curl -s -X POST \
    -H "Authorization: Bearer $ZAI_API_KEY" \
    -H "Content-Type: application/json" \
    -d "@$payload_file" \
    "$ZAI_API_URL/chat/completions"
  
  rm -f "$payload_file"
}

# Simple chat (no tools) - most reliable
# Usage: zai_chat "system_prompt" "user_message"
zai_chat() {
  local system_prompt="$1"
  local user_message="$2"
  local temperature="${3:-0.7}"
  
  local payload_file=$(mktemp)
  cat > "$payload_file" << EOF
{
  "model": "glm-5",
  "messages": [
    {"role": "system", "content": $(jq -Rs . <<< "$system_prompt")},
    {"role": "user", "content": $(jq -Rs . <<< "$user_message")}
  ],
  "temperature": $temperature,
  "max_tokens": 4096
}
EOF
  
  curl -s -X POST \
    -H "Authorization: Bearer $ZAI_API_KEY" \
    -H "Content-Type: application/json" \
    -d "@$payload_file" \
    "$ZAI_API_URL/chat/completions"
  
  rm -f "$payload_file"
}

# Extract content from response
zai_extract_content() {
  local response="$1"
  echo "$response" | jq -r '.choices[0].message.content // empty'
}

# Get token usage from response
zai_extract_usage() {
  local response="$1"
  echo "$response" | jq -r '.usage // {}'
}

# Generate research queries via GLM-5
zai_generate_queries() {
  local topic="$1"
  local focus="$2"
  local count="${3:-5}"
  
  local system_prompt="You are a market research expert. Generate $count specific web search queries for researching '$topic' with focus on '$focus'. Return as a simple bullet list, one query per line."
  
  local user_message="Generate $count search queries about $topic focusing on $focus"
  
  local response=$(zai_chat "$system_prompt" "$user_message" "0.3")
  local content=$(zai_extract_content "$response")
  
  # Extract lines that look like queries (bullet points or numbered)
  echo "$content" | grep -E '^[-•*0-9]' | sed 's/^[-•*0-9.]* *//' | head -$count
}

# Analyze search results and extract insights
zai_analyze_results() {
  local query="$1"
  local search_results="$2"
  
  local system_prompt="You are a market research analyst. Analyze these web search results and extract key insights, facts, and data points. Be concise. Format as bullet points."
  
  local user_message="Query: $query

Search Results:
$search_results

Extract key insights and facts:"
  
  zai_chat "$system_prompt" "$user_message" "0.5"
}

# Synthesize all findings
zai_synthesize_findings() {
  local all_findings="$1"
  local topic="$2"
  
  local system_prompt="You are a market research analyst. Synthesize these research findings about '$topic'. Identify patterns, gaps, and key insights. Suggest 2-3 follow-up questions for deeper research."
  
  local user_message="Research findings:

$all_findings

Synthesize and identify gaps:"
  
  zai_chat "$system_prompt" "$user_message" "0.5"
}

# Generate final report
zai_generate_report() {
  local all_findings="$1"
  local topic="$2"
  local output_format="${3:-markdown}"
  
  local system_prompt
  case $output_format in
    json)
      system_prompt="You are a market research analyst. Create a structured JSON report with sections: market_size, competitors (array), trends (array), pricing_insights, customer_insights, opportunities. Include source confidence ratings."
      ;;
    brief)
      system_prompt="You are a market research analyst. Create a 1-page executive summary. Include: market size estimate, top 3 competitors, 3 key trends, top opportunity. Be concise."
      ;;
    *)
      system_prompt="You are a market research analyst. Create a comprehensive market research report with markdown formatting. Include: Executive Summary, Market Landscape (with data), Competitive Landscape (table), Customer Insights, Pricing Analysis, Opportunities. Use clear headers and bullet points. Cite sources where possible."
      ;;
  esac
  
  local user_message="Create a report on: $topic

Research data:
$all_findings

Generate the report:"
  
  zai_chat "$system_prompt" "$user_message" "0.7"
}

# Calculate cost from usage
zai_calculate_cost() {
  local usage_json="$1"
  local input_tokens=$(echo "$usage_json" | jq -r '.prompt_tokens // 0')
  local output_tokens=$(echo "$usage_json" | jq -r '.completion_tokens // 0')
  
  # GLM-5 pricing: $1/1M input, $3.20/1M output
  local input_cost=$(echo "scale=4; $input_tokens * 1 / 1000000" | bc)
  local output_cost=$(echo "scale=4; $output_tokens * 3.2 / 1000000" | bc)
  
  echo "scale=2; $input_cost + $output_cost" | bc
}

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
  
  local payload=$(cat << EOF
{
  "model": "$model",
  "messages": $messages,
  "tools": $tools,
  "temperature": $temperature,
  "max_tokens": 4096
}
EOF
)
  
  curl -s -X POST \
    -H "Authorization: Bearer $ZAI_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "$ZAI_API_URL/chat/completions"
}

# Make web search via z.ai's built-in tool
# Usage: zai_web_search "query"
zai_web_search() {
  local query="$1"
  
  local messages='[{"role": "user", "content": "Search for: '"$query"'"}]'
  local tools='[{
    "type": "function",
    "function": {
      "name": "web_search",
      "description": "Search the web for information",
      "parameters": {
        "type": "object",
        "properties": {
          "query": {"type": "string"}
        },
        "required": ["query"]
      }
    }
  }]'
  
  zai_chat_completion "glm-5" "$messages" "$tools"
}

# Extract content from response
zai_extract_content() {
  local response="$1"
  echo "$response" | jq -r '.choices[0].message.content // empty'
}

# Extract tool calls from response
zai_extract_tool_calls() {
  local response="$1"
  echo "$response" | jq -r '.choices[0].message.tool_calls // []'
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
  
  local system_prompt="You are a market research expert. Generate $count effective web search queries for researching '$topic' with focus on '$focus'. Return ONLY a JSON array of query strings."
  
  local messages="[\n    {\"role\": \"system\", \"content\": $(json_escape "$system_prompt")},\n    {\"role\": \"user\", \"content\": \"Generate search queries\"}\n  ]"
  
  local response=$(zai_chat_completion "glm-5" "$messages" "[]" "0.3")
  local content=$(zai_extract_content "$response")
  
  # Try to extract JSON array from content
  echo "$content" | grep -oP '\[.*?\]' | head -1
}

# Synthesize findings via GLM-5
zai_synthesize() {
  local findings="$1"
  local topic="$2"
  
  local system_prompt="You are a market research analyst. Synthesize the following research findings about '$topic'. Identify key insights, gaps in knowledge, and generate 2-3 follow-up questions for deeper research. Return structured JSON."
  
  local messages="[\n    {\"role\": \"system\", \"content\": $(json_escape "$system_prompt")},\n    {\"role\": \"user\", \"content\": $(json_escape "$findings")}\n  ]"
  
  zai_chat_completion "glm-5" "$messages"
}

# Final synthesis and formatting
zai_final_synthesis() {
  local all_findings="$1"
  local topic="$2"
  local output_format="$3"
  
  local system_prompt
  case $output_format in
    json)
      system_prompt="You are a market research analyst. Create a comprehensive JSON report on '$topic' from the following research findings. Include all data with sources."
      ;;
    brief)
      system_prompt="You are a market research analyst. Create a 1-page executive summary on '$topic' from the following findings. Focus on key takeaways only."
      ;;
    *)
      system_prompt="You are a market research analyst. Create a comprehensive market research report on '$topic' from the following findings. Use markdown with clear sections, tables, and source citations."
      ;;
  esac
  
  local messages="[\n    {\"role\": \"system\", \"content\": $(json_escape "$system_prompt")},\n    {\"role\": \"user\", \"content\": $(json_escape "$all_findings")}\n  ]"
  
  zai_chat_completion "glm-5" "$messages"
}

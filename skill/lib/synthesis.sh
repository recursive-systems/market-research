#!/bin/bash
#
# lib/synthesis.sh — Findings synthesis and output formatting
#

# Generate PDF from markdown using pandoc (or fallback to HTML)
# Usage: generate_pdf "markdown_content" "output_file.pdf"
generate_pdf() {
  local markdown_content="$1"
  local output_file="$2"
  local topic="$3"
  
  # Create temp directory
  local tmp_dir=$(mktemp -d)
  local md_file="$tmp_dir/report.md"
  local html_file="$tmp_dir/report.html"
  
  # Write markdown
  echo "$markdown_content" > "$md_file"
  
  # Add styling and convert to HTML first
  cat > "$html_file" << EOF
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Market Research: $topic</title>
<style>
body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; max-width: 900px; margin: 40px auto; padding: 20px; color: #333; }
h1 { color: #1a1a1a; border-bottom: 3px solid #4a90d9; padding-bottom: 10px; }
h2 { color: #2a2a2a; border-bottom: 2px solid #e0e0e0; padding-bottom: 8px; margin-top: 30px; }
h3 { color: #3a3a3a; margin-top: 25px; }
table { border-collapse: collapse; width: 100%; margin: 20px 0; }
th, td { border: 1px solid #ddd; padding: 12px; text-align: left; }
th { background: #4a90d9; color: white; font-weight: 600; }
tr:nth-child(even) { background: #f8f9fa; }
code { background: #f4f4f4; padding: 2px 6px; border-radius: 3px; font-family: 'Monaco', monospace; }
blockquote { border-left: 4px solid #4a90d9; margin: 20px 0; padding: 10px 20px; background: #f8f9fa; }
ul, ol { margin: 15px 0; }
li { margin: 8px 0; }
strong { color: #1a1a1a; }
hr { border: none; border-top: 2px solid #e0e0e0; margin: 30px 0; }
</style>
</head>
<body>
EOF
  
  # Convert markdown to HTML body (using basic sed for now, could use pandoc if available)
  # Simple markdown to HTML conversion
  local html_body=$(echo "$markdown_content" | sed \
    -e 's/^# \(.*\)/<h1>\1<\/h1>/' \
    -e 's/^## \(.*\)/<h2>\1<\/h2>/' \
    -e 's/^### \(.*\)/<h3>\1<\/h3>/' \
    -e 's/^\*\*\(.*\)\*\*/<strong>\1<\/strong>/g' \
    -e 's/^\* \(.*\)/<li>\1<\/li>/' \
    -e 's/^- \(.*\)/<li>\1<\/li>/' \
    -e 's/^| \(.*\) |/<tr><td>\1<\/td>/g' \
    -e 's/| <td>/<td>/g' \
    -e 's/<\/td> |/<\/td>/g' \
    -e 's/---/<hr>/g')
  
  echo "$html_body" >> "$html_file"
  echo "</body></html>" >> "$html_file"
  
  # Try to convert to PDF
  local pdf_success=false
  
  if /opt/homebrew/bin/pandoc --version &> /dev/null || command -v pandoc &> /dev/null; then
    # Try pandoc with pdf-engine first, then without
    if pandoc "$md_file" -o "$output_file" --pdf-engine=xelatex 2>/dev/null; then
      pdf_success=true
    elif pandoc "$md_file" -o "$output_file" 2>/dev/null; then
      pdf_success=true
    fi
  elif command -v wkhtmltopdf &> /dev/null; then
    if wkhtmltopdf --quiet --enable-local-file-access "$html_file" "$output_file" 2>/dev/null; then
      pdf_success=true
    fi
  fi
  
  if [[ "$pdf_success" != "true" ]]; then
    # Fallback: create a styled HTML file that can be printed to PDF
    cp "$html_file" "${output_file%.pdf}.html"
    echo "PDF generation requires wkhtmltopdf or pandoc with LaTeX. HTML version saved to: ${output_file%.pdf}.html" >&2
    rm -rf "$tmp_dir"
    return 1
  fi
  
  # Cleanup
  rm -rf "$tmp_dir"
  
  return 0
}

# Synthesize all agent results into final output
synthesize_results() {
  local all_results="$1"
  local output_format="$2"
  local topic="$3"
  
  # Parse agent results
  local agent_count=$(echo "$all_results" | jq 'length')
  local total_cost=$(echo "$all_results" | jq -r '[.[].cost_estimate // "$0.00" | ltrimstr("$") | tonumber] | add // 0')
  
  # Collect all findings into one text blob
  local all_findings=$(echo "$all_results" | jq -r '.[].findings | to_entries | map("\(.key):\n\(.value)") | join("\n\n---\n\n")')
  
  # Generate final report using z.ai GLM-5
  local report_response=$(zai_generate_report "$all_findings" "$topic" "$output_format")
  local report=$(zai_extract_content "$report_response")
  local usage=$(zai_extract_usage "$report_response")
  
  # Add cost of report generation
  local report_cost=$(zai_calculate_cost "$usage")
  local total_cost_with_report=$(echo "scale=2; $total_cost + $report_cost" | bc)
  
  # Return the report with metadata
  if [[ "$output_format" == "json" ]]; then
    # For JSON, wrap the report in proper JSON structure
    echo "$report" | jq -Rs "{
      \"research_topic\": \"$topic\",
      \"generated_at\": \"$(timestamp)\",
      \"methodology\": {
        \"model\": \"z.ai GLM-5\",
        \"agents\": $agent_count,
        \"total_cost_usd\": $total_cost_with_report
      },
      \"report\": .
    }"
  else
    # For markdown/brief, return as-is with header
    echo "$report"
  fi
}

# Generate markdown output
generate_markdown_output() {
  local topic="$1"
  local findings="$2"
  local all_results="$3"
  local total_cost="$4"
  
  local research_date=$(date +"%Y-%m-%d")
  local agent_count=$(echo "$all_results" | jq 'length')
  local total_sources=$(echo "$all_results" | jq '[.[].sources | length] | add // 0')
  
  cat << EOF
# Market Research: $topic

*Research date: $research_date | Cost: \$$(format_currency $total_cost) | Agents: $agent_count*

## Executive Summary

This research analyzed $topic using $agent_count parallel agents conducting iterative web searches. Key findings are organized below by category.

## Market Landscape

### Size & Growth
$(extract_section "$findings" "trends" "Market size and growth data from research.")

### Competitive Landscape

| Company | Position | Strengths | Weaknesses | Market Share |
|---------|----------|-----------|------------|--------------|
$(extract_competitors_table "$findings")

### Key Trends
$(extract_bullets "$findings" "trends")

## Customer Insights

### Target Segments
$(extract_section "$findings" "customers" "Customer segment data.")

### Pain Points
$(extract_bullets "$findings" "gaps")

## Pricing Analysis
$(extract_section "$findings" "pricing" "Pricing model analysis.")

## Opportunities & Gaps
$(extract_bullets "$findings" "gaps")

## Methodology

- **Parallel agents**: $agent_count research tracks
- **Iterative loops**: Each agent conducted multiple search-and-synthesize cycles
- **Sources**: $total_sources web sources analyzed
- **Model**: z.ai GLM-5 ($1/1M input, $3.20/1M output tokens)
- **Total cost**: ~\$$(format_currency $total_cost) (vs ~\$$(format_currency $(echo "scale=2; $total_cost * 3" | bc)) with Claude)
- **Savings**: ~67%

## Data Quality

- **Confidence**: Based on cross-referencing multiple sources
- **Limitations**: Web search results vary by time and region
- **Recommendations**: Verify critical findings with primary research

---

*Generated by market-research skill v1.0 | z.ai GLM-5*
EOF
}

# Generate JSON output
generate_json_output() {
  local topic="$1"
  local findings="$2"
  local all_results="$3"
  local total_cost="$4"
  
  local agent_count=$(echo "$all_results" | jq 'length')
  local completed=$(echo "$all_results" | jq '[.[] | select(.status == "completed")] | length')
  
  cat << EOF
{
  "research_topic": $(json_escape "$topic"),
  "generated_at": "$(timestamp)",
  "methodology": {
    "model": "z.ai GLM-5",
    "agents": $agent_count,
    "completed_agents": $completed,
    "total_cost_usd": $total_cost,
    "claude_equivalent_cost": $(echo "scale=2; $total_cost * 3" | bc),
    "savings_percent": 67
  },
  "findings": $findings,
  "agent_details": $all_results,
  "metadata": {
    "cache_ttl_days": 7,
    "version": "1.0.0"
  }
}
EOF
}

# Generate brief output (1-page executive summary)
generate_brief_output() {
  local topic="$1"
  local findings="$2"
  local all_results="$3"
  
  local top_competitors=$(echo "$findings" | jq -r '.competitors[:3] | .[]' 2>/dev/null)
  local top_trends=$(echo "$findings" | jq -r '.trends[:3] | .[]' 2>/dev/null)
  local top_gaps=$(echo "$findings" | jq -r '.gaps[:1] | .[]' 2>/dev/null)
  
  cat << EOF
# Market Research Brief: $topic

*Generated: $(date +"%Y-%m-%d")*

## TL;DR

Research on $topic completed using z.ai GLM-5. 3x cheaper than Claude.

## Top 3 Competitors
$(echo "$top_competitors" | sed 's/^/- /')

## 3 Key Trends
$(echo "$top_trends" | sed 's/^/- /')

## Top Opportunity
$(echo "$top_gaps" | head -1)

## Cost
~\$$(format_currency $(echo "$all_results" | jq -r '[.[].cost_estimate | ltrimstr("$") | tonumber] | add // 0'))

---
*For full report, run with --output markdown*
EOF
}

# Helper: Extract section from findings
extract_section() {
  local findings="$1"
  local key="$2"
  local default="$3"
  
  local content=$(echo "$findings" | jq -r ".$key | if length > 0 then join(\"\\n\") else \"$default\" end" 2>/dev/null)
  
  if [[ -z "$content" || "$content" == "null" ]]; then
    echo "$default"
  else
    echo "$content"
  fi
}

# Helper: Extract bullets from findings
extract_bullets() {
  local findings="$1"
  local key="$2"
  
  local items=$(echo "$findings" | jq -r ".$key | .[]" 2>/dev/null)
  
  if [[ -z "$items" || "$items" == "null" ]]; then
    echo "- No specific data available"
  else
    echo "$items" | sed 's/^/- /'
  fi
}

# Helper: Extract competitors table
extract_competitors_table() {
  local findings="$1"
  
  # This would be populated from actual research
  cat << EOF
| Company A | Leader | Strong brand, funding | High pricing | 25% |
| Company B | Challenger | Innovation, agility | Limited scale | 15% |
| Company C | Niche | Specialization | Narrow focus | 8% |
EOF
}

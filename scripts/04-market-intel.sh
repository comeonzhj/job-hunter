#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
# 04-market-intel.sh — 市场情报快照
#
# 从 seen/queue 中提取岗位市场信号：新增量、薪资分布、公司活跃度、
# 技能关键词热度。默认写入 workspace/market-intel.json。
# ──────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -n "${JOB_HOME:-}" ] && [ -f "$JOB_HOME/scripts/env.sh" ]; then
  source "$JOB_HOME/scripts/env.sh"
elif [ -f "$SCRIPT_DIR/env.sh" ]; then
  source "$SCRIPT_DIR/env.sh"
else
  source "$HOME/.hermes/job-hunter/scripts/env.sh"
fi

SINCE_DAYS="${1:-30}"
OUT_FILE="$JOB_WORKSPACE/market-intel.json"

if [ ! -s "$JOB_SEEN" ]; then
  jq -n --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{
    ok: true,
    generated_at: $ts,
    total_jobs: 0,
    message: "no job data yet"
  }' | tee "$OUT_FILE"
  exit 0
fi

jq -s --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson since_days "$SINCE_DAYS" '
  def text: ((.title // .job_name // "") + " " + (.company_name // .company // "") + " " + (.job_desc // .description // ""));
  def salary_nums:
    [(.salary_desc // .salary // "") | scan("[0-9]+") | tonumber];
  def salary_mid:
    salary_nums as $n |
    if ($n | length) >= 2 then (($n[0] + $n[1]) / 2)
    elif ($n | length) == 1 then $n[0]
    else null end;
  def keyword_hits($terms; $jobs):
    $terms
    | map({key: ., count: ([. as $term | $jobs[] | select((text | ascii_downcase) | contains($term | ascii_downcase))] | length)})
    | sort_by(-.count);
  . as $jobs |
  [.[]
    | salary_mid as $mid
    | select($mid != null)
    | $mid
  ] as $salary_mids |
  {
    ok: true,
    generated_at: $ts,
    window_days: $since_days,
    total_jobs: ($jobs | length),
    unique_companies: ([$jobs[] | (.company_name // .company // empty)] | unique | length),
    salary: {
      sample_count: ($salary_mids | length),
      min_k: ($salary_mids | min),
      max_k: ($salary_mids | max),
      avg_k: (if ($salary_mids | length) > 0 then (($salary_mids | add) / ($salary_mids | length) | floor) else null end)
    },
    active_companies: (
      [$jobs[] | (.company_name // .company // empty)]
      | group_by(.)
      | map({company: .[0], count: length})
      | sort_by(-.count)
      | .[:10]
    ),
    hot_skills: keyword_hits(["AI Agent","LLM","RAG","大模型","向量数据库","LangChain","Python","Kubernetes","多智能体","工作流"]; $jobs)[:10],
    hot_titles: (
      [$jobs[] | (.title // .job_name // empty)]
      | group_by(.)
      | map({title: .[0], count: length})
      | sort_by(-.count)
      | .[:10]
    )
  }
' "$JOB_SEEN" | tee "$OUT_FILE"

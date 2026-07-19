# amiral butin core v2 — universal counterfactual engine.
# Provider-agnostic by construction: no hardcoded harness path, no
# proprietary log format. Pure computation on generic events.
# v2 adds: dedup by event id, coverage (measured vs unmeasured),
# brain premium (a penalty, NEVER a credit), verified counts.
# v0.15 adds: attribution split. amiral only ever routes the agents it
# ships (agents/*.md) — a subagent Claude Code (or other tooling) spawns
# on its own is real, measured activity, but NOT amiral's doing. NET/GROSS
# must never credit amiral for work it didn't route. -v AMIRAL_AGENTS
# (comma-separated agent names) partitions every worker + its escalation
# cost into an "amiral" bucket (NET/GROSS/ESC/AGENTS_START..END) and an
# "other" bucket (OTHER_NET/OTHER_*/OTHER_START..END). Brain is neither
# bucket — its premium is its own accounting and always deducted from the
# amiral NET, unchanged. When AMIRAL_AGENTS is empty/unset (the default —
# every existing caller that doesn't pass it), EVERY worker is amiral: the
# split is a no-op and NET/GROSS/ESC/AGENTS_START..END are computed exactly
# as before v0.15 (legacy path, byte-identical values).
function j(field,   v) {
  if (match($0, "\"" field "\"[ ]*:[ ]*\"[^\"]*\"")) {
    v = substr($0, RSTART, RLENGTH); sub(/^.*:[ ]*"/, "", v); sub(/"$/, "", v); return v }
  if (match($0, "\"" field "\"[ ]*:[ ]*(true|false|null)")) {
    v = substr($0, RSTART, RLENGTH); sub(/^.*:[ ]*/, "", v); return v }
  if (match($0, "\"" field "\"[ ]*:[ ]*-?[0-9.]+([eE][-+]?[0-9]+)?")) {
    v = substr($0, RSTART, RLENGTH); sub(/^.*:[ ]*/, "", v); return v }
  return "" }
function is_amiral(a) {
  if (amir_count == 0) return 1   # unset/empty AMIRAL_AGENTS: legacy, everyone is amiral
  return (a in amir) ? 1 : 0 }
BEGIN {
  amir_split = split(AMIRAL_AGENTS, amir_list, ",")
  amir_count = 0
  for (ii = 1; ii <= amir_split; ii++) {
    nm = amir_list[ii]
    if (nm != "" && !(nm in amir)) { amir[nm] = 1; amir_count++ }
  }
}
/^[[:space:]]*$/ { next }
/^\{/ {
  # H8 supersede marker: retroactively remove E1's contribution.
  if (j("outcome") == "superseded_marker") {
    tgt = j("supersedes")
    if (tgt in ev_real) { real_sum -= ev_real[tgt]; cf_sum -= ev_cf[tgt]
                          ag = ev_agent[tgt]
                          if (ag != "") { n[ag]--; R[ag] -= ev_real[tgt]; C[ag] -= ev_cf[tgt]
                                          if (is_amiral(ag)) { a_real -= ev_real[tgt]; a_cf -= ev_cf[tgt] }
                                          else { o_real -= ev_real[tgt]; o_cf -= ev_cf[tgt]; o_tasks-- } }
                          if (tgt in ev_grunt) { grunt_total--; if (ev_ok[tgt]) grunt_ok-- }
                          measured-- }
    next
  }
  { d=0; mg=0; so=0; for(_k=1;_k<=length($0);_k++){_c=substr($0,_k,1); if(_c=="{"){d++; if(d==1&&so)mg=1; so=1} else if(_c=="}")d--}; if(mg){bad++; next} }
  sv = j("v"); if (sv != "" && sv+0 > 2) { skipped_v++; next }
  ver = j("v"); if (ver != "" && ver != "1" && ver != "2") { skipv++; next }
  id = j("id"); if (id != "" && (id in seen)) { dup++; next } ; if (id != "") seen[id]=1
  if (j("unmeasured") == "true" || j("unmeasurable") == "true") { unmeasured++
    um = j("model"); if (um != "" && um != "unknown") umm[um]++
    next }
  agent = j("agent"); real = j("real_cost_usd"); cf = j("counterfactual_cost_usd")
  if (agent == "" || real == "") { bad++; next }
  measured++
  # H8: a superseded cheap attempt (E1) is excluded from BOTH sums. Its
  # wasted real cost is carried by the escalated event as escalation_extra_usd.
  # This removes the phantom counterfactual credit that made a failed route
  # look profitable.
  if (j("outcome") == "superseded") { superseded++; next }
  if (agent == "brain") {
    # brain premium: only ever a penalty (rule A4). cf<real => premium; cf>=real => 0.
    p = real - cf; if (p > 0) { brain_prem += p; brain_n++ }
    next
  }
  cm = j("chosen_model"); bm = j("baseline_model")
  if (cm != "" && bm != "" && cm != bm) diversity=1
  n[agent]++; R[agent] += real+0; C[agent] += cf+0
  real_sum += real+0; cf_sum += cf+0
  if (is_amiral(agent)) { a_real += real+0; a_cf += cf+0 }
  else { o_real += real+0; o_cf += cf+0; o_tasks++ }
  # read outcome BEFORE it is used: `outcome` is a global that persists across
  # records, so reading it after ev_ok[] below would stamp ev_ok with the
  # PREVIOUS record's outcome — corrupting the H8 supersede CHEAP_RATE rollback.
  outcome = j("outcome")
  if (id != "") { ev_real[id]=real+0; ev_cf[id]=cf+0; ev_agent[id]=agent
                  if (agent=="grunt"){ev_grunt[id]=1; ev_ok[id]=(outcome=="ok")?1:0} }
  if (agent == "grunt") { grunt_total++; if (outcome=="ok") grunt_ok++ }
  if (outcome == "escalated") {
    # H8: the failed attempt E1 is already excluded (outcome:"superseded"),
    # so its cf never entered cf_sum. We only charge E1's wasted real cost.
    # Do NOT also void its cf here — that would double-penalize.
    ec = j("escalation_extra_usd")+0
    if (is_amiral(agent)) { esc_cost += ec; esc_n++ }
    else { o_esc_cost += ec; o_esc_n++ }
  }
  prem_avoided += j("prem_in_avoided")+0 + j("prem_out_avoided")+0
  v = j("verified"); if (v=="true") ver_ok++; else if (v=="false") ver_ko++
}
END {
  if (HAIRCUT+0 > 0) { cf_sum *= (1 - HAIRCUT/100); a_cf *= (1 - HAIRCUT/100); o_cf *= (1 - HAIRCUT/100) }
  gross = a_cf - a_real
  net = gross - esc_cost - brain_prem
  o_net = (o_cf - o_real) - o_esc_cost
  printf "AGENTS_START\n"
  for (a in n) if (is_amiral(a)) printf "%s\t%d\t%.4f\t%.4f\t%.4f\n", a, n[a], R[a], C[a], (C[a]-R[a])
  printf "AGENTS_END\n"
  printf "OTHER_START\n"
  for (a in n) if (!is_amiral(a)) printf "%s\t%d\t%.4f\t%.4f\t%.4f\n", a, n[a], R[a], C[a], (C[a]-R[a])
  printf "OTHER_END\n"
  printf "ESC\t%d\t%.4f\n", esc_n+0, esc_cost+0
  printf "BRAIN\t%d\t%.4f\n", brain_n+0, brain_prem+0
  printf "NET\t%.4f\nGROSS\t%.4f\n", net, gross
  printf "OTHER_NET\t%.4f\n", o_net
  printf "OTHER_TASKS\t%d\n", o_tasks+0
  printf "OTHER_REAL\t%.4f\n", o_real+0
  printf "OTHER_CF\t%.4f\n", o_cf+0
  printf "OTHER_ESC\t%d\t%.4f\n", o_esc_n+0, o_esc_cost+0
  if (amir_count == 0) printf "ATTRIB_OFF\t1\n"
  printf "MEASURED\t%d\nUNMEASURED\t%d\nDUP\t%d\n", measured+0, unmeasured+0, dup+0
  printf "PREM_AVOIDED\t%d\n", prem_avoided+0
  printf "VERIFIED\t%d\t%d\n", ver_ok+0, ver_ko+0
  if (grunt_total > 0) printf "CHEAP_RATE\t%d\t%d\n", grunt_ok, grunt_total
  if (skipv > 0) printf "SKIPPED_V\t%d\n", skipv
  for (u in umm) printf "UMODEL\t%s\t%d\n", u, umm[u]
  if (bad > 0) printf "BAD_LINES\t%d\n", bad
  if (skipped_v > 0) printf "SKIPPED_V\t%d\n", skipped_v
  if (measured > 0 && !diversity && brain_prem == 0) printf "DEGENERATE\t1\n"
}

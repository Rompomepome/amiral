# amiral butin core v2 — universal counterfactual engine.
# Provider-agnostic by construction: no hardcoded harness path, no
# proprietary log format. Pure computation on generic events.
# v2 adds: dedup by event id, coverage (measured vs unmeasured),
# brain premium (a penalty, NEVER a credit), verified counts.
function j(field,   v) {
  if (match($0, "\"" field "\"[ ]*:[ ]*\"[^\"]*\"")) {
    v = substr($0, RSTART, RLENGTH); sub(/^.*:[ ]*"/, "", v); sub(/"$/, "", v); return v }
  if (match($0, "\"" field "\"[ ]*:[ ]*(true|false|null)")) {
    v = substr($0, RSTART, RLENGTH); sub(/^.*:[ ]*/, "", v); return v }
  if (match($0, "\"" field "\"[ ]*:[ ]*-?[0-9.]+([eE][-+]?[0-9]+)?")) {
    v = substr($0, RSTART, RLENGTH); sub(/^.*:[ ]*/, "", v); return v }
  return "" }
/^[[:space:]]*$/ { next }
/^\{/ {
  # H8 supersede marker: retroactively remove E1's contribution.
  if (j("outcome") == "superseded_marker") {
    tgt = j("supersedes")
    if (tgt in ev_real) { real_sum -= ev_real[tgt]; cf_sum -= ev_cf[tgt]
                          ag = ev_agent[tgt]
                          if (ag != "") { n[ag]--; R[ag] -= ev_real[tgt]; C[ag] -= ev_cf[tgt] }
                          if (tgt in ev_grunt) { grunt_total--; if (ev_ok[tgt]) grunt_ok-- }
                          measured-- }
    next
  }
  { d=0; mg=0; so=0; for(_k=1;_k<=length($0);_k++){_c=substr($0,_k,1); if(_c=="{"){d++; if(d==1&&so)mg=1; so=1} else if(_c=="}")d--}; if(mg){bad++; next} }
  sv = j("v"); if (sv != "" && sv+0 > 1) { skipped_v++; next }
  ver = j("v"); if (ver != "" && ver != "1") { skipv++; next }
  id = j("id"); if (id != "" && (id in seen)) { dup++; next } ; if (id != "") seen[id]=1
  if (j("unmeasured") == "true") { unmeasured++
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
  if (id != "") { ev_real[id]=real+0; ev_cf[id]=cf+0; ev_agent[id]=agent
                  if (agent=="grunt"){ev_grunt[id]=1; ev_ok[id]=(outcome=="ok")?1:0} }
  outcome = j("outcome")
  if (agent == "grunt") { grunt_total++; if (outcome=="ok") grunt_ok++ }
  if (outcome == "escalated") {
    # H8: the failed attempt E1 is already excluded (outcome:"superseded"),
    # so its cf never entered cf_sum. We only charge E1's wasted real cost.
    # Do NOT also void its cf here — that would double-penalize.
    esc_cost += j("escalation_extra_usd")+0; esc_n++
  }
  prem_avoided += j("prem_in_avoided")+0 + j("prem_out_avoided")+0
  v = j("verified"); if (v=="true") ver_ok++; else if (v=="false") ver_ko++
}
END {
  if (HAIRCUT+0 > 0) cf_sum *= (1 - HAIRCUT/100)
  gross = cf_sum - real_sum
  net = gross - esc_cost - brain_prem
  printf "AGENTS_START\n"
  for (a in n) printf "%s\t%d\t%.4f\t%.4f\t%.4f\n", a, n[a], R[a], C[a], (C[a]-R[a])
  printf "AGENTS_END\n"
  printf "ESC\t%d\t%.4f\n", esc_n+0, esc_cost+0
  printf "BRAIN\t%d\t%.4f\n", brain_n+0, brain_prem+0
  printf "NET\t%.4f\nGROSS\t%.4f\n", net, gross
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

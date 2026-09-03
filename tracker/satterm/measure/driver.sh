#!/usr/bin/env bash
# Sequential driver: one JVM at a time, 120 s timeout each, stop walking a family once a run's wall > 90 s.
S=/tmp/claude-1000/-home-dmitry-research-ermine/8ad54026-1a3a-4b68-a018-ea52aca01453/scratchpad/satterm/measure
E=/home/dmitry/research/ermine/ermine-scala
lastwall() { tail -1 "$S/runs/RUNS.tsv" | cut -f2; }
over() { awk -v w="$(lastwall)" 'BEGIN{exit !(w > 90)}'; }
echo "driver start $(date)" >> $S/runs/DRIVER.log
# family 1: RowStress
for n in $(seq 2 14); do $S/run.sh $S/rowstress/RowStress$n.e RowStress$n 120; over && { echo "RowStress stop at $n" >> $S/runs/DRIVER.log; break; }; done
# family 2: gen-row-overlap
for n in $(seq 3 9); do $S/run.sh $S/rowprobe/CoStar$n.e CoStar$n 120; over && { echo "CoStar stop at $n" >> $S/runs/DRIVER.log; break; }; done
for n in 4 5 6; do $S/run.sh $S/rowprobe/PartStar$n.e PartStar$n 120; over && { echo "PartStar stop at $n" >> $S/runs/DRIVER.log; break; }; done
for m in Overlap1 Overlap2 OverlapHalf Chain4 Chain8; do $S/run.sh $S/rowprobe/$m.e $m 120; done
# family 3: gen-res-star
for n in $(seq 2 10); do $S/run.sh $S/resprobe/ResStar$n.e ResStar$n 120; over && { echo "ResStar stop at $n" >> $S/runs/DRIVER.log; break; }; done
$S/run.sh $S/resprobe/Gadget.e Gadget 120
# corpus: six .slow divergers + gu01 + gu05
for f in gu02_star_join_7dim_inferred.slow gu03_star_join_8dim_inferred.slow gu07_label_helper_callsite.slow gu09_star_join_halves_composed.slow np05a_inferring_the_helper.slow np05c_helper_at_a_call_site.slow gu01_star_join_6dim_inferred.e gu05_star_join_4dim_concrete_signature.e; do
  $S/run.sh $E/core/examples/incomplete/$f "${f%%_*}" 120
done
echo "driver done $(date)" >> $S/runs/DRIVER.log

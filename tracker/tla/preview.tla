------------------------------- MODULE preview -------------------------------
(*****************************************************************************)
(* UNCHECKED.  THIS FILE HAS NEVER BEEN PARSED BY SANY, NEVER TRANSLATED,    *)
(* NEVER RUN THROUGH TLC OR ANY OTHER TOOL.  It is a DRAFT SKELETON written  *)
(* by reading core/src/main/scala/com/clarifi/reporting/ermine/lsp/          *)
(* Preview.scala at b7b93daa and editor/vscode/src/preview-core.js.  Expect  *)
(* syntax errors, missing conjuncts, and at least one wrong invariant.  Its  *)
(* purpose is to show the SHAPE and the SIZE of the model, not to be right.  *)
(*                                                                          *)
(* WHY PLAIN TLA+ AND NOT PLUSCAL.  PlusCal's labels are its atomicity       *)
(* boundaries, and here the atomicity boundaries are already explicit in the *)
(* code: every interesting step is a `lock.synchronized { ... }` block       *)
(* (Preview.scala:80 names the monitor and says what may not be done under   *)
(* it).  One TLA+ action per locked block is a FAITHFUL translation; PlusCal *)
(* would ask me to re-invent the same boundaries as labels and would hide    *)
(* them behind a translator.  If a reader prefers PlusCal, the mapping is    *)
(* one process per thread (dispatch, preview, timer, client) and one label   *)
(* per action below.                                                        *)
(*****************************************************************************)
EXTENDS Naturals, Sequences, FiniteSets, TLC

CONSTANTS
  Reqs,        \* request ids.  BOUND: {r1, r2} is enough for displacement.
  MaxInv,      \* bound on `invalidate` posts (coalescing needs 2)
  MaxFire,     \* bound on watchdog fires (2 reaches phase 2b after a phase 1)
  MaxCrash,    \* bound on preview-thread crashes (1)
  CancelOn     \* ermine.preview.cancelOnTimeout: run the model TRUE and FALSE

NoJob == CHOOSE x : x \notin Reqs
Kinds == {"render", "schema"}          \* the two Answering job kinds (:96)
Outcomes == {"ok", "failed", "threwNonFatal", "threwFatal", "wedged"}
  \* "failed"        = a 500 BY RETURNING; `evalFailed` (Preview.scala:516,
  \*                   :1157) -- the poisoning path DD-1 found.
  \* "threwNonFatal" = escapes the nets; `threw` (:950)
  \* "threwFatal"    = isFatal (:1261): Error or not NonFatal -> never recovers
  \* "wedged"        = never ends on its own; only the watchdog acts

VARIABLES
  \* ---- server state under Preview.lock (Preview.scala:80-191) -------------
  queue,          \* Seq of job records; Preview.scala:81
  inFlight,       \* job record or NoJob; :96
  claimed,        \* answeredInFlight, per in-flight job; :191, claimAnswer :196
  cancelledIn,    \* cancelledInFlight; :97
  stopping,       \* :98
  alive,          \* :176 (volatile; loop's finally :1421)
  stuck,          \* :128
  stuckJob,       \* :142
  stuckSeq,       \* :167
  dirtyGen,       \* dirtyGeneration; :216 (bumped per POST, :777)
  bootToken,      \* at most one outstanding progress token; :351
  \* ---- watchdog (timer thread) -------------------------------------------
  armEpoch,       \* :420, bumped by arm :2150 and disarm :2175
  armed,          \* the armed TimerTask's job+epoch, or NoJob; :407
  cancelTask,     \* phase-2 task; :428
  cancelTarget,   \* ErmineRuntime.cancelTarget: "none" | "preview"; :2288/:2336
  fireCount,
  \* ---- preview thread ----------------------------------------------------
  pc,             \* "idle","taken","boot","eval","catchCancel","catchThrow",
                  \* "finDisarm","finClear","finAnswer","finInFlight",
                  \* "finDiscard","finStuck","done","dead"
  outcome,        \* how the running job will end (chosen when it starts)
  threw, evalFailed, cancelledFlag, cancelDiscarded,   \* :950,:516,:956,:960
  session,        \* "none" | "up"   (runner/sessionUp :342, :462)
  crashCount,
  \* ---- the wire and the client -------------------------------------------
  wire,           \* SET of messages not yet delivered: delivery is UNORDERED
                  \* between the timer thread and the preview thread (:149-158)
  delivered,      \* Seq of messages the client has processed (for properties)
  client,         \* [view |-> BOOLEAN, highWater |-> Nat, running |-> BOOLEAN,
                  \*  rerender |-> BOOLEAN]  -- preview-core.js:292-370
  invCount

vars == << queue, inFlight, claimed, cancelledIn, stopping, alive, stuck,
           stuckJob, stuckSeq, dirtyGen, bootToken, armEpoch, armed,
           cancelTask, cancelTarget, fireCount, pc, outcome, threw, evalFailed,
           cancelledFlag, cancelDiscarded, session, crashCount, wire,
           delivered, client, invCount >>

Job(id, k) == [id |-> id, kind |-> k]

(*****************************************************************************)
(* INIT                                                                      *)
(*****************************************************************************)
Init ==
  /\ queue = << >>  /\ inFlight = NoJob  /\ claimed = FALSE
  /\ cancelledIn = FALSE /\ stopping = FALSE /\ alive = TRUE
  /\ stuck = FALSE /\ stuckJob = NoJob /\ stuckSeq = 0
  /\ dirtyGen = 0 /\ bootToken = "none"
  /\ armEpoch = 0 /\ armed = NoJob /\ cancelTask = NoJob
  /\ cancelTarget = "none" /\ fireCount = 0
  /\ pc = "idle" /\ outcome = "ok"
  /\ threw = FALSE /\ evalFailed = FALSE
  /\ cancelledFlag = FALSE /\ cancelDiscarded = FALSE
  /\ session = "none" /\ crashCount = 0
  /\ wire = {} /\ delivered = << >>
  /\ client = [view |-> FALSE, highWater |-> 0, running |-> TRUE,
               rerender |-> FALSE]
  /\ invCount = 0

(*****************************************************************************)
(* NEXT, as NAMED DISJUNCTS.  Each names the code it abstracts.              *)
(*****************************************************************************)

\* --- dispatch thread: Preview.render :553 / Preview.schema :649 ------------
ReqRefuseDead(r, k)     == \* :569  -32603 "the preview thread is not running"
ReqRefuseStopping(r, k) == \* :571  -32800 "the preview is shutting down"
ReqRefuseStuck(r, k)    == \* :579 / :666  result-shaped, stuck: TRUE marker
ReqEnqueue(r, k)        == \* :587 / :667  enqueue + notifyAll
ReqDisplaceRender(r)    == \* :586 dequeueAll Render, each answered -32800
                           \* ("replaced by a newer render") via answerAll :685
CancelRequest(r)        == \* :749  queued -> removed + -32800; in flight ->
                           \* cancelledIn := TRUE, work NOT interrupted
PostInvalidate          == \* :766  guarded by alive /\ ~stopping /\ ~stuck;
                           \* dirtyGen bumped INSIDE the guard (:777);
                           \* COALESCED into the earliest pending slot (:795)
Shutdown                == \* :819  stopping := TRUE, drain every Answering,
                           \* cancelTimer :2497 (this is DM-2's fourth clear)

\* --- preview thread: loop :1399 / takeJob :895 / runJob :940 ---------------
TakeJob ==                 \* :895
  /\ pc = "idle" /\ alive /\ ~stopping /\ queue # << >>
  /\ LET j == Head(queue) IN
     /\ cancelTarget # "preview"       \* :905 LOUD BUG CHECK, then disarm
     /\ queue' = Tail(queue)
     /\ inFlight' = j                  \* reference store that cannot throw
     /\ claimed' = FALSE /\ cancelledIn' = FALSE
     /\ pc' = "taken"
  /\ UNCHANGED << (* ... *) >>

ArmWatchdog     == \* :970 -> arm :2131; armEpoch += 1; armed := (job, epoch)
BootBegin       == \* unwatched :2204: disarm FIRST, so the boot is UNWATCHED
BootEnd         == \* :2052 session := "up"; finally arm(job) again
EvalStep        == \* the evaluation: a stuttering step that EXISTS so the
                   \* timer thread can interleave anywhere inside it
JobEnds         == \* doRender :1659 / doSchema :1730 returns with `outcome`
CatchCancelled  == \* :996  cancelled := TRUE; threw := TRUE;
                   \* THEN clearCancel :1020, THEN discardSession :1022,
                   \* THEN finish :1024 -- DM-1's order, and the invariant
                   \* CancelClearedBeforeCancelAnswer is what pins it
CatchThrowable  == \* :1027  fatal := isFatal(e); threw := TRUE; finish(500)
FinDisarm       == \* :1045
FinClearCancel  == \* :1051  idempotent catch-all, EVERY job
FinReleaseToken == \* :1054
FinClaimAnswer  == \* :1058-1071 claimAnswer, else crashAnswer :208
FinClearInFlight== \* :1072  inFlight := NoJob
FinCancelDiscard== \* :1095  UNCONDITIONAL discard on the cancel path
FinClearStuck   == \* :1114 -> clearStuck :1298 (only if stuckJob = this job)
FinRecoveryDiscard == \* :1157  if ~cancelled /\ (threw \/ evalFailed)
FinRecovered    == \* :1168 -> recovered :1360: {stuck: FALSE, seq} + showMessage
ThreadCrash     == \* loop's catch :1407: rescueInFlight :1439 then continue,
                   \* or MaxLoopFailures -> alive := FALSE
DrainOnDeath    == \* :1453  rescueInFlight + answer everything queued

\* --- timer thread: fire :2245 ---------------------------------------------
FireGuard(j, e) == (inFlight = j) /\ (e = armEpoch) /\ ~claimed   \* :2281/:2373

FirePhase1Cancel ==        \* fireCancel :2276, only when CancelOn
  /\ CancelOn /\ armed # NoJob /\ FireGuard(armed.job, armed.epoch)
  /\ ~stopping                                \* :2281
  /\ cancelTarget = "none"                    \* armCancel refuses otherwise
  /\ cancelTarget' = "preview"
  /\ cancelTask' = armed                      \* phase 2 scheduled
  /\ fireCount' = fireCount + 1
  /\ UNCHANGED << (* nothing answered, nothing stuck, nothing drained *) >>

FirePhase1Refused ==       \* :2309 armCancel refused -> straight to fireStuck
FirePhase2Fallback ==      \* firePhase2 :2332: disarmCancel FIRST (:2336),
                           \* then fireStuck
FireStuckClaim ==          \* fireStuck :2367-2400, ONE locked step:
                           \* claimed := TRUE; stuck := TRUE; stuckWhy;
                           \* stuckJob := job; stuckSeq += 1;
                           \* cancelled := cancelledIn; queue drained to a local
FireStuckAnswer ==         \* :2412 -32800 if cancelledIn else stuckRefusal
FireStuckDrain ==          \* :2414 every queued Answering -> stuckRefusal
FireStuckNotify ==         \* :2437 showMessage(Error) and :2450
                           \* ermine/preview/stuck {stuck: TRUE, seq}

\* --- the wire and the client (preview-core.js) ----------------------------
Deliver(m) ==              \* UNORDERED: any message in `wire` may be next.
                           \* This is the whole point: the rising edge is the
                           \* TIMER thread's and the falling edge is the
                           \* PREVIEW thread's, with nothing ordering them
                           \* (Preview.scala:149-158).
ClientNotification(m) ==   \* preview-core.js:306-335, rule (1) high-water
ClientAnswerMarker(m)  ==  \* :337-342, rule (3) seqAtSend
ClientRestart ==           \* :344-359, DD-2: highWater := 0 on Running

Next ==
  \/ \E r \in Reqs, k \in Kinds :
        ReqRefuseDead(r,k) \/ ReqRefuseStopping(r,k) \/ ReqRefuseStuck(r,k)
        \/ ReqEnqueue(r,k) \/ ReqDisplaceRender(r) \/ CancelRequest(r)
  \/ PostInvalidate \/ Shutdown
  \/ TakeJob \/ ArmWatchdog \/ BootBegin \/ BootEnd \/ EvalStep \/ JobEnds
  \/ CatchCancelled \/ CatchThrowable
  \/ FinDisarm \/ FinClearCancel \/ FinReleaseToken \/ FinClaimAnswer
  \/ FinClearInFlight \/ FinCancelDiscard \/ FinClearStuck
  \/ FinRecoveryDiscard \/ FinRecovered
  \/ ThreadCrash \/ DrainOnDeath
  \/ FirePhase1Cancel \/ FirePhase1Refused \/ FirePhase2Fallback
  \/ FireStuckClaim \/ FireStuckAnswer \/ FireStuckDrain \/ FireStuckNotify
  \/ \E m \in wire : Deliver(m)
  \/ ClientRestart

(*****************************************************************************)
(* FAIRNESS.  The preview thread and the timer are fair; the CLIENT is not   *)
(* (it may never send another request), and a CRASH is not (it may never     *)
(* happen).  Delivery is fair: the wire is a pipe, not a lossy channel.      *)
(*****************************************************************************)
Fairness ==
  /\ WF_vars(TakeJob \/ ArmWatchdog \/ BootBegin \/ BootEnd \/ JobEnds
             \/ CatchCancelled \/ CatchThrowable \/ FinDisarm \/ FinClearCancel
             \/ FinReleaseToken \/ FinClaimAnswer \/ FinClearInFlight
             \/ FinCancelDiscard \/ FinClearStuck \/ FinRecoveryDiscard
             \/ FinRecovered \/ DrainOnDeath)
  /\ WF_vars(FirePhase1Cancel \/ FirePhase1Refused \/ FirePhase2Fallback
             \/ FireStuckClaim \/ FireStuckAnswer \/ FireStuckDrain
             \/ FireStuckNotify)
  /\ \A m \in Reqs : WF_vars(\E x \in wire : Deliver(x))

Spec == Init /\ [][Next]_vars /\ Fairness

(*****************************************************************************)
(* SAFETY.  Each names its source: T = stated in tracker/                    *)
(* JSON-WIDGET-PLAYGROUND.md, C = read out of the code, I = inferred by me.  *)
(*****************************************************************************)
\* T  §2.5 "one in flight, at most one queued, latest wins"
AtMostOneQueuedRender ==
  Cardinality({i \in 1..Len(queue) : queue[i].kind = "render"}) <= 1
\* C  Preview.scala:792 "at most one Invalidate in the queue"
AtMostOneQueuedInvalidate == TRUE  \* modelled as a counter, not a job, here
\* C  Rpc.deferredRequest :641-646 one-shot + claimAnswer :196
AtMostOneAnswerPerRequest ==
  \A r \in Reqs : Cardinality({m \in Range(delivered) :
                     m.kind = "answer" /\ m.id = r}) <= 1
\* T  §4 "a displaced render is answered -32800"; I: and never runs
NoWorkAfterDisplacement ==
  \A r \in Reqs : Displaced(r) => (inFlight = NoJob \/ inFlight.id # r)
\* C  Preview.scala:2288 armCancel(thread, ...) + :905 + :1051
CancelArmedOnlyForRunningJob ==
  (cancelTarget = "preview") => (inFlight # NoJob /\ pc \in {"eval","boot"})
\* C  takeJob :896-909 "NO JOB IS EVER HANDED OUT WITH A CANCEL STILL ARMED"
NoCancelArmedAtTakeJob == (pc = "idle") => (cancelTarget = "none")
\* C  DM-1, Preview.scala:1000-1024: clear, discard, THEN answer
CancelClearedBeforeCancelAnswer ==
  \A m \in Range(delivered) :
     (m.kind = "answer" /\ m.text = "cancelled") => m.cancelTargetAtSend = "none"
\* C  fireStuck :2375-2387 -- one locked step sets all three
StuckPairWellFormed ==
  stuck => (stuckSeq > 0 /\ (stuckJob # NoJob \/ ForgottenFatal))
\* I  the seq contract of §4 rule (1), restated as an invariant on the wire
SeqStrictlyMonotonic ==
  \A m1, m2 \in Range(delivered) :
     (m1.kind = "stuckNote" /\ m2.kind = "stuckNote" /\ m1.seq = m2.seq)
       => m1 = m2
\* T  §4 Q8: the marker is on EXACTLY four answers and nothing else
MarkerWellFormed ==
  \A m \in Range(delivered) :
     m.kind = "answer" => (m.stuckMarker <=> m.reason \in
        {"refusedWhileStuck", "watchdogAnswer", "watchdogDrain"})
\* C  WP-5B: fireStuck :2399 drains, so nothing is left with no consumer
NothingQueuedWhileStuck == stuck => (queue = << >>)
\* C  DM-2: shutdown inside the grace must not leak the arming
NoArmedCancelWhenIdle == (stopping /\ pc = "idle") => cancelTarget = "none"
\* I  the client's view is the server's view as of the highest seq it has seen
ClientNeverLatchesWrongly ==
  (client.view /\ ~stuck) => (\E m \in wire : m.kind = "stuckNote")

(*****************************************************************************)
(* LIVENESS, under Fairness above.                                           *)
(*****************************************************************************)
\* T  §2.5 / the whole design: "a request that is dropped without an answer is
\*    a request the client waits on for ever" (Preview.scala:581-585)
EveryRequestAnswered ==
  \A r \in Reqs : Requested(r) ~> Answered(r)
\* T  Q10: "the stuck state CLEARS if the job the watchdog fired on returns"
StuckEventuallyClears ==
  (stuck /\ outcome # "wedged" /\ outcome # "threwFatal") ~> ~stuck
\* I  the WP-7 defect, as a temporal property of the CLIENT
ClientEventuallyRerenders ==
  (stuck /\ outcome \notin {"wedged","threwFatal"}) ~> client.rerender
\* C  loop :1418-1425 -- the outermost finally is the contract
NoOutstandingWhenDead ==
  (~alive) ~> (\A r \in Reqs : Requested(r) => Answered(r))

(*****************************************************************************)
(* BOUNDS I WOULD USE FOR THE FIRST TLC RUN.  Expected: seconds to minutes.  *)
(*   Reqs = {r1, r2}      (one in flight + one displaced is the whole rule)  *)
(*   MaxInv = 2           (coalescing needs two posts)                       *)
(*   MaxFire = 2          (phase 1 then phase 2b)                            *)
(*   MaxCrash = 1                                                            *)
(*   CancelOn: TWO RUNS, FALSE then TRUE (it is a default-OFF switch)        *)
(*   Outcomes: all five                                                      *)
(* A state constraint caps fireCount, invCount and crashCount so the model   *)
(* is finite: /\ fireCount <= MaxFire /\ invCount <= MaxInv                  *)
(*            /\ crashCount <= MaxCrash                                      *)
(*****************************************************************************)
=============================================================================

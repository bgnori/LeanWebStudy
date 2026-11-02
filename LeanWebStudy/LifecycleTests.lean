import StdExt.Http.WebSocket.Lifecycle

namespace LeanWebStudy.LifecycleTests

open Std.Http.WebSocket.Lifecycle

private def limits : Limits := ⟨2, 8⟩

private def run (events : List Event) : Except Error (State × List Effect) :=
  events.foldlM (fun (s, effects) event => do
    let (s, next) ← step limits s event
    pure (s, effects ++ next)) ({}, [])

private def fails (events : List Event) (expected : Error) : Bool :=
  match run events with
  | .error actual => actual == expected
  | .ok _ => false

private def graceful := run [
  .submit 3, .submit 4, .localClose,
  .reserve, .start 2, .writeDone 2 .written,
  .reserve, .start 3, .writeDone 3 .written,
  .reserve, .start 4, .writeDone 4 .written,
  .peerClose, .backendDone, .release]

#guard match graceful with
  | .ok (s, effects) => s.released && s.results == [(0, .written), (1, .written)] &&
      effects == [
        .accepted 0, .accepted 1, .write ⟨2, .data 0 3⟩, .result 0 .written,
        .write ⟨3, .data 1 4⟩, .result 1 .written, .write ⟨4, .close⟩,
        .finishSend, .releaseOwned]
  | _ => false

#guard fails [.submit 5, .submit 4] .capacity
#guard fails [.submit 1, .localClose, .submit 1] .closed
#guard fails [.submit 1, .reserve, .abort, .start 1] .closed
#guard fails [.beginRead, .deadline, .backendDone, .release] .busy
#guard fails [.beginRead, .beginRead] .busy
#guard fails [.submit 1, .reserve, .start 1, .writeDone 7 .written] .invalidEvent
#guard fails [.submit 1, .reserve, .start 1, .writeDone 1 .written,
  .writeDone 1 .written] .invalidEvent
#guard match run [.submit 1, .reserve, .start 1, .deadline, .backendDone,
    .writeDone 1 .cancelled, .release] with
  | .ok (s, _) => s.released && s.results == [(0, .cancelled)]
  | _ => false
#guard match run [.submit 2, .submit 3, .reserve, .peerClose,
    .reserve, .start 3, .writeDone 3 .written, .backendDone, .release] with
  | .ok (s, _) => s.released && s.results == [(1, .cancelled), (0, .cancelled)]
  | _ => false
#guard match run [.submit 2, .reserve, .start 1, .writeDone 1 .failed,
    .backendDone, .release] with
  | .ok (s, _) => s.released && s.results == [(0, .failed)]
  | _ => false
#guard fails [.localClose, .reserve, .start 0, .reserve] .closed
#guard fails [.submit 5, .reserve, .start 1, .submit 4] .capacity
#guard fails [.submit 1, .submit 1, .submit 1] .capacity
#guard fails [.submit 1, .reserve, .start 1, .abort, .backendDone, .release] .busy
#guard fails [.localClose, .reserve, .start 0, .writeDone 0 .failed, .reserve] .closed
#guard fails [.submit 1, .reserve, .start 1, .writeDone 1 .cancelled] .invalidEvent
#guard fails [.abort, .backendDone, .release, .release] .busy
#guard match run [.beginRead, .deadline, .backendDone, .readDone 0, .release] with
  | .ok (s, effects) => s.released &&
      effects == [.read 0, .abortBackend, .releaseOwned]
  | _ => false
#guard match run [.localClose, .localClose, .reserve, .start 0,
    .peerClose, .writeDone 0 .written, .peerClose, .backendDone, .release] with
  | .ok (_, effects) => effects == [.write ⟨0, .close⟩, .finishSend, .releaseOwned]
  | _ => false

private def validState (s : State) : Bool :=
  let ids := s.results.map Prod.fst
  ids.eraseDups.length == ids.length &&
    outstanding s <= limits.requests && retainedBytes s <= limits.bytes &&
    !(s.reserved.isSome && s.writing.isSome) &&
    (!s.released || quiet s)

private def validEffects (before : State) (effects : List Effect) : Bool :=
  effects.all fun effect => match effect with
    | .write ⟨_, .data ..⟩ => !before.closeStarted && !before.stopping && !before.peerClosed
    | .write ⟨_, .close⟩ => !before.closeStarted && before.writing.isNone
    | .releaseOwned => quiet before && !before.released
    | _ => true

private def explore (depth : Nat) (s : State) (history : List Event) : IO Nat := do
  unless validState s do
    throw <| IO.userError s!"Lifecycle invariant failed: {repr history}"
  match depth with
  | 0 => pure 1
  | n + 1 =>
    let writeId := (s.writing.map (·.id)).getD s.nextId
    let reservedId := (s.reserved.map (·.id)).getD s.nextId
    let readId := s.reading.getD s.nextId
    let events : List Event := [
      .submit 3, .submit 6, .localClose, .peerClose, .abort, .deadline,
      .reserve, .start reservedId, .writeDone writeId .written,
      .writeDone writeId .failed, .writeDone writeId .cancelled,
      .beginRead, .readDone readId, .backendDone, .release]
    events.foldlM (fun count event => do
      match step limits s event with
      | .error _ => pure count
      | .ok (next, effects) =>
        unless validEffects s effects do
          throw <| IO.userError s!"Lifecycle effect failed: {repr (history ++ [event])}"
        let visited ← explore n next (history ++ [event])
        pure (count + visited)) 1

def test : IO Unit := do
  let count ← explore 5 {} []
  IO.println s!"PASS: lifecycle deterministic traces and {count} bounded exploration nodes"

end LeanWebStudy.LifecycleTests

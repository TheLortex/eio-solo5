

module Suspended = Eio_utils.Suspended
module Fiber_context = Eio.Private.Fiber_context
module Lf_queue = Eio_utils.Lf_queue
module Zzz = Eio_utils.Zzz

exception Deadlock_detected

(* The scheduler could just return [unit], but this is clearer. *)
type exit = [ `Exit_scheduler ]

type runnable =
  | Thread : 'a Suspended.t * 'a -> runnable
  | Failed_thread : 'a Suspended.t * exn -> runnable

type t = {
  (* Suspended fibers waiting to run again.
     [Lf_queue] is like [Stdlib.Queue], but is thread-safe (lock-free) and
     allows pushing items to the head too, which we need. *)
  run_q : runnable Lf_queue.t;
  sleep_q: Zzz.t;                       (* Fibers waiting for timers. *)
  io_q : (int64, unit Suspended.t) Hashtbl.t;
}

(* Resume the next runnable fiber, if any. *)
let rec schedule t : exit =
  match Lf_queue.pop t.run_q with
  | Some (Thread (k, v)) ->
    Fiber_context.clear_cancel_fn k.fiber;
    Suspended.continue k v
  | Some (Failed_thread (k, ex)) ->
    Fiber_context.clear_cancel_fn k.fiber;
    Suspended.discontinue k ex
  | None ->
    let now = Time.now () in
    match Zzz.pop ~now t.sleep_q with
    | `Due k -> Suspended.continue k ()
    | (`Wait_until _ | `Nothing as e) ->
        let time =
          match e with
          | `Nothing when
              Hashtbl.length t.io_q = 0 && Lf_queue.is_empty t.run_q -> None
          | `Nothing -> Some (86_400_000_000_000L) (* 1 day *)
          | `Wait_until time -> Some (Mtime.to_uint64_ns time)
        in
        match time with
        | None -> `Exit_scheduler
        | Some time ->
          (* let now = Mtime.to_uint64_ns now in *)
          (* let diff_ns = Int64.sub time now in *)
          (* Eio.traceln "yield %Ld %d" diff_ns (Hashtbl.length t.io_q); *)
          let ready_set = Time.solo5_yield time in
          (* Eio.traceln "yield > %Ld" ready_set; *)
          if Int64.equal ready_set 0L then
            schedule t
          else
            match
              Hashtbl.to_seq_keys t.io_q
              |> Seq.find (fun x ->
                not Int64.(equal 0L (logand ready_set (shift_left 1L (to_int x)))))
              with
            | None -> schedule t
            | Some key ->
              let work = Hashtbl.find t.io_q key in
              Hashtbl.remove t.io_q key;
              Suspended.continue work ()

type _ Effect.t += Enter : (t -> 'a Eio_utils.Suspended.t -> [`Exit_scheduler]) -> 'a Effect.t

let enter fn = Effect.perform (Enter fn)

let wait_for_work_on_handle handle =
  enter @@ fun t k ->
  Hashtbl.add t.io_q handle k;
  schedule t

(* Run [main] in an Eio main loop. *)
let run main =
  let t =
    { run_q = Lf_queue.create ();
      sleep_q = Zzz.create ();
      io_q = Hashtbl.create 0 }
  in
  let rec fork ~new_fiber:fiber fn =
    (* Create a new fiber and run [fn] in it. *)
    Effect.Deep.match_with fn ()
      { retc = (fun () -> Fiber_context.destroy fiber; schedule t);
        exnc = (fun ex ->
            let bt = Printexc.get_raw_backtrace () in
            Fiber_context.destroy fiber;
            Printexc.raise_with_backtrace ex bt
          );
        effc = fun (type a) (e : a Effect.t) : ((a, exit) Effect.Deep.continuation -> exit) option ->
          match e with
          | Enter fn -> Some (fun k ->
              match Fiber_context.get_error fiber with
              | Some e -> Effect.Deep.discontinue k e
              | None -> fn t { Suspended.k; fiber }
            )
          | Eio.Private.Effects.Suspend f -> Some (fun k ->
              (* Ask [f] to register whatever callbacks are needed to resume the fiber.
                 e.g. it might register a callback with a promise, for when that's resolved. *)
              let k = { Suspended.k; fiber } in
              f fiber (function
                  | Ok v -> Lf_queue.push t.run_q (Thread (k, v))
                  | Error ex -> Lf_queue.push t.run_q (Failed_thread (k, ex))
                );
              (* Switch to the next runnable fiber while this one's blocked. *)
              schedule t
            )
          | Eio.Private.Effects.Fork (new_fiber, f) -> Some (fun k ->
              let k = { Suspended.k; fiber } in
              (* Arrange for the forking fiber to run immediately after the new one. *)
              Lf_queue.push_head t.run_q (Thread (k, ()));
              (* Create and run the new fiber (using fiber context [new_fiber]). *)
              fork ~new_fiber f
            )
          | Eio.Private.Effects.Get_context -> Some (fun k ->
              Effect.Deep.continue k fiber
            )
          | _ -> None
      }
  in
  let new_fiber = Fiber_context.make_root () in
  let result = ref None in
  let `Exit_scheduler = fork ~new_fiber (fun () -> result := Some (main ())) in
  match !result with
  | None -> raise Deadlock_detected
  | Some x -> x

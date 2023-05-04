type stdenv = <
  clock : Eio.Time.clock;
  mono : Eio.Time.Mono.t;
  netif : string ->
    <
    send: Cstruct.t -> unit;
    recv: Cstruct.t -> int;
    mac: Macaddr.t;
    mtu: int>;
>


module Fiber_context = Eio.Private.Fiber_context
module Zzz = Eio_utils.Zzz

let clock = object

  method now =
    (Time.now () |> Mtime.to_uint64_ns |> Int64.to_float) /. 1_000_000_000.

  method sleep_until time =
    let time =
      Int64.of_float (time *. 1_000_000_000.) |> Mtime.of_uint64_ns
    in
    Sched.enter @@ fun t k ->
    match Fiber_context.get_error k.fiber with
    | Some e -> Eio_utils.Suspended.discontinue k e
    | None ->
      let node = Zzz.add t.sleep_q time k in
      Fiber_context.set_cancel_fn k.fiber (fun ex ->
        Zzz.remove t.sleep_q node;
        Eio_utils.Lf_queue.push t.run_q (Failed_thread(k, ex))
      );
      Sched.schedule t

end

let mono : Eio.Time.Mono.t = object

  method now = Time.now ()

  method sleep_until time =
    Sched.enter @@ fun t k ->
    match Fiber_context.get_error k.fiber with
    | Some e -> Eio_utils.Suspended.discontinue k e
    | None ->
      let node = Zzz.add t.sleep_q time k in
      Fiber_context.set_cancel_fn k.fiber (fun ex ->
        Zzz.remove t.sleep_q node;
        Eio_utils.Lf_queue.push t.run_q (Failed_thread(k, ex))
      );
      Sched.schedule t

end

let stdenv = object

  method clock = clock

  method mono = mono

  method netif devname =
    let result, handle, ni =
      Netif.solo5_net_acquire devname
    in
    match result with
    | SOLO5_R_OK -> Netif.flow devname handle ni
    | SOLO5_R_AGAIN -> failwith "unexpected response from solo5"
    | SOLO5_R_EINVAL ->
        failwith (Fmt.str "Netif: connect(%s): Invalid argument" devname)
    | SOLO5_R_EUNSPEC ->
        failwith (Fmt.str "Netif: connect(%s): Unspecified error" devname)

end

let run fn =
  Sched.run @@ fun () -> fn stdenv

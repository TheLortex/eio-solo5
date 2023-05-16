module Arp = Arp.Make (Ethernet)
module Ip = Static_ipv4.Make (Ethernet) (Arp)
module Icmp = Icmpv4.Make (Ip)
module Tcp = Tcp.Flow.Make (Ip)

let stack ~net ~mono ~random ~clock ~cidr fn =
  Eio.Switch.run @@ fun sw ->
  let netv =
    object
      method recv buf =
        (* Eio.traceln "WAITIN"; *)
        let len = net#recv buf in
        (* Eio.traceln "IN";
           Eio.traceln "%s" (Cstruct.to_hex_string ~len buf); *)
        len

      method sendv buf =
        let buf = Cstruct.concat buf in
        (* Eio.traceln "OUT";
           Eio.traceln "%s" (Cstruct.to_hex_string buf); *)
        net#send buf

      method mac = net#mac
      method mtu = net#mtu
    end
  in
  let ethernet = Ethernet.connect netv in
  let arp = Arp.connect ~sw ~clock ethernet in
  let ip = Ip.connect ~mono ~random ~cidr ethernet arp in
  let icmp = Icmp.connect ip in
  let tcp = Tcp.connect ~sw ~mono ~random ~clock ip in
  let ign ~src:_ ~dst:_ _ = () in
  let ipv4 =
    Ip.input ip ~tcp:(Tcp.input tcp) ~udp:ign
      ~default:(fun ~proto ~src ~dst buf ->
        match proto with 1 -> Icmp.input icmp ~src ~dst buf | _ -> ())
  in
  Eio.Fiber.fork_daemon ~sw (fun () ->
      while true do
        let buffer = Cstruct.create_unsafe net#mtu in
        let len = netv#recv buffer in
        Eio.Fiber.fork ~sw (fun () ->
            Ethernet.input ~arpv4:(Arp.input arp) ~ipv4 ~ipv6:(Fun.const ())
              ethernet (Cstruct.sub buffer 0 len))
      done;
      `Stop_daemon);
  let net =
    object
      method connect ~sw:_ _ = failwith "TODO"

      method datagram_socket ~reuse_addr:_ ~reuse_port:_ ~sw:_ _ =
        failwith "TODO"

      method getaddrinfo ~service:_ _ = failwith "TODO"
      method getnameinfo _ = failwith "TODO"

      method listen ~reuse_addr:_ ~reuse_port:_ ~backlog:_ ~sw:_ stream =
        match stream with
        | `Tcp (_ip, port) ->
            let waiters_cond = Eio.Condition.create () in
            let waiters = Queue.create () in
            let listening_socket =
              object
                method accept ~sw:_ =
                  let promise, resolver = Eio.Promise.create () in
                  Queue.add resolver waiters;
                  Eio.Condition.broadcast waiters_cond;
                  let res = Eio.Promise.await promise in
                  let ip, port = res#dst in
                  ( (res :> < Eio.Net.stream_socket ; Eio.Flow.close >),
                    `Tcp
                      (ip |> Ipaddr.V4.to_octets |> Eio.Net.Ipaddr.of_raw, port)
                  )

                method close = Tcp.unlisten tcp ~port

                method probe : type a. a Eio.Generic.ty -> a option =
                  fun _ -> None
              end
            in
            let rec add flow =
              match Queue.take_opt waiters with
              | None ->
                  Eio.Condition.await_no_mutex waiters_cond;
                  add flow
              | Some v -> Eio.Promise.resolve v flow
            in
            Tcp.listen tcp ~port add;
            listening_socket
        | _ -> failwith "TODO"
    end
  in

  let env =
    object
      method net = net
      method clock = clock
      method mono_clock = mono
      method secure_random = random
    end
  in
  let message = String.make 100000 'a' in
  Eio.Fiber.both
    (fun () ->
      Dream__mirage.Mirage.https ~port:443 env (fun _request ->
          Dream__mirage.Mirage.respond "Thanks"))
    (fun () ->
      Dream__mirage.Mirage.http ~port:80 env (fun _request ->
          Dream__mirage.Mirage.respond message));

  fn ()

let random =
  let best_rng = Cstruct.of_string (String.make 10000000 'a') in

  for i = 0 to 10000000 - 1 do
    Cstruct.set_uint8 best_rng i (((i * 27653201) + 24324) mod 255)
  done;

  Eio.Flow.cstruct_source [ best_rng ]

let net ~env ~netif () =
  stack ~net:netif ~mono:env#mono ~random ~clock:env#clock
    ~cidr:(Ipaddr.V4.Prefix.of_string_exn "10.0.0.2/24")
  @@ fun () ->
  while true do
    Eio.Time.sleep env#clock 10.
  done

let program ~clock:_ ~env ~netif () =
  Eio.Switch.run @@ fun _sw ->
  Eio.traceln "net starting";
  net ~env ~netif ();
  Eio.traceln "net finished"

let () =
  Logs.set_level (Some Info);
  Logs.set_reporter (Logs_fmt.reporter ());
  Eio_solo5.run @@ fun env ->
  program ~clock:env#clock ~env ~netif:(env#netif "service") ()

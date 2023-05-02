

let a = ref 0

let b = ref 0

let c = ref 0

let msg = ref ""

let loop1 ~clock () =
  while true do
    incr a;
    Eio.Time.sleep clock 0.134;
  done

let loop2 ~clock () =
  while true do
    incr b;
    Eio.Time.sleep clock 1.0;
  done

let loop3 ~clock () =
  while true do
    incr c;
    Eio.Time.sleep clock 0.0037;
  done

let printer ~clock () =
  while true do
    Eio.Time.sleep clock 0.05;
    Printf.printf "%5d %5d %5d %s\r%!" !a !b !c !msg;
  done

let net ~netif () =
  let buffer = Cstruct.create_unsafe 1024 in
  while true do
    let len = Eio.Flow.single_read netif buffer in
    msg := Cstruct.to_hex_string ~len buffer
  done

let program ~clock ~netif () =
  Eio.Switch.run @@ fun sw ->
  Eio.Fiber.fork ~sw (loop1 ~clock);
  Eio.Fiber.fork ~sw (loop2 ~clock);
  Eio.Fiber.fork ~sw (loop3 ~clock);
  Eio.Fiber.fork ~sw (net ~netif);
  printer ~clock ()

let () =
  Eio_solo5.run @@ fun env ->
  program ~clock:env#clock ~netif:(env#netif "service") ()

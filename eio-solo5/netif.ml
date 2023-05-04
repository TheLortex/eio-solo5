type solo5_result =
  | SOLO5_R_OK
  | SOLO5_R_AGAIN
  | SOLO5_R_EINVAL
  | SOLO5_R_EUNSPEC

type solo5_net_info = { solo5_mac : string; solo5_mtu : int }

external solo5_net_acquire : string -> solo5_result * int64 * solo5_net_info
  = "mirage_solo5_net_acquire"

external solo5_net_read :
  int64 -> Cstruct.buffer -> int -> int -> solo5_result * int
  = "mirage_solo5_net_read_3"

external solo5_net_write : int64 -> Cstruct.buffer -> int -> int -> solo5_result
  = "mirage_solo5_net_write_3"


type 'a ok = #Eio.Flow.source as 'a

let flow devname handle ni =
  let mac = Macaddr.of_octets ni.solo5_mac |> Result.get_ok in
  let mtu = ni.solo5_mtu in
  Eio.traceln "OK: Mac is %s" (Macaddr.to_string mac);
  Eio.traceln "OK: Mtu is %d" mtu;
  object(self)

    method recv (buffer: Cstruct.t) =
      match solo5_net_read handle buffer.buffer buffer.off buffer.len with
      | SOLO5_R_OK, len -> len
      | SOLO5_R_AGAIN, _ ->

        Sched.wait_for_work_on_handle handle;
        self#recv buffer


      | SOLO5_R_EINVAL, _ ->
        failwith (Fmt.str "Netif: connect(%s): Invalid argument" devname)
      | SOLO5_R_EUNSPEC, _ ->
          failwith (Fmt.str "Netif: connect(%s): Unspecified error" devname)


    method send (src : Cstruct.t) =
      solo5_net_write handle src.buffer src.off src.len |> ignore;

    method mac = mac
    method mtu = mtu
  end
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

let flow devname handle _: Eio.Flow.two_way =
  object(self)

    inherit Eio.Flow.two_way

    method shutdown _ = ()

    method read_into (buffer: Cstruct.t) =
      assert (buffer.off = 0);
      match solo5_net_read handle buffer.buffer buffer.off buffer.len with
      | SOLO5_R_OK, len -> len
      | SOLO5_R_AGAIN, _ ->

        Sched.wait_for_work_on_handle handle;
        self#read_into buffer


      | SOLO5_R_EINVAL, _ ->
        failwith (Fmt.str "Netif: connect(%s): Invalid argument" devname)
      | SOLO5_R_EUNSPEC, _ ->
          failwith (Fmt.str "Netif: connect(%s): Unspecified error" devname)

    method copy _source = failwith "e"

  end

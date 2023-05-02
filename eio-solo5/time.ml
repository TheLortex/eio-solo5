external now : unit -> Mtime.t = "caml_get_monotonic_time"

external solo5_yield : int64 -> int64 = "mirage_solo5_yield_2"

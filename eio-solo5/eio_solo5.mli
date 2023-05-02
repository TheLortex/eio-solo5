type stdenv = <
  clock : Eio.Time.clock;
  netif : string -> Eio.Flow.two_way;
>

val run : (stdenv -> 'a) -> 'a

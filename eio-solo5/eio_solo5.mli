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

val run : (stdenv -> 'a) -> 'a

## What is this ?

An http1 webserver using dream over mirage libraries and eio. Highly experimental !
The stack:
- dream
- httpaf
- tls
- mirage-crypto
- mirage-tcpip
- arp, ethernet
- eio-solo5

## eio-solo5 ?

A hacky backend for Eio using solo5 APIs.
Here is the environment signature:
```ocaml
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
```

quite minimal

## setup ?

a bit painful because of opam-monorepo quirks, but it works in CI so don't worry.

```
opam pin https://github.com/mirage/ocaml-solo5.git#500-cleaned -ny
opam install solo5.0.8.0 ocaml-solo5 opam-monorepo dune
git clone https://github.com/TheLortex/eio-solo5
cd eio-solo5
rm -rf networking-experiments/vendor/httpaf/
rm -rf networking-experiments/vendor/luv/test/
sed '/pin-depends:/,/^]/d' -i  dream/src/vendor/httpaf/*.opam
sed '/pin-depends:/,/^]/d' -i  dream/src/vendor/websocketaf/*.opam
opam monorepo lock
opam monorepo pull
dune build _build/solo5/main.exe
```

The obtained image (x86) is available as an artifact of the CI build.
(https://github.com/TheLortex/eio-solo5/actions/runs/5012744312)

To use it, set up a tap device (example: https://gist.github.com/TheLortex/62f01ece1ebf1d9c9465e50084279b68) and call the solo5 tender:
```
solo5-hvt --net:service=tap0 ~/Downloads/main.exe
```

Then, one can ping and curl the service:
```
ping 10.0.0.2
curl http://10.0.0.2
```

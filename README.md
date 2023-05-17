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
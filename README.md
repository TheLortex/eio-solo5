```

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
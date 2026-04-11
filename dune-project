(lang dune 3.21)

(name bulkhead_lm)

(generate_opam_files true)

(source
 (github Louis-Ph/bulkhead-lm))

(authors "Louis-Ph")

(maintainers "Louis-Ph")

(license Apache-2.0)

(package
 (name bulkhead_lm)
 (synopsis "Secure OCaml LLM gateway with OpenAI-compatible endpoints")
 (description
  "A hierarchical, security-first OCaml LLM gateway with routing, budgets, virtual keys, and provider adapters.")
 (depends
  ocaml
  dune
  lwt
  yojson
 uri
  cohttp-lwt-unix
  tls-lwt
  sqlite3
  cmdliner
  linenoise
  logs
  fmt
  x509
  mirage-crypto
  mirage-crypto-ec
  mirage-crypto-rng
  mirage-crypto-rng-unix
  digestif
  uuidm
  base64
  (alcotest :with-test)
  (alcotest-lwt :with-test)))

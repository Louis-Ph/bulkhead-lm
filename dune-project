(lang dune 3.21)

(name aegis_lm)

(generate_opam_files true)

(source
 (github Louis-Ph/aegis-lm))

(authors "Louis-Ph")

(maintainers "Louis-Ph")

(license Proprietary)

(package
 (name aegis_lm)
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
  digestif
  uuidm
  base64
  (alcotest :with-test)
  (alcotest-lwt :with-test)))

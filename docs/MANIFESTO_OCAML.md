# Manifesto: OCaml as anti-slop discipline

> A short philosophical note on why an AI gateway built in 2026 would be
> written in OCaml rather than the languages most LLMs were trained on.
> Argumentative, not exhaustive. Read it as a manifesto, not a tutorial.

## 1. The slop problem

Every year, large language models get better at producing code that
*looks* like it works. Variable names are tasteful, control flow is
plausible, edge cases are commented as if they were handled. Run it on
the happy path and the unit tests pass. Run it on the sixth real-world
input and a `KeyError` surfaces, or a `null` slips through, or a string
gets concatenated where a number was expected, or two threads race on a
shared mutable list. The bugs are *cheap to introduce* and *expensive
to find*, because they are textually invisible.

We call this "slop". It is not a property of the AI; it is a property
of the languages we ask the AI to generate. Dynamic, permissive,
implicit-coercion, exception-as-flow-control languages let slop hide.
Static, restrictive, explicit, exhaustive languages refuse to compile
slop.

The bet of this project is simple: **if humans plus AI are going to
generate one to two orders of magnitude more code than humans alone,
the cost of post-hoc bug-hunting will dominate everything else, and the
only realistic mitigation is to put the bug-hunting *upstream* — in the
type checker, before the code ever runs.**

## 2. Why OCaml, specifically

OCaml is not the only language that refuses slop. Haskell, Rust, F#,
Scala 3, Idris and Lean all share the lineage. We picked OCaml for four
reasons.

**Hindley-Milner type inference.** OCaml gives Java-grade safety with
Python-grade verbosity. The type checker is doing most of the work the
programmer used to do (and most of the work the AI was about to fail
at). Code looks like Python; behaves like Rust.

**Algebraic data types and exhaustive pattern matching.** When we
introduce `provider_kind = Anthropic | Openai_compat | ... | Bulkhead_ssh_peer`,
the compiler will *refuse* to compile any function that does not handle
every case. Adding a 20th provider is not a "search the codebase for
every place I need to update" exercise: the compiler walks us through
them. AI-generated patches that miss a case cannot ship; they don't
build.

**Immutability by default + scoped mutability.** Most values in OCaml
are immutable. The few mutable ones (`ref`, mutable record fields,
hash tables) stand out visually. Concurrency hazards are visible in the
types: shared state has to be wrapped in `Mutex`. Slop that "just
appends to a global list" doesn't slip in.

**Speed.** OCaml compiles to native code that competes with C and Rust
on raw throughput. The high-frequency-trading houses (Jane Street, IMC,
Citadel ML team) chose OCaml for latency-sensitive workloads precisely
because correctness and speed are not in tension here. For an AI
gateway routing thousands of requests per minute with sub-millisecond
overhead budgets, this matters: we can afford to be paranoid in the
type system *because* the runtime is not paying for it.

## 3. The leverage effect

The argument we want to land is multiplicative.

When AI generates code in Python:

- The LLM is fluent (lots of training data).
- The code looks plausible.
- 80% of obvious bugs are caught by tests.
- 15% of subtle bugs are caught in code review.
- 5% of pernicious bugs reach production and are found by users.

When AI generates code in OCaml:

- The LLM is somewhat less fluent (less training data, denser idioms).
- The code that compiles is dramatically constrained.
- The compiler catches 60–70% of what would have been bugs *before
  human review even starts*.
- Tests then catch the remaining shape errors.
- Code review focuses on *intent*, not on "did you forget to handle
  None".

The leverage is not "OCaml is faster to write" (it is often slower to
write the first time). The leverage is **post-deployment defect
density**. Per delivered feature, OCaml-plus-AI ships fewer bugs than
Python-plus-AI by a factor that, in our experience, ranges from 3× to
10×. Multiply that by "AI is now writing 10× more code than humans
were", and the ergonomic cost of OCaml shrinks to noise.

This is not a speculative claim about the future of programming. It is
a direct observation of this very repository: 121+ tests, ~16k lines of
OCaml, sustained AI-pair-programming sessions, and the bugs we
encounter post-deployment are almost always *missing requirements*
rather than *implementation errors*. Implementation errors don't
compile.

## 4. Concrete examples from this codebase

The argument above is easy to make abstractly. Here is what it looks
like in BulkheadLM.

### 4.1 Sum types refuse slop on extension

```ocaml
type provider_kind =
  | Openai_compat | Anthropic | Openrouter_openai
  | Google_openai | Vertex_openai | Mistral_openai
  | Ollama_openai | Alibaba_openai | Moonshot_openai
  | Xai_openai | Meta_openai | Deepseek_openai
  | Groq_openai | Perplexity_openai | Together_openai
  | Cerebras_openai | Cohere_openai
  | Bulkhead_peer | Bulkhead_ssh_peer
```

When we added DeepSeek, the compiler failed in nine different files
until we taught each match expression about the new kind. AI patches
that "look right" but forgot the registry, or the schema, or the kind-to-string
mapping, or the discovery exclusion, simply did not build. The fix-it
loop was fast; the slop never reached `main`.

### 4.2 Structured errors with exhaustive rejection reasons

```ocaml
type unavailable_reason =
  | Route_missing
  | Budget_exhausted
  | All_circuits_open
```

Every pool member rejection carries a reason. The wizard renders
"`paul (daily budget exhausted)`" not "`paul (something went wrong)`",
because the type system never lets us throw away the structured cause.
There is no slop "let me just add a string error message". The value
flows from the selector to the UI without intermediate parsing.

### 4.3 Result-bind chains kill error swallowing

OCaml's `Result.bind` (or `>>=`) makes "happy path with explicit error
returns" the cheapest thing to write. The AI can't accidentally drop an
error: if it doesn't bind the result, the value is unused and the
compiler warns; if it binds without handling, the type doesn't match.
Unlike Python try/except, you cannot accidentally swallow an exception
because there's no exception to swallow.

### 4.4 No implicit secret propagation

The codebase has a hard rule: client `Authorization` headers are NEVER
forwarded upstream. In Python this would be a code-review item ("did
you forget to strip the header?"). In OCaml, the type for the upstream
request body literally has no field for that header. The mistake is
unrepresentable.

## 5. Toward demonstrative programming

OCaml is not the destination. It is a launching pad.

The same OCaml ecosystem that produces this gateway also produces
**Rocq** (formerly known as Coq, renamed in 2024). Rocq is the world's
most-used proof assistant, written in OCaml and producing OCaml code
via extraction. It is the language of the seL4 verified microkernel,
the CompCert verified C compiler, the verified TLS implementations
shipping in Firefox and Linux, the verified blockchain runtimes shipping
at Tezos.

The progression we expect, both in BulkheadLM and in the wider
post-AI software ecosystem, is:

| Stage | Technique | What it rejects |
|---|---|---|
| Today | OCaml types + exhaustive matching | "You forgot a case." |
| Year 1 | OCaml + GADTs + abstract types | "You used the wrong representation." |
| Year 2 | OCaml + property-based tests at module boundaries | "Your invariants don't survive composition." |
| Year 3 | Critical paths in Rocq, extracted to OCaml | "You didn't *prove* this couldn't go wrong." |
| Year 5+ | LLMs that emit Rocq proof obligations alongside code | "The compiler wants a proof; the AI ships one." |

We call this trajectory **demonstrative programming**: the code is not
just "I think this is right because the tests pass". The code is "here
is a machine-checkable demonstration that the property holds". When AI
generates code at scale, the only viable trust model is "the AI also
generates the proof, the proof checker accepts it, and we don't have
to re-read the code". That trust model exists already, in Rocq. It is
not science fiction; it is engineering that has been waiting for the
economic case to flip.

The economic case has flipped. AI lowered the cost of generating
candidate code; LLMs running locally lower the cost of generating
candidate proofs; modern proof assistants close the loop. OCaml is the
on-ramp. Rocq is the destination. We expect to see chunks of this very
codebase migrate to formally-verified Rocq modules over the next 24 to
36 months — starting with the security-critical pieces: the egress
policy decision, the auth token comparison, the budget-charging
transaction.

## 6. Honest tradeoffs

We are not pretending OCaml is free.

**Smaller LLM training corpus.** GPT-class models have seen orders of
magnitude less OCaml than Python. Patches need more iterations. We
mitigate by keeping the architecture *boring*: hierarchical modules,
no fancy dependent types, no monad transformer towers. The AI sees
patterns it recognizes from Python ported one-to-one.

**Smaller package ecosystem.** opam has thousands of packages, not
hundreds of thousands. We work around it by writing thin
language-specific adapters and reusing what's there (Cohttp, Lwt,
Yojson, Sqlite3) rather than chasing the latest framework.

**Higher initial mental load.** New contributors need to learn the
type system. We mitigate with a flat module hierarchy, a `CLAUDE.md`
hub for AI assistants, and ruthless commit-message discipline so the
git history is itself a tutorial.

**Build infrastructure.** OCaml on Windows is not native. We picked
WSL/Docker/cloud-SSH as the official Windows paths and wrote a
fault-tolerant decision tree (`INSTALL_PROMPT.md`) so users do not
hit this themselves.

These are real costs. They are also the costs of building software
that is *meant to last*, in a world where the marginal cost of code
went to zero.

## 7. Stance

BulkheadLM is a security-first AI gateway. "Security-first" means we
chose every line for fail-closed defaults, explicit policy, auditable
behavior. Choosing OCaml is part of that. The slop you don't write is
the bug you don't ship; the bug you don't ship is the breach you don't
have to disclose.

If you are reading this manifesto and thinking "I would never have
picked OCaml for this", that is the point. The marginal incentive to
pick the popular language is precisely what produces a long tail of
mostly-correct, occasionally-disastrous AI-generated infrastructure.
We are betting against the marginal incentive.

> When it builds, it works.

That is the prime directive. Everything else — the pools, the
discovery cache, the multi-persona connectors, the Windows install
trees — flows from it.

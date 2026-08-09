# The refactoring catalog

The closed list of code transformations this skill performs, with the id each
one carries into its commit message.

Two readers. Step 1.4 writes the `Recommendation` column of
`TECH_DEBT_AUDIT.md` out of this file — "god function at
`src/billing/charge.ts:41`" becomes `extract-function` + `guard-clauses`, which
is something a person can do where the finding alone was a complaint. Phase 4
executes out of it: `references/phase-4-refactor.md` is the when and how of the
loop, this file is the what of each operation in isolation.

Not a refactoring course and not Fowler's catalog. The list is closed because
the failure mode of an open one is known: a cleanup that keeps finding one more
thing to fix stops being a cleanup. Out of scope permanently, approval or not —
changing a published API's signature unasked, optimizing performance, adding
behavior, and "while I am in here".

## Refactor, and where it stops being one

A refactor changes the shape of the code and preserves its externally observable
behavior: same returns for the same inputs, same errors thrown, same calls out
of the process in the same order, same shape on the wire. Cross that line and
the change is an edit — not forbidden by nature, just not this pipeline's work,
and it needs its own name, its own commit and someone's yes.

The blur is where the change looks like an improvement: adding validation,
tightening an error message, fixing an off-by-one found on the way. All three
are worth doing, none is a refactor, and a commit labeled `refactor(...)`
carrying one lied to whoever reverts it a year from now.

## The green gate is evidence, not the definition

"Behavior preserved" is a claim about every input; a suite is a sample. A green
gate says the sample it happens to hold gave the same answers before and after,
which is the same statement only when the sample covers what changed.

Usually it does not. GREEN measures the repository — typecheck runs, the suite
passes — and says nothing about whether any test executes the forty lines being
reshaped. A green gate over an uncovered target looks exactly like one over a
covered target, and a suite that does not reach the target cannot fail for it.
So every entry below says what the gate attests and what it does not: the second
is the residual risk, and it is what a reviewer works through by hand. Phase 4
turns it into a precondition per target — coverage of that target before it is
touched — in `references/phase-4-refactor.md`; here it is only the principle.

## The two tiers

Not a list, a criterion. **Tier A — autonomous.** The transformation is
mechanical and local: the set of observable behaviors does not change, and the
change is derivable from the code alone — someone reading the before and the
after, knowing nothing about the domain, agrees they are the same program. A
green gate is sufficient evidence because nothing is left to be wrong about that
the gate cannot see.

**Tier B — user checkpoint.** The transformation picks an abstraction or a
domain name, and no test can fail because the choice was wrong: green proves the
behavior did not change, which is exactly not the question. Same argument as the
phase 2 checkpoint, one level down — a module boundary there, a responsibility,
a type or a name here. The test between the two: state the transformation as a
rule a tool could apply without knowing what the program is for. If that works,
tier A. If it needs a word invented — a class, a type, a strategy — tier B,
because the word is the deliverable and no gate reads words.

| Tier | id | Operation |
|---|---|---|
| A | `extract-function` | extract a function inside the same file |
| A | `guard-clauses` | nesting → early return |
| A | `named-constant` | magic number or string → named constant |
| A | `dead-branch` | remove an unreachable branch or commented-out code |
| A | `rename-local` | rename a local-scope variable (never an export) |
| B | `extract-class` | split a god class or module by responsibility |
| B | `domain-type` | primitive obsession → domain type |
| B | `polymorphism` | conditional on a type tag → polymorphism / Strategy |
| B | `parameter-object` | long parameter list → object |
| B | `delegation` | inheritance → composition |
| B | `type-boundary` | remove `any` / `type: ignore` at a trust boundary |

---

# Tier A

## `extract-function`

**Smell.** A function you scroll to read, with comments naming its sections
(`// validate`, `// compute the total`, `// persist`): those comments are the
extraction boundaries, already written by whoever wrote the function.
**Operation.** Cut one contiguous block into a named function in the same file —
what it reads becomes parameters, what it writes becomes the return. No new
export; that is a boundary decision and it belongs to `extract-class`.

```diff
 export async function chargeInvoice(invoice: Invoice): Promise<Receipt> {
-  let subtotal = 0;
-  for (const line of invoice.lines) subtotal += line.unitCents * line.quantity;
-  const total = subtotal - discountCents(invoice.coupon, subtotal);
+  const total = invoiceTotalCents(invoice);
   return gateway.charge(invoice.customerId, total);
 }
+
+function invoiceTotalCents(invoice: Invoice): number {
+  let subtotal = 0;
+  for (const line of invoice.lines) subtotal += line.unitCents * line.quantity;
+  return subtotal - discountCents(invoice.coupon, subtotal);
+}
```

**The gate attests** that the caller compiles, that the block still runs where
it used to, and that the paths the suite walks give the same results. **It does
not attest** that the name describes the block — names are not testable — nor
that the extraction kept a side effect inside the `try`, transaction or lock
that used to enclose it: moving code out of an enclosing block compiles fine.

**Typical risk.** Extracting a block that contains an early `return` or `throw`:
it now exits the extracted function, the caller discards the value, and the flow
that used to stop keeps going, with the types lining up and typecheck green.

## `guard-clauses`

**Smell.** The real work sits three or four levels deep, wrapped in `if`s whose
`else` branches all end the same way — a throw, or a null return.
**Operation.** Invert each condition, exit early, unwrap one level per
condition. Keep the order: reordering is a behavior change whenever one guard is
what makes the next one safe.

```diff
 export function authorize(session: Session | null, doc: Document): void {
-  if (session) {
-    if (session.expiresAt > Date.now()) {
-      if (session.roles.includes(doc.ownerRole)) {
-        audit.log("access", session.userId, doc.id);
-      } else throw new ForbiddenError(doc.id);
-    } else throw new SessionExpiredError();
-  } else throw new UnauthenticatedError();
+  if (!session) throw new UnauthenticatedError();
+  if (session.expiresAt <= Date.now()) throw new SessionExpiredError();
+  if (!session.roles.includes(doc.ownerRole)) throw new ForbiddenError(doc.id);
+  audit.log("access", session.userId, doc.id);
 }
```

**The gate attests** that every path the suite walks ends where it used to, with
the same error type. **It does not attest** that the inverted conditions are
equivalent (`!(a && b)` is not `!a && !b`, and a suite that never hits the mixed
case says nothing), nor that a guard was not hoisted above a side effect that
ran before it — an audit line, a counter, a lock — since both orders satisfy the
same assertions.

**Typical risk.** Inverting a comparison by hand. `expiresAt > now` becomes
`expiresAt <= now`, correct until one side is `NaN`: both comparisons are false,
and the branch that used to be taken no longer is.

## `named-constant`

**Smell.** A literal whose meaning comes only from the line around it
(`if (elapsedMs > 900000)`), or one value at three call sites that have to change
together. **Operation.** Hoist it to a module-scope `const` whose name carries
the unit, and replace the occurrences that *mean* the same thing — the ones that
merely *equal* it stay literals.

```diff
+const REQUEST_TIMEOUT_MS = 30_000;
+const MAX_ATTEMPTS = 3;
+
 export async function fetchWithRetry(url: string): Promise<Response> {
-  for (let attempt = 0; attempt < 3; attempt++) {
-    const res = await fetch(url, { signal: AbortSignal.timeout(30_000) });
+  for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
+    const res = await fetch(url, { signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS) });
     if (res.status < 500) return res;
   }
   throw new UpstreamUnavailableError(url);
 }
```

**The gate attests** that the value is identical at every site the constant
replaced, and in a typed stack that no site changed type on the way. **It does
not attest** that those sites meant the same thing: two `86400`s, one a cache
TTL and one a token lifetime, become one constant and stay green until someone
raises the TTL and changes the product's session length in the same edit.

**Typical risk.** Over-collection — the evidence for merging two literals is
visible (they are equal) and the evidence against it is not (they answer to
different reasons).

## `dead-branch`

**Smell.** A branch dominated by an earlier one, a block after an unconditional
`return` or `throw`, or code commented out and kept "in case". **Operation.**
Delete the branch with the condition that guarded it; commented-out code goes
outright, because history holds it and a comment nobody can execute is a claim
nobody can check. Not phase 1 arriving late — phase 1 deletes at file and export
granularity, and no graph tool sees inside a live function.

```diff
 export function shippingCents(order: Order): number {
   if (order.items.length === 0) return 0;
   if (order.totalCents >= FREE_SHIPPING_THRESHOLD_CENTS) return 0;
-  if (order.items.length === 0) return FLAT_RATE_CENTS / 2;
-  // 2023 promo, kept in case marketing asks for it again
-  // if (order.coupon === "SHIPFREE") return 0;
   return FLAT_RATE_CENTS;
 }
```

**The gate attests** that nothing referenced the deleted names and that the
paths the suite exercises are unchanged. **It does not attest** that the branch
was unreachable at runtime: a field declared `string` that arrives from JSON can
be a number, and the `typeof` check that looked redundant was the only thing
catching it. A branch sitting on top of an `any` is undeclared validation, and
its target is `type-boundary`.

**Typical risk.** A branch dead today because a flag is off, or dead in
TypeScript and alive in the JavaScript calling the compiled output. Both delete
cleanly and come back as an incident nobody attributes to a cleanup commit.

## `rename-local`

**Smell.** A local called `data`, `res`, `tmp`, `data2` — or worse, a name that
used to be true: `userIds` holding emails since a change three commits ago.
**Operation.** Rename inside one scope. Never an export, never a parameter of an
exported function (a parameter name is public the moment a caller destructures
it), never a field that reaches serialization.

```diff
 export async function syncSubscriptions(): Promise<void> {
-  const data = await billing.listSubscriptions();
-  const data2 = data.filter((s) => s.status === "past_due");
-  for (const d of data2) {
-    await dunning.enqueue(d.customerId);
+  const subscriptions = await billing.listSubscriptions();
+  const pastDue = subscriptions.filter((s) => s.status === "past_due");
+  for (const subscription of pastDue) {
+    await dunning.enqueue(subscription.customerId);
   }
 }
```

**The gate attests** that every reference was updated: in a typed stack a missed
one does not compile, and that is all of it. **It does not attest** that the new
name is better, and it is blind to references that are strings — a template
literal, a key read back through `Object.keys`, a dynamic `obj[name]`, a fixture
matched by property name. In an untyped stack a missed reference is a runtime
`undefined`, and `undefined` travels a long way before it fails.

**Typical risk.** The rename done by textual replacement, catching the name as a
substring of another identifier or inside a string.

---

# Tier B

Everything here stops at a checkpoint, and the checkpoint covers the target named
in it — approval of `domain-type` on one module is not approval of `domain-type`
on the codebase. Signature changes are in scope only up to the package boundary:
a symbol exported from the published entry point is public API and stays out even
with a yes, because the people it breaks are not in the room.

## `extract-class`

**Smell.** A class whose fields split into disjoint groups used by disjoint
method sets — `Order` holding `items` and `totalCents` next to `smtpHost` and
`lastReceiptSentAt`. **Operation.** Move one group of fields, with the methods
that use them, into a new type; hold it as a field; delegate. If the new type
wants its own file, stop: that is a phase 3 move, in its own commit, after this
one.

```diff
 export class Order {
   constructor(
     readonly items: OrderLine[],
-    private readonly smtpHost: string,
-    private lastReceiptSentAt: Date | null,
+    private readonly receipts: ReceiptMailer,
   ) {}
   async sendReceipt(to: string): Promise<void> {
-    await smtp.connect(this.smtpHost).send(renderReceipt(this), to);
-    this.lastReceiptSentAt = new Date();
+    await this.receipts.send(renderReceipt(this), to);
   }
 }
```

**The gate attests** that callers compile against the delegating surface and
that the suite passes through it. **It does not attest** that the split is on
the right axis: a cut made one field too far left is green today and crossed by
every change for the next two years. Green proves the behavior held, not that a
boundary belongs here.

**Typical risk.** Shared mutable state. Fields that looked disjoint are written
by one group and read by the other, so one object becomes two that have to be
kept in sync, and the suite notices only if it exercises the order they drift in.

## `domain-type`

**Smell.** The same primitive threads through five signatures and each one
re-validates it, or two parameters of the same primitive sit side by side and
swapping them still compiles: `transfer(fromId, toId, cents)`. **Operation.**
Introduce a type for the concept and one constructor for it, and move into that
constructor the validation the call sites were each repeating — the same checks.
A constructor that rejects input the old code accepted has changed behavior.

```diff
-export function transfer(from: string, to: string, cents: number): Promise<void> {
-  if (!ACCOUNT_ID.test(from)) throw new InvalidAccountError(from);
-  if (!ACCOUNT_ID.test(to)) throw new InvalidAccountError(to);
-  return ledger.post(from, to, cents);
+export type AccountId = string & { readonly __brand: "AccountId" };
+
+export function accountId(raw: string): AccountId {
+  if (!ACCOUNT_ID.test(raw)) throw new InvalidAccountError(raw);
+  return raw as AccountId;
+}
+
+export function transfer(from: AccountId, to: AccountId, cents: Cents): Promise<void> {
+  return ledger.post(from, to, cents);
 }
```

**The gate attests** that every construction site went through the constructor,
so no raw string reaches `transfer` along a typed path. **It does not attest**
that the concept is the right one — `Cents` and `Money` are both green, only one
survives the first currency the product adds — nor that the validation moved
unchanged, since the second argument's error now fires before the first
argument's work instead of after.

**Typical risk.** The brand evaporates at the edges: anything from JSON, an ORM
row or a queue message is a plain string a cast can dress up as an `AccountId`.
The type guarantees the inside of the process, nothing about what enters it.

## `polymorphism`

**Smell.** The same `switch` on the same tag appears in more than one function,
and adding a case means editing all of them; one `switch` in one place is not
this smell, it is a `switch`. **Operation.** One implementation per case behind
a shared shape, a lookup from tag to implementation, callers dispatching through
it.

```diff
-function feeCents(payment: Payment): number {
-  switch (payment.method) {
-    case "card": return Math.round(payment.amountCents * 0.029) + 30;
-    case "pix": return 0;
-    case "boleto": return 350;
-  }
-}
+const FEE_RULES: Record<Payment["method"], (amountCents: number) => number> = {
+  card: (a) => Math.round(a * 0.029) + 30,
+  pix: () => 0,
+  boleto: () => 350,
+};
+
+function feeCents(payment: Payment): number {
+  return FEE_RULES[payment.method](payment.amountCents);
+}
```

**The gate attests** that every case the suite exercises produces the same result
and — with a `Record` keyed by the union, as above — that no case was dropped.
**It does not attest** what happens to a tag the union does not contain: the
`switch` fell through at a known line, the map returns `undefined` and throws one
line later, elsewhere, with a different error. If the old `default` carried
behavior, moving it is the part no type checks.

**Typical risk.** Applying it to a single `switch`, where the conditional was the
readable thing and the map is indirection with no leverage. The deletion test in
`references/phase-2-consolidation.md` applies unchanged: if deleting the
abstraction moves complexity nowhere, it was not paying for itself.

## `parameter-object`

**Smell.** Five or more parameters, or three of the same type in a row where a
caller can swap two and the compiler stays quiet, or a call site trailing
`null, null, true`. **Operation.** Group the parameters that travel together into
one named type; the rest stay. An object built to shorten the list rather than to
name a thing is a worse signature with fewer commas.

```diff
-export function createCheckout(
-  customerId: string,
-  amountCents: number,
-  currency: string,
-  captureNow: boolean,
-  sendReceipt: boolean,
-): Promise<Checkout> {
+export interface CheckoutRequest {
+  customerId: string;
+  amountCents: number;
+  currency: string;
+  captureNow: boolean;
+  sendReceipt: boolean;
+}
+
+export function createCheckout(req: CheckoutRequest): Promise<Checkout> {
@@ every call site @@
-createCheckout(id, 4999, "BRL", true, false);
+createCheckout({ customerId: id, amountCents: 4999, currency: "BRL",
+                 captureNow: true, sendReceipt: false });
```

**The gate attests** that every call site was migrated: in a typed stack nothing
compiles until they all are. **It does not attest** that they were migrated
*correctly* — two booleans swapped into each other's field typecheck perfectly
and invert the meaning of the call. This is where the gate is least informative,
and where reading the diff call site by call site is not optional.

**Typical risk.** Defaults. Optional positional parameters default in order;
optional object fields do not, so a caller that used to stop early now passes
`undefined` explicitly into code that never saw it.

## `delegation`

**Smell.** A subclass that overrides half the parent's methods to throw or no-op,
or that uses one of the parent's ten: the inheritance was reuse of code, not a
claim that one is the other. **Operation.** Hold the former parent as a field,
forward what is actually used, delete the rest.

```diff
-export class RetryingHttpClient extends HttpClient {
+export class RetryingHttpClient {
+  constructor(private readonly inner: HttpClient) {}
+
   async get(url: string): Promise<Response> {
-    return withRetry(() => super.get(url));
+    return withRetry(() => this.inner.get(url));
   }
-
-  async post(): Promise<Response> {
-    throw new Error("not supported on the retrying client");
-  }
 }
```

**The gate attests** that the methods callers actually call still exist and
behave the same. **It does not attest** anything about consumers that read the
type instead of calling it: an `instanceof` check, a DI container keyed by class,
a serializer walking the prototype chain, a registry populated at construction.
Type identity disappeared and the compiler cannot see who relied on it.

**Typical risk.** A base constructor with a side effect — registering the
instance, opening a pool, reading config once. Composition runs it at a different
time, or twice, or not at all.

## `type-boundary`

**Smell.** An `any` (or a `# type: ignore`, or a `@ts-ignore`) on a value from
outside the process — a response body, a queue message, an env var, a
`JSON.parse` — with every consumer downstream reaching into it by hand.
**Operation.** Declare the shape and narrow once, where the value enters.
**Adding schema validation there is not a refactor**: input that used to pass
starts being rejected, which is a change in observable behavior by this file's
own definition. It can be the right change — it is a different commit, with a
different name, that the user agreed to. What is refactor here is the typing:
the declared shape, `unknown` with explicit narrowing instead of `any`, the
suppression comment gone.

```diff
-export async function loadCustomer(id: string): Promise<any> {
+export interface CustomerDTO {
+  id: string;
+  email: string;
+  delinquent?: boolean;
+}
+
+export async function loadCustomer(id: string): Promise<CustomerDTO> {
   const res = await http.get(`/customers/${id}`);
-  // @ts-ignore — the client returns any
-  return res.body;
+  return res.body as CustomerDTO;
 }
```

**The gate attests** that nothing downstream depended on `any`'s permission to do
anything: every property access typechecks now, and a consumer reading a field
the shape does not declare fails the build. **It does not attest** that the shape
matches what the boundary sends — the cast is an assertion, as true as the API's
documentation, and the fixtures agree with the type because the same person wrote
both.

**Typical risk.** An optimistic shape turns a quiet `undefined` into a confident
access that throws in production. The bug class moves from wrong value to crash,
usually better and always different — and "always different" is why a wrong shape
is not a pure refactor either.

---

## When not to apply

An operation costs a diff to review now and pays out over future reads and edits
of that code, so code nobody reads and nobody edits pays no dividend and the
cost is the whole transaction. That is measurable, not a matter of taste: the
churn rule in `references/duplication.md` already uses co-change to separate
real duplication from structural coincidence, and the same history answers the
question here — will anyone open this file again.

- **The target is cold and green.** Untouched inside the churn window, tests
  passing. It belongs in the audit's "looks bad but is fine" section with the
  churn numbers, which is what stops the next cleanup from re-flagging it.
- **No test reaches the target.** The gate would be green for reasons unrelated
  to the change; phase 4 makes this a precondition and gives the ways out.
- **Phase 2 or 3 is going to touch it.** Reshaping inside a module about to be
  consolidated, or a file about to move, is guaranteed rework — the same
  argument that orders the whole pipeline.
- **The code is generated or vendored.** The next generation run reverts you.
- **The diff stops being reviewable.** An operation whose diff nobody will read
  has lost the property that made it safe. Split it, or leave it.

"It is ugly" is not a criterion, and neither is "that is not how I would have
written it". Both cost review time, buy nothing, and are indistinguishable from
real findings once they are in the branch.

## Why the operation is named in the commit

One operation per commit, `refactor(<id>): <what>` — `refactor(guard-clauses):
flatten authorize() in src/auth/authorize.ts`. The id is not decoration. Six
months from now someone bisects to this commit and has a minute to decide
whether to revert it: `refactor: improve code` tells them nothing actionable,
because they cannot tell what was supposed to stay the same and so cannot tell
whether it did. `refactor(guard-clauses)` names the transformation, and this
file names what a green gate did not attest about it — the list to check by hand
before blaming the commit, and again when reverting it.

The id is also a claim, which is why one operation per commit is not a style
preference. A commit tagged `guard-clauses` that also renamed three locals and
hoisted a constant is unrevertible in the only sense that matters: reverting the
flattening drags the rest along, and whoever is doing it at 3am cannot tell
which part they wanted back.

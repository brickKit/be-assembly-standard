# Reference Implementation Standard

Business-logic design should almost always start by looking at how mature real-world software already solves the same problem. This isn't modesty — a domain model that took decades of real deployments to shape has already absorbed edge cases that a from-scratch design will almost certainly miss, and those missed edge cases don't surface until three months after a customer is live on the new system.

This document governs *how* to consult a reference implementation responsibly — the order of operations, what to record, and the one signal worth watching for while doing it. It is deliberately domain-agnostic: "which real project to look at for which of our own components" is a separate, project-specific table (see the Master Guide's SOP-R §R-2), not part of this standard.

## 1. The Three-Step Method (order matters, never reverse it)

| Step | What to do | Why this order |
|---|---|---|
| **1a. Design your own version first** | Sketch a design against your own project's constraints before opening any reference | Bringing your own plan to someone else's implementation is what lets you see where the difference actually is. Reading with an empty head just produces a copy. |
| **1b. Consult a reference only for the parts you can't work out** | How the domain model is carved up, what states a state machine has and which transitions are legal, which fields are mandatory, how edge cases are actually handled | This step is research, not copying homework. |
| **1c. Come back and think it through yourself before writing it** | Reconcile what you learned with your own project's actual constraints | A reference project's tech stack and component boundaries are usually nothing like yours (different language, different process/database topology). Copying it verbatim is neither possible nor correct — the point was never to port the code, only to borrow the *reasoning*. |

**Closed-source products are worth consulting too.** You can't read the source, but you can observe how a mature product is actually *used* in the real world: which features customers touch every day, which ones nobody ever clicks, which workflows have been complained about for twenty years. This kind of information is often more valuable than source code for judging whether something deserves to become its own separate, independently-releasable piece (a decision driven by whether customers would pay for it standalone) — and that judgment matters more than any implementation detail, because it comes earlier.

**On licensing** (a short note, not a reason for anxiety): consulting a reference implementation for its *reasoning* and then re-implementing it independently, possibly in a different language, does not create a derivative work. The one thing to actually avoid is opening the other project's source file and copying or mechanically transcribing it line by line. Following the three-step method above keeps you well clear of that line. If code truly needs to be used directly, restrict this to permissively-licensed projects (Apache-2.0 / MIT / BSD) and preserve the original notice in a `NOTICE` file.

## 2. How to Record What Was Consulted

Record this before implementation starts, as part of the component's design documentation (see the documentation standard's template for where this section lives):

```markdown
## Reference Implementations

| Project | Version/commit | Module consulted | What was borrowed | License (verified) | Usage |
|---|---|---|---|---|---|
| Odoo | 17.0 | `addons/product/models/product_uom.py` | The table design for unit-of-measure conversion factors and its rounding strategy; which edge cases it specifically handles | LGPL-3 | Borrowed reasoning |
| Apache OFBiz | 18.12 | `applications/product/entitydef/entitymodel.xml` | Completeness of the Product/UoM entity relationships | Apache-2.0 | Borrowed reasoning |
| A closed-source product | — | — | How multi-unit conversion is actually used in practice: which conversion scenarios come up every day, which are never touched | Closed source | Borrowed real-world usage |

**Explicitly not consulted** (state this, so the next reader doesn't assume it was overlooked):

**What to deliberately avoid**:
- [Name the specific anti-pattern found in a reference and why this project doesn't replicate it]
```

**The three legal values for the "Usage" column:**

| Value | Meaning |
|---|---|
| Borrowed reasoning | Read its implementation, understood *why* it works that way, then designed and implemented your own version independently. **This is the value in almost every row.** |
| Borrowed real-world usage | A closed-source product, or something where only documentation/UX was consulted, not source |
| Copied code | Code was actually used verbatim. **Only permitted for Apache-2.0 / MIT / BSD projects**, and the `NOTICE` file must carry the original attribution; this table must state exactly which file and which section |

## 3. A Common Failure Pattern Worth Watching For When Comparing References

Reading several mature implementations of the same domain tends to surface a pattern worth naming explicitly: multiple real systems share the same set of structural weaknesses, often because they inherited them from an earlier era of the same architectural tradition. Recognizing this while reading is exactly the point of doing the reading — it's the chance to deliberately not repeat something everyone else got stuck with.

| Weakness | How to design around it |
|---|---|
| Every module shares one process and one database, so cross-module table joins become the norm and the intended boundary is a "soft" one that gets crossed constantly | Independent processes with independent schemas, enforced by a physical wall (real access control), not convention |
| Customization done via runtime patching or hooks into the base implementation, so every upgrade risks breaking every customization | A cleanly forked, independently versioned copy plus a locked contract, so an upgrade is an explicit, deliberate merge — not an automatic one that silently interacts with patched code |
| Metadata-driven everything (dynamic fields, generic "document type" abstractions), so there's no static type an AI or an IDE can use to catch a mistake before runtime | Contract-first (a schema language, not a database table) plus a statically-typed implementation language |
| Reports query live transactional tables directly, so a heavy analytical query degrades the core transactional system | Reports must go through a summary table or a dedicated analytics component, never the live transactional path |
| Tables grow forever, and the system eventually gets crushed under its own history | Design every growable table as partitioned from day one, with an explicit archival policy |

## 4. Recognizing a Slot-Family Signal

While comparing references, a specific situation comes up repeatedly: **the same feature has genuinely different implementations across several mature systems, and — this is the key qualifier — each one is reasonable, just suited to a different customer profile.**

**This is not a "should we make it configurable" question. It is a signal that this feature needs a pluggable-variant family, not a single implementation with a flag.**

The judgment hinges entirely on that qualifier — "each one is reasonable":

- If reading several implementations reveals that one is **clearly better** than the rest → that's your default implementation. No family needed.
- If several implementations are **each defensible, serving genuinely different customer profiles** → there is a real, distinct market need here, and it deserves a proper pluggable family.

Illustrative examples (the point is the judgment, not these specific cases):

| Feature | The real-world divergence | Conclusion |
|---|---|---|
| Costing method | Moving weighted average / FIFO / standard cost with variance / batch actual cost — four approaches, each correct for a different industry, and a company's own accountant often mandates a specific one | Needs a pluggable family |
| Warehouse picking strategy | First-expiry-first-out / FIFO / nearest-bin / wave picking | Needs a pluggable family |
| Approval routing | Strict organizational hierarchy / amount-tiered / matrix-based / rule-engine-driven | Needs a pluggable family, but — depending on your architecture — this kind of business logic may need to live in a business-facing component rather than a generic infrastructure one; check whether your platform has a rule against infrastructure components containing business logic before assuming this is purely a technical decision |
| Document numbering scheme | Sequential / year-month-segmented / org-and-type-segmented | **Not** a family — this is a single configuration item |
| Which fields exist on a core master-data record | Every vendor differs only in "a few more fields, a few fewer" | **Not** a family — that's a customization/fork concern, not an architectural one |

**What to do once this signal is recognized (in this order):**

1. **Formally register the new family first**, before writing any implementation: name it, define what the shared "slot" contract is, confirm every member of the family must expose an *identical* contract surface, identify which customer profile each member serves, and decide which one ships as the default.
2. Update whatever central registries your project uses to track this (port/schema registries, a component count, an architecture appendix — append-only, never edit existing entries).
3. **Confirm the hard constraint that makes something eligible to be a pluggable slot at all**: nothing else in the system may hold a dependency edge on it. If something else depends on it directly, it cannot be a slot — the correct shape at that point is "one component with an internal strategy" (see the AI-driven development standard's pattern-usage criteria) or a full fork instead.
4. Only then write the design and implementation for each family member.

⚠️ **Never write a branch like `if costingMethod == "fifo"` inside a single component to paper over this.** That packs multiple customers' genuinely different needs into one codebase, where every customer's requirement now constrains every other customer's — exactly the "pull one thread, the whole thing moves" failure this discipline exists to prevent. **The one exception**: the divergence is small enough to be a couple of branches, and there is no foreseeable fifth variant on the horizon (see the AI-driven development standard's anti-signals for when *not* to reach for an abstraction).

This discipline is also the physical precondition for letting a customer do closed-source customization starting from whichever family member is closest to what they need: the more closely a family's members track the real divergence found in step 4, the closer a customer's fork starting point already is to what they actually want, and the less custom work is needed afterward.

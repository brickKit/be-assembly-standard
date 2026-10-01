# BrickEnterprise Deployment Selection Guide

*[中文](../zh/deployment-selection-guide.md)*

> **This document answers one question: with this many ways to deploy, which one should I pick?** The [deployment handbook](deployment-handbook.md) answers "how do I actually do it once I've decided"; this document answers "what do I need to know before deciding" — what each form actually is, who it suits, its benefits and costs, and the pitfalls found on real hardware.
>
> **How to read this document**:
> 1. Look at the matrix below first and find the cell you care about (in general, you only need to care about **one** cell — whichever way you're actually planning to deploy).
> 2. Every cell in the matrix has a one-line summary and a jump link — click through to that section.
> 3. **Every section is independent and complete** — none of them require you to have read another section first to understand it. Read only the section you need; you don't have to read this document top to bottom.
> 4. Once you've read it and decided which one to use, go to [deployment-handbook.md](deployment-handbook.md) and follow it.
>
> If you're still not sure what "topology" and "environment" mean, read the short section right below — it's the minimum background needed to make sense of the matrix.

## Two independent axes of choice

Deploying a BrickEnterprise stack means making two independent decisions:

**Decision one: topology — should components be merged with each other?**

- **Pure independent components**: each component gets its own process/container, and they talk to each other over real network calls (gRPC/HTTP).
- **Pure shells**: multiple components' workloads are merged into a single process (we call this merged unit a "shell") — externally each component still looks like it has its own address, but physically they share one process and one connection pool.
- **Component + shell mix**: most components merge into shells; a small number (the ones that structurally can't merge — a pure front end, a stateless gateway-type component) stay independently deployed. This is this repo's current real production form.

**Decision two: environment — where does this actually run?**

- **Local bare process**: every component is an ordinary process on the host machine (`go run`/`uvicorn` and the like), with no container/orchestration platform involved at all.
- **Docker**: the brickKit platform (`brickkit up`) generates and manages real Docker containers.
- **K8s**: the brickKit platform talks to a real Kubernetes cluster and generates Deployments/Services.
- **Docker + local hybrid**: the vast majority of components run normally in Docker; you pick out exactly one component (usually whichever one you're actively editing) and pull it onto the host with `local: true` — you don't need to rebuild an image to see a code change, and every other component keeps running for real, unaffected.

These two decisions are independent and combine freely — 3 topologies × 4 environments = 12 combinations, and every one of them has been real-machine verified and confirmed workable in this project; there is no cell that's "theoretically possible but nobody's actually tried it."

## Behind these two axes: an actual growth path

The matrix looks like 12 equal cells, but in practice the topology axis has a genuine order to it — it's not "pick any 1 of 12":

**How you choose a topology is fundamentally driven by "scale" and "whether you need fine-grained control over each component's resources":**

1. **When scale is still small (including the development stage), use pure independent components** — whether it's a human writing code or AI-driven development, each component is its own process, boundaries are as clear as they get, and you only need to focus on the one component in front of you, with no need to understand any merged topology. Even when deploying for a real customer, as long as the component count is small and a single machine has resources to spare, pure independent components on Docker is fine — there's no need to reach for shells right out of the gate. **This is also the general default starting point for local development**: as long as your project's real topology hasn't adopted shells yet, local development should default to pure independent components as bare processes; once the real topology has merged some components into shells, the local default should follow suit and become "component + shell mix" (the local environment should track the real topology, not stay frozen at its original default forever).
2. **Only once the component count grows large enough that a single machine can no longer hold the baseline overhead of that many independent containers does shell-merging become worth considering** — this is not a "pick it from day one" option; it's a trade-off forced by scale, packing as many components as possible into as few containers as possible in exchange for lower resource overhead.
3. **Once you're genuinely on the cloud with a real K8s cluster, the choice between pure shells, a mix, or pure independent components maps directly onto how much cluster resource you have — it's a spectrum, not three isolated options**:
   - Cluster resources are tight → **pure shells**: merge as much as possible, push overall overhead as low as it goes.
   - Cluster resources are neither tight nor especially abundant → **component + shell mix**: keep most things in shells to save resources, and pull out only the handful of components that genuinely need independent scaling — this is the balance point between pure shells (saves resources, but can't independently control any one component) and pure independent components (fine-grained control, but expensive).
   - Cluster resources are abundant → **pure independent components**: you no longer need to sacrifice granularity to save resources, and every component can independently control its own replica count and resource quota.

**"Pure independent components" shows up at both ends of this path, but for completely different reasons**: in the development stage, it's used because scale is small and you need to stay focused; at the cloud-native, fully-scaled-out end, it's used because resources are abundant enough that merging just to save resources is no longer necessary. The stretch in between — "a single Docker machine can't hold it, but cloud resources are still limited" — is where shells and mixes actually earn their keep.

**The environment axis is largely independent of the topology choice, with one exception**: the Docker + local hybrid environment. No matter which topology your production deployment ultimately picks — pure independent components, pure shells, or a mix — this environment's job is always the same one thing: let you conveniently debug one or two components locally without sacrificing the reality of everything else. **It is not a deployment target — it's purely a development-time debugging tool**, and it has nothing to do with the question "how am I going to deploy this for the customer." Choosing it says nothing about your topology choice — it only means you're currently editing code locally.

## The matrix: find your cell here first

| Topology \ Environment | Local bare process | Docker | K8s | Docker + local hybrid |
|---|---|---|---|---|
| **Pure independent components** | [The general default starting point for local development, before shells enter the picture](#1-pure-independent-components--local-bare-process) | [Scale is still small, a single machine has resources to spare](#2-pure-independent-components--docker) | [Cloud resources are abundant, and you need fine-grained control over each component's resources](#3-pure-independent-components--k8s) | [Local debugging use — the rest of the components run alongside the real topology](#4-pure-independent-components--docker--local-hybrid) |
| **Pure shells** | [Verifying "can a shell run on its own, outside the platform" — usually only the dev tooling itself needs this](#5-pure-shells--local-bare-process) | [A single machine can no longer hold independent containers — push overhead as low as possible](#6-pure-shells--docker) | [Cloud resources are tight — the most resource-efficient end of the spectrum](#7-pure-shells--k8s) | [Local debugging use — you're editing one merged component and don't want to rebuild the whole shell image](#8-pure-shells--docker--local-hybrid) |
| **Component + shell mix** | [The default environment for daily development once the real topology already uses shells](#9-component--shell-mix--local-bare-process) | [A structural mix: some components can't merge by design, independent of how much resource is available](#10-component--shell-mix--docker) | [Cloud resources are moderate — the balance point between pure shells and pure independent components](#11-component--shell-mix--k8s) | [Local debugging use — editing one independent component on the topology closest to production](#12-component--shell-mix--docker--local-hybrid) |

---

## 1. Pure independent components × local bare process

**What this is**: every component is an ordinary process on the host (`go run ./cmd/module`, `uvicorn app:app`, and the like) — there's no Docker network and no K8s Service between them, just ordinary `localhost:<port>` network calls. Because this bypasses the brickKit platform's container orchestration entirely, the environment variables the platform would normally auto-inject (dependency addresses, resource connection strings, authorization config) have to be hand-simulated and fed to each process yourself.

**When to use it**: this is the general default starting point for local development — regardless of whether the project currently has shells, and regardless of whether a human or AI is driving the development, this is the form daily development defaults to as long as shell-merging hasn't been adopted yet: change a line of code, `Ctrl+C` and restart, see the effect in seconds — no need for the whole "change code → build an image → restart the container" cycle, and no need to reason about whether this component is currently merged into some shell. AI-driven development benefits from this especially — the context only needs to hold this one component's code and boundaries, not the whole merged topology at once — but this isn't an AI-exclusive scenario; anyone editing a component locally naturally ends up here. Once the project's real topology has adopted shells, the local-development default shifts to §9 (component + shell mix × local bare process) — what's described here is the default *before* shells show up.

**Benefits**:
- Fastest possible iteration — attach an IDE debugger directly to the process, no extra steps for crossing container/network-namespace boundaries.
- Lowest cognitive overhead — no containers, no orchestration layer; when something breaks, there are only two variables to consider ("this process itself" and "the address it's talking to"), which keeps the search space as small as it gets.
- No Docker/K8s environment required — a laptop is enough.

**Costs / limitations**:
- **This is not a deployment form brickKit actually manages** — `brickkit up` generates Docker Compose or K8s manifests; a bare process sits entirely outside that machinery. Two consequences follow: first, you have to hand-assemble every environment variable each process needs (dependency addresses, `DATABASE_*`/`MQ_*` connection strings, authorization config like `AUTHZ_BUNDLE_URL`/`IAM_JWKS_URL`) — the platform won't do it for you; second, conclusions verified here can't automatically be treated as guarantees for "this also holds under Docker/K8s" — this project has cross-verified that almost all business-level conclusions (contract compatibility, version coexistence) are consistent across all four environments, but the underlying mechanisms (health checks, how addresses get generated) simply don't exist under a bare process at all, and that gap is worth keeping in mind.
- No health checks, no automatic address rewriting from the platform — every assumption of "the platform will handle this for me" is off the table.
- Once the component count grows, hand-maintaining every process's startup script and environment variables gets tedious.

**Real-machine-verified caveats**:
- To genuinely make an authorized business call (not just test that a port is reachable), `infra-iam-casdoor`/`infra-authz` need to be running as bare processes too — a real business call needs a JWT that passes local JWKS signature verification (which means walking through the full Casdoor OAuth login → token exchange flow), and `infra-authz` needs to be reachable and to have successfully polled `/authz/bundle` at least once, or a specific permission check will just return 503. These two are ordinary components in their own right, not background infrastructure you can quietly ignore.
- Some hand-written literal config values (e.g. `authzBundleUrl`/`iamJwksUrl`) are written as Docker network addresses (`http://host.docker.internal:...` and the like) for real containerized deployment — those addresses simply won't connect under a bare process, and need to be manually swapped to the real `localhost` port. This isn't a bug — these literals assume a containerized network as a precondition, which doesn't hold in a pure bare-process scenario, so it needs manual correction.
- **Be extra careful about side effects when constructing a "the dependent uses an old code version" test scenario**: the moment a dependent switches to some older source snapshot, *every* dependency it declares in its own manifest (not just the one you meant to test) reverts to that historical point in time — any edge that no longer matches your current real topology can trigger extra components you never meant to start, or fail outright from missing configuration. Check *every* relevant dependency edge when constructing this kind of scenario, not just the one relationship you set out to test. Likewise, *other components not directly involved in this test* can also be dragged in if they happen to depend on the component you swapped to an old version.

---

## 2. Pure independent components × Docker

**What this is**: each component gets its own Docker container; `brickkit up` generates and manages the compose orchestration for all of them — networking, address injection, health checks, and start order are all native platform mechanics, with nothing for you to simulate by hand.

**When to use it**: the stage where the component count is still small and a single machine has resources to spare — typically early in a project, or when a customer has only purchased a small number of components. **This isn't meant to be a long-term choice**: once the component count grows and a single machine can no longer hold that many independent containers' baseline overhead, you should move to shell-merging (see §6) — that turning point isn't something you plan for in advance, it's a threshold you naturally run into once resource usage climbs. Before that threshold, this is the most standard form there is — the platform works exactly as designed, with no extra manual steps.

**Benefits**:
- Matches this project's most central design rule — "every component can be independently `brickkit up`-able" — to the letter: blast radius is as small as possible, and upgrading/restarting one component never affects any other.
- The platform natively generates correct dependency addresses, health checks, and start order, with zero manual intervention needed.
- Boundaries are as clear as possible when troubleshooting — every container's logs, resource usage, and health status are independent and don't interfere with each other.

**Costs / limitations**:
- **Resource overhead is this topology's inherent cost**: each component having its own container means each one carries its own web-framework runtime baseline (the memory footprint of the Gin/FastAPI process itself) and its own database connection pool. Once the component count spreads out to the dozens, this baseline overhead visibly accumulates on a single machine — this is the direct reason the "pure shells" topology exists at all (see §6 below).
- For a small customer or a local-only deployment, "one container per component" can, by itself, exceed what their hardware can carry.

**Real-machine-verified caveats**:
- This is the most complete business-logic scenario this project has verified — a real three-step inventory reserve/confirm/cancel TCC chain (including one genuine "insufficient inventory" negative case), with real cross-container gRPC calls correct end to end.
- **A "the dependent is newer, the dependency is older" version-mismatch scenario is easier to construct under Docker than under a bare process** — no source code or image rebuild needed at all, just change one line of manifest dependency-version declaration, and `brickkit up` automatically works out the correct multi-version-coexistence topology; two exact versions of the same component can genuinely run at once in a single deployment, each serving its own caller.
- **To test a "declared as a non-current checked-out version" scenario, what you edit is the archived manifest file `.brickkit/manifests/<component-id>-<version>.yaml`** (or, equivalently, actually check out the submodule's working tree to that tag — both routes lead to the same place) — don't assume changing the top-level version field in `brickkit.yaml` is enough; this archive is where brickKit actually reads a non-current component's dependencies/config from under Docker.

---

## 3. Pure independent components × K8s

**What this is**: each component generates its own K8s Deployment + Service; `brickkit up` talks to a real K8s cluster (the `--context` flag picks the target cluster) to carry out the deployment, and service discovery goes through K8s's native Service + CoreDNS mechanism.

**When to use it**: this is the **most resource-abundant end** of the cloud-native scaling path — taken together with "pure shells × K8s" (§7, resources are tight) and "mix × K8s" (§11, resources are moderate), the three sit on one spectrum running from tight to abundant resources. **This is not the default any K8s customer should reach for**: if cluster resources are tight, look at §7/§11 first; only once resources are abundant enough that you no longer need to agonize over "should I merge to save resources" does pure independent components become the optimal choice — every component is its own Deployment, naturally supporting an independent replica count and independent resource requests/limits, giving you the finest-grained independent scaling available.

**Benefits**:
- Genuine horizontal elastic scaling — each component's load curve can be completely different, and independent deployment means you can tune each one's replica count and resource quota individually, without being mutually constrained by a shared container's resource ceiling from merging.
- K8s-native capabilities like cross-machine scheduling and self-healing apply independently to every single component.

**Costs / limitations**:
- Operational complexity is the highest in this combination — it requires the customer to have their own K8s cluster management capability; it's not as simple as "install Docker and it runs."
- Requires installing `kubectl` separately — **the brickKit platform itself will not substitute `minikube kubectl --` for it** — `kubectl` must be installed on the machine doing the deployment.
- With a large component count, the number of Deployment/Service objects K8s has to manage grows proportionally too (this is a property of the "pure independent components" topology itself, and doesn't change by moving to K8s).

**Real-machine-verified caveats**:
- **Under `deploy.target: k8s`, any component with `expose: true` must set `hostname`, and cannot reuse `exposePort` the way Docker does** — K8s exposes services externally via Ingress + a domain name, not by mapping a host port; if `hostname` is missing, `brickkit up --dry-run` errors out immediately, rather than waiting until an actual deployment to fail.
- Under K8s/minikube, some resource-address literals that assumed "the same machine as Docker's network" need to be swapped for the K8s-appropriate address form (e.g. `host.minikube.internal` under minikube instead of Docker's `host.docker.internal`) — these are hand-written literals, and won't be automatically corrected just because the orchestrator changed.
- Real deployment time on hardware turned out faster than the intuitive expectation that "K8s deployments are inherently slow" — there's no need to carry extra worry about deployment time for this combination.

---

## 4. Pure independent components × Docker + local hybrid

**What this is**: the vast majority of components are real Docker containers, going through brickKit's full container orchestration as normal; you additionally pick exactly 1 (and only 1) fully independent component and pull it onto the host as a bare process with `local: true` — this is the only combination where "bare-process debugging" and "the real topology running alongside it" can both appear in the same `brickkit.yaml` at once.

**When to use it**: **this tier's role has nothing to do with "how you're planning to deploy for the customer" — it is always just a development/testing-time debugging tool**, regardless of whether your production topology ultimately ends up as pure independent components, pure shells, or a mix — whenever you want to "conveniently test just one component" without sacrificing the reality of everything else, this is the combination you reach for. Concretely: you're editing one component's code, but don't want to sacrifice the environment's reality — everything else stays a real container with the platform's real generation mechanics active — for example you need to verify how the component you're editing genuinely interacts with the other real containers, while also wanting the "no rebuild needed to see a code change" development experience.

**Benefits**:
- You don't have to sacrifice the reality of the whole environment just to debug one component — apart from the one you're actively editing, everything else stays a real container with real health checks and the platform's real address-injection mechanics.
- Closer to real production behavior than "all bare processes" (§1), because most components are still going through brickKit's real generation machinery, not something you hand-simulated.
- The edit-to-verify loop is as fast as a pure bare process, with no rebuild needed for the one component you're editing.

**Costs / limitations**:
- Requires understanding exactly how the `local:true` mechanism rewrites addresses — the learning cost isn't huge, but without understanding this layer, a "why can't this address connect" problem becomes harder to debug.
- Only suits the "pick 1 component for local debugging" scenario — if you want to edit several components at once, this combination's value drops (you're better off switching straight to §1's pure bare process).

**Real-machine-verified caveats**:
- **`local:true`'s address generation isn't a simple literal substitution — it uses `extra_hosts` to remap the service name itself to the host gateway** — the `*_ENDPOINT` string a dependent originally gets doesn't change in format; only that service name's internal DNS resolution inside the container gets redirected to the host — it's not really a different network protocol or address format underneath. This detail matches what this project's documentation has always described; it's just the first time the exact mechanism was pulled apart and confirmed on real hardware.
- brickKit's own official regression test (`TestLocalStillWorksAlongsideServedBy`) confirms `local:true` doesn't conflict with this topology, and this project re-confirmed the same conclusion on its own real components.

---

## 5. Pure shells × local bare process

**What this is**: multiple components' workloads are merged into one process (a shell), and that shell itself runs as a bare process on the host, with no container/K8s orchestration involved — you need to accurately reconstruct the full environment brickKit would really inject into this shell (the list of merged members plus each member's own config, plus the standard `DATABASE_*`/`MQ_*`/`IAM_JWKS_URL`/`AUTHZ_BUNDLE_URL`/`OTEL_BASE_URL` variables — the same convention as an ordinary independent component).

**When to use it**: this tier usually isn't something an ordinary deployer would actively choose — it's more about **verifying whether a shell can survive independently outside the platform's own orchestration** — for example when writing unit/integration tests for the shell merge-unit itself, or when the dev tooling needs to verify a shell's internal multi-module orchestration logic under a bare process.

**Benefits**:
- Confirms whether the definition "a shell is just turning N processes into 1" actually holds — with no container/K8s orchestration layer in the way, this is the most direct way to confirm that a shell's internal module orchestration, health checks, cross-module calls, and background async tasks are all correct purely because of the shell's own code, independent of containerization.
- No need to account for container networking as an extra factor when troubleshooting a shell's internal logic.

**Costs / limitations**:
- **Requires precisely reconstructing what the platform would inject** — a layer more complex than an independent component's bare process (§1), because the shell needs to know "which members it has merged, and what each member's own config is" — normally the platform auto-generates and injects this data, but under a bare process you have to assemble it yourself.
- Also not a deployment form brickKit actually manages — mechanism-level conclusions verified here are for reference only; real deployment behavior should still follow what's real under Docker/K8s.

**Real-machine-verified caveats**:
- Under a bare process, a shell's internal health checks, real cross-module business calls (a complete TCC chain), and background async task pushing all work correctly — confirming that merging by itself doesn't change any individual module's business behavior; "a shell just turns N processes into 1" holds equally well under a bare process.
- In the shell's member manifest, **a given member's "version" field is confirmed to be pure metadata** — from shell assembly all the way down to the underlying SDK, nothing anywhere in that chain uses this version number to make a decision or run a check. Declaring an old version number doesn't error, and doesn't make the shell actually assemble a copy of old code (which is physically impossible anyway — a bare process always runs whatever code the current working tree actually compiled into that executable). **Which code actually runs inside a shell's image/executable depends entirely on the state of the source tree at the moment it was built** — it has nothing to do with the version label written in the manifest; that responsibility falls entirely on "when should this get rebuilt," which is not the platform's job.
- **Declaring the same component collected under one shell with two different "versions" at once neither errors nor gets deduplicated under the current implementation** — it genuinely assembles two independent module instances listening on different ports, but both instances are backed by the same code and the same database schema; "different version" is, once again, just a label in a merged state, not proof that two different copies of code were actually assembled. If you accidentally write two records for the same component in a merge manifest (even with the same version number), `buildModules` currently doesn't catch it — it just quietly starts two fully equivalent module instances sharing the same data, with no data-isolation risk (since it's the same data to begin with), just two wasted ports and one extra connection for no benefit.

---

## 6. Pure shells × Docker

**What this is**: every mergeable component is merged into a shell; the shell itself is an ordinary Docker container, and merged members no longer generate their own independent containers — this is the most thorough form, under Docker, of "fit as many components as possible into as few containers as possible."

**When to use it**: running pure independent components (§2) on a single machine has already stopped fitting — the component count has grown large enough that each component's independent runtime baseline overhead is visibly straining a single machine, and only then does shell-merging become worth it, packing as many components as possible into as few containers as possible. This is the natural solution this project's core scenario — "a customer runs a whole ERP/CRM suite locally on their own machine" — grows into as the component count increases; **it's not the thing you should skip straight to instead of §2 from day one**. Compared to "pure independent components," the container count can drop from dozens to single digits, and the host's memory/CPU baseline overhead falls substantially.

**Benefits**:
- **Single-machine resource overhead drops significantly**: one shell container carries only one copy of the web-framework runtime baseline and one database connection pool, not one per merged component — this is this topology's core value proposition.
- Fewer containers, faster startup too, and day-to-day operations (reading logs, restarting) have fewer things to deal with.
- Natively supported by brickKit — fields that only make sense for an independent container (`expose`/`exposePort`) automatically become inert on a merged member (a warning, not an error), so there's nothing extra to clean up.

**Costs / limitations**:
- **Blast radius grows**: shipping a new version of one module inside the shell means the entire shell image has to be rebuilt and the entire shell container has to restart (even though a single module's runtime panic has been verified not to drag down the rest of the shell's modules, "shipping new code" is inherently a shell-level event).
- **"Does the shell need its own release" is something you have to actively manage** — declaring a new version number for a member in the shell manifest does **not** make the shell image automatically pick up that new code; what code actually gets compiled into a shell image depends solely on the state of the shell's own build pipeline at build time. This consistency is entirely the shell's own responsibility — the platform won't guarantee it for you.
- Debugging a component that's merged into a shell adds a layer of "which shell container is this actually living in right now" that you have to keep track of — unlike an independent component, which you can locate at a glance.
- **The same shell cannot collect two different versions of the same real component** — this is a structural limitation: this project's "one component, one fixed port from the registry" design means the two versions would inevitably declare the same port, guaranteed to collide inside the same shell container — `brickkit up` catches this directly at generation time with a clear error, rather than letting it surface at runtime as one module simply failing to start.

**Real-machine-verified caveats**:
- The extreme "zero independent components, 100% merged" form genuinely works: the container count compresses down to just the shells themselves, cross-shell dependency calls are correctly reachable, and the full business chain handles real requests.
- "Does the shell need its own release" now has mechanized backing — this project runs a dedicated version-consistency scan gate that continuously watches whether "the member versions a shell has pinned" and "the version label the shell itself ships under" stay self-consistent, so this no longer relies on someone remembering to check by hand.

---

## 7. Pure shells × K8s

**What this is**: every mergeable component is merged into a shell; the shell itself is an ordinary K8s Deployment, and each merged member generates its own Service pointing at the shell's Pod (no Deployment) — externally it still looks like "every component has its own address," but the traffic all lands on the shell's Pod.

**⚠️ This tier deserves special emphasis**: for a long time, this combination was believed to be **impossible** in this project — the old merge mechanism only supported a Docker target, and going to K8s meant tearing every shell back apart into independent containers first; "partially merged, partially on K8s" was believed to be a nonexistent middle ground. **That belief has been reversed**: the current merge mechanism natively supports K8s, and it has been real-machine verified as working.

**When to use it**: you're genuinely on the cloud with a real K8s cluster, but **cluster resources are relatively tight** — this is the tightest end of the cloud-native scaling spectrum: merge as many components as possible into shells first, pushing overall overhead as low as it goes, forming a complete spectrum together with "pure independent components × K8s" (§3, the resource-abundant end) and "mix × K8s" (§11, the moderate balance point) — resources running from tight to abundant map onto pure shells → mix → pure independent components. This kind of scenario used to be considered impossible — either you merge to save resources, or you go to K8s, but not both — now you can have both at once.

**Benefits**:
- You get both "shell-merging saves resources" and "K8s elastic scaling" at once — no longer an either/or choice.
- `brickkit up` natively generates the correct Deployment/Service structure, cross-shell dependency calls resolve through K8s's native Service + CoreDNS mechanism, with no extra manual configuration needed.

**Costs / limitations**:
- The K8s operational-complexity cost (needing cluster management capability, needing `kubectl`) is the same as "pure independent components × K8s" (§3) — merging by itself doesn't reduce this layer of complexity, it only reduces the resource-overhead layer.
- "Does the shell need its own release" holds just as much under K8s, and is completely independent of whether you chose Docker or K8s as your deployment target — the shell image's build pipeline remains the sole responsible party.
- The same shell still cannot collect two different versions of the same real component — this limitation holds equally under K8s (the root cause is this project's own port-registry design, unrelated to the orchestrator); under K8s the error may show up as the container endlessly restarting into `CrashLoopBackOff`, which is the same underlying cause as Docker's "container keeps restarting and exiting," just expressed through each orchestrator's own restart semantics.

**Real-machine-verified caveats**:
- The Deployment/Service structure `brickkit up` natively generates is entirely correct, cross-shell dependencies resolve through K8s-native mechanics, and the full business chain is usable end to end — this combination has already run a complete deployment flow through to completion on a real K8s cluster.
- There's one operational difference under K8s that doesn't exist under Docker: **if you want to temporarily swap a file inside a shell and have the effect take hold for verification/debugging purposes, Docker lets you "copy a file into the running container and restart that container" — this trick doesn't work under K8s** — K8s's Pod/container restart semantics don't preserve a container's writable layer across a restart, so any verification-purpose file swap has to go through the heavier path of "change the source → rebuild the image → let the cluster pull the new image → trigger a rolling update." This isn't a bug — it's a genuine design difference between the two orchestration systems over "what survives a container restart" — day-to-day operations are unlikely to run into it, but it's worth keeping in mind when doing verification-style debugging.

---

## 8. Pure shells × Docker + local hybrid

**What this is**: shell-based deployment (multiple components merged into shell containers) as the main form, with exactly 1 fully independent component additionally pulled onto the host with `local: true` for debugging, while the rest of the components stay real, unaffected shell containers.

**When to use it**: same as §4 — this tier is always just a local-debugging tool, unrelated to your production topology choice. Concretely for this combination: your production topology is already "shell-merged," but you're editing a component that's still independently deployed (e.g. the structurally-independent kind), and you want the "no rebuild needed" development experience without sacrificing the reality on the shell side.

**Benefits**:
- Similar benefits to §4 (pure independent components × hybrid) — you don't sacrifice the whole environment's reality just to debug one component; the shell side keeps running as real, merged containers.
- Especially good for verifying "how does an independently-deployed component genuinely interact with a component already merged into a shell," because the shell side is real, not simulated.

**Costs / limitations**:
- Requires understanding two mechanisms at once — shell-merging and `local:true` local debugging — a somewhat higher cognitive load than a single-dimension combination.
- Only suits debugging **structurally independent** components (a pure front end, a BFF) — if you want to debug a component that's already merged into a shell, this combination doesn't help; that scenario should use §12 (mix × hybrid) instead.

**Real-machine-verified caveats**:
- When a `local:true` component depends on a member collected by a shell, address resolution works out of the box — the **dependency-edge address** (the kind of `*_ENDPOINT` brickKit auto-generates) needs no manual intervention at all.
- **But hand-written literal config values aren't covered by this automatic mechanism**: if some config item (say, an address pointing at an authorization service) is a hand-written literal in the config file rather than an address brickKit auto-generated from a declared dependency, that value doesn't get rewritten automatically along with `local:true` — it still needs to be manually synced to the correct address. This is an inherent boundary between "hand-written literal" and "auto-generated from a dependency edge" as two distinct mechanisms, not a bug on either side.

---

## 9. Component + shell mix × local bare process

**What this is**: some components are merged into shells, some are deployed independently, and both run as bare processes on the host — this is the real "component + shell mix" production topology, moved onto the lightest possible environment: a local bare process.

**When to use it**: **this is the default environment for daily development, but with one precondition — your project's real topology has already adopted shells**. Before that point, the local-development default is §1 (pure independent components × local bare process); once the production deployment has merged some components into shells, the local development environment should follow suit and switch to the mix, so that the address resolution and cross-process calls you verify locally stay consistent with the real topology — you don't need to spin up a whole set of containers just to change one component; run exactly the components you need (whether shell-form or independent) as bare processes directly, and verify one real cross-process call (including a real authorization chain) far faster than repeatedly rebuilding images.

**Benefits**:
- Same as §1 — fast iteration, easy debugging — and because this topology is already close to the real production form (a mix), the business-logic conclusions you verify carry more weight.
- Lets you verify address resolution and cross-process calls under both "independent component" and "merged-into-a-shell component" forms at once, without having to verify each separately.

**Costs / limitations**:
- Same as §1 and §5 — you have to hand-assemble the environment the platform would normally auto-inject (dependency addresses, the shell's merged-member manifest, authorization config), one extra manual step compared to a real containerized deployment.
- Mechanism-level conclusions verified here (not business-logic conclusions) are for reference only — real address generation and health-check behavior should follow what's real under Docker/K8s.

**Real-machine-verified caveats**:
- **This combination may be the first place a given component's own complete code path is genuinely exercised** — a lot of verification tasks, when testing a cross-component call, are in the habit of using a low-level protocol tool to bypass a component's own business code and connect straight to its downstream (e.g. skipping a GraphQL gateway and hitting the backend directly with a gRPC tool) — that does confirm "is the network reachable," but it never actually executes the code the component itself wrote (the resolver/forwarding layer between the gateway and the backend call). If what you actually need to verify is that layer's own code, make sure your verification genuinely originates from the outermost entry point (e.g. genuinely constructing a full request with real authorization) rather than bypassing it and connecting straight to the downstream — a bypass-style verification, even if it's stayed green for a long time, may simply have never actually executed that code path.
- When multiple independent components each depend on a different version of the same downstream component, a bare process **has no mechanism whatsoever to stop or even warn you about it** — as long as the two instances each listen on a different port and each caller has its own address configured correctly, the system runs no consistency check at all, and both chains just work independently and correctly. This is a useful contrast against "the generation stage under Docker/K8s does run some static checks" — a bare process completely bypasses that layer of checking, and any resulting version-management mess is preventable only through the developer's own discipline; the system won't back you up.
- A component's multiple versions can coexist fine, one going through merged deployment and the other through fully independent deployment, with the two paths needing no coordination at all — old and new versions each work correctly along their own path, with no extra synchronization mechanism required.

---

## 10. Component + shell mix × Docker

**What this is**: some components are merged into shell containers, some are independently deployed as their own containers, and `brickkit up` generates and manages this whole mixed topology — **this is this project's current real production deployment form**, and also the combination the vast majority of real customers will actually use.

**When to use it**: a real customer deployment, especially a local, single-machine one — the mix here is **structural**: some components (a pure front end, a stateless gateway-type component) simply can't merge into any shell by design, and stay independently deployed no matter how much resource is available; the rest, which can merge, get merged into shells to save resources. **This is a different driving factor from §11's (mix × K8s) "actively choosing a mix because cluster resources are moderate"** — here, even with abundant resources on a single machine, it would still be a mix, because a few components are structurally independent regardless. If you're not sure which combination to pick for a single-machine deployment, this is usually the right answer.

**Benefits**:
- Gets both "shell-merging saves resources" and "structurally-independent components stay flexible" — the closest match to real-world needs.
- Natively supported by the platform, generating the correct mixed topology with zero manual intervention (which components merge into which shell, and which stay independent, is entirely driven by the manifest declarations).

**Costs / limitations**:
- The topology itself is more complex than a single-dimension one (pure independent / pure shells) — troubleshooting requires holding both "version consistency inside a shell" and "version compatibility between independent components" as mental models at once.
- The cognitive load of "is this component currently merged, or independently deployed" is still there, especially once the component count grows.

**Real-machine-verified caveats**:
- This is this project's "current sole real deployment form" — the cross-container network path from an independent container to a shell container has already been real-machine verified.
- **Both directions — a shell upgraded while an independent component lags behind, and the reverse — have been verified to work correctly**: as long as the contract itself has no breaking change, which side upgrades first doesn't affect business-level correctness — the only thing version management genuinely needs to watch is the long-standing "contract changes must be additive-only" rule, which is independent of this topology.
- **Operational scripts can have their own bugs too — don't blindly trust "it's run fine many times before" as proof it's always safe**: this project's real-machine testing surfaced a real flaw in one of its own acceptance scripts — its precondition check only looked at whether the config file was clean, without checking whether a real deployment was actually already running, which under a specific ordering silently destroyed an in-use real deployment entirely (not stopped — the containers and the network were removed together). This kind of issue is a reminder: any operational script that does a "clear and rebuild" style operation should get in the habit of first confirming whether something is actually running before executing against a real environment, rather than relying entirely on the script's own precondition logic.

---

## 11. Component + shell mix × K8s

**What this is**: some components are merged into a shell Deployment, some are independently deployed as their own Deployments, all talking to a real K8s cluster — this is the "component + shell mix" real production topology, taken to K8s-scale deployment.

**When to use it**: genuinely on the cloud, with **cluster resources that are neither tight nor especially abundant** — this is the balance point between "pure shells × K8s" (§7, resources are tight, merge as much as possible) and "pure independent components × K8s" (§3, resources are abundant, everything torn apart): pure independent components cost too much overhead when resources aren't generous enough, while pure shells make it hard to independently tune resources for any one component that genuinely needs elastic scaling — a mix resolves exactly this tension, keeping most components in shells to save resources, and pulling out only the handful that genuinely need independent control over resources/replica count. **Unlike §10's "structural mix," the mix here is an active resource-tuning decision**, not a structural constraint like "some components can't merge" — the very same component might, here, get actively pulled out for independent deployment because its load happens to be especially high, even though it's perfectly capable of merging.

**Benefits**:
- Gets both "merging saves resources" and "independent components get fine-grained scaling," without having to pick one of §7 (pure shells × K8s) or §3 (pure independent components × K8s).
- The cross-Pod network path between an independent Pod and a shell Pod (K8s's Service-discovery mechanism) has already been real-machine verified — this project's first time verifying this complete path on a real K8s environment.

**Costs / limitations**:
- This is the cell in the whole matrix with the most stacked-up operational complexity and cognitive load — K8s cluster management capability + shell version-consistency management + independent-component version-compatibility management, all three at once.
- Most of the caveats that apply to §3, §7, and §10 hold simultaneously in this cell (`hostname` is required, `kubectl` needs a separate install, whether the shell needs its own release, handling independent-component version mismatches) — not repeated in full here; skim those sections too before picking this combination.

**Real-machine-verified caveats**:
- A real full-scale topology (shell + independent-component mix) has successfully completed a deployment under the K8s target in one pass, and the cross-Pod network path between an independent Pod and a shell Pod has been confirmed reachable on real hardware.
- When multiple independent components each depend on a different version of the same downstream component, K8s's generation-stage behavior is entirely consistent with the Docker side: no conflict, no error, and it never silently picks one version to share — Service naming and routing naturally distinguish by exact version. The only thing that will actually block you is the orthogonal, necessary requirement of a resource binding (a newly-independent component must explicitly declare which database/message-queue resource it uses) — not any conflict over versions themselves.

---

## 12. Component + shell mix × Docker + local hybrid

**What this is**: the main body is the "component + shell mix" real production topology, with the vast majority of components (independent or shell-merged, either way) running normally in Docker, plus exactly 1 fully independent component pulled onto the host with `local: true` for local debugging — **this is the combination closest to real development in practice**: the component you're actively editing is usually exactly the structurally-independent kind (a component merged inside a shell isn't a good fit to pull out and debug on its own — see the boundary noted in §8).

**When to use it**: same as §4/§8 — this tier is always just a local-debugging tool, unrelated to your production topology choice. Concretely for this combination: you're in an environment already running the real production topology (most components merged, a few independent), and you need to edit and verify one independently-deployed component, while requiring its genuine interaction with every other component (merged or independent alike) to stay fully real, with nothing scaled back.

**Benefits**:
- The closest thing in the whole matrix to the intersection of "real production topology" and "fast local iteration" — apart from the one component you're actively editing, everything else runs in exactly the real form production would use.
- Dependency-edge address resolution (the part brickKit auto-generates) is correct throughout, with no manual intervention needed.

**Costs / limitations**:
- This is the cell requiring the most mechanisms understood at once in the whole matrix: shell-merging + independent-component version management + `local:true` address resolution, all three stacked together.
- Hand-written literal config values (not dependency-edge auto-generated addresses) still aren't covered by the `local:true` automatic mechanism and still need manual syncing — the same limitation as §8, not a new problem specific to this combination, just the same boundary continuing into a more complex topology.

**Real-machine-verified caveats**:
- **`local:true`'s address resolution isn't one-directional, and this is the combination where that was first fully verified**:
  - The direction "a `local:true` component depends on an ordinary container" — the dependency-edge address is automatically resolved to an address pointing at the host, correctly, out of the box.
  - The reverse direction, "an ordinary container depends on a `local:true` component" — brickKit generates a Docker-native network-alias mapping (mapping that component's service name directly to the host gateway), which is also out-of-the-box, with no manual port mapping required.
  - Both directions have been verified; this is worth calling out specifically because most debugging scenarios are used to setting the component being debugged itself to `local:true` (matching the first direction), and the second direction (some other component depending, in reverse, on the one being debugged locally) is easy to overlook — but it genuinely works out of the box too, nothing to worry about there.
- For multiple independent components each depending on a different version of the same downstream component, and for one version merged into a shell while another is fully independent — for both of these multi-version-coexistence scenarios, the extra `local:true` local-debugging state doesn't change their generation-stage behavior at all; how to handle them is covered in §9/§10/§11 respectively (not repeated here) — this is fully independent of the rest of the topology and can be layered on safely.

---

## One conclusion that holds across all 12 combinations: multi-version coexistence

No matter which combination you pick, whenever "old and new versions running together" is in play, the conclusion is the same:

- **Whether the dependent or the dependency upgrades first**: fully compatible, as long as the contract itself follows the "additive-only" rule — independent of deployment form.
- **Can multiple versions of one component coexist?** Yes, but **only via independent deployment, or via being merged into separate shells** — the same shell cannot collect two versions of the same component at once (it collides on ports — a structural limitation from this project's port-registry design, not a limitation of any particular environment).
- **Who's responsible for keeping "the version a shell declares" and "the code actually inside the shell image" consistent?** Always the shell's own build pipeline — the platform neither will, nor is able to, inspect what's actually compiled inside an already-built image on your behalf.
- **Will the system proactively help you spot a version-management mess?** Not at all under a bare process — that's purely down to your own configuration discipline; Docker/K8s's generation stage does run some static checks (e.g. whether a resource binding was declared), but those checks are about "is the deployment declaration complete," not "is the version choice sensible" — whether a version choice is sound is ultimately a human judgment call; what the platform guarantees is the baseline that it "won't generate a self-contradictory deployment manifest," not "it'll make your version-management decisions for you."

---

Once you've decided which combination to use, go to [deployment-handbook.md](deployment-handbook.md) for how to actually operate it.

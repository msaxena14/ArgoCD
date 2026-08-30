# ArgoCD Lab

A GitOps sandbox using the Argo CD **app-of-apps** pattern: one bootstrap
`Application` manages everything else declared in this repo, and an
`ApplicationSet` fans out multiple Helm-based apps from a single list.

## How it works

```
bootstrap/bootstrap-app.yaml   (applied manually, once)
        │  watches argocd/
        ▼
argocd/project.yaml            AppProject "lab" — scopes what/where apps may deploy
argocd/applicationset.yaml     ApplicationSet "lab-apps" — generates one Application
        │                      per list entry (hello-world, podinfo)
        ▼
charts/<name>/                 Helm chart (generic, reusable)
values/local/<name>/values.yaml  Environment-specific value overrides
        │
        ▼
Deployed into the "app" namespace on the same cluster
```

1. **Bootstrap** — `kubectl apply -f bootstrap/bootstrap-app.yaml` creates a
   single Argo CD `Application` that points at the [`argocd/`](argocd/)
   folder. From then on, everything in that folder is self-managed
   (`prune: true`, `selfHeal: true`).
2. **Project** — [`argocd/project.yaml`](argocd/project.yaml) defines the
   `lab` `AppProject`: apps in this project may only pull from this repo and
   deploy into the `app` namespace.
3. **ApplicationSet** — [`argocd/applicationset.yaml`](argocd/applicationset.yaml)
   uses a `list` generator to stamp out one `Application` per chart
   (`labs-hello-world`, `labs-podinfo`). Each generated `Application` uses
   Argo CD's multi-source Helm feature: one source is the chart itself, the
   other is a `ref` source used only to supply
   `values/local/<chart>/values.yaml` as an override file.
4. **Charts** — [`charts/hello-world/`](charts/hello-world/) is a minimal
   demo chart; [`charts/podinfo/`](charts/podinfo/) is the upstream podinfo
   demo microservice (Redis subchart, gRPC route, ServiceMonitor, PDB, etc.).
5. **Values** — [`values/local/`](values/local/) holds per-environment Helm
   value overrides, kept separate from the charts so the same chart can be
   reused across environments (e.g. a future `values/prod/`).

## Adding a new app

1. Add a chart under `charts/<name>/`.
2. Add its overrides under `values/local/<name>/values.yaml`.
3. Add `{ chartName: <name>, path: charts/<name> }` to the `list` generator
   in [`argocd/applicationset.yaml`](argocd/applicationset.yaml).

Argo CD picks up the new list entry and creates the `Application`
automatically — no manual `kubectl apply` needed beyond the initial
bootstrap.

## Repo layout

```
bootstrap/            Seed Application (applied manually once)
argocd/               AppProject + ApplicationSet definitions
charts/                Helm charts (hello-world, podinfo)
values/local/          Per-environment Helm value overrides
```

##### UNDERSTANDING THE COMPONENTS AND FLOW

Big picture: this is a GitOps repo (app-of-apps pattern)
Nothing runs from your laptop — Argo CD polls this repo and makes the cluster match whatever is committed here. There's one bootstrap object and everything else cascades from it.

1. The seed: bootstrap-app.yaml
This is the one thing a human applies manually (kubectl apply -f bootstrap/bootstrap-app.yaml). It's an Argo CD Application that just watches the argocd/ folder in this same repo. Because its syncPolicy.automated has prune: true and selfHeal: true, once it exists Argo CD keeps that folder's contents applied forever — this is the classic "app-of-apps" bootstrap: one Application whose only job is to manage the manifests that define everything else.

2. What lives in argocd/: the guardrails + the generator
project.yaml defines an AppProject called lab — think of it as an RBAC/scope boundary. It says: anything under this project can only pull from this one repo, and can only deploy into the app namespace on the local cluster. It's a sandbox fence, not app logic.
applicationset.yaml is the interesting part. An ApplicationSet is a template that stamps out multiple Argo CD Application objects from a list. Here the generator is a hardcoded list with two entries:

## hello-world -> charts/hello-world
## podinfo     -> charts/podinfo
For each entry, it generates an Application named labs-<chartName>, belonging to the lab project, deployed into the app namespace.

3. The "two sources" trick for values
Look closely at the sources: list in the ApplicationSet template — there are two entries, not one:

The Helm chart itself (charts/hello-world or charts/podinfo)
A second source with ref: values — this doesn't deploy anything, it just exposes this repo checkout under the alias $values so the first source's valueFiles: can reach into a different path in the repo: values/local/<chartName>/values.yaml.
This is Argo CD's "multiple sources" Helm feature — it lets you keep the chart (reusable, generic) separate from environment-specific overrides. That's why you have a parallel values/local/ directory: values/local/hello-world/values.yaml just bumps replicaCount: 2, and values/local/podinfo/values.yaml does the same plus overrides a UI message. If you wanted a prod environment later, you'd add values/prod/<chart>/values.yaml and a new generator entry (or a matrix generator) — the chart code itself wouldn't change.

4. The charts themselves
charts/hello-world/ — a minimal, presumably hand-rolled demo chart (Deployment, Service, HPA, Ingress/HTTPRoute).
charts/podinfo/ — the well-known upstream "podinfo" demo microservice, vendored in with more features (gRPC route, cert-manager Certificate, ServiceMonitor, PDB, a Redis subchart, Helm hooks). It's commonly used in Argo CD/Flux labs specifically because it has knobs to demonstrate rollouts, canaries, etc.


## End-to-end flow
1. You apply bootstrap-app.yaml once.
2. Argo CD syncs it → applies everything in argocd/ → creates the lab AppProject and the lab-apps ApplicationSet.
3. The ApplicationSet's list generator produces two child Applications: labs-hello-world and labs-podinfo.
4. Each child Application renders its Helm chart with the corresponding values/local/.../values.yaml overlay and syncs it into the app namespace.
5. Every level (bootstrap-app, and the ApplicationSet template) sets automated: {prune: true, selfHeal: true} — so this is fully self-driving GitOps: manual 

## NOTE :-
kubectl edit on the cluster gets reverted, and deleting an entry from the ApplicationSet's list deletes that whole app from the cluster (resources-finalizer.argocd.argoproj.io finalizers make sure that cleanup actually happens instead of orphaning resources).


## ARGOCD ARCHITECTURE 
## 1. argocd-application-controller (a StatefulSet, hence the -0 suffix):-  
   is the brain of the system. It continuously compares the desired state (manifests in Git) with the live state (what's actually running in the cluster). When they drift apart, it marks the Application as OutOfSync, and if auto-sync is enabled, it applies the changes. It also handles health assessment, pruning of deleted resources, and executing sync hooks.

## 2. argocd-applicationset-controller :- 
   manages ApplicationSet resources — a templating layer on top of Applications. Instead of manually creating an Argo CD Application per cluster or per environment, you define one ApplicationSet with a generator (list, Git directories, cluster labels, pull requests, etc.) and it automatically stamps out Applications. This is the multi-cluster / multi-environment automation piece.

## 3. argocd-dex-server :- 
   handles SSO authentication. Dex is an identity broker that connects Argo CD to external identity providers like Okta, Google, GitHub, LDAP, or SAML. When you log in via SSO, the request flows through Dex. If you only use local Argo CD users, this component sits mostly idle.

## 4. argocd-notifications-controller :-
   watches Application events (sync succeeded, sync failed, health degraded, etc.) and sends alerts to configured channels — Slack, email, Teams, PagerDuty, webhooks, and so on. It's how your team finds out a deployment failed without staring at the UI.

## 5. argocd-redis :-
   is an in-memory cache. It stores rendered manifests and cluster state comparisons so the controller and API server don't have to recompute or re-fetch everything constantly. It's throwaway data — losing Redis just means a temporary performance hit while caches rebuild, not data loss.

## 6. argocd-repo-server :-
   is the component that actually talks to your Git repositories. It clones repos, and — critically — renders the final manifests: running helm template, kustomize build, or Jsonnet as needed. The application controller asks the repo server "what should the desired state be?" and gets fully rendered YAML back. This is often the pod that needs more CPU/memory in large installations.

## 7. argocd-server :-
   is the API server and web UI. It's what you interact with — the dashboard at your Argo CD URL, the argocd CLI, and the gRPC/REST API all hit this pod. It handles authentication (delegating SSO to Dex), RBAC enforcement, and exposes application status. It's stateless, so it can be scaled horizontally.

## How they work together, end to end :-  
   you push a change to Git → the repo server pulls and renders the manifests → the application controller compares rendered manifests against the live cluster (using Redis as cache) → it syncs the difference into the cluster → the notifications controller tells your Slack channel it succeeded → you watch it all through the argocd-server UI, logged in via Dex.
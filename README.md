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

# ArgoCD ApplicationSet Lab

A minimal "everything as code" GitOps repo for practicing the ApplicationSet pattern locally on
minikube. Structure deliberately mirrors the production pattern documented in `~/notes/TechStack/GitOps/`
(chart / values / ArgoCD-manifests separation), scaled down to one repo for a local exercise.

```
charts/hello-world/        # the Helm chart (like global-products-helm-chart)
values/local/hello-world/  # env-specific value overrides (like client-deployments)
argocd/                    # AppProject + ApplicationSet — self-managed once bootstrapped
bootstrap/                 # the ONE manually-applied Application (app-of-apps root)
```

## One-time bootstrap

```bash
kubectl apply -f bootstrap/bootstrap-app.yaml
```

Everything else (`argocd/project.yaml`, `argocd/applicationset.yaml`, and every Application the
ApplicationSet spawns) is then reconciled automatically — never `kubectl apply` those directly
again, edit them in git instead.

## Adding a second test app

1. Add a new chart under `charts/<name>/`.
2. Add its value overrides under `values/local/<name>/values.yaml`.
3. Add one element to `argocd/applicationset.yaml`'s `generators.list.elements`:
   ```yaml
   - chartName: <name>
     chartPath: charts/<name>
   ```
4. Commit + push. The ApplicationSet controller diffs the list and spawns exactly one new
   Application (`lab-<name>`) — the existing `lab-hello-world` Application is untouched.

# TAK Server Ignite dependency

This chart deploys Apache Ignite nodes built with the TAK Server Ignite
extensions. It is maintained as a sibling chart so `charts/takserver` can
consume it through a standard optional Helm dependency.

The parent chart normally supplies these values under its `ignite` section.
The dependency can also be rendered independently:

```text
helm lint ./charts/ignite
helm template ignite ./charts/ignite
```

Important settings include `replicaCount`, `image`, `serviceAccount`, `rbac`,
`persistence`, `podDisruptionBudget`, `networkPolicy`, scheduling constraints,
and the standard pod/container security contexts.

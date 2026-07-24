# Legacy TAK Server Helm chart

This chart is retained temporarily as a migration and behavior reference. It
contains obsolete dependencies and values and is not the foundation for the
replacement chart.

The replacement chart is planned at `charts/takserver`; see
[`HELM_CONTAINER_GAMEPLAN.md`](../../../../HELM_CONTAINER_GAMEPLAN.md).

The replacement will:

- use standard Kubernetes APIs without assuming a cloud or traffic controller;
- expose image repositories, tags, digests, storage classes, and networking as
  values;
- support external services instead of requiring bundled dependencies; and
- provide generated values documentation from `values.schema.json`.

Do not copy the old parameter tables or deployment examples into the new
chart. Keep a legacy value only when a migration test proves it is still
needed.

# TAK Server Helm chart

This is the controller-neutral TAK Server chart. It replaces the removed legacy
chart and creates only standard Kubernetes resources. It does not install
Traefik, another ingress controller, Gateway API CRDs, NATS, or Ignite.

External PostgreSQL/PostGIS is the default. Set `database.mode=embedded` only
for development or evaluation. The development values file uses the requested
`imresamu/postgis` image and the locally tagged `dev-amd64` TAK images.

The chart supports four exposure modes:

- `disabled`: create internal Services only;
- `service`: change the API and messaging Services to the configured Service type;
- `ingress`: create a standard `networking.k8s.io/v1` Ingress for the API's
  plain HTTP service port (override `exposure.ingress.servicePort` when the
  selected controller is configured for a different backend);
- `gateway`: create/reference a Gateway API Gateway and HTTPRoute for the API's
  plain HTTP service port.

Provide the TAK `CoreConfig.xml`, `TAKIgniteConfig.xml`, and certificate material
through `config` values or pre-created ConfigMaps/Secrets. They are deliberately
not copied from the generated Gradle build output into this chart.

Example render:

```text
helm template takserver ./charts/takserver \
  -f ./charts/takserver/values-development.yaml
```

The chart's NATS and Ignite connection details are values for the next dependency
integration slice; the chart currently leaves those systems operator-managed.

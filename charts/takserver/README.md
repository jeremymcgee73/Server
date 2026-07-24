# TAK Server Helm chart

This is the controller-neutral TAK Server chart. It replaces the removed legacy
chart and creates only standard Kubernetes resources by default. Traefik, NATS,
and Ignite are optional dependencies in this same chart and remain disabled
unless explicitly enabled. The chart does not install Gateway API CRDs.

External PostgreSQL/PostGIS is the default. Set `database.mode=embedded` only
for development or evaluation. The development values file uses the requested
`imresamu/postgis` image, enables all three optional dependencies, and selects
the locally tagged `dev-amd64` TAK images. Override those tags with `dev-arm64`
when building on Apple silicon.

Build or refresh the vendored chart dependencies after changing dependency
versions or the repository-owned sibling chart at `charts/ignite`:

```text
helm dependency update ./charts/takserver
```

The dependency switches can be used independently:

```yaml
traefik:
  enabled: true
traefikRoutes:
  enabled: true
nats:
  enabled: true
ignite:
  enabled: true
```

### Passing values to subcharts

The `traefik`, `nats`, and `ignite` maps in the parent values are direct
pass-through sections for their corresponding subcharts. Add any value
supported by the pinned dependency beneath its chart name, either in the main
values file or in an environment-specific override:

```yaml
traefik:
  enabled: true
  deployment:
    replicas: 2
    podAnnotations:
      example.com/source: takserver-chart

nats:
  enabled: true
  podTemplate:
    merge:
      metadata:
        annotations:
          example.com/source: takserver-chart

ignite:
  enabled: true
  replicaCount: 3
  jvmOptions: -Xms512m -Xmx1g -Djava.net.preferIPv4Stack=true
```

For example, `nats.podTemplate.merge` reaches the NATS chart unchanged; the
parent chart does not need to enumerate every upstream setting. Do not place
these values beneath a generic `subcharts` key—Helm only forwards values under
the dependency's name (or alias). Parent-owned settings such as
`traefikRoutes` and `integrations` remain separate.

Bundled dependency names are release-scoped by default: `<release>-traefik`,
`<release>-nats`, and `<release>-ignite`. Explicit `fullnameOverride` values are
still supported, but the operator is then responsible for avoiding collisions
between releases. The Traefik routes use TLS passthrough for TAK ports 8443,
8444, 8446, 8089, 9000, and 9001. If Traefik is enabled in a k3s or k3d cluster,
disable the distribution's built-in Traefik first to avoid competing ingress
controllers and host ports.

The parent uses Helm's conventional fullname behavior: when the release name
already contains `takserver`, it is not repeated. For example, release
`takserver` creates `takserver-api`, while release `production` creates
`production-takserver-api`.

## ServiceAccount and RBAC

By default, the chart creates a release-scoped ServiceAccount and the discovery
Role used by TAK's Kubernetes clustering. To use an operator-managed account:

```yaml
serviceAccount:
  create: false
  name: takserver-runtime
  automount: true
rbac:
  create: true # bind the chart's Role to the existing account
```

Set `rbac.create=false` when the existing account is already bound to equivalent
permissions. `serviceAccount.annotations` are applied only when the chart
creates the account. The embedded database, migration Job, Helm test, and other
pods that do not call Kubernetes disable token mounting explicitly. The
certificate bootstrap uses its own dedicated account.

## Secrets and external PostgreSQL

The parent chart uses the following Secret references:

- `database.auth.existingSecret` supplies the database name, username, and
  password. The key names are configurable under `database.auth.secretKeys`.
  When no existing Secret is named, the chart creates one from the corresponding
  `database.auth` values.
- `config.existing.coreSecret` supplies `CoreConfig.xml`; its key defaults to
  `CoreConfig.xml` and can be changed with `config.existing.coreSecretKey`.
  Chart-generated and inline CoreConfig content is also stored as a Secret
  because it contains JDBC credentials. The legacy `config.existing.core`
  ConfigMap reference remains supported for non-sensitive configurations.
- `config.existing.certificates` names the Secret containing `takserver.jks`,
  `truststore-root.jks`, and `fed-truststore.jks`.
- `imagePullSecrets` is the standard list of registry credential Secret names.

Prefer existing Secrets in production. Credentials supplied directly through
Helm values or inline CoreConfig content are also recorded in Helm's release
metadata, even though the resulting Kubernetes objects are Secrets.

Secrets are normally created before Helm runs by a GitOps/CI pipeline, an
external secret controller, a sealed-secret workflow, or a certificate
controller. The chart then references those stable names and does not need
permission to manage organization credentials.

For development and evaluation, the chart can instead bootstrap the TAK
certificate Secret:

```yaml
config:
  existing:
    certificates: ""

certificates:
  bootstrap:
    enabled: true
    secretName: "" # defaults to <release>-takserver-certificates
    caName: TAKServer-Development-CA
    state: Colorado
    city: Denver
    organization: TAK
    organizationalUnit: Development
```

A dedicated bootstrap Job uses the `takserver-ca-setup` image to generate one
shared certificate set, then publishes it with a short-lived, dedicated Service
Account. TAK pod init containers wait for the optional Secret projection before
starting; the application ServiceAccount receives no Secret-write permissions.
If the Secret already exists, the Job leaves it unchanged. Delete the Secret
and the completed bootstrap Job (or run a Helm upgrade after its TTL removes
the Job) to intentionally generate a new development CA. Because the Job—not
Helm—creates the Secret, it is retained when the release is uninstalled.

The generated Secret contains the three server trust-store files plus
`admin.p12` and `admin.pem`. Retrieve the development administrator bundle with:

```text
kubectl get secret <secret-name> -n <namespace> \
  -o jsonpath='{.data.admin\.p12}' | base64 --decode > admin.p12
```

The bootstrap is enabled by `values-development.yaml` and disabled in the base
values. It is not a replacement for production PKI or a secret-management
controller. The bootstrap Role must have namespace-level `create` permission
for Secrets because Kubernetes RBAC cannot restrict create requests by resource
name; only the dedicated completed Job uses that ServiceAccount.

Traefik is configured for TLS passthrough and does not need the TAK certificate
Secret. The bundled NATS and Ignite defaults do not create authentication
Secrets; their upstream/custom values can reference Secrets if TLS or
authentication is enabled.

External PostgreSQL is the chart default. Point it at any reachable
PostgreSQL/PostGIS endpoint and reference operator-created Secrets:

```yaml
database:
  mode: external
  external:
    host: postgresql.database.svc.cluster.local
    port: 5432
  auth:
    existingSecret: takserver-postgres
    secretKeys:
      database: database
      username: username
      password: password
  migration:
    enabled: true
    hook: true

config:
  generated: false
  existing:
    coreSecret: takserver-core-config
    coreSecretKey: CoreConfig.xml
    certificates: takserver-certificates
```

The database and CoreConfig references may point to the same Secret if it
contains all four keys. `CoreConfig.xml` must use the same external host,
database, and credentials. Disable `database.migration.enabled` when schema
migrations are managed separately or the database user lacks schema-management
permissions. PostgreSQL TLS files and JDBC settings can be supplied through the
CoreConfig Secret plus the migration and workload extra-volume mechanisms.

With `database.migration.hook=false` (the default), Helm creates a hash-named
migration Job and database-consuming TAK pods wait for it to complete. This
avoids immutable Job updates and prevents application startup before the schema
is ready. `hook=true` instead runs a pre-install/pre-upgrade hook and is accepted
only for an external database with `database.auth.existingSecret`, because hook
resources run before chart-managed Secrets and databases exist.

The chart follows the conventional top-level Service, Ingress, and Gateway
values pattern. Internal `ClusterIP` Services are created by default. Set
`service.type` to `NodePort` or `LoadBalancer` when direct L4 exposure is
needed. Set `ingress.enabled=true` for a standard `networking.k8s.io/v1`
Ingress, or `gateway.enabled=true` to create an HTTPRoute and optionally its
Gateway. Override `ingress.servicePort` when the controller uses a different
backend port.

## Additional volumes

`extraVolumes` and `extraVolumeMounts` are appended to every TAK application
Deployment. Each entry under `workloads.api`, `workloads.config`,
`workloads.messaging`, and `workloads.plugins` also accepts role-specific
`extraVolumes` and `extraVolumeMounts`:

```yaml
extraVolumes:
  - name: shared-ca
    secret:
      secretName: shared-ca
extraVolumeMounts:
  - name: shared-ca
    mountPath: /etc/tak/shared-ca
    readOnly: true

workloads:
  api:
    extraVolumes:
      - name: api-settings
        configMap:
          name: api-settings
    extraVolumeMounts:
      - name: api-settings
        mountPath: /etc/tak/api-settings
        readOnly: true
```

The embedded database and migration Job expose the same lists under
`database.embedded` and `database.migration`. The Ignite subchart exposes them
under `ignite`. The upstream Traefik chart provides `additionalVolumes` and
`additionalVolumeMounts`; the NATS chart provides `podTemplate.merge` and
`container.merge` for equivalent customizations.

## Horizontal autoscaling

Optional `autoscaling/v2` HPAs are available for the API and messaging
Deployments. Both remain disabled by default. When enabled, the chart leaves
the Deployment replica count to the HPA.

```yaml
workloads:
  api:
    resources:
      requests:
        cpu: 500m
        memory: 1Gi
    autoscaling:
      enabled: true
      minReplicas: 2
      maxReplicas: 10
      metrics:
        - type: Resource
          resource:
            name: cpu
            target:
              type: Utilization
              averageUtilization: 70
```

API is the best initial HPA candidate. Messaging can also scale, but its
long-lived client connections stay on their existing pods; connection-count or
message-rate custom metrics are preferable to CPU when available. Keep config
and plugins at fixed replica counts. NATS, Ignite, and embedded PostgreSQL are
stateful quorum/data services and should be sized deliberately rather than with
this HPA. The Traefik dependency has its own `traefik.autoscaling` values.

Resource-utilization metrics require matching container resource requests and
a cluster metrics pipeline such as Metrics Server. The default five-minute
scale-down stabilization window avoids rapid churn for the JVM workloads.

## Production hardening

The chart supplies RuntimeDefault seccomp, drops Linux capabilities, and
disables privilege escalation by default. The current TAK images still run as
root, so set `runAsNonRoot` only after using images built for a non-root UID.
Pod and container security contexts remain fully overridable.

Common scheduling controls apply to the TAK workloads, embedded database, and
migration Job:

```yaml
nodeSelector: {}
tolerations: []
affinity: {}
topologySpreadConstraints: []
priorityClassName: ""
runtimeClassName: ""
schedulerName: ""
```

API and messaging PodDisruptionBudgets are available under
`workloads.<role>.pdb`; Ignite has `ignite.podDisruptionBudget`. Enable them only
with a replica count and availability policy appropriate for the cluster.

`networkPolicy.enabled=true` creates a policy selecting the parent chart's TAK
and embedded-database pods. Empty `ingress` or `egress` lists are default-deny,
so explicitly allow DNS, PostgreSQL, NATS, Ignite, ingress-controller, and client
traffic as required. The Ignite subchart has a separate
`ignite.networkPolicy` block. NetworkPolicy remains disabled by default because
not every CNI enforces it.

Every image supports an optional `digest`. When present, the chart renders
`repository@digest`; otherwise it renders `repository:tag`. The Iron Bank values
keep third-party dependencies, embedded PostGIS, certificate bootstrap, and the
test pod disabled unless approved images are supplied.

Generated configuration is checksummed into the workload Pod templates so Helm
upgrades roll pods when chart-managed CoreConfig or Ignite configuration
changes. For externally managed Secrets, trigger a rollout through
`podAnnotations` or the organization's secret-reloader controller.

## Chart test

The development values enable a `helm test` pod that authenticates to
`/Marti/api/version` using `admin.p12` from the certificate bootstrap Secret:

```text
helm test takserver --namespace takserver --logs
```

Production certificate Secrets do not have to include an administrator bundle,
so the test is disabled by default. Set `tests.certificateSecret`,
`tests.certificateKey`, and `tests.certificatePassword` when enabling it with an
operator-managed test credential.

Provide the TAK `CoreConfig.xml`, `TAKIgniteConfig.xml`, and certificate material
through `config` values or pre-created ConfigMaps/Secrets. Setting
`config.generated=true` renders development-oriented config files bundled with
the chart; certificate material must still come from a Secret.

Example render:

```text
helm template takserver ./charts/takserver \
  -f ./charts/takserver/values-development.yaml
```

# TAK Server container and Helm chart game plan

Status: proposed
Prepared: 2026-07-24
Working repository: https://github.com/jeremymcgee73/Server
Upstream repository: https://github.com/TAK-Product-Center/Server

## Outcome

Produce reproducible TAK Server container images and a controller-neutral Helm
chart that can install TAK Server on a current Kubernetes cluster.

The first release will:

- keep the current Eclipse Temurin/Ubuntu image family as the default;
- provide an Iron Bank values overlay and documented build path;
- support separate native linux/amd64 and linux/arm64 builds where upstream base
  images permit it; each architecture is tagged separately;
- support an external PostgreSQL/PostGIS database by default;
- offer an embedded PostGIS deployment for development and evaluation;
- expose TAK with Services, standard Kubernetes Ingress, or Gateway API;
- install no ingress or Gateway controller;
- avoid provider- and controller-specific resources; and
- pin released artifacts while continuously proposing updates to the newest
  stable, compatible versions.

Chainguard is a planned third image flavor after the standard and Iron Bank
paths are working.

## Decisions already made

1. There will be one Helm chart. Image repositories, tags, digests, pull
   secrets, and security-context differences are values, not separate
   templates.
2. Standard images are the default. An example values-ironbank.yaml switches
   every image to its Iron Bank equivalent without chart conditionals tied to
   a vendor.
3. The chart will not install or configure a traffic controller. It creates
   standard Kubernetes resources that a conforming implementation can consume.
4. Controller-specific CRDs and configuration are outside this chart.
5. Gateway API is the preferred controller-neutral choice when all web and
   raw TCP/TLS TAK endpoints must be exposed through one gateway.
6. Production installations use an external PostgreSQL/PostGIS service.
   Embedded PostGIS is explicitly a development convenience.
7. Release artifacts never use a floating latest tag. "Track latest" means
   automation opens updates to exact versions and digests after tests pass.

## Migration stance

The existing chart under src/takserver-cluster/deployments/helm is legacy
input, not the design foundation. The replacement chart starts from standard
Kubernetes APIs and carries forward only verified TAK runtime requirements.
Old provider-specific deployment instructions, generated value tables, and
controller-specific routing examples will not be copied.

## Dependency policy

Every external dependency follows these rules:

1. Select the newest stable release available when the change is prepared.
   Exclude alpha, beta, release-candidate, nightly, and untagged artifacts.
2. Stay on the newest compatible major line unless a separately tested
   migration is required. For example, use the latest Java 17 patch and
   latest Ignite 2 LTS; do not silently jump TAK to a new Java major or
   Ignite 3.
3. Pin base images and release images by digest. Retain a readable version tag
   next to the digest in build and chart metadata.
4. Commit Chart.lock for Helm dependencies and verify its digest in CI.
5. Use update automation for Docker images, GitHub Actions, Helm
   dependencies, Gradle dependencies, and tool versions. Patch and minor
   updates receive normal pull requests; major updates require an explicit
   compatibility note.
6. Rebuild images when a base-image digest changes even if the human-readable
   tag does not.
7. Generate vulnerability reports, provenance attestations, and signatures
   for every published image and chart.
8. Record intentional holds with the incompatible version, reason, owner, and
   review date. A stale version must never be unexplained.

### Version baseline as of 2026-07-24

This table is a starting point, not permission to hard-code these versions
forever. The implementation pull request must re-check each source.

| Dependency | Repository baseline | Initial target | Reason |
| --- | --- | --- | --- |
| Eclipse Temurin | 17-jammy, floating | Java 17.0.19 release image, exact digest | Latest patch on TAK's current Java major |
| Apache Ignite | 2.17.0 | 2.18.0 LTS | Latest compatible Ignite 2 line; Ignite 3 is a migration |
| Kubernetes | Unspecified | Test 1.34, 1.35, and 1.36; develop against 1.36.2 | Current supported Kubernetes minors |
| Helm | Legacy chart | Helm 4.2.0 primary; temporary Helm 3 smoke test through its support window | Current stable Helm |
| Gateway API | Not used | v1.5.1 CRDs supplied by the cluster operator | Current stable release |
| NATS Helm chart | 1.0.1 | nats-2.14.0 or newer released stable | Replace the obsolete chart and STAN-era assumptions |
| PostgreSQL/PostGIS | postgis/postgis:15-3.4 | External DB for production; imresamu/postgis:15-3.6.1-bookworm for development, pinned by digest | Explicit image reference; build or schedule separately per node architecture |
| Iron Bank bases | OpenJDK 17 UBI 9 references | Newest approved Repo One tags and digests available to the build | Iron Bank catalog access and approvals are environment-specific |

Authoritative release sources:

- Kubernetes releases: https://kubernetes.io/releases/
- Kubernetes downloads: https://kubernetes.io/releases/download/
- Helm releases: https://github.com/helm/helm/releases
- Helm 3 support timeline: https://helm.sh/blog/helm-v3-end-of-life/
- Gateway API releases: https://github.com/kubernetes-sigs/gateway-api/releases
- Apache Ignite downloads: https://ignite.apache.org/download/
- NATS Helm releases: https://github.com/nats-io/k8s/releases
- PostgreSQL releases: https://www.postgresql.org/docs/release/
- PostGIS image:
  https://hub.docker.com/r/imresamu/postgis
- PostGIS source:
  https://github.com/ImreSamu/docker-postgis
- Eclipse Temurin release notes: https://adoptium.net/news?tag=release-notes

### Embedded database architecture

Use imresamu/postgis:15-3.6.1-bookworm for the development database. Keep the
repository, tag, digest, and node selection overrideable. If both architectures
are needed, build or select an explicit image for each architecture rather than
requiring a combined architecture tag.

Iron Bank publication is conditional on the approved Repo One base image being
available for the architecture being built.

## Target container design

### Images

Build the smallest practical image set:

| Image | Purpose |
| --- | --- |
| takserver-base | Common Java/Tak runtime filesystem shared by the role images |
| takserver-api | API role entrypoint |
| takserver-config | Configuration role entrypoint |
| takserver-messaging | Messaging role entrypoint |
| takserver-plugins | Plugin manager/runtime additions |
| takserver-database-setup | Schema installation and database migration Job |
| takserver-ignite | TAK-compatible Ignite runtime and configuration |
| takserver-ca-setup | Optional CA/certificate administration utility |


Before consolidating existing role images, compare their installed files,
entrypoints, permissions, and runtime configuration. Keep a separate image
only when that difference is operationally meaningful.

### Build flavors

The Dockerfiles are the primary build interface. There is no repository-level
build orchestrator to learn or maintain. Prepare the generated container context,
then build the base image before the role images:

~~~text
# Run this from the repository root.
(cd src && ./gradlew :takserver-cluster:buildCluster)
cd src/takserver-cluster/build

# Set ARCH to the architecture of the Docker host (amd64 or arm64).
export ARCH=amd64
docker build -f docker-files/Dockerfile.takserver-base \
  -t takserver-base:dev-${ARCH} .

# Build each role image against that local base.
docker build -f docker-files/Dockerfile.takserver-api \
  --build-arg TAKSERVER_IMAGE_REPO=takserver-base \
  --build-arg TAKSERVER_IMAGE_TAG=dev-${ARCH} \
  -t takserver-api:dev-${ARCH} .
docker build -f docker-files/Dockerfile.takserver-config \
  --build-arg TAKSERVER_IMAGE_REPO=takserver-base \
  --build-arg TAKSERVER_IMAGE_TAG=dev-${ARCH} \
  -t takserver-config:dev-${ARCH} .
docker build -f docker-files/Dockerfile.takserver-messaging \
  --build-arg TAKSERVER_IMAGE_REPO=takserver-base \
  --build-arg TAKSERVER_IMAGE_TAG=dev-${ARCH} \
  -t takserver-messaging:dev-${ARCH} .
docker build -f docker-files/Dockerfile.takserver-plugins \
  --build-arg TAKSERVER_IMAGE_REPO=takserver-base \
  --build-arg TAKSERVER_IMAGE_TAG=dev-${ARCH} \
  -t takserver-plugins:dev-${ARCH} .
~~~

The database setup, Ignite, and CA utility images use their Dockerfiles directly
as documented in src/takserver-cluster/CONTAINERS.md. Iron Bank remains an
opt-in flavor implemented by changing the explicit base-image arguments and
registry references.

Standard remains the default flavor:

- Eclipse Temurin Java 17 on Ubuntu Jammy is the initial base family.
- The exact Temurin patch and manifest digest are build arguments maintained
  by update automation.
- Runtime images use a non-root UID, a read-only root filesystem where TAK
  supports it, and writable mounts only for declared data paths.

Iron Bank is an opt-in flavor:

- Java workloads use the newest approved OpenJDK 17 UBI 9 base in Repo One.
- Utility stages use an approved UBI base.
- Builds accept authenticated registry configuration without copying
  credentials into layers or source files.
- The resulting application behavior, UID/GID contract, filesystem paths, and
  health probes match the standard images.

Chainguard is phase two:

- add only after the common build contract is proven;
- prefer a glibc Java 17 runtime compatible with TAK's native libraries; and
- validate shell-free operation before selecting a distroless runtime.

### Reproducibility and supply chain

- Keep every Dockerfile independently buildable with ordinary `docker build` commands.
- Build on a native amd64 or arm64 host when that architecture is required; publish explicit architecture tags rather than combining architectures under one tag.
- Run smoke tests on the same architecture as the image build; no emulated or combined-architecture build is required.
- Pass source artifacts between stages rather than downloading at runtime.
- Pin downloaded tools and archives by version and SHA-256.
- Label images with source URL, revision, version, licenses, and creation time.
- Publish OCI images and the OCI Helm chart to an operator-selected OCI registry
  after release permissions are configured.
- Scan with a defined severity policy, sign with keyless Cosign, and attach
  SLSA provenance. SBOM generation is intentionally out of this phase.

## Target Helm chart

Create a new chart at charts/takserver. Keep the legacy chart in place during
the transition so behavior can be compared. Remove it only after migration
documentation and acceptance tests exist.

Suggested layout:

~~~text
charts/takserver/
  Chart.yaml
  Chart.lock
  values.yaml
  values.schema.json
  values-ironbank.yaml
  values-development.yaml
  templates/
    deployments/
    services/
    exposure/
    jobs/
    config/
    rbac/
    networkpolicy/
  tests/
~~~

The chart must render with helm template alone. It must not require Python
scripts to rewrite values or manifests before installation.

### Local development with k3d

Use k3d as the default local Kubernetes environment for chart and container
development. A documented developer workflow should:

- create a disposable k3d cluster with the required Kubernetes version;
- load locally built standard images into the k3d nodes without publishing
  them;
- install the chart with development values and an embedded
  imresamu/postgis database;
- exercise Service, Ingress, and Gateway API manifests through explicitly
  enabled local components; and
- delete and recreate the cluster as part of clean-install and upgrade tests.

k3d is a fast developer feedback loop, not a substitute for native
linux/amd64 and linux/arm64 image tests or a load-balancer-capable integration
environment. Keep controller installation and configuration in the local
development harness rather than in the chart.

### Workload behavior

- Model TAK API, messaging, configuration, and plugin workloads explicitly.
- Use Deployments or StatefulSets according to actual state ownership.
- Add startup, readiness, and liveness probes based on real application
  behavior.
- Add PodDisruptionBudgets, topology spread, affinity, resources, and
  autoscaling as optional values with conservative defaults.
- Use checksum annotations to roll workloads when mounted configuration
  changes.
- Provide least-privilege service accounts and RBAC.
- Default to restricted pod/container security contexts, then document any
  exception TAK genuinely needs.
- Support existing Secrets for PKI, database credentials, trust stores, and
  image pulls. Never put credentials in ConfigMaps or rendered NOTES.
- Run schema installation/upgrades as an idempotent, retryable Job with clear
  failure output.

### Database modes

~~~yaml
database:
  mode: external
  external:
    host: ""
    port: 5432
    database: cot
    existingSecret: ""
    usernameKey: username
    passwordKey: password
  embedded:
    image:
      repository: imresamu/postgis
      tag: 18-3.6.1-bookworm
      digest: ""
    persistence:
      enabled: true
~~~

Rules:

- external is the production default;
- embedded is labeled development/evaluation;
- the migration Job uses the same connection contract for both modes;
- PostgreSQL major upgrades require documented backup, restore, and rollback
  testing; and
- the chart never upgrades an existing database major automatically.

### NATS and Ignite

- Upgrade to the latest released official NATS Helm chart, commit Chart.lock,
  and use the chart's supported configuration rather than preserving obsolete
  NATS Streaming/STAN assumptions.
- Confirm whether current TAK 5.7 behavior still requires STAN semantics. If
  so, document and isolate the compatibility layer; do not pretend a direct
  JetStream migration is automatic.
- Upgrade Ignite to 2.18.0 LTS and keep it on the Ignite 2 line for this work.
- Verify cluster discovery, persistence, ports, probes, graceful shutdown,
  and arm64 native libraries.
- Allow operators to use externally managed NATS and Ignite endpoints when
  practical.

## Exposure model

The value contract is:

~~~yaml
exposure:
  mode: disabled # disabled, service, ingress, or gateway

  service:
    type: LoadBalancer
    annotations: {}
    loadBalancerClass: ""
    externalTrafficPolicy: Cluster

  ingress:
    className: ""
    annotations: {}
    hosts: []
    tls: []
    tcpService:
      type: LoadBalancer
      annotations: {}

  gateway:
    create: false
    gatewayClassName: ""
    parentRefs: []
    annotations: {}
    listeners: []
~~~

### disabled

Create ClusterIP Services only. This supports port-forwarding, service meshes,
and operators that manage exposure separately.

### service

Create controller-neutral LoadBalancer or NodePort Services for the selected
TAK endpoints. This is the simplest portable option for raw TLS/TCP traffic.

### ingress

Create networking.k8s.io/v1 Ingress resources only for HTTP/HTTPS-compatible
endpoints such as 8443 and 8444. Accept ingressClassName and arbitrary
annotations so any conforming implementation can consume them.

Ports 8089, 9000, and 9001 are not representable with portable standard
Ingress rules. In ingress mode, expose selected raw TLS/TCP ports through the
separate Service settings. Do not generate controller-specific TCP resources.

### gateway

Use Gateway API for the complete controller-neutral routing model:

- HTTPRoute where HTTP-aware routing is desired;
- TLSRoute for TLS passthrough/SNI routing; and
- TCPRoute only when its experimental CRDs are installed and the selected
  controller supports it.

TLSRoute is part of the standard Gateway API channel. TCPRoute is currently
experimental, so the chart must gate it behind a value and produce an
actionable validation error when its CRD is absent.

By default the chart attaches Routes to operator-supplied parentRefs. If
gateway.create is true, it may create a namespaced Gateway that references an
existing GatewayClass. It never installs a GatewayClass, controller, or
cluster-scoped Gateway API CRDs.

Compatibility is defined by Kubernetes Ingress and Gateway API conformance,
not by a controller-specific template path.

## Values and image override contract

The standard values file contains normal public/default image locations.
The Iron Bank overlay changes only values:

~~~yaml
global:
  imagePullSecrets:
    - name: repo-one

images:
  takserver:
    repository: registry1.dso.mil/example/takserver
    tag: 5.7.x
    digest: sha256:...
  dbTool:
    repository: registry1.dso.mil/example/takserver-db-tool
    tag: 5.7.x
    digest: sha256:...
  ignite:
    repository: registry1.dso.mil/example/takserver-ignite
    tag: 2.18.0
    digest: sha256:...
~~~

The final Repo One paths depend on how these derived TAK images are admitted
and published. Base images may come from Iron Bank before the resulting TAK
images themselves are available there. The overlay must use real approved
paths, never placeholders, when released.

## Delivery sequence

### PR 1: baseline and dependency inventory

- Add this game plan and a machine-readable dependency inventory.
- Add Renovate or Dependabot configuration.
- Record all current base images, downloads, Helm dependencies, GitHub
  Actions, and Gradle dependencies.
- Add a documented compatibility-hold mechanism.
- Establish CI versions from the latest stable sources.

Exit: every external artifact is discoverable by update automation or has a
documented manual check.

### PR 2: reproducible standard containers

- Refactor Dockerfiles into shared multi-stage builds.
- Document the sequential base, role, database-tool, Ignite, and CA
  Dockerfile builds.
- Pin Temurin 17, Ignite 2.18, downloads, and OS packages reproducibly.
- Establish UID/GID, paths, entrypoints, probes, and volume contracts.
- Build and smoke-test amd64 and arm64 separately on matching native builders.
- Produce scans, signatures, and provenance in CI; SBOM generation is out of
  scope for this phase.

Exit: standard images start successfully and pass smoke tests natively on
both architectures.

### PR 3: chart foundation

- Scaffold charts/takserver with schema validation and helper templates.
- Implement workloads, Services, configuration, Secrets, RBAC, probes, and
  the migration Job.
- Add external database mode first.
- Add helm lint, helm template, schema, kubeconform, and unit tests.

Exit: a clean namespace install against an external database reaches Ready
without manifest preprocessing.

### PR 4: exposure modes

- Implement disabled and service modes.
- Implement standard Ingress for web endpoints plus L4 Service exposure.
- Implement Gateway API Routes and optional Gateway creation.
- Run conformance-oriented tests without making one controller part of the
  chart contract.
- Exclude controller-specific behavior from the new chart.

Exit: each mode has an install test and endpoint-level connectivity test.

### PR 5: data and messaging dependencies

- Add the development-only embedded PostGIS option.
- Integrate the current released NATS chart and resolve STAN/JetStream
  compatibility explicitly.
- Integrate Ignite 2.18.0 and validate discovery and graceful termination.
- Test backup/restore and schema migration failure recovery.

Exit: dependency modes are documented, locked, and exercised in CI.

### PR 6: Iron Bank flavor

- Add Iron Bank base-image arguments and document the same sequential Dockerfile build path.
- Add values-ironbank.yaml.
- Validate non-root behavior, UBI paths, certificates, FIPS expectations, and
  registry authentication.
- Publish an architecture support matrix based on the explicit image tags
  that were built and tested.

Exit: the same Helm templates pass with standard and Iron Bank values; every
advertised architecture has a successful smoke test.

### PR 7: release and migration

- Package and publish signed OCI images and chart from a tagged release.
- Add installation, upgrade, rollback, backup/restore, and migration guides.
- Map every legacy value to its replacement or mark it removed.
- Exercise upgrade from the legacy deployment in a disposable cluster.
- Define support and deprecation windows for the legacy chart.

Exit: a user can install, upgrade, roll back, and verify a release using only
published artifacts and documentation.

## CI acceptance matrix

At minimum:

| Dimension | Coverage |
| --- | --- |
| Architecture | amd64 and arm64 application images, built and tagged separately |
| Kubernetes | 1.34, 1.35, and 1.36 |
| Helm | 4.2.x primary; latest supported Helm 3 while compatibility is promised |
| Image flavor | standard; Iron Bank where registry credentials are available |
| Database | external PostgreSQL/PostGIS; embedded PostGIS with explicit per-architecture image references |
| Exposure | disabled, service, ingress, gateway TLSRoute; optional experimental TCPRoute |
| Lifecycle | clean install, upgrade, rollback render, uninstall, failed migration |
| Security | non-root, read-only filesystem where supported, scan, signature verification |

CI should use a disposable Kubernetes cluster for rendering and install tests,
plus an environment capable of exercising the selected exposure resources.
Developers may use k3d for the same fast inner loop.

## Risks to resolve early

1. TAK artifacts or licenses may restrict what can be embedded in public
   images. Confirm distribution rights before enabling public OCI releases.
2. The community PostGIS image requires its own supply-chain review
   before production use.
3. Iron Bank base images and derived-image publication may support only one
   architecture or require credentials unavailable to public CI.
4. Current TAK behavior may depend on NATS Streaming/STAN, while current NATS
   deployments favor JetStream.
5. Ignite 3 is not a drop-in upgrade from Ignite 2. Keep it out of this scope.
6. TCPRoute remains experimental in Gateway API and is not universally
   enabled by controllers.
7. Changing PostgreSQL major versions is a data migration, not an image-tag-only
   update.
8. Consolidating role images could expose hidden assumptions in the existing
   provisioning scripts.

## Definition of done

- A fresh user can select standard or Iron Bank images without editing
  templates.
- Standard TAK application images are published with explicit amd64 and arm64
  tags when both are supported.
- All shipped image references and dependencies are exact and reproducible.
- Update automation identifies newer stable dependencies.
- The chart installs with an external database and no ingress controller.
- Service, Ingress, and Gateway API exposure behave as documented.
- Conforming traffic controllers work through standard resources without a
  controller-specific chart dependency.
- Secrets are never rendered into non-Secret resources or build layers.
- Install, upgrade, rollback, backup/restore, and uninstall are tested and
  documented.
- Published images and charts have scan results, provenance, and verifiable
  signatures.

## First implementation slice

Start with PR 1, then prepare the Gradle-generated container context and build
the base and role images with the documented Dockerfiles. Load the matching
architecture images into k3d for the first local smoke test, then repeat the
separate native build on any second architecture before creating the
external-database-only chart skeleton. This proves the image contract,
architecture-specific viability, and values structure before spending time on
embedded dependencies or vendor-specific hardening.

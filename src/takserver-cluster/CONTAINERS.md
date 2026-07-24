# TAK Server container builds

The existing Dockerfiles remain the build interface. They are intentionally
ordinary Dockerfiles so a developer can build one image with `docker build`
without learning a repository-specific build language.

## Prepare the build context

The Dockerfiles expect the generated files under
`src/takserver-cluster/build`. From the repository root, generate that context
first:

```text
(cd src && ./gradlew :takserver-cluster:buildCluster)
cd src/takserver-cluster/build
```

The Gradle task must complete before any image build. Do not run the Docker
commands from the repository root; the generated directory is the Docker build
context because the `COPY` paths are relative to it.

## Build the standard images

Build the common base first. The role Dockerfiles use the base repository and
tag through `TAKSERVER_IMAGE_REPO` and `TAKSERVER_IMAGE_TAG`:

```text
# Set this to the architecture of the Docker host.
export ARCH=amd64

# Common runtime base.
docker build \
  -f docker-files/Dockerfile.takserver-base \
  -t takserver-base:dev-${ARCH} .

# Role images derived from the local base.
for ROLE in api config messaging plugins; do
  docker build \
    -f docker-files/Dockerfile.takserver-${ROLE} \
    --build-arg TAKSERVER_IMAGE_REPO=takserver-base \
    --build-arg TAKSERVER_IMAGE_TAG=dev-${ARCH} \
    -t takserver-${ROLE}:dev-${ARCH} .
done
```

Build the supporting images separately:

```text
docker build -f docker-files/Dockerfile.database-setup \
  -t takserver-database-setup:dev-${ARCH} .
docker build -f docker-files/Dockerfile.takserver-ignite \
  -t takserver-ignite:dev-${ARCH} .
docker build -f docker-files/Dockerfile.ca \
  -t takserver-ca-setup:dev-${ARCH} .
```

The default base remains the current Eclipse Temurin/Ubuntu image family. The
standard image names and tags should be passed to Helm values explicitly; avoid
using `latest` for a release.

## Separate architecture builds

No combined architecture image is required. Build on a native amd64 host with
`ARCH=amd64`, and repeat the same commands on a native arm64 host with
`ARCH=arm64`. Publish or load the resulting tags independently, for example:

```text
docker tag takserver-api:dev-${ARCH} registry.example/takserver-api:dev-${ARCH}
docker push registry.example/takserver-api:dev-${ARCH}
```

Kubernetes values must select the tag that matches the target nodes. If an
operator later wants one tag for multiple architectures, that release policy can
be considered separately; it is not part of this build plan.

## Iron Bank option

Standard images remain the default. Iron Bank is an opt-in flavor that will use
the same sequence and image contracts, but with approved Iron Bank base image
references and registry authentication supplied by the build environment. It
must produce separate architecture tags when both architectures are supported.
Do not copy credentials into Dockerfiles or image layers.

## k3d development

Create a disposable k3d cluster, import the images for the cluster's
architecture, and install the chart with development values:

```text
k3d cluster create takserver-dev
k3d image import --cluster takserver-dev \
  takserver-api:dev-${ARCH} \
  takserver-config:dev-${ARCH} \
  takserver-messaging:dev-${ARCH} \
  takserver-plugins:dev-${ARCH} \
  takserver-database-setup:dev-${ARCH} \
  takserver-ignite:dev-${ARCH} \
  takserver-ca-setup:dev-${ARCH}
helm upgrade --install takserver <chart-path> \
  --namespace takserver --create-namespace \
  -f <chart-path>/values-development.yaml
```

Use `k3d cluster delete takserver-dev` to reset the environment. Keep
controller installation and configuration outside the chart; the chart should
only create the selected Service, Ingress, or Gateway API resources.

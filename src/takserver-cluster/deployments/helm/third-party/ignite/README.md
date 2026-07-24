# Legacy Ignite subchart

This vendored chart is retained only to compare legacy TAK Server behavior
while `charts/takserver` is developed. Its archived upstream documentation and
provider-specific persistence examples have been removed.

The replacement must use Apache Ignite 2.18.x, accept an existing
`storageClassName`, and rely on the cluster's default StorageClass when that
value is empty. The chart must not create infrastructure-specific
StorageClasses.

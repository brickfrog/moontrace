///|
/// The moontrace release reported as `telemetry.sdk.version`. Update it with
/// `moon.mod` when cutting a release.
pub let sdk_version : String = "0.19.0"

///|
/// A resource with the attributes the OpenTelemetry resource specification
/// requires: `service.name` (default `unknown_service`) and
/// `telemetry.sdk.{name,language,version}`. Optional `service_version` and
/// extra `attributes` follow; later attributes with the same key win.
pub fn default_resource(
  service_name~ : String = "unknown_service",
  service_version~ : String = "",
  attributes~ : Array[OtlpAttribute] = [],
) -> Resource {
  let base = resource(service_name~, service_version~, attributes=[
    { key: "telemetry.sdk.name", value: StringVal("moontrace"), },
    { key: "telemetry.sdk.language", value: StringVal("moonbit"), },
    { key: "telemetry.sdk.version", value: StringVal(sdk_version), },
  ])
  base.merge({ attributes: attributes.copy(), })
}

///|
/// Merge two resources. Attributes from `other` replace attributes with the
/// same key in `self`, keeping `self`'s position; new keys are appended. Neither
/// input is modified.
pub fn Resource::merge(self : Resource, other : Resource) -> Resource {
  let merged = self.attributes.copy()
  for attribute in other.attributes {
    match merged.search_by(existing => existing.key == attribute.key) {
      Some(index) => merged[index] = attribute
      None => merged.push(attribute)
    }
  }
  { attributes: merged, }
}

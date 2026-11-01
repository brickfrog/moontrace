///|
fn otel_env(vars : Map[String, String]) -> @otlp.OtelConfig {
  @otlp.parse_otel_config(name => vars.get(name))
}

///|
fn attribute_string(resource : @otlp.Resource, key : String) -> String? {
  for attribute in resource.attributes {
    if attribute.key == key {
      match attribute.value {
        StringVal(value) => return Some(value)
        _ => return None
      }
    }
  }
  None
}

///|
test "OTEL defaults follow the specification" {
  let config = otel_env({})
  assert_false(config.disabled)
  assert_eq(config.service_name, None)
  assert_eq(config.traces_endpoint, "http://localhost:4318/v1/traces")
  assert_eq(config.logs_endpoint, "http://localhost:4318/v1/logs")
  assert_eq(config.headers.length(), 0)
  assert_eq(config.timeout_ms, 10000)
  assert_eq(config.protocol, "http/protobuf")
  assert_eq(config.compression, "none")
  assert_eq(config.sampler, "parentbased_always_on")
  assert_eq(config.sampler_ratio, 1.0)
  assert_eq(config.batch_delay_ms, 5000)
  assert_eq(config.max_queue_size, 2048)
  assert_eq(config.max_export_batch_size, 512)
  assert_eq(config.warnings, [])
}

///|
test "generic endpoint gets signal paths; signal endpoints are used as-is" {
  let generic = otel_env({
    "OTEL_EXPORTER_OTLP_ENDPOINT": "https://otel.example:4318/",
  })
  assert_eq(generic.traces_endpoint, "https://otel.example:4318/v1/traces")
  assert_eq(generic.logs_endpoint, "https://otel.example:4318/v1/logs")
  let specific = otel_env({
    "OTEL_EXPORTER_OTLP_ENDPOINT": "https://otel.example:4318",
    "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT": "https://traces.example/custom",
  })
  assert_eq(specific.traces_endpoint, "https://traces.example/custom")
  assert_eq(specific.logs_endpoint, "https://otel.example:4318/v1/logs")
}

///|
test "headers and resource attributes are percent-decoded lists" {
  let config = otel_env({
    "OTEL_EXPORTER_OTLP_HEADERS": "api-key=abc%20123, x-team = core ",
    "OTEL_RESOURCE_ATTRIBUTES": "deployment.environment=prod,region=eu%2Dwest,city=Z%C3%BCrich",
  })
  assert_eq(config.headers.get("api-key"), Some("abc 123"))
  assert_eq(config.headers.get("x-team"), Some("core"))
  let resource = config.resource()
  assert_eq(attribute_string(resource, "deployment.environment"), Some("prod"))
  assert_eq(attribute_string(resource, "region"), Some("eu-west"))
  assert_eq(attribute_string(resource, "city"), Some("Zürich"))
  assert_eq(config.warnings, [])
}

///|
test "malformed lists are discarded with a warning" {
  for bad in ["novalue", "=x", "k=%zz", "k=%4", "k=%ff"] {
    let config = otel_env({
      "OTEL_RESOURCE_ATTRIBUTES": bad,
      "OTEL_EXPORTER_OTLP_HEADERS": bad,
    })
    assert_eq(config.resource_attributes.length(), 0)
    assert_eq(config.headers.length(), 0)
    assert_eq(config.warnings.length(), 2)
  }
}

///|
test "service name precedence and resource defaults" {
  let resource = otel_env({
    "OTEL_RESOURCE_ATTRIBUTES": "service.name=from-attrs,team=core",
  }).resource()
  assert_eq(attribute_string(resource, "service.name"), Some("from-attrs"))
  let named = otel_env({
    "OTEL_SERVICE_NAME": "checkout",
    "OTEL_RESOURCE_ATTRIBUTES": "service.name=from-attrs",
  })
  assert_eq(
    attribute_string(named.resource(), "service.name"),
    Some("checkout"),
  )
  let overridden = named.resource(
    extra=@otlp.resource(service_name="from-code"),
  )
  assert_eq(attribute_string(overridden, "service.name"), Some("from-code"))
  let defaults = otel_env({}).resource()
  assert_eq(attribute_string(defaults, "service.name"), Some("unknown_service"))
  assert_eq(attribute_string(defaults, "telemetry.sdk.name"), Some("moontrace"))
  assert_eq(
    attribute_string(defaults, "telemetry.sdk.language"),
    Some("moonbit"),
  )
  assert_eq(
    attribute_string(defaults, "telemetry.sdk.version"),
    Some(@otlp.sdk_version),
  )
}

///|
test "Resource::merge replaces keys in place and appends new ones" {
  let base = @otlp.resource(service_name="a", attributes=[
    { key: "k", value: StringVal("1"), },
  ])
  let merged = base.merge(
    @otlp.resource(attributes=[
      { key: "k", value: StringVal("2"), },
      { key: "new", value: StringVal("3"), },
    ]),
  )
  assert_eq(merged.attributes.map(a => a.key), ["service.name", "k", "new"])
  assert_eq(attribute_string(merged, "k"), Some("2"))
  assert_eq(attribute_string(base, "k"), Some("1"))
}

///|
test "numeric settings reject invalid values with warnings" {
  let config = otel_env({
    "OTEL_EXPORTER_OTLP_TIMEOUT": "2500",
    "OTEL_BSP_SCHEDULE_DELAY": "-1",
    "OTEL_BSP_MAX_QUEUE_SIZE": "lots",
    "OTEL_BSP_MAX_EXPORT_BATCH_SIZE": "128",
    "OTEL_TRACES_SAMPLER_ARG": "1.5",
  })
  assert_eq(config.timeout_ms, 2500)
  assert_eq(config.batch_delay_ms, 5000)
  assert_eq(config.max_queue_size, 2048)
  assert_eq(config.max_export_batch_size, 128)
  assert_eq(config.sampler_ratio, 1.0)
  assert_eq(config.warnings.length(), 3)
}

///|
test "protocol, compression, and disabled flags are validated" {
  let config = otel_env({
    "OTEL_EXPORTER_OTLP_PROTOCOL": "http/json",
    "OTEL_EXPORTER_OTLP_COMPRESSION": "GZIP",
    "OTEL_SDK_DISABLED": "TRUE",
  })
  assert_eq(config.protocol, "http/json")
  assert_eq(config.compression, "gzip")
  assert_true(config.disabled)
  let bad = otel_env({
    "OTEL_EXPORTER_OTLP_PROTOCOL": "grpc",
    "OTEL_EXPORTER_OTLP_COMPRESSION": "zstd",
    "OTEL_SDK_DISABLED": "yes",
  })
  assert_eq(bad.protocol, "http/protobuf")
  assert_eq(bad.compression, "none")
  assert_false(bad.disabled)
  assert_eq(bad.warnings.length(), 3)
  assert_eq(otel_env({ "OTEL_SERVICE_NAME": "   " }).service_name, None)
}

///|
test "OTEL_TRACES_SAMPLER selects span samplers" {
  let root = (config : @otlp.OtelConfig) => {
    @moontrace.with_span_sampler(config.span_sampler(), () => {
      @moontrace.span_with_trace("root", "ffffffffffffffffffffffffffffffff").is_sampled()
    })
  }
  assert_true(root(otel_env({})))
  assert_false(root(otel_env({ "OTEL_TRACES_SAMPLER": "always_off" })))
  assert_false(
    root(otel_env({ "OTEL_TRACES_SAMPLER": "parentbased_always_off" })),
  )
  assert_false(
    root(
      otel_env({
        "OTEL_TRACES_SAMPLER": "traceidratio",
        "OTEL_TRACES_SAMPLER_ARG": "0",
      }),
    ),
  )
  assert_true(
    root(otel_env({ "OTEL_TRACES_SAMPLER": "parentbased_traceidratio" })),
  )
  assert_false(root(otel_env({ "OTEL_SDK_DISABLED": "true" })))
  let unknown = otel_env({ "OTEL_TRACES_SAMPLER": "jaeger_remote" })
  assert_eq(unknown.sampler, "parentbased_always_on")
  assert_eq(unknown.warnings.length(), 1)
}

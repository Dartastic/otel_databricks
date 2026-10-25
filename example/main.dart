// Licensed under the Apache License, Version 2.0
// Copyright 2025-2026 Mindful Software LLC d/b/a Dartastic.io, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:otel_databricks/otel_databricks.dart';

/// Traces Databricks Jobs calls with OpenTelemetry.
///
/// `otel_databricks` depends on the OpenTelemetry API only, so the application
/// initializes an SDK once at startup. Wrap each Databricks Jobs call in
/// [tracedDatabricksSql]; the `invoke` callback makes the real call and reports what
/// came back, which is recorded on the span.
Future<void> main() async {
  await OTel.initialize(serviceName: 'databricks-example');

  // Wraps a Databricks SQL Warehouse statement execution in a CLIENT span.
  final databricksSqlId = await tracedDatabricksSql<String>(
    statement: 'active',
    warehouseId: 'warehouse_8f3a2c',
    catalog: 'example',
    schema: 'example',
    workspaceHost: 'api.example.com',
    invoke: () async {
      // Make the Databricks Jobs call here, then report what it returned.
      const id = 'databricks_8f3a2c';
      return const DatabricksSqlResult(
          value: id, statementId: 'statement_8f3a2c', rowCount: 3);
    },
  );
  OTelLog.info('tracedDatabricksSql returned $databricksSqlId');

  // Wraps a Databricks Jobs API call (run-now, get-run, cancel-run) in a CLIENT span.
  final databricksJobId = await tracedDatabricksJob<String>(
    action: 'example',
    jobId: 1,
    runId: 1,
    workspaceHost: 'api.example.com',
    invoke: () async {
      // Make the Databricks Jobs call here, then report what it returned.
      return 'databricks_8f3a2c';
    },
  );
  OTelLog.info('tracedDatabricksJob returned $databricksJobId');

  // Calls that should not be traced, such as health checks, run inside
  // runWithoutDatabricksInstrumentationAsync.
  await runWithoutDatabricksInstrumentationAsync(
    () => tracedDatabricksSql<String>(
      statement: 'active',
      warehouseId: 'warehouse_8f3a2c',
      catalog: 'example',
      schema: 'example',
      workspaceHost: 'api.example.com',
      invoke: () async {
        const id = 'databricks_8f3a2c';
        return const DatabricksSqlResult(
            value: id, statementId: 'statement_8f3a2c', rowCount: 3);
      },
    ),
  );

  await OTel.shutdown();
}

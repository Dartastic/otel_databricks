// Licensed under the Apache License, Version 2.0
// Copyright 2025-2026 Mindful Software LLC d/b/a Dartastic.io, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:dartastic_opentelemetry/testing.dart';
import 'package:otel_databricks/otel_databricks.dart';
import 'package:test/test.dart';

void main() {
  late TestHarness harness;
  late InMemorySpanExporter spans;

  setUpAll(() async {
    harness = await maybeInitializeOtelForTest(
      serviceName: 'otel_databricks-test',
    );
    spans = harness.spans;
  });

  setUp(() => harness.clear());

  Map<String, Object> attrsOf(Span s) =>
      {for (final a in s.attributes.toList()) a.key: a.value};

  test('SQL records CLIENT span', () async {
    await tracedDatabricksSql<String>(
      statement: 'SELECT * FROM samples.tpch.lineitem LIMIT 100',
      warehouseId: 'wh-1',
      catalog: 'samples',
      schema: 'tpch',
      workspaceHost: 'acme.databricks.com',
      invoke: () async => const DatabricksSqlResult(
        value: 'rows',
        statementId: 'stmt-9',
        rowCount: 100,
      ),
    );
    final a = attrsOf(spans.findSpanByName('databricks SELECT')!);
    expect(a['db.system'], 'spark');
    expect(a['db.operation'], 'SELECT');
    expect(a['databricks.warehouse.id'], 'wh-1');
    expect(a['databricks.catalog'], 'samples');
    expect(a['databricks.schema'], 'tpch');
    expect(a['databricks.workspace.host'], 'acme.databricks.com');
    expect(a['databricks.statement.id'], 'stmt-9');
    expect(a['db.row_count'], 100);
    expect(a['databricks.product'], 'sql_warehouse');
  });

  test('Jobs.run-now records CLIENT span', () async {
    await tracedDatabricksJob<String>(
      action: 'run-now',
      jobId: 42,
      invoke: () async => 'run-1',
    );
    final a = attrsOf(spans.findSpanByName('databricks jobs.run-now')!);
    expect(a['databricks.product'], 'jobs');
    expect(a['databricks.jobs.action'], 'run-now');
    expect(a['databricks.job.id'], 42);
  });

  test('suppression skips spans', () async {
    await runWithoutDatabricksInstrumentationAsync(() async {
      await tracedDatabricksSql<String>(
        statement: 'SELECT 1',
        invoke: () async => const DatabricksSqlResult(value: 'v'),
      );
    });
    expect(spans.findSpansStartingWith('databricks '), isEmpty);
  });
}

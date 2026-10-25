// Licensed under the Apache License, Version 2.0
// Copyright 2025-2026 Mindful Software LLC d/b/a Dartastic.io, All rights reserved.

import 'package:dartastic_opentelemetry_api/dartastic_opentelemetry_api.dart';

import 'otel_databricks_suppression.dart';

const _tracerName = 'dartastic_otel_libs_databricks';

APITracer _tracer() => OTelAPI.tracerProvider().getTracer(_tracerName);

const _maxStatementLength = 1024;
String _truncate(String s) =>
    s.length <= _maxStatementLength ? s : s.substring(0, _maxStatementLength);

/// Pair returned from `tracedDatabricksSql` callback.
class DatabricksSqlResult<T> {
  /// Creates a result.
  const DatabricksSqlResult({
    required this.value,
    this.statementId,
    this.rowCount,
  });

  /// The value returned to the caller.
  final T value;
  final String? statementId;
  final int? rowCount;
}

/// Wraps a Databricks SQL Warehouse statement execution in a CLIENT
/// span. db.system=spark (Databricks SQL is Spark-based).
Future<T> tracedDatabricksSql<T>({
  required String statement,
  required Future<DatabricksSqlResult<T>> Function() invoke,
  String? warehouseId,
  String? catalog,
  String? schema,
  String? workspaceHost,
}) async {
  if (databricksInstrumentationSuppressed()) {
    final r = await invoke();
    return r.value;
  }
  final m = <String, Object>{
    'db.system': 'spark',
    'db.operation': _operationFromStatement(statement) ?? 'query',
    'db.statement': _truncate(statement),
    'databricks.product': 'sql_warehouse',
  };
  if (warehouseId != null) m['databricks.warehouse.id'] = warehouseId;
  if (catalog != null) m['databricks.catalog'] = catalog;
  if (schema != null) m['databricks.schema'] = schema;
  if (workspaceHost != null) m['databricks.workspace.host'] = workspaceHost;

  final span = _tracer().startSpan(
    'databricks ${m['db.operation']}',
    kind: SpanKind.client,
    attributes: OTelAPI.attributesFromMap(m),
  );
  try {
    final r = await invoke();
    final extras = <Attribute<Object>>[];
    if (r.statementId != null) {
      extras.add(OTelAPI.attributeString(
        'databricks.statement.id',
        r.statementId!,
      ));
    }
    if (r.rowCount != null) {
      extras.add(OTelAPI.attributeInt('db.row_count', r.rowCount!));
    }
    if (extras.isNotEmpty) span.addAttributes(OTelAPI.attributes(extras));
    return r.value;
  } catch (e, st) {
    span.addAttributes(OTelAPI.attributes([
      OTelAPI.attributeString(
        ErrorAttributes.errorType.key,
        e.runtimeType.toString(),
      ),
    ]));
    span.recordException(e, stackTrace: st);
    span.setStatus(SpanStatusCode.Error, e.toString());
    rethrow;
  } finally {
    span.end();
  }
}

/// Wraps a Databricks Jobs API call (run-now, get-run, cancel-run)
/// in a CLIENT span.
Future<T> tracedDatabricksJob<T>({
  required String action,
  required Future<T> Function() invoke,
  int? jobId,
  int? runId,
  String? workspaceHost,
}) async {
  if (databricksInstrumentationSuppressed()) {
    return invoke();
  }
  final m = <String, Object>{
    'databricks.product': 'jobs',
    'databricks.jobs.action': action,
  };
  if (jobId != null) m['databricks.job.id'] = jobId;
  if (runId != null) m['databricks.run.id'] = runId;
  if (workspaceHost != null) m['databricks.workspace.host'] = workspaceHost;

  final span = _tracer().startSpan(
    'databricks jobs.$action',
    kind: SpanKind.client,
    attributes: OTelAPI.attributesFromMap(m),
  );
  try {
    return await invoke();
  } catch (e, st) {
    span.addAttributes(OTelAPI.attributes([
      OTelAPI.attributeString(
        ErrorAttributes.errorType.key,
        e.runtimeType.toString(),
      ),
    ]));
    span.recordException(e, stackTrace: st);
    span.setStatus(SpanStatusCode.Error, e.toString());
    rethrow;
  } finally {
    span.end();
  }
}

String? _operationFromStatement(String statement) {
  final trimmed = statement.trimLeft();
  if (trimmed.isEmpty) return null;
  final first = trimmed.split(RegExp(r'\s+')).first.toUpperCase();
  const known = {
    'SELECT',
    'INSERT',
    'UPDATE',
    'DELETE',
    'CREATE',
    'ALTER',
    'DROP',
    'TRUNCATE',
    'COPY',
    'MERGE',
    'WITH',
    'SHOW',
    'USE',
    'OPTIMIZE',
    'VACUUM',
    'ANALYZE',
  };
  return known.contains(first) ? first : null;
}

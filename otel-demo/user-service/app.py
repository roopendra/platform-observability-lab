import logging
import os
import time

from flask import Flask, jsonify
from opentelemetry import trace
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.instrumentation.logging.handler import LoggingHandler
from opentelemetry.sdk._logs import LoggerProvider, LoggingHandler as SDKLoggingHandler
from opentelemetry.sdk._logs.export import BatchLogRecordProcessor
from opentelemetry.exporter.otlp.proto.http._log_exporter import OTLPLogExporter

OTEL_ENDPOINT = os.getenv(
    "OTEL_EXPORTER_OTLP_ENDPOINT",
    "http://opentelemetry-collector.opentelemetry.svc.cluster.local:4318",
)

resource = Resource.create({
    "service.name": "user-service",
    "service.version": "1.0",
})

trace_provider = TracerProvider(resource=resource)
trace_provider.add_span_processor(
    BatchSpanProcessor(
        OTLPSpanExporter(endpoint=f"{OTEL_ENDPOINT}/v1/traces")
    )
)
trace.set_tracer_provider(trace_provider)
tracer = trace.get_tracer("user-service")

logger_provider = LoggerProvider(resource=resource)
logger_provider.add_log_record_processor(
    BatchLogRecordProcessor(
        OTLPLogExporter(endpoint=f"{OTEL_ENDPOINT}/v1/logs")
    )
)
otel_log_handler = SDKLoggingHandler(
    level=logging.INFO,
    logger_provider=logger_provider,
)

logger = logging.getLogger("user-service")
logger.setLevel(logging.INFO)
logger.handlers.clear()
logger.addHandler(otel_log_handler)
logger.propagate = False

app = Flask(__name__)
FlaskInstrumentor().instrument_app(app)


@app.route("/users/<user_id>")
def get_user(user_id):
    with tracer.start_as_current_span("fetch-user") as span:
        span.set_attribute("user.id", user_id)

        logger.info("Fetching user")

        time.sleep(0.05)

        logger.info("User lookup completed")

        return jsonify({
            "id": user_id,
            "name": "Demo User",
            "status": "active",
        })


@app.route("/health")
def health():
    return jsonify({"status": "ok"})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8081)

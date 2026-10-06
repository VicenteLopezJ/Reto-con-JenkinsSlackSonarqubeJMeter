#!/usr/bin/env bash
# Levanta la aplicacion, ejecuta la prueba de carga JMeter y la detiene.
# Uso: ./scripts/carga.sh [usuarios] [rampup] [iteraciones] [puerto]
# Requiere: el .jar ya construido (mvn clean verify) y JMETER_HOME o jmeter en el PATH.
set -euo pipefail

THREADS="${1:-50}"
RAMPUP="${2:-10}"
LOOPS="${3:-10}"
PORT="${4:-8085}"

if [ -n "${JMETER_HOME:-}" ]; then JMETER="$JMETER_HOME/bin/jmeter"; else JMETER="jmeter"; fi

JAR=$(ls target/*.jar | grep -v '\.original$' | head -n 1)
mkdir -p target/jmeter
rm -rf target/jmeter/reporte target/jmeter/resultados.jtl

echo "Iniciando aplicacion: $JAR (puerto $PORT)"
java -jar "$JAR" --server.port="$PORT" > target/app.log 2>&1 &
APP_PID=$!
trap 'kill $APP_PID 2>/dev/null || true' EXIT

for i in $(seq 1 60); do
  if curl -s "http://localhost:$PORT/actuator/health" | grep -q '"UP"'; then
    echo "Aplicacion lista"; break
  fi
  if [ "$i" -eq 60 ]; then echo "La aplicacion no levanto"; cat target/app.log; exit 1; fi
  sleep 2
done

echo "Ejecutando JMeter: $THREADS usuarios, ramp-up ${RAMPUP}s, $LOOPS iteraciones"
"$JMETER" -n -t jmeter/PruebaCarga_Products_Login.jmx \
  -l target/jmeter/resultados.jtl -e -o target/jmeter/reporte \
  -Jthreads="$THREADS" -Jrampup="$RAMPUP" -Jloops="$LOOPS" -Jport="$PORT"

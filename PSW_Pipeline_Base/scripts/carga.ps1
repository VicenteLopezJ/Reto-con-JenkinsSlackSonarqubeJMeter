# Levanta la aplicacion, ejecuta la prueba de carga JMeter y la detiene (Windows).
# Uso: powershell -ExecutionPolicy Bypass -File scripts\carga.ps1 -Threads 50 -RampUp 10 -Loops 10 -Port 8085
# Requiere: el .jar ya construido (mvn clean verify) y JMETER_HOME (o JMeter en C:\apache-jmeter-5.6.3).
param(
    [int]$Threads = 50,
    [int]$RampUp = 10,
    [int]$Loops = 10,
    [int]$Port = 8085,
    [string]$JMeterHome = $env:JMETER_HOME
)
$ErrorActionPreference = 'Stop'
if (-not $JMeterHome) { $JMeterHome = 'C:\apache-jmeter-5.6.3' }
$jmeter = Join-Path $JMeterHome 'bin\jmeter.bat'
if (-not (Test-Path $jmeter)) { throw "No se encontro JMeter en $jmeter. Define JMETER_HOME." }

$jar = Get-ChildItem -Path 'target\*.jar' | Where-Object { $_.Name -notlike '*.original' } | Select-Object -First 1
if (-not $jar) { throw 'No existe el .jar en target. Ejecuta primero: mvn clean verify' }

New-Item -ItemType Directory -Force -Path 'target\jmeter' | Out-Null
Remove-Item -Recurse -Force 'target\jmeter\reporte', 'target\jmeter\resultados.jtl' -ErrorAction SilentlyContinue

Write-Host "Iniciando aplicacion: $($jar.Name) (puerto $Port)"
$app = Start-Process -FilePath 'java' -ArgumentList '-jar', "`"$($jar.FullName)`"", "--server.port=$Port" `
    -PassThru -NoNewWindow -RedirectStandardOutput 'target\app.log' -RedirectStandardError 'target\app-error.log'

try {
    $listo = $false
    for ($i = 0; $i -lt 60; $i++) {
        try {
            $r = Invoke-RestMethod -Uri "http://localhost:$Port/actuator/health" -TimeoutSec 2
            if ($r.status -eq 'UP') { $listo = $true; break }
        } catch { }
        Start-Sleep -Seconds 2
    }
    if (-not $listo) { throw "La aplicacion no levanto en el puerto $Port" }
    Write-Host 'Aplicacion lista'

    Write-Host "Ejecutando JMeter: $Threads usuarios, ramp-up $RampUp s, $Loops iteraciones"
    & $jmeter -n -t 'jmeter\PruebaCarga_Products_Login.jmx' -l 'target\jmeter\resultados.jtl' -e -o 'target\jmeter\reporte' `
        "-Jthreads=$Threads" "-Jrampup=$RampUp" "-Jloops=$Loops" "-Jport=$Port"
    if ($LASTEXITCODE -ne 0) { throw "JMeter termino con codigo $LASTEXITCODE" }
}
finally {
    Write-Host 'Deteniendo aplicacion'
    Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue
}

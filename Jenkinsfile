// =====================================================================
//  Pipeline de Calidad - PSW Pipeline Base
//  Flujo: Codigo -> Jenkins -> Build -> SonarQube -> JMeter -> Slack
//
//  Plugins requeridos: Pipeline, Git, JUnit, SonarQube Scanner,
//                      Slack Notification (HTML Publisher es opcional)
//  Funciona en agentes Windows (bat + PowerShell) y Linux/Mac (sh).
// =====================================================================

pipeline {
    agent any

    // Si configuraste herramientas en "Manage Jenkins > Tools", descomenta
    // y usa los mismos nombres. Si mvn y java ya estan en el PATH, dejalo asi.
    // tools {
    //     maven 'Maven3'
    //     jdk 'JDK17'
    // }

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 30, unit: 'MINUTES')
        disableConcurrentBuilds()
    }

    parameters {
        string(name: 'USUARIOS',    defaultValue: '50', description: 'Usuarios concurrentes en JMeter (entre 50 y 100)')
        string(name: 'RAMPUP',      defaultValue: '10', description: 'Ramp-up en segundos')
        string(name: 'ITERACIONES', defaultValue: '10', description: 'Iteraciones (loop count) por usuario')
        string(name: 'MAX_ERROR',   defaultValue: '5',  description: '% maximo de errores aceptado en JMeter')
        string(name: 'REPO_URL',    defaultValue: 'https://github.com/VicenteLopezJ/Reto-con-JenkinsSlackSonarqubeJMeter.git',
               description: 'Solo se usa si el job es "Pipeline script" (no "from SCM")')
        string(name: 'BRANCH',      defaultValue: 'main', description: 'Rama a construir')
        string(name: 'SLACK_CHANNEL', defaultValue: '', description: 'Canal de Slack (ej. #jenkins-pipeline). Vacio = canal por defecto del plugin')
    }

    environment {
        PROJECT_DIR   = 'PSW_Pipeline_Base'                  // carpeta del proyecto Maven
        SONAR_SERVER  = 'SonarQube'                          // nombre en Manage Jenkins > System > SonarQube servers
        SONAR_KEY     = 'psw-pipeline-base'
        APP_PORT      = '8085'
    }

    stages {

        stage('Checkout') {
            steps {
                script {
                    env.R_BUILD = 'NO EJECUTADO'
                    env.R_SONAR = 'NO EJECUTADO'
                    env.R_QG    = 'NO EJECUTADO'
                    env.R_JMETER = 'NO EJECUTADO'
                    env.R_JMETER_DETALLE = ''
                    try {
                        checkout scm                          // job "Pipeline script from SCM"
                    } catch (err) {
                        echo "checkout scm no disponible, clonando ${params.REPO_URL}"
                        git url: params.REPO_URL, branch: params.BRANCH
                    }
                }
                script { ejecutar('git log -1 --oneline', 'git log -1 --oneline') }
            }
        }

        stage('Build') {
            steps {
                dir(env.PROJECT_DIR) {
                    // compila, ejecuta pruebas unitarias, genera reporte JaCoCo y empaqueta el .jar
                    script { ejecutar('mvn -B clean verify', 'mvn -B clean verify') }
                }
            }
            post {
                always {
                    junit allowEmptyResults: true, testResults: "${env.PROJECT_DIR}/target/surefire-reports/*.xml"
                }
                success {
                    archiveArtifacts artifacts: "${env.PROJECT_DIR}/target/*.jar", fingerprint: true
                    script { env.R_BUILD = 'OK' }
                }
                failure {
                    script { env.R_BUILD = 'FALLO' }
                }
            }
        }

        stage('Analisis SonarQube') {
            steps {
                dir(env.PROJECT_DIR) {
                    withSonarQubeEnv(env.SONAR_SERVER) {
                        script {
                            String cmd = "mvn -B org.sonarsource.scanner.maven:sonar-maven-plugin:sonar -Dsonar.projectKey=${env.SONAR_KEY}"
                            ejecutar(cmd, cmd)
                        }
                    }
                }
            }
            post {
                success { script { env.R_SONAR = 'OK' } }
                failure { script { env.R_SONAR = 'FALLO' } }
            }
        }

        stage('Quality Gate') {
            steps {
                script {
                    try {
                        timeout(time: 3, unit: 'MINUTES') {
                            def qg = waitForQualityGate abortPipeline: false
                            env.R_QG = qg.status
                            if (qg.status != 'OK') {
                                unstable("Quality Gate de SonarQube: ${qg.status}")
                            }
                        }
                    } catch (err) {
                        // Ocurre si no se configuro el webhook SonarQube -> Jenkins
                        env.R_QG = 'SIN RESPUESTA'
                        echo 'No se recibio el Quality Gate (revisa el webhook en SonarQube). Se continua el pipeline.'
                    }
                }
            }
        }

        stage('Pruebas de carga JMeter') {
            steps {
                dir(env.PROJECT_DIR) {
                    script {
                        ejecutar(
                            "chmod +x scripts/carga.sh && ./scripts/carga.sh ${params.USUARIOS} ${params.RAMPUP} ${params.ITERACIONES} ${env.APP_PORT}",
                            "powershell -NoProfile -ExecutionPolicy Bypass -File scripts\\carga.ps1 -Threads ${params.USUARIOS} -RampUp ${params.RAMPUP} -Loops ${params.ITERACIONES} -Port ${env.APP_PORT}"
                        )
                        evaluarJMeter('target/jmeter/resultados.jtl', params.MAX_ERROR as String)
                    }
                }
            }
            post {
                always {
                    archiveArtifacts artifacts: "${env.PROJECT_DIR}/target/jmeter/**", allowEmptyArchive: true
                    script {
                        try {
                            publishHTML(target: [reportDir: "${env.PROJECT_DIR}/target/jmeter/reporte", reportFiles: 'index.html',
                                                 reportName: 'Reporte JMeter', keepAll: true, alwaysLinkToLastBuild: true, allowMissing: true])
                        } catch (err) {
                            echo 'HTML Publisher no instalado: el reporte queda en los artefactos del build.'
                        }
                    }
                }
                failure { script { if (env.R_JMETER == 'NO EJECUTADO') { env.R_JMETER = 'FALLO' } } }
            }
        }

        stage('Notificacion') {
            steps {
                script {
                    notificarSlack(currentBuild.currentResult)
                }
            }
        }
    }

    post {
        failure {
            script { notificarSlack('FAILURE') }
        }
        aborted {
            script { notificarSlack('ABORTED') }
        }
    }
}

// ---------------------------------------------------------------------
// Funciones auxiliares
// ---------------------------------------------------------------------

// Ejecuta un comando con sh (Linux/Mac) o bat (Windows)
def ejecutar(String cmdUnix, String cmdWindows) {
    if (isUnix()) {
        sh cmdUnix
    } else {
        bat cmdWindows
    }
}

// Lee el .jtl de JMeter, imprime metricas por endpoint y marca UNSTABLE si supera el % de error
def evaluarJMeter(String jtl, String maxError) {
    try {
        def resumen = resumirJtl(readFile(jtl))
        echo "===== Resultados JMeter =====\n${resumen.tabla}"
        env.R_JMETER_DETALLE = resumen.slack
        double limite = Double.parseDouble(maxError)
        if (resumen.errorTotal > limite) {
            env.R_JMETER = "ERRORES ${String.format('%.2f', resumen.errorTotal)}%"
            unstable("JMeter supero el ${maxError}% de errores")
        } else {
            env.R_JMETER = 'OK'
        }
    } catch (err) {
        env.R_JMETER = 'EJECUTADO (sin resumen)'
        echo "No se pudo resumir el .jtl: ${err}"
    }
}

@NonCPS
def resumirJtl(String contenido) {
    def lineas = contenido.split('\n')
    def cab = lineas[0].trim().split(',')
    int iTs = -1, iEl = -1, iLb = -1, iOk = -1
    for (int c = 0; c < cab.length; c++) {
        if (cab[c] == 'timeStamp') { iTs = c }
        if (cab[c] == 'elapsed')   { iEl = c }
        if (cab[c] == 'label')     { iLb = c }
        if (cab[c] == 'success')   { iOk = c }
    }
    def stats = [:]
    long totalN = 0, totalErr = 0
    for (int i = 1; i < lineas.length; i++) {
        def f = lineas[i].trim().split(',')
        if (f.length <= iOk) { continue }
        String label = f[iLb]
        long ts = Long.parseLong(f[iTs])
        long el = Long.parseLong(f[iEl])
        boolean ok = f[iOk] == 'true'
        def s = stats[label]
        if (s == null) {
            s = [n: 0L, err: 0L, sum: 0L, min: Long.MAX_VALUE, max: 0L, ini: Long.MAX_VALUE, fin: 0L]
            stats[label] = s
        }
        s.n = s.n + 1
        s.sum = s.sum + el
        if (el < s.min) { s.min = el }
        if (el > s.max) { s.max = el }
        if (ts < s.ini) { s.ini = ts }
        if (ts + el > s.fin) { s.fin = ts + el }
        if (!ok) { s.err = s.err + 1; totalErr++ }
        totalN++
    }
    def tabla = new StringBuilder()
    def slack = new StringBuilder()
    tabla.append(String.format('%-16s %8s %8s %8s %8s %10s %8s%n', 'Endpoint', 'Muestras', 'Prom(ms)', 'Min(ms)', 'Max(ms)', 'Req/s', 'Error%'))
    stats.each { label, s ->
        double prom = s.n > 0 ? (s.sum as double) / s.n : 0d
        double seg = Math.max(1L, s.fin - s.ini) / 1000d
        double tput = s.n / seg
        double errPct = s.n > 0 ? (s.err * 100d) / s.n : 0d
        tabla.append(String.format('%-16s %8d %8.1f %8d %8d %10.2f %7.2f%%%n', label, s.n, prom, s.min, s.max, tput, errPct))
        slack.append(String.format('- %s: %d req | prom %.1f ms | %.2f req/s | error %.2f%%\n', label, s.n, prom, tput, errPct))
    }
    double errorTotal = totalN > 0 ? (totalErr * 100d) / totalN : 0d
    tabla.append(String.format('TOTAL: %d solicitudes, %.2f%% de error%n', totalN, errorTotal))
    return [tabla: tabla.toString(), slack: slack.toString(), errorTotal: errorTotal]
}

// Envia el resultado a Slack (no rompe el pipeline si Slack no esta configurado)
def notificarSlack(String estado) {
    def colores = [SUCCESS: 'good', UNSTABLE: 'warning', FAILURE: 'danger', ABORTED: '#808080']
    def iconos  = [SUCCESS: ':white_check_mark:', UNSTABLE: ':warning:', FAILURE: ':x:', ABORTED: ':no_entry_sign:']
    String msg = "${iconos[estado] ?: ''} *${env.JOB_NAME}* #${env.BUILD_NUMBER} - *${estado}*\n" +
                 "Build: ${env.R_BUILD ?: 'NO EJECUTADO'} | SonarQube: ${env.R_SONAR ?: 'NO EJECUTADO'} " +
                 "(Quality Gate: ${env.R_QG ?: 'NO EJECUTADO'}) | JMeter: ${env.R_JMETER ?: 'NO EJECUTADO'}\n" +
                 (env.R_JMETER_DETALLE ? "${env.R_JMETER_DETALLE}" : '') +
                 "Detalle: ${env.BUILD_URL}"
    def args = [color: colores[estado] ?: 'good', message: msg]
    if (params.SLACK_CHANNEL?.trim()) {
        args.channel = params.SLACK_CHANNEL.trim()
    }
    try {
        slackSend(args)
    } catch (err) {
        echo "No se pudo enviar a Slack: ${err}"
    }
}

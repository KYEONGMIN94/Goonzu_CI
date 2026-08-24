pipeline {
    agent { label 'goonzu-windows' }

    options {
        disableConcurrentBuilds()
        skipDefaultCheckout(false)
    }

    parameters {
        choice(
            name: 'BUILD_TARGET',
            choices: ['Auto', 'All'],
            description: 'Auto uses change-impact analysis. All forces every supported target.'
        )
        string(
            name: 'SOURCE_BRANCH',
            defaultValue: 'master',
            description: 'Goonzu_Build branch to verify'
        )
        string(
            name: 'BASE_REVISION',
            defaultValue: 'origin/master',
            description: 'Merge base used by preflight and impact analysis'
        )
    }

    environment {
        SOURCE_REPOSITORY = 'https://github.com/KYEONGMIN94/Goonzu_Build.git'
        DEVENV_PATH = 'C:\\Program Files (x86)\\Microsoft Visual Studio .NET 2003\\Common7\\IDE\\devenv.com'
    }

    stages {
        stage('Reset generated workspace') {
            steps {
                dir('src') { deleteDir() }
                dir('artifacts') { deleteDir() }
                dir('build') { deleteDir() }
            }
        }

        stage('Checkout exact source') {
            steps {
                dir('src') {
                    checkout([
                        $class: 'GitSCM',
                        branches: [[name: "*/${params.SOURCE_BRANCH}"]],
                        doGenerateSubmoduleConfigurations: false,
                        extensions: [],
                        userRemoteConfigs: [[url: env.SOURCE_REPOSITORY]]
                    ])
                    bat 'git status --porcelain'
                    bat 'git rev-parse HEAD'
                }
            }
        }

        stage('Verify environment') {
            steps {
                bat '''powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%WORKSPACE%\\scripts\\Test-BuildEnvironment.ps1" -SourceRoot "%WORKSPACE%\\src" -DevenvPath "%DEVENV_PATH%"'''
            }
        }

        stage('Preflight and impact') {
            steps {
                bat '''powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%WORKSPACE%\\scripts\\Invoke-Preflight.ps1" -SourceRoot "%WORKSPACE%\\src" -BaseRevision "%BASE_REVISION%" -OutputDirectory "%WORKSPACE%\\artifacts\\meta" -RequireClean'''
                script {
                    def impact = [:]
                    readFile('artifacts/meta/impact.properties').readLines().each { line ->
                        def pair = line.split('=', 2)
                        if (pair.size() == 2) { impact[pair[0]] = pair[1] }
                    }
                    env.RESOLVED_BUILD_TARGET = params.BUILD_TARGET == 'All' ? 'All' : impact['BuildTarget']
                    currentBuild.description = "${env.RESOLVED_BUILD_TARGET} ${impact['CommitSha']?.take(12)}"
                    echo "Resolved build target: ${env.RESOLVED_BUILD_TARGET}"
                }
            }
        }

        stage('Prepare isolated outputs') {
            when { expression { env.RESOLVED_BUILD_TARGET != 'None' } }
            steps {
                bat '''powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%WORKSPACE%\\scripts\\Prepare-IsolatedBuild.ps1" -SourceRoot "%WORKSPACE%\\src" -StagingRoot "%WORKSPACE%" -Target "%RESOLVED_BUILD_TARGET%" -BuildTargetsPath "%WORKSPACE%\\config\\build-targets.csv" -DependenciesPath "%WORKSPACE%\\config\\build-dependencies.csv"'''
            }
        }

        stage('Build') {
            when { expression { env.RESOLVED_BUILD_TARGET != 'None' } }
            steps {
                bat '''powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%WORKSPACE%\\scripts\\Invoke-GoonzuBuild.ps1" -SourceRoot "%WORKSPACE%\\src" -Target "%RESOLVED_BUILD_TARGET%" -DevenvPath "%DEVENV_PATH%" -StagingRoot "%WORKSPACE%" -BuildTargetsPath "%WORKSPACE%\\config\\build-targets.csv"'''
            }
        }
    }

    post {
        always {
            archiveArtifacts artifacts: 'artifacts/**/*', fingerprint: true, allowEmptyArchive: true
        }
    }
}

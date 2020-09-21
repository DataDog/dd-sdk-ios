/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal struct DDEnvironmentValues {
    /// Datatog Configuration values
    let ddClientToken: String?
    let ddEnvironment: String?
    let ddService: String?

    /// CI  values
    let isCi: Bool
    let provider: String?
    let repository: String?
    let commit: String?
    let sourceRoot: String?
    let workspacePath: String?
    let pipelineId: String?
    let pipelineNumber: String?
    let pipelineURL: String?
    let jobURL: String?
    let branch: String?
    let tag: String?

    static var environment = ProcessInfo.processInfo.environment

    init() {
        /// Datatog configuration values
        var clientToken: String?
        clientToken = DDEnvironmentValues.getEnvVariable("DATADOG_CLIENT_TOKEN")
        if clientToken == nil {
            clientToken = Bundle.main.infoDictionary?["DatadogClientToken"] as? String
        }
        ddClientToken = clientToken

        ddEnvironment = DDEnvironmentValues.getEnvVariable("DD_ENV")
        ddService = DDEnvironmentValues.getEnvVariable("DD_SERVICE")

        /// CI  values
        var branchEnv: String?
        if DDEnvironmentValues.getEnvVariable("TRAVIS") != nil {
            isCi = true
            provider = "travis"
            repository = DDEnvironmentValues.getEnvVariable("TRAVIS_REPO_SLUG")
            commit = DDEnvironmentValues.getEnvVariable("TRAVIS_COMMIT")
            sourceRoot = DDEnvironmentValues.getEnvVariable("TRAVIS_BUILD_DIR")
            pipelineId = DDEnvironmentValues.getEnvVariable("TRAVIS_BUILD_ID")
            pipelineNumber = DDEnvironmentValues.getEnvVariable("TRAVIS_BUILD_NUMBER")
            pipelineURL = DDEnvironmentValues.getEnvVariable("TRAVIS_BUILD_WEB_URL")
            jobURL = DDEnvironmentValues.getEnvVariable("TRAVIS_JOB_WEB_URL")
            branchEnv = DDEnvironmentValues.getEnvVariable("TRAVIS_PULL_REQUEST_BRANCH")
            if branchEnv?.isEmpty ?? true {
                branchEnv = DDEnvironmentValues.getEnvVariable("TRAVIS_BRANCH")
            }
            tag = nil
        } else if DDEnvironmentValues.getEnvVariable("CIRCLECI") != nil {
            isCi = true
            provider = "circleci"
            repository = DDEnvironmentValues.getEnvVariable("CIRCLE_REPOSITORY_URL")
            commit = DDEnvironmentValues.getEnvVariable("CIRCLE_SHA1")
            sourceRoot = DDEnvironmentValues.getEnvVariable("CIRCLE_WORKING_DIRECTORY")
            pipelineId = nil
            pipelineNumber = DDEnvironmentValues.getEnvVariable("CIRCLE_BUILD_NUM")
            pipelineURL = DDEnvironmentValues.getEnvVariable("CIRCLE_BUILD_URL")
            jobURL = nil
            branchEnv = DDEnvironmentValues.getEnvVariable("CIRCLE_BRANCH")
            tag = nil
        } else if DDEnvironmentValues.getEnvVariable("JENKINS_URL") != nil {
            isCi = true
            provider = "jenkins"
            repository = DDEnvironmentValues.getEnvVariable("GIT_URL")
            commit = DDEnvironmentValues.getEnvVariable("GIT_COMMIT")
            sourceRoot = DDEnvironmentValues.getEnvVariable("WORKSPACE")
            pipelineId = DDEnvironmentValues.getEnvVariable("BUILD_ID")
            pipelineNumber = DDEnvironmentValues.getEnvVariable("BUILD_NUMBER")
            pipelineURL = DDEnvironmentValues.getEnvVariable("BUILD_URL")
            jobURL = DDEnvironmentValues.getEnvVariable("JOB_URL")
            branchEnv = DDEnvironmentValues.getEnvVariable("GIT_BRANCH")
            if let branchCopy = branchEnv, branchCopy.hasPrefix("origin/") {
                branchEnv = String(branchCopy.dropFirst("origin/".count))
            }
            tag = nil
        } else if DDEnvironmentValues.getEnvVariable("GITLAB_CI") != nil {
            isCi = true
            provider = "gitlab"
            repository = DDEnvironmentValues.getEnvVariable("CI_REPOSITORY_URL")
            commit = DDEnvironmentValues.getEnvVariable("CI_COMMIT_SHA")
            sourceRoot = DDEnvironmentValues.getEnvVariable("CI_PROJECT_DIR")
            pipelineId = DDEnvironmentValues.getEnvVariable("CI_PIPELINE_ID")
            pipelineNumber = DDEnvironmentValues.getEnvVariable("CI_PIPELINE_IID")
            pipelineURL = DDEnvironmentValues.getEnvVariable("CI_PIPELINE_URL")
            jobURL = DDEnvironmentValues.getEnvVariable("CI_JOB_URL")
            branchEnv = DDEnvironmentValues.getEnvVariable("CI_COMMIT_BRANCH")
            if branchEnv?.isEmpty ?? true {
                branchEnv = DDEnvironmentValues.getEnvVariable("CI_COMMIT_REF_NAME")
            }
            tag = DDEnvironmentValues.getEnvVariable("CI_COMMIT_TAG")
        } else if DDEnvironmentValues.getEnvVariable("APPVEYOR") != nil {
            isCi = true
            provider = "appveyor"
            repository = DDEnvironmentValues.getEnvVariable("APPVEYOR_REPO_NAME")
            commit = DDEnvironmentValues.getEnvVariable("APPVEYOR_REPO_COMMIT")
            sourceRoot = DDEnvironmentValues.getEnvVariable("APPVEYOR_BUILD_FOLDER")
            pipelineId = DDEnvironmentValues.getEnvVariable("APPVEYOR_BUILD_ID")
            pipelineNumber = DDEnvironmentValues.getEnvVariable("APPVEYOR_BUILD_NUMBER")
            let projectSlug = DDEnvironmentValues.getEnvVariable("APPVEYOR_PROJECT_SLUG")
            pipelineURL = "https://ci.appveyor.com/project/\(projectSlug ?? "")/builds/\(pipelineId ?? "")"
            jobURL = nil
            branchEnv = DDEnvironmentValues.getEnvVariable("APPVEYOR_PULL_REQUEST_HEAD_REPO_BRANCH")
            if branchEnv?.isEmpty ?? true {
                branchEnv = DDEnvironmentValues.getEnvVariable("APPVEYOR_REPO_BRANCH")
            }
            tag = nil
        } else if DDEnvironmentValues.getEnvVariable("TF_BUILD") != nil {
            isCi = true
            provider = "azurepipelines"
            sourceRoot = DDEnvironmentValues.getEnvVariable("BUILD_SOURCESDIRECTORY")
            pipelineId = DDEnvironmentValues.getEnvVariable("BUILD_BUILDID")
            pipelineNumber = DDEnvironmentValues.getEnvVariable("BUILD_BUILDNUMBER")

            let foundationCollectionUri = DDEnvironmentValues.getEnvVariable("SYSTEM_TEAMFOUNDATIONCOLLECTIONURI")
            let teamProject = DDEnvironmentValues.getEnvVariable("SYSTEM_TEAMPROJECT")
            pipelineURL = "\(foundationCollectionUri ?? "")/\(teamProject ?? "")/_build/results?buildId=\(pipelineId ?? "")&_a=summary"
            jobURL = nil
            repository = DDEnvironmentValues.getEnvVariable("BUILD_REPOSITORY_URI")

            var commitEnv = DDEnvironmentValues.getEnvVariable("SYSTEM_PULLREQUEST_SOURCECOMMITID")
            if commitEnv?.isEmpty ?? true {
                commitEnv = DDEnvironmentValues.getEnvVariable("BUILD_SOURCEVERSION")
            }
            commit = commitEnv

            branchEnv = DDEnvironmentValues.getEnvVariable("SYSTEM_PULLREQUEST_SOURCEBRANCH")
            if branchEnv?.isEmpty ?? true {
                branchEnv = DDEnvironmentValues.getEnvVariable("BUILD_SOURCEBRANCHNAME")
            }
            if branchEnv?.isEmpty ?? true {
                branchEnv = DDEnvironmentValues.getEnvVariable("BUILD_SOURCEBRANCH")
            }
            tag = nil
        } else if DDEnvironmentValues.getEnvVariable("BITBUCKET_COMMIT") != nil {
            isCi = true
            provider = "bitbucketpipelines"
            repository = DDEnvironmentValues.getEnvVariable("BITBUCKET_GIT_SSH_ORIGIN")
            commit = DDEnvironmentValues.getEnvVariable("BITBUCKET_COMMIT")
            sourceRoot = DDEnvironmentValues.getEnvVariable("BITBUCKET_CLONE_DIR")
            pipelineId = DDEnvironmentValues.getEnvVariable("BITBUCKET_PIPELINE_UUID")
            pipelineNumber = DDEnvironmentValues.getEnvVariable("BITBUCKET_BUILD_NUMBER")
            pipelineURL = nil
            jobURL = nil
            tag = nil
        } else if DDEnvironmentValues.getEnvVariable("GITHUB_SHA") != nil {
            isCi = true
            provider = "github"
            repository = DDEnvironmentValues.getEnvVariable("GITHUB_REPOSITORY")
            commit = DDEnvironmentValues.getEnvVariable("GITHUB_SHA")
            sourceRoot = DDEnvironmentValues.getEnvVariable("GITHUB_WORKSPACE")
            pipelineId = DDEnvironmentValues.getEnvVariable("GITHUB_RUN_ID")
            pipelineNumber = DDEnvironmentValues.getEnvVariable("GITHUB_RUN_NUMBER")
            pipelineURL = "\(repository ?? "")/commit/\(commit ?? "")/checks"
            jobURL = nil
            branchEnv = DDEnvironmentValues.getEnvVariable("GITHUB_REF")
            tag = nil
        } else if DDEnvironmentValues.getEnvVariable("TEAMCITY_VERSION") != nil {
            isCi = true
            provider = "teamcity"
            repository = DDEnvironmentValues.getEnvVariable("BUILD_VCS_URL")
            commit = DDEnvironmentValues.getEnvVariable("BUILD_VCS_NUMBER")
            sourceRoot = DDEnvironmentValues.getEnvVariable("BUILD_CHECKOUTDIR")
            pipelineId = DDEnvironmentValues.getEnvVariable("BUILD_ID")
            pipelineNumber = DDEnvironmentValues.getEnvVariable("BUILD_NUMBER")
            let serverUrl = DDEnvironmentValues.getEnvVariable("SERVER_URL")
            if let pipelineId = pipelineId, let serverUrl = serverUrl {
                pipelineURL = "\(serverUrl)/viewLog.html?buildId=\(pipelineId)"
            } else {
                pipelineURL = nil
            }
            jobURL = nil
            tag = nil
        } else if DDEnvironmentValues.getEnvVariable("BUILDKITE") != nil {
            isCi = true
            provider = "buildkite"
            repository = DDEnvironmentValues.getEnvVariable("BUILDKITE_REPO")
            commit = DDEnvironmentValues.getEnvVariable("BUILDKITE_COMMIT")
            sourceRoot = DDEnvironmentValues.getEnvVariable("BUILDKITE_BUILD_CHECKOUT_PATH")
            pipelineId = DDEnvironmentValues.getEnvVariable("BUILDKITE_BUILD_ID")
            pipelineNumber = DDEnvironmentValues.getEnvVariable("BUILDKITE_BUILD_NUMBER")
            pipelineURL = DDEnvironmentValues.getEnvVariable("BUILDKITE_BUILD_URL")
            jobURL = nil
            branchEnv = DDEnvironmentValues.getEnvVariable("BUILDKITE_BRANCH")
            tag = nil
        } else if DDEnvironmentValues.getEnvVariable("BITRISE_BUILD_NUMBER") != nil {
            isCi = true
            provider = "bitrise"
            repository = DDEnvironmentValues.getEnvVariable("GIT_REPOSITORY_URL")
            commit = DDEnvironmentValues.getEnvVariable("BITRISE_GIT_COMMIT")
            sourceRoot = DDEnvironmentValues.getEnvVariable("BITRISE_SOURCE_DIR")
            pipelineId = DDEnvironmentValues.getEnvVariable("BITRISE_TRIGGERED_WORKFLOW_ID")
            pipelineNumber = DDEnvironmentValues.getEnvVariable("BITRISE_BUILD_NUMBER")
            jobURL = DDEnvironmentValues.getEnvVariable("BITRISE_APP_URL")
            pipelineURL = DDEnvironmentValues.getEnvVariable("BITRISE_BUILD_URL")
            branchEnv = DDEnvironmentValues.getEnvVariable("BITRISEIO_GIT_BRANCH_DEST")
            if branchEnv?.isEmpty ?? true {
                branchEnv = DDEnvironmentValues.getEnvVariable("BITRISE_GIT_BRANCH")
            }
            tag = DDEnvironmentValues.getEnvVariable("BITRISE_GIT_TAG")
        } else {
            isCi = false
            provider = nil
            repository = nil
            commit = nil
            sourceRoot = nil
            pipelineId = nil
            pipelineNumber = nil
            pipelineURL = nil
            jobURL = nil
            branchEnv = nil
            tag = nil
        }

        /// Remove /refs/heads/ from the branch when it appears. Some CI's add this info.
        if let branchCopy = branchEnv {
            if branchCopy.hasPrefix("/refs/heads/") {
                branchEnv = String(branchCopy.dropFirst("/refs/heads/".count))
            } else if branchCopy.hasPrefix("/refs/") {
                branchEnv = String(branchCopy.dropFirst("/refs/".count))
            }
        }
        self.branch = branchEnv

        /// Currently workspacePath is the same than sourceRoot, it could change in the future
        workspacePath = sourceRoot
    }

    func addTagsToSpan( span: OTSpan ) {
        guard isCi else {
            return
        }

        setTagToSpanIfExist(span: span, key: DDCITags.ciProvider, value: provider)
        setTagToSpanIfExist(span: span, key: DDCITags.ciPipelineId, value: pipelineId)
        setTagToSpanIfExist(span: span, key: DDCITags.ciPipelineNumber, value: pipelineNumber)
        setTagToSpanIfExist(span: span, key: DDCITags.ciPipelineURL, value: pipelineURL)
        setTagToSpanIfExist(span: span, key: DDCITags.ciJobURL, value: jobURL)
        setTagToSpanIfExist(span: span, key: DDCITags.ciWorkspacePath, value: sourceRoot)

        setTagToSpanIfExist(span: span, key: DDCITags.gitRepository, value: repository)
        setTagToSpanIfExist(span: span, key: DDCITags.gitCommit, value: commit)
        setTagToSpanIfExist(span: span, key: DDCITags.gitBranch, value: branch)
        setTagToSpanIfExist(span: span, key: DDCITags.gitTag, value: tag)

        setTagToSpanIfExist( span: span, key: DDCITags.buildSourceRoot, value: sourceRoot)
    }

    private func setTagToSpanIfExist(span: OTSpan, key: String, value: String?) {
        if let value = value {
            span.setTag(key: key, value: value)
        }
    }

    static func getEnvVariable(_ name: String) -> String? {
        guard let variable = environment[name] else {
            return nil
        }
        let returnVariable = variable.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        return returnVariable.isEmpty ? nil : returnVariable
    }
}

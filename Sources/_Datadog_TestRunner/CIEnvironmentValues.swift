/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal struct CIEnvironmentValues {
    let isCi: Bool
    let provider: String?
    let repository: String?
    let commit: String?
    let branch: String?
    let tag: String?
    let sourceRoot: String?
    let workspacePath: String?
    let pipelineId: String?
    let pipelineNumber: String?
    let pipelineURL: String?
    let jobURL: String?

    static var environment = ProcessInfo.processInfo.environment

    init() {
        if CIEnvironmentValues.getEnvVariable("TRAVIS") != nil {
            isCi = true
            provider = "travis"
            repository = CIEnvironmentValues.getEnvVariable("TRAVIS_REPO_SLUG")
            commit = CIEnvironmentValues.getEnvVariable("TRAVIS_COMMIT")
            sourceRoot = CIEnvironmentValues.getEnvVariable("TRAVIS_BUILD_DIR")
            pipelineId = CIEnvironmentValues.getEnvVariable("TRAVIS_BUILD_ID")
            pipelineNumber = CIEnvironmentValues.getEnvVariable("TRAVIS_BUILD_NUMBER")
            pipelineURL = CIEnvironmentValues.getEnvVariable("TRAVIS_BUILD_WEB_URL")
            jobURL = CIEnvironmentValues.getEnvVariable("TRAVIS_JOB_WEB_URL")
            branch = CIEnvironmentValues.getEnvVariable("TRAVIS_PULL_REQUEST_BRANCH")
            if branch?.isEmpty ?? true {
                branch = CIEnvironmentValues.getEnvVariable("TRAVIS_BRANCH")
            }
        } else if CIEnvironmentValues.getEnvVariable("CIRCLECI") != nil {
            isCi = true
            provider = "circleci"
            repository = CIEnvironmentValues.getEnvVariable("CIRCLE_REPOSITORY_URL")
            commit = CIEnvironmentValues.getEnvVariable("CIRCLE_SHA1")
            sourceRoot = CIEnvironmentValues.getEnvVariable("CIRCLE_WORKING_DIRECTORY")
            pipelineId = nil
            pipelineNumber = CIEnvironmentValues.getEnvVariable("CIRCLE_BUILD_NUM")
            pipelineURL = CIEnvironmentValues.getEnvVariable("CIRCLE_BUILD_URL")
            branch = CIEnvironmentValues.getEnvVariable("CIRCLE_BRANCH")
        } else if CIEnvironmentValues.getEnvVariable("JENKINS_URL") != nil {
            isCi = true
            provider = "jenkins"
            repository = CIEnvironmentValues.getEnvVariable("GIT_URL")
            commit = CIEnvironmentValues.getEnvVariable("GIT_COMMIT")
            sourceRoot = CIEnvironmentValues.getEnvVariable("WORKSPACE")
            pipelineId = CIEnvironmentValues.getEnvVariable("BUILD_ID")
            pipelineNumber = CIEnvironmentValues.getEnvVariable("BUILD_NUMBER")
            pipelineURL = CIEnvironmentValues.getEnvVariable("BUILD_URL")
            jobURL = CIEnvironmentValues.getEnvVariable("JOB_URL")
            branch = CIEnvironmentValues.getEnvVariable("GIT_BRANCH")
            if let branchCopy = branch, branchCopy.hasPrefix("origin/") {
                branch = String(branchCopy.dropFirst("origin/".count))
            }
        } else if CIEnvironmentValues.getEnvVariable("GITLAB_CI") != nil {
            isCi = true
            provider = "gitlab"
            repository = CIEnvironmentValues.getEnvVariable("CI_REPOSITORY_URL")
            commit = CIEnvironmentValues.getEnvVariable("CI_COMMIT_SHA")
            sourceRoot = CIEnvironmentValues.getEnvVariable("CI_PROJECT_DIR")
            pipelineId = CIEnvironmentValues.getEnvVariable("CI_PIPELINE_ID")
            pipelineNumber = CIEnvironmentValues.getEnvVariable("CI_PIPELINE_IID")
            pipelineURL = CIEnvironmentValues.getEnvVariable("CI_PIPELINE_URL")
            jobURL = CIEnvironmentValues.getEnvVariable("CI_JOB_URL")
            branch = CIEnvironmentValues.getEnvVariable("CI_COMMIT_BRANCH")
            if branch?.isEmpty ?? true {
                branch = CIEnvironmentValues.getEnvVariable("CI_COMMIT_REF_NAME")
            }
            tag = CIEnvironmentValues.getEnvVariable("CI_COMMIT_TAG")
        } else if CIEnvironmentValues.getEnvVariable("APPVEYOR") != nil {
            isCi = true
            provider = "appveyor"
            repository = CIEnvironmentValues.getEnvVariable("APPVEYOR_REPO_NAME")
            commit = CIEnvironmentValues.getEnvVariable("APPVEYOR_REPO_COMMIT")
            sourceRoot = CIEnvironmentValues.getEnvVariable("APPVEYOR_BUILD_FOLDER")
            pipelineId = CIEnvironmentValues.getEnvVariable("APPVEYOR_BUILD_ID")
            pipelineNumber = CIEnvironmentValues.getEnvVariable("APPVEYOR_BUILD_NUMBER")
            let projectSlug = CIEnvironmentValues.getEnvVariable("APPVEYOR_PROJECT_SLUG")
            pipelineURL = "https://ci.appveyor.com/project/\(projectSlug ?? "")/builds/\(pipelineId ?? "")"
            branch = CIEnvironmentValues.getEnvVariable("APPVEYOR_PULL_REQUEST_HEAD_REPO_BRANCH")
            if branch?.isEmpty ?? true {
                branch = CIEnvironmentValues.getEnvVariable("APPVEYOR_REPO_BRANCH")
            }
        } else if CIEnvironmentValues.getEnvVariable("TF_BUILD") != nil {
            isCi = true
            provider = "azurepipelines"
            sourceRoot = CIEnvironmentValues.getEnvVariable("BUILD_SOURCESDIRECTORY")
            pipelineId = CIEnvironmentValues.getEnvVariable("BUILD_BUILDID")
            pipelineNumber = CIEnvironmentValues.getEnvVariable("BUILD_BUILDNUMBER")

            let foundationCollectionUri = CIEnvironmentValues.getEnvVariable("SYSTEM_TEAMFOUNDATIONCOLLECTIONURI")
            let teamProject = CIEnvironmentValues.getEnvVariable("SYSTEM_TEAMPROJECT")
            pipelineURL = "\(foundationCollectionUri ?? "")/\(teamProject ?? "")/_build/results?buildId=\(pipelineId ?? "")&_a=summary"
            repository = CIEnvironmentValues.getEnvVariable("BUILD_REPOSITORY_URI")

            commit = CIEnvironmentValues.getEnvVariable("SYSTEM_PULLREQUEST_SOURCECOMMITID")
            if commit?.isEmpty ?? true {
                commit = CIEnvironmentValues.getEnvVariable("BUILD_SOURCEVERSION")
            }

            branch = CIEnvironmentValues.getEnvVariable("SYSTEM_PULLREQUEST_SOURCEBRANCH")
            if branch?.isEmpty ?? true {
                branch = CIEnvironmentValues.getEnvVariable("BUILD_SOURCEBRANCHNAME")
            }
            if branch?.isEmpty ?? true {
                branch = CIEnvironmentValues.getEnvVariable("BUILD_SOURCEBRANCH")
            }
        } else if CIEnvironmentValues.getEnvVariable("BITBUCKET_COMMIT") != nil {
            isCi = true
            provider = "bitbucketpipelines"
            repository = CIEnvironmentValues.getEnvVariable("BITBUCKET_GIT_SSH_ORIGIN")
            commit = CIEnvironmentValues.getEnvVariable("BITBUCKET_COMMIT")
            sourceRoot = CIEnvironmentValues.getEnvVariable("BITBUCKET_CLONE_DIR")
            pipelineId = CIEnvironmentValues.getEnvVariable("BITBUCKET_PIPELINE_UUID")
            pipelineNumber = CIEnvironmentValues.getEnvVariable("BITBUCKET_BUILD_NUMBER")
            pipelineURL = nil
        } else if CIEnvironmentValues.getEnvVariable("GITHUB_SHA") != nil {
            isCi = true
            provider = "github"
            repository = CIEnvironmentValues.getEnvVariable("GITHUB_REPOSITORY")
            commit = CIEnvironmentValues.getEnvVariable("GITHUB_SHA")
            sourceRoot = CIEnvironmentValues.getEnvVariable("GITHUB_WORKSPACE")
            pipelineId = CIEnvironmentValues.getEnvVariable("GITHUB_RUN_ID")
            pipelineNumber = CIEnvironmentValues.getEnvVariable("GITHUB_RUN_NUMBER")
            pipelineURL = "\(repository ?? "")/commit/\(commit ?? "")/checks"
            branch = CIEnvironmentValues.getEnvVariable("GITHUB_REF")
        } else if CIEnvironmentValues.getEnvVariable("TEAMCITY_VERSION") != nil {
            isCi = true
            provider = "teamcity"
            repository = CIEnvironmentValues.getEnvVariable("BUILD_VCS_URL")
            commit = CIEnvironmentValues.getEnvVariable("BUILD_VCS_NUMBER")
            sourceRoot = CIEnvironmentValues.getEnvVariable("BUILD_CHECKOUTDIR")
            pipelineId = CIEnvironmentValues.getEnvVariable("BUILD_ID")
            pipelineNumber = CIEnvironmentValues.getEnvVariable("BUILD_NUMBER")
            let serverUrl = CIEnvironmentValues.getEnvVariable("SERVER_URL")
            if let pipelineId = pipelineId, let serverUrl = serverUrl {
                pipelineURL = "\(serverUrl)/viewLog.html?buildId=\(pipelineId)"
            } else {
                pipelineURL = nil
            }
        } else if CIEnvironmentValues.getEnvVariable("BUILDKITE") != nil {
            isCi = true
            provider = "buildkite"
            repository = CIEnvironmentValues.getEnvVariable("BUILDKITE_REPO")
            commit = CIEnvironmentValues.getEnvVariable("BUILDKITE_COMMIT")
            sourceRoot = CIEnvironmentValues.getEnvVariable("BUILDKITE_BUILD_CHECKOUT_PATH")
            pipelineId = CIEnvironmentValues.getEnvVariable("BUILDKITE_BUILD_ID")
            pipelineNumber = CIEnvironmentValues.getEnvVariable("BUILDKITE_BUILD_NUMBER")
            pipelineURL = CIEnvironmentValues.getEnvVariable("BUILDKITE_BUILD_URL")
            branch = CIEnvironmentValues.getEnvVariable("BUILDKITE_BRANCH")
        } else if CIEnvironmentValues.getEnvVariable("BITRISE_BUILD_NUMBER") != nil {
            isCi = true
            provider = "bitrise"
            repository = CIEnvironmentValues.getEnvVariable("GIT_REPOSITORY_URL")
            commit = CIEnvironmentValues.getEnvVariable("BITRISE_GIT_COMMIT")
            sourceRoot = CIEnvironmentValues.getEnvVariable("BITRISE_SOURCE_DIR")
            pipelineId = CIEnvironmentValues.getEnvVariable("BITRISE_TRIGGERED_WORKFLOW_ID")
            pipelineNumber = CIEnvironmentValues.getEnvVariable("BITRISE_BUILD_NUMBER")
            jobURL = CIEnvironmentValues.getEnvVariable("BITRISE_APP_URL")
            pipelineURL = CIEnvironmentValues.getEnvVariable("BITRISE_BUILD_URL")
            branch = CIEnvironmentValues.getEnvVariable("BITRISEIO_GIT_BRANCH_DEST")
            if branch?.isEmpty ?? true {
                branch = CIEnvironmentValues.getEnvVariable("BITRISE_GIT_BRANCH")
            }
            tag = CIEnvironmentValues.getEnvVariable("BITRISE_GIT_TAG")
        } else {
            isCi = false
        }

        /// Remove /refs/heads/ from the branch when it appears. Some CI's add this info.
        if let branchCopy = branch {
            if branchCopy.hasPrefix("/refs/heads/") {
                branch = String(branchCopy.dropFirst("/refs/heads/".count))
            } else if branchCopy.hasPrefix("/refs/") {
                branch = String(branchCopy.dropFirst("/refs/".count))
            }
        }

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

/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class CIEnvironmentValuesTests: XCTestCase {
    var testEnvironment = [String: String]()

    override func setUp() {
        CIEnvironmentValues.environment = [String: String]()
    }

    func setEnvVariables() {
        CIEnvironmentValues.environment = testEnvironment
    }

    func testTravisEnvironment() {
        testEnvironment["TRAVIS"] = "1"
        testEnvironment["TRAVIS_REPO_SLUG"] = "/test/repo"
        testEnvironment["TRAVIS_COMMIT"] = "37e376448b0ac9b7f54404"
        testEnvironment["TRAVIS_BUILD_DIR"] = "/build"
        testEnvironment["TRAVIS_BUILD_ID"] = "pipeline1"
        testEnvironment["TRAVIS_BUILD_NUMBER"] = "4345"
        testEnvironment["TRAVIS_BUILD_WEB_URL"] = "http://travis.com/build"
        testEnvironment["TRAVIS_JOB_WEB_URL"] = "http://travis.com/job"
        testEnvironment["TRAVIS_PULL_REQUEST_BRANCH"] = ""
        testEnvironment["TRAVIS_BRANCH"] = "develop"

        setEnvVariables()

        let ci = CIEnvironmentValues()

        XCTAssertTrue(ci.isCi)
        XCTAssertEqual(ci.provider!, "travis")
        XCTAssertEqual(ci.repository!, "/test/repo")
        XCTAssertEqual(ci.commit!, "37e376448b0ac9b7f54404")
        XCTAssertEqual(ci.sourceRoot!, "/build")
        XCTAssertEqual(ci.pipelineId!, "pipeline1")
        XCTAssertEqual(ci.pipelineNumber!, "4345")
        XCTAssertEqual(ci.pipelineURL!, "http://travis.com/build")
        XCTAssertEqual(ci.jobURL!, "http://travis.com/job")
        XCTAssertEqual(ci.branch!, "develop")
    }

    func testCircleCIEnvironment() {
        testEnvironment["CIRCLECI"] = "1"
        testEnvironment["CIRCLE_REPOSITORY_URL"] = "/test/repo"
        testEnvironment["CIRCLE_SHA1"] = "37e376448b0ac9b7f54404"
        testEnvironment["CIRCLE_WORKING_DIRECTORY"] = "/build"
        testEnvironment["CIRCLE_BUILD_NUM"] = "43"
        testEnvironment["CIRCLE_BUILD_URL"] = "http://circleci.com/build"
        testEnvironment["CIRCLE_BRANCH"] = "develop"

        setEnvVariables()

        let ci = CIEnvironmentValues()

        XCTAssertTrue(ci.isCi)
        XCTAssertEqual(ci.provider!, "circleci")
        XCTAssertEqual(ci.repository!, "/test/repo")
        XCTAssertEqual(ci.commit!, "37e376448b0ac9b7f54404")
        XCTAssertEqual(ci.sourceRoot!, "/build")
        XCTAssertEqual(ci.pipelineNumber!, "43")
        XCTAssertEqual(ci.pipelineURL!, "http://circleci.com/build")
        XCTAssertEqual(ci.branch!, "develop")
    }

    func testJenkinsEnvironment() {
        testEnvironment["JENKINS_URL"] = "http://jenkins.com/"
        testEnvironment["GIT_URL"] = "/test/repo"
        testEnvironment["GIT_COMMIT"] = "37e376448b0ac9b7f54404"
        testEnvironment["WORKSPACE"] = "/build"
        testEnvironment["BUILD_ID"] = "pipeline1"
        testEnvironment["BUILD_NUMBER"] = "45"
        testEnvironment["BUILD_URL"] = "http://jenkins.com/build"
        testEnvironment["JOB_URL"] = "http://jenkins.com/job"
        testEnvironment["GIT_BRANCH"] = "origin/develop"

        setEnvVariables()

        let ci = CIEnvironmentValues()

        XCTAssertTrue(ci.isCi)
        XCTAssertEqual(ci.provider!, "jenkins")
        XCTAssertEqual(ci.repository!, "/test/repo")
        XCTAssertEqual(ci.commit!, "37e376448b0ac9b7f54404")
        XCTAssertEqual(ci.sourceRoot!, "/build")
        XCTAssertEqual(ci.pipelineId!, "pipeline1")
        XCTAssertEqual(ci.pipelineNumber!, "45")
        XCTAssertEqual(ci.pipelineURL!, "http://jenkins.com/build")
        XCTAssertEqual(ci.jobURL!, "http://jenkins.com/job")
        XCTAssertEqual(ci.branch!, "develop")
    }

    func testGitlabCIEnvironment() {
        testEnvironment["GITLAB_CI"] = "1"
        testEnvironment["CI_REPOSITORY_URL"] = "/test/repo"
        testEnvironment["CI_COMMIT_SHA"] = "37e376448b0ac9b7f54404"
        testEnvironment["CI_PROJECT_DIR"] = "/build"
        testEnvironment["CI_PIPELINE_ID"] = "pipeline1"
        testEnvironment["CI_PIPELINE_IID"] = "4345"
        testEnvironment["CI_PIPELINE_URL"] = "http://travis.com/build"
        testEnvironment["CI_JOB_URL"] = "http://travis.com/job"
        testEnvironment["TRAVIS_PULL_REQUEST_BRANCH"] = ""
        testEnvironment["CI_COMMIT_BRANCH"] = "develop"
        testEnvironment["CI_COMMIT_TAG"] = "0.1.1"

        setEnvVariables()

        let ci = CIEnvironmentValues()

        XCTAssertTrue(ci.isCi)
        XCTAssertEqual(ci.provider!, "gitlab")
        XCTAssertEqual(ci.repository!, "/test/repo")
        XCTAssertEqual(ci.commit!, "37e376448b0ac9b7f54404")
        XCTAssertEqual(ci.sourceRoot!, "/build")
        XCTAssertEqual(ci.pipelineId!, "pipeline1")
        XCTAssertEqual(ci.pipelineNumber!, "4345")
        XCTAssertEqual(ci.pipelineURL!, "http://travis.com/build")
        XCTAssertEqual(ci.jobURL!, "http://travis.com/job")
        XCTAssertEqual(ci.branch!, "develop")
        XCTAssertEqual(ci.tag!, "0.1.1")
    }

    func testAppVeyorEnvironment() {
        testEnvironment["APPVEYOR"] = "1"
        testEnvironment["APPVEYOR_REPO_NAME"] = "/test/repo"
        testEnvironment["APPVEYOR_REPO_COMMIT"] = "37e376448b0ac9b7f54404"
        testEnvironment["APPVEYOR_BUILD_FOLDER"] = "/build"
        testEnvironment["APPVEYOR_BUILD_ID"] = "pipeline1"
        testEnvironment["APPVEYOR_BUILD_NUMBER"] = "4345"
        testEnvironment["APPVEYOR_PROJECT_SLUG"] = "projectSlug"
        testEnvironment["APPVEYOR_REPO_BRANCH"] = "develop"

        setEnvVariables()

        let ci = CIEnvironmentValues()

        XCTAssertTrue(ci.isCi)
        XCTAssertEqual(ci.provider!, "appveyor")
        XCTAssertEqual(ci.repository!, "/test/repo")
        XCTAssertEqual(ci.commit!, "37e376448b0ac9b7f54404")
        XCTAssertEqual(ci.sourceRoot!, "/build")
        XCTAssertEqual(ci.pipelineId!, "pipeline1")
        XCTAssertEqual(ci.pipelineNumber!, "4345")
        XCTAssertEqual(ci.pipelineURL!, "https://ci.appveyor.com/project/projectSlug/builds/pipeline1")
        XCTAssertEqual(ci.branch!, "develop")
    }

    func testAzureEnvironment() {
        testEnvironment["TF_BUILD"] = "1"
        testEnvironment["BUILD_SOURCESDIRECTORY"] = "/test/repo"
        testEnvironment["BUILD_SOURCEVERSION"] = "37e376448b0ac9b7f54404"
        testEnvironment["BUILD_BUILDID"] = "pipeline1"
        testEnvironment["BUILD_BUILDNUMBER"] = "4345"
        testEnvironment["SYSTEM_TEAMFOUNDATIONCOLLECTIONURI"] = "foundationCollection"
        testEnvironment["SYSTEM_TEAMPROJECT"] = "teamProject"
        testEnvironment["BUILD_REPOSITORY_URI"] = "/test/repo"
        testEnvironment["BUILD_SOURCEBRANCHNAME"] = "/refs/develop"

        setEnvVariables()

        let ci = CIEnvironmentValues()

        XCTAssertTrue(ci.isCi)
        XCTAssertEqual(ci.provider!, "azurepipelines")
        XCTAssertEqual(ci.repository!, "/test/repo")
        XCTAssertEqual(ci.commit!, "37e376448b0ac9b7f54404")
        XCTAssertEqual(ci.sourceRoot!, "/test/repo")
        XCTAssertEqual(ci.pipelineId!, "pipeline1")
        XCTAssertEqual(ci.pipelineNumber!, "4345")
        XCTAssertEqual(ci.pipelineURL!, "foundationCollection/teamProject/_build/results?buildId=pipeline1&_a=summary")
        XCTAssertEqual(ci.branch!, "develop")
    }

    func testBitbucketEnvironment() {
        testEnvironment["BITBUCKET_GIT_SSH_ORIGIN"] = "/test/repo"
        testEnvironment["BITBUCKET_COMMIT"] = "37e376448b0ac9b7f54404"
        testEnvironment["BITBUCKET_CLONE_DIR"] = "/build"
        testEnvironment["BITBUCKET_PIPELINE_UUID"] = "pipeline1"
        testEnvironment["BITBUCKET_BUILD_NUMBER"] = "4345"

        setEnvVariables()

        let ci = CIEnvironmentValues()

        XCTAssertTrue(ci.isCi)
        XCTAssertEqual(ci.provider!, "bitbucketpipelines")
        XCTAssertEqual(ci.repository!, "/test/repo")
        XCTAssertEqual(ci.commit!, "37e376448b0ac9b7f54404")
        XCTAssertEqual(ci.sourceRoot!, "/build")
        XCTAssertEqual(ci.pipelineId!, "pipeline1")
        XCTAssertEqual(ci.pipelineNumber!, "4345")
    }

    func testGithubEnvironment() {
        testEnvironment["GITHUB_REPOSITORY"] = "http://github.com/project"
        testEnvironment["GITHUB_SHA"] = "37e376448b0ac9b7f54404"
        testEnvironment["GITHUB_WORKSPACE"] = "/build"
        testEnvironment["GITHUB_RUN_ID"] = "pipeline1"
        testEnvironment["GITHUB_RUN_NUMBER"] = "4345"
        testEnvironment["TRAVIS_PULL_REQUEST_BRANCH"] = ""
        testEnvironment["GITHUB_REF"] = "/refs/heads/develop"

        setEnvVariables()

        let ci = CIEnvironmentValues()

        XCTAssertTrue(ci.isCi)
        XCTAssertEqual(ci.provider!, "github")
        XCTAssertEqual(ci.repository!, "http://github.com/project")
        XCTAssertEqual(ci.commit!, "37e376448b0ac9b7f54404")
        XCTAssertEqual(ci.sourceRoot!, "/build")
        XCTAssertEqual(ci.pipelineId!, "pipeline1")
        XCTAssertEqual(ci.pipelineNumber!, "4345")
        XCTAssertEqual(ci.pipelineURL!, "http://github.com/project/commit/37e376448b0ac9b7f54404/checks")
        XCTAssertEqual(ci.branch!, "develop")
    }

    func testTeamCityEnvironment() {
        testEnvironment["TEAMCITY_VERSION"] = "1"
        testEnvironment["BUILD_VCS_URL"] = "/test/repo"
        testEnvironment["BUILD_VCS_NUMBER"] = "37e376448b0ac9b7f54404"
        testEnvironment["BUILD_CHECKOUTDIR"] = "/build"
        testEnvironment["BUILD_ID"] = "pipeline1"
        testEnvironment["BUILD_NUMBER"] = "4345"
        testEnvironment["SERVER_URL"] = "http://teamcity.com"

        setEnvVariables()

        let ci = CIEnvironmentValues()

        XCTAssertTrue(ci.isCi)
        XCTAssertEqual(ci.provider!, "teamcity")
        XCTAssertEqual(ci.repository!, "/test/repo")
        XCTAssertEqual(ci.commit!, "37e376448b0ac9b7f54404")
        XCTAssertEqual(ci.sourceRoot!, "/build")
        XCTAssertEqual(ci.pipelineId!, "pipeline1")
        XCTAssertEqual(ci.pipelineNumber!, "4345")
        XCTAssertEqual(ci.pipelineURL!, "http://teamcity.com/viewLog.html?buildId=pipeline1")
    }

    func testBuildkiteEnvironment() {
        testEnvironment["BUILDKITE"] = "1"
        testEnvironment["BUILDKITE_REPO"] = "/test/repo"
        testEnvironment["BUILDKITE_COMMIT"] = "37e376448b0ac9b7f54404"
        testEnvironment["BUILDKITE_BUILD_CHECKOUT_PATH"] = "/build"
        testEnvironment["BUILDKITE_BUILD_ID"] = "pipeline1"
        testEnvironment["BUILDKITE_BUILD_NUMBER"] = "4345"
        testEnvironment["BUILDKITE_BUILD_URL"] = "http://buildkite.com/build"
        testEnvironment["BUILDKITE_BRANCH"] = "develop"

        setEnvVariables()

        let ci = CIEnvironmentValues()

        XCTAssertTrue(ci.isCi)
        XCTAssertEqual(ci.provider!, "buildkite")
        XCTAssertEqual(ci.repository!, "/test/repo")
        XCTAssertEqual(ci.commit!, "37e376448b0ac9b7f54404")
        XCTAssertEqual(ci.sourceRoot!, "/build")
        XCTAssertEqual(ci.pipelineId!, "pipeline1")
        XCTAssertEqual(ci.pipelineNumber!, "4345")
        XCTAssertEqual(ci.pipelineURL!, "http://buildkite.com/build")
        XCTAssertEqual(ci.branch!, "develop")
    }

    func testBitriseEnvironment() {
        testEnvironment["BITRISE_BUILD_NUMBER"] = "1"
        testEnvironment["GIT_REPOSITORY_URL"] = "/test/repo"
        testEnvironment["BITRISE_GIT_COMMIT"] = "37e376448b0ac9b7f54404"
        testEnvironment["BITRISE_SOURCE_DIR"] = "/build"
        testEnvironment["BITRISE_TRIGGERED_WORKFLOW_ID"] = "pipeline1"
        testEnvironment["BITRISE_BUILD_NUMBER"] = "4345"
        testEnvironment["BITRISE_APP_URL"] = "https://app.bitrise.io/app"
        testEnvironment["BITRISE_BUILD_URL"] = "https://app.bitrise.io/build"
        testEnvironment["TRAVIS_PULL_REQUEST_BRANCH"] = ""
        testEnvironment["BITRISE_GIT_BRANCH"] = "develop"
        testEnvironment["BITRISE_GIT_TAG"] = "0.0.1"

        setEnvVariables()

        let ci = CIEnvironmentValues()

        XCTAssertTrue(ci.isCi)
        XCTAssertEqual(ci.provider!, "bitrise")
        XCTAssertEqual(ci.repository!, "/test/repo")
        XCTAssertEqual(ci.commit!, "37e376448b0ac9b7f54404")
        XCTAssertEqual(ci.sourceRoot!, "/build")
        XCTAssertEqual(ci.pipelineId!, "pipeline1")
        XCTAssertEqual(ci.pipelineNumber!, "4345")
        XCTAssertEqual(ci.pipelineURL!, "https://app.bitrise.io/build")
        XCTAssertEqual(ci.jobURL!, "https://app.bitrise.io/app")
        XCTAssertEqual(ci.branch!, "develop")
        XCTAssertEqual(ci.tag!, "0.0.1")
    }

    func testAddsTagsToSpan() {
        testEnvironment["JENKINS_URL"] = "http://jenkins.com/"
        testEnvironment["GIT_URL"] = "/test/repo"
        testEnvironment["GIT_COMMIT"] = "37e376448b0ac9b7f54404"
        testEnvironment["WORKSPACE"] = "/build"
        testEnvironment["BUILD_ID"] = "pipeline1"
        testEnvironment["BUILD_NUMBER"] = "45"
        testEnvironment["BUILD_URL"] = "http://jenkins.com/build"
        testEnvironment["JOB_URL"] = "http://jenkins.com/job"
        testEnvironment["GIT_BRANCH"] = "origin/develop"

        setEnvVariables()

        let span: DDSpan = .mockWith(operationName: "operation")
        XCTAssertEqual(span.tags.count, 0)

        let ci = CIEnvironmentValues()
        ci.addTagsToSpan(span: span)

        XCTAssertEqual(span.tags.count, 10)

        XCTAssertEqual(span.tags["ci.provider.name"] as? String, "jenkins")
        XCTAssertEqual(span.tags["git.repository_url"] as? String, "/test/repo")
        XCTAssertEqual(span.tags["git.commit_sha"] as? String, "37e376448b0ac9b7f54404")
        XCTAssertEqual(span.tags["build.source_root"] as? String, "/build")
        XCTAssertEqual(span.tags["ci.pipeline.id"] as? String, "pipeline1")
        XCTAssertEqual(span.tags["ci.pipeline.number"] as? String, "45")
        XCTAssertEqual(span.tags["ci.pipeline.url"] as? String, "http://jenkins.com/build")
        XCTAssertEqual(span.tags["ci.job.url"] as? String, "http://jenkins.com/job")
        XCTAssertEqual(span.tags["git.branch"] as? String, "develop")
    }

    func testWhenNotRunningInCI_TagsAreNotAdded() {
        setEnvVariables()

        let span: DDSpan = .mockWith(operationName: "operation")
        XCTAssertEqual(span.tags.count, 0)

        let ci = CIEnvironmentValues()
        ci.addTagsToSpan(span: span)

        XCTAssertEqual(span.tags.count, 0)
    }
}

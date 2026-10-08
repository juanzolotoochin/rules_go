"""Tests the rules_go registration filter without fetching or running SDKs."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts", "unittest")
load("//go/private:sdk.bzl", "detect_host_platform", "go_toolchain_exec_platforms", "go_toolchains_build_file_content")

_SDKS = [
    ("_0000_linux_amd64_", "linux", "amd64", "linux_amd64", "remote", "1.27.1"),
    ("_0001_darwin_arm64_", "darwin", "arm64", "darwin_arm64", "remote", "1.27.1"),
    ("_0002_linux_arm64_", "linux", "arm64", "linux_arm64", "remote", "1.27.1"),
    ("_0003_darwin_amd64_", "darwin", "amd64", "darwin_amd64", "remote", "1.27.1"),
    ("_0004_windows_amd64_", "windows", "amd64", "windows_amd64", "remote", "1.27.1"),
    ("_0005_other_version_", "linux", "amd64", "other_version", "remote", "1.26.6"),
    ("_0006_host_", "", "", "host", "host", "1.27.1"),
]

def _ctx(goos = "linux", goarch = "x86_64"):
    return struct(os = struct(name = goos, arch = goarch))

def _render(requested, ctx, indexes = None, host_platform = ""):
    sdks = _SDKS if indexes == None else [_SDKS[i] for i in indexes]
    return go_toolchains_build_file_content(
        ctx,
        prefixes = [sdk[0] for sdk in sdks],
        geese = [sdk[1] for sdk in sdks],
        goarchs = [sdk[2] for sdk in sdks],
        sdk_repos = [sdk[3] for sdk in sdks],
        sdk_types = [sdk[4] for sdk in sdks],
        sdk_versions = [sdk[5] for sdk in sdks],
        exec_platforms = go_toolchain_exec_platforms(requested, "_".join(detect_host_platform(ctx))),
        host_platform = host_platform,
    )

def _disabled_impl(ctx):
    env = unittest.begin(ctx)
    asserts.equals(env, [], go_toolchain_exec_platforms("", "linux_amd64"))
    content = _render("", _ctx())
    for sdk in _SDKS:
        asserts.true(env, 'sdk_name = "{}"'.format(sdk[3]) in content)
    asserts.equals(env, content, _render("   ", _ctx()))
    return unittest.end(env)

def _linux_impl(ctx):
    env = unittest.begin(ctx)

    # Compare complete generated contents, not just candidate counts. The
    # original names, priorities and all compatible SDK versions must survive.
    asserts.equals(env, _render("", _ctx(), [0, 5, 6]), _render("linux_amd64", _ctx()))
    return unittest.end(env)

def _mac_arm_impl(ctx):
    env = unittest.begin(ctx)
    host = _ctx("mac os x", "aarch64")
    asserts.equals(env, _render("", host, [0, 1, 5, 6]), _render("linux_amd64", host))
    return unittest.end(env)

def _linux_arm_impl(ctx):
    env = unittest.begin(ctx)
    host = _ctx("linux", "aarch64")
    asserts.equals(env, _render("", host, [0, 2, 5, 6]), _render("linux_amd64", host))
    return unittest.end(env)

def _mac_amd_impl(ctx):
    env = unittest.begin(ctx)
    host = _ctx("mac os x", "x86_64")
    asserts.equals(env, _render("", host, [0, 3, 5, 6]), _render("linux_amd64", host))
    return unittest.end(env)

def _windows_impl(ctx):
    env = unittest.begin(ctx)
    host = _ctx("windows 11", "x86_64")
    asserts.equals(env, _render("", host, [0, 4, 5, 6]), _render("linux_amd64", host))
    return unittest.end(env)

def _multiple_executors_impl(ctx):
    env = unittest.begin(ctx)
    asserts.equals(
        env,
        ["darwin_arm64", "linux_amd64", "linux_arm64"],
        go_toolchain_exec_platforms(" linux_arm64, linux_amd64,linux_arm64 ", "darwin_arm64"),
    )
    host = _ctx("mac os x", "aarch64")
    asserts.equals(env, _render("", host, [0, 1, 2, 5, 6]), _render("linux_amd64,linux_arm64", host))
    return unittest.end(env)

def _explicit_host_impl(ctx):
    env = unittest.begin(ctx)

    # The module's host must be part of repository attributes, independently
    # of an allowlist shared by multiple hosts. Host SDKs use that explicit
    # identity rather than an untracked repository-evaluation host.
    mac = _ctx("mac os x", "aarch64")
    expected = _render("", mac, [6])
    actual = _render("", _ctx(), [6], host_platform = "darwin_arm64")
    asserts.equals(env, expected, actual)
    return unittest.end(env)

def _invalid_policy_impl(ctx):
    go_toolchain_exec_platforms(ctx.attr.value, "linux_amd64")
    return []

_invalid_policy = rule(
    implementation = _invalid_policy_impl,
    attrs = {"value": attr.string(mandatory = True)},
)

def _invalid_policy_test_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, "invalid RULES_GO_TOOLCHAIN_EXEC_PLATFORMS entry")
    return analysistest.end(env)

_disabled_test = unittest.make(_disabled_impl)
_linux_test = unittest.make(_linux_impl)
_mac_arm_test = unittest.make(_mac_arm_impl)
_linux_arm_test = unittest.make(_linux_arm_impl)
_mac_amd_test = unittest.make(_mac_amd_impl)
_windows_test = unittest.make(_windows_impl)
_multiple_executors_test = unittest.make(_multiple_executors_impl)
_explicit_host_test = unittest.make(_explicit_host_impl)
_invalid_policy_test = analysistest.make(_invalid_policy_test_impl, expect_failure = True)

def toolchain_exec_platform_test_suite():
    name = "toolchain_exec_platform_tests"
    visibility = ["//visibility:private"]
    tests = []
    for suffix, test_rule in [
        ("disabled", _disabled_test),
        ("linux", _linux_test),
        ("mac_arm", _mac_arm_test),
        ("mac_amd", _mac_amd_test),
        ("linux_arm", _linux_arm_test),
        ("windows", _windows_test),
        ("multiple_executors", _multiple_executors_test),
        ("explicit_host", _explicit_host_test),
    ]:
        test_name = name + "_" + suffix
        test_rule(name = test_name, visibility = visibility)
        tests.append(":" + test_name)
    for suffix, value in [
        ("unknown_os", "linuz_amd64"),
        ("unknown_arch", "linux_amd6"),
        ("empty_entry", "linux_amd64,"),
    ]:
        probe_name = name + "_" + suffix + "_probe"
        _invalid_policy(name = probe_name, value = value, tags = ["manual"])
        test_name = name + "_" + suffix
        _invalid_policy_test(
            name = test_name,
            target_under_test = ":" + probe_name,
            visibility = visibility,
        )
        tests.append(":" + test_name)
    native.test_suite(name = name, tests = tests, visibility = visibility)


# Copyright 2015 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@rules_java//java:defs.bzl", "java_binary", "java_import", "java_library")

def _groovy_jar_impl(ctx):
    """Creates a .jar file from Groovy sources. Users should rely on
    groovy_library instead of using this rule directly.
    """
    class_jar = ctx.outputs.class_jar
    build_output = class_jar.path + ".build_output"

    # Extract all transitive dependencies
    # TODO(bazel-team): get transitive dependencies from other groovy libraries
    all_deps = depset(
        ctx.files.deps,
        transitive = [
            dep[JavaInfo].transitive_runtime_deps
            for dep in ctx.attr.deps
            if JavaInfo in dep
        ],
    )

    # Set up the output directory and set JAVA_HOME
    cmd = "rm -rf %s\n" % build_output
    cmd += "mkdir -p %s\n" % build_output
    cmd += "export JAVA_HOME=%s\n" % ctx.attr._jdk[java_common.JavaRuntimeInfo].java_home

    # Set GROOVY_HOME by scanning through the groovy SDK to find the license file,
    # which should be at the root of the SDK. The name of the license file depends
    # changed with newer versions of groovy.
    for file in ctx.files._groovysdk:
        if file.basename == "CLI-LICENSE.txt" or file.basename == "LICENSE":
            cmd += "export GROOVY_HOME=%s\n" % file.dirname
            break

    # Compile all files in srcs with groovyc
    cmd += "$GROOVY_HOME/bin/groovyc %s -d %s %s\n" % (
        "-cp " + ":".join([dep.path for dep in all_deps.to_list()]) if len(all_deps.to_list()) != 0 else "",
        build_output,
        " ".join([src.path for src in ctx.files.srcs]),
    )

    # Discover all of the generated class files and write their paths to a file.
    # Run the paths through sed to trim out everything before the package root so
    # that the paths match how they should look in the jar file.
    cmd += "find %s -name '*.class' | sed 's:^%s/::' > %s/class_list\n" % (
        build_output,
        build_output,
        build_output,
    )

    # Create a jar file using the discovered paths
    cmd += "root=`pwd`\n"
    cmd += "cd %s; $root/%s Cc ../%s @class_list\n" % (
        build_output,
        ctx.executable._zipper.path,
        class_jar.basename,
    )
    cmd += "cd $root\n"

    # Clean up temporary output
    cmd += "rm -rf %s" % build_output

    # Execute the command
    ctx.actions.run_shell(
        inputs = (
            ctx.files.srcs +
            all_deps.to_list() + ctx.files._groovysdk + ctx.files._jdk
        ),
        tools = ctx.files._zipper,
        outputs = [class_jar],
        mnemonic = "Groovyc",
        command = "set -e;" + cmd,
        use_default_shell_env = True,
    )

_groovy_jar = rule(
    attrs = {
        "srcs": attr.label_list(
            allow_empty = False,
            allow_files = [".groovy"],
        ),
        "deps": attr.label_list(
            mandatory = False,
            allow_files = [".jar"],
        ),
        "_groovysdk": attr.label(
            default = Label("//external:groovy-sdk"),
        ),
        "_jdk": attr.label(
            default = Label("@bazel_tools//tools/jdk:current_java_runtime"),
        ),
        "_zipper": attr.label(
            default = Label("@bazel_tools//tools/zip:zipper"),
            executable = True,
            allow_single_file = True,
            cfg = "host",
        ),
    },
    outputs = {
        "class_jar": "lib%{name}.jar",
    },
    implementation = _groovy_jar_impl,
)

def groovy_library(name, srcs = [], testonly = 0, deps = [], **kwargs):
    """Rule analagous to java_library that accepts .groovy sources instead of
    .java sources. The result is wrapped in a java_import so that java rules may
    depend on it.
    """
    _groovy_jar(
        name = name + "-impl",
        srcs = srcs,
        testonly = testonly,
        deps = deps,
    )
    java_import(
        name = name,
        jars = [name + "-impl"],
        testonly = testonly,
        deps = deps,
        **kwargs
    )

def groovy_and_java_library(name, srcs = [], testonly = 0, deps = [], **kwargs):
    """Accepts .groovy and .java srcs to create a groovy_library and a
    java_library. The groovy_library will depend on the java_library, so the
    Groovy code may reference the Java code but not vice-versa.
    """
    groovy_deps = deps
    jars = []

    # Put all .java sources in a java_library
    java_srcs = [src for src in srcs if src.endswith(".java")]
    if java_srcs:
        java_library(
            name = name + "-java",
            srcs = java_srcs,
            testonly = testonly,
            deps = deps,
        )
        groovy_deps = depset(groovy_deps + [name + "-java"])
        jars += ["lib" + name + "-java.jar"]

    # Put all .groovy sources in a groovy_library depending on the java_library
    groovy_srcs = [src for src in srcs if src.endswith(".groovy")]
    if groovy_srcs:
        _groovy_jar(
            name = name + "-groovy",
            srcs = groovy_srcs,
            testonly = testonly,
            deps = groovy_deps,
        )
        jars += ["lib" + name + "-groovy.jar"]

    # Output a java_import combining both libraries
    java_import(
        name = name,
        jars = jars,
        testonly = testonly,
        deps = deps,
        **kwargs
    )

def groovy_binary(name, main_class, srcs = [], testonly = 0, deps = [], **kwargs):
    """Rule analagous to java_binary that accepts .groovy sources instead of .java
    sources.
    """
    all_deps = deps + ["//external:groovy"]
    if srcs:
        groovy_library(
            name = name + "-lib",
            srcs = srcs,
            testonly = testonly,
            deps = deps,
        )
        all_deps += [name + "-lib"]
    java_binary(
        name = name,
        main_class = main_class,
        runtime_deps = all_deps,
        testonly = testonly,
        **kwargs
    )

def path_to_class(path, project_path):
    if path.startswith(project_path):
        path = path[len(project_path):]

    if path.startswith("src/test/groovy/"):
        return path[len("src/test/groovy/"):path.index(".groovy")].replace("/", ".")
    elif path.startswith("src/test/java/"):
        return path[len("src/test/java/"):path.index(".groovy")].replace("/", ".")
    else:
        fail("groovy_test sources must be under src/test/java or src/test/groovy")

def runfiles_root(ctx):
    return "${TEST_SRCDIR}/%s" % ctx.workspace_name

def _java_bin(ctx):
    java_path = str(ctx.attr._jdk[java_common.JavaRuntimeInfo].java_home)

    if paths.is_absolute(java_path):
        javabin = java_path
    else:
        runfiles_root_var = runfiles_root(ctx)
        javabin = "%s/%s" % (runfiles_root_var, java_path)
    return javabin + "/bin/java"

def _groovy_test_impl(ctx):
    # Collect jars from the Groovy sdk
    groovy_sdk_jars = [
        file
        for file in ctx.files._groovysdk
        if file.basename.endswith(".jar")
    ]

    # Extract all transitive dependencies
    all_deps = depset(
        ctx.files.deps + ctx.files._implicit_deps + groovy_sdk_jars,
        transitive = [
            dep[JavaInfo].transitive_runtime_deps
            for dep in ctx.attr.deps
            if JavaInfo in dep
        ],
    )

    # Infer a class name from each src file
    java_bin = _java_bin(ctx)

    project_path = ctx.attr.generator_location[:ctx.attr.generator_location.index("BUILD:")]
    classes = [path_to_class(src.path, project_path) for src in ctx.files.srcs]
    
    # Write a file that executes JUnit on the inferred classes
    cmd = "%s %s -cp %s org.junit.runner.JUnitCore %s\n" % (
        java_bin,
        " ".join(ctx.attr.jvm_flags),
        ":".join([dep.short_path for dep in all_deps.to_list()]),
        " ".join(classes),
    )

    # Return all dependencies needed to run the tests
    ctx.actions.write(
        output = ctx.outputs.executable,
        content = cmd,
    )

    # Return all dependencies needed to run the tests
    return struct(
        runfiles = ctx.runfiles(files = all_deps.to_list() + ctx.files.data + ctx.files._jdk),
    )

_groovy_test = rule(
    attrs = {
        "srcs": attr.label_list(
            mandatory = True,
            allow_files = [".groovy"],
        ),
        "data": attr.label_list(allow_files = True),
        "jvm_flags": attr.string_list(),
        "deps": attr.label_list(allow_files = [".jar"]),
        "_groovysdk": attr.label(
            default = Label("//external:groovy-sdk"),
        ),
        "_implicit_deps": attr.label_list(default = [
            Label("//external:junit"),
        ]),
        "_jdk": attr.label(
            default = Label("@bazel_tools//tools/jdk:current_java_runtime"),
        ),
    },
    test = True,
    implementation = _groovy_test_impl,
)

def groovy_test(
        name,
        deps = [],
        srcs = [],
        data = [],
        resources = [],
        jvm_flags = [],
        size = "medium",
        tags = []):
    # Create an extra jar to hold the resource files if any were specified
    all_deps = deps
    if resources:
        java_library(
            name = name + "-resources",
            resources = resources,
            testonly = 1,
        )
        all_deps += [name + "-resources"]

    _groovy_test(
        name = name,
        size = size,
        tags = tags,
        srcs = srcs,
        deps = all_deps,
        data = data,
        jvm_flags = jvm_flags,
    )

def groovy_junit_test(
        name,
        tests,
        deps = [],
        groovy_srcs = [],
        java_srcs = [],
        data = [],
        resources = [],
        jvm_flags = [],
        size = "small",
        tags = []):
    groovy_lib_deps = deps + ["//external:junit"]
    test_deps = deps + ["//external:junit"]

    if len(tests) == 0:
        fail("Must provide at least one file in tests")

    # Put all Java sources into a Java library
    if java_srcs:
        java_library(
            name = name + "-javalib",
            srcs = java_srcs,
            testonly = 1,
            deps = deps + ["//external:junit"],
        )
        groovy_lib_deps += [name + "-javalib"]
        test_deps += [name + "-javalib"]

    # Put all tests and Groovy sources into a Groovy library
    groovy_library(
        name = name + "-groovylib",
        srcs = tests + groovy_srcs,
        testonly = 1,
        deps = groovy_lib_deps,
    )
    test_deps += [name + "-groovylib"]

    # Create a groovy test
    groovy_test(
        name = name,
        deps = test_deps,
        srcs = tests,
        data = data,
        resources = resources,
        jvm_flags = jvm_flags,
        size = size,
        tags = tags,
    )

def spock_test(
        name,
        specs,
        deps = [],
        groovy_srcs = [],
        java_srcs = [],
        data = [],
        resources = [],
        jvm_flags = [],
        size = "small",
        tags = [],
        include_external_deps = 1):
    groovy_lib_deps = deps + [
        "//external:junit",
        "//external:spock",
    ]

    test_deps = deps
    if include_external_deps:
        test_deps = deps + [
            "//external:junit",
            "//external:spock",
        ]

    if len(specs) == 0:
        fail("Must provide at least one file in specs")

    # Put all Java sources into a Java library
    if java_srcs:
        java_library(
            name = name + "-javalib",
            srcs = java_srcs,
            testonly = 1,
            deps = test_deps,
        )
        groovy_lib_deps += [name + "-javalib"]
        test_deps += [name + "-javalib"]

    # Put all specs and Groovy sources into a Groovy library
    groovy_library(
        name = name + "-groovylib",
        srcs = specs + groovy_srcs,
        testonly = 1,
        deps = groovy_lib_deps,
    )
    test_deps += [name + "-groovylib"]

    # Create a groovy test
    groovy_test(
        name = name,
        deps = test_deps,
        srcs = specs,
        data = data,
        resources = resources,
        jvm_flags = jvm_flags,
        size = size,
        tags = tags,
    )

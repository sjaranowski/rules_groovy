load("@io_bazel_rules_groovy//groovy:groovy.bzl", "groovy_library", "groovy_and_java_library")

groovy_library(
    name = "groovylib",
    srcs = glob(["*.groovy"]),
    visibility = ["//visibility:public"],
    deps = [
        ":javalib",
    ],
)

java_library(
    name = "javalib",
    srcs = glob(["*.java"]),
)

groovy_and_java_library(
    name = "groovyjavalib",
    srcs = glob(["*.groovy", "*.java"]),
)

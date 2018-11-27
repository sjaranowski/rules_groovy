workspace(name = "io_bazel_rules_groovy")

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
http_archive(
  name = "bazel_toolchains",
  urls = [
    "https://mirror.bazel.build/github.com/bazelbuild/bazel-toolchains/archive/bc0091adceaf4642192a8dcfc46e3ae3e4560ea7.tar.gz",
    "https://github.com/bazelbuild/bazel-toolchains/archive/bc0091adceaf4642192a8dcfc46e3ae3e4560ea7.tar.gz",
  ],
  strip_prefix = "bazel-toolchains-bc0091adceaf4642192a8dcfc46e3ae3e4560ea7",
  sha256 = "7e85a14821536bc24e04610d309002056f278113c6cc82f1059a609361812431",
)

load("//groovy:groovy.bzl", "groovy_repositories")
groovy_repositories()

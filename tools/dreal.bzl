# -*- python -*-
# Based on Drake's drake.bzl file,
# https://github.com/RobotLocomotion/drake/blob/master/tools/drake.bzl.

# The CXX_FLAGS will be enabled for all C++ rules in the project
# building with any compiler.
CXX_FLAGS = [
    "-Werror=all",
    "-Werror=ignored-qualifiers",
    "-Werror=overloaded-virtual",
    "-Werror=old-style-cast",
]

# The CLANG_FLAGS will be enabled for all C++ rules in the project when
# building with clang.
CLANG_FLAGS = CXX_FLAGS + [
    "-Werror=shadow",
    "-Werror=inconsistent-missing-override",
    "-Werror=sign-compare",
    "-Werror=return-stack-address",
    "-Werror=non-virtual-dtor",
]

# The GCC_FLAGS will be enabled for all C++ rules in the project when
# building with gcc.
GCC_FLAGS = CXX_FLAGS + [
    "-Werror=extra",
    "-Werror=return-local-addr",
    "-Werror=non-virtual-dtor",
    "-Werror=unused-but-set-parameter",
    "-Werror=logical-op",
]

# The GCC_CC_TEST_FLAGS will be enabled for all cc_test rules in the project
# when building with gcc.
GCC_CC_TEST_FLAGS = [
    "-Wno-unused-parameter",
]

def _platform_copts(rule_copts, cc_test = 0):
    """Returns both the rule_copts, and platform-specific copts.

    When cc_test=1, the GCC_CC_TEST_FLAGS will be added.  It should only be set
    to 1 from cc_test rules or rules that are boil down to cc_test rules.
    """
    extra_gcc_flags = []
    if cc_test:
        extra_gcc_flags = GCC_CC_TEST_FLAGS
    return select({
        "//tools:gcc4.9-linux": GCC_FLAGS + extra_gcc_flags + rule_copts,
        "//tools:gcc5-linux": GCC_FLAGS + extra_gcc_flags + rule_copts,
        "//tools:gcc6-linux": GCC_FLAGS + extra_gcc_flags + rule_copts,
        "//tools:clang3.9-linux": CLANG_FLAGS + rule_copts,
        "//tools:apple": CLANG_FLAGS + rule_copts,
        "//conditions:default": rule_copts,
    })

def _dsym_command(name):
    """Returns the command to produce .dSYM on OS X, or a no-op on Linux."""
    return select({
        "//tools:apple_debug":
            "dsymutil -f $(location :" + name + ") -o $@ 2> /dev/null",
        "//conditions:default": "touch $@",
    })

def _check_library_deps_blacklist(name, deps):
    """Report an error if a library should not use something from deps."""
    if not deps:
        return
    if type(deps) != 'list':
        # We can't handle select() yet.
        return
    for dep in deps:
        if dep.endswith(":main"):
            fail("The cc_library '" + name + "' must not depend on a :main " +
                 "function from a cc_library; only cc_binary program should " +
                 "have a main function")

def dreal_cc_library(
        name,
        hdrs = None,
        srcs = None,
        deps = None,
        copts = [],
        **kwargs):
    """Creates a rule to declare a C++ library.
    """
    _check_library_deps_blacklist(name, deps)
    native.cc_library(
        name = name,
        hdrs = hdrs,
        srcs = srcs,
        deps = deps,
        copts = _platform_copts(copts),
        **kwargs)

def dreal_cc_binary(
        name,
        hdrs = None,
        srcs = None,
        deps = None,
        copts = [],
        testonly = 0,
        add_test_rule = 0,
        test_rule_args = [],
        test_rule_size = None,
        **kwargs):
    """Creates a rule to declare a C++ binary.

    If you wish to create a smoke-test demonstrating that your binary runs
    without crashing, supply add_test_rule=1. Note that if you wish to do
    this, you should consider suppressing that urge, and instead writing real
    tests. The smoke-test will be named <name>_test. You may override cc_test
    defaults using test_rule_args=["-f", "--bar=42"] or test_rule_size="baz".
    """
    native.cc_binary(
        name = name,
        hdrs = hdrs,
        srcs = srcs,
        deps = deps,
        copts = _platform_copts(copts),
        testonly = testonly,
        **kwargs)

    # Also generate the OS X debug symbol file for this binary.
    native.genrule(
        name = name + "_dsym",
        srcs = [":" + name],
        outs = [name + ".dSYM"],
        output_to_bindir = 1,
        testonly = testonly,
        tags = ["dsym"],
        visibility = ["//visibility:private"],
        cmd = _dsym_command(name),
    )

    if add_test_rule:
        dreal_cc_test(
            name = name + "_test",
            hdrs = hdrs,
            srcs = srcs,
            deps = deps,
            copts = copts,
            size = test_rule_size,
            testonly = testonly,
            args = test_rule_args,
            **kwargs)

def dreal_cc_test(
        name,
        size = None,
        srcs = None,
        copts = [],
        disable_in_compilation_mode_dbg = False,
        **kwargs):
    """Creates a rule to declare a C++ unit test.  Note that for almost all
    cases, dreal_cc_googletest should be used, instead of this rule.

    By default, sets size="small" because that indicates a unit test.
    By default, sets name="test/${name}.cc" per Dreal's filename convention.

    If disable_in_compilation_mode_dbg is True, the srcs will be suppressed
    in debug-mode builds, so the test will trivially pass. This option should
    be used only rarely, and the reason should always be documented.
    """
    if size == None:
        size = "small"
    if srcs == None:
        srcs = ["test/%s.cc" % name]
    if disable_in_compilation_mode_dbg:
        # Remove the test declarations from the test in debug mode.
        # TODO(david-german-tri): Actually suppress the test rule.
        srcs = select({"//tools:debug": [], "//conditions:default": srcs})
    native.cc_test(
        name = name,
        size = size,
        srcs = srcs,
        copts = _platform_copts(copts, cc_test = 1),
        **kwargs)

    # Also generate the OS X debug symbol file for this test.
    native.genrule(
        name = name + "_dsym",
        srcs = [":" + name],
        outs = [name + ".dSYM"],
        output_to_bindir = 1,
        testonly = 1,
        tags = ["dsym"],
        visibility = ["//visibility:private"],
        cmd = _dsym_command(name),
    )

def dreal_cc_googletest(
        name,
        deps = None,
        use_default_main = True,
        **kwargs):
    """Creates a rule to declare a C++ unit test using googletest.  Always adds
    a deps= entry for googletest main (@gtest//:main).

    By default, sets size="small" because that indicates a unit test.
    By default, sets name="test/${name}.cc" per Dreal's filename convention.
    By default, sets use_default_main=True to use GTest's main, via
    @gtest//:main. Otherwise, it will depend on @gtest//:without_main.

    If disable_in_compilation_mode_dbg is True, the srcs will be suppressed
    in debug-mode builds, so the test will trivially pass. This option should
    be used only rarely, and the reason should always be documented.
    """
    if deps == None:
        deps = []
    if use_default_main:
        deps.append("@gtest//:main")
    else:
        deps.append("@gtest//:without_main")
    dreal_cc_test(
        name = name,
        deps = deps,
        **kwargs)

def smt2_test(
        name,
        **kwargs):
    """Create smt2 test."""
    smt2 = name + ".smt2"
    expected = smt2 + ".expected"
    data_files = native.glob([
        smt2 + "*",
    ])
    native.py_test(
        name = name,
        args = [
            "$(location //dreal:dreal)",
            "$(location %s)" % smt2,
            "$(location %s)" % expected,
        ],
        tags = ["smt2"],
        srcs = ["test.py"],
        data = [
            "//dreal:dreal",
        ] + data_files,
        main = "test.py",
        **kwargs)

def dr_test(
        name,
        **kwargs):
    """Create dr test."""
    dr = name + ".dr"
    expected = dr + ".expected"
    data_files = native.glob([
        dr + "*",
    ])
    native.py_test(
        name = name,
        args = [
            "$(location //dreal:dreal)",
            "$(location %s)" % dr,
            "$(location %s)" % expected,
        ],
        tags = ["dr"],
        srcs = ["test.py"],
        data = [
            "//dreal:dreal",
        ] + data_files,
        main = "test.py",
        **kwargs)

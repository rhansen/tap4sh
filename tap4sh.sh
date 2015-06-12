######################################################################
#
# Copyright (c) 2015, Richard Hansen <rhansen@rhansen.org>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
#   1. Redistributions of source code must retain the above copyright
#      notice, this list of conditions and the following disclaimer.
#
#   2. Redistributions in binary form must reproduce the above
#      copyright notice, this list of conditions and the following
#      disclaimer in the documentation and/or other materials provided
#      with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
# FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
# COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
# BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
# ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#
######################################################################

# tap4sh.sh: library of useful Test Anything Protocol functions for
# POSIX shells
#
# Available functions (see their definitions for usage details):
#
#   Testing functions:
#
#     * t4s_setup:  Prepare to run test cases (required)
#     * t4s_done:  No more tests (required)
#     * t4s_bailout:  Abort the test script
#     * t4s_testcase:  Run a script as a test case and output the
#       results in TAP format
#     * t4s_subtests:  Run a command that performs its own tests
#       and integrate the results
#
#   Helper functions:
#
#     * t4s_log, t4s_debug, t4s_warn, t4s_error:  Logging
#       functions
#     * t4s_fatal:  Log an error and exit non-zero
#     * t4s_try:  Run the given command and call t4s_fatal if it
#       returns non-zero
#     * t4s_usage_fatal:  Log an error, print the output of 'usage'
#       to standard error, and exit non-zero
#     * t4s_pecho:  Portable echo
#     * t4s_esc:  Wrap each argument suitable for 'eval'
#     * t4s_re_match:  Check if a string matches a regular
#       expression
#
# Example test script:
#
#     #!/bin/sh
#
#     d=${0%/*}
#     . "${d}"/tap4sh.sh
#
#     t4s_setup "$@"
#
#     t4s_testcase "setup" '
#         create_database
#     '
#
#     t4s_testcase "basic addition" '
#         [ $((1+1)) -eq 2 ]
#     '
#
#     t4s_testcase --xfail "waiting for mad scientist" "pigs fly" '
#         check_pigs_fly
#     '
#
#     t4s_testcase --skip "pigs don't yet fly" "pigs carry > 20lbs" '
#         launch_pig --weight 20lbs
#     '
#
#     my_subtests() {
#         t4s_setup "$@"
#         t4s_testcase "true returns 0" 'true'
#         t4s_testcase "false returns non-zero" '!false"
#         t4s_done
#     }
#
#     t4s_subtests my_subtests
#
#     t4s_done
#
# Release history:
#
#   v1.0, released 2015-06-12:
#     * initial release

t4s_usage() {
    cat <<EOF
Usage: $0 [options]

Options:

  -h, --help
    Display this usage message and exit.
EOF
}

## useful logging/error handling/string handling functions

t4s_log() { printf %s\\n "$*"; }
t4s_debug() { : t4s_log "DEBUG: $@" >&2; }
t4s_warn() { t4s_log "WARNING: $@" >&2; }
t4s_error() { t4s_log "ERROR: $@" >&2; }
t4s_fatal() { t4s_error "$@"; exit 1; }
t4s_usage_fatal() { t4s_error "$@"; t4s_usage >&2; exit 1; }
t4s_try() { "$@" || t4s_fatal "'$@' failed"; }
t4s_pecho() { printf %s\\n "$*"; }
t4s_esc() {
    t4s_esc_sep=
    for t4s_esc_x in "$@"; do
        t4s_esc_x_esc=$(
            t4s_pecho "${t4s_esc_x}" | sed -e "s/'/'\\\\''/g")
        printf %s "${t4s_esc_sep}'${t4s_esc_x_esc}'"
        t4s_esc_sep=' '
    done
    printf \\n
}
t4s_re_match() {
    # the 'x' ensures the operands are interpreted as strings.  the
    # regex is adjusted to match, and the regex is anchored at the
    # beginning, so this should not affect the results.
    t4s_re_match_str=x$1
    # expr calculates its results based on \1, so the parens around
    # the x ensure that a match is always reported, even when $2 has a
    # grouping where its \1 ends up being the empty string.
    t4s_re_match_re='\(x\)'$2
    t4s_debug "t4s_re_match: matching '${t4s_re_match_str}'" \
                 "against '${t4s_re_match_re}'"
    expr "${t4s_re_match_str}" : "${t4s_re_match_re}" >/dev/null
}

## setup and cleanup

# internal helper
#
# automatically called on exit to print the plan or bailout message
#
t4s_finalize() {
    if [ -n "${t4s_is_done+set}" ]; then
        t4s_pecho "1..${t4s_testnum}"
    elif [ -n "${t4s_do_bailout+set}" ]; then
        t4s_pecho "Bail out! ${t4s_bailout_msg}"
        exit 1
    fi
    exit "${t4s_ret}"
}

unset t4s_setup_done

# prepare to run tests
#
t4s_setup() {
    t4s_testnum=0
    t4s_ret=0
    unset t4s_is_done
    unset t4s_bailout_msg
    t4s_do_bailout=true
    t4s_setup_done=true
    trap 't4s_finalize' EXIT
    trap 'exit 1' HUP INT TERM

    ## parse arguments
    while [ "$#" -gt 0 ]; do
        t4s_arg=$1
        case $1 in
            --*'='*)
                shift
                set -- "${t4s_arg%%=*}" "${t4s_arg#*=}" "$@"
                continue;;
            -h|--help) unset t4s_do_bailout; t4s_usage; exit 0;;
            --) shift; break;;
            -*) t4s_usage_fatal "unknown option: '$1'";;
            *) break;;
        esac
        shift || t4s_usage_fatal "option '${t4s_arg}' requires a value"
    done
    [ "$#" -eq 0 ] || t4s_usage_fatal "unknown argument: '$1'"
}

unset t4s_in_test_script

# abort the test script
#
# This can be called from within the script passed to t4s_testcase().
#
t4s_bailout() {
    t4s_debug "t4s_bailout $@"
    if [ -n "${t4s_in_test_script+set}" ]; then
        t4s_debug "  in test script"
        t4s_pecho "$@" >&4
    else
        t4s_debug "  not in test script"
        t4s_bailout_msg="$*"
    fi
    exit 1
}

# run a test case and output the results in TAP format
#
# see t4s_usage() definition below
#
t4s_testcase() {
    t4s_testnum=$((t4s_testnum+1))

    t4s_debug "new test case: ${t4s_testnum}"

    [ -n "${t4s_setup_done+set}" ] || t4s_fatal "must run t4s_setup first"

    # back up stdout
    exec 3>&1
    t4s_to_eval=$(
        # back up new stdout, restore original stdout
        exec 4>&1 1>&3

        t4s_pecho "t4s_testcase_ret=0" >&4

        t4s_usage() {
            cat<<EOF
Usage: dotest [options] [--] <description> <test-script>

Run <test-script> in a subshell via 'eval'.  If the script returns
non-zero, report it as a failure, otherwise a pass.

Options:

  -h, --help
    Display this usage message and exit.

  -s <skip-msg>, --skip=<skip-msg>
    Skip this test with message <skip-msg>.  The <test-script> is not
    run.

  -x <todo-msg>, --xfail=<todo-msg>
    Expect <test-script> to fail, explained by <todo-msg>.

  -p, --pass
    Expect <test-script> to pass.  This is the default.

  --
    End of options.  Useful if <description> begins with '-'.

  <description>
    Short, single-line description of the test.

  <test-script>
    Test code to run in a subshell via 'eval'.
EOF
        }

        type=pass
        while [ "$#" -gt 0 ]; do
            arg=$1
            case $1 in
                --*'='*) shift; set -- "${arg%%=*}" "${arg#*=}" "$@"; continue;;
                -h|--help) t4s_usage; exit 0;;
                -s|--skip) type=skip; shift; msg=$1;;
                -x|--xfail) type=xfail; shift; msg=$1;;
                -p|--pass) type=pass;;
                --) shift; break;;
                -*) t4s_usage_fatal "unknown option: '$1'";;
                *) break;;
            esac
            shift || t4s_usage_fatal "unknown option: '$1'"
        done
        desc=$1; shift || t4s_usage_fatal "no description provided"
        script=$1; shift || t4s_usage_fatal "no test script provided"
        [ "$#" -eq 0 ] || t4s_usage_fatal "unknown argument: $1"

        if [ "${type}" = skip ]; then
            t4s_pecho "ok ${t4s_testnum} ${desc} # skip ${msg}"
            exit 0
        fi

        status=ok
        ret=0
        line="${t4s_testnum} ${desc}"
        [ "${type}" != xfail ] || line=${line}" # TODO ${msg}"

        bailout=$(
            exec 4>&1 1>&3
            t4s_in_test_script=true
            ret=$(
                exec 5>&1 1>&3
                {
                    (eval "${script}")
                    t4s_pecho "$?" >&5
                } | while IFS= read -r line; do
                    t4s_pecho "# ${line}"
                done
            )
            exit "${ret}"
        ) || {
            [ -z "${bailout}" ] || {
                t4s_debug "bailout=${bailout}"
                bailout_esc=$(t4s_esc "${bailout}")
                t4s_debug "bailout_esc=${bailout_esc}"
                t4s_pecho "t4s_bailout_msg=${bailout_esc}" >&4
                exit 0
            }
            status="not ok"
            ret=1
        }
        [ "${type}" != xfail ] || ret=$((1-ret))

        t4s_pecho "t4s_testcase_ret=${ret}" >&4
        t4s_pecho "${status} ${line}"

    ) || exit 1

    t4s_debug "t4s_to_eval="
    while IFS= read -r t4s_testcase_line; do
        t4s_debug "> ${t4s_testcase_line}"
    done <<EOF
${t4s_to_eval}
EOF
    t4s_try eval "${t4s_to_eval}"
    [ -z "${t4s_bailout_msg+set}" ] || t4s_bailout "${t4s_bailout_msg}"
    [ "${t4s_testcase_ret}" -eq 0 ] || t4s_ret=1
}

# internal helper
#
# split TAP output lines into their components
#
t4s_split_tap_lines() (
    q='\{0,1\}'
    p='\{1,\}'
    s='[[:space:]]'
    S='[^[:space:]]'
    sp='[[:space:]]'${p}
    status_re="^${s}*\\(\\(not${sp}\\)${q}ok\\)${s}*\\(${s}\\(.*\\)\\)${q}\$"
    testnum_re="^${s}*\\([[:digit:]]${p}\\)${s}*\\(${s}\\(.*\\)\\)${q}\$"
    skiptodo_pre="^\\([^#]*\\)#${s}*"
    skiptodo_post="${s}*\\(${s}\\(.*\\)\\)${q}\$"
    skip_re="${skiptodo_pre}[Ss][Kk][Ii][Pp]${S}*${skiptodo_post}"
    todo_re="${skiptodo_pre}[Tt][Oo][Dd][Oo]${skiptodo_post}"
    sed -e "#n
# back up the line in the hold space
h

# note the start of a new line
s/.*/t4s_tap_line=&/p
# restore the backup
g

# extract status
s/${status_re}/t4s_tap_status=\\1/p
t rmstat
# no status
b error

:rmstat
g
# remove the status
s/${status_re}/\\4/
t rmstat2
b error
:rmstat2
# save the line sans status
h

# extract the test number
s/${testnum_re}/t4s_tap_testnum=\\1/p
t rmnum
b

# remove the test number
:rmnum
g
s/${testnum_re}/\\3/
t rmnum2
b error
:rmnum2
h

# extract the skip message
:skip
g
s/${skip_re}/t4s_tap_skip=\\3/
t skip2
b todo
:skip2
s/${s}*\$//
p
b rmskip

# remove the skip message
:rmskip
g
s/${skip_re}/\\1/
t rmskip2
b error
:rmskip2
h
b desc

# extract the todo message
:todo
g
s/${todo_re}/t4s_tap_todo=\\3/
t todo2
b desc
:todo2
s/${s}*\$//
p
b rmtodo

# remove the todo message
:rmtodo
g
s/${todo_re}/\\1/
t rmtodo2
b error
:rmtodo2
h
b desc

# extract the description
:desc
g
s/${s}*\$//
s/.*/t4s_tap_desc=&/p
t desc2
b error
:desc2

b done
:error
s/.*/t4s_tap_error=&/p
:done
"
)

# internal helper
#
# call t4s_split_tap_lines on a single line and set an environment
# variable for each component
#
t4s_parse_tap_line() {
    unset t4s_tap_status
    unset t4s_tap_testnum
    unset t4s_tap_skip
    unset t4s_tap_todo
    unset t4s_tap_desc
    while IFS= read -r t4s_ptl_line; do
        case ${t4s_ptl_line} in
            t4s_tap_line=*) continue;;
            t4s_tap_error=*) return 1;;
            *=*)
                t4s_ptl_var=${t4s_ptl_line%%=*}
                t4s_ptl_val=${t4s_ptl_line#*=}
                t4s_ptl_cmd="${t4s_ptl_var}=\${t4s_ptl_val}"
                eval "${t4s_ptl_cmd}"
                ;;
            *) t4s_fatal "unexpected error parsing TAP line";;
        esac
    done <<EOF
$(t4s_pecho "$*" | t4s_split_tap_lines)
EOF
    (
        for v in status testnum desc skip todo; do
            eval "[ -z \"\${t4s_tap_${v}+set}\" ]" \
                || eval "t4s_debug \"t4s_tap_${v}=\${t4s_tap_${v}}\""
        done
    )
}

# run a command that performs its own tests and integrate the results
#
# see t4s_usage() below
#
t4s_subtests() {

    [ -n "${t4s_setup_done+set}" ] \
        || t4s_fatal "must run t4s_setup first"

    exec 3>&1
    unset t4s_subtests_bailout
    t4s_subtests_failed=0
    t4s_to_eval=$(
        exec 4>&1 1>&3

        t4s_usage() {
            cat<<EOF
Usage: t4s_subtests [options] [--] <command> [<args>...]

Run <command> (with its <args>) and interpret its standard output as
TAP output.  For each ok/not ok line, translate the test number to
continue the overall sequence and prefix the description.

For example:

    t4s_setup "$@"
    t4s_testcase "trivial test #1" 'true'
    my_subtests() {
        t4s_setup "$@"
        t4s_testcase "trivial test #1" 'false'
        t4s_done
    }
    t4s_subtests -p "my subtests: " my_subtests
    t4s_done

will output:

    ok 1 trivial test #1
    not ok 2 my subtests: trivial test #1
    1..2

Options:

  -h, --help
    Display this usage message and exit.

  -p <prefix>, --prefix=<prefix>
    Prefix each ok/not ok description with <prefix>.
    Default: <command> and <args> separated by spaces followed by ': '.

  --
    End of options.  Useful if <command> begins with '-'.

  <command>
    Utility or function to run.

  <args>...
    Arguments to pass to <command>.
EOF
        }

        pfx="$*: "
        while [ $# -gt 0 ]; do
            arg=$1
            case $1 in
                --*'='*) shift; set -- "${arg%%=*}" "${arg#*=}" "$@"; continue;;
                -h|--help) t4s_usage; exit 0;;
                -p|--prefix) shift; pfx=$1;;
                --) shift; break;;
                -*) t4s_usage_fatal "unknown option: '$1'";;
                *) break;;
            esac
            shift || t4s_usage_fatal "unknown option: '$1'"
        done

        t4s_debug "running t4s_subtests: $@"
        t4s_subtests_bailout() {
            t4s_debug "t4s_subtests bailing out: $@"
            t4s_pecho "t4s_subtests_bailout=$(t4s_esc "$*")" >&4
            exit 0
        }
        testnum_offset=${t4s_testnum}
        {
            unset t4s_setup_done
            "$@"
        } | {
            unset plan
            firstline=true
            unset plan_on_last
            t4s_testnum=0

            s='[[:space:]]'
            p='\{1,\}'
            sp=${s}${p}
            q='\{0,1\}'
            re_bailout="[Bb][Aa][Ii][Ll]${sp}[Oo][Uu][Tt]!"
            re_bailout_line="${s}*${re_bailout}${s}*\\(${s}.*\\)${q}\$"

            while IFS= read -r line; do
                t4s_debug "subtest line=${line}"
                if (
                    re="${s}*1\\.\\.[[:digit:]]${p}${s}*\$"
                    t4s_re_match "${line}" "${re}"
                ); then
                    t4s_debug "subtest: found plan"
                    if [ -n "${firstline+set}" ]; then
                        plan=${line}
                    elif [ -z "${plan+set}" ]; then
                        plan=${line}
                        plan_on_last=true
                    else
                        t4s_subtests_bailout "${pfx}multiple plan lines found"
                    fi
                elif (
                    re="${s}*\\(not${sp}\)${q}ok${s}*\\(${s}.*\\)${q}\$"
                    t4s_re_match "${line}" "${re}"
                ); then
                    t4s_parse_tap_line "${line}" \
                        || t4s_subtests_bailout "${pfx}failed to parse TAP line\
 ${line}"
                    [ -z "${plan_on_last+set}" ] || \
                        t4s_subtests_bailout "${pfx}plan in middle of test\
 results"
                    : "${t4s_tap_testnum=$((t4s_testnum+1))}"
                    [ "${t4s_tap_testnum}" -eq $((t4s_testnum+1)) ] || \
                        t4s_subtests_bailout "${pfx}out-of-order test numbers\
 (got ${t4s_tap_testnum} expected $((t4s_testnum+1)))"
                    [ "${t4s_tap_status}" = ok ] \
                        || [ -n "${t4s_tap_skip+set}" ] \
                        || t4s_pecho "t4s_subtests_failed=1" >&4
                    t4s_testnum=${t4s_tap_testnum}
                    out=${t4s_tap_status}\ $((t4s_testnum+testnum_offset))
                    t4s_pecho "t4s_testnum="$((t4s_testnum+testnum_offset)) >&4
                    out=${out}" ${pfx}${t4s_tap_desc}"
                    out=${out}${t4s_tap_todo+ \# TODO ${t4s_tap_todo}}
                    out=${out}${t4s_tap_skip+ \# skip ${t4s_tap_skip}}
                    t4s_pecho "${out}"
                elif t4s_re_match "${line}" "${re_bailout_line}"; then
                    msg=$(expr x"${line}" : "x${re_bailout_line}") || true
                    # remove matching leading whitespace
                    msg=${msg#?}
                    t4s_debug "t4s_subtests: bailout line: ${msg}"
                    t4s_subtests_bailout "${msg}"
                else
                    t4s_debug "t4s_subtests: misc line: ${line}"
                    t4s_pecho "${line}"
                fi
                unset firstline
            done
            t4s_debug "t4s_subtests: done parsing subtest output"
            [ -n "${plan+set}" ] || t4s_subtests_bailout "${pfx}no TAP plan"
            plantests=${plan#1..}
            [ "${plantests}" -eq "${t4s_testnum}" ] \
                || t4s_subtests_bailout "${pfx}test cases seen doesn't match\
 plan"
        } || exit 1
        t4s_debug "t4s_subtests: leaving subshell"
    ) || { t4s_debug "t4s_subtests: subshell exited non-zero"; exit 1; }
    t4s_debug "t4s_subtests t4s_to_eval="
    while IFS= read -r t4s_subtests_line; do
        t4s_debug "> ${t4s_subtests_line}"
    done <<EOF
${t4s_to_eval}
EOF
    t4s_try eval "${t4s_to_eval}"
    [ -z "${t4s_subtests_bailout+set}" ] \
        || t4s_bailout "${t4s_subtests_bailout}"
    [ "${t4s_subtests_failed}" -eq 0 ] || t4s_ret=1
}

t4s_done() {
    t4s_is_done=true
    [ "${t4s_ret}" -eq 0 ] || exit "${t4s_ret}"
}
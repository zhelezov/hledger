# shellcheck disable=2034

# Completion script for hledger.
# Created using a Makefile and real hledger.

# This script is sourced by an interactive shell, so do NOT do things like
# 'set -o pipefail' or mangle the global environment in any other way!
# That said, we *do* remove colon (:) from COMP_WORDBREAKS which impacts
# the rest of the session and completion for other programs.

_hledger_completion_function() {
    local cur prev words cword
    _init_completion -n : || return 0

    # Current treatment for special characters:
    # - exclude colon (:) from COMP_WORDBREAKS
    # - option processing assumes that `=` is in COMP_WORDBREAKS
    # - use compopt -o filenames selectively to escape the rest
    COMP_WORDBREAKS=${COMP_WORDBREAKS//:}
    case $COMP_WORDBREAKS in
        *=*) : ;;
        *)   COMP_WORDBREAKS=$COMP_WORDBREAKS= ;;
    esac

    local subcommand
    local i
    for ((i=1; i<${#words[@]}; i++)); do
        subcommand=${words[i]}
        if ! grep -Fxqe "$subcommand" <<< "$_hledger_complist_commands"; then
            subcommand=
            continue
        fi
        # There could be other commands begining with $subcommand, e.g.:
        # $subcommand == reg --> register, register-match,
        # $subcommand == bal --> balance, balancesheet, balancesheetequity, etc.
        # Do not ignore them!
        if ((i == cword)); then
            _hledger_compreply "$(
                _hledger_compgen "$_hledger_complist_commands"
            )"
            return 0
        fi
        break
    done

    # Option argument completion
    _hledger_compreply_optarg && return

    if [[ -z $subcommand ]]; then
        if [[ $cur == -* ]]; then
            _hledger_compreply "$(
                _hledger_compgen "$_hledger_complist_generic_options"
            )"
            # Suspend space on completion of long options requiring an argument
            [[ ${COMPREPLY[0]} == --*= ]] && compopt -o nospace
        else
            _hledger_compreply "$(
                _hledger_compgen "$_hledger_complist_commands"
            )"
        fi

        return 0
    fi

    if [[ $cur == -* ]]; then
        local subcommandOptions
        # Replace dashes with underscores and use indirect expansion
        subcommandOptions=_hledger_complist_options_${subcommand//-/_}
        _hledger_compreply "$(_hledger_compgen "${!subcommandOptions}")"

        # Suspend space on completion of long options requiring an argument
        [[ ${COMPREPLY[0]} == --*= ]] && compopt -o nospace

        return 0
    fi

    # Set this from here on because queries tend to have lots of special chars
    # TODO: better handling of special characters
    compopt -o filenames

    # Query completion
    _hledger_compreply_query && return

    # Subcommand specific
    case $subcommand in
        help)
            compopt -o nosort +o filenames
            _hledger_compreply "$(
                compgen -W "$(hledger help | tail -n 1)" -- "$cur"
            )"
            return 0
            ;;
        # These do not expect or support any query arguments
        commodities|check-dupes|files|import|print-unique|test)
            return 0
            ;;
    esac

    # Offer query filters and accounts for the rest
    _hledger_compreply "$(_hledger_compgen "$_hledger_complist_query_filters")"
    if [[ -z $cur ]]; then
        _hledger_compreply_append "$(
            _hledger_compgen "$(_hledger accounts --flat --depth 1)"
        )"
    else
        _hledger_compreply_append "$(
            _hledger_compgen "$(_hledger accounts --flat)"
        )"
    fi

    # Suspend space on completion of query prefix
    # Do not sort, keep accounts and query filters grouped separately
    [[ ${COMPREPLY[0]} == *: ]] && compopt -o nospace
    compopt -o nosort

    return 0
}

_hledger_extension_completion_function() {
    # Pretend that hledger is called with given extension
    # as first argument and call main completion function
    COMP_WORDS=("hledger" "${1#*-}" "${COMP_WORDS[@]:1}")
    COMP_CWORD=$((COMP_CWORD + 1))
    _hledger_completion_function "hledger" "${@:1}"
}

# Register completion function for hledger:
complete -F _hledger_completion_function hledger

# Register completion functions for hledger extensions:
complete -F _hledger_extension_completion_function hledger-ui
complete -F _hledger_extension_completion_function hledger-web

# Helpers

# Comment out when done
_hledger_debug() {
    ((HLEDGER_DEBUG)) || return 0
    local var vars=(words)
    (($#)) && vars=("$@")
    for var in "${vars[@]}"; do
        printf '\ndebug: %s\n' "$(declare -p "$var")" >&2
    done
}

# Stolen from bash-completion
# This function quotes the argument in a way so that readline dequoting
# results in the original argument.  This is necessary for at least
# `compgen' which requires its arguments quoted/escaped:
_hledger_quote_by_ref()
{
    printf -v "$2" %q "$1"

    # If result becomes quoted like this: $'string', re-evaluate in order to
    # drop the additional quoting.  See also: http://www.mail-archive.com/
    # bash-completion-devel@lists.alioth.debian.org/msg01942.html
    [[ ${!2} == \$* ]] && eval "$2=${!2}"
}

# Set the value of COMPREPLY from newline delimited completion candidates
_hledger_compreply() {
    local IFS=$'\n'
    # shellcheck disable=2206
    COMPREPLY=($1)
}

# Append the value of COMPREPLY from newline delimited completion candidates
_hledger_compreply_append() {
    local IFS=$'\n'
    # shellcheck disable=2206
    COMPREPLY+=($1)
}

# Generate input suitable for _hledger_compreply() from newline delimited
# completion candidates. It doesn't seem there is a way to feed a literal
# word list to compgen -- it will eat your quotes, drink your booze and...
# Completion candidates are quoted accordingly first and then we leave it to
# compgen to deal with readline.
#
# Arguments:
# $1: a newline separated list with completion cadidates
# $2: (optional) a prefix string to add to generated completions
# $3: (optional) a word to match instead of $cur, the default.
# If $match is null and $prefix is defined the match is done against $cur
# stripped of $prefix. If both $prefix and $match are null we match against
# $cur and no prefix is added to completions.
_hledger_compgen() {
    local complist=$1
    local prefix=$2
    local match=$3
    local quoted=()
    local word
    local i=0

    while IFS= read -r word; do
        _hledger_quote_by_ref "$word" word
        quoted[i++]=$word
    done <<< "$complist"

    if (($# < 3)); then
        match=${cur:${#prefix}}
    fi

    local IFS=$'\n'
    compgen -P "$prefix" -W "${quoted[*]}" -- "$match"
}

# Try required option argument completion. Set COMPREPLY and return 0 on
# success, 1 if option doesn't require an argument or out of context
_hledger_compreply_optarg() {
    local optionIndex=$((cword - 1))
    local match=$cur
    local wordlist

    # Match the empty string on --file=<TAB>, not the equal sign itself
    if [[ $cur == = ]]; then
        match=""
    # Once input is present, cword is incremented so we compensate
    elif [[ $prev == = ]]; then
        optionIndex=$((cword - 2))
    fi

    [[ ${words[optionIndex]} == -* ]] || return

    case ${words[optionIndex]} in
        --alias)
            compopt -o nospace -o filenames
            _hledger_compreply "$(
                _hledger_compgen "$(_hledger accounts --flat)" "" "$match"
            )"
            ;;
        -f|--file|--rules-file|-o|--output-file)
            compopt -o filenames
            _hledger_compreply "$(compgen -f -- "$match")"
            ;;
        --pivot)
            compopt -o nosort
            wordlist="code description note payee"
            _hledger_compreply "$(compgen -W "$wordlist" -- "$match")"
            _hledger_compreply_append "$(
                _hledger_compgen "$(_hledger tags)" "" "$match"
            )"
            ;;
        --value)
            wordlist="cost then end now"
            _hledger_compreply "$(compgen -W "$wordlist" -- "$match")"
            ;;
        -X|--exchange)
            _hledger_compreply "$(
                _hledger_compgen "$(_hledger commodities)" "" "$match"
            )"
            ;;
        --color|--colour)
            compopt -o nosort
            wordlist="auto always yes never no"
            _hledger_compreply "$(compgen -W "$wordlist" -- "$match")"
            ;;
        -O|--output-format)
            wordlist="txt csv json sql"
            _hledger_compreply "$(compgen -W "$wordlist" -- "$match")"
            ;;
        --close-acct|--open-acct)
            compopt -o filenames
            _hledger_compreply "$(
                _hledger_compgen "$(_hledger accounts --flat)" "" "$match"
            )"
            ;;
        --debug)
            wordlist="{1..9}"
            _hledger_compreply "$(compgen -W "$wordlist" -- "$match")"
            ;;
        # Argument required, but no handler (yet)
        -b|--begin|-e|--end|-p|--period|--depth|--drop)
            _hledger_compreply ""
            ;;
        *)
            return 1
            ;;
    esac

    return 0
}

# Query filter completion through introspection
_hledger_compreply_query() {
    [[ $cur =~ .: ]] || return
    local query=${cur%%:*}:
    local match=${cur#*:}
    grep -Fxqe "$query" <<< "$_hledger_complist_query_filters" || return

    local hledgerArgs=()
    case $query in
        acct:)
            if (( ${#match} )); then
                hledgerArgs=(accounts --flat)
            else
                hledgerArgs=(accounts --flat --depth 1)
            fi
            ;;
        code:)  hledgerArgs=(codes) ;;
        cur:)   hledgerArgs=(commodities) ;;
        desc:)  hledgerArgs=(descriptions) ;;
        note:)  hledgerArgs=(notes) ;;
        payee:) hledgerArgs=(payees) ;;
        tag:)   hledgerArgs=(tags) ;;
        *)
            local wordlist
            case $query in
                amt:)    wordlist="< <= > >=" ;;
                real:)   wordlist="\  0" ;;
                status:) wordlist="\  * !" ;;
                *)       return 1 ;;
            esac
            _hledger_compreply "$(
                compgen -P "$query" -W "$wordlist" -- "$match"
            )"
            return 0
            ;;
    esac

    _hledger_compreply "$(
        _hledger_compgen "$(_hledger "${hledgerArgs[@]}")" "$query"
    )"

    return 0
}

# Parse the command line so far and fill the array $optarg with the arguments to
# given options. $optarg should be declared by the caller
_hledger_optarg() {
    local options=("$@")
    local i j offset
    optarg=()

    # hledger balance --file ~/ledger _
    # 0       1       2      3        4
    for ((i=1; i < ${#words[@]} - 2; i++)); do
        offset=0
        for j in "${!options[@]}"; do
            if [[ ${words[i]} == "${options[j]}" ]]; then
                if [[ ${words[i+1]} == '=' ]]; then
                    offset=2
                else
                    offset=1
                fi
                # Pass it through compgen to unescape it
                optarg+=("$(compgen -W "${words[i + offset]}")")
            fi
        done
        ((i += offset))
    done
}

# Get ledger file from -f --file arguments from COMP_WORDS and pass it to the
# 'hledger' call. Note that --rules-file - if present - must also be passed!
# Multiple files are allowed so pass them all in the order of appearance.
_hledger() {
    local hledgerArgs=("$@")
    local file
    local -a optarg

    _hledger_optarg -f --file
    for file in "${optarg[@]}"; do
        [[ -f $file ]] && hledgerArgs+=(--file "$file")
    done

    _hledger_optarg --rules-file
    for file in "${optarg[@]}"; do
        [[ -f $file ]] && hledgerArgs+=(--rules-file "$file")
    done

    # Discard errors. Is there a way to validate files before using them?
    hledger "${hledgerArgs[@]}" 2>/dev/null
}

# Include lists of commands and options generated by the Makefile using the
# m4 macro processor.
# Included files must have exactly one newline at EOF to prevent weired errors.

read -r -d "" _hledger_complist_commands <<TEXT
accounts
activity
add
areg
aregister
bal
balance
balancesheet
balancesheetequity
bs
bse
cashflow
cf
check-dates
check-dupes
close
codes
commodities
descriptions
diff
equity
files
help
import
incomestatement
is
notes
payees
prices
print
print-unique
reg
register
register-match
rewrite
roi
stats
tags
test
txns
ui
web
api
TEXT

read -r -d "" _hledger_complist_query_filters <<TEXT
acct:
amt:
code:
cur:
date:
date2:
depth:
desc:
inacct:
not:
note:
payee:
real:
status:
tag:
TEXT

read -r -d "" _hledger_complist_generic_options <<TEXT
--alias=
--anon
--auto
--begin=
--cleared
--color=
--cost
--daily
--date2
--debug=
--depth=
--empty
--end=
--exchange=
--file=
--forecast
--help
--ignore-assertions
--infer-value
--market
--monthly
--pending
--period=
--pivot=
--quarterly
--real
--rules-file=
--unmarked
--value=
--version
--weekly
--yearly
TEXT

# Dashes are replaced by m4 with underscores to form valid identifiers
# Referenced by indirect expansion of $subcommandOptions

read -r -d "" _hledger_complist_options_accounts <<TEXT
--alias=
--anon
--auto
--begin=
--cleared
--color=
--cost
--daily
--date2
--debug=
--declared
--depth=
--drop=
--empty
--end=
--exchange=
--file=
--flat
--forecast
--help
--ignore-assertions
--infer-value
--market
--monthly
--pending
--period=
--pivot=
--quarterly
--real
--rules-file=
--tree
--unmarked
--used
--value=
--version
--weekly
--yearly
TEXT

read -r -d "" _hledger_complist_options_activity <<TEXT
--alias=
--anon
--auto
--begin=
--cleared
--color=
--cost
--daily
--date2
--debug=
--depth=
--empty
--end=
--exchange=
--file=
--forecast
--help
--ignore-assertions
--infer-value
--market
--monthly
--pending
--period=
--pivot=
--quarterly
--real
--rules-file=
--unmarked
--value=
--version
--weekly
--yearly
TEXT

read -r -d "" _hledger_complist_options_add <<TEXT
--alias=
--anon
--debug=
--file=
--help
--ignore-assertions
--no-new-accounts
--pivot=
--rules-file=
--version
TEXT

read -r -d "" _hledger_complist_options_areg <<TEXT
--alias=
--anon
--auto
--begin=
--cleared
--color=
--cost
--daily
--date2
--debug=
--depth=
--empty
--end=
--exchange=
--file=
--forecast
--help
--ignore-assertions
--infer-value
--market
--monthly
--no-elide
--output-file=
--output-format=
--pending
--period=
--pivot=
--quarterly
--real
--rules-file=
--txn-dates
--unmarked
--value=
--version
--weekly
--width=
--yearly
TEXT

read -r -d "" _hledger_complist_options_aregister <<TEXT
--alias=
--anon
--auto
--begin=
--cleared
--color=
--cost
--daily
--date2
--debug=
--depth=
--empty
--end=
--exchange=
--file=
--forecast
--help
--ignore-assertions
--infer-value
--market
--monthly
--no-elide
--output-file=
--output-format=
--pending
--period=
--pivot=
--quarterly
--real
--rules-file=
--txn-dates
--unmarked
--value=
--version
--weekly
--width=
--yearly
TEXT

read -r -d "" _hledger_complist_options_bal <<TEXT
--alias=
--anon
--auto
--average
--begin=
--budget
--change
--cleared
--color=
--cost
--cumulative
--daily
--date2
--debug=
--depth=
--drop=
--empty
--end=
--exchange=
--file=
--flat
--forecast
--format=
--help
--historical
--ignore-assertions
--infer-value
--invert
--market
--monthly
--no-elide
--no-total
--output-file=
--output-format=
--pending
--percent
--period=
--pivot=
--pretty-tables
--quarterly
--real
--row-total
--rules-file=
--sort-amount
--transpose
--tree
--unmarked
--value=
--version
--weekly
--yearly
TEXT

read -r -d "" _hledger_complist_options_balance <<TEXT
--alias=
--anon
--auto
--average
--begin=
--budget
--change
--cleared
--color=
--cost
--cumulative
--daily
--date2
--debug=
--depth=
--drop=
--empty
--end=
--exchange=
--file=
--flat
--forecast
--format=
--help
--historical
--ignore-assertions
--infer-value
--invert
--market
--monthly
--no-elide
--no-total
--output-file=
--output-format=
--pending
--percent
--period=
--pivot=
--pretty-tables
--quarterly
--real
--row-total
--rules-file=
--sort-amount
--transpose
--tree
--unmarked
--value=
--version
--weekly
--yearly
TEXT

read -r -d "" _hledger_complist_options_balancesheet <<TEXT
--alias=
--anon
--auto
--average
--begin=
--change
--cleared
--color=
--cost
--cumulative
--daily
--date2
--debug=
--depth=
--drop=
--empty
--end=
--exchange=
--file=
--flat
--forecast
--format=
--help
--historical
--ignore-assertions
--infer-value
--market
--monthly
--no-elide
--no-total
--output-file=
--output-format=
--pending
--percent
--period=
--pivot=
--pretty-tables
--quarterly
--real
--row-total
--rules-file=
--sort-amount
--tree
--unmarked
--value=
--version
--weekly
--yearly
TEXT

read -r -d "" _hledger_complist_options_balancesheetequity <<TEXT
--alias=
--anon
--auto
--average
--begin=
--change
--cleared
--color=
--cost
--cumulative
--daily
--date2
--debug=
--depth=
--drop=
--empty
--end=
--exchange=
--file=
--flat
--forecast
--format=
--help
--historical
--ignore-assertions
--infer-value
--market
--monthly
--no-elide
--no-total
--output-file=
--output-format=
--pending
--percent
--period=
--pivot=
--pretty-tables
--quarterly
--real
--row-total
--rules-file=
--sort-amount
--tree
--unmarked
--value=
--version
--weekly
--yearly
TEXT

read -r -d "" _hledger_complist_options_bs <<TEXT
--alias=
--anon
--auto
--average
--begin=
--change
--cleared
--color=
--cost
--cumulative
--daily
--date2
--debug=
--depth=
--drop=
--empty
--end=
--exchange=
--file=
--flat
--forecast
--format=
--help
--historical
--ignore-assertions
--infer-value
--market
--monthly
--no-elide
--no-total
--output-file=
--output-format=
--pending
--percent
--period=
--pivot=
--pretty-tables
--quarterly
--real
--row-total
--rules-file=
--sort-amount
--tree
--unmarked
--value=
--version
--weekly
--yearly
TEXT

read -r -d "" _hledger_complist_options_bse <<TEXT
--alias=
--anon
--auto
--average
--begin=
--change
--cleared
--color=
--cost
--cumulative
--daily
--date2
--debug=
--depth=
--drop=
--empty
--end=
--exchange=
--file=
--flat
--forecast
--format=
--help
--historical
--ignore-assertions
--infer-value
--market
--monthly
--no-elide
--no-total
--output-file=
--output-format=
--pending
--percent
--period=
--pivot=
--pretty-tables
--quarterly
--real
--row-total
--rules-file=
--sort-amount
--tree
--unmarked
--value=
--version
--weekly
--yearly
TEXT

read -r -d "" _hledger_complist_options_cashflow <<TEXT
--alias=
--anon
--auto
--average
--begin=
--change
--cleared
--color=
--cost
--cumulative
--daily
--date2
--debug=
--depth=
--drop=
--empty
--end=
--exchange=
--file=
--flat
--forecast
--format=
--help
--historical
--ignore-assertions
--infer-value
--market
--monthly
--no-elide
--no-total
--output-file=
--output-format=
--pending
--percent
--period=
--pivot=
--pretty-tables
--quarterly
--real
--row-total
--rules-file=
--sort-amount
--tree
--unmarked
--value=
--version
--weekly
--yearly
TEXT

read -r -d "" _hledger_complist_options_cf <<TEXT
--alias=
--anon
--auto
--average
--begin=
--change
--cleared
--color=
--cost
--cumulative
--daily
--date2
--debug=
--depth=
--drop=
--empty
--end=
--exchange=
--file=
--flat
--forecast
--format=
--help
--historical
--ignore-assertions
--infer-value
--market
--monthly
--no-elide
--no-total
--output-file=
--output-format=
--pending
--percent
--period=
--pivot=
--pretty-tables
--quarterly
--real
--row-total
--rules-file=
--sort-amount
--tree
--unmarked
--value=
--version
--weekly
--yearly
TEXT

read -r -d "" _hledger_complist_options_check_dates <<TEXT
--alias=
--anon
--auto
--begin=
--cleared
--color=
--cost
--daily
--date2
--debug=
--depth=
--empty
--end=
--exchange=
--file=
--forecast
--help
--ignore-assertions
--infer-value
--market
--monthly
--pending
--period=
--pivot=
--quarterly
--real
--rules-file=
--strict
--unmarked
--value=
--version
--weekly
--yearly
TEXT

read -r -d "" _hledger_complist_options_check_dupes <<TEXT
--alias=
--anon
--auto
--begin=
--cleared
--color=
--cost
--daily
--date2
--debug=
--depth=
--empty
--end=
--exchange=
--file=
--forecast
--help
--ignore-assertions
--infer-value
--market
--monthly
--pending
--period=
--pivot=
--quarterly
--real
--rules-file=
--unmarked
--value=
--version
--weekly
--yearly
TEXT

read -r -d "" _hledger_complist_options_close <<TEXT
--alias=
--anon
--auto
--begin=
--cleared
--close
--close-acct=
--close-desc=
--color=
--cost
--daily
--date2
--debug=
--depth=
--empty
--end=
--exchange=
--explicit
--file=
--forecast
--help
--ignore-assertions
--infer-value
--interleaved
--market
--monthly
--open
--open-acct=
--open-desc=
--pending
--period=
--pivot=
--quarterly
--real
--rules-file=
--show-costs
--unmarked
--value=
--version
--weekly
--yearly
TEXT

read -r -d "" _hledger_complist_options_codes <<TEXT
--alias=
--anon
--auto
--begin=
--cleared
--color=
--cost
--daily
--date2
--debug=
--depth=
--empty
--end=
--exchange=
--file=
--forecast
--help
--ignore-assertions
--infer-value
--market
--monthly
--pending
--period=
--pivot=
--quarterly
--real
--rules-file=
--unmarked
--value=
--version
--weekly
--yearly
TEXT

read -r -d "" _hledger_complist_options_commodities <<TEXT
--alias=
--anon
--debug=
--file=
--help
--ignore-assertions
--pivot=
--rules-file=
--version
TEXT

read -r -d "" _hledger_complist_options_descriptions <<TEXT
--alias=
--anon
--auto
--begin=
--cleared
--color=
--cost
--daily
--date2
--debug=
--depth=
--empty
--end=
--exchange=
--file=
--forecast
--help
--ignore-assertions
--infer-value
--market
--monthly
--pending
--period=
--pivot=
--quarterly
--real
--rules-file=
--unmarked
--value=
--version
--weekly
--yearly
TEXT

read -r -d "" _hledger_complist_options_diff <<TEXT
--alias=
--anon
--debug=
--file=
--help
--ignore-assertions
--pivot=
--rules-file=
--version
TEXT

read -r -d "" _hledger_complist_options_equity <<TEXT
--alias=
--anon
--auto
--begin=
--cleared
--close
--close-acct=
--close-desc=
--color=
--cost
--daily
--date2
--debug=
--depth=
--empty
--end=
--exchange=
--explicit
--file=
--forecast
--help
--ignore-assertions
--infer-value
--interleaved
--market
--monthly
--open
--open-acct=
--open-desc=
--pending
--period=
--pivot=
--quarterly
--real
--rules-file=
--show-costs
--unmarked
--value=
--version
--weekly
--yearly
TEXT

read -r -d "" _hledger_complist_options_files <<TEXT
--alias=
--anon
--debug=
--file=
--help
--ignore-assertions
--pivot=
--rules-file=
--version
TEXT

read -r -d "" _hledger_complist_options_help <<TEXT
--cat
--help
--info
--man
--pager
TEXT

read -r -d "" _hledger_complist_options_import <<TEXT
--alias=
--anon
--auto
--begin=
--catchup
--cleared
--color=
--cost
--daily
--date2
--debug=
--depth=
--dry-run
--empty
--end=
--exchange=
--file=
--forecast
--help
--ignore-assertions
--infer-value
--market
--monthly
--pending
--period=
--pivot=
--quarterly
--real
--rules-file=
--unmarked
--value=
--version
--weekly
--yearly
TEXT

read -r -d "" _hledger_complist_options_incomestatement <<TEXT
--alias=
--anon
--auto
--average
--begin=
--change
--cleared
--color=
--cost
--cumulative
--daily
--date2
--debug=
--depth=
--drop=
--empty
--end=
--exchange=
--file=
--flat
--forecast
--format=
--help
--historical
--ignore-assertions
--infer-value
--market
--monthly
--no-elide
--no-total
--output-file=
--output-format=
--pending
--percent
--period=
--pivot=
--pretty-tables
--quarterly
--real
--row-total
--rules-file=
--sort-amount
--tree
--unmarked
--value=
--version
--weekly
--yearly
TEXT

read -r -d "" _hledger_complist_options_is <<TEXT
--alias=
--anon
--auto
--average
--begin=
--change
--cleared
--color=
--cost
--cumulative
--daily
--date2
--debug=
--depth=
--drop=
--empty
--end=
--exchange=
--file=
--flat
--forecast
--format=
--help
--historical
--ignore-assertions
--infer-value
--market
--monthly
--no-elide
--no-total
--output-file=
--output-format=
--pending
--percent
--period=
--pivot=
--pretty-tables
--quarterly
--real
--row-total
--rules-file=
--sort-amount
--tree
--unmarked
--value=
--version
--weekly
--yearly
TEXT

read -r -d "" _hledger_complist_options_notes <<TEXT
--alias=
--anon
--auto
--begin=
--cleared
--color=
--cost
--daily
--date2
--debug=
--depth=
--empty
--end=
--exchange=
--file=
--forecast
--help
--ignore-assertions
--infer-value
--market
--monthly
--pending
--period=
--pivot=
--quarterly
--real
--rules-file=
--unmarked
--value=
--version
--weekly
--yearly
TEXT

read -r -d "" _hledger_complist_options_payees <<TEXT
--alias=
--anon
--auto
--begin=
--cleared
--color=
--cost
--daily
--date2
--debug=
--depth=
--empty
--end=
--exchange=
--file=
--forecast
--help
--ignore-assertions
--infer-value
--market
--monthly
--pending
--period=
--pivot=
--quarterly
--real
--rules-file=
--unmarked
--value=
--version
--weekly
--yearly
TEXT

read -r -d "" _hledger_complist_options_prices <<TEXT
--alias=
--anon
--auto
--begin=
--cleared
--color=
--cost
--costs
--daily
--date2
--debug=
--depth=
--empty
--end=
--exchange=
--file=
--forecast
--help
--ignore-assertions
--infer-value
--inverted-costs
--market
--monthly
--pending
--period=
--pivot=
--quarterly
--real
--rules-file=
--unmarked
--value=
--version
--weekly
--yearly
TEXT

read -r -d "" _hledger_complist_options_print <<TEXT
--alias=
--anon
--auto
--begin=
--cleared
--color=
--cost
--daily
--date2
--debug=
--depth=
--empty
--end=
--exchange=
--explicit
--file=
--forecast
--help
--ignore-assertions
--infer-value
--market
--match=
--monthly
--new
--output-file=
--output-format=
--pending
--period=
--pivot=
--quarterly
--real
--rules-file=
--unmarked
--value=
--version
--weekly
--yearly
TEXT

read -r -d "" _hledger_complist_options_print_unique <<TEXT
--alias=
--anon
--auto
--begin=
--cleared
--color=
--cost
--daily
--date2
--debug=
--depth=
--empty
--end=
--exchange=
--file=
--forecast
--help
--ignore-assertions
--infer-value
--market
--monthly
--pending
--period=
--pivot=
--quarterly
--real
--rules-file=
--unmarked
--value=
--version
--weekly
--yearly
TEXT

read -r -d "" _hledger_complist_options_reg <<TEXT
--alias=
--anon
--auto
--average
--begin=
--cleared
--color=
--cost
--cumulative
--daily
--date2
--debug=
--depth=
--empty
--end=
--exchange=
--file=
--forecast
--help
--historical
--ignore-assertions
--infer-value
--invert
--market
--monthly
--output-file=
--output-format=
--pending
--period=
--pivot=
--quarterly
--real
--related
--rules-file=
--unmarked
--value=
--version
--weekly
--width=
--yearly
TEXT

read -r -d "" _hledger_complist_options_register <<TEXT
--alias=
--anon
--auto
--average
--begin=
--cleared
--color=
--cost
--cumulative
--daily
--date2
--debug=
--depth=
--empty
--end=
--exchange=
--file=
--forecast
--help
--historical
--ignore-assertions
--infer-value
--invert
--market
--monthly
--output-file=
--output-format=
--pending
--period=
--pivot=
--quarterly
--real
--related
--rules-file=
--unmarked
--value=
--version
--weekly
--width=
--yearly
TEXT

read -r -d "" _hledger_complist_options_register_match <<TEXT
--alias=
--anon
--auto
--begin=
--cleared
--color=
--cost
--daily
--date2
--debug=
--depth=
--empty
--end=
--exchange=
--file=
--forecast
--help
--ignore-assertions
--infer-value
--market
--monthly
--pending
--period=
--pivot=
--quarterly
--real
--rules-file=
--unmarked
--value=
--version
--weekly
--yearly
TEXT

read -r -d "" _hledger_complist_options_rewrite <<TEXT
--add-posting=
--alias=
--anon
--auto
--begin=
--cleared
--color=
--cost
--daily
--date2
--debug=
--depth=
--diff
--empty
--end=
--exchange=
--file=
--forecast
--help
--ignore-assertions
--infer-value
--market
--monthly
--pending
--period=
--pivot=
--quarterly
--real
--rules-file=
--unmarked
--value=
--version
--weekly
--yearly
TEXT

read -r -d "" _hledger_complist_options_roi <<TEXT
--alias=
--anon
--auto
--begin=
--cashflow
--cleared
--color=
--cost
--daily
--date2
--debug=
--depth=
--empty
--end=
--exchange=
--file=
--forecast
--help
--ignore-assertions
--infer-value
--investment=
--market
--monthly
--pending
--period=
--pivot=
--profit-loss=
--quarterly
--real
--rules-file=
--unmarked
--value=
--version
--weekly
--yearly
TEXT

read -r -d "" _hledger_complist_options_stats <<TEXT
--alias=
--anon
--auto
--begin=
--cleared
--color=
--cost
--daily
--date2
--debug=
--depth=
--empty
--end=
--exchange=
--file=
--forecast
--help
--ignore-assertions
--infer-value
--market
--monthly
--output-file=
--pending
--period=
--pivot=
--quarterly
--real
--rules-file=
--unmarked
--value=
--version
--weekly
--yearly
TEXT

read -r -d "" _hledger_complist_options_tags <<TEXT
--alias=
--anon
--auto
--begin=
--cleared
--color=
--cost
--daily
--date2
--debug=
--depth=
--empty
--end=
--exchange=
--file=
--forecast
--help
--ignore-assertions
--infer-value
--market
--monthly
--parsed
--pending
--period=
--pivot=
--quarterly
--real
--rules-file=
--unmarked
--value=
--values
--version
--weekly
--yearly
TEXT

read -r -d "" _hledger_complist_options_test <<TEXT
--debug=
--help
--version
TEXT

read -r -d "" _hledger_complist_options_txns <<TEXT
--alias=
--anon
--auto
--begin=
--cleared
--color=
--cost
--daily
--date2
--debug=
--depth=
--empty
--end=
--exchange=
--explicit
--file=
--forecast
--help
--ignore-assertions
--infer-value
--market
--match=
--monthly
--new
--output-file=
--output-format=
--pending
--period=
--pivot=
--quarterly
--real
--rules-file=
--unmarked
--value=
--version
--weekly
--yearly
TEXT

read -r -d "" _hledger_complist_options_ui <<TEXT
--alias=
--anon
--auto
--begin=
--change
--cleared
--color=
--cost
--daily
--date2
--debug=
--depth=
--empty
--end=
--exchange=
--file=
--flat
--forecast
--help
--ignore-assertions
--infer-value
--market
--monthly
--pending
--period=
--pivot=
--quarterly
--real
--register=
--rules-file=
--theme=
--tree
--unmarked
--value=
--version
--watch
--weekly
--yearly
TEXT

read -r -d "" _hledger_complist_options_web <<TEXT
TEXT

read -r -d "" _hledger_complist_options_api <<TEXT
TEXT

# Local Variables:
# sh-basic-offset: 4
# indent-tabs-mode: nil
# End:
# ex: ts=4 sw=4 et

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
    # - use comptop -o filenames to escape the rest
    COMP_WORDBREAKS=${COMP_WORDBREAKS//:}
    compopt -o filenames

    local subcommand
    local subcommandOptions
    local i

    for (( i=1; i<${#words[@]}; i++ )); do
        subcommand=${words[i]}
        if ! grep -Fxqe "$subcommand" <<< "$_hledger_complist_commands"; then
            subcommand=
            continue
        fi
        # There could be other commands begining with $subcommand, e.g.:
        # $subcommand == reg --> register, register-match,
        # $subcommand == bal --> balance, balancesheet, balancesheetequity, etc.
        # Do not ignore them!
        if [[ $subcommand == "$cur" ]] && ((i == cword)); then
            local subcommandMatches
            subcommandMatches=$(grep -c "^$subcommand" <<< "$_hledger_complist_commands")
            if ((subcommandMatches > 1)); then
                subcommand=
                break
            else
                _hledger_compreply "$subcommand"
                return 0
            fi
        fi
        # Replace dashes with underscores and use indirect expansion
        subcommandOptions=_hledger_complist_options_${subcommand//-/_}
        _hledger_compreply "$(_hledger_compgen "${!subcommandOptions}")"
        break
    done

    # Option argument completion
    _hledger_compreply_optarg && return

    if [[ -z $subcommand ]]; then
        # Completion lists are already sorted at build-time
        # This keeps commands and options grouped separately
        compopt -o nosort +o filenames
        _hledger_compreply "$(_hledger_compgen "$_hledger_complist_commands")"
        _hledger_compreply_append "$(_hledger_compgen "$_hledger_complist_generic_options")"

        return 0
    fi

    # Avoid setting compopt bellow if completing an option
    [[ $cur == -* ]] && return

    # Almost all subcommands accept [QUERY]
    # -> always add accounts to completion list
    # Except for those few that will complain
    local noQuery=(files help test)
    # shellcheck disable=2076
    [[ " ${noQuery[*]} " =~ " $subcommand " ]] && return
    # Add any other subcommand special treatment here, or if it becomes unwieldy
    # move it out in say _hledger_compreply_subcommand() and return on success.

    # Query specific completions
    _hledger_compreply_query && return

    # Do not sort, keep accounts and query filters grouped separately
    compopt -o nosort -o nospace
    _hledger_compreply_append "$(_hledger_compgen "$_hledger_complist_query_filters")"
    if [[ -z $cur ]]; then
        _hledger_compreply_append "$(_hledger_compgen "$(_hledger accounts --flat --depth 1)")"
    else
        _hledger_compreply_append "$(_hledger_compgen "$(_hledger accounts --flat)")"
    fi

    return 0
}

_hledger_extension_completion_function() {
    local cmd=$1
    shift

    # Change parameters and arguments and call the
    # normal hledger completion function.
    local extensionName=${cmd#*-}
    COMP_WORDS=( "hledger" "$extensionName" "${COMP_WORDS[@]:1}" )
    COMP_CWORD=$((COMP_CWORD + 1))
    _hledger_completion_function "hledger" "$@"
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

_hledger_quote()
{
    local quoted
    _hledger_quote_by_ref "$1" quoted
    printf %s "$quoted"
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
# wordlist to compgen -- it will eat your quotes, drink your booze and...
# Completion candidates are quoted accordingly first and then we leave it to
# compgen to deal with readline.
#
# Arguments:
# $1: a newline separated wordlist with completion cadidates
# $2: (optional) a prefix string to add to generated completions
# $3: (optional) a word to match instead of $cur, the default.
# If $match is null and $prefix is defined the match is done against $cur
# stripped of $prefix. If both $prefix and $match are null we match against
# $cur and no prefix is added to completions.
_hledger_compgen() {
    local wordlist=$1
    local prefix=$2
    local match=$3
    local quoted=()
    local word
    local i=0

    while IFS= read -r word; do
        _hledger_quote_by_ref "$word" word
        quoted[i++]=$word
    done <<< "$wordlist"

    if (( $# < 3 )); then
        match=${cur:${#prefix}}
    fi

    local IFS=$'\n'
    compgen -P "$prefix" -W "${quoted[*]}" -- "$match"
}

# Try required option argument completion. Set COMPREPLY and return 0 on
# success, 1 if option doesn't require an argument or out of context
_hledger_compreply_optarg() {
    local optionIndex=${1:-$((cword - 1))}
    local recursionLevel=${2:-0}
    local wordlist
    local error=0
    local match

    # Match the empty string on --file=<TAB>
    [[ $cur == = ]] || match=$cur

    case ${words[optionIndex]} in
        --alias)
            compopt -o nospace
            _hledger_compreply "$(_hledger_compgen "$(_hledger accounts --flat)" "" "$match")"
            ;;
        -f|--file|--rules-file|-o|--output-file)
            _hledger_compreply "$(compgen -f -- "$match")"
            ;;
        --pivot)
            compopt -o nosort
            wordlist="code description note payee"
            _hledger_compreply "$(compgen -W "$wordlist" -- "$match")"
            _hledger_compreply_append "$(_hledger_compgen "$(_hledger tags)" "" "$match")"
            ;;
        --value)
            wordlist="cost then end now"
            _hledger_compreply "$(compgen -W "$wordlist" -- "$match")"
            ;;
        -X|--exchange)
            _hledger_compreply "$(_hledger_compgen "$(_hledger commodities)" "" "$match")"
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
            compopt -o nospace
            _hledger_compreply "$(_hledger_compgen "$(_hledger accounts --flat)" "" "$match")"
            ;;
        --debug)
            _hledger_compreply "$(compgen -W "{1..9}" -- "$match")"
            ;;
        # Argument required, but no handler (yet)
        -b|--begin|-e|--end|-p|--period|--depth|--drop)
            _hledger_compreply ""
            ;;
        =)
            # Recurse only once!
            ((recursionLevel > 1)) && return 1
            if [[ ${words[optionIndex - 1]} == -* ]]; then
                _hledger_compreply_optarg $((optionIndex - 1)) $((recursionLevel + 1))
                error=$?
            fi
            ;;
        *)
            error=1
            ;;
    esac

    return $error
}

# Query filter completion through introspection
_hledger_compreply_query() {
    [[ $cur =~ .: ]] || return
    local query=${cur%%:*}:
    grep -Fxqe "$query" <<< "$_hledger_complist_query_filters" || return

    local hledgerArgs=()
    case $query in
        acct:)  hledgerArgs=(accounts --flat) ;;
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
            _get_comp_words_by_ref -n '<=>' -c cur
            _hledger_compreply "$(compgen -P "$query" -W "$wordlist" -- "${cur#*:}")"
            return 0
            ;;
    esac

    _hledger_compreply "$(
        _hledger_compgen "$(
            _hledger "${hledgerArgs[@]}"
        )" "$query"
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
    for (( i=1; i < ${#words[@]} - 2; i++ )); do
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
include(`commands.txt')dnl
TEXT

read -r -d "" _hledger_complist_query_filters <<TEXT
include(`query-filters.txt')dnl
TEXT

read -r -d "" _hledger_complist_generic_options <<TEXT
include(`generic-options.txt')dnl
TEXT

# Dashes are replaced by m4 with underscores to form valid identifiers
# Referenced by indirect expansion of $subcommandOptions
dnl
include(`foreach2.m4')dnl
foreach(`cmd', (include(`commands-list.txt')), `
read -r -d "" _hledger_complist_options_`'translit(cmd, -, _) <<TEXT
include(options-cmd.txt)dnl
TEXT
')dnl

# Local Variables:
# sh-basic-offset: 4
# indent-tabs-mode: nil
# End:
# ex: ts=4 sw=4 et

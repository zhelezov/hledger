undivert(`hledger-completion.bash.stub')dnl

# Include lists of commands and options generated by the Makefile using the
# m4 macro processor.
# Included files must have exactly one newline at EOF to prevent weired errors.

read -r -d "" _hledger_complist_commands <<"__TEXT__"
undivert(`commands.txt')dnl
__TEXT__

read -r -d "" _hledger_complist_query_filters <<"__TEXT__"
undivert(`query-filters.txt')dnl
__TEXT__

read -r -d "" _hledger_complist_generic_options <<"__TEXT__"
undivert(`generic-options.txt')dnl
__TEXT__

# Dashes are replaced by m4 with underscores to form valid identifiers
# Referenced by indirect expansion of $subcommandOptions
dnl
include(`foreach2.m4')dnl
foreach(`cmd', (include(`commands-list.txt')), `
read -r -d "" _hledger_complist_options_`'translit(cmd, -, _) <<"__TEXT__"
undivert(options-cmd.txt)dnl
__TEXT__
')dnl

return 0

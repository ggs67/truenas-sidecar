# Script variable changer

This script is not an integral part of this project but developed in its context and subject for later removal.

The scripts goal is to be able to quickly and safely change variables in BASH scripts. This in order to unify variables names and reduce the potential collision of variables between custom builders and the framework.

The script can either work on a single file, or on a complete package.

# Synopsis

usage: script_change_var.py [-h] [-B] [-C] [-c] [-i IGNORE] [-l LIST] [-L] [-n NAME] [-N NOT_NAME] [--var VAR] [--not-var NOT_VAR] [-v] [-V] [-x] start [vardef ...]

## positional arguments:

| Arg      | Count | Description                  |
|----------|-------|------------------------------|
|  start   |   1   | start directory or file      |
|  vardef  |  0..n | variable change definition  |

## Vardefs

Vardefs have the following format:

1. var_name->new_var_name
2. var_name ->
4. @vardef-file
5. # comment (in vardef-file)

(1) This is the general vardef, which defines that the variable with name "var_name" should be renamed to "new_var_name"

(2) This is a place holder vardef which is useful in vardef files, to use as a reminder that this variable may be subject to rename, but not yet surem, or the name is to be defined later. This vardef will have no impact on the actual process.

(3) This syntax is used to include a vardef file. It can either be used on the command line to actually load vardefs from a file, but it can also be used in a vardef file to include another file.

(4) Vardef files can also contain comments, which have to start with a hash sign (#) in the beginning of the line. Please note that inline comments (i.e. a comment behind a vardef on the same line) are not supported

>[!NOTE]
> Vardefs on the command line and in files are equivalent and can be mixed at will.

## Options

###  -h, --help

Shows a help message

### -B, --no-backups

Skips files that are expected to be backups, these are files ending with a tilde (~), having the .bak extension or files with names starting an ending with a hash sign (#)

Alternatively you may use the _N|--not-name option to explicitely specify names

### -C, --collect 

This option switches the tool to collect mode, where variables are not to be replaced, but identified. The tool will process all scripts and attempts to identify all variables in the script(s). The idea is to produce a list of variables to be used to pick those that are to be renamed.

###  -c, --comment 

Add comments to each modified script.  Each line with at least one renamed variable will be preceded by a comment line starting with #<># and followed by the original line

In addition each line that has a potentially omitted variable renaming will be followed by a comment line starting with  \#//# and  marking the omitted variable with ^^^^^^ folowed by
the related vardef so that the user can edit the line manually.

>[!Note]
>The tool attempts to identify variables as 

###  -i \<ignore-patrh>, --ignore \<ignore-patrh>

Ignores the specified file or directory. Relative paths are resolved relative to the "start" positional argument, i.e. relative to the start location.

### -l \<list-file>, --list \<list-file>

Specifies a file to log the modified files including counts of renamed variables as well as potential omissions. 

Example:

| changes  | misses | file
|-----------|---------|--------------------------------------------------------------|
|   3           |    3       |   /home/dev/truenas/ext/config_checker.sh
| 28           |    4       |   /home/dev/truenas/ext/deploy.sh
|   5           |   8        |  /home/dev/truenas/ext/sanity.sh
|   3           |   7        |  /home/dev/truenas/ext/load_config.sh
|   5           |   0        |  /home/dev/truenas/builders.d/build_magick.sh
|   4           |   0        |  /home/dev/truenas/builders.d/build_lxd.sh.removed
|   6           |   0        |  /home/dev/truenas/builders.d/build_bacula.sh
|   5           |   0        |  /home/dev/truenas/builders.d/build_emacs.sh.disabled
|   5           |   0        |  /home/dev/truenas/builders.d/build_python.sh
|  91          |    4       |  /home/dev/truenas/build.sh
|   2           |   0        |  /home/dev/truenas/gglib/include
|  12          |   3        |  /home/dev/truenas/gglib/l.d/funcopts.lib
|  18          |  1         |  /home/dev/truenas/gglib/l.d/errmgr.lib
|   9           |  9         |  /home/dev/truenas/conf.d/config.sh


### -L, --lines           
  
  Include information about the script lines with --collect
  
###  -n \<pattern>, --name \<pattern>

If this option is present the tool only consideres files that match the given file name or pattern. This option can be repeated multiple times.

###  -N \<pattern>, --not-name \<pattern>

This is the opposite option of the previous one, by filtering out any file name that does fit the given pattern.

```
> **_EXAMPLE:_**  --not-name "*.bak" 
```

###  --var VAR      

only consider matching variable names (regex)

  --not-var NOT_VAR     only consider non-matching variable names (regex)
  -v, --verbose         enable verbose output (default if -x|--exec is omitted
  -V, --list-vars       list also files per variable, where found (with -l)
  -x, --exec            this flag is required to perform any changes in the file. Withou t this flag a dry-run is performed
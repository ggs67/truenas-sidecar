
# Introduction
Project llowing additional linux packages to be installed on a TrueNAS Scale NAS, without altering the TrueNAS installation itself. Thus: "sidecar installation"

Project start: 02-JAN-2024

# Disclaimer

ANY AND EVERY USE OF THIS WORK IMPLIES THE PRIOR READ AND COMPREHENSION OF THIS COMPLETE DISCLAIMER SECTION WITH ALL ITS SUB-SECTIONS.

Before going any further, let me tell you that I develop these scripts for my own needs while keeping them as general and open as possible to provide them as-is for reference and use to others. 

## Work in progress

As for now this project is work in progress, which means that behavior, layout, names, features, options and others are subject to important changes  over time. Many aspects are also not yet or not yet correctly (due to changes) documented

In this state this project is not meant to be used in any environment except pure testing environments. The main purpose of providing this work at this stage is to allow for comments.

Fundamental changes this project went already through:

- build.sh now being the main build script dispatching to builder's functions, initially it was a library of functions and variables sourced from each builder
- build.sh general purpose functions moved to a bash function library (gglib) and split into modules that can be loaded upon need (similar to python's `import`).
- build_all.sh integrated into build.sh


## Risks and possible Side Effects

While this work is performed with high care, risks and side-effects cannot be and are not excluded. These can include, but are not limited to, destroying the integrity of the system used for developing and/or building  as well as of the target TrueNAS environment(s) including their data. The former risk may be reduced by adopting the recommended way of using a separate virtual machine for this sole purpose and using a non-superuser for building and deployment. The latter risk depending not only on this work but also on the packages built and installed requires the user to progress with care.

We assume as well that the destination directory on the TrueNAS server where the packages are to be installed is a dataset (or on a dataset) separate from any TrueNAS system partition. Usually such a path would be in the /mnt directory, like for example /mnt/data/opt)

I do explicitly point out that, while the goal of the sidecar project is to avoid any altering of the core TrueNAS installation I cannot exclude that some (even bundled) builders still generate packages that could place files within the TrueNAS system when run.

An example of such a potential risk is python, where for example pip could potentially (while not expected) install downloaded modules in a system path. To avoid such side effects is actually also the main reason why the installation path on the development system should match the installation path on the TrueNAS server.

The above gives you only an overview of some of the potential risks and side effects that may occur using this work. 
## Disclaimer of Warranty

This Work is provided “as is”. Any express or implied warranties, including but not limited to, the implied warranties of merchantability and fitness for a particular purpose are disclaimed. In no event shall the author be liable for any direct, indirect, incidental, special, exemplary or consequential damages (including, but not limited to, procurement of substitute goods or services, loss of use, data or profits, or business interruption) however caused and on any theory of liability, whether in contract, strict liability, or tort (including negligence or otherwise) arising in any way out of the use of this Work, even if advised of the possibility of such damage.

The User of this Work agrees to hold harmless and indemnify the author from every claim or liability (whether in tort or in contract), including attorneys’ fees, court costs, and expenses, arising in direct consequence of Recipient’s use of the item, including but not limited to, claims or liabilities made for injury to or death of personnel of user or third parties, damage to or destruction of property of user or third parties, infringement or other violations of intellectual property or technical data rights.

Nothing in this Work is intended to constitute an endorsement, explicit or implied, by the author of any particular manufacturer’s product or service.

## Disclaimer of Endorsement

Reference herein to any specific commercial or non-commercial product, process, or service by trade name, trademark, manufacturer, or otherwise, in this Work does not constitute an endorsement, recommendation, or favoring by the author and shall not be used for advertising or product endorsement purposes.

# Introduction

Officially, TrueNAS does not allow installation of additional packages. On the other hand situations may arise that require such packages for better management of the NAS and/or its files were creating an App would be an overkill.

While there are workarounds available allowing to bypass this limitation, I prefer to stick to the rules as closely as possible. One may believe for example that adding a pure application package like ImageMagick may cause no harm, but dependencies may well do so and are quickly overseen.  
The problems that could quickly arise by forcefully installing Linux packages could include (but not limited to) version and expectation mismatches. The latter means that TrueNAS may assume facts about the installation, well knowing it has full control of it while the installation from different sources may break those assumptions.

# What is TrueNAS-Sidecar ?

To avoid the problems named above I decided to "sidecar" install packages from source code, which means installation in some path outside of the TrueNAS system (usually on a ZFS dataset).

For this reason I created a set of scrips assuring the following tasks:

* Common setup of the build environment
* Build the wanted packages for the destination path
* Check for libraries required by the package and package them as well if not available in TrueNAS
* Install the packages onto TrueNAS (actually copy, not altering the package database)
* provide a script which defines path environment variables to the packages

# How it works

## Build environment

First of all we need a separate build environment, as TrueNAS cannot build the packages. The build environment could be a virtual machine (recommended) or a physical server running the same Linux version (currently Debian 12) than your TrueNAS. 

The linux version can be obtained on TrueNAS with `cat /etc/os-release`

It is best to limit this environment use to TrueNAS package building only.
## Build user

The next step is to create a non-superuser user which does the actual builds. Note that the scripts are restricted to run  in non-root (not root and not UID or GID = 0) user process and will abort if run under root.

As the scripts are to perform some privileged tasks like creating directories outside of the build environment (matching the destination on TrueNAS)  and installing packages needed for the builds
it must be allowed to use sudo. This is could be achieved for example by adding it to the sudo group.

## Build environment

Setting up the build environment is as simple as copying the file tree from this repository into a directory in the build users home directory.

Which is easiest achieved by using `git clone`

## Sidecar directory structure

### Root directory
Contains the main scripts to manage the building and deployment process
### builders.d
Contains the builder scripts (`build_{package}.sh`)  for the different packages. Currently the following builders are available:
- python
- imagick
- bacula
- emacs

Note that packages can be build explicitly one by one or all at once. In the latter case builders can be enabled and disabled. Explicit builds are always executed when requested, even if the builder is disabled.
### conf.d
This directory contains the optional builder configuration filles (`build_{package}.conf`). Most builders will have at least a  minimal configuration file to configure the built version number. Son however download a constant link always representing the latest version and thus may not use any config file at all. 

Missing files (for builders needing one) are generated by the builder, using default values, on first build.
### logs

During the building process some command like the build itself generate a mass of output possibly burying builder messages between them. For this reason such commands are automatically logged into separate log files which are stored in a per builder  directory under the logs directory. The content of these log files is automatically displayed in case of a detected error. Log files are retained after the build for reference.
### packages
This is the default directory for downloading and building the packages
### distribute.d
Files contained in this directory are transferred to TrueNAS together with the build files. These files are 2-way synchronized during the deployment, to avoid that configuration files get unexpectedly overwritten.

### gglib
## Prerequisites

Note that Debian may not install sudo by default, in which case manual installation of sudo via the root use is required `apt install sudo` before any further step

After this you run the `prepare_environment.sh` script. This is only required once at first installation or update of the scripts. This script will install the required scripts.

In addition it will check the availability of required commands and suggest additional packages if missing. In that case you may re-run this script after the installation in order to make sure all tests have been done.
## Configuration

The next step is to edit  the configuration file config.sh which is sourced by other scripts. This file is divided in 3 parts.

### Part 1: Mandatory config area
The first part  before the single line comment is required to be adjusted for your environment. Please refer to the comments in the file to do so.

### Part2: Optional config area
The second part, between the single- and hash-line comment can be optionally configured but usually should be fine as-is. 

### Part 3: Static area
The static area, beginning after the hash-sign line is meant to setup the environment as expected by the different scripts and should not be modified unless you know exactly what you are doing

## SSH

The scripts make heavy use of SSH to transfer the files to the NAS but also for other tasks, for example looking up for exisiting or missing shared ibrararies. For this reason it is important to configure ssh on the NAS to put the public key of the build user into the `~/ssh/authorized_keys` file.

# Build files

## build_{package}.*

Every package must have a build script (aka. builder) named `build_{package}.sh` ( where package is the package name, like python in the `builders.d`subdirectory. The package name does only have to be meaningful to the user, it does not have to be directly linked to any repository or other name.

The build scripts are meant not to be edited, which is why some builders come with an additional configuration file called `build_{package}.conf` in the `conf.d` directory

See the following sections for details on how to configure existing builders and/or create your own ones.
### conf.d/build_{package}.conf

The main use of configuration files is to set the version number of the package to be retrieved and built. This file is included by the main `build.sh` script and can basically contain any bash command but usually is limited to variable definitions. 

If the file does not exist and the builder provides a `builder_default_config()` function, it will be called to create the default config file. Note that `build.sh` will source the newly created file before calling any other builder function.

The configuration file should contain comments documenting the use of the variables.
### builders.d/build_{package}.sh

The main builder script is calls by the main builder `build.sh` described below, which allows builders to be rather compact.

```
> **_NOTE:_**  builder scripts should call the `Establish` function first for better error reporting.
```

```
> **_NOTE:_**  builder scripts (with the exception to the call to Establish) SHOULD ONLY define functions and not perform any actions at global scope (i.e. all code should be within functions).
```

Global configuration variables should go into a separate config file `conf.d/build_{package}.conf`. The builder does not have to care about including this file as this is assured by the main `build.sh` before any builder function is called. (but after it has been sourced!) 

The general tasks of the builder are:
- Retrieve the source code
- Unpack the source archive (if applicable)
- Configure the package
- Build the package
- Install the package into the sidecar path identical to the destination path on the NAS ready for deployment

The above tasks are assisted by functions provided the `build.sh` script allowing very fast builder development. Note that builders should use these functions whenever available as these may  (now or later) perform additional actions necessary or useful for the build and/or deployment.

For example, the auto_configure function automatically changes to the package directory (assuming the configure script is at top level) configures the correct prefix (including any other provided options) as well as restoring original current directory. In addition it silently (by default) logs the process and only displays it in case of error.

The final deployment to the NAS is done by a separate script without assistance of the builder.

### Builder callback functions

These functions define callback functions of the builder called by `build.sh` to progress through the build process. Some functions are mandatory, others optional.

#### builder_default_config(config-file) [optional]

If no config file exists, this function is called, if available, with an absolute path to the expected config file. The function MUST create the configuration file with the default configuration. Don't define this function if no config file is required. The build process will fail if the file is still not existing after the call to this function.

#### Main building functions

The functions in this section are called in that order for preparing, configuring, building and finally installing the package. All these function with the exception of `config` and `prerequisites` are mandatory and every function should do exactely what it is expected to do, nothing more, nothing less. The reason to split up the build into several functions is to allow the build script to halt or interact with the process at given milestones.

##### package_prepare()
This function should prepare the package ready for the next steps. This should include the download and in case of an archive extracting of the package sources.

##### package_prerequisites() [optional]
This optional function is meant to install any prerequisite packages. 

##### package_config() [optional]
Prepares the package for build without building it. For an autoconf project this means for example running the ./configure script

Remember that packages should be build for installation on the TrueNAS path. In case of autoconf projects this is assured by the auto_configure() function which will set the correct prefix.

##### package_build()
This function initiates the actual build, without installing (e.g. "make")

##### package_install()
This is th efinal function called for installing the built files into the destination path ready for deployment to the NAS

#### package_config_files()

## build.sh

`build.sh`  is the main script for building the packages. It will use all other required scripts like the builder(s) to do so.

```
> **_NOTE:_**  It is mandatory for the builder script name to follow the build_{package}.sh pattern, for build.sh to produce expected results. 
```

### Variables
`build.sh` defines a set of variables described in this section.  The title shows each variable as well as its attributes in brackets. Variables should be assumed to be permanent and not to be altered by the builder, except if attributes allow it.

```
> **_NOTE:_** While the script should create all undocumented variables as local ones, we strongly discourage not to define any variable prior to sourcing `build.sh`
```

Variable attributes are as follows:
- **TEMP:** temporary variable. The descriptive text gives the lifetime of this variable, e.g. until when it is required by `build.sh` before it can be reused by the builder
- **OPT:** optional configuration variable which can be redefined by the builder (after sourcing `builder.common`) if needed.
- **DYN:** dynamic variable that may eventually change its value driven by `build.sh` functions
- **INTERNAL:** internal (build.sh) use only 

#### CMD_ARGS [TEMP]
Contains the arguments passed to the builder script. This variable is used by `parse_cmd()` and can be reused by the builder once this function was called.

#### SCRIPT
Contains the path to the `build.sh` script as invoked (eg. $0)

#### ME
Contains the name of the `build.sh` script without path

#### DIR
Contains the absolute path to the directory containing the called `build.sh` script

#### RUN_DIR
Contains the directory from which the builder was called. 

#### BUILDER
Contains the builder name, which is the script name without its `.sh` extension

#### TARGET
The target is the package name as given in the builder script name, i.e. `builder_{package}.sh` without the `builder_` and `.sh` extension.

#### BUILDER_CONFIG
Is the absolute path to the builders optional configuration (.conf) file. Note that this variable is set regardless of the file existing or not.

#### BUILDER_SCRIPT
Contains the absolute path to the requested package builder

#### LOGDIR
Absolute path to the builders own logging directory which will contain the logs for silenced operations like building and installing

#### SYNOPSIS [OPT]
This variable is used in the `usage()`  function to display the general usage synopsis.  `usage()` shows the script name with the -h (help, available for any builder) option and appends SYNOPSIS to it so that the builder is able to show its own SYNOPSIS

This can be combined with a custom `usage_info()` function.

#### SHELL_ENABLED_OPTS / SHELL_DISABLED_OPTS
These variables define the bash shell options as set (or unset) in the development environment. To avoid unexpected behavior of the scripts, `build.sh` will reset the shell options to exactly these setting.

If ever a different option set is required by the builder these options should be changed by the builder and preferably reset prior to any `build.sh` function call.

`build.sh` offers a number of functions to manage flag changes

#### CATCH_LOGFILE [OPT, DYN]

This variable designates the current log file in use. In case of a ought error, its tail will be displayed before the error message

CAUGHT_LOGFILE can be set directly by the builder, but be aware that it is also used and reset by `catch_log()` which catches the log of a single command line.

This variable must be reset (unset or set to empty value) whenever the logfile is no longer in use.

#### VERBOSE [DYN, default=0]
Contains the verbosity level, i.e. the number of -v flags. 

#### BUILD_ALL [INTERNAL]
Variable denoting that script is currently in BUILD_ALL mode. This variable is internal use only.

### Functions
`build.sh` defines a set of functions described in this section.  The title shows each function as well as its attributes in brackets. 

Variable attributes are as follows:

- **CB:** callback function, i.e. function optionally defined by the builder and called back from given `build.sh` functions.

#### usage("{error-msg}")
Prints usage information and then exits the script. This function has multiple hooks for it to be customized.

The first is its parameter which, if passed (i.e. not empty) is printed as error message (preceded by "ERROR:") before the usage information.

Then the SYNOPSIS variable which allows to customize the "usage:" line by specifying the synopsis of the command without the command name and the common -h option which is already handled by `usage()`. 

Last but not least the builder defined callback function `usage_info` which can be used to output option and argument descriptions.

#### usage_info() [CB]
This is a callback function to be defined by the builder allowing to output option and argument descriptions as well as addition notes.

The text output from this function is inserted below the description of -h ("  -h : help - display this text"), eg. indented by 2 spaces., thus descriptions should follow this indent, while  additional notes may fall back to the 1st column.

#### catch() [CB]
This is the callback function defined by build.sh called in the event of any error of a command as we expect a proper build to be errorless.

# Installed package usage

Once the packages have been deployed to TRUENAS, the top-level directory of the destination will contain a script called `setup_paths.sh`. Any procees requiring these packages shoudl source this file.

Results of sourcing this file:

- add any existing binary directories to the PATH variable
- add any existing library directories to LD_LIBRARY_PATH variable
- define variables for select commands
- optionally define aliases for select commands (if -a option was given)


## Command variables and aliases

```
> **_NOTE:_** this script does append all paths behind any already existing paths. This makes sure 
```

Some (rare) packages may overlay existing commands

# Roadmap

Some expected next changes/additions are:

- Adding support for additional distributable files, for examples site specific configuration files
- Integrating the installer and the builder together so that the same environment and functions are available allowing increased coherence
- Adding support for git repositories



# CAUTION - KNOWN MAJOR ISSUE

***`NOTE:`*** I leave this point for now as it is an important thought. Actually the current version implements config file handling using multiple three-way syncs which should do the trick. HOWEVER this is an early stage of the implementation, and there are also situations which are not covered (for. ex. but not only, when using --purge)

The current version of the sidecar will result in the loss of modified configuration files in the NAS sidecar upon the next deployment.  

A solution to this is currently under development but is not not trivial because of possible site specific config files as well as different behaviors of the package staging processes which present
a number of major pitfalls.

Due to this the project is currently undergoing some substantial changes which may (and will eventually) currently break it for some time. Please keep posted for news on this matter, as this is no.1 priority now. For properly handling this issue it is necessary to integrate the deployment process into the building one (they have been separate scripts until now). The reason is that the staging and deployment phases must take place amid of the config file handling.

# Introduction
Project allowing additional Linux packages to be installed on a TrueNAS Scale NAS, without altering the TrueNAS installation itself. Thus: "sidecar installation"

Project start: 02-JAN-2024

# Disclaimer

ANY AND EVERY USE OF THIS WORK IMPLIES THE PRIOR READ AND COMPREHENSION OF THIS COMPLETE DISCLAIMER SECTION WITH ALL ITS SUB-SECTIONS.

Before going any further, let me tell you that I develop these scripts for my own needs while keeping them as general and open as possible to provide them as-is for reference and use to others. Over the time the project has evolved from the initial quick-hack using a collection of scripts to a rather clean approach with mainly one single integrated script and callbacks.

## Work in progress

As for now this project is work in progress, which means that behavior, layout, names, features, options and others are subject to important changes  at any time. Many aspects are also not yet or not yet correctly (also but not only due to changes) documented

In this state this project is not meant to be used in any environment except pure testing environments. The main purpose of providing this work at this stage is to allow for comments.

Fundamental changes this project went already through:

- build.sh now being the main build script dispatching to builder's functions, initially it was a library of functions and variables sourced from each builder
- build.sh general purpose functions moved to a bash function library (gglib) and split into modules that can be loaded upon need (similar to python's `import`).
- build_all.sh integrated into build.sh
- deploy.sh integrated into build.sh


## Risks and possible Side Effects

While this work is performed with high care, risks and side-effects cannot be and are not excluded. These can include, but are not limited to, destroying the integrity of the system used for developing and/or building  as well as of the target TrueNAS environment(s) including their data. The former risk may be reduced by adopting the recommended way of using a separate virtual machine for this sole purpose and using a non-superuser for building and deployment. The latter risk depending not only on this work but also on the packages built and installed requires the user to progress with care.

We assume as well that the destination directory on the TrueNAS server where the packages are to be installed is a dataset (or on a dataset) separate from any TrueNAS system partition. Furthermore the target directory should solely be used for the sidecar. Usually such a path would be in the /mnt directory, like for example /mnt/data/opt)

I do explicitly point out that, while the goal of the sidecar project is to avoid any altering of the core TrueNAS installation I cannot exclude that some (even bundled) builders still generate packages that could place or alter files within the TrueNAS system when run.

An example of such a potential risk is python, where for example pip could potentially (while not expected) install downloaded modules in a system path. Avoiding such side effects is actually also the main reason why the staging path on the development system should match the installation path on the TrueNAS server.

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

# Motivation

The motivation for this project, for me, was the migration form a QNap NAS to a custom TrueNAS. On my old NAS I had a set of python 3 scripts to manage videos which require a number python modules, and a script using ImageMagick to automatically handle and assemble scanned documents.

On my old NAS I also used a LXD container with bacula to backup my different servers around. My TRUENAS running on Proxmox which in turn now runs the bacula container, it does not have direct access to the TrueNAS storage. So the idea is to have the bacula storage daemon run on TrueNAS to avoid storage sharing overhead.

While python3 is available in TrueNAS it does not allow for additional module installations  through `pip`. Manual installation may work, but difficult to maintain and obviously also not meant to be done.

This is the reason why the project includes builders for python 3, ImageMagick and bacula with the latest having options on which parts to include. Being a big fan of Emacs, on Linux, I also did a builder for it.

`***Note:***` Another motivation point is also that IMHO the TrueNAS Scale App concept is a pain in the ass. With all the app parameters being somewhat opaque and often badly or not at all documented you never know if it is correctly configured, even if it works. TrueNAS shoudl here really have a glance to its competitors on how to implement apps. (my 5 cents)

# What is TrueNAS-Sidecar ?

To avoid the problems named above I decided to "sidecar" install packages from source code, which means installation in some path outside of the TrueNAS system (preferably on a ZFS dataset).

For this reason I created a set of scrips assuring the following tasks:

* Common setup of the build environment
* Build the wanted packages for the destination path
* Check for libraries required by the package and package them as well if not available in TrueNAS
* Install the packages onto TrueNAS (actually copy, not altering the package database)
* provide a script which defines path environment variables to the packages
* handle config files

# Limitations

TrueNAS sidecar is limited to user-space software only, kernel modules for instance are currently not supported. There are currently also no plans to change this because of the higher potential of impact on TrueNAS.

# Glossary of used terms

- ***Build Environment:***  the build environment is the host or virtual machine used for preparing (eg. building) the packages to be "installed" in the NAS sidecar. It is highly recommended to use a dedicated virtual machine for this purpose
- ***Sidecar home:*** is the root directory of this project
- ***NAS:*** speaking of NAS (or TrueNAS) we refer to the target NAS on which the sidecar packages are to be installed.
- ***Package:*** while actual linux packages are not supported for deployment by the project, we still call each software to be build and installed as a package. Each package has its own build script. It is also not recommended to bundle multiple software within a single package (f.ex. bundle a database server with a software requiring it), but separate them in different bundles. The project is currently not managing any such dependencies but eventually will.
- ***Sidecar:*** the word sidecar can be tricky but should be clear within its context. Usually when speaking of "the sidecar", it refers to the directory tree of the sidecar installation on the NAS. While, when referring to the building environment we usually use "sidecar project" or "sidecar builder", when speaking of the files and directories of the downloaded TrueNAS/sidecar github project. So when speaking of the "github builder root" it does not refer to the physical root (/) but the root directory of the sidecar project (usually /..../sidecar, for ex. /home/dev/sidecar)

# How it works

## Build environment

First of all we need a separate build environment, as TrueNAS cannot be used to build the packages. The build environment could be a virtual machine (recommended) or a physical server running the same Linux version  than your TrueNAS (currently Debian 12). 

The linux version can be obtained on TrueNAS with `cat /etc/os-release`

It is best to limit this host's use to TrueNAS package building only.

## Build user

The next step is to create a non-superuser user which does the actual builds. Note that the scripts are restricted to run  in non-root (not root and not UID or GID = 0) user process and will abort if run under root.

As the scripts are to perform some privileged tasks like creating directories outside of the build environment (matching the destination on TrueNAS)  and installing packages needed for the builds
it must be allowed to use sudo. This is could be achieved for example by adding it to the sudo group (at least with the default sudoers config).

```
> **_NOTE:_**  it is HIGHLY DISCOURAGED to run these scripts using a superuser to avoid altering of system files and also allow to trap and correct such bogous configurations.
```

## Build environment

Setting up the build environment is as simple as copying the file tree from this repository into a directory in the build users home directory.

Which is easiest achieved by using `git clone https://github.com/ggs67/truenas-sidecar.git`

## Deployment areas

Sidecar uses several distinct areas to store files at different stages during the deployment. 

These are described in the next sections in order of use.

### Package area

The package area is contained in the package directory in the sidecar project root. This area, by default, receives the downloaded archives and the build directories for the different packages.

For custom builders not relying on sidecar functions for download and preparation (i.e. extraction,...) it is highly recommended to stick on using this area as intended, i.e. create a build subdirectory for the target package. 

Such custom builders also need to define a number of variables (like ARCHIVE, PACKAGE_DIR, PACKAGE_TYPE,...) in order to stay compatible with the build process

### Staging area

Once the package is build it can be staged, i.e. installed into the staging area.  It is very important (and also currently enforced) that the staging area path and the final sidecar path on the NAS are identical. This because the build process may hardcode some paths into the software.

Currently the script enforces the staging/sidecar path to be within /mnt

Therefore a superuser is required to setup the staging area in the build environment. It is recommended that the complete path to the staging area is owned by root with the build user only having read-execute access to the directories, except for the final, actual sidecar directory which should be owned by the build user.

### TrueNAS Sidecar

This the actual destination of the software, i.e. a folder on the NAS which contains the sidecar files, and ONLY the sidecar files

The project currently enforces the sidecar area to be below the /mnt directory as it is expected to be on some ZFS dataset managed by TrueNAS

`***TODO:***` : let /mnt to be configured

### Config vault

The config vault is a directory in the sidecar home (`config_vault.d`) which is used to save edited configuration files from the sidecar to avoid overwriting of those.

## Sidecar builder directory structure

### Root directory
Contains the main scripts to manage the building and deployment process

The directories below are marked with the following attributes to show their use:
- [static] : directory containing project scripts and/or data which is static and only meant to be altered by sidecar project developers
- [editable]: directory with user editable config files.
- [add]: directory where more files may be added by the user, while the project provided files are not meant to be altered
- [read-only]: as opposed to [static] these files are altered by the build process but ment only to be read by the user (f.ex. log files)
- [dynamic]: this directory is (or may be) altered by the build processes. It's content is however mostly considered opaque to the user and user interaction with it should be limited to what this document explicitly allows. 

### ext/ [static]

This directory contains additional scripts internally used by the project and not meant to be used directly

### builders.d/ [add]

Contains the builder scripts (`build_{package}.sh`)  for the different packages. Currently the following builders are available:
- python
- imagick
- bacula
- emacs

Note that packages can be build explicitly one by one or all at once. In the latter case builders can be enabled and disabled. Explicit builds are always executed when requested, even if the builder is disabled.

### conf.d/ [config]
This directory contains man configuration file (`config.sh`) and the optional builder configuration filles (`build_{package}.conf`). Most builders will have at least a  minimal configuration file to configure the built version number. Some however download a constant link always representing the latest version and thus may not use any config file at all. 

Missing files (for builders needing one) are generated by the builder on the fly, using default values, on first build.

### logs/ [read-only]

During the building process some commands, like the build itself generate a mass of output possibly burying builder messages between them. For this reason such commands are automatically logged into separate log files which are stored in a per builder  directory under the logs directory. The content of these log files is automatically displayed in case of a detected error. Log files are retained after the build for reference.

### packages/ [dynamic]
This is the default directory for downloading and building the packages. Each package must use its own private directory (which is usually managed by functions provided by sidecar)

The user could manually delete archives and/or package directories either because that package is not required anymore, or to force the download and/or extraction. In either case it is of course mandatory to start from the first phase (default start phase for --build) when deploying this package again.

### config_vault.d/ [dynamic]
Files contained in this directory are transferred to TrueNAS together with the build files. These files are 2-way synchronized during the deployment, to avoid that configuration files get unexpectedly overwritten. This process is highly configurable and will be explained in detail later in this document.

Interaction within this directory is usually not necessary and if so, needs to be performed with extreme care. Files should not be edited in this directory, but rather on the NAS. Files may be deleted from this directory if they are for sure not required on the NAS anymore (deinstalled package).

### gglib/ [static]

gglib is candidate for a separate repository later and contains a bash function library separated in different modules which can be imported as required (similar to python import). Since currently the library modules are developed as required by the project, we import all modules.

## Prerequisites

Note that Debian may not install sudo by default, in which case manual installation of sudo via the root user is required (`apt install sudo`) before any further step

After this you run the `prepare_environment.sh` script. This is only required once at first installation or update of the scripts. This script will install the required packages.

In addition it will check the availability of required commands and suggest additional packages if missing. In that case you may re-run this script after the installation in order to make sure all tests will pass.

## Deployment process

### Caution

There are a few possible pitfalls with the sidecar installation. This document will describe the steps which are done in an attempt to avoid them. Make sure you understand the pitfalls completely before any build and deployment to avoid data loss.

The pitfalls are:

#### Time zones
While different timezones in the build environment and NAS should not impact the correct synchronization of the files as the underlying timestamps in UTC remain identical, there have been reports of exactely such issues with rsync. Such problems may also be injected (at least in theory) by explicit file "touching" and the related time conversions.

As a result the current deployment sanity checks enforce the build environment and NAS to have the same time zone in order to proceed with the deployment

#### Time synchronization

Another potential pitfall is time synchronization. For this reason both the NAS and the build environment host (or virtual machine) should have their clocks synchronized using NTP. 

The deployment process checks the time synchronization between both hosts and will warn if they are above 10 seconds, and fail with an error above 30 seconds.

For a reliable synchronization it is mandatory that the interval between two consecutive package staging and/or deployments is higher than the time difference between both hosts !

```
> **_NOTE:_**  NTP should be configured using the same sources on both NAS and build host. Also they should be configured using a minimum of 3 sources in order for NTP to be able to identify falsetickers.
```

```
> **_NOTE:_**  NTP should use known reliable servers. If internal servers are used, these in turn should use a minimum of 3 reliable sources (or be reliable stratum 1 servers on their own)
```

#### Debian version mismatch

Since the sidecar runs using the TRUENAS Linux environment (mainly libraries, and especially the kernel library) it is important that both the NAS and the build host are using the same Debian distribution version.

While both hosts should also be kept up-to-date in parallel (i.e. "apt update ; apt upgrade" run on both systems each time), small divergences are still possible, but these should usually not be an issue.

#### Edited config files

Edited config files is a whole other level of complexity when it comes to pitfalls. This because there are multiple sources and scenarios of configuration file updates. This complexity deserves its own chapter (Config file handling) below.

### Config file handling

![Config file syncing](docs/img/config_vault.svg)

In this context a config file is any file which has been or may be altered or added by the user to the sidecar. This may be an actual config file or for example an emacs lisp module or theme.

#### Config file sources
- initially provided by the installer (staging)
- updated (i.e. edited) by the user
- updated by installer
	- always
	- only if non-existent
	- only if not edited (i.e. not newer than binary file)
- provided by the user (i.e. site-specific config files not generated by the installer)

#### Related challenges

Each scenario has its own challenges that need to be addressed. But especially due to the build process being steered by the respective package and this is out of our control there is no 100% safety for config files. For this reason the deployment process offers the possibility to create backups prior to any deployment, and also to keep multiple versions of this backup, as well as an editable config hint file.

#### The handling process

If all options are enabled, the following course of actions is taken in order:
1. Sync from the NAS to the config vault, steered by the staging area (update) (this MUST BE done BEFORE the reverse sync)
2. Reverse sync (update only) from the NAS to the staging area (only files existing in the staging area)
3. Cleanup config vault
4. Sync NAS sidecar again with vault checking for all files existing in the vault (to catch any site-specific files)
5. Syncing files from the hint file to the vault
6. stage the package(s)
7. deploy
8. Sync back the vault to the NAS sidecar

The process is steered by the following configuration variables in config.sh

#### Special case: "--purge"

--purge is the way deinstallations of packages may be handled, as it clears the complete deployment area before 

##### DEPLOY_CONFIG_KEEP (Y/N, recommended=Y)

This is the master variable enabling the configuration file handling at all. If set to "N", which is highly discouraged, config files will not be saved and highly susceptible to be overwritten by subsequent deployments

##### DEPLOY_NO_SITE_CONFIG_FILES (Y/N, recommended=N) 

If 'Y', this disables special handling of site-specific config files (i.e. files added by the user). This will result in deleting any such file. 

In this context site-specific config files are files which have been added to the sidecar, and not initially deployed. I.e. files which were not exisitsng in the initial package installation.

Setting this to 'N' is the safer option and absolutely required if site-specific config files are used, while a setting of 'Y' in the case such files are not used reduces the artefact files left behind by packages over time or when deinstalled.

##### DEPLOY_CONFIG_REVERSE_SYNC (Y/N, recommended=Y)

Reverse sync is a fallback sync (i.e. an additional safety net) in order to avoid overwriting of
config files on deployment in the first place. Overwritten config files should be recovered through the 3-way config syncs as well.

Reverse-sync updates any file in the staging area which has been altered on the NAS after the last deployment. This takes place  prior to the staging process.

Note that this setting does only sync back modified config files existing in the staging area
(i.e. part of the initial package install). This in order to avoid artefacts and other sync issues.

##### DEPLOY_CONFIG_DUAL_SYNC} (Y/N, default=Y)

Dual sync uses a second sync process from the NAS to the config vault, by syncing any file difference of any file present in the vault. This may catch updates missed in the 3-way sync, using the staging area as reference.

##### DEPLOY_CONFIG_TOUCH (Y/N, default=N)
If enabled (Y), each file in the config vault (wether retrieved in this run or before)  will be "touched" (i.e. get its timestamp set to current time) for in order to make sure it will be synced back to the NAS and also preselect it that way for the next config file sync, as it will be newer than any file in the staging area.

The backside of the medal is that you will be unable to track the time of the last change 

```
> **_TODO:_**  keep track of config file editing dates by using extended file attributes and a sentinal file. The sentinel file is created (touched) just after the deployment thus we know that any file with an mtime later than this file was modified by the user.
```

##### DEPLOY_CONFIG_CLEANUP (Y/N, default=N)

If 'Y', this will cause any config file deleted in the NAS sidecar to be removed from the vault as well. If this setting is 'N' and a file present in the vault gets deleted on the NAS sidecar, the saved version will reappear upon next peployment.

##### DEPLOY_CONFIG_HINTS (array of paths)
```
> **_TODO:_**  Thi s variable exists but is not yet implemented
```

This variable is an array of hints for configuration files. There are 2 types of entries:

1. ***/absolute/path:*** an absolute path to a file or directory. Note that even though this is an absolute path it is interpreted as being relative to the sidecar root directory. Using the absolute path notiotion makes it mor readable as one is used to see `/etc/cfgdir/file.conf` but `ètc/cfgdir/file.conf` may be confusing.
2. ***@path:*** in this case the path may be an absolute or relative path to a hint file. If a relative path is given, it is meant to be relative to the Truenas sidecar builder root directory.

This variable is defining hints to be used by any package, while the package specific file `conf.d/build_<package>.cfg.hints` is used only for the given package.

The content format of this array is identical to the config file, so see "Config hints" below for more information

```
> **_NOTE:_**  the hint file conf.d/build_<package>.cfg.hints is implicitely used and should not be included in this array
```


#### Config hints

Config hints are defined globally through the DEPLOY_CONFIG_HINTS config variable (see above) or the package specific hint file `conf.d/build_<package>.cfg.hints`.

Both can contain the same entry types, but in addition hint files can contain comments starting with a '#' . Note that comments must be on a separate line, inline comments are not supported.

##### Config file or directory path

`***Format:***` /absolute/path

Config file or directory path MUST be specified as absolute path, even though it is interpreted as being relative to the sidecar root directory. The given file or directory is expected to be a config file and will be forcefully saved to the config vault.

##### Hint file

`***Format:***` @path

Here the path following the '@' can be either relative or absolute and is a path on the build environment host. Relative paths will be interpreted as relative to the sidecar home.

Each hint file can contain exactly the same entries as described in this section, i.e. also include other hint files

##### General path format

Paths following the rules described here above can inside of these constraints have wildcards allowing easy multiple selections.

```
> **_TODO:_**  we may consider using extended file attributes to mark files as config files as well
```

### General process

Once the  package build it can be installed in the local staging area, which should be the exact same path than on the destination NAS. During deployment all files in the staging area are copied to the destination NAS deployment directory (TRUENAS_DST).

### Detailed deployment steps

#### Library gathering

While the local development system does install all required libraries before building a package, these libraries may not be available on the destination NAS, and cannot be installed through normal processes.

The deployment process first builds a list of all shared libraries used by all binaries in the staging area. Then it checks the TRUENAS installation for libraries from this list that are available on the NAS and eliminates those from the list. The remaining libraries are then copied from the local system area top the staging area for deployment.

The `setup_path.sh` script deployed as well, creates an LD_LIBRARY_PATH variable pointing to all library directories in the sidecar for binaries to find those libraries.

#### make_setup_path.sh

The next step is to generate the `setup_path.sh` file which is to be deployed in order for users to have an easy way to setup correct paths for the sidecar.

This script is not static but requires some adjustments to fit the environment. For example system library folders are translated relative to the sidecar folder.

Next builders can offer an optional callback function, called to register additional commands.  

#### Backup of the existing sidecar

The next step being very delicate it is highly recommended to backup the previous installation prior to the actual deployment. The deployment script offers this service (which can be configured) as well.

#### Three-way syncing of configuration filers

#### Deployment

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


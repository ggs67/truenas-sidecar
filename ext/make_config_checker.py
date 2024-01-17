#!/usr/bin/env python3
import json
import re
import sys
import os
from pathlib import Path

import argparse
from typing import TextIO, Union, List, Optional

# ...
parser = argparse.ArgumentParser()
parser.add_argument(
    "-c",
    "--checker",
    help="Checker file path or directory"
)
parser.add_argument(
    "-f",
    "--function",
    action="store_true",
    help="Generate checker as bash function"
)
parser.add_argument(
    "-C",
    "--call",
    action="store_true",
    help="Implicit call to function"
)
parser.add_argument(
    "-g",
    "--gglib",
    action="store",
    help="path to gglib folder"
)
parser.add_argument(
    "-n",
    "--nosource",
    action="store_true",
    help="do not source config file"
)
parser.add_argument(
    "config",
    metavar="config-script",
    help="config script to be parsed and checked"
)

args = parser.parse_args()

if args.call and not args.function:
  print(f"ERROR: -C|--call flag requires -f|--function")
  sys.exit(99)

#---------------------------------------------------------------------------
def split_comment(s: str):
  q=None
  esc=False

  for i in range(len(s)):
    c=s[i]
    if esc: esc=False; continue
    if c == '\\': esc=True; continue
    if q is None:
      if c=="'" or c=='"':
        q=c
        continue
      if c== "#":
        # Got it
        return s[:i].strip(),s[i:].strip()
    else:
      if c == q:
        q=None
  return s.strip(), ""

#----------------------------------------------------------------------------
CheckerFile: TextIO=None
LazyCheckerSpacer=False
CheckerSpaced=False
def checker(s="", ignoreLazy: bool=False):
  global LazyCheckerSpacer,CheckerSpaced

  if LazyCheckerSpacer:
    LazyCheckerSpacer=False
    if not ignoreLazy: checker()
  s=s.rstrip()
  if s=="" and CheckerSpaced: return # Avoid multiple spaceing lines
  CheckerFile.write(s + '\n')
  CheckerSpaced = (s=="")

#----------------------------------------------------------------------------
def checker_spacer(lazy:bool = False):
  if lazy:
    LazyCheckerSpacer=True
  else:
    LazyCheckerSpacer = False # Reset any pending lazy spacer
    checker()

###############################################################################
class TScript:
  def __init__(self, argv=None):
    self._argv=sys.argv if argv is None else argv
    self.Script = Path(self._argv[0])
    self.Directory = self.Script.parent.resolve()
    self.ScriptName = self.Script.name

###############################################################################
class TChecker:

  def __init__(self, var: str, val: str, checks: Optional[Union[str, List[str]]], inCFG: bool=False):
    self.Variable=var
    self.Value=val
    if checks is not None:
      checks=list(checks[:]) if isinstance(checks,(list, tuple)) else [ checks ]
      checks=list(map(str.strip, checks))
    self.Checks=checks
    self.fromCfg=inCFG
    self.Confirmed=inCFG # If from config, then it is also confirmed

  def Update(self, check, inCFG=False):
    if check is None: return False
    check=check.strip()
    if check == "": return False
    # Only allow updates from cfg
    if self.Checks is not None:
      if not inCFG: return False
      if not self.fromCfg: self.Checks=[] # Override db checks with config checks
    if self.Checks is None: self.Checks=[]
    self.Checks.append(check)
    self.fromCfg=inCFG
    if inCFG: self.Confirmed=True
    return True

  #----------------------------------------------------------------------------
  def Generate(self, indent: int=0):
    if self.Checks is None: return

    if len(self.Checks) > 1: checker_spacer()
    for check in self.Checks:
      vpos=check.find("{}")
      if vpos >= 0:
        check=check[:vpos] + self.Variable + check[vpos+2:]
      else:
        check=f"{check} {self.Variable}"
      checker((indent*' ')+check+'\n')
    if len(self.Checks) > 1: checker_spacer(True) # Lazy spacer

  #----------------------------------------------------------------------------
  def Serialize(self):
    return [ self.Variable, self.Value, self.Checks ]

  def Deserialize(self, lst):
    self.Variable=lst[0]
    self.Value=lst[1]
    self.Check=lst[2]

###############################################################################
class TConfigScript:

  def __init__(self, path : Path, checkerPath: Path = None, gglibDir: Path=None):
    self._path=path
    self._checks={}
    self._lastVardef=None
    self._gglib = "gglib" if gglibDir is None else gglibDir

    # Resolve checker path
    n = self._path.name.split('.')[0]+"_checker"
    d = self._path.parent
    if checkerPath is None:
      self._checkerDB = d / (n + ".cdb")
      self._checker = d / (n + ".sh")
    else:
      if checkerPath.is_dir():
        d = checkerPath
        self._checkerDB = checkerPath / (n + ".cdb")
        self._checker = checkerPath / (n + ".sh")
      else:
        n=checkerPath.stem if checkerPath.suffix == ".sh" else checkerPath.name
        d=checkerPath.parent
        self._checkerDB = d / (n + ".cdb")
        self._checker = d / (n + ".sh")
    self._checkerDir = d

  #----------------------------------------------------------------------------
  def LoadDB(self):
    self._checks = {}
    checks={}
    if self._checkerDB.exists():
      db=open(self._checkerDB, "r")
      checks = json.load(db)
      db.close()

    for var in checks:
      c=checks[var]
      self._checks[var]=TChecker(c[0], c[1], c[2], False)

  #----------------------------------------------------------------------------
  def SaveDB(self):
    checks={}

    # Prepare JSON
    for var in self._checks:
      checks[var]=self._checks[var].Serialize()

    db=open(self._checkerDB, "w")
    checks = json.dump(checks, db)
    db.close()


  #----------------------------------------------------------------------------
  def Make(self, asFunc:bool):
    self.LoadDB()

    self._parseConfig()
    self._cleanupDB() # Remove orphan entries from DB
    self.SaveDB()
    self._generateScript(asFunc)
    print(f"config checker '{str(self._checker)}' generated")

  #----------------------------------------------------------------------------
  def _cleanupDB(self):
    self._checks = { k:c for k,c in self._checks.items() if c.Confirmed }

  #----------------------------------------------------------------------------
  def _generateScript(self, asFunc:bool):
    global args,CheckerFile

    CheckerFile=open(self._checker, "w")

    indent=2 if asFunc else 0

    checker('#!/usr/bin/env bash')
    checker_spacer()
    checker('CHECKER_DIR=$( dirname "${BASH_SOURCE}" )')
    checker_spacer()
    cmt=""
    checker(f'{cmt}source ${{CHECKER_DIR}}/{os.path.relpath(self._gglib.absolute(), self._checkerDir.absolute())}/include checks')
    checker_spacer()
    cmt="# " if args.nosource else ""
    checker(f'{cmt}source ${{CHECKER_DIR}}/{os.path.relpath(self._path, self._checkerDir.absolute())}')
    checker_spacer()

    if asFunc:
      checker('check_config()')
      checker('{')
    for var in sorted(self._checks.keys()):
      self._checks[var].Generate(indent)
    if asFunc:
      checker('}', True)

    checker()

    if asFunc and args.call:
      checker("check_config")
      checker()

    CheckerFile.close()
    CheckerFile=None

  #----------------------------------------------------------------------------
  def _parseConfig(self):
    f=open(self._path, "r")
    for line in f:
      line=line.rstrip()
      if line == "": continue # Ignore empty lines

      # Variable assignment ?
      m=re.fullmatch(r"\s*([a-zA-Z0-9_]+)[=](.*)", line)
      if m is not None:
        var = m.group(1)
        val = m.group(2).strip()
        val,comment = split_comment(val)
        if comment.startswith("#->"):
          check=comment[3:].strip()
        else:
          check=None
        self._update(var,val,check)
        continue

      # OOL check ?
      m=re.fullmatch(r"\s*[#][-][>](.+)", line)
      if m is not None:
        check=m.group(1).strip()
        if check != "":
          self._update(None, None, check)
        continue # We allow multiple checks (avoid to clear _lastVardef below)

      self._lastVardef=None

  #----------------------------------------------------------------------------
  def _update(self, var, val, check):
    if var is None:
      if self._lastVardef is None:
        print(f"ERROR: out-of-line check without previous variable assignment")
        sys.exit(1)

      return self._lastVardef.Update(check,True)
    if var in self._checks:
      self._checks[var].Confirmer=True
      self._checks[var].Update(check, True)
    else:
      self._checks[var] = TChecker(var, val, check, True)
    self._lastVardef = self._checks[var] # Remember for out-of-line check definition

###############################################################################
###############################################################################

ME=TScript()

#ConfigDirectory=ME.Directory / ".." / "conf.d"
#ConfigFile=ConfigDirectory / "config.sh"

gglib=Path("gglib")
# Checr path can be directory or file
checkerPath=Path(ME.Directory if args.checker is None else args.checker)
checkerDir=checkerPath if checkerPath.is_dir() else checkerPath.parent

if args.gglib is not None:
  gglib=Path(args.gglib)

if not gglib.is_absolute(): gglib = gglib.absolute()

cfg = TConfigScript(Path(args.config), checkerPath.absolute(), gglib)
cfg.Make(args.function)

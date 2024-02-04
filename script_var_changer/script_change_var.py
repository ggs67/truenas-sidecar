#!/usr/bin/env python3
from __future__ import annotations
import argparse
import re
import sys
from fnmatch import fnmatch
from pathlib import Path
from typing import List, AnyStr, Dict, Optional

ModificationComment="#<>#"
OmissionComment="#//#"

VERBOSE=False

rxVar="[a-zA-Z_][a-zA-Z0-9]*"

# ...
parser = argparse.ArgumentParser()
parser.add_argument(
    "start",
    nargs=1,
    help="start directory or file"
)
parser.add_argument(
    "vardef",
    nargs="*",
    help="variable change definition"
)
parser.add_argument(
    "-B",
    "--no-backups",
    action="store_true",
    help=f"""skips backup files *.bak, *~ and #*#"""
)
parser.add_argument(
    "-C",
    "--collect",
    action="store_true",
    help=f"""collects all variables"""
)
parser.add_argument(
    "-c",
    "--comment",
    action="store_true",
    help=f"""add comments to each modified line ({ModificationComment}) or potential ommission  ({OmissionComment}))"""
)
parser.add_argument(
    "-i", "--ignore",
    action="append",
    help="ignore given file or directory relative to start"
)
parser.add_argument(
    "-l", "--list",
    action="store",
    help="filename to store modified files"
)
parser.add_argument(
    "-L", "--lines",
    action="store_true",
    help="include script lines with --collect"
)
parser.add_argument(
    "-n", "--name",
    action="append",
    help="only consider matching file names"
)
parser.add_argument(
    "-N", "--not-name",
    action="append",
    help="only consider non-matching file names"
)
parser.add_argument(
    "--var",
    action="append",
    help="only consider matching variable names (regex)"
)
parser.add_argument(
    "--not-var",
    action="append",
    help="only consider non-matching variable names (regex)"
)
parser.add_argument(
    "-v",
    "--verbose",
    action="store_true",
    help="""enable verbose output (default if -x|--exec is omitted"""
)
parser.add_argument(
    "-x",
    "--exec",
    action="store_true",
    help="""this flag is required to perform any changes in the file. Withou\
            t this flag a dry-run is performed"""
)
parser.description="""
vardefs: var_name->new_var_name : var translation
         @vardef-file
"""
args = parser.parse_args()
VERBOSE=args.verbose or not args.exec

#------------------------------------------------------------------------------
def error(msg:AnyStr):
  print(f"ERROR: {msg}")
  sys.exit(1)

#----------------------------------------------------------------------------
def isBashScript(file : Path):
  # Check header in binary mode
  f = open(file, "rb")
  hdr = f.readline(256)
  f.close()
  try:
    hdr = hdr.decode()
  except:
    return False
  if hdr[:3] != "#!/": return False
  if re.search(r"[\s/]bash", hdr) is None: return False
  return True

#----------------------------------------------------------------------------
def parseParameters(line, pos):
  q=None
  inSpace=True
  escape=False
  pars=[]

  start=None

  while pos<len(line):
    c=line[pos]
    p=pos
    pos+=1
    if escape:
      escape=False
      continue

    if c=='\\':
      escape=True
      continue

    if c.isspace():
      if inSpace: continue
      if q is not None: continue
      pars.append([line[start:p], start, p])
      start=None
      inSpace=True
      continue

    if inSpace:
      if c in "&|;":
        pos-=1 # Unwind character
        break # End of command
      inSpace=False
      start=p

    if c in "'\"":
      if q is None:
        q=c
      else:
        if c==q: q=None
      # Note: The closing quote is not necessarly the end of the parameter
      continue

  pos-=1
  if start is not None: pars.append([line[start:pos].strip(), start, len(line)])
  return pars, pos

#-------------------------------------------------------------------------
# line: line
# command: command to be checked
# optdef: "option char or name", in case of name with "-" or "--" as expected
#         single letter options without "-". Note that opny options with srguments must bve specified
#         any unknown option will be treated as flag. This makes it more flexible to command
#         syntax additons
# varargs: once all options have been processed this list guides the variable finding:
#          [[n, v],...]
#
#           n=skip n parameters
#           v=read v variables (-1=all remaining)
#           Default=[[0,1]]
def _findCommandVars(line: str, command: str, optdefs : Dict[str,int]={}, varargs: List[List[int,int]]=[[0,1]]):
  vars = []
  rx=f"([$][(]|[|&;])\s*{command}\s" # There my be other characters than trailing space but then the command is not relevant anywway

  # check option types:
  longopts=False
  longnormal=True
  for opt in optdefs:
    if len(opt)>1:
      if opt[0] != "-": raise RuntimeError("BUG: long options must be given with hyphen(s)")
      longnormal = (longnormal and (opt[:2]=="--"))
      longopts=True

  # Now process command
  line=";"+line
  pos=-1
  for cmd in re.finditer(rx,line):
    p=cmd.end(0)
    if cmd.start(0) < pos:
      # Prevent overlapping matches
      pos=p
      continue

    pars,pos=parseParameters(line, p)
    pos =p if len(pars)==0 else pars[-1][2]
    idx=0
    while idx < len(pars):
      pardef=pars[idx]
      par=pardef[0]
      idx+=1
      if par == "--": break # End of options
      if par[0]!="-":
        idx-=1 # Pointer back to this paramater
        break
      # Here we have an option
      m=re.fullmatch("([-]+)([^\s=]+)", par)
      dash=m.group(1)
      opt=m.group(2)
      if len(par)==2:
        if opt in optdefs:
          idx+=optdefs[opt] # Skip parameters
      else:
        if dash=="--":
          if par in optdefs: idx+=optdefs[opt]
        else:
          assert dash=="-", "EROOR: unexpected dash count"
          if longnormal:
            ## So long is with -- so this should be multiplke short options
            skip=0
            for o in opt:
              if o in optdefs: skip+=optdefs[o]
            idx+=skip
          else:
            # logg also with one dash '-' (like 'find' command)
            if opt in optdefs: idx+=optdefs[opt]

    for vararg in varargs:
      idx+=vararg[0]
      count=vararg[1]
      # Checking count't equality against 0 implicitly renders negative numbers endless
      while count!=0:
        if idx >= len(pars): break # End of command
        count-=1
        pardef=pars[idx]
        idx+=1
        par=pardef[0]
        m=re.fullmatch(rxVar, par)
        if m is not None:
          # Valid variable name
          vars.append(TVar(par, pardef[1]-1, pardef[2]-1, False, False)) # -1 to account for the prepended ';' at parsing
        else:
          break # Whenever we do not get a variable as expected, we abort

  return vars

#----------------------------------------------------------------------------
def _findDeclaredVars(line, word):
  vars=[]

  rxVar="[a-zA-Z_][a-zA-Z0-9_]*"

  regex=f"([|;&]\s*){word}(?P<opts>(?:\s+[-][^\s]+)*)"
  line=";"+line
  for decl in re.finditer(regex,line):
    opts = decl.group("opts")
    pos=decl.end(0) # Where to start findiong variables
    while True:
      part=line[pos:]
      var=re.match(f"\\s*({rxVar})", part)
      if var is None:
        # Check for valid end of expression
        check=re.match(r"\s*", part)
        if check is None: check=re.match(r"\s*[&|;]")
        assert check is not None, f"BUG: unexpected declaration end in '{line}'"
        break
      else:
        s=pos+var.start(1)
        e=pos+var.end(1)
        readonly=(opts.find("r") >= 0)
        local=(word=="local" or (opts.find("g")<0 and opts.find("x")<0))
        vars.append(TVar(var.group(1), s-1, e-1, readonly, local)) # -1 for prepended ';'
        pos=e
        if pos<len(line) and line[pos]== "=":
          pos+=1
          # now skip assignment
          q=None
          parens=0
          escape=False
          while pos<len(line):
            c=line[pos]
            pos+=1
            if escape:
              escape=False
              continue

            if c=='\\':
              escape=True
              continue
            if q is None:
              if c in "'\"":
                q=c
                continue
              elif c=="(":
                parens+=1
                continue
              elif c==")":
                parens-=1
                continue
              elif c.isspace() and parens==0:
                break
            else:
              if c==q:
                q=None
                continue


  return vars

#----------------------------------------------------------------------------
def _findExpressionVars(line : str):
  vars=[]
  rxVar="[a-zA-Z_][a-zA-Z0-9_]*"
  e=0
  line=line+" " # Make sure we get expression at EOL
  for ex in re.finditer(r"[$][(][(]", line):
     s=ex.start(0)
     if s<e:
       raise RuntimeError("BUG: we do not expect nested expressions (error in script?)")

     e=s+3
     p=2
     while e < len(line) and p>0:
       c=line[e]
       if c=='(': p+=1
       if c==')': p-=1
       e+=1

     if e < len(line):
       expr=line[s:e]
       for vm in re.finditer(rxVar,expr):
         vo=TVar(vm.group(0),s+vm.start(0), s+vm.end(0), False, False)
         vars.append(vo)
         vo.Verify(line)
     else:
       raise RuntimeError(f"ERROR: do not find end of expression in '{line[s:]}'")

  return vars


#----------------------------------------------------------------------------
def _findVars(line, pattern):
  vars = []
  for v in re.finditer(pattern, line):
    vo=TVar(v.group("var"), v.start("var"), v.end("var"), False, False)
    vars.append(vo)
    vo.Verify(line)
  return vars


#----------------------------------------------------------------------------
def findVarList(line):
  vlist=[]

  vlist += _findDeclaredVars(line, "declare")
  vlist += _findDeclaredVars(line, "typeset")
  vlist += _findDeclaredVars(line, "local")

  vlist += _findVars(line, r"[$](?P<var>[a-zA-Z_][a-zA-Z0-9_]*)")
  vlist += _findVars(line, r"[$][{](?P<var>[a-zA-Z_][a-zA-Z0-9_]*)")
  vlist += _findVars(line, r"(?P<var>[a-zA-Z_][a-zA-Z0-9_]*)[=]")

  vlist += _findExpressionVars(line)

  vlist += _findCommandVars(line, "read",
                                 { "a": 1, "d": 1, "i":1, "n":1, "N":1, "p":1, "t":1, "u":1 },
                                 [[0,-1]])
  # Filter list for duplicates 8f.ex. "local VAR=value" will be found twice
  #                                    ^^^^^^^^^^^^^^^^.. findDeclareVars
  #                                          ^^^^---_findVars
  vlist2=[]
  for v in vlist:
    for v2 in vlist2:
      if v.Start == v2.Start:
        # duplicate match
        assert v.End == v2.End, "variable assumed to completely overlap"
        break
    else:
      vlist2.append(v)

  return vlist2

#----------------------------------------------------------------------------
def findVars(line):
  vlist = findVarList(line)
  vars={}

  for v in vlist:
    if v.Name in vars:
      vars[v.Name].append(v)
    else:
      vars[v.Name]=[ v ]

  return vars

###############################################################################
class TVar:

  def __init__(self, name: str, start: int, end, readonly, local):
    self.Name=name
    self.Start=start
    self.End=end
    self.ReadOnly=readonly
    self.Local=local

  #----------------------------------------------------------------------------
  def __lt__(self, other):
    if self.Name==other.Name:
      return self.Start < other.Start
    return self.Name < other.Name

  #----------------------------------------------------------------------------
  def Verify(self, line):
    v=line[self.Start: self.End]
    assert v==self.Name

  def Update(self, v:TVar):
    self.ReadOnly = self.ReadOnly | v.ReadOnly
    self.Local = self.Local | v.Local

###############################################################################
class TLine:

  def __init__(self, script: TScript, lnum: int, line: str, vars : List[str, TVar]=[]):
    self.LineNumber=lnum
    self.Line=line
    self.Variables : Dict[str, TVar] ={}
    self.Script=script
    self.AddVars(vars)
    self.NewLine = None
    self.Omissions = None
    self.Comments=None

  def __lt__(self, other:TLine):
    return self.LineNumber < other.LineNumber

  #----------------------------------------------------------------------------
  def hasVariables(self):
    return len(self.Variables) > 0

  #----------------------------------------------------------------------------
  def hasOmmissions(self):
    if self.Omissions is None: return False
    return len(self.Omissions) > 0

  #----------------------------------------------------------------------------
  def _getComments(self, idx: int):
    if self.Comments is None:
      self.Comments=[ [], [] ]

    return self.Comments[idx]

  #----------------------------------------------------------------------------
  def AddPreComment(self, cmt: str):
    self._getComments(0).append(cmt)

  #----------------------------------------------------------------------------
  def AddPostComment(self, cmt: str):
    self._getComments(1).append(cmt)

  #----------------------------------------------------------------------------
  def ChangeVars(self, vardefs : TVarList):
    ofs=0
    pos=-1
    line=self.Line
    changes=0

    # extract all vars first, so that we can sort by position
    vars = sorted([ v for vl in self.Variables.values() for v in vl ], key=lambda x : x.Start)

    for v in vars:
      assert vardefs.isKnown(v.Name), "BUG: we assume variables to have been cleaned-up before change"
      vd=vardefs.Find(v.Name)
      if vd is None: continue # May still not be a vardef, as known variables can be new names as well
      if not vd.isActive(): continue
      s=v.Start+ofs
      e=v.End+ofs
      assert s > pos, "BUG: we assume variables to be sorted by position"
      changes+=1
      line=line[:s]+vd.NewName+line[e:]
      ofs+=len(vd.NewName)-len(vd.OriginalName)
      pos=e

    if changes>0: self.NewLine = line
    return changes

  #----------------------------------------------------------------------------
  def GetActiveLine(self):
    return self.Line if self.NewLine is None else self.NewLine

  #----------------------------------------------------------------------------
  def CheckOmissions(self, vardefs: TVarList) -> List:
    line = self.GetActiveLine()  # Use active line (i.e. modified if so)
    found = []
    for vd in vardefs.VarDefDB.values():
      if not vd.isActive(): continue # Only active variables
      f=self._findVar(line, vd.OriginalName) # Find all possible occurences
      if vd.OriginalName in self.Variables and len(f)>0:
        # If we have possibe ommissions while we also have this variable
        # in the colectors list, we need to cleanup the found list
        f = [ x for x in f if not any(xx.Start == x[0] for xx in self.Variables[x[2]] ) ]
      found = found + f

    self.Omissions = None if len(found)==0 else found
    return found


  #----------------------------------------------------------------------------
  def _findVar(self, line: str, var: str):
    found=[]
    l=len(var)
    p=0
    while (p := line.find(var,p)) >= 0:
      vs=p
      ve=vs + l
      p += l # Advance already
      if vs > 0 and TVarDef.isValidVarChar(line[vs-1]): continue
      if ve < len(line) and TVarDef.isValidVarChar(line[ve]): continue
      found.append([vs,ve,var])
    return found

  #----------------------------------------------------------------------------
  def _purgeVar(self, v:str) -> int:
    del self.Variables[v]
    return len(self.Variables)

  #----------------------------------------------------------------------------
  def AddVars(self, vars: List[TVar]):
    for var in vars:
      self.AddVar(var)

  #----------------------------------------------------------------------------
  def AddVar(self, var: TVar):
    if var.Name in self.Variables:
      self.Variables[var.Name].append(var)
    else:
      self.Variables[var.Name]=[ var ]

###############################################################################
class TScript:

  def __init__(self, file: Path):
    self.File=file.absolute()
    self.Lines : List[TLine] = []
    self.Variables : Dict[str, TLine]={}
    self._loaded = False # Loaded means that all lines of the script are loade iun the "Lines" array

  def __lt__(self, other):
    return str(self.File) < str(other.File)

  #----------------------------------------------------------------------------
  def _purgeVar(self,v):
    assert v in self.Variables, "we expect to be called only with valid var"
    lines=self.Variables[v]
    for line in lines:
      if line._purgeVar(v) == 0 and not self._loaded:
        # Line has no vars left
        self.Lines = [ l for l in self.Lines if l.LineNumber != line.LineNumber ]

    del self.Variables[v]

    return len(self.Variables)

  #----------------------------------------------------------------------------
  def AddLine(self, line: TLine):
    self.Lines.append(line)
    for vname in line.Variables:
      if vname in self.Variables:
        self.Variables[vname].append(line)
      else:
        self.Variables[vname] = [ line ]

  #----------------------------------------------------------------------------
  def Load(self):
    f = open(self.File, "r")
    lnum=0
    xlines : List[TLine] = self.Lines
    self.Lines = []

    if len(xlines)==0:
      xline : Optional[TLine] = None
    else:
      xline = xlines[0] # Prepare first variable (already known) line
      xlines.pop(0)

    for line in f:
      line=line.rstrip()
      lnum+=1
      if xline is None or lnum < xline.LineNumber:
        # This is a new line
        self.Lines.append(TLine(self, lnum,line))
      else:
        assert lnum == xline.LineNumber, "BUG: line number should match"
        assert xline.Line == line, "BUG: line content should match"
        self.Lines.append(xline) # Add existing line with possible variables
        # Update xline
        xline = None if len(xlines)==0 else xlines[0]
        if xline is not None: xlines.pop(0)

    f.close()

    assert len(xlines)==0, "BUG: xlines should be empty by now"

  #----------------------------------------------------------------------------
  def Unload(self):
    self.Lines = [ l for l in self.Lines if l.hasVariables() or l.hasOmmissions() ]

###############################################################################
class TRegistry:

  def __init__(self):
    self.Scripts=[]
    self.Variables={}

  #----------------------------------------------------------------------------
  def AddScript(self, script: TScript):
    self.Scripts.append(script)
    return self.Scripts[-1]

  #----------------------------------------------------------------------------
  def GetScript(self, path: Path) -> TScript:
    path = path.absolute()
    for script in self.Scripts:
      if path == script.File: return script
    return None

  #----------------------------------------------------------------------------
  def CollectVariables(self):
    self.Variables={}
    script: TScript=None
    for script in self.Scripts:
      for vname in script.Variables:
        if vname in self.Variables:
          self.Variables[vname].append(script)
        else:
          self.Variables[vname]=[ script ]

  #----------------------------------------------------------------------------
  def Cleanup(self, vardefs : TVarList):
    origvars={ vd.OriginalName: 0 for vd in vardefs.VarDefDB.values() if vd.isActive()}
    newvars={ vd.NewName: 0 for vd in vardefs.VarDefDB.values() if vd.isActive() }
    chains= { vd.OriginalName: 0 for vd in vardefs.VarDefDB.values() if vd.OriginalName in newvars }

    # A chained variable is a group of at least 2 renaming definitions where the new variable name
    # of one is the original name of the other
    assert len(chains)==0, f"BUG: found chained variable(s): {','.join(chains)}"

    vlist = list(self.Variables.keys()) # Pass through list as current variable may get deleted from dictionary
    for v in vlist:
      if v in origvars: continue
      if v in newvars: continue
      self._purgeVar(v)

  #----------------------------------------------------------------------------
  def _purgeVar(self, v:str):
    if v not in self.Variables: return
    scripts=self.Variables[v]
    i=0
    while i<len(scripts):
      script=scripts[i]
      i+=1
      if script._purgeVar(v)==0:
       i-=1
       del scripts[i]
    del self.Variables[v]

###############################################################################
class TVarDef:
  _rx_valid_varchars1=r"[a-zA-Z_]"
  _rx_valid_varchars=r"[a-zA-Z0-9_]"
  _rx_var=f"{_rx_valid_varchars1}{_rx_valid_varchars}*"
  def __init__(self,vardef):
    self.Parse(vardef)

  #------------------------------------------------------------------------------
  def Parse(self,vardef):
    m=re.fullmatch(f"({self._rx_var})[-][>]({self._rx_var})?", vardef, re.IGNORECASE)
    assert m is not None, f"invalid vardef '{vardef}'"
    self.OriginalName=m.group(1)
    self.NewName=m.group(2)
    # Special case (place holder), i.e no change for now, but max be change later
    # This allows the user to provide the vardef, eventhough not yet used (i.e. not changed yet)
    if self.NewName is not None and self.NewName == self.OriginalName: self.NewName=None

  #----------------------------------------------------------------------------
  def isActive(self):
    return self.NewName is not None

  #------------------------------------------------------------------------------
  def isValidVar(var):
    m=re.fullmatch(TVarDef._rx_var, var)
    return m is not None

  #------------------------------------------------------------------------------
  def isValidVarChar(varchar):
    assert len(varchar)==1,"expect single char"
    m=re.fullmatch(TVarDef._rx_valid_varchars, varchar)
    return m is not None

###############################################################################
class TVarList:

  def __init__(self, vardefs : List[str]):
    self.VarDefDB : Dict[str,TVarDef]={}
    self.NewVarsDB : Dict[str,TVarDef]={}
    self.AddVardefs(vardefs)

  #----------------------------------------------------------------------------
  def AddVardefs(self, iter, path:Path=None):
    for vd in iter:
      vd=vd.strip()
      if vd=="": continue
      if vd[0]=="@":
        vd=vd[1:].strip()
        p = Path(vd) if path is None else path.absolute().parent.joinpath(vd)
        vdf = open(vd, "r")
        self.AddVardefs(vdf, p)
        vdf.close()
      else:
        self.Add(TVarDef(vd))


  #------------------------------------------------------------------------------
  def Add(self, vardef : TVarDef):
    if vardef.OriginalName in self.VarDefDB:
      assert self.VarDefDB[vardef.OriginalName].NewName == vardef.NewName, f"ERROR: duplicate vardef for original name '{vardef.OriginalName}' while new name missmatches ('{self.VarDefDB[vardef.OriginalName].NewName}' & '{vardef.NewName}')"
    else:
      self.VarDefDB[vardef.OriginalName] = vardef

    if vardef.NewName is not None:
      if vardef.NewName in self.NewVarsDB:
        assert self.NewVarsDB[vardef.NewName].OriginalName == vardef.OriginalName, f"ERROR: duplicate vardef for new name '{vardef.NewName}' while original name missmatches ('{self.VarDefDB[vardef.NewName].OriginalName}' & '{vardef.OriginalName}')"
      else:
        self.NewVarsDB[vardef.NewName] = vardef

  #------------------------------------------------------------------------------
  def Find(self, var : str) -> TVarDef:
    return self.VarDefDB.get(var)

  def FindNew(self, var : str) -> TVarDef:
    return self.NewVarsDB.get(var)

  #----------------------------------------------------------------------------
  def isKnown(self, var : str):
    return self.Find(var) is not None or self.FindNew(var) is not None

###############################################################################
class TVarCollector:

  def __init__(self, script:TScript):
    self._script=script
    self._file=None
    self._vars={}

  def Close(self):
    if self._file is None: return
    self._file.close()
    self._file=None

  def Collect(self) -> Optional[TScript]:
    global VERBOSE

    self._vars={}

    path=self._script.File
    if not isBashScript(path): return None

    print(f"processing {str(path)}")
    self._file=open(path,"r")

    lnum=0
    for line in self._file:
      lnum+=1
      line=line.rstrip()
      vars=self._processLine(line)
      if len(vars)==0: continue
      self._script.AddLine(TLine(self._script, lnum, line, vars))

    self.Close()

    return self._script

  #----------------------------------------------------------------------------
  def _processLine(self,line):
    # We ignore any comment line previously added by this tool
    l=line.strip()
    if l[:len(ModificationComment)] == ModificationComment: return []
    if l[:len(OmissionComment)] == OmissionComment: return []

    vars = findVarList(line)
    return vars

###############################################################################
class TVarChanger:

  def __init__(self, registry: TRegistry, path:Path, vardefs:TVarList):
    self._path=path
    self._vardefs=vardefs
    self._registry=registry
    self._file=None

  #------------------------------------------------------------------------------
  def _identify(self):
    if not self._identified:
      self._identified=True
      print("")
      print( "###############################################################################")
      print(f" {str(self._path)}")
      print( "###############################################################################")
      print("")
      return True
    return False

  #------------------------------------------------------------------------------
  def _print_change(self, line: TLine):
    if line.NewLine is None: return
    if not self._identify():
      print( "-------------------------------------------------------------------------------")
      print(f"")

    print(f"Line {line.LineNumber}:")
    print(f"  OLD: {line.Line}")
    print(f"  NEW: {line.NewLine}")
    print("")

  #------------------------------------------------------------------------------
  def Close(self):
    if self._file is None: return
    self._file.close()
    self._file=None

  #----------------------------------------------------------------------------
  def _writeChanges(self, comments:bool):
    global args

    backup=Path(str(self._path)+".bak")
    self._path.rename(backup)

    print(f"  updating {str(self._path)}...")
    f=open(self._path,"w")

    for L in self._lines:
      if comments:
        # Add comment with original line above change
        if L[1] is not None: f.write(ModificationComment+" "+L[1]+"\n")
      f.write(L[0]+'\n')
      if comments and len(L)>2:
        for LL in L[2:]:
          f.write(LL+'\n') # These lines have already comment marks

    f.close()

  def Do(self, exec=False):
    global VERBOSE

    self._lines=[]
    self._identified = False

    script = self._registry.GetScript(self._path)
    if script is None: return 0,0

    print(f"processing {str(self._path)}")
    script.Load() # Load complete script

    changes=0
    lnum= -1
    for line in script.Lines:
      assert line.LineNumber > lnum, "BUG: we assume lines to be sorted"
      changed=self._processLine(line)
      if changed > 0:
        if VERBOSE: self._print_change(line)
        self._lines.append(line)
        changes+=changed

    # Check for potential omissions
    reported=False
    unchanges=0
    for L in script.Lines:
      if not L.hasOmmissions(): continue
      found = L.Omissions
      if VERBOSE:
        if not reported:
          self._identify()
          print("")
          print("Possible omissions:")
          print("===================")
          reported=True
        print("")
        print(f"in line: {L.LineNumber}")
        print(f"         {L.GetActiveLine()}")
        for f in found:
          vs=f[0] ; ve=f[1] ; v=f[2]
          print(((vs+9)*" ")+((ve-vs)*"^")+"---" + v + "->" + self._vardefs.Find(v).NewName )
      if args.comment:
        for f in found:
          unchanges += 1 # Only counted if comments are enabled
          vs=f[0] ; ve=f[1] ; v=f[2]
          cmt= (vs*" ")+((ve-vs)*"^")+"----"+v
          cmt="#//#" + cmt[4:] # Need to insert comment even if variable at BOL
          L.AddPostComment(cmt)

    if exec:
      if changes>0 or (unchanges>0 and args.comment): self._writeChanges(args.comment)

    script.Unload()

    return changes,unchanges

  #----------------------------------------------------------------------------
  def _replace(self, line, regex, newName):
    m=re.search(regex, line)
    if m is None: return False, line
    # part of longer variable ?
    g=m.group("var")
    start=m.start("var")
    end=m.end("var")
    if start > 0 and TVarDef.isValidVarChar(line[start-1]): return False,line
    if end < len(line) and TVarDef.isValidVarChar(line[end]): return False,line

    line=line[:m.start("var")] + newName + line[m.end("var"):]
    return True, line

  #----------------------------------------------------------------------------
  def _processLine(self,lineInfo:TLine) -> int:
    line=lineInfo.Line

    if len(lineInfo.Variables)==0:
      # Script line without detected variables
      lineInfo.CheckOmissions(self._vardefs)
      return 0

    # We ignore any comment line previously added by this tool
    l=line.strip()
    if l[:len(ModificationComment)] == ModificationComment: return 0
    if l[:len(OmissionComment)] == OmissionComment: return 0

    found = lineInfo.ChangeVars(self._vardefs)
    lineInfo.CheckOmissions(self._vardefs)
    return found

###############################################################################
class TVarChangeManager:
  MODE_CHANGE=1
  MODE_COLLECT=2

  def __init__(self, start : Path, vardefs : List[str], ignoreList: List[AnyStr], exec:bool=False):
    self._start = start.absolute()
    self._vardefs = TVarList(vardefs)
    self._exec=exec
    self._ignoreList=[]
    self.ModifiedFiles=[]
    if ignoreList is not None:
      for p in ignoreList:
        p=Path(p)
        if not p.is_absolute(): p = self._start / p
        self._ignoreList.append(p)

  #------------------------------------------------------------------------------
  def _Start(self, mode):
    if not self._start.exists(): error(f"start path '{str(self._start)}' does not exist")

    if self._start.is_dir():
      self._startDir(self._start, mode)
    else:
      self._startFile(self._start, mode)

  #----------------------------------------------------------------------------
  def _ReportWarnings(self):
    for vd in self._vardefs.VarDefDB.values():
      if vd.NewName in self.Registry.Variables and vd.OriginalName in self.Registry.Variables:
        print("")
        print(f"WARNING: variable '{vd.NewName}' already found for {vd.OriginalName}->{vd.NewName}")
        print(f"         while {vd.OriginalName} is still present")

  #----------------------------------------------------------------------------
  def StartChange(self):
    # We first run the collector to get all variables. This is required to be able to
    # identifying existing name collisions through all files.
    # A name collision occurs if any file still contains a variable to be change while
    # its new name als already exists somewhere.
    self.StartCollect()
    self.Registry.Cleanup(self._vardefs)

    self.ModifiedFiles=[]
    self._Start(self.MODE_CHANGE)
    self._ReportWarnings()

  #----------------------------------------------------------------------------
  def StartCollect(self):
    self.Registry=TRegistry()
    self._Start(self.MODE_COLLECT)

    # Now collect all variables
    self.Registry.CollectVariables()

  #------------------------------------------------------------------------------
  def _startFile(self, file : Path, mode : int):
    global args

    # Filtered file ?
    # --no-backups
    if args.no_backups:
      p=str(file)
      if p[-1]=='~': return
      if p[-4:]==".bak": return
      if file.name[0]=="#" and p[-1]=="#": return

    # --name
    fn = file.name
    if args.name is not None and len(args.name)>0:
      for n in args.name:
        if fnmatch(fn, n): break
      else:
        return

    # --not-name
    if args.not_name is not None and len(args.not_name)>0:
      for n in args.not_name:
        if fnmatch(fn, n): return

    if mode == self.MODE_CHANGE:
      changer = TVarChanger(self.Registry, file, self._vardefs)
      changes,unchanges = changer.Do(self._exec)
      if changes>0 or (unchanges > 0 and args.comment):
        self.ModifiedFiles.append([file, changes, unchanges])
    else:
      collector = TVarCollector(TScript(file))
      script = collector.Collect() # Retuirns None if file is not a valid script
      if script is not None: self.Registry.AddScript(script)

  #------------------------------------------------------------------------------
  def _startDir(self, dir, mode: int):
    for p in dir.iterdir():
      # Should be ignored ?
      for ip in self._ignoreList:
        if p==ip: break
      else:
        ip=""
      if p==ip:
        print(f"{p} ignored")
        continue

      if p.is_file():
        self._startFile(p, mode)
      elif p.is_dir():
        self._startDir(p, mode)

if args.collect:
  vcm = TVarChangeManager(Path(args.start[0]), [], args.ignore, False)
  vcm.StartCollect()
  reg=vcm.Registry

  for vname in sorted(reg.Variables):

    # Filter variable names (if requested by --var or --not-var
    if args.var is not None and len(args.var)>0:
      for n in args.var:
        if re.fullmatch(n,vname) is not None: break
      else:
        continue

    if args.not_var is not None and len(args.not_var)>0:
      found=False
      for n in args.not_var:
        if re.fullmatch(n,vname) is not None:
          found=True
          break
        if found: continue

    if args.lines:
      print("---------------------------------------------------------------------------------")
    print(vname)
    script: TScript = None
    for script in sorted(reg.Variables[vname]):
      print(f"  {str(script.File)}")
      if args.lines:
        lines=sorted(script.Variables[vname])
        line: TLine = None
        for line in lines:
          print(f"  {line.LineNumber:5d}: {line.Line}")
          poslist=sorted(line.Variables[vname])
          v : TVar
          ps="         "
          p=0
          for v in poslist:
            s=v.Start
            e=v.End
            if s>p: ps+=(s-p)*' '
            ps+=(e-s)*'^'
            p=e
          print(ps)

  sys.exit(0)

if len(args.vardef)==0:
  print("ERROR: need at least one vardef")
  sys.exit(1)

vcm = TVarChangeManager(Path(args.start[0]), args.vardef, args.ignore, args.exec)

vcm.StartChange()

if args.list is not None:
  list_file_path=Path(args.list).absolute()
  list_file = open(list_file_path,"w")
  list_file.write("changes misses file\n")
  list_file.write("----------------------------------------------------------------------------------------\n")

  for mf in vcm.ModifiedFiles:
    list_file.write(f"{mf[1]:^7d} {mf[2]:^6d} {mf[0]}\n")

  list_file.close()
  print(f"list of modified files written to {str(list_file_path)}")

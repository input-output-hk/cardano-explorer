import re
import subprocess
import json

buffer = open("cabal.project").read()

# match looks like this:

# source-repository-package
#  type: git
#  location: https://github.com/input-output-hk/iohk-monitoring-framework
#  tag: d5eb7ee92f0974aed5ac4a57a9bf5697ec065b7d
#  subdir: iohk-monitoring

# subdir is optional, so is a --sha256 comment

pattern = r'source-repository-package.*\n' \
        + r'(?P<pad> .*)type: git.*\n' \
        + r'\1location: (?P<loc>[^ \n]+).*\n' \
        + r'\1tag: (?P<tag>[^ \n]+).*\n' \
        + r'(?P<subdir>\1subdir: [^ \n]+\n){0,1}' \
        + r'(\1--sha256:.*\n){0,1}'
# ( .*--sha256:.*\n){0,1}"""

def repl(match):
  dict = match.groupdict()
  if not dict["subdir"]:
    dict["subdir"] = ''
  prefetchJSON = subprocess.run(
     ["nix-prefetch-git", "--quiet", dict['loc'], dict['tag']],
     capture_output=True, check=True).stdout
  sha256 = json.loads(prefetchJSON)["sha256"]
  return """source-repository-package
{pad}type: git
{pad}location: {loc}
{pad}tag: {tag}
{subdir}{pad}--sha256: {sha256}
""".format(**{**dict, **{"sha256": sha256}})

f = open("cabal.project",'w')
f.write(re.sub(pattern, repl, buffer, flags = re.I + re.M))
f.close()

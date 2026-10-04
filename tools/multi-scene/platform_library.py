"""Source/object/link/library joins shared by the platform build consumer."""
from pathlib import Path
import json
import plistlib
import shlex
import struct
import platform_context as context


def library_report(inputs,root,cwd,drivers,lists,other,products,lines,platform,targets=None):
    """Inspect object, binary and linker evidence independently for every target."""
    profile=context.PLATFORMS[platform];result=[]
    other={r['target']:r for r in other};products={Path(r['path']).stem:r for r in products};inventory={r['target']:r for r in lists}
    issues=[]
    for target in targets or inventory:
        parts={};faults=[]
        def inspect(phase,fn):
            try:parts[phase]=fn()
            except (AssertionError,ValueError,OSError,KeyError,TypeError,IndexError,struct.error) as error:
                faults.append(dict(target=target,phase=phase,detail=str(error) or type(error).__name__))
        base=root/'derived-data/Build/Products'/profile['products']/(target+'.framework')
        binary=(base/target).resolve();info=(base/('Resources/Info.plist' if profile['versioned'] else 'Info.plist')).resolve()
        def objects():
            row=inventory[target]
            return object_context(inputs,root,cwd,drivers[target],row,other[target])
        def observed_binary():
            if target not in products:raise ValueError('qualified product inventory missing')
            observed=context.binary_context(inputs.read(inputs.capture(binary)),plistlib.loads(inputs.read(inputs.capture(info))),platform)
            return dict(binary=inputs.capture(binary),info_plist=inputs.capture(info),binary_context=observed)
        def observed_linker():
            return linker_context(lines,target,binary,other.get(target,{}).get('link_file_list'),profile)
        inspect('objects',objects);inspect('binary',observed_binary);inspect('linker',observed_linker)
        issues.extend(faults)
        if not faults:result.append(dict(target=target,**parts['objects'],**parts['binary'],linker=parts['linker']))
    return dict(rows=result,issues=issues)


def object_context(inputs,root,cwd,drivers,row,other):
    target=row['target'];maps={r['arguments'][r['arguments'].index('-output-file-map')+1] for r in drivers}
    if len(maps)!=1:raise ValueError('ambiguous output map: '+target)
    path=Path(maps.pop())
    if not path.is_relative_to(root/'derived-data') or path.is_symlink():raise ValueError('foreign output map')
    mapping=json.loads(inputs.read(inputs.capture(path)));expected={str(cwd/m['path']) for m in row['members']}
    if set(mapping)!=expected|{''}:raise ValueError('Swift output membership differs')
    objects=[Path(mapping[k]['object']) for k in sorted(expected)]
    if len(objects)!=len(set(objects)) or not all(p.is_relative_to(root/'derived-data') and p.resolve()==p and p.is_file() for p in objects):
        raise ValueError('Swift object inventory differs')
    object_refs=[inputs.capture(p) for p in objects];extra=other['compilations']+other['generated_compilations']
    wanted={str(p) for p in objects}|{r['object']['path'] for r in extra}
    link=other['link_file_list'];actual=inputs.read(link).decode().splitlines()
    if len(actual)!=len(set(actual)) or set(actual)!=wanted:raise ValueError('complete link inventory differs')
    return dict(output_map=inputs.capture(path),swift_objects=object_refs,complete_link_count=len(actual),link_file_list=link)


def linker_context(lines,target,binary,link,profile):
    linker=[];issues=[]
    for line in lines:
        if '/clang ' not in line or ' -dynamiclib ' not in line:continue
        tokens=shlex.split(line)
        if '-o' not in tokens or Path(tokens[tokens.index('-o')+1])!=binary:continue
        def value(flag):
            if tokens.count(flag)!=1 or tokens.index(flag)+1>=len(tokens):
                issues.append('missing/duplicate linker '+flag);return None
            return tokens[tokens.index(flag)+1]
        if tokens[0]!=context.TOOLCHAIN+'clang':issues.append('foreign linker')
        if value('-target') not in profile['link_targets']:issues.append('linker target differs')
        if value('-isysroot')!=context.sdk_path(profile):issues.append('linker SDK differs')
        if link is None or value('-filelist')!=link['path']:issues.append('linker object list differs or unavailable')
        install='@rpath/'+target+'.framework/'+('Versions/A/' if profile['versioned'] else '')+target
        if value('-install_name')!=install:issues.append('library install name differs')
        linker.append(dict(command=line,arguments=tokens))
    if len(linker)!=1:issues.append('missing/duplicate actual library linker')
    if issues:raise ValueError(target+': '+'; '.join(issues))
    return linker[0]


def library_context(*args,**kwargs):
    report=library_report(*args,**kwargs)
    if report['issues']:raise ValueError('; '.join(r['target']+': '+r['phase']+': '+r['detail'] for r in report['issues']))
    return report['rows']

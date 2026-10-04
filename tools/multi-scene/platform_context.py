"""Shared actual compiler/library context for finite platform qualification.

Compiler aliases and forwarded Clang flags are parsed by role. Nominal target
and actual binary minimum remain separate, especially for watchOS arm64.
"""
import hashlib
import json
from pathlib import Path
import shlex
import struct

TOOLCHAIN='/Applications/Xcode_27.1.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/'
PLATFORMS={
    'macos':dict(sdk='macosx',destination='macOS',sdk_path='MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk',
                 targets=['arm64-apple-macos12.0','arm64-apple-macosx12.0'],link_targets=['arm64-apple-macos12.0','arm64-apple-macosx12.0'],
                 products='Debug',platform=1,nominal='12.0',minimum=0xc0000,info_minimum='LSMinimumSystemVersion',versioned=True),
    'tvos':dict(sdk='appletvos',destination='tvOS',sdk_path='AppleTVOS.platform/Developer/SDKs/AppleTVOS27.0.sdk',
                targets=['arm64-apple-tvos15.0'],link_targets=['arm64-apple-tvos15.0'],
                products='Debug-appletvos',platform=3,nominal='15.0',minimum=0xf0000,info_minimum='MinimumOSVersion',versioned=False),
    'watchos':dict(sdk='watchos',destination='watchOS',sdk_path='WatchOS.platform/Developer/SDKs/WatchOS27.0.sdk',
                   targets=['arm64-apple-watchos9.0'],link_targets=['arm64-apple-watchos9.0'],
                   products='Debug-watchos',platform=4,nominal='9.0',minimum=0x1a0000,info_minimum='MinimumOSVersion',versioned=False),
    'visionos':dict(sdk='xros',destination='visionOS',sdk_path='XROS.platform/Developer/SDKs/XROS27.0.sdk',
                    targets=['arm64-apple-xros1.0'],link_targets=['arm64-apple-xros1.0'],
                    products='Debug-xros',platform=11,nominal='1.0',minimum=0x10000,info_minimum='MinimumOSVersion',versioned=False),
}


def sdk_path(profile):
    return '/Applications/Xcode_27.1.app/Contents/Developer/Platforms/'+profile['sdk_path']


def scan_compilers(lines, expected_targets, lists, platform, *, read_bytes=None):
    """Return all independent row failures in one pass over actual output."""
    profile=PLATFORMS[platform];result={target:[] for target in expected_targets};issues=[]
    inventory={r['target']:r for r in lists}
    if set(inventory)!=set(result) or len(inventory)!=len(lists):issues.append('source target inventory differs')
    def local_bytes(path):
        path=Path(path)
        if not path.is_file() or path.is_symlink():raise OSError('missing or redirected source response')
        return path.read_bytes()
    read_bytes=read_bytes or local_bytes
    for line in lines:
        if 'swiftc -module-name ' not in line:continue
        try:tokens=shlex.split(line.strip())
        except ValueError:issues.append('unparseable compiler command');continue
        positions=[i for i,t in enumerate(tokens) if t.endswith('/swiftc')]
        if len(positions)!=1:issues.append('ambiguous compiler driver');continue
        tokens=tokens[positions[0]:]
        def value(flag):
            if tokens.count(flag)!=1 or tokens.index(flag)+1>=len(tokens):
                issues.append('missing/duplicate compiler '+flag);return None
            return tokens[tokens.index(flag)+1]
        name=value('-module-name')
        if name not in result:continue
        prefix=name+': '
        if tokens[0]!=TOOLCHAIN+'swiftc':issues.append(prefix+'foreign compiler')
        if value('-target') not in profile['targets']:issues.append(prefix+'compiler target differs')
        if value('-sdk')!=sdk_path(profile):issues.append(prefix+'compiler SDK differs')
        if value('-swift-version')!='5':issues.append(prefix+'Swift language mode differs')
        for flag in ('-Onone','-enable-testing'):
            if tokens.count(flag)!=1:issues.append(prefix+'missing/duplicate '+flag)
        outer=[];i=0
        while i<len(tokens):
            if tokens[i]=='-Xcc':
                if i+1>=len(tokens):issues.append(prefix+'missing forwarded Clang argument')
                i+=2
            else:outer.append(tokens[i]);i+=1
        defines=[]
        for i,t in enumerate(outer):
            if t=='-D':defines.append(outer[i+1] if i+1<len(outer) else None)
            elif t.startswith('-D'):defines.append(t[2:])
        if defines!=['DEBUG']:issues.append(prefix+'shipping compilation conditions differ')
        responses=[t[1:] for t in tokens if t.startswith('@')];binding=inventory.get(name,{}).get('list')
        if binding is None or responses!=[binding['path']]:issues.append(prefix+'source response binding differs')
        else:
            try:
                if hashlib.sha256(read_bytes(binding['path'])).hexdigest()!=binding['sha256']:issues.append(prefix+'source response bytes changed')
            except (OSError,KeyError):issues.append(prefix+'source response unavailable')
        result[name].append(dict(command=line,arguments=tokens,source_list=binding))
    for name,rows in result.items():
        if not rows:issues.append(name+': no actual compiler driver')
    return dict(rows=result,issues=issues)


def compiler_rows(lines, expected_targets, lists, platform):
    report=scan_compilers(lines,expected_targets,lists,platform)
    if report['issues']:raise ValueError('; '.join(report['issues']))
    return report['rows']


def binary_context(raw,info,platform):
    profile=PLATFORMS[platform]
    if len(raw)<32:raise ValueError('truncated MachO header')
    magic,cpu,subtype,kind,count,size,flags,reserved=struct.unpack('<8I',raw[:32])
    if (magic,cpu,kind)!=(0xfeedfacf,0x100000c,6) or 32+size>len(raw):raise ValueError('invalid arm64 library')
    pos=32;versions=[]
    for _ in range(count):
        if pos+8>32+size:raise ValueError('truncated load command')
        cmd,length=struct.unpack('<II',raw[pos:pos+8])
        if length<8 or pos+length>32+size:raise ValueError('invalid load command length')
        if cmd==0x32:
            if length<24:raise ValueError('truncated version command')
            target,minimum,sdk,tools=struct.unpack('<4I',raw[pos+8:pos+24])
            if length!=24+tools*8:raise ValueError('invalid version tools')
            versions.append(dict(platform=target,minimum=minimum,sdk=sdk))
        pos+=length
    expected=dict(platform=profile['platform'],minimum=profile['minimum'],sdk=0x1b0000)
    if pos!=32+size or versions!=[expected]:raise ValueError('actual library platform/minimum/SDK differs')
    if info['CFBundlePackageType']!='FMWK' or info['DTPlatformName']!=profile['sdk'] or info[profile['info_minimum']]!=profile['nominal']:
        raise ValueError('nominal framework metadata differs')
    return dict(architecture='arm64',filetype='MH_DYLIB',build_version=versions[0],nominal_minimum=profile['nominal'],
        distribution_limit='arm64 binary minimum26; no watchOS9 distribution/runtime proof' if platform=='watchos' else 'compile-only; no runtime proof')

"""Source-bound simulator entitlement and signing-only link transitions."""
import plistlib
import struct
from pathlib import Path


def macho_section(raw, wanted):
    """Read one actual __TEXT section from the thin arm64 simulator executable."""
    assert len(raw) >= 32 and raw[:4] == bytes.fromhex('cffaedfe'), 'Expected thin little-endian Mach-O 64'
    commands, size = struct.unpack_from('<II', raw, 16)
    end, offset, found = 32 + size, 32, []
    assert end <= len(raw)
    for _ in range(commands):
        assert offset + 8 <= end
        command, length = struct.unpack_from('<II', raw, offset)
        assert length >= 8 and offset + length <= end
        if command == 0x19:
            assert length >= 72
            sections = struct.unpack_from('<I', raw, offset + 64)[0]
            assert length == 72 + sections * 80
            for index in range(sections):
                section = offset + 72 + index * 80
                name = raw[section:section + 16].rstrip(b'\0')
                segment = raw[section + 16:section + 32].rstrip(b'\0')
                if (segment, name) == (b'__TEXT', wanted):
                    count, position = struct.unpack_from('<QI', raw, section + 40)
                    assert position + count <= len(raw)
                    found.append(raw[position:position + count])
        offset += length
    assert offset == end and len(found) <= 1, 'Ambiguous or invalid entitlement section'
    return found[0] if found else None


def entitlement_section(raw):
    value=macho_section(raw,b'__entitlements')
    return plistlib.loads(value.rstrip(b'\0')) if value is not None else None


def packaged_entitlements(binary, xml, der):
    actual=entitlement_section(binary)
    assert actual == plistlib.loads(xml), 'Linked simulator XML entitlement mismatch'
    assert macho_section(binary,b'__ents_der') == der, 'Linked simulator DER entitlement mismatch'
    return actual


def source_entitlements(declared, effective, info, team):
    env = info['LSEnvironment']
    group = env['APP_GROUP']
    keychain = env['KEYCHAIN_GROUP']
    assert group == 'group.com.datadog.apps-staging'
    identifier = effective.get('application-identifier')
    assert identifier == team + '.' + info['CFBundleIdentifier'], 'Application identity differs'
    assert keychain == team + '.' + group, 'Keychain prefix does not match source team'
    def expand(value):
        if isinstance(value, list):return [expand(v) for v in value]
        if isinstance(value, dict):return {k:expand(v) for k,v in value.items()}
        if isinstance(value, str):
            value=value.replace('$(AppIdentifierPrefix)',team+'.').replace('$(APP_GROUP)',group)
            assert '$(' not in value, 'Unresolved source entitlement'
        return value
    expected=expand(declared)
    # Xcode's iOS simulator packaging omits these macOS-only source entries.
    omitted={'com.apple.security.app-sandbox','com.apple.security.device.audio-input',
             'com.apple.security.network.client','com.apple.security.personal-information.photos-library'}
    assert set(expected)-set(effective) <= omitted, 'Required declared capability missing'
    assert set(effective)-set(expected) == {'application-identifier'}, 'Undeclared effective capability'
    assert all(expected[key] == value for key,value in effective.items() if key in expected), 'Declared capability altered'
    assert effective['keychain-access-groups'] == [keychain]
    assert effective['com.apple.security.application-groups'] == [group]
    return {'application_identifier':identifier,'keychain_group':keychain,'app_group':group}


def signing_link_transition(tokens, derived, *, embedded=True):
    """Remove only Xcode's exact simulator packaging additions for comparison."""
    directory=Path(derived)/'Build/Intermediates.noindex/DatadogApp.build/Debug-iphonesimulator/DatadogApp.build'
    result=[];sections={};no_adhoc=0;index=0
    while index < len(tokens):
        if (tokens[index:index+2] == ['-Xlinker','-sectcreate']
                and tokens[index+5:index+6] in [['__entitlements'],['__ents_der']]):
            row=tokens[index:index+8]
            assert len(row)==8 and row[2:5]==['-Xlinker','__TEXT','-Xlinker'] and row[6]=='-Xlinker'
            section=row[5];assert section in ['__entitlements','__ents_der'] and section not in sections
            expected=directory/('DatadogApp.app-Simulated.xcent'+('.der' if section=='__ents_der' else ''))
            assert Path(row[7])==expected, 'Foreign entitlement input'
            sections[section]=str(expected);index+=8
        elif tokens[index:index+2] == ['-Xlinker','-no_adhoc_codesign']:
            no_adhoc+=1;index+=2
        else:
            result.append(tokens[index]);index+=1
    assert set(sections)==({'__entitlements','__ents_der'} if embedded else set()) and no_adhoc==1, 'Incomplete signing link transition'
    return result,sections


def signing_inventory(files, reference):
    extra=set(files)-set(reference)
    assert set(reference)<=set(files), 'Original product file missing'
    assert extra, 'Signing metadata absent'
    signatures={}
    for name in extra:
        path=Path(name)
        assert path.parent.name=='_CodeSignature', 'Non-signature product addition'
        owner=path.parent.parent
        assert str(owner/'Info.plist') in reference, 'Signature belongs to a new bundle'
        signatures.setdefault(str(owner),set()).add(path.name)
    for names in signatures.values():
        assert names in ({'CodeResources'}, {'CodeDirectory','CodeRequirements','CodeResources','CodeSignature'}), 'Unrecognized signature metadata'
    assert all(files[name]['mode']==old['mode'] for name,old in reference.items()), 'Original file modes changed'
    return sorted(extra)
